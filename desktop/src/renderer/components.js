// Elementi dell'interfaccia condivisi dalle schede, come HTML.
// I clic arrivano ad app.js tramite gli attributi data-action.

import * as L from '../core/logic.js';
import { italianLong, italianShort } from '../core/calendar.js';
import { checkCircle, icon } from './icons.js';

export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

/** Attributi data-* da un oggetto. */
export function data(attributes) {
  return Object.entries(attributes)
    .filter(([, value]) => value !== null && value !== undefined)
    .map(([key, value]) => `data-${key}="${esc(value)}"`)
    .join(' ');
}

export const C = L.PALETTE;

export function colorBar(color) {
  return `<span class="color-bar" style="--c:${color}"></span>`;
}

/** Countdown in giorni: numero grande, "Oggi" e "Domani" in parole. */
export function countdownText(days, color, large = true) {
  const size = large ? 'large' : 'small';
  if (days === 0 || days === 1) {
    return `<span class="countdown ${size} words" style="color:${color}">${days === 0 ? 'Oggi' : 'Domani'}</span>`;
  }
  return `<span class="countdown ${size}" style="color:${color}" title="Tra ${days} giorni"><b>${days}</b><small>${large ? 'giorni' : 'g'}</small></span>`;
}

export function preciseCountdownText(countdown, color) {
  if (countdown.kind === 'remaining') {
    return `<div class="countdown large precise" style="color:${color}">
      <div><b>${countdown.value}</b><small>${countdown.unit}</small></div>
      ${countdown.detail ? `<div class="detail">${countdown.detail}</div>` : ''}
    </div>`;
  }
  if (countdown.kind === 'lessThanAMinute') return `<div class="countdown words title" style="color:${color}">Meno di un minuto</div>`;
  return `<div class="countdown words title" style="color:${color}">${icon('pen')} In corso</div>`;
}

export function progressRing(progress, color, size = 58) {
  const radius = 26;
  const length = 2 * Math.PI * radius;
  const percent = Math.round(progress * 100);
  return `<svg class="ring" width="${size}" height="${size}" viewBox="0 0 60 60" role="img" aria-label="Avanzamento ${percent}%">
    <circle cx="30" cy="30" r="${radius}" fill="none" stroke="${color}" stroke-opacity="0.2" stroke-width="6"/>
    <circle cx="30" cy="30" r="${radius}" fill="none" stroke="${color}" stroke-width="6" stroke-linecap="round"
      stroke-dasharray="${length}" stroke-dashoffset="${length * (1 - progress)}" transform="rotate(-90 30 30)"/>
    <text x="30" y="34.5" text-anchor="middle">${percent}%</text>
  </svg>`;
}

/** Etichetta del corso; con un solo corso mostrato non serve. */
export function degreeTag(degree, visibility) {
  return visibility === 'both' ? `<span class="degree-tag">${L.degreeLabel(degree)}</span>` : '';
}

/** Esito di un esame passato: voto, lode, non superato o da inserire. */
export function gradeBadge(exam) {
  let content;
  let color;
  if (exam.passed === true && L.isMasterThesis(exam)) {
    content = esc(L.thesisPointsLabel(exam) ?? '✓');
    color = C.gold;
  } else if (exam.passed === true && exam.honors) {
    content = '30L';
    color = C.gold;
  } else if (exam.passed === true) {
    content = exam.grade ?? '✓';
    color = C.success;
  } else if (exam.passed === false) {
    content = icon('x');
    color = C.danger;
  } else {
    content = icon('question');
    color = C.textSecondary;
  }
  return `<span class="grade-badge" style="--c:${color}" title="${esc(L.outcomeLabel(exam))}">${content}</span>`;
}

/** "lunedì 24 novembre 2026, ore 14:30" */
function dateLine(exam) {
  if (!exam.isScheduled) return 'Data da definire';
  const time = L.startTimeLabel(exam);
  return time ? `${italianLong(exam.date)}, ore ${time}` : italianLong(exam.date);
}

/** Riquadro del prossimo esame e intestazione del dettaglio. */
export function examCard(exam, { today, now, visibility, showsName = true, action = null }) {
  const days = L.daysRemaining(exam, today);
  const color = L.examColor(exam);
  let countdown;
  if (!exam.isScheduled) {
    countdown = `<div class="countdown words title" style="color:${color}">Da programmare</div>`;
  } else if (days >= 0 && exam.startTime !== null) {
    countdown = preciseCountdownText(L.preciseCountdown(exam, now), L.countdownColor(days, color));
  } else if (days >= 0) {
    countdown = countdownText(days, L.countdownColor(days, color));
  } else {
    countdown = `<div class="countdown words title">${esc(L.outcomeLabel(exam))}</div>`;
  }
  const tasksLine = exam.tasks.length === 0
    ? 'Nessun task: aggiungine uno per pianificare lo studio'
    : `${L.completedTaskCount(exam)} di ${exam.tasks.length} task completati`;
  const tag = action ? 'button' : 'div';
  return `<${tag} class="exam-card${action ? ' clickable' : ''}" style="--c:${color}" ${action ? data(action) : ''}>
    <div class="exam-card-top">
      <div class="exam-card-info">
        ${showsName ? `<div class="exam-card-name">${esc(exam.name)}</div>` : ''}
        <div class="muted">${esc(dateLine(exam))}</div>
        ${degreeTag(exam.degree, visibility)}
      </div>
      ${exam.tasks.length > 0 ? progressRing(L.progress(exam), color) : ''}
    </div>
    ${countdown}
    <div class="footnote muted">${tasksLine}</div>
  </${tag}>`;
}

