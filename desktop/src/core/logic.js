// Calcoli sugli esami: countdown, agenda, carriera, simulazione, piano di studio.
// Porta in JavaScript ExamsCore dell'app iOS, con gli stessi nomi dove possibile.

import { addDays, atTime, dayDiff, isoOf, noon, startOfDay } from './calendar.js';
import { newUUID } from './codec.js';

export const DEFAULT_CFU = 6;
export const THESIS_CFU = 20;
export const TRIENNALE_CFU = 180;
/** CFU degli insegnamenti della magistrale: 120 meno i 20 della tesi, che non ha un voto. */
export const MAGISTRALE_COURSE_CFU = 100;

export const DEGREES = ['triennale', 'magistrale'];
export const degreeLabel = (degree) => (degree === 'magistrale' ? 'Magistrale' : 'Triennale');

// MARK: Ordinamenti

export function compare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Confronta coppie in ordine, come le tuple di Swift: `compareBy([a1, b1], [a2, b2])`. */
export function compareBy(...pairs) {
  for (const [a, b] of pairs) {
    const result = compare(a, b);
    if (result !== 0) return result;
  }
  return 0;
}

/** Come `localizedStandardCompare`: senza maiuscole, con i numeri in ordine numerico. */
export const standardCompare = (a, b) => a.localeCompare(b, 'it', { numeric: true, sensitivity: 'base' });

// MARK: Creazione

export function makeTask({ id = newUUID(), title, dueDate, isDone = false, subtasks = [] }) {
  return { id, title, dueDate: isoOf(dueDate), isDone, subtasks };
}

export function makeSubtask({ id = newUUID(), title, isDone = false }) {
  return { id, title, isDone };
}

/** Quanto è fatto un task (0...1): 1 se fatto, altrimenti la frazione di sotto-task fatti. */
export function taskCompletion(task) {
  if (task.isDone) return 1;
  const subtasks = task.subtasks ?? [];
  return subtasks.length === 0 ? 0 : subtasks.filter((sub) => sub.isDone).length / subtasks.length;
}

/** "2/3"; null senza sotto-task. */
export function subtaskLabel(task) {
  const subtasks = task.subtasks ?? [];
  return subtasks.length === 0 ? null : `${subtasks.filter((sub) => sub.isDone).length}/${subtasks.length}`;
}

export function makeExam({
  id = newUUID(), name, date, tasks = [], passed = null, grade = null, honors = false, degree = 'triennale',
  cfu = DEFAULT_CFU, isFinalTest = false, thesisPoints = null, isScheduled = true, startTime = null,
  colorIndex = null, modifiedAt = null, simulatedGrade = null, simulationModifiedAt = null, notes = '',
}) {
  return {
    id, name, date: isoOf(date), tasks, passed, grade, honors, degree, cfu, isFinalTest, thesisPoints,
    isScheduled, startTime, colorIndex, modifiedAt: modifiedAt && isoOf(modifiedAt), simulatedGrade,
    simulationModifiedAt: simulationModifiedAt && isoOf(simulationModifiedAt), notes,
  };
}

// MARK: Esame singolo

export function daysRemaining(exam, today) {
  return dayDiff(today, exam.date);
}

/** Da sostenere: esame non ancora programmato, oppure con data oggi o futura. */
export function isActive(exam, today) {
  return !exam.isScheduled || daysRemaining(exam, today) >= 0;
}

export const completedTaskCount = (exam) => exam.tasks.filter((task) => task.isDone).length;

/** Ogni task vale uno; quelli con sotto-task in parte fatti valgono la loro frazione. */
export function progress(exam) {
  return exam.tasks.length === 0 ? 0 : exam.tasks.reduce((sum, task) => sum + taskCompletion(task), 0) / exam.tasks.length;
}

export const progressPercent = (exam) => Math.round(progress(exam) * 100);

export function sortedTasks(exam) {
  return [...exam.tasks].sort((a, b) => compareBy([a.dueDate, b.dueDate], [a.title, b.title]));
}

export function isOverdue(task, today) {
  return !task.isDone && dayDiff(today, task.dueDate) < 0;
}

export function overdueCount(exam, today) {
  return exam.tasks.filter((task) => isOverdue(task, today)).length;
}

