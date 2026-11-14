// Test della logica condivisa, portati dai test Swift di ExamsCore.
// Fuso fisso Europa/Roma, come nei test Swift (impostato in test/setup.js).

import './setup.js';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import { iso } from '../src/core/calendar.js';
import { decodeExamList, swiftJSON } from '../src/core/codec.js';
import * as L from '../src/core/logic.js';
import { decodeSnapshot, encodeSnapshot, makeSnapshot, merge, backupsToDelete, backupFileName } from '../src/core/sync.js';
import { ExamStore, BackupError } from '../src/core/store.js';
import { planNotifications, DEFAULT_NOTIFICATION_SETTINGS } from '../src/core/notifications.js';

const date = (y, m, d, h = 12, min = 0) => new Date(y, m - 1, d, h, min);
const exam = (fields) => L.makeExam({ name: 'E', date: date(2026, 1, 10), ...fields });

// MARK: Compatibilità con l'app iOS

test('codifica come JSONEncoder di Swift', () => {
  const text = swiftJSON({ b: [], a: { z: 1, y: 'x/y' }, c: [true], d: null });
  assert.equal(text, '{\n  "a" : {\n    "y" : "x\\/y",\n    "z" : 1\n  },\n  "b" : [\n\n  ],\n  "c" : [\n    true\n  ]\n}');
  assert.equal(swiftJSON({ deletions: {} }), '{\n  "deletions" : {\n\n  }\n}');
});

const syncFile = join(homedir(), 'iCloudDrive', 'Downloads', '0_Uni', '7_ExamsTrack', 'ExamsTrack-sync.json');
test('il file di sync dell\'iPhone si rilegge e riscrive identico', { skip: !existsSync(syncFile) }, () => {
  const original = readFileSync(syncFile, 'utf8');
  assert.equal(encodeSnapshot(decodeSnapshot(original)), original);
});

test('dati vecchi ricevono i valori predefiniti', () => {
  const [decoded] = decodeExamList(JSON.parse(
    '[{"id":"6f9619ff-8b86-d011-b42d-00c04fc964ff","name":"Analisi","date":"2026-11-10T11:00:00Z","tasks":[],"honors":false}]'));
  assert.equal(decoded.cfu, 6);
  assert.equal(decoded.isFinalTest, false);
  assert.equal(decoded.isScheduled, true);
  assert.equal(decoded.id, '6F9619FF-8B86-D011-B42D-00C04FC964FF');
});

// MARK: Unione

const A = '00000000-0000-0000-0000-00000000000A';
const B = '00000000-0000-0000-0000-00000000000B';
const C = '00000000-0000-0000-0000-00000000000C';
const t0 = iso(date(2026, 11, 1, 10));
const t1 = iso(date(2026, 11, 1, 11));
const t2 = iso(date(2026, 11, 1, 12));
const ex = (id, name, modifiedAt) => L.makeExam({ id, name, date: date(2026, 12, 1), modifiedAt });
const names = (snapshot) => snapshot.exams.map((e) => e.name);

test('vince la modifica più recente da entrambi i lati', () => {
  const local = makeSnapshot([ex(A, 'Locale', t2)]);
  const remote = makeSnapshot([ex(A, 'Remoto', t1)]);
  assert.deepEqual(names(merge(local, remote)), ['Locale']);
  assert.deepEqual(names(merge(remote, local)), ['Locale']);
});

test('ordine: locali, poi remoti', () => {
  const local = makeSnapshot([ex(A, 'A', t0), ex(B, 'B', t0)]);
  const remote = makeSnapshot([ex(C, 'C', t1), ex(A, 'A', t0)]);
  assert.deepEqual(names(merge(local, remote)), ['A', 'B', 'C']);
});

test('eliminazioni remote e modifiche successive', () => {
  const merged = merge(makeSnapshot([ex(A, 'A', t0), ex(B, 'B', t0)]), makeSnapshot([ex(B, 'B', t0)], { [A]: t1 }));
  assert.deepEqual(names(merged), ['B']);
  assert.equal(merged.deletions[A], t1);
  assert.deepEqual(names(merge(makeSnapshot([ex(A, 'Dopo', t2)]), makeSnapshot([], { [A]: t1 }))), ['Dopo']);
  assert.deepEqual(merge(makeSnapshot([], { [A]: t0, [B]: t2 }), makeSnapshot([], { [A]: t1 })).deletions, { [A]: t1, [B]: t2 });
});

