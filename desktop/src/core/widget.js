// Dati del widget sul desktop: gli stessi del widget "Prossimo esame" di iPhone e iPad
// (NextExamSummary.make e ExamEntityQuery in ExamsCore e nel widget iOS).

import { active, compareBy, completedTaskCount, daysRemaining, isOverdue, nextExam, progress, progressPercent } from './logic.js';

/** Task della lista "Da fare" (il widget ne mostra quanti ci stanno). */
export const WIDGET_TASK_LIMIT = 6;
/** Esami successivi al prossimo, come `NextExamSummary.followingExamLimit`. */
export const WIDGET_FOLLOWING_LIMIT = 12;
/** Un task spuntato dal widget resta barrato per 3 secondi, come `RecentlyCompleted.window`. */
export const WIDGET_RECENT_MS = 3000;

/**
 * Cosa mostra il widget, o null senza esami programmati.
 * `focusedExamID`: esame scelto nelle impostazioni; se è ancora da sostenere e programmato si mostra quello,
 * altrimenti il prossimo esame. `tasksFromAllExams`: i task di tutti gli esami da sostenere, o solo di quello
 * mostrato. `recentlyCompleted`: id dei task appena spuntati, da mostrare ancora barrati.
 */
export function widgetSummary(exams, today, { focusedExamID = null, tasksFromAllExams = false, recentlyCompleted = new Set() } = {}) {
  const pending = active(exams, today);
  const focused = focusedExamID ? pending.find((exam) => exam.id === focusedExamID && exam.isScheduled) : null;
  const exam = focused ?? nextExam(exams, today);
  if (!exam) return null;

  const open = (tasksFromAllExams ? pending : [exam])
    .flatMap((other) => other.tasks
      .filter((task) => !task.isDone || recentlyCompleted.has(task.id))
      .map((task) => ({ exam: other, task })))
    .sort((a, b) => compareBy([a.task.dueDate, b.task.dueDate], [a.exam.name, b.exam.name], [a.task.title, b.task.title]));

  return {
    examID: exam.id,
    name: exam.name,
    degree: exam.degree,
    daysRemaining: daysRemaining(exam, today),
    examDate: exam.date,
    progress: progress(exam),
    progressPercent: progressPercent(exam),
    hasTasks: exam.tasks.length > 0,
    completedTasks: completedTaskCount(exam),
    totalTasks: exam.tasks.length,
    colorIndex: exam.colorIndex ?? 0,
    upcomingTasks: open.slice(0, WIDGET_TASK_LIMIT).map(({ exam: other, task }) => ({
      examID: other.id,
      taskID: task.id,
      title: task.title,
      dueDate: task.dueDate,
      isOverdue: isOverdue(task, today),
      isDone: task.isDone,
      examName: other.name,
      colorIndex: other.colorIndex ?? 0,
    })),
    followingExams: pending
      .filter((other) => other.isScheduled && other.id !== exam.id)
      .slice(0, WIDGET_FOLLOWING_LIMIT)
      .map((other) => ({
        examID: other.id,
        name: other.name,
        daysRemaining: daysRemaining(other, today),
        colorIndex: other.colorIndex ?? 0,
        examDate: other.date,
        progress: progress(other),
        hasTasks: other.tasks.length > 0,
      })),
  };
}

/** Esami che si possono scegliere per il widget: da sostenere e programmati, dal più vicino. */
export function widgetExamChoices(exams, today) {
  return active(exams, today).filter((exam) => exam.isScheduled);
}