/** La tesi magistrale: si valuta con un punteggio bonus, non con un voto. */
export const isMasterThesis = (exam) => exam.degree === 'magistrale' && exam.isFinalTest;

/** Voto valido per la media: 30 e lode conta 30; la tesi magistrale non ha voto. */
export function countedGrade(exam) {
  return exam.passed === true && !isMasterThesis(exam) ? exam.grade : null;
}

/** "+5", "+5,5", "−1"; null senza punteggio. */
export function thesisPointsLabel(exam) {
  if (exam.thesisPoints === null || exam.thesisPoints === undefined) return null;
  const magnitude = Math.abs(exam.thesisPoints);
  const number = Number.isInteger(magnitude) ? String(magnitude) : magnitude.toFixed(1).replace('.', ',');
  return (exam.thesisPoints < 0 ? '−' : '+') + number;
}

export function outcomeLabel(exam) {
  if (exam.passed === null) return 'Esito da inserire';
  if (exam.passed === false) return 'Non superato';
  if (isMasterThesis(exam)) {
    const points = thesisPointsLabel(exam);
    if (!points) return 'Superato';
    return `Superato, ${points} ${Math.abs(exam.thesisPoints) === 1 ? 'punto' : 'punti'}`;
  }
  if (exam.grade === null) return 'Superato';
  return exam.honors && exam.grade === 30 ? 'Superato 30L' : `Superato ${exam.grade}`;
}

/** Riconosce dal nome una prova finale (triennale) o la tesi (magistrale). */
export function looksLikeFinalTest(name, degree = 'triennale') {
  const lower = name.toLowerCase();
  return degree === 'magistrale' ? lower.includes('tesi') || lower.includes('thesis') : lower.includes('prova finale');
}

/** Si può simulare un voto solo per esami senza voto vero; la tesi magistrale ha un punteggio. */
export const isSimulatable = (exam) => countedGrade(exam) === null && !isMasterThesis(exam);

// MARK: Orario di inizio

export function startDate(exam) {
  if (exam.startTime === null || exam.startTime === undefined) return null;
  return atTime(exam.date, Math.floor(exam.startTime / 60), exam.startTime % 60);
}

/** "14:30", oppure null se l'esame non ha un orario. */
export function startTimeLabel(exam) {
  if (exam.startTime === null || exam.startTime === undefined) return null;
  return `${Math.floor(exam.startTime / 60)}:${String(exam.startTime % 60).padStart(2, '0')}`;
}

/** Tempo reale che manca all'inizio; null senza orario o per esami non programmati. */
export function preciseCountdown(exam, now) {
  const start = exam.isScheduled ? startDate(exam) : null;
  if (!start) return null;
  if (now >= start) return { kind: 'started' };

  let days = dayDiff(now, start);
  if (addDays(now, days) > start) days -= 1;
  const rest = start.getTime() - addDays(now, days).getTime();
  const hours = Math.floor(rest / 3_600_000);
  const minutes = Math.floor((rest % 3_600_000) / 60_000);

  if (days > 0) {
    return { kind: 'remaining', value: days, unit: days === 1 ? 'giorno' : 'giorni',
      detail: hours > 0 ? `e ${hours} ${hours === 1 ? 'ora' : 'ore'}` : null };
  }
  if (hours > 0) {
    return { kind: 'remaining', value: hours, unit: hours === 1 ? 'ora' : 'ore',
      detail: minutes > 0 ? `e ${minutes} ${minutes === 1 ? 'minuto' : 'minuti'}` : null };
  }
  if (minutes > 0) return { kind: 'remaining', value: minutes, unit: minutes === 1 ? 'minuto' : 'minuti', detail: null };
  return { kind: 'lessThanAMinute' };
}

/** Posizione del segnaposto "Oggi" tra i task ordinati; null se l'esame è già passato. */
export function todayMarkerIndex(exam, today) {
  if (!isActive(exam, today)) return null;
  const tasks = sortedTasks(exam);
  const index = tasks.findIndex((task) => dayDiff(today, task.dueDate) >= 0);
  return index === -1 ? tasks.length : index;
}

