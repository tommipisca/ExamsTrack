// Avvio della finestra: stato dell'interfaccia, disegno delle schede, azioni e sincronizzazione.

import * as L from '../core/logic.js';
import { addDays, dayDiff, dayKey, fromDayKey, iso, isoOf, noon, startOfDay } from '../core/calendar.js';
import { ExamStore, STORE_ERRORS, BackupError } from '../core/store.js';
import { widgetSummary, WIDGET_RECENT_MS } from '../core/widget.js';
import { prefs, makePersistence, SyncService, Notifier } from './services.js';
import { TABS, todayView, examsView, careerView, settingsView, careerDegree, studyRemaining } from './views.js';
import { renderModal, examFormModal, taskFormModal, plannerModal, plannerPreview, isFinalTestOf, quickTaskModal, studyModal, minutesLabel } from './modals.js';
import { attachChartHover } from './chart.js';
import { esc } from './components.js';
import { icon } from './icons.js';

const api = window.api;
const view = document.getElementById('view');
const rail = document.getElementById('rail');
const modalRoot = document.getElementById('modal-root');
const menuRoot = document.getElementById('menu-root');

let store;
let sync;
let desktop = null;
/** Stato degli aggiornamenti, inviato dal processo principale (vedi updater.cjs). */
let update = null;
let today = new Date();
let now = new Date();

const ui = {
  tab: prefs.get('startTab'),
  examsSelected: null,
  examsQuery: '',
  careerSelection: 'overview',
  careerQuery: '',
  /** Corso mostrato in Carriera: la preferenza vale solo alla prima apertura dopo l'avvio. */
  careerDegree: null,
  dropTarget: null,
  /** Sessione di studio in corso (o appena finita): sopravvive alla chiusura della finestra. */
  study: prefs.get('studySession'),
};
/** Finestre aperte, l'ultima in primo piano. */
const modals = [];

const visibility = () => prefs.get('degreeVisibility');
const context = () => ({ store, today, now, ui, prefs, sync, desktop, update, visibility: visibility(), study: ui.study });

// MARK: Disegno

function render() {
  if (!store) return;
  // Selezioni che non esistono più (eliminate qui o su un altro dispositivo).
  if (ui.examsSelected && !store.exam(ui.examsSelected)) ui.examsSelected = null;
  if (ui.careerSelection !== 'overview' && !store.exam(ui.careerSelection)) ui.careerSelection = 'overview';

  const scrolls = new Map([...view.querySelectorAll('[data-scroll]')].map((el) => [el.dataset.scroll, el.scrollTop]));
  const focus = captureFocus(view);
  const ctx = context();
  const screens = { today: todayView, exams: examsView, career: careerView, settings: settingsView };
  view.innerHTML = (screens[ui.tab] ?? todayView)(ctx);
  for (const el of view.querySelectorAll('[data-scroll]')) {
    if (scrolls.has(el.dataset.scroll)) el.scrollTop = scrolls.get(el.dataset.scroll);
  }
  restoreFocus(view, focus);
  attachChartHover(view);
  renderRail();
  pushWidget();
}

function renderRail() {
  const syncState = !sync?.isEnabled ? '' : sync.isSyncing
    ? `<span class="sync-state syncing" title="Sincronizzazione in corso">${icon('sync')}</span>`
    : sync.errorMessage
      ? `<button class="sync-state error" data-action="tab" data-value="settings" title="${esc(sync.errorMessage)}">${icon('alert')}</button>`
      : `<button class="sync-state" data-action="sync-now" title="Sincronizzato. Clic per sincronizzare ora (F5)">${icon('cloud')}</button>`;
  rail.innerHTML = `<div class="rail-logo"><img src="../../build/icon.png" alt=""></div>
    ${Object.entries(TABS).map(([key, tab], index) => `<button class="rail-item${ui.tab === key ? ' selected' : ''}" data-action="tab" data-value="${key}" title="${tab.title} (Ctrl+${index + 1})">
      ${icon(tab.icon)}<span>${tab.title}</span></button>`).join('')}
    <div class="rail-spacer"></div>${syncState}`;
}

