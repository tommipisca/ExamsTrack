// Widget sul desktop: disegna i dati che arrivano dalla finestra principale (vedi core/widget.js),
// come ExtraLargeHomeWidgetView del widget iOS. Clic su un task o un esame: apre l'esame nell'app;
// clic sul cerchio: spunta il task; clic altrove: apre "Oggi". Si sposta trascinandolo.

import { colorAt, countdownColor, degreeLabel, PALETTE } from '../core/logic.js';
import { italianShort, toDate } from '../core/calendar.js';
import { checkCircle, icon } from './icons.js';

const widget = window.widget;
const card = document.getElementById('card');
let data = null;

const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

const longFormat = new Intl.DateTimeFormat('it-IT', { weekday: 'short', day: 'numeric', month: 'short' });
/** "sab 14 nov", come `widgetLong` del widget iOS. */
const widgetLong = (date) => longFormat.format(toDate(date)).replaceAll('.', '');
const tint = (color, percent) => `color-mix(in srgb, ${color} ${percent}%, transparent)`;

// MARK: Disegno

function countdown(summary) {
  const color = countdownColor(summary.daysRemaining, colorAt(summary.colorIndex));
  if (summary.daysRemaining <= 1) {
    return `<div class="countdown words" style="color:${color}">${summary.daysRemaining === 0 ? 'Oggi' : 'Domani'}</div>`;
  }
  return `<div class="countdown" style="color:${color}"><b>${summary.daysRemaining}</b><small>giorni</small></div>`;
}

function ring(summary) {
  const color = colorAt(summary.colorIndex);
  const radius = 28.5;
  const length = 2 * Math.PI * radius;
  // La percentuale è testo HTML sopra l'anello: resta della stessa grandezza quando l'anello si riduce.
  return `<div class="ring"><svg viewBox="0 0 62 62" aria-hidden="true">
    <circle cx="31" cy="31" r="${radius}" fill="none" stroke="${tint(color, 22)}" stroke-width="5"/>
    <circle cx="31" cy="31" r="${radius}" fill="none" stroke="${color}" stroke-width="5" stroke-linecap="round"
      stroke-dasharray="${length * summary.progress} ${length}" transform="rotate(-90 31 31)"/></svg>
    <span>${summary.progressPercent}%</span></div>`;
}

function header(summary) {
  return `<div class="header">
    <div class="header-text">
      <div class="name-row"><span class="name">${esc(summary.name)}</span>${data.showDegree
        ? `<span class="capsule">${degreeLabel(summary.degree)}</span>` : ''}</div>
      ${countdown(summary)}
      <div class="date">${widgetLong(summary.examDate)}</div>
    </div>
    ${summary.hasTasks ? `<div class="progress">${ring(summary)}
      <div class="count">${summary.completedTasks} di ${summary.totalTasks}</div></div>` : ''}
  </div>`;
}

function taskRow(task) {
  const examColor = colorAt(task.colorIndex);
  const checkColor = task.isOverdue ? PALETTE.danger : examColor;
  const label = task.isDone ? `Segna ${task.title} come da fare` : `Segna ${task.title} come fatto`;
  return `<div class="task${task.isDone ? ' done' : ''}" data-fit data-open="${esc(task.examID)}">
    <button class="toggle" data-toggle data-exam="${esc(task.examID)}" data-task="${esc(task.taskID)}" title="${esc(label)}">${checkCircle(task.isDone, checkColor)}</button>
    <span class="title">${esc(task.title)}</span>
    <span class="exam" style="color:${examColor}">${esc(task.examName)}</span>
    <span class="due${task.isOverdue ? ' late' : ''}">${task.isOverdue ? 'scaduto' : italianShort(task.dueDate)}</span>
  </div>`;
}

function taskList(summary) {
  const empty = summary.upcomingTasks.length > 0 ? ''
    : summary.hasTasks ? '<div class="note done">Tutti i task completati</div>' : '<div class="note">Nessun task pianificato</div>';
  return `<div class="list" data-fit-list><div class="list-title">Da fare</div>${empty}${summary.upcomingTasks.map(taskRow).join('')}</div>`;
}