test('conflitto nello stesso secondo converge', () => {
  const one = makeSnapshot([ex(A, 'iPhone', t1)]);
  const two = makeSnapshot([ex(A, 'PC', t1)]);
  assert.deepEqual(merge(one, two).exams, merge(two, one).exams);
  assert.deepEqual(names(merge(makeSnapshot([ex(A, 'Vecchio', null)]), makeSnapshot([ex(A, 'Nuovo', t0)]))), ['Nuovo']);
});

test('unione idempotente', () => {
  const local = makeSnapshot([ex(A, 'A', t2), ex(B, 'B', t0)], { [C]: t1 });
  const remote = makeSnapshot([ex(A, 'A vecchio', t1), ex(C, 'C', t0)]);
  const merged = merge(local, remote);
  assert.deepEqual(merge(merged, remote), merged);
  assert.deepEqual(merge(merged, merged), merged);
  assert.deepEqual(decodeSnapshot(encodeSnapshot(merged)), merged);
  assert.throws(() => decodeSnapshot('rotto'));
});

test('rotazione dei backup', () => {
  const files = Array.from({ length: 16 }, (_, i) => backupFileName(date(2026, 10, i + 1)));
  assert.deepEqual(backupsToDelete([...files, 'altro.json']), [files[1], files[0]]);
});

// MARK: Store

function memory() {
  const files = new Map();
  return {
    files,
    async readText(name) { return files.has(name) ? files.get(name) : null; },
    async writeTexts(list) { for (const { name, text } of list) files.set(name, text); },
    async rename(from, to) { files.set(to, files.get(from)); files.delete(from); },
    async remove(name) { files.delete(name); },
  };
}

test('store: date di modifica, eliminazioni ricordate, backup', async () => {
  const persistence = memory();
  let now = date(2026, 11, 1, 10);
  const store = await ExamStore.open({ persistence, now: () => now });
  const e = L.makeExam({ name: 'A', date: date(2026, 12, 1, 18) });
  store.addExam(e);
  assert.equal(store.exam(e.id).modifiedAt, iso(date(2026, 11, 1, 10)));
  assert.equal(store.exam(e.id).date, iso(date(2026, 12, 1, 12)));
  assert.equal(store.exam(e.id).colorIndex, 0);

  now = date(2026, 11, 2, 9);
  store.addTask(L.makeTask({ title: 'T', dueDate: date(2026, 12, 20) }), e.id);
  assert.equal(store.exam(e.id).modifiedAt, iso(date(2026, 11, 2, 9)));
  assert.equal(store.exam(e.id).tasks[0].dueDate, iso(date(2026, 12, 1)), 'scadenza non oltre l\'esame');

  store.setOutcome(e.id, true, 31, true);
  assert.equal(store.exam(e.id).grade, 30);
  assert.equal(store.exam(e.id).honors, true);

  now = date(2026, 11, 3, 8);
  store.deleteExam(e.id);
  await store.flush();
  const reopened = await ExamStore.open({ persistence, now: () => now });
  assert.equal(reopened.deletions[e.id], iso(date(2026, 11, 3, 8)));

  const old = L.makeExam({ name: 'Vecchio', date: date(2026, 12, 1) });
  reopened.addExam(old);
  reopened.importBackup(swiftJSON([L.makeExam({ name: 'Nuovo', date: date(2026, 12, 1) })]));
  assert.deepEqual(reopened.exams.map((x) => x.name), ['Nuovo']);
  assert.ok(reopened.deletions[old.id]);
  assert.throws(() => reopened.importBackup('non json'), BackupError);
});

test('store: dati illeggibili spostati in exams.corrupt.json', async () => {
  const persistence = memory();
  persistence.files.set('exams.json', '{rotto');
  const store = await ExamStore.open({ persistence });
  assert.equal(store.lastError, 'corruptedData');
  assert.equal(persistence.files.get('exams.corrupt.json'), '{rotto');
});

// MARK: Carriera

const passed = (grade, cfu, extra = {}) => exam({ passed: true, grade, cfu, ...extra });
const close = (a, b) => assert.ok(Math.abs(a - b) < 0.0001, `${a} ≠ ${b}`);