function renderModals() {
  const focus = captureFocus(modalRoot);
  const ctx = context();
  modalRoot.innerHTML = modals.map((modal, index) =>
    `<div class="backdrop${index === modals.length - 1 ? ' top' : ''}">${renderModal(modal, ctx)}</div>`).join('');
  if (!restoreFocus(modalRoot, focus)) {
    modalRoot.querySelector('.backdrop.top #modal-first')?.focus();
  }
}

function captureFocus(root) {
  const active = document.activeElement;
  if (!active || !root.contains(active) || !active.id) return null;
  return { id: active.id, start: active.selectionStart, end: active.selectionEnd };
}

function restoreFocus(root, focus) {
  if (!focus) return false;
  const el = root.querySelector(`#${focus.id}`);
  if (!el) return false;
  el.focus();
  try {
    if (focus.start !== null && focus.start !== undefined) el.setSelectionRange(focus.start, focus.end);
  } catch {
    // Campi senza selezione (date).
  }
  return true;
}

function openModal(modal) {
  closeMenu();
  modals.push(modal);
  renderModals();
}

function closeModal() {
  modals.pop();
  renderModals();
}

function alertModal(title, message) {
  openModal({ type: 'alert', title, message });
}

function confirmModal(title, message, confirmLabel, onConfirm, destructive = true) {
  openModal({ type: 'confirm', title, message, confirmLabel, onConfirm, destructive });
}

// MARK: Menu contestuale

function closeMenu() {
  menuRoot.innerHTML = '';
}

function showMenu(event, items) {
  event.preventDefault();
  menuRoot.innerHTML = `<div class="menu">${items.map((item, index) => (item === '-'
    ? '<div class="menu-divider"></div>'
    : `<button class="menu-item${item.destructive ? ' danger' : ''}" data-menu="${index}">${icon(item.icon)} ${esc(item.label)}</button>`)).join('')}</div>`;
  const menu = menuRoot.firstElementChild;
  const x = Math.min(event.clientX, window.innerWidth - menu.offsetWidth - 8);
  const y = Math.min(event.clientY, window.innerHeight - menu.offsetHeight - 8);
  menu.style.left = `${x}px`;
  menu.style.top = `${y}px`;
  menu.onclick = (click) => {
    const button = click.target.closest('[data-menu]');
    if (!button) return;
    closeMenu();
    items[Number(button.dataset.menu)].run();
  };
}

function taskMenu(event, examID, taskID) {
  const exam = store.exam(examID);
  const task = exam?.tasks.find((item) => item.id === taskID);
  if (!task) return;
  const tomorrow = addDays(startOfDay(today), 1);
  // Solo per task che scadono prima di domani, e se domani non è dopo l'esame.
  const canMove = dayDiff(task.dueDate, tomorrow) > 0 && (!exam.isScheduled || dayDiff(tomorrow, exam.date) >= 0);
  showMenu(event, [
    { label: task.isDone ? 'Segna da fare' : 'Segna come fatto', icon: 'check', run: () => store.toggleTask(taskID, examID) },
    ...(canMove ? [{ label: 'Sposta a domani', icon: 'arrow', run: () => store.moveTask(taskID, examID, noon(tomorrow)) }] : []),
    { label: 'Modifica', icon: 'pencil', run: () => openModal(taskFormModal(exam, task)) },
    ...(task.isDone ? [] : ['-', ...studyItems(studyTarget(exam, task))]),
    '-',
    { label: 'Elimina', icon: 'trash', destructive: true, run: () => store.deleteTask(taskID, examID) },
  ]);
}

// MARK: Sessione di studio

function studyTarget(exam, task = null) {
  return { examID: exam.id, examName: exam.name, colorIndex: exam.colorIndex ?? 0, taskID: task?.id ?? null, taskTitle: task?.title ?? null };
}

/** Le durate fisse, l'ultima usata e "Altra durata…". */
function studyItems(target) {
  const last = prefs.get('studyLastMinutes');
  const durations = L.STUDY_DURATIONS.includes(last) ? L.STUDY_DURATIONS : [...L.STUDY_DURATIONS, last].sort((a, b) => a - b);
  return [
    ...durations.map((minutes) => ({ label: `Studia ${minutesLabel(minutes)}`, icon: 'timer', run: () => startStudy(target, minutes) })),
    { label: 'Studia… altra durata', icon: 'timer', run: () => openModal(studyModal(target, last)) },
  ];
}

