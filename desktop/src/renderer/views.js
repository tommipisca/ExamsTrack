// Le schede dell'app, impaginate come su iPad: Oggi, Esami, Carriera, Impostazioni.

import * as L from '../core/logic.js';
import { dayDiff, dayKey, italianLong, italianShort, italianWeekday, relativeLabel } from '../core/calendar.js';
import { REMINDER_OFFSETS } from '../core/notifications.js';
import { C, data, esc, examCard, upcomingRow, pastRow, rescheduleBanner, taskRow, emptyState, sectionHeader,
  segmented, toggle, gradeBadge, colorBar, degreeTag } from './components.js';
import { icon, checkCircle } from './icons.js';
import { trendChart, sparkline } from './chart.js';

export const TABS = {
  today: { title: 'Oggi', icon: 'sun' },
  exams: { title: 'Esami', icon: 'calendar' },
  career: { title: 'Carriera', icon: 'cap' },
  settings: { title: 'Impostazioni', icon: 'gear' },
};

const VISIBILITY_LABELS = { both: 'Triennale e magistrale', triennale: 'Solo triennale', magistrale: 'Solo magistrale' };

function card(content, extra = '') {
  return `<div class="card" ${extra}>${content}</div>`;
}

function pageHeader(title, trailing = '') {
  return `<header class="page-header"><h1>${esc(title)}</h1><div class="page-actions">${trailing}</div></header>`;
}

// MARK: Oggi

