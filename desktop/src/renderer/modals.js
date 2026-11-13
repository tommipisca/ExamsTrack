// Finestre sopra la scheda: form di esami e task, note, piano di studio, simulazione, conferme.
// Lo stato di ogni finestra vive nell'oggetto `modal`; i campi con data-model lo aggiornano.

import * as L from '../core/logic.js';
import { addDays, dayKey, fromDayKey, italianShort, startOfDay } from '../core/calendar.js';
import { C, data, esc, colorBar, segmented, toggle } from './components.js';
import { icon, checkCircle } from './icons.js';

// MARK: Apertura

export function examFormModal(store, exam, visibility) {
  const minutes = exam?.startTime ?? 9 * 60;
  return {
    type: 'exam',
    examID: exam?.id ?? null,
    original: exam ? L.examDetails(exam) : null,
    name: exam?.name ?? '',
    day: dayKey(exam ? exam.date : addDays(new Date(), 30)),
    isScheduled: exam?.isScheduled ?? true,
    hasStartTime: exam ? exam.startTime !== null : false,
    time: `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`,
    degree: exam?.degree ?? (visibility !== 'both' ? visibility : store.defaultDegree),
    cfu: exam?.cfu ?? L.DEFAULT_CFU,
    /** null finché non si tocca l'interruttore: si deduce dal nome ("prova finale"). */
    chosenFinalTest: exam ? exam.isFinalTest : null,
    colorIndex: exam?.colorIndex ?? store.nextColorIndex,
  };
}

export function isFinalTestOf(modal) {
  return modal.chosenFinalTest ?? L.looksLikeFinalTest(modal.name, modal.degree);
}

export function taskFormModal(exam, task) {
  const today = startOfDay(new Date());
  const max = exam.isScheduled ? dayKey(exam.date) : null;
  const fallback = max && fromDayKey(max) < today ? fromDayKey(max) : today;
  return {
    type: 'task',
    examID: exam.id,
    taskID: task?.id ?? null,
    title: task?.title ?? '',
    due: dayKey(task ? task.dueDate : fallback),
    max,
    /** Voci della checklist in modifica: quelle esistenti tengono id e stato. */
    subtasks: (task?.subtasks ?? []).map((sub) => ({ ...sub })),
  };
}

/** Nuovo task da "Oggi", scegliendo l'esame al volo; scadenza oggi. */
export function quickTaskModal(exams, today) {
  const examID = (L.nextExam(exams, today) ?? exams[0])?.id ?? null;
  return { type: 'quick-task', examID, title: '', due: dayKey(today), subtasks: [] };
}

/** Durata di una sessione di studio, a passi di 5 minuti. */
export function studyModal(target, lastMinutes) {
  const minutes = Math.min(Math.max(Math.round(lastMinutes / 5) * 5, L.STUDY_RANGE.min), L.STUDY_RANGE.max);
  return { type: 'study', target, minutes: String(minutes) };
}

/** "45 minuti", "1 ora e 30 minuti". */
export function minutesLabel(minutes) {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) return `${minutes} minuti`;
  const hourText = hours === 1 ? '1 ora' : `${hours} ore`;
  return rest === 0 ? hourText : `${hourText} e ${rest} minuti`;
}

export function plannerModal(exam) {
  return {
    type: 'planner',
    examID: exam.id,
    topics: '',
    start: dayKey(new Date()),
    deadline: dayKey(exam.isScheduled ? exam.date : addDays(new Date(), 30)),
    isScheduled: exam.isScheduled,
    reviewDays: 2,
  };
}

export function plannerPreview(modal) {
  return L.planStudy(modal.topics.split(/\r?\n/), fromDayKey(modal.start), fromDayKey(modal.deadline), modal.reviewDays);
}

// MARK: Disegno

function shell(title, body, { confirm = null, cancel = 'Annulla', wide = false } = {}) {
  return `<div class="modal${wide ? ' wide' : ''}" role="dialog" aria-modal="true">
    <header class="modal-header">
      <button class="link" data-action="modal-cancel">${esc(cancel)}</button>
      <h2>${esc(title)}</h2>
      ${confirm ? `<button class="link strong" data-action="modal-confirm" ${confirm.disabled ? 'disabled' : ''}>${esc(confirm.label)}</button>` : '<span></span>'}
    </header>
    <div class="modal-body">${body}</div>
  </div>`;
}