function startStudy(target, minutes) {
  const clamped = Math.min(Math.max(Number(minutes), L.STUDY_RANGE.min), L.STUDY_RANGE.max);
  ui.study = { ...target, end: iso(new Date(Date.now() + clamped * 60_000)), minutes: clamped, notified: false };
  prefs.set('studySession', ui.study);
  prefs.set('studyLastMinutes', clamped);
  ui.tab = 'today';
  render();
}

function stopStudy() {
  ui.study = null;
  prefs.set('studySession', null);
  render();
}

/** Ogni secondo: il timer della sessione e, alla fine, la notifica di Windows. */
function studyTick() {
  if (!ui.study) return;
  const current = new Date();
  for (const el of view.querySelectorAll('[data-study-end]')) el.textContent = studyRemaining(el.dataset.studyEnd, current);
  if (!ui.study.notified && current >= new Date(ui.study.end)) {
    ui.study = { ...ui.study, notified: true };
    prefs.set('studySession', ui.study);
    const what = ui.study.taskTitle ? `«${ui.study.taskTitle}» (${ui.study.examName})` : ui.study.examName;
    api.notify('Sessione finita', `${minutesLabel(ui.study.minutes)} su ${what}. Hai finito, o ti serve ancora un po'?`);
    now = current;
    render();
  }
}

function examMenu(event, examID) {
  const exam = store.exam(examID);
  if (!exam) return;
  showMenu(event, [
    { label: 'Apri', icon: 'chevron', run: () => openExam(examID) },
    { label: 'Modifica', icon: 'pencil', run: () => openModal(examFormModal(store, exam, visibility())) },
    '-',
    { label: 'Elimina', icon: 'trash', destructive: true, run: () => confirmDeleteExam(examID) },
  ]);
}

// MARK: Azioni

function openExam(examID) {
  const exam = store.exam(examID);
  if (!exam) return;
  if (ui.tab === 'career' && !L.isActive(exam, today)) {
    ui.careerSelection = examID;
  } else {
    ui.tab = 'exams';
    ui.examsSelected = examID;
  }
  render();
}

function confirmDeleteExam(examID) {
  const exam = store.exam(examID);
  if (!exam) return;
  confirmModal("Eliminare l'esame?", 'Verranno eliminati anche tutti i suoi task.', `Elimina ${exam.name}`, () => store.deleteExam(examID));
}

function newExam() {
  openModal(examFormModal(store, null, visibility()));
}

function focusSearch() {
  if (ui.tab !== 'exams' && ui.tab !== 'career') {
    ui.tab = 'exams';
    render();
  }
  view.querySelector('input[type=search]')?.focus();
}

async function importBackup() {
  const file = await api.openBackup();
  if (!file) return;
  confirmModal('Sostituire tutti i dati con il backup?', 'Esami, task e voti attuali verranno sostituiti da quelli del file, anche su iPhone e iPad.', 'Sostituisci i dati', async () => {
    try {
      // Prima prende gli esami creati sugli altri dispositivi: così il ripristino elimina anche quelli.
      await sync.sync(store);
      store.importBackup(file.text);
      await sync.sync(store);
      alertModal('Backup', `Backup importato: ${store.exams.length} esami ripristinati.`);
    } catch (error) {
      alertModal('Backup', error instanceof BackupError ? error.message : new BackupError().message);
    }
  });
}

function updateNotificationSettings(change) {
  const settings = prefs.get('notificationSettings');
  change(settings);
  prefs.set('notificationSettings', settings);
  render();
}

/** Tesi magistrale: propone 20 CFU se sono ancora quelli di default. */
function proposeThesisCFU(modal) {
  if (modal.degree === 'magistrale' && isFinalTestOf(modal) && modal.cfu === L.DEFAULT_CFU) modal.cfu = L.THESIS_CFU;
}