test('media pesata e voto di laurea triennale', () => {
  close(L.weightedAverage([passed(28, 6), passed(30, 12)], 'triennale'), 528 / 18);
  close(L.graduationEstimate([passed(18, 171), passed(18, 9, { isFinalTest: true })]).minimum, 70);
  close(L.graduationEstimate([passed(30, 171), passed(30, 9, { isFinalTest: true })]).maximum, 116);
  const e = L.graduationEstimate([passed(30, 12)]);
  close(e.minimum, ((30 * 12 + 18 * 168) / 180) * 110 / 30 + 4);
  close(e.maximum, 116);
  assert.equal(L.missingGraduationCFU([passed(30, 12), passed(24, 6)]), 162);
  assert.equal(L.graduationEstimate([]), null);
});

test('voto di laurea magistrale', () => {
  const m = (grade, cfu, honors = false) => passed(grade, cfu, { degree: 'magistrale', honors });
  const full = L.masterGraduationEstimate([m(27, 100)], 'withReviewer');
  close(full.minimum, 98);
  close(full.maximum, 106);
  close(L.masterGraduationEstimate([m(27, 100)], 'withoutReviewer').maximum, 103);
  const half = L.masterGraduationEstimate([m(30, 50)], 'withReviewer');
  close(half.minimum, 87);
  close(half.maximum, 117);
  assert.equal(L.masterGraduationEstimate([m(18, 100)], 'withReviewer').minimum, 66);
  const honors = [...Array.from({ length: 6 }, () => m(30, 10, true)), m(30, 40)];
  assert.equal(L.masterGraduationEstimate(honors, 'withReviewer').honorsThreshold, 111);
  assert.equal(L.gradeText({ minimum: 97.6, maximum: 110.6 }), '98–110+');
});

test('simulazione e andamento', () => {
  const exams = [passed(24, 6), exam({ cfu: 6, simulatedGrade: 30 })];
  close(L.simulatedAverage(exams, 'triennale'), 27);
  assert.equal(L.simulatedAverage([passed(24, 6)], 'triennale'), null);
  assert.deepEqual(L.averageTrend(exams, 'triennale').map((p) => p.average), [24]);
});

// MARK: Piano di studio e oggi

test('piano di studio e ripianificazione', () => {
  const tasks = L.planStudy(['A', 'B', ' ', 'C'], date(2026, 11, 1), date(2026, 11, 11), 2);
  // 8 giorni di studio (1–8 novembre), ripasso il 10.
  assert.deepEqual(tasks.map((t) => [t.title, new Date(t.dueDate).getDate()]),
    [['A', 3], ['B', 6], ['C', 8], [L.REVIEW_TITLE, 10]]);

  const today = date(2026, 11, 10);
  const e = exam({ date: date(2026, 11, 14), tasks: [
    L.makeTask({ title: '1', dueDate: date(2026, 11, 5) }),
    L.makeTask({ title: '2', dueDate: date(2026, 11, 6) }),
    L.makeTask({ title: '3', dueDate: date(2026, 11, 7), isDone: true }),
  ] });
  const moved = L.rescheduleOverdue(e, today).map((t) => new Date(t.dueDate).getDate());
  assert.deepEqual(moved, [10, 12, 7]);
});

test('countdown preciso e prossimo esame', () => {
  const e = exam({ date: date(2026, 11, 12), startTime: 14 * 60 + 30 });
  assert.deepEqual(L.preciseCountdown(e, date(2026, 11, 1, 10)),
    { kind: 'remaining', value: 11, unit: 'giorni', detail: 'e 4 ore' });
  assert.deepEqual(L.preciseCountdown(e, date(2026, 11, 12, 14, 0)), { kind: 'remaining', value: 30, unit: 'minuti', detail: null });
  assert.deepEqual(L.preciseCountdown(e, date(2026, 11, 12, 15)), { kind: 'started' });
  const later = exam({ name: 'Dopo', date: date(2026, 12, 1) });
  const unscheduled = exam({ name: 'Senza data', isScheduled: false });
  assert.equal(L.nextExam([later, unscheduled, e], date(2026, 11, 1)).id, e.id);
  assert.deepEqual(L.active([unscheduled, later, e], date(2026, 11, 1)).map((x) => x.name), ['E', 'Dopo', 'Senza data']);
});

test('ricerca senza accenti e maiuscole', () => {
  const e = exam({ name: 'Fisica', notes: 'Università' });
  assert.equal(L.matching([e], 'UNIVERSITA fis').length, 1);
  assert.equal(L.matching([e], 'chimica').length, 0);
});