function row(label, control) {
  return `<div class="form-row"><span>${esc(label)}</span>${control}</div>`;
}

function stepper(field, value, min, max) {
  return `<span class="stepper"><button ${data({ action: 'modal-step', field, delta: -1, min, max })}>−</button><b>${value}</b><button ${data({ action: 'modal-step', field, delta: 1, min, max })}>+</button></span>`;
}

export function renderModal(modal, ctx) {
  switch (modal.type) {
    case 'exam': return examForm(modal, ctx);
    case 'task': return taskForm(modal);
    case 'quick-task': return quickTaskForm(modal, ctx);
    case 'study': return studyForm(modal);
    case 'notes': return notesForm(modal, ctx);
    case 'planner': return plannerForm(modal);
    case 'simulation': return simulation(modal, ctx);
    case 'confirm':
      return `<div class="modal small" role="alertdialog" aria-modal="true"><div class="modal-body center-text">
        <h2>${esc(modal.title)}</h2><p class="muted">${esc(modal.message)}</p>
        <div class="dialog-buttons"><button class="btn" data-action="modal-cancel">Annulla</button>
        <button class="btn prominent ${modal.destructive ? 'danger' : ''}" data-action="modal-confirm">${esc(modal.confirmLabel)}</button></div>
      </div></div>`;
    case 'alert':
      return `<div class="modal small" role="alertdialog" aria-modal="true"><div class="modal-body center-text">
        <h2>${esc(modal.title)}</h2><p class="muted">${esc(modal.message)}</p>
        <div class="dialog-buttons"><button class="btn prominent" data-action="modal-cancel">OK</button></div>
      </div></div>`;
    default: return '';
  }
}

function examForm(modal, ctx) {
  const finalTest = isFinalTestOf(modal);
  const body = `<div class="card form">
      <div class="form-row">${colorBar(L.colorAt(modal.colorIndex))}<input class="title-input" id="modal-first" type="text" placeholder="Nome esame, es. Analisi 1" value="${esc(modal.name)}" data-model="name"></div>
      ${row('Programmato', toggle(modal.isScheduled, { model: 'isScheduled', rerender: 1 }))}
      ${modal.isScheduled ? row("Data dell'esame", `<input type="date" value="${modal.day}" data-model="day">`)
        + row('Orario', toggle(modal.hasStartTime, { model: 'hasStartTime', rerender: 1 }))
        + (modal.hasStartTime ? row('Inizio', `<input type="time" value="${modal.time}" data-model="time">`) : '') : ''}
      ${ctx.visibility === 'both' ? `<div class="form-row">${segmented(L.DEGREES.map((d) => [d, L.degreeLabel(d)]), modal.degree, 'modal-degree')}</div>` : ''}
    </div>
    <p class="footer-note">Ogni esame ha un suo colore, usato in lista e nella timeline.</p>
    <div class="card form">
      ${row('CFU', stepper('cfu', modal.cfu, 1, 30))}
      ${row(modal.degree === 'magistrale' ? 'Tesi' : 'Prova finale', toggle(finalTest, { model: 'chosenFinalTest', rerender: 1 }))}
    </div>
    <p class="footer-note">${modal.degree === 'magistrale'
      ? 'I CFU pesano il voto nella media. La tesi non ha un voto: riceve un punteggio da −1 a +8 che si somma alla media.'
      : 'I CFU pesano il voto nella media. Le prove finali danno i punti bonus del voto di laurea.'}</p>`;
  return shell(modal.examID ? 'Modifica esame' : 'Nuovo esame', body, { confirm: { label: 'Salva', disabled: !modal.name.trim() } });
}