const actions = {
  'tab': ({ value }) => {
    ui.tab = value;
    if (value === 'career' && ui.careerDegree === null) ui.careerDegree = careerDegree(context());
    render();
  },
  'new-exam': newExam,
  'open-exam': ({ exam }) => openExam(exam),
  'select-exam': ({ exam }) => {
    ui.examsSelected = exam;
    render();
  },
  'edit-exam': ({ exam }) => openModal(examFormModal(store, store.exam(exam), visibility())),
  'delete-exam': ({ exam }) => confirmDeleteExam(exam),
  'toggle-task': ({ exam, task }) => store.toggleTask(task, exam),
  'toggle-subtask': ({ exam, task, sub }) => store.toggleSubtask(sub, task, exam),
  'quick-task': () => openModal(quickTaskModal(L.active(L.visible(store.exams, visibility()), today), today)),
  'study-menu': (_, event) => {
    const suggestion = L.studySuggestion(L.visible(store.exams, visibility()), today);
    if (suggestion) showMenu(event, studyItems(suggestion));
  },
  'study-stop': stopStudy,
  'study-done': () => {
    if (ui.study?.taskID) store.setTaskDone(ui.study.taskID, ui.study.examID);
    stopStudy();
  },
  'study-more': () => {
    const { examID, examName, colorIndex, taskID, taskTitle } = ui.study ?? {};
    if (examID) startStudy({ examID, examName, colorIndex, taskID, taskTitle }, L.STUDY_EXTRA_MINUTES);
  },
  'edit-task': ({ exam, task }) => {
    const item = store.exam(exam);
    openModal(taskFormModal(item, item.tasks.find((t) => t.id === task)));
  },
  'new-task': ({ exam }) => openModal(taskFormModal(store.exam(exam), null)),
  'delete-task': ({ exam, task }) => store.deleteTask(task, exam),
  'reschedule': ({ exams }) => {
    for (const id of exams.split(',')) store.rescheduleOverdue(id, today);
  },
  'edit-notes': ({ exam }) => openModal({ type: 'notes', examID: exam, text: store.exam(exam).notes }),
  'plan-study': ({ exam }) => openModal(plannerModal(store.exam(exam))),
  'outcome': ({ exam, value }) => {
    const item = store.exam(exam);
    store.setOutcome(exam, value === 'none' ? null : value === 'passed', item.grade, item.honors);
  },
  'thesis-points': ({ exam, delta }) => store.setThesisPoints(exam, (store.exam(exam).thesisPoints ?? 0) + Number(delta)),
  'career-degree': ({ value }) => {
    ui.careerDegree = value;
    ui.careerSelection = 'overview';
    render();
  },
  'career-overview': () => {
    ui.careerSelection = 'overview';
    render();
  },
  'career-exam': ({ exam }) => {
    ui.careerSelection = exam;
    render();
  },
  'open-simulation': () => openModal({ type: 'simulation', degree: careerDegree(context()) }),
  'clear-simulation': ({ value }) => store.clearSimulation(value),
  'sync-now': () => sync.sync(store),
  'open-sync-folder': () => api.openFolder(sync.folder),
  'unlink-sync': () => confirmModal('Scollegare la cartella?', 'I dati restano su questo PC, ma non si sincronizzano più con iPhone e iPad.', 'Scollega', () => sync.unlink()),
  'link-suggested': () => {
    sync.link(sync.suggestedFolder);
    sync.sync(store);
  },
  'choose-sync-folder': async () => {
    const folder = await api.chooseFolder();
    if (!folder) return;
    sync.link(folder);
    sync.sync(store);
  },
  'remove-reminder': ({ value }) => updateNotificationSettings((settings) => {
    settings.examReminders = settings.examReminders.filter((key) => key !== value);
  }),
  'export-backup': async () => {
    try {
      if (await api.saveBackup(backupName(), store.exportBackup())) alertModal('Backup', 'Backup esportato.');
    } catch {
      alertModal('Backup', 'Impossibile creare il backup.');
    }
  },
  'import-backup': importBackup,
  'open-data-folder': () => api.openFolder(desktop.dataDir),
  'check-update': () => api.update.check(),
  'install-update': () => api.update.install(),
  'open-release-page': () => api.update.openReleasePage(),

  // Finestre
  'modal-cancel': closeModal,
  'modal-confirm': confirmTopModal,
  'modal-step': ({ field, delta, min, max }) => {
    const modal = modals.at(-1);
    modal[field] = Math.min(Math.max(modal[field] + Number(delta), Number(min)), Number(max));
    renderModals();
  },
  'modal-add-subtask': () => {
    const modal = modals.at(-1);
    // Una sola voce vuota alla volta.
    if (!modal.subtasks.some((sub) => !sub.title.trim())) modal.subtasks.push(L.makeSubtask({ title: '' }));
    renderModals();
    modalRoot.querySelector(`[data-subtask="${modal.subtasks.findIndex((sub) => !sub.title.trim())}"]`)?.focus();
  },
  'modal-remove-subtask': ({ index }) => {
    modals.at(-1).subtasks.splice(Number(index), 1);
    renderModals();
  },
  'modal-toggle-subtask': ({ index }) => {
    const sub = modals.at(-1).subtasks[Number(index)];
    sub.isDone = !sub.isDone;
    renderModals();
  },
  'modal-degree': ({ value }) => {
    const modal = modals.at(-1);
    modal.degree = value;
    proposeThesisCFU(modal);
    renderModals();
  },
};