test('notifiche: promemoria e riepilogo task', () => {
  const e = exam({ name: 'Analisi', date: date(2026, 11, 20), startTime: 9 * 60 + 30,
    tasks: [L.makeTask({ title: 'Limiti', dueDate: date(2026, 11, 15) })] });
  const plan = planNotifications([e], DEFAULT_NOTIFICATION_SETTINGS, date(2026, 11, 1, 8));
  assert.deepEqual(plan.map((p) => [p.body, p.fireDate.getDate(), p.fireDate.getHours(), p.fireDate.getMinutes()]), [
    ['Esame tra 7 giorni', 13, 9, 0],
    ['Limiti (Analisi)', 15, 9, 0],
    ['Esame domani', 19, 9, 0],
    ['Esame oggi: in bocca al lupo!', 20, 8, 30],
  ]);
});

// MARK: Sotto-task (come SubtaskTests in ExamsCore)

test('sotto-task: si leggono e si riscrivono come l\'app iOS, e mancano nei dati vecchi', () => {
  const swift = '[\n  {\n    "dueDate" : "2026-11-12T11:00:00Z",\n    "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",\n    "isDone" : false,\n    "subtasks" : [\n      {\n        "id" : "7F9619FF-8B86-D011-B42D-00C04FC964FF",\n        "isDone" : true,\n        "title" : "Teoria"\n      }\n    ],\n    "title" : "Capitolo 4"\n  }\n]';
  const [task] = decodeExamList([{ id: '6f9619ff-8b86-d011-b42d-00c04fc964ff', name: 'A', date: '2026-11-20T11:00:00Z', honors: false,
    tasks: JSON.parse(swift) }])[0].tasks;
  assert.equal(swiftJSON([task]), swift);
  const [old] = decodeExamList([{ id: '6f9619ff-8b86-d011-b42d-00c04fc964ff', name: 'A', date: '2026-11-20T11:00:00Z', honors: false,
    tasks: [{ id: '6f9619ff-8b86-d011-b42d-00c04fc964ff', title: 'T', dueDate: '2026-11-12T11:00:00Z', isDone: true }] }])[0].tasks;
  assert.deepEqual(old.subtasks, []);
  // Come in Swift, si scrivono sempre: anche vuoti.
  assert.match(swiftJSON(old), /"subtasks" : \[\n\n  \]/);
});

test('sotto-task: avanzamento parziale, completamento e riapertura', async () => {
  const store = await ExamStore.open({ persistence: memory() });
  const subtasks = ['Teoria', 'Esercizi', 'Formulario'].map((title) => L.makeSubtask({ title }));
  const task = L.makeTask({ title: 'Capitolo 4', dueDate: date(2026, 11, 12), subtasks });
  store.addExam(exam({ date: date(2026, 11, 20), tasks: [task, L.makeTask({ title: 'Altro', dueDate: date(2026, 11, 13) })] }));
  const id = store.exams[0].id;

  store.toggleSubtask(subtasks[0].id, task.id, id);
  assert.equal(L.subtaskLabel(store.exam(id).tasks[0]), '1/3');
  assert.ok(Math.abs(L.progress(store.exam(id)) - 1 / 6) < 1e-9);

  for (const sub of subtasks.slice(1)) store.toggleSubtask(sub.id, task.id, id);
  assert.equal(store.exam(id).tasks[0].isDone, true);
  store.toggleSubtask(subtasks[1].id, task.id, id);
  assert.equal(store.exam(id).tasks[0].isDone, false);

  store.toggleTask(task.id, id);
  assert.ok(store.exam(id).tasks[0].subtasks.every((sub) => sub.isDone));
  store.toggleTask(task.id, id);
  assert.ok(store.exam(id).tasks[0].subtasks.every((sub) => !sub.isDone));
});

// MARK: "Oggi" su tutti gli esami (come TodayBoardTests e TodayWeekTests)