/** La checklist del task: voci da spuntare, rinominare o togliere. */
function subtaskEditor(modal) {
  const rows = modal.subtasks.map((sub, index) => `<div class="form-row subtask-editor">
      <button class="check-button" ${data({ action: 'modal-toggle-subtask', index })} title="${sub.isDone ? 'Segna da fare' : 'Segna fatta'}">${checkCircle(sub.isDone, sub.isDone ? C.success : C.textSecondary)}</button>
      <input type="text" placeholder="Voce, es. Esercizi" value="${esc(sub.title)}" ${data({ subtask: index })}>
      <button class="icon-button danger" title="Togli la voce" ${data({ action: 'modal-remove-subtask', index })}>${icon('minus')}</button>
    </div>`).join('');
  return `<h3 class="form-title">Sotto-task</h3>
    <div class="card form">${rows}
      <div class="form-row buttons"><button class="link" data-action="modal-add-subtask">${icon('plus')} Aggiungi voce</button></div>
    </div>
    <p class="footer-note">Facoltativi: una checklist del task. Il task è fatto quando lo sono tutte le voci, e quelle già fatte contano nell'avanzamento dell'esame.</p>`;
}

function taskForm(modal) {
  const body = `<div class="card form">
      <div class="form-row"><input class="title-input" id="modal-first" type="text" placeholder="Cosa devi fare, es. Ripasso capitoli 1-3" value="${esc(modal.title)}" data-model="title"></div>
      ${row('Entro il', `<input type="date" value="${modal.due}" ${modal.max ? `max="${modal.max}"` : ''} data-model="due">`)}
    </div>
    ${modal.max ? '<p class="footer-note">La scadenza non può superare il giorno dell\'esame.</p>' : ''}
    ${subtaskEditor(modal)}`;
  return shell(modal.taskID ? 'Modifica task' : 'Nuovo task', body, { confirm: { label: 'Salva', disabled: !modal.title.trim() } });
}

function quickTaskForm(modal, ctx) {
  const exams = L.active(L.visible(ctx.store.exams, ctx.visibility), ctx.today);
  const exam = exams.find((item) => item.id === modal.examID);
  const max = exam?.isScheduled ? dayKey(exam.date) : null;
  const body = `<div class="card form">
      ${row('Esame', `<select data-model="examID" data-rerender="1">${exams.map((item) =>
        `<option value="${item.id}" ${item.id === modal.examID ? 'selected' : ''}>${esc(item.name)}</option>`).join('')}</select>`)}
      <div class="form-row"><input class="title-input" id="modal-first" type="text" placeholder="Cosa devi fare, es. Ripasso capitoli 1-3" value="${esc(modal.title)}" data-model="title"></div>
      ${row('Entro il', `<input type="date" value="${modal.due}" ${max ? `max="${max}"` : ''} data-model="due">`)}
    </div>
    ${max ? '<p class="footer-note">La scadenza non può superare il giorno dell\'esame.</p>' : ''}`;
  return shell('Nuovo task', body, { confirm: { label: 'Salva', disabled: !modal.title.trim() || !exam } });
}

function studyForm(modal) {
  const { target } = modal;
  const options = [];
  for (let minutes = L.STUDY_RANGE.min; minutes <= L.STUDY_RANGE.max; minutes += 5) {
    options.push(`<option value="${minutes}" ${String(minutes) === modal.minutes ? 'selected' : ''}>${minutesLabel(minutes)}</option>`);
  }
  const body = `<div class="card form">
      <div class="form-row"><span><strong>${esc(target.taskTitle ?? target.examName)}</strong>
        ${target.taskTitle ? `<small style="color:${L.colorAt(target.colorIndex)}">${esc(target.examName)}</small>` : ''}</span></div>
      ${row('Durata', `<select id="modal-first" data-model="minutes">${options.join('')}</select>`)}
    </div>
    <p class="footer-note">Alla fine arriva una notifica di Windows; in "Oggi" scegli se segnare fatto il task, studiare altri ${L.STUDY_EXTRA_MINUTES} minuti o fare una pausa.</p>`;
  return shell('Sessione di studio', body, { confirm: { label: 'Avvia' } });
}

function notesForm(modal, ctx) {
  const exam = ctx.store.exam(modal.examID);
  const body = `<textarea id="modal-first" class="notes-editor" data-model="text" placeholder="Programma, materiale, modalità d'esame…">${esc(modal.text)}</textarea>`;
  return shell(`Note di ${exam?.name ?? ''}`, body, { confirm: { label: 'Salva' }, wide: true });
}