function examRow(exam) {
  const color = colorAt(exam.colorIndex);
  const days = exam.daysRemaining === 0 ? 'Oggi' : exam.daysRemaining === 1 ? 'Domani' : `${exam.daysRemaining} g`;
  return `<div class="exam-row" data-fit data-open="${esc(exam.examID)}">
    <span class="bar" style="background:${color}"></span>
    <div class="text">
      <span class="exam-name">${esc(exam.name)}</span>
      <span class="exam-date">${widgetLong(exam.examDate)}</span>
      ${exam.hasTasks ? `<div class="meter" style="background:${tint(color, 22)}"><span style="width:${Math.round(exam.progress * 100)}%;background:${color}"></span></div>` : ''}
    </div>
    <span class="days" style="color:${color}">${days}</span>
  </div>`;
}

function followingExams(summary) {
  const rows = summary.followingExams.length === 0
    ? '<div class="note">Nessun altro esame in programma</div>'
    : summary.followingExams.map(examRow).join('');
  return `<div class="list exams" data-fit-list><div class="list-title">Prossimi esami</div>${rows}</div>`;
}

function render() {
  if (!data) return;
  const summary = data.summary;
  card.innerHTML = summary
    ? `<div class="columns">
        <section class="column">${header(summary)}<div class="divider"></div>${taskList(summary)}</section>
        <div class="vrule"></div>
        <section class="column">${followingExams(summary)}</section>
      </div>`
    : `<div class="empty">${icon('cap')}<p>Nessun esame in programma</p></div>`;
  fit();
}

/** Come FittingColumn del widget iOS: solo le righe che ci stanno per intero, le altre si nascondono. */
function fit() {
  for (const list of card.querySelectorAll('[data-fit-list]')) {
    const bottom = list.getBoundingClientRect().bottom + 0.5;
    let isFull = false;
    for (const row of list.querySelectorAll('[data-fit]')) {
      if (!isFull && row.getBoundingClientRect().bottom > bottom) isFull = true;
      row.style.visibility = isFull ? 'hidden' : '';
    }
  }
}

// MARK: Clic e trascinamento

let press = null;
let suppressClick = false;

document.addEventListener('pointerdown', (event) => {
  if (event.button !== 0 || data?.locked) return;
  press = { x: event.screenX, y: event.screenY, moved: false };
  widget.dragStart();
});

document.addEventListener('pointermove', (event) => {
  if (!press) return;
  if (!press.moved && Math.hypot(event.screenX - press.x, event.screenY - press.y) < 4) return;
  if (!press.moved) {
    // Catturato solo quando diventa un trascinamento: altrimenti il clic finirebbe sulla pagina, non sul task.
    press.moved = true;
    document.documentElement.setPointerCapture(event.pointerId);
  }
  widget.drag();
});

document.addEventListener('pointerup', () => {
  if (press?.moved) {
    widget.dragEnd();
    suppressClick = true;
  }
  press = null;
});

document.addEventListener('click', (event) => {
  if (suppressClick) {
    suppressClick = false;
    return;
  }
  const toggle = event.target.closest('[data-toggle]');
  if (toggle) {
    // Subito barrato (o riaperto) qui; poi arrivano i dati aggiornati dall'app.
    const task = data?.summary?.upcomingTasks.find((item) => item.taskID === toggle.dataset.task);
    if (task) {
      task.isDone = !task.isDone;
      render();
    }
    widget.toggleTask(toggle.dataset.exam, toggle.dataset.task);
    return;
  }
  widget.open(event.target.closest('[data-open]')?.dataset.open || null);
});

document.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  widget.menu();
});

widget.onData((next) => {
  data = next;
  document.documentElement.dataset.size = next.size ?? 'small';
  document.documentElement.classList.toggle('locked', Boolean(next.locked));
  render();
});
window.addEventListener('resize', fit);
widget.ready();