test('oggi: agenda di tutti gli esami, settimana e più avanti', () => {
  const today = date(2026, 11, 10, 15);
  const exams = [
    exam({ name: 'Analisi', date: date(2026, 11, 20), tasks: [
      L.makeTask({ title: 'Oggi A', dueDate: date(2026, 11, 10) }),
      L.makeTask({ title: 'Ritardo A', dueDate: date(2026, 11, 8) }),
      L.makeTask({ title: 'Fatto oggi A', dueDate: date(2026, 11, 10), isDone: true }),
      L.makeTask({ title: 'Domani A', dueDate: date(2026, 11, 11) }),
      L.makeTask({ title: 'Dopo A', dueDate: date(2026, 11, 15) }),
    ] }),
    exam({ name: 'Fisica', date: date(2026, 12, 1), tasks: [
      L.makeTask({ title: 'Oggi F', dueDate: date(2026, 11, 10) }),
      L.makeTask({ title: 'Futuro F', dueDate: date(2026, 11, 25) }),
    ] }),
    exam({ name: 'Senza data', date: date(2026, 1, 1), isScheduled: false, tasks: [
      L.makeTask({ title: 'Ritardo S', dueDate: date(2026, 11, 1) }),
    ] }),
  ];
  const board = L.todayBoard(exams, today);
  assert.equal(board.next.name, 'Analisi');
  assert.deepEqual(board.agenda.overdue.map((i) => i.task.title), ['Ritardo S', 'Ritardo A']);
  assert.deepEqual(board.agenda.dueToday.map((i) => i.task.title), ['Oggi A', 'Oggi F', 'Fatto oggi A']);
  assert.equal(board.agenda.days.length, 7);
  assert.deepEqual(board.agenda.days.flatMap((d) => d.items).map((i) => i.task.title), ['Domani A', 'Dopo A']);
  assert.deepEqual(board.agenda.later.map((i) => i.task.title), ['Futuro F']);
  assert.deepEqual(board.others.map((e) => e.name), ['Fisica', 'Senza data']);

  const suggestion = L.studySuggestion(exams, today);
  assert.equal(suggestion.taskTitle, 'Ritardo S');
});

// MARK: Widget sul desktop

import { widgetSummary, widgetExamChoices } from '../src/core/widget.js';

test('il widget mostra il prossimo esame, o quello scelto se è ancora da sostenere', () => {
  const today = date(2026, 1, 5);
  const first = exam({ name: 'Analisi', date: date(2026, 1, 10), colorIndex: 2 });
  const second = exam({ name: 'Fisica', date: date(2026, 1, 20) });
  const past = exam({ name: 'Chimica', date: date(2026, 1, 1) });
  const unscheduled = exam({ name: 'Geometria', isScheduled: false });
  const exams = [second, past, first, unscheduled];

  const next = widgetSummary(exams, today);
  assert.equal(next.name, 'Analisi');
  assert.equal(next.daysRemaining, 5);
  assert.equal(next.colorIndex, 2);
  assert.deepEqual(next.followingExams.map((e) => e.name), ['Fisica']);

  assert.equal(widgetSummary(exams, today, { focusedExamID: second.id }).name, 'Fisica');
  // Già sostenuto o senza data: si torna al prossimo esame.
  assert.equal(widgetSummary(exams, today, { focusedExamID: past.id }).name, 'Analisi');
  assert.equal(widgetSummary(exams, today, { focusedExamID: unscheduled.id }).name, 'Analisi');
  assert.equal(widgetSummary([past, unscheduled], today), null);
  assert.deepEqual(widgetExamChoices(exams, today).map((e) => e.name), ['Analisi', 'Fisica']);
});

test('i task del widget: solo dell\'esame mostrato o di tutti, per scadenza, con quelli appena spuntati', () => {
  const today = date(2026, 1, 5);
  const late = L.makeTask({ title: 'Ripasso', dueDate: date(2026, 1, 3) });
  const done = L.makeTask({ title: 'Fatto', dueDate: date(2026, 1, 4), isDone: true });
  const later = L.makeTask({ title: 'Esercizi', dueDate: date(2026, 1, 8) });
  const other = L.makeTask({ title: 'Formule', dueDate: date(2026, 1, 6) });
  const first = exam({ name: 'Analisi', date: date(2026, 1, 10), tasks: [later, done, late] });
  const second = exam({ name: 'Fisica', date: date(2026, 1, 20), tasks: [other] });

  const own = widgetSummary([first, second], today);
  assert.deepEqual(own.upcomingTasks.map((t) => t.title), ['Ripasso', 'Esercizi']);
  assert.equal(own.upcomingTasks[0].isOverdue, true);
  assert.equal(own.completedTasks, 1);
  assert.equal(own.totalTasks, 3);

  const all = widgetSummary([first, second], today, { tasksFromAllExams: true, recentlyCompleted: new Set([done.id]) });
  assert.deepEqual(all.upcomingTasks.map((t) => t.title), ['Ripasso', 'Fatto', 'Formule', 'Esercizi']);
  assert.equal(all.upcomingTasks[1].isDone, true);
  assert.equal(all.upcomingTasks[2].examName, 'Fisica');
});