function plannerForm(modal) {
  const preview = plannerPreview(modal);
  const hasTopics = modal.topics.split(/\r?\n/).some((topic) => topic.trim());
  const body = `<h3 class="form-title">Argomenti</h3>
    <div class="card form"><textarea id="modal-first" class="topics" rows="6" data-model="topics" data-rerender="1" placeholder="Un argomento per riga, es.&#10;Limiti&#10;Derivate&#10;Integrali">${esc(modal.topics)}</textarea></div>
    <h3 class="form-title">Periodo</h3>
    <div class="card form">
      ${row('Inizio', `<input type="date" value="${modal.start}" max="${modal.deadline}" data-model="start" data-rerender="1">`)}
      ${modal.isScheduled ? '' : row('Entro il', `<input type="date" value="${modal.deadline}" min="${modal.start}" data-model="deadline" data-rerender="1">`)}
      ${row('Giorni di ripasso', stepper('reviewDays', modal.reviewDays, 0, 14))}
    </div>
    <p class="footer-note">${modal.isScheduled
      ? "Gli argomenti si distribuiscono fino all'esame, lasciando liberi gli ultimi giorni per il ripasso."
      : "L'esame non ha una data: scegli entro quando finire."}</p>
    ${preview.length ? `<h3 class="form-title">Anteprima: ${preview.length} task</h3>
      <div class="card form">${preview.map((task) => row(task.title, `<span class="muted">${italianShort(task.dueDate)}</span>`)).join('')}</div>` : ''}`;
  return shell('Pianifica lo studio', body, { confirm: { label: 'Crea task', disabled: !hasTopics }, wide: true });
}

function simulation(modal, ctx) {
  const { store, prefs } = ctx;
  const degree = modal.degree;
  const simulatedExams = L.applyingSimulation(store.exams);
  const estimate = L.estimateFor(simulatedExams, degree, prefs.get('thesisType'));
  const candidates = store.exams.filter((exam) => exam.degree === degree && L.isSimulatable(exam))
    .sort((a, b) => (a.isScheduled !== b.isScheduled ? (a.isScheduled ? -1 : 1) : L.compareBy([a.date, b.date], [a.name, b.name])));
  const hasSimulation = candidates.some((exam) => exam.simulatedGrade !== null);

  const rows = candidates.map((exam) => `<div class="form-row">
      <span class="sim-name">${colorBar(L.examColor(exam))}<span><strong>${esc(exam.name)}</strong><small class="muted">${exam.cfu} CFU</small></span></span>
      <select ${data({ change: 'simulated-grade', exam: exam.id })} style="color:${exam.simulatedGrade === null ? C.textSecondary : C.success}">
        <option value="">—</option>
        ${Array.from({ length: 13 }, (_, i) => 18 + i).map((grade) => `<option value="${grade}" ${grade === exam.simulatedGrade ? 'selected' : ''}>${grade}</option>`).join('')}
      </select></div>`).join('');

  const body = `<div class="card stats sim-summary">
      <div class="stat"><b style="color:${C.success}">${L.averageText(L.simulatedAverage(store.exams, degree))}</b><span>Media simulata</span></div>
      <div class="stat"><b style="color:${C.gold}">${estimate ? L.gradeText(estimate) : '—'}</b><span>Voto di laurea</span></div>
    </div>
    <p class="footer-note">Calcolati come se i voti ipotetici fossero veri. La media reale e la carriera non cambiano.</p>
    <h3 class="form-title">Esami senza voto</h3>
    <div class="card form">${rows || `<div class="form-row muted">Tutti gli esami della ${L.degreeLabel(degree).toLowerCase()} hanno già un voto.</div>`}</div>
    ${candidates.length ? '<p class="footer-note">Scegli un voto ipotetico per gli esami che vuoi simulare. Restano salvati (e sincronizzati) finché non li togli o registri il voto vero.</p>' : ''}
    ${hasSimulation ? `<div class="center"><button class="btn danger-text" ${data({ action: 'clear-simulation', value: degree })}>${icon('trash')} Azzera simulazione</button></div>` : ''}`;
  return shell(`Simulazione ${L.degreeLabel(degree).toLowerCase()}`, body, { cancel: 'Fine', wide: true });
}