/** 'urgent' (≤ 2 giorni), 'soon' (≤ 7), 'calm'. */
export function urgency(days) {
  if (days <= 2) return 'urgent';
  if (days <= 7) return 'soon';
  return 'calm';
}

export const Countdown = {
  label: (days) => (days < 0 ? 'Passato' : days === 0 ? 'Oggi' : days === 1 ? 'Domani' : `tra ${days} giorni`),
  shortLabel: (days) => (days < 0 ? 'Passato' : days === 0 ? 'Oggi' : days === 1 ? 'Domani' : `${days} giorni`),
};

// MARK: Elenchi di esami

export function visible(exams, visibility) {
  return visibility === 'both' ? exams : exams.filter((exam) => exam.degree === visibility);
}

/** Da sostenere: prima i programmati per data (poi nome), in fondo i non programmati in ordine alfabetico. */
export function active(exams, today) {
  const pending = exams.filter((exam) => isActive(exam, today));
  const scheduled = pending.filter((exam) => exam.isScheduled)
    .sort((a, b) => compareBy([a.date, b.date], [a.name, b.name]));
  const unscheduled = pending.filter((exam) => !exam.isScheduled)
    .sort((a, b) => standardCompare(a.name, b.name) || compare(a.id, b.id));
  return [...scheduled, ...unscheduled];
}

/** Esami passati, dal più recente. */
export function archived(exams, today) {
  return exams.filter((exam) => !isActive(exam, today)).sort((a, b) => compare(b.date, a.date));
}

export function career(exams, degree, today) {
  return archived(exams, today).filter((exam) => exam.degree === degree);
}

/** Prossimo esame con una data: quelli non programmati non hanno countdown. */
export function nextExam(exams, today) {
  return active(exams, today).find((exam) => exam.isScheduled) ?? null;
}