/** Minuti e secondi che mancano alla fine della sessione ("24:59"). */
export function studyRemaining(end, now = new Date()) {
  const seconds = Math.max(0, Math.round((new Date(end).getTime() - now.getTime()) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

/** La sessione di studio in corso, o appena finita con i pulsanti per decidere cosa fare. */
function studyCard(study, ctx) {
  const color = L.colorAt(study.colorIndex);
  const finished = new Date(study.end) <= ctx.now;
  const actions = finished
    ? `${study.taskID ? `<button class="btn prominent" data-action="study-done">${icon('check')} Segna fatto</button>` : ''}
       <button class="btn" data-action="study-more">${icon('timer')} Altri ${L.STUDY_EXTRA_MINUTES} minuti</button>
       <button class="btn" data-action="study-stop">Pausa</button>`
    : '<button class="btn" data-action="study-stop">Termina</button>';
  return `<div class="card study-card" style="--c:${color}">
    ${icon('timer')}
    <span class="row-main">
      <strong>${esc(study.taskTitle ?? 'Sessione di studio')}</strong>
      <span class="study-exam">${esc(study.examName)}</span>
    </span>
    ${finished ? '<span class="muted">Sessione finita</span>' : `<span class="study-timer" data-study-end="${esc(study.end)}">${studyRemaining(study.end, ctx.now)}</span>`}
    <span class="actions">${actions}</span>
  </div>`;
}

/** "Oggi": a sinistra il prossimo esame e l'agenda di tutti gli esami, a destra gli altri esami da sostenere. */
export function todayView(ctx) {
  const { store, today, ui } = ctx;
  const exams = L.visible(store.exams, ctx.visibility);
  const board = L.todayBoard(exams, today);
  const examByID = new Map(exams.map((exam) => [exam.id, exam]));
  const hasActive = L.active(exams, today).length > 0;
  // Come la barra di navigazione su iPad: solo il titolo e due icone (sessione di studio e nuovo task).
  const actions = hasActive ? `<button class="btn icon-only" data-action="study-menu" title="Sessione di studio sul prossimo task di oggi">${icon('timer')}</button>
    <button class="btn icon-only" data-action="quick-task" title="Nuovo task">${icon('plus')}</button>` : '';
  return `${pageHeader('Oggi', actions)}
  <div class="board">
    <section class="board-left scroll" data-scroll="today-left">${todayLeft()}</section>
    <section class="board-right scroll" data-scroll="today-right">${todayRight()}</section>
  </div>`;

  function dropZone(key, content, extraClass = '') {
    return `<div class="card drop-zone ${extraClass}${ui.dropTarget === key ? ' targeted' : ''}" ${data({ drop: key })}>${content}</div>`;
  }

  function row(item, options = {}) {
    const exam = examByID.get(item.examID);
    return exam ? taskRow(item.task, exam, { today, draggable: true, showsExam: true, ...options }) : '';
  }

  function todayLeft() {
    const parts = [];
    if (ctx.study) parts.push(studyCard(ctx.study, ctx));
    const next = board.next;
    parts.push(next
      ? examCard(next, { ...ctx, action: { action: 'open-exam', exam: next.id } })
      : card(`<div class="empty-line">${icon('calendarPlus')} Nessun esame in programma: aggiungi la data a un esame nella scheda Esami.</div>`));

    const { overdue, dueToday, days, later } = board.agenda;
    if (overdue.length > 0) parts.push(rescheduleBanner(overdue.length, [...new Set(overdue.map((item) => item.examID))]));

    const todays = [...overdue, ...dueToday].map((item) => row(item, { large: true }));
    parts.push(`<div class="group">${sectionHeader('Da fare oggi')}
      ${dropZone(dayKey(today), todays.length ? todays.join('') : `<div class="empty-line">${icon('seal')} Niente in scadenza oggi.</div>`)}</div>`);

    const slots = days.map((day) => {
      const examsThatDay = exams.filter((exam) => exam.isScheduled && dayDiff(day.date, exam.date) === 0);
      const label = dayDiff(today, day.date) === 1 ? 'Domani' : italianWeekday(day.date);
      const head = `<div class="day-head"><span>${esc(label.charAt(0).toUpperCase() + label.slice(1))}</span>
        ${examsThatDay.map((exam) => `<span class="exam-day" style="color:${L.examColor(exam)}">${icon('cap')} Esame: ${esc(exam.name)}</span>`).join('')}</div>`;
      // Un giorno libero è una riga sottile: resta un punto di arrivo per trascinarci un task.
      if (day.items.length === 0 && examsThatDay.length === 0) {
        return dropZone(dayKey(day.date), `${head}<span class="free-label">${ui.dropTarget === dayKey(day.date) ? 'Lascia qui' : 'Libero'}</span>`, 'day-slot free');
      }
      return dropZone(dayKey(day.date), head + day.items.map((item) => row(item)).join(''), 'day-slot');
    });
    parts.push(`<div class="group">${sectionHeader('Questa settimana')}${slots.join('')}</div>`);

    if (later.length > 0) {
      parts.push(`<div class="group">${sectionHeader('Più avanti')}${card(later.map((item) => row(item, { showsDate: true })).join(''))}</div>`);
    }
    return parts.join('');
  }

  function todayRight() {
    const parts = [sectionHeader('Prossimi esami')];
    if (board.others.length === 0) {
      parts.push(card(`<div class="empty-line">${icon('seal')} Nessun altro esame da sostenere.</div>`));
      return parts.join('');
    }
    // Come su iPad: ogni esame nel suo riquadro.
    for (const exam of board.others) {
      const color = L.examColor(exam);
      const days = L.daysRemaining(exam, today);
      const trailing = exam.isScheduled
        ? `<span class="countdown small" style="color:${L.countdownColor(days, color)}">${days === 0 ? 'Oggi' : days === 1 ? 'Domani' : `<b>${days}</b><small>g</small>`}</span>`
        : '<span class="muted small-text">Da programmare</span>';
      parts.push(card(`<button class="other-exam" ${data({ action: 'open-exam', exam: exam.id })} ${data({ ctx: 'exam', exam: exam.id })}>${colorBar(color)}
        <span class="row-main"><span class="row-title">${esc(exam.name)}</span>
          ${exam.tasks.length ? `<span class="bar"><span style="width:${L.progressPercent(exam)}%;background:${color}"></span></span>` : ''}</span>
        ${trailing}</button>`));
    }
    return parts.join('');
  }
}

// MARK: Esami

export function examsView(ctx) {
  const { store, today, ui } = ctx;
  const exams = L.visible(store.exams, ctx.visibility);
  const query = ui.examsQuery.trim();
  const rowsFor = (title, list, isPast) => (list.length === 0 ? '' : `<div class="group">${sectionHeader(title)}<div class="card list">${list.map((exam) => {
    const options = { today, visibility: ctx.visibility, selected: ui.examsSelected === exam.id, action: { action: 'select-exam', exam: exam.id } };
    return isPast ? pastRow(exam, options) : upcomingRow(exam, options);
  }).join('')}</div></div>`);

  let list;
  if (!query) {
    const active = L.active(exams, today);
    list = rowsFor('In programma', active.filter((exam) => exam.isScheduled), false)
      + rowsFor('Da programmare', active.filter((exam) => !exam.isScheduled), false);
    if (active.length === 0) {
      list = emptyState('cap', 'Nessun esame da sostenere', 'Aggiungi un esame per iniziare il conto alla rovescia.',
        `<button class="btn prominent" data-action="new-exam">${icon('plus')} Aggiungi esame</button>`);
    }
  } else {
    // Ricerca su tutti gli esami del corso visibile, anche quelli passati.
    const matches = L.matching(exams, query);
    list = rowsFor('Da sostenere', matches.filter((exam) => L.isActive(exam, today))
      .sort((a, b) => L.compareBy([a.date, b.date], [a.name, b.name])), false)
      + rowsFor('Esami passati', matches.filter((exam) => !L.isActive(exam, today))
        .sort((a, b) => L.compare(b.date, a.date)), true);
    if (matches.length === 0) list = emptyState('search', `Nessun risultato per “${query}”`, 'Controlla l\'ortografia o prova un\'altra ricerca.');
  }

  const selected = ui.examsSelected ? store.exam(ui.examsSelected) : null;
  return `<div class="split">
    <section class="split-list">
      ${pageHeader('Esami', `<button class="btn icon-only prominent" data-action="new-exam" title="Nuovo esame (Ctrl+N)">${icon('plus')}</button>`)}
      <div class="search">${icon('search')}<input id="exam-search" type="search" placeholder="Cerca esami, note e task (Ctrl+F)" value="${esc(ui.examsQuery)}" data-input="exams-query"></div>
      <div class="scroll" data-scroll="exams-list">${list}</div>
    </section>
    <section class="split-detail scroll" data-scroll="exams-detail-${esc(ui.examsSelected ?? '')}">
      ${selected ? examDetail(selected, ctx) : emptyState('sidebar', 'Seleziona un esame', 'Il dettaglio compare qui.')}
    </section>
  </div>`;
}

// MARK: Dettaglio esame

export function examDetail(exam, ctx) {
  const { today } = ctx;
  const color = L.examColor(exam);
  const isActive = L.isActive(exam, today);
  const parts = [];

  parts.push(`<header class="detail-header">
    <div><h1>${esc(exam.name)}</h1></div>
    <div class="page-actions">
      <button class="btn" ${data({ action: 'edit-exam', exam: exam.id })}>${icon('pencil')} Modifica</button>
      <button class="btn danger-text" ${data({ action: 'delete-exam', exam: exam.id })}>${icon('trash')} Elimina</button>
    </div>
  </header>`);
  parts.push(examCard(exam, { ...ctx, showsName: false }));
  if (!isActive) parts.push(outcomeSection(exam));

  parts.push(`<button class="notes-card" ${data({ action: 'edit-notes', exam: exam.id })}>
    <span style="color:${color}">${icon('note')}</span>
    <span class="${exam.notes ? 'notes-text' : 'muted'}">${exam.notes ? esc(exam.notes) : 'Aggiungi note: programma, materiale, modalità d\'esame…'}</span>
    ${icon('chevron', 'muted')}
  </button>`);

  const overdue = L.overdueCount(exam, today);
  if (overdue > 0) parts.push(rescheduleBanner(overdue, [exam.id]));

  // Timeline: i task in ordine di scadenza, il segnaposto di oggi e il giorno dell'esame.
  const tasks = L.sortedTasks(exam);
  const items = tasks.map((task) => ({ task }));
  const marker = L.todayMarkerIndex(exam, today);
  if (marker !== null) items.splice(marker, 0, { today: true });
  const rows = items.map((item, index) => {
    const first = index === 0 ? ' first' : '';
    if (item.today) {
      return `<div class="timeline-row today-marker${first}" style="--c:${color}">
        <span class="timeline-node"><span class="today-dot"></span></span>
        <span class="today-label"><strong>Oggi</strong> <span class="muted">${italianShort(today)}</span><span class="rule"></span></span>
      </div>`;
    }
    const task = item.task;
    const overdueTask = L.isOverdue(task, today);
    return `<div class="timeline-row${first}${task.isDone ? ' done' : ''}" style="--c:${color}" ${data({ ctx: 'task', exam: exam.id, task: task.id })}>
      <span class="timeline-node"><button class="check-button" ${data({ action: 'toggle-task', exam: exam.id, task: task.id })}
        title="${task.isDone ? 'Segna come da fare' : 'Segna come fatto'}">${checkCircle(task.isDone, overdueTask ? C.danger : color)}</button></span>
      <button class="task-text" ${data({ action: 'edit-task', exam: exam.id, task: task.id })}>
        <span class="task-title">${esc(task.title)}</span>
        <span class="task-sub${overdueTask ? ' danger' : ''}">${overdueTask ? `In ritardo, scadeva il ${italianShort(task.dueDate)}` : italianShort(task.dueDate)}${L.subtaskLabel(task) ? `<span class="sub-count">${icon('checklist')} ${L.subtaskLabel(task)}</span>` : ''}</span>
      </button>
      <button class="row-delete" title="Elimina task" ${data({ action: 'delete-task', exam: exam.id, task: task.id })}>${icon('trash')}</button>
    </div>${(task.subtasks ?? []).length ? `<div class="timeline-row subtask-row" style="--c:${color}">
      <span class="timeline-node"></span>
      <div class="subtasks">${task.subtasks.map((sub) => `<button class="subtask${sub.isDone ? ' done' : ''}" ${data({ action: 'toggle-subtask', exam: exam.id, task: task.id, sub: sub.id })}
        title="${sub.isDone ? 'Segna da fare' : 'Segna fatta'}">${checkCircle(sub.isDone, sub.isDone ? color : C.textSecondary)}<span>${esc(sub.title)}</span></button>`).join('')}</div>
    </div>` : ''}`;
  });
  rows.push(`<div class="timeline-row milestone last${items.length === 0 ? ' first' : ''}" style="--c:${color}">
    <span class="timeline-node"><span class="milestone-icon" style="background:${color}">${icon('cap')}</span></span>
    <span class="task-text static"><span class="task-title strong">Esame</span>
    <span class="task-sub">${exam.isScheduled ? italianLong(exam.date) : 'Data da definire'}</span></span>
  </div>`);

  parts.push(`<div class="group">${sectionHeader('Piano di studio', `<div class="header-actions">
      ${isActive ? `<button class="link" style="color:${color}" ${data({ action: 'plan-study', exam: exam.id })}>${icon('wand')} Pianifica</button>` : ''}
      <button class="link" style="color:${color}" ${data({ action: 'new-task', exam: exam.id })}>${icon('plus')} Aggiungi task</button>
    </div>`)}<div class="timeline">${rows.join('')}</div></div>`);

  return `<div class="detail readable">${parts.join('')}</div>`;
}

function outcomeSection(exam) {
  const passed = exam.passed;
  let extra = '';
  if (passed === true && L.isMasterThesis(exam)) {
    extra = `<div class="form-row"><span>Punteggio tesi</span>
      <span class="stepper"><button ${data({ action: 'thesis-points', exam: exam.id, delta: -0.5 })}>−</button>
      <b style="color:${C.gold}">${esc(L.thesisPointsLabel(exam) ?? '—')}</b>
      <button ${data({ action: 'thesis-points', exam: exam.id, delta: 0.5 })}>+</button></span></div>`;
  } else if (passed === true) {
    const options = Array.from({ length: 13 }, (_, i) => 18 + i)
      .map((grade) => `<option value="${grade}" ${grade === (exam.grade ?? 18) ? 'selected' : ''}>${grade}</option>`).join('');
    extra = `<div class="form-row"><span>Voto</span><select ${data({ change: 'grade', exam: exam.id })}>${options}</select></div>`;
    if (exam.grade === 30) {
      extra += `<div class="form-row"><span>Lode</span>${toggle(exam.honors, { change: 'honors', exam: exam.id })}</div>`;
    }
  }
  const value = passed === null ? 'none' : passed ? 'passed' : 'failed';
  return `<div class="group">${sectionHeader('Esito')}
    <div class="card form">
      <div class="form-row">${segmented([['none', 'Da inserire'], ['passed', 'Superato'], ['failed', 'Non superato']], value, 'outcome', { exam: exam.id })}</div>
      ${extra}
    </div>
    ${L.isMasterThesis(exam) ? '<p class="footer-note">Da −1 a +7 punti con controrelatore (+8 con giudizio di eccellenza), fino a +4 senza.</p>' : ''}
  </div>`;
}

// MARK: Carriera

export function careerDegree(ctx) {
  return ctx.visibility !== 'both' ? ctx.visibility : (ctx.ui.careerDegree ?? ctx.prefs.get('careerFilter'));
}

export function careerView(ctx) {
  const { store, today, ui, prefs } = ctx;
  const degree = careerDegree(ctx);
  const thesis = prefs.get('thesisType');
  const sort = prefs.get('careerSort');
  const estimate = L.estimateFor(store.exams, degree, thesis);
  const trend = L.averageTrend(L.visible(store.exams, ctx.visibility), degree);
  const career = L.sortedForCareer(L.matching(L.career(store.exams, degree, today), ui.careerQuery), sort);
  const query = ui.careerQuery.trim();

  const switcher = ctx.visibility === 'both'
    ? `<div class="center">${segmented(L.DEGREES.map((d) => [d, L.degreeLabel(d)]), degree, 'career-degree')}</div>` : '';
  const totalCFU = degree === 'triennale' ? L.TRIENNALE_CFU : 120;
  const summary = `<button class="summary-card${ui.careerSelection === 'overview' ? ' selected' : ''}" data-action="career-overview">
    <span class="summary-head">${icon('cap')}<strong>Riepilogo</strong><span class="muted">${L.degreeLabel(degree)}</span></span>
    <span class="summary-main"><span><b class="summary-grade">${estimate ? L.gradeText(estimate) : '—'}</b><small class="muted">Voto di laurea</small></span>
      ${trend.length >= 2 ? sparkline(trend) : ''}</span>
    <span class="summary-stats">
      <span><b style="color:${C.accent}">${L.averageText(L.weightedAverage(store.exams, degree))}</b><small>Media</small></span>
      <span><b>${L.earnedCFU(store.exams, degree)}/${totalCFU}</b><small>CFU</small></span>
    </span>
  </button>`;

  let rows;
  if (career.length === 0) {
    rows = `<div class="card"><p class="empty-line">${query
      ? `Nessun esame sostenuto corrisponde a “${esc(query)}”.`
      : `Gli esami della ${L.degreeLabel(degree).toLowerCase()} compaiono qui dopo la loro data, con il voto che inserisci.`}</p></div>`;
  } else {
    rows = `<div class="card list">${career.map((exam) => pastRow(exam, {
      selected: ui.careerSelection === exam.id, action: { action: 'career-exam', exam: exam.id },
    })).join('')}</div>`;
  }
  const sortSelect = `<label class="sort">${icon('sort')}<select data-change="career-sort">${Object.entries(L.CAREER_SORTS)
    .map(([value, label]) => `<option value="${value}" ${value === sort ? 'selected' : ''}>${label}</option>`).join('')}</select></label>`;

  const selectedExam = ui.careerSelection !== 'overview' ? store.exam(ui.careerSelection) : null;
  const detail = selectedExam ? examDetail(selectedExam, ctx) : careerOverview(ctx, degree, estimate, trend);

  return `<div class="split">
    <section class="split-list">
      ${pageHeader('Carriera')}
      <div class="scroll" data-scroll="career-list">
        ${switcher}
        ${summary}
        <div class="search">${icon('search')}<input id="career-search" type="search" placeholder="Cerca negli esami sostenuti" value="${esc(ui.careerQuery)}" data-input="career-query"></div>
        <div class="group">${sectionHeader('Esami sostenuti', sortSelect)}${rows}</div>
      </div>
    </section>
    <section class="split-detail scroll" data-scroll="career-detail-${esc(ui.careerSelection)}">${detail}</section>
  </div>`;
}

function careerOverview(ctx, degree, estimate, trend) {
  const { store, prefs } = ctx;
  const thesis = prefs.get('thesisType');
  const average = L.weightedAverage(store.exams, degree);
  const simulated = L.simulatedAverage(store.exams, degree);
  const totalCFU = degree === 'triennale' ? L.TRIENNALE_CFU : 120;

  const notes = [];
  if (estimate) {
    const missing = degree === 'triennale' ? L.missingGraduationCFU(store.exams) : L.missingMasterCFU(store.exams);
    if (missing > 0) notes.push(`Minimo e massimo supponendo 18 o 30 nei ${missing} CFU ancora senza voto.`);
    if (degree === 'triennale') {
      if (!store.exams.some((e) => e.degree === 'triennale' && e.isFinalTest && L.countedGrade(e) !== null)) {
        notes.push('Anche le prove finali sono stimate tra 18 e 30.');
      }
    } else {
      const assigned = store.exams.find((e) => L.isMasterThesis(e) && e.passed === true && e.thesisPoints !== null);
      notes.push(assigned ? `Punteggio della tesi: ${L.thesisPointsLabel(assigned)}.`
        : `Tesi ${L.THESIS_TYPES[thesis].label.toLowerCase()}: da −1 a +${L.THESIS_TYPES[thesis].maximumPoints} punti.`);
    }
    if (estimate.canGetHonors) {
      const threshold = estimate.honorsThreshold.toLocaleString('it-IT', { maximumFractionDigits: 1 });
      notes.push(`Lode possibile da ${threshold} punti prima dell'arrotondamento, con voto unanime della commissione.`);
    }
  }

  const stats = `<div class="card stats">
    <div class="big-grade"><b>${estimate ? L.gradeText(estimate) : '—'}</b><span>Voto di laurea</span></div>
    <div class="stat-row">
      <div class="stat"><b style="color:${C.accent}">${L.averageText(average)}</b><span>Media</span></div>
      <div class="stat"><b>${L.earnedCFU(store.exams, degree)}/${totalCFU}</b><span>CFU</span></div>
      <button class="stat clickable" data-action="open-simulation" title="Apre il simulatore dei voti">
        ${simulated !== null ? `<b style="color:${C.success}">${L.averageText(simulated)}</b>` : `<span class="stat-icon" style="color:${C.success}">${icon('wand')}</span>`}
        <span>Media simulata ${icon('chevron')}</span>
      </button>
    </div>
    ${notes.length ? `<p class="footnote muted">${esc(notes.join(' '))}</p>` : ''}
  </div>`;

  const chart = trend.length >= 2 ? `<div class="group">${sectionHeader('Andamento della media')}<div class="card">${trendChart(trend, 260)}</div></div>` : '';
  return `<div class="detail readable">
    <header class="detail-header"><h1>Riepilogo</h1></header>
    ${stats}${chart}
  </div>`;
}

// MARK: Impostazioni

function settingRow(label, control, note = '') {
  return `<div class="form-row"><span>${esc(label)}${note ? `<small class="muted">${esc(note)}</small>` : ''}</span>${control}</div>`;
}

function select(change, options, selected) {
  return `<select data-change="${change}">${options.map(([value, label]) =>
    `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>${esc(label)}</option>`).join('')}</select>`;
}

/** Riga di stato e pulsanti della sezione Aggiornamenti. */
function updateRows(update, now) {
  const checked = update.lastCheck ? `Controllato ${esc(relativeLabel(new Date(update.lastCheck), now))}` : '';
  const checkButton = (label = 'Controlla aggiornamenti') =>
    `<div class="form-row buttons"><button class="btn" data-action="check-update">${icon('sync')} ${label}</button></div>`;
  switch (update.status) {
    case 'unsupported':
      return '<div class="form-row muted">Gli aggiornamenti funzionano solo nell\'app installata, non con npm start.</div>';
    case 'checking':
      return '<div class="form-row"><span>Controllo in corso…</span><span class="spinner"></span></div>';
    case 'downloading':
      return `<div class="form-row"><span>Download della versione ${esc(update.version)}…</span><span class="muted">${update.percent}%</span></div>`;
    case 'downloaded':
      return `<div class="form-row"><span>Versione ${esc(update.version)} pronta<small class="muted">Si installa alla chiusura di ExamsTrack</small></span>
        <button class="btn prominent" data-action="install-update">${icon('download')} Riavvia e aggiorna</button></div>`;
    case 'available':
      return `<div class="form-row"><span>Versione ${esc(update.version)} disponibile<small class="muted">La versione portable va scaricata a mano</small></span>
        <button class="btn prominent" data-action="open-release-page">${icon('download')} Scarica</button></div>`;
    case 'not-available':
      return `<div class="form-row"><span>ExamsTrack è aggiornata</span><span class="muted">${checked}</span></div>` + checkButton();
    case 'error':
      return `<div class="form-row warning">${icon('alert')} ${esc(update.error)}</div>` + checkButton('Riprova');
    default:
      return checkButton();
  }
}

function settingsSection(title, rows, footer = '') {
  return `<div class="group">${sectionHeader(title)}<div class="card form">${rows}</div>${footer ? `<p class="footer-note">${footer}</p>` : ''}</div>`;
}

export function settingsView(ctx) {
  const { prefs, sync, desktop, update, now } = ctx;
  const visibility = ctx.visibility;
  const sections = [];

  sections.push(settingsSection('Visualizzazione',
    settingRow('Scheda all\'apertura', select('start-tab', Object.entries(TABS).map(([key, tab]) => [key, tab.title]), prefs.get('startTab')))
    + settingRow('Corsi di laurea', select('visibility', Object.entries(VISIBILITY_LABELS), visibility))
    + (visibility === 'both' ? settingRow('Carriera default', select('career-filter', L.DEGREES.map((d) => [d, L.degreeLabel(d)]), prefs.get('careerFilter'))) : ''),
    'Con un solo corso, gli esami dell\'altro restano salvati e sincronizzati ma non compaiono da nessuna parte, neanche nelle notifiche. Scheda all\'apertura e filtro carriera valgono dal prossimo avvio.'));

  if (visibility !== 'triennale') {
    sections.push(settingsSection('Carriera',
      settingRow('Tesi magistrale', select('thesis-type', Object.entries(L.THESIS_TYPES).map(([key, type]) => [key, type.label]), prefs.get('thesisType'))),
      'Serve alla stima del voto di laurea magistrale: la tesi vale fino a 7 punti con controrelatore, fino a 4 senza. La lode è possibile solo con controrelatore.'));
  }

  // Sincronizzazione
  let syncRows;
  if (sync.folder) {
    syncRows = settingRow('Cartella', `<span class="path" title="${esc(sync.folder)}">${esc(sync.folder)}</span>`)
      + settingRow('Ultima sincronizzazione', sync.isSyncing ? '<span class="spinner"></span>'
        : `<span class="muted">${sync.lastSync ? esc(relativeLabel(sync.lastSync, now)) : 'Mai'}</span>`)
      + settingRow('Ultimo backup automatico', `<span class="muted">${sync.lastAutoBackup ? esc(relativeLabel(sync.lastAutoBackup, now)) : 'Mai'}</span>`)
      + (sync.errorMessage ? `<div class="form-row warning">${icon('alert')} ${esc(sync.errorMessage)}</div>` : '')
      + `<div class="form-row buttons">
          <button class="btn" data-action="sync-now" ${sync.isSyncing ? 'disabled' : ''}>${icon('sync')} Sincronizza ora</button>
          <button class="btn" data-action="open-sync-folder">${icon('folder')} Apri cartella</button>
          <button class="btn danger-text" data-action="unlink-sync">Scollega cartella</button>
        </div>`;
  } else {
    syncRows = (sync.suggestedFolder ? `<div class="form-row suggestion">${icon('cloud')}
        <span>Trovata in iCloud Drive la cartella usata da iPhone e iPad:<br><span class="path">${esc(sync.suggestedFolder)}</span></span>
        <button class="btn prominent" data-action="link-suggested">Collega</button></div>` : '')
      + `<div class="form-row buttons"><button class="btn" data-action="choose-sync-folder">${icon('folder')} Scegli cartella in iCloud Drive…</button></div>`;
  }
  sections.push(settingsSection('Sincronizzazione', syncRows,
    'Scegli la stessa cartella di iPhone e iPad (in iCloud Drive, sincronizzata su questo PC da iCloud per Windows): i dati si uniscono esame per esame e, se modifichi lo stesso esame su più dispositivi, vince la modifica più recente. Ogni giorno viene salvato un backup nella sottocartella Backup (gli ultimi 14).'));

  // Notifiche
  const settings = prefs.get('notificationSettings');
  const activeOffsets = Object.keys(REMINDER_OFFSETS).filter((key) => settings.examReminders.includes(key));
  const available = Object.keys(REMINDER_OFFSETS).filter((key) => !settings.examReminders.includes(key));
  const reminderRows = (activeOffsets.length === 0 ? '<div class="form-row muted">Nessun promemoria per gli esami</div>' : '')
    + activeOffsets.map((key) => `<div class="form-row"><span class="reminder">${icon('bell')} ${esc(REMINDER_OFFSETS[key].label)}</span>
      <button class="icon-button danger" title="Rimuovi" ${data({ action: 'remove-reminder', value: key })}>${icon('minus')}</button></div>`).join('')
    + (available.length ? `<div class="form-row"><select data-change="add-reminder"><option value="">＋ Aggiungi promemoria…</option>${available
      .map((key) => `<option value="${key}">${esc(REMINDER_OFFSETS[key].label)}</option>`).join('')}</select></div>` : '');
  sections.push(settingsSection('Promemoria esami', reminderRows, 'Valgono per tutti gli esami programmati. Gli esami da programmare non hanno promemoria.'));
  const time = `${String(settings.hour).padStart(2, '0')}:${String(settings.minute).padStart(2, '0')}`;
  sections.push(settingsSection('Promemoria giornaliero',
    settingRow('Task in scadenza oggi', toggle(settings.dailyTaskSummary, { change: 'daily-summary' }))
    + settingRow('Orario delle notifiche', `<input type="time" value="${time}" data-change="notification-time">`),
    'Nei giorni in cui scadono dei task ricevi l\'elenco di quelli ancora da fare. Le notifiche arrivano mentre ExamsTrack è aperta, anche solo come icona nell\'area di notifica.'));

  // Windows
  if (desktop) {
    sections.push(settingsSection('Windows',
      settingRow('Chiudendo la finestra resta nell\'area di notifica', toggle(desktop.closeToTray, { change: 'close-to-tray' }))
      + settingRow('Avvia con Windows', toggle(desktop.openAtLogin, { change: 'open-at-login' }), 'Parte nascosta nell\'area di notifica'),
      'Restando attiva, ExamsTrack invia i promemoria e riceve subito le modifiche fatte su iPhone e iPad. Per chiuderla del tutto: clic destro sull\'icona → Esci.'));
  }

  sections.push(settingsSection('Backup',
    `<div class="form-row buttons">
      <button class="btn" data-action="export-backup">${icon('upload')} Esporta dati</button>
      <button class="btn" data-action="import-backup">${icon('download')} Importa backup</button>
    </div>`,
    'Il backup è un file JSON compatibile con l\'app per iPhone e iPad: puoi importare qui un backup esportato dal telefono e viceversa.'));

  if (desktop && update) {
    sections.push(settingsSection('Aggiornamenti',
      settingRow('Versione installata', `<span class="muted">${esc(desktop.version)}</span>`)
      + updateRows(update, now)
      + (update.status === 'unsupported' ? '' : settingRow('Controlla automaticamente', toggle(desktop.autoUpdate !== false, { change: 'auto-update' }))),
      'ExamsTrack controlla su GitHub se c\'è una nuova versione all\'avvio e ogni 6 ore, e la scarica in background. I tuoi dati restano dove sono.'));
  }

  if (desktop) {
    sections.push(settingsSection('Informazioni',
      settingRow('Dati su questo PC', `<button class="btn" data-action="open-data-folder">${icon('folder')} Apri cartella</button>`)));
  }

  return `<div class="page scroll" data-scroll="settings">${pageHeader('Impostazioni')}<div class="readable">${sections.join('')}</div></div>`;
}

export { gradeBadge, degreeTag };