function backupName() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `ExamsTrack-backup-${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const changes = {
  'grade': ({ exam }, el) => store.setOutcome(exam, true, Number(el.value), store.exam(exam).honors),
  'honors': ({ exam }, el) => store.setOutcome(exam, true, store.exam(exam).grade, el.checked),
  'career-sort': (_, el) => {
    prefs.set('careerSort', el.value);
    render();
  },
  'start-tab': (_, el) => prefs.set('startTab', el.value),
  'visibility': (_, el) => {
    prefs.set('degreeVisibility', el.value);
    ui.careerDegree = null;
    ui.careerSelection = 'overview';
    render();
  },
  'career-filter': (_, el) => prefs.set('careerFilter', el.value),
  'thesis-type': (_, el) => {
    prefs.set('thesisType', el.value);
    render();
  },
  'add-reminder': (_, el) => {
    if (!el.value) return;
    const value = el.value;
    updateNotificationSettings((settings) => settings.examReminders.push(value));
  },
  'daily-summary': (_, el) => updateNotificationSettings((settings) => {
    settings.dailyTaskSummary = el.checked;
  }),
  'notification-time': (_, el) => {
    const [hour, minute] = el.value.split(':').map(Number);
    if (Number.isNaN(hour)) return;
    updateNotificationSettings((settings) => {
      settings.hour = hour;
      settings.minute = minute;
    });
  },
  'close-to-tray': async (_, el) => {
    await api.setCloseToTray(el.checked);
    desktop = await api.getDesktopSettings();
  },
  'auto-update': async (_, el) => {
    await api.setAutoUpdate(el.checked);
    desktop = await api.getDesktopSettings();
  },
  'widget-enabled': (_, el) => setWidgetConfig({ enabled: el.checked }),
  'widget-exam': (_, el) => setWidgetConfig({ examID: el.value || null }),
  'widget-size': (_, el) => setWidgetConfig({ size: el.value }),
  'widget-locked': (_, el) => setWidgetConfig({ locked: el.checked }),
  'widget-other-tasks': (_, el) => setWidgetConfig({ includeOtherExams: el.checked }),
  'open-at-login': async (_, el) => {
    await api.setOpenAtLogin(el.checked);
    desktop = await api.getDesktopSettings();
    render();
  },
  'simulated-grade': ({ exam }, el) => store.setSimulatedGrade(exam, el.value ? Number(el.value) : null),
};

function confirmTopModal() {
  const modal = modals.at(-1);
  if (!modal) return;
  switch (modal.type) {
    case 'exam': return saveExamForm(modal);
    case 'task': return saveTaskForm(modal);
    case 'quick-task': return saveTaskForm(modal);
    case 'study':
      closeModal();
      startStudy(modal.target, Number(modal.minutes));
      return;
    case 'notes':
      store.setNotes(modal.examID, modal.text);
      break;
    case 'planner': {
      if (!modal.topics.split(/\r?\n/).some((topic) => topic.trim())) return;
      store.addTasks(plannerPreview(modal), modal.examID);
      break;
    }
    case 'confirm':
      closeModal();
      modal.onConfirm();
      return;
    default:
      break;
  }
  if (!store.lastError) closeModal();
}

function saveExamForm(modal) {
  const name = modal.name.trim();
  if (!name || (modal.isScheduled && !modal.day)) return;
  const [h, m] = modal.time.split(':').map(Number);
  const startTime = modal.isScheduled && modal.hasStartTime && !Number.isNaN(h) ? h * 60 + (m || 0) : null;
  const edited = {
    name,
    date: isoOf(fromDayKey(modal.day || dayKey(new Date()))),
    degree: modal.degree,
    cfu: modal.cfu,
    isFinalTest: isFinalTestOf(modal),
    isScheduled: modal.isScheduled,
    startTime,
  };
  if (modal.examID) {
    // L'esame potrebbe essere stato eliminato su un altro dispositivo mentre il form era aperto.
    const latest = store.exam(modal.examID);
    if (!latest) {
      closeModal();
      alertModal('Esame eliminato', 'Questo esame è stato eliminato su un altro dispositivo: le modifiche non sono state salvate.');
      return;
    }
    // Solo i campi cambiati qui: le modifiche arrivate intanto dall'altro dispositivo restano.
    store.updateExamDetails(modal.examID, L.mergeDetails(modal.original, edited, L.examDetails(latest)));
  } else {
    const exam = L.makeExam({ ...edited, colorIndex: modal.colorIndex });
    store.addExam(exam);
    ui.tab = 'exams';
    ui.examsSelected = exam.id;
    render();
  }
  if (!store.lastError) closeModal();
}

function saveTaskForm(modal) {
  const title = modal.title.trim();
  if (!title || !modal.due) return;
  const exam = store.exam(modal.examID);
  if (!exam) return closeModal();
  let due = modal.due;
  const max = exam.isScheduled ? dayKey(exam.date) : null;
  if (max && due > max) due = max;
  const dueDate = fromDayKey(due);
  const subtasks = (modal.subtasks ?? []).map((sub) => ({ ...sub, title: sub.title.trim() })).filter((sub) => sub.title);
  if (modal.taskID) {
    const task = exam.tasks.find((item) => item.id === modal.taskID);
    if (task) store.updateTask({ ...task, title, dueDate: isoOf(dueDate), subtasks }, modal.examID);
  } else {
    store.addTask(L.makeTask({ title, dueDate, subtasks }), modal.examID);
  }
  if (!store.lastError) closeModal();
}

// MARK: Widget sul desktop

/** Task spuntati dal widget (id → fine), mostrati ancora barrati per qualche secondo come su iOS. */
const widgetRecents = new Map();
let widgetSent = '';

/** Calcola cosa mostra il widget e lo invia, solo se è cambiato (vedi widget.cjs). */
function pushWidget() {
  if (!store || !desktop?.widget) return;
  const current = Date.now();
  for (const [id, until] of widgetRecents) if (until <= current) widgetRecents.delete(id);
  const summary = widgetSummary(L.visible(store.exams, visibility()), new Date(current), {
    focusedExamID: desktop.widget.examID,
    tasksFromAllExams: desktop.widget.includeOtherExams,
    recentlyCompleted: new Set(widgetRecents.keys()),
  });
  const data = { summary, showDegree: visibility() === 'both' };
  const text = JSON.stringify(data);
  if (text === widgetSent) return;
  widgetSent = text;
  api.widget.update(data);
}

function toggleFromWidget({ examID, taskID }) {
  const task = store?.exam(examID)?.tasks.find((item) => item.id === taskID);
  if (!task) return;
  if (task.isDone) {
    widgetRecents.delete(taskID);
  } else {
    widgetRecents.set(taskID, Date.now() + WIDGET_RECENT_MS);
    setTimeout(pushWidget, WIDGET_RECENT_MS + 50);
  }
  store.toggleTask(taskID, examID);
}

function openFromWidget(target) {
  closeMenu();
  if (target?.examID && store?.exam(target.examID)) {
    ui.tab = 'exams';
    ui.examsSelected = target.examID;
    render();
  } else if (target?.tab) {
    actions.tab({ value: target.tab });
  }
}

async function setWidgetConfig(change) {
  await api.widget.setConfig(change);
  desktop = await api.getDesktopSettings();
  render();
}

// MARK: Eventi

document.addEventListener('click', (event) => {
  if (!event.target.closest('.menu')) closeMenu();
  const target = event.target.closest('[data-action]');
  if (!target || target.disabled) return;
  // Le azioni di una finestra valgono solo per quella in primo piano.
  if (modals.length > 0 && !target.closest('.backdrop.top')) return;
  const handler = actions[target.dataset.action];
  if (handler) {
    event.preventDefault();
    handler({ ...target.dataset }, event);
  }
});

// Clic sullo sfondo scuro: chiude la finestra (non i dialoghi di conferma).
modalRoot.addEventListener('mousedown', (event) => {
  if (event.target.classList.contains('backdrop') && event.target.classList.contains('top')) {
    const type = modals.at(-1)?.type;
    if (type !== 'confirm' && type !== 'alert') closeModal();
  }
});

document.addEventListener('input', (event) => {
  const el = event.target;
  if (el.dataset.input === 'exams-query') {
    ui.examsQuery = el.value;
    render();
  } else if (el.dataset.input === 'career-query') {
    ui.careerQuery = el.value;
    render();
  } else if (el.dataset.subtask !== undefined && modals.length > 0) {
    // Titolo di una voce della checklist: niente ridisegno, per non perdere il cursore.
    const sub = modals.at(-1).subtasks?.[Number(el.dataset.subtask)];
    if (sub) sub.title = el.value;
  } else if (el.dataset.model && el.type !== 'checkbox') {
    const modal = modals.at(-1);
    const before = modal.type === 'exam' ? isFinalTestOf(modal) : null;
    modal[el.dataset.model] = el.value;
    if (modal.type === 'exam' && el.dataset.model === 'name') {
      // Il nome può far riconoscere una prova finale o una tesi.
      if (isFinalTestOf(modal) !== before) {
        proposeThesisCFU(modal);
        renderModals();
      } else {
        modalRoot.querySelector('[data-action=modal-confirm]').disabled = !modal.name.trim();
      }
    } else if (el.dataset.model === 'title') {
      modalRoot.querySelector('[data-action=modal-confirm]').disabled = !modal.title.trim();
    } else if (el.dataset.rerender) {
      renderModals();
    }
  }
});

document.addEventListener('change', (event) => {
  const el = event.target;
  if (el.dataset.change && changes[el.dataset.change]) {
    changes[el.dataset.change]({ ...el.dataset }, el);
  } else if (el.dataset.model && el.type === 'checkbox') {
    const modal = modals.at(-1);
    modal[el.dataset.model] = el.checked;
    proposeThesisCFU(modal);
    renderModals();
  }
});

document.addEventListener('contextmenu', (event) => {
  if (modals.length > 0) return;
  const task = event.target.closest('[data-ctx=task]');
  if (task) return taskMenu(event, task.dataset.exam, task.dataset.task);
  const exam = event.target.closest('[data-ctx=exam]');
  if (exam) return examMenu(event, exam.dataset.exam);
  closeMenu();
});

// Trascinamento dei task (di qualsiasi esame) sui giorni della settimana.
document.addEventListener('dragstart', (event) => {
  const row = event.target.closest?.('[data-drag]');
  if (!row) return;
  event.dataTransfer.setData('text/plain', row.dataset.drag);
  event.dataTransfer.effectAllowed = 'move';
  row.classList.add('dragging');
});

document.addEventListener('dragend', (event) => {
  event.target.closest?.('[data-drag]')?.classList.remove('dragging');
  setDropTarget(null);
});

function setDropTarget(key) {
  if (ui.dropTarget === key) return;
  ui.dropTarget = key;
  for (const zone of view.querySelectorAll('[data-drop]')) zone.classList.toggle('targeted', zone.dataset.drop === key);
}

document.addEventListener('dragover', (event) => {
  const zone = event.target.closest?.('[data-drop]');
  if (!zone) return setDropTarget(null);
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
  setDropTarget(zone.dataset.drop);
});

document.addEventListener('drop', (event) => {
  const zone = event.target.closest?.('[data-drop]');
  setDropTarget(null);
  if (!zone) return;
  event.preventDefault();
  const [examID, taskID] = event.dataTransfer.getData('text/plain').split('|');
  // "Oggi" mostra i task di tutti gli esami: qualsiasi task si può spostare (mai oltre il giorno del suo esame).
  if (!examID || !taskID || !store.exam(examID)) return;
  store.moveTask(taskID, examID, noon(fromDayKey(zone.dataset.drop)));
});

document.addEventListener('keydown', (event) => {
  const top = modals.at(-1);
  if (event.key === 'Escape') {
    if (menuRoot.firstChild) return closeMenu();
    if (top) return closeModal();
  }
  if (top) {
    const inTextarea = event.target.tagName === 'TEXTAREA';
    if (event.key === 'Enter' && (!inTextarea || event.ctrlKey) && top.type !== 'simulation') {
      event.preventDefault();
      confirmTopModal();
    }
    return;
  }
  if (event.key === 'F5') {
    event.preventDefault();
    sync.sync(store);
    return;
  }
  if (!event.ctrlKey || event.altKey) return;
  const tabs = Object.keys(TABS);
  const index = Number(event.key) - 1;
  if (index >= 0 && index < tabs.length) {
    event.preventDefault();
    actions.tab({ value: tabs[index] });
  } else if (event.key.toLowerCase() === 'n') {
    event.preventDefault();
    newExam();
  } else if (event.key.toLowerCase() === 'f') {
    event.preventDefault();
    focusSearch();
  }
});

// MARK: Avvio e sincronizzazione

/** Dopo ogni modifica, 2 secondi di attesa per raggruppare le modifiche ravvicinate. */
let syncTimer = null;
let lastErrorShown = null;
let lastFocusSync = 0;

function onStoreChange() {
  render();
  if (modals.at(-1)?.type === 'simulation') renderModals();
  if (store.lastError && store.lastError !== lastErrorShown) {
    lastErrorShown = store.lastError;
    alertModal('Errore', STORE_ERRORS[store.lastError]);
    store.clearError();
    lastErrorShown = null;
  }
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => sync.sync(store), 2000);
}

/** Ogni mezzo minuto: nuovo giorno o countdown al minuto da aggiornare. */
function tick() {
  const previous = now;
  now = new Date();
  const dayChanged = dayDiff(today, now) !== 0;
  if (dayChanged) today = now;
  const minuteChanged = Math.floor(previous / 60_000) !== Math.floor(now / 60_000);
  const busy = ['SELECT', 'INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName) || menuRoot.firstChild;
  if (dayChanged || (minuteChanged && !busy && view.querySelector('.precise'))) render();
  pushWidget();
}

async function start() {
  try {
    desktop = await api.getDesktopSettings();
    update = await api.update.getState();
    store = await ExamStore.open({ persistence: await makePersistence() });
  } catch (error) {
    view.innerHTML = `<div class="empty-state">${icon('alert')}<h3>Impossibile avviare ExamsTrack</h3><p>${esc(String(error))}</p></div>`;
    return;
  }
  sync = new SyncService(() => {
    renderRail();
    if (ui.tab === 'settings') render();
  });
  if (ui.tab === 'career') ui.careerDegree = careerDegree(context());
  store.subscribe(onStoreChange);
  render();
  if (store.lastError) onStoreChange();

  new Notifier(() => store.exams);
  sync.detect();
  sync.sync(store);
  setInterval(tick, 30_000);
  setInterval(studyTick, 1_000);
  // Le modifiche fatte su iPhone e iPad arrivano anche senza toccare nulla.
  setInterval(() => sync.sync(store), 5 * 60_000);

  api.onFocus(() => {
    tick();
    if (Date.now() - lastFocusSync > 15_000) {
      lastFocusSync = Date.now();
      sync.sync(store);
    }
  });
  api.onFolderChanged(() => sync.sync(store));
  api.update.onState((state) => {
    update = state;
    const busy = ['SELECT', 'INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);
    if (ui.tab === 'settings' && !busy) render();
  });
  api.onSyncNow(() => sync.sync(store));
  api.widget.onToggleTask(toggleFromWidget);
  api.widget.onOpen(openFromWidget);
  api.onDesktopChanged(async () => {
    desktop = await api.getDesktopSettings();
    const busy = ['SELECT', 'INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);
    if (ui.tab === 'settings' && !busy) render();
    else pushWidget();
  });
  api.onHidden(() => sync.sync(store));
  api.onBeforeQuit(async () => {
    clearTimeout(syncTimer);
    try {
      await store.flush();
      await sync.sync(store);
    } finally {
      api.readyToQuit();
    }
  });
}

start();