/** Riga compatta di un esame in arrivo: barra colorata, nome, giorni e avanzamento. */
export function upcomingRow(exam, { today, visibility, selected, action }) {
  const days = L.daysRemaining(exam, today);
  const color = L.examColor(exam);
  return `<button class="row exam-row${selected ? ' selected' : ''}" ${data(action)} ${data({ ctx: 'exam', exam: exam.id })}>
    ${colorBar(color)}
    <span class="row-main">
      <span class="row-title">${esc(exam.name)}</span>
      <span class="row-sub">${exam.isScheduled ? italianShort(exam.date) : 'Da programmare'} ${degreeTag(exam.degree, visibility)}</span>
    </span>
    <span class="row-trailing">
      ${exam.isScheduled ? countdownText(days, L.countdownColor(days, color), false) : ''}
      ${exam.tasks.length > 0 ? `<span class="mini-progress"><span class="bar"><span style="width:${L.progressPercent(exam)}%;background:${color}"></span></span>${L.progressPercent(exam)}%</span>` : ''}
    </span>
  </button>`;
}

/** Riga di un esame passato, con l'esito in un badge. */
export function pastRow(exam, { selected, action }) {
  return `<button class="row exam-row${selected ? ' selected' : ''}" ${data(action)} ${data({ ctx: 'exam', exam: exam.id })}>
    ${colorBar(L.examColor(exam))}
    <span class="row-main">
      <span class="row-title">${esc(exam.name)}</span>
      <span class="row-sub">${italianShort(exam.date)}</span>
    </span>
    ${gradeBadge(exam)}
  </button>`;
}

/** Avviso con i task in ritardo e il pulsante per ridistribuirli fino all'esame. */
export function rescheduleBanner(count, examIDs) {
  return `<div class="banner danger">
    ${icon('clock')}
    <div class="banner-text">
      <strong>${count === 1 ? '1 task in ritardo' : `${count} task in ritardo`}</strong>
      <span>Ridistribuiscili da oggi fino all'esame.</span>
    </div>
    <button class="btn prominent danger" ${data({ action: 'reschedule', exams: examIDs.join(',') })}>Ripianifica</button>
  </div>`;
}

/**
 * Un task da spuntare: il cerchio lo spunta, il resto apre l'esame (o il form, nel dettaglio).
 * `showsExam`: mostra il nome dell'esame, per le liste che mescolano più esami ("Oggi").
 */
export function taskRow(task, exam, { today, large = false, showsDate = false, draggable = false, open = 'exam', showsExam = false }) {
  const overdue = L.isOverdue(task, today);
  const examColor = L.examColor(exam);
  const color = overdue ? C.danger : examColor;
  const openAction = open === 'edit'
    ? { action: 'edit-task', exam: exam.id, task: task.id }
    : { action: 'open-exam', exam: exam.id };
  const meta = [];
  if (showsExam) meta.push(`<span class="exam-name">${esc(exam.name)}</span>`);
  const label = L.subtaskLabel(task);
  if (label) meta.push(`<span class="sub-count">${icon('checklist')}${label}</span>`);
  if (overdue) meta.push(`<span class="danger">In ritardo, scadeva il ${italianShort(task.dueDate)}</span>`);
  return `<div class="task-row${large ? ' large' : ''}${task.isDone ? ' done' : ''}" style="--c:${examColor}" ${data({ ctx: 'task', exam: exam.id, task: task.id })}
      ${draggable ? `draggable="true" ${data({ drag: `${exam.id}|${task.id}` })}` : ''}>
    <button class="check-button" ${data({ action: 'toggle-task', exam: exam.id, task: task.id })}
      title="${task.isDone ? 'Segna come da fare' : 'Segna come fatto'}">${checkCircle(task.isDone, color)}</button>
    <button class="task-text" ${data(openAction)}>
      <span class="task-title">${esc(task.title)}</span>
      ${meta.length ? `<span class="task-meta">${meta.join('')}</span>` : ''}
    </button>
    ${showsDate ? `<span class="task-date">${italianShort(task.dueDate)}</span>` : ''}
  </div>`;
}

export function emptyState(iconName, title, description, button = '') {
  return `<div class="empty-state">${icon(iconName)}<h3>${esc(title)}</h3><p>${esc(description)}</p>${button}</div>`;
}

export function sectionHeader(title, trailing = '') {
  return `<div class="section-header"><h2>${esc(title)}</h2>${trailing}</div>`;
}

/** Interruttore a capsule (Triennale / Magistrale). */
export function segmented(options, selected, action, extra = {}) {
  return `<div class="segmented">${options.map(([value, label]) =>
    `<button class="${value === selected ? 'selected' : ''}" ${data({ action, value, ...extra })}>${esc(label)}</button>`).join('')}</div>`;
}

export function toggle(checked, attributes) {
  return `<label class="switch"><input type="checkbox" ${checked ? 'checked' : ''} ${data(attributes)}><span></span></label>`;
}