/** Testo normalizzato per la ricerca: minuscolo e senza accenti. */
function searchKey(text) {
  return text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

/** Esami con tutte le parole cercate nel nome, nelle note o nei titoli dei task. */
export function matching(exams, query) {
  const words = query.split(/\s+/).filter(Boolean).map(searchKey);
  if (words.length === 0) return exams;
  return exams.filter((exam) => {
    const haystack = searchKey([exam.name, exam.notes, ...exam.tasks.map((task) => task.title)].join('\n'));
    return words.every((word) => haystack.includes(word));
  });
}

/** Ordine degli esami sostenuti nella scheda Carriera. */
export const CAREER_SORTS = { date: 'Data', grade: 'Voto', cfu: 'CFU' };

export function sortedForCareer(exams, sort) {
  const list = [...exams];
  if (sort === 'grade') {
    // 30 e lode sopra il 30; senza voto in fondo; a parità, il più recente.
    const key = (exam) => {
      const grade = countedGrade(exam);
      if (grade === null) return -1;
      return exam.honors ? grade + 1 : grade;
    };
    return list.sort((a, b) => compareBy([key(b), key(a)], [b.date, a.date]));
  }
  if (sort === 'cfu') return list.sort((a, b) => compareBy([b.cfu, a.cfu], [a.name, b.name]));
  return list.sort((a, b) => compareBy([b.date, a.date], [a.name, b.name]));
}

// MARK: Agenda e "Oggi"

const agendaItem = (exam, task) => ({ examID: exam.id, examName: exam.name, colorIndex: exam.colorIndex ?? 0, task });
export const AGENDA_DAYS = 7;

/**
 * Cosa c'è da fare oggi e nei prossimi giorni, su tutti gli esami da sostenere (come `Agenda` in ExamsCore):
 * in ritardo, di oggi (prima da fare, poi fatti), i prossimi 7 giorni da domani (anche vuoti) e più avanti.
 */
export function agenda(exams, today) {
  const items = active(exams, today).flatMap((exam) => exam.tasks.map((task) => agendaItem(exam, task)));
  items.sort((a, b) => compareBy([a.task.dueDate, b.task.dueDate], [a.examName, b.examName], [a.task.title, b.task.title]));
  const on = (day) => {
    const ofDay = items.filter((item) => dayDiff(day, item.task.dueDate) === 0);
    return [...ofDay.filter((item) => !item.task.isDone), ...ofDay.filter((item) => item.task.isDone)];
  };
  const start = startOfDay(today);
  const days = Array.from({ length: AGENDA_DAYS }, (_, i) => addDays(start, i + 1));
  const lastDay = days.at(-1);
  return {
    overdue: items.filter((item) => isOverdue(item.task, today)),
    dueToday: on(start),
    days: days.map((day) => ({ date: noon(day), items: on(day) })),
    later: items.filter((item) => !item.task.isDone && dayDiff(lastDay, item.task.dueDate) > 0),
  };
}

/** "Oggi" a due colonne: prossimo esame e agenda di tutti gli esami a sinistra, gli altri esami a destra. */
export function todayBoard(exams, today) {
  const next = nextExam(exams, today);
  return {
    next,
    agenda: agenda(exams, today),
    others: active(exams, today).filter((exam) => exam.id !== next?.id),
  };
}

// MARK: Sessione di studio

/** Durate proposte (minuti); con "Altra durata…" se ne sceglie una qualsiasi tra 5 e 180. */
export const STUDY_DURATIONS = [25, 50];
export const STUDY_RANGE = { min: 5, max: 180 };
export const STUDY_EXTRA_MINUTES = 10;

/** Su cosa studiare se non si sceglie: il primo task da fare in ritardo o di oggi, altrimenti il prossimo esame. */
export function studySuggestion(exams, today) {
  const { overdue, dueToday } = agenda(exams, today);
  const item = [...overdue, ...dueToday].find((entry) => !entry.task.isDone);
  if (item) {
    return { examID: item.examID, examName: item.examName, colorIndex: item.colorIndex, taskID: item.task.id, taskTitle: item.task.title };
  }
  const next = nextExam(exams, today);
  return next ? { examID: next.id, examName: next.name, colorIndex: next.colorIndex ?? 0, taskID: null, taskTitle: null } : null;
}

// MARK: Carriera

function weightedAverageOf(exams) {
  let points = 0;
  let credits = 0;
  for (const exam of exams) {
    const grade = countedGrade(exam);
    if (grade === null) continue;
    points += grade * exam.cfu;
    credits += exam.cfu;
  }
  return credits > 0 ? points / credits : null;
}

/** Media dei voti pesata sui CFU di un corso; null se non ci sono voti. */
export function weightedAverage(exams, degree) {
  return weightedAverageOf(exams.filter((exam) => exam.degree === degree));
}

export function earnedCFU(exams, degree) {
  return exams.filter((exam) => exam.degree === degree && exam.passed === true).reduce((sum, exam) => sum + exam.cfu, 0);
}

function missingCFU(exams, degree, total) {
  const graded = exams.filter((exam) => exam.degree === degree && countedGrade(exam) !== null)
    .reduce((sum, exam) => sum + exam.cfu, 0);
  return Math.max(0, total - graded);
}

export const missingGraduationCFU = (exams) => missingCFU(exams, 'triennale', TRIENNALE_CFU);
export const missingMasterCFU = (exams) => missingCFU(exams, 'magistrale', MAGISTRALE_COURSE_CFU);

/** Media pesata supponendo 18 (minimo) o 30 (massimo) nei CFU mancanti; null senza voti. */
function averageRange(exams, missing) {
  const graded = exams.filter((exam) => countedGrade(exam) !== null);
  if (graded.length === 0) return null;
  const points = graded.reduce((sum, exam) => sum + countedGrade(exam) * exam.cfu, 0);
  const total = graded.reduce((sum, exam) => sum + exam.cfu, 0) + missing;
  return { low: (points + 18 * missing) / total, high: (points + 30 * missing) / total };
}

function estimate(minimum, maximum, exams, honorsAllowed) {
  const honorsCount = exams.filter((exam) => exam.passed === true && exam.honors && !isMasterThesis(exam)).length;
  const threshold = Math.max(113 - 0.5 * honorsCount, 111);
  return {
    // Il voto minimo di laurea è comunque 66.
    minimum: Math.max(minimum, 66),
    maximum: Math.max(maximum, 66),
    honorsThreshold: threshold,
    canGetHonors: honorsAllowed && maximum >= threshold,
  };
}

/** Voto di laurea triennale: media × 110/30 + 1 + media delle prove finali / 6. */
export function graduationEstimate(exams) {
  const triennale = exams.filter((exam) => exam.degree === 'triennale');
  const range = averageRange(triennale, missingGraduationCFU(exams));
  if (!range) return null;
  const finalTests = weightedAverageOf(triennale.filter((exam) => exam.isFinalTest));
  return estimate(
    (range.low * 110) / 30 + 1 + (finalTests ?? 18) / 6,
    (range.high * 110) / 30 + 1 + (finalTests ?? 30) / 6,
    triennale,
    true,
  );
}

export const THESIS_TYPES = {
  withReviewer: { label: 'Con controrelatore', maximumPoints: 7 },
  withoutReviewer: { label: 'Senza controrelatore', maximumPoints: 4 },
};
export const THESIS_MINIMUM_POINTS = -1;

/** Voto di laurea magistrale: media degli insegnamenti × 110/30 + punti della tesi. */
export function masterGraduationEstimate(exams, thesis) {
  const magistrale = exams.filter((exam) => exam.degree === 'magistrale');
  const range = averageRange(magistrale, missingMasterCFU(exams));
  if (!range) return null;
  const assigned = magistrale.find((exam) => isMasterThesis(exam) && exam.passed === true && exam.thesisPoints !== null)?.thesisPoints;
  return estimate(
    (range.low * 110) / 30 + (assigned ?? THESIS_MINIMUM_POINTS),
    (range.high * 110) / 30 + (assigned ?? THESIS_TYPES[thesis].maximumPoints),
    magistrale,
    // La lode alla magistrale richiede la tesi con controrelatore.
    thesis === 'withReviewer',
  );
}

export function estimateFor(exams, degree, thesis) {
  return degree === 'triennale' ? graduationEstimate(exams) : masterGraduationEstimate(exams, thesis);
}

/** Voto in centodecimi arrotondato ("98", "98–103", "110+"). */
export function gradeText(estimate) {
  const grade = (value) => (value >= 110.5 ? '110+' : String(Math.round(value)));
  const low = grade(estimate.minimum);
  const high = grade(estimate.maximum);
  return low === high ? low : `${low}–${high}`;
}

/** "27,45" oppure "—". */
export function averageText(average) {
  return average === null || average === undefined
    ? '—'
    : average.toLocaleString('it-IT', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Media pesata cumulativa dopo ogni esame superato del corso, in ordine di data. */
export function averageTrend(exams, degree) {
  const graded = exams.filter((exam) => exam.degree === degree && countedGrade(exam) !== null)
    .sort((a, b) => compareBy([a.date, b.date], [a.name, b.name]));
  let points = 0;
  let credits = 0;
  return graded.map((exam) => {
    const grade = countedGrade(exam);
    points += grade * exam.cfu;
    credits += exam.cfu;
    return { id: exam.id, date: exam.date, examName: exam.name, grade, average: points / Math.max(credits, 1) };
  });
}

// MARK: Simulazione

/** Gli esami come se i voti ipotetici fossero veri. */
export function applyingSimulation(exams) {
  return exams.map((exam) => {
    if (!isSimulatable(exam) || exam.simulatedGrade === null) return exam;
    return { ...exam, passed: true, grade: exam.simulatedGrade, honors: false };
  });
}

/** Media con i voti veri più quelli ipotetici; null se nel corso non c'è nessuna simulazione. */
export function simulatedAverage(exams, degree) {
  if (!exams.some((exam) => exam.degree === degree && isSimulatable(exam) && exam.simulatedGrade !== null)) return null;
  return weightedAverage(applyingSimulation(exams), degree);
}

// MARK: Dati del form d'esame

export const DETAIL_FIELDS = ['name', 'date', 'degree', 'cfu', 'isFinalTest', 'isScheduled', 'startTime'];

export function examDetails(exam) {
  return Object.fromEntries(DETAIL_FIELDS.map((field) => [field, exam[field]]));
}

/** Prende dal form solo i campi cambiati rispetto all'apertura; gli altri dalla versione più recente. */
export function mergeDetails(original, edited, latest) {
  return Object.fromEntries(DETAIL_FIELDS.map((field) => [
    field, edited[field] !== original[field] ? edited[field] : latest[field],
  ]));
}

// MARK: Piano di studio

export const REVIEW_TITLE = 'Ripasso generale';

/** Un task per argomento distribuito fino a prima dei giorni di ripasso, più un "Ripasso generale". */
export function planStudy(topics, start, end, reviewDays) {
  const titles = topics.map((topic) => topic.trim()).filter(Boolean);
  const startDay = startOfDay(start);
  const endDay = startOfDay(end);
  const day = (offset) => noon(addDays(startDay, offset));

  const lastStudyDay = addDays(endDay, -(Math.max(reviewDays, 0) + 1));
  const studyDays = Math.max(1, dayDiff(startDay, lastStudyDay) + 1);

  const tasks = titles.map((title, index) => {
    const position = ((index + 1) * studyDays) / titles.length;
    return makeTask({ title, dueDate: day(Math.max(0, Math.ceil(position) - 1)) });
  });
  if (reviewDays > 0) {
    tasks.push(makeTask({ title: REVIEW_TITLE, dueDate: day(Math.max(0, dayDiff(startDay, endDay) - 1)) }));
  }
  return tasks;
}

/** I task con quelli in ritardo ridistribuiti da oggi al giorno prima dell'esame (o sui prossimi 7 giorni). */
export function rescheduleOverdue(exam, today) {
  const overdue = sortedTasks(exam).filter((task) => isOverdue(task, today));
  if (overdue.length === 0) return exam.tasks;

  const startDay = startOfDay(today);
  let lastDay;
  if (exam.isScheduled) {
    const dayBeforeExam = addDays(startOfDay(exam.date), -1);
    lastDay = dayBeforeExam > startDay ? dayBeforeExam : startDay;
  } else {
    lastDay = addDays(startDay, 6);
  }
  const days = dayDiff(startDay, lastDay) + 1;

  const newDates = new Map();
  overdue.forEach((task, index) => {
    const offset = Math.floor((index * days) / overdue.length);
    newDates.set(task.id, isoOf(noon(addDays(startDay, offset))));
  });
  return exam.tasks.map((task) => (newDates.has(task.id) ? { ...task, dueDate: newDates.get(task.id) } : task));
}

// MARK: Colori

/** Tema "inchiostro e evidenziatore", lo stesso dell'app iOS. */
export const PALETTE = {
  background: '#0F1728', // inchiostro
  surface: '#172238',    // carta di notte
  elevated: '#1D2A42',
  stroke: '#26324A',     // filetti
  textPrimary: '#ECE8DD', // carta
  textSecondary: '#93A0B8', // matita
  accent: '#8FB0FF',     // penna blu
  success: '#5BD6A0',
  warning: '#F6B94A',
  danger: '#FF7D8E',
  gold: '#F5CB45',
  chartLine: '#86A6F5',
};

/** Colori degli esami, tinte da evidenziatore (stesso ordine dell'app iOS: l'indice è salvato negli esami). */
export const EXAM_COLORS = [
  '#9AA5FF', '#4FE3A6', '#FF9F5A', '#5CCBFF', '#F08CFF', '#C6F24E', '#B59CFF',
  '#3EE6CF', '#FFD15C', '#76AEFF', '#FF8FC8', '#6EEB8E', '#D39BFF', '#45E0F2',
];

/** Colore per un nuovo esame: il meno usato; a parità, il primo nell'ordine della tavolozza. */
export function balancedColorIndex(used) {
  const counts = EXAM_COLORS.map(() => 0);
  for (const index of used) {
    if (index >= 0 && index < counts.length) counts[index] += 1;
  }
  return counts.indexOf(Math.min(...counts));
}

export function examColor(exam) {
  return colorAt(exam.colorIndex);
}

export function colorAt(index) {
  const i = index ?? 0;
  return EXAM_COLORS[((i % EXAM_COLORS.length) + EXAM_COLORS.length) % EXAM_COLORS.length];
}

/** Colore del countdown: quello dell'esame finché c'è tempo, poi ambra e corallo. */
export function countdownColor(days, color) {
  const level = urgency(days);
  return level === 'calm' ? color : level === 'soon' ? PALETTE.warning : PALETTE.danger;
}
