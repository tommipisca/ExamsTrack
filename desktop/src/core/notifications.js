// Promemoria di esami e task, come NotificationPlanner dell'app iOS.

import { addDays, addMonths, atTime, dayDiff, dayKey, startOfDay } from './calendar.js';
import { active, compareBy, startDate } from './logic.js';

/** Quanto prima di un esame arriva un promemoria, nell'ordine dell'app iOS. */
export const REMINDER_OFFSETS = {
  oneMonth: { label: '1 mese prima', shift: (day) => addMonths(day, -1) },
  twoWeeks: { label: '2 settimane prima', shift: (day) => addDays(day, -14) },
  oneWeek: { label: '1 settimana prima', shift: (day) => addDays(day, -7) },
  threeDays: { label: '3 giorni prima', shift: (day) => addDays(day, -3) },
  twoDays: { label: '2 giorni prima', shift: (day) => addDays(day, -2) },
  oneDay: { label: '1 giorno prima', shift: (day) => addDays(day, -1) },
  sameDay: { label: 'Il giorno stesso', shift: (day) => day },
};

export const DEFAULT_NOTIFICATION_SETTINGS = {
  examReminders: ['oneWeek', 'oneDay', 'sameDay'],
  dailyTaskSummary: true,
  hour: 9,
  minute: 0,
};

function examBody(days) {
  if (days === 0) return 'Esame oggi: in bocca al lupo!';
  if (days === 1) return 'Esame domani';
  return `Esame tra ${days} giorni`;
}

/** Notifiche future per esami e task, dalle più vicine: { id, title, body, fireDate }. */
export function planNotifications(exams, settings, now) {
  const at = (day) => atTime(day, settings.hour, settings.minute);
  const pending = active(exams, now);
  const planned = [];

  for (const exam of pending.filter((item) => item.isScheduled)) {
    const examDay = startOfDay(exam.date);
    for (const key of settings.examReminders) {
      const offset = REMINDER_OFFSETS[key];
      if (!offset) continue;
      const day = offset.shift(examDay);
      let fireDate = at(day);
      // Il giorno dell'esame, almeno un'ora prima dell'inizio se l'orario è indicato.
      const start = startDate(exam);
      if (key === 'sameDay' && start) {
        const hourBefore = new Date(start.getTime() - 3_600_000);
        if (hourBefore < fireDate) fireDate = hourBefore;
      }
      if (fireDate <= now) continue;
      planned.push({ id: `exam-${exam.id}-${key}`, title: exam.name, body: examBody(dayDiff(day, examDay)), fireDate });
    }
  }

  if (settings.dailyTaskSummary) {
    const byDay = new Map();
    for (const exam of pending) {
      for (const task of exam.tasks.filter((item) => !item.isDone)) {
        const key = dayKey(task.dueDate);
        if (!byDay.has(key)) byDay.set(key, []);
        byDay.get(key).push({ task, examName: exam.name });
      }
    }
    for (const [key, items] of byDay) {
      const fireDate = at(new Date(`${key}T12:00:00`));
      if (fireDate <= now) continue;
      items.sort((a, b) => compareBy([a.task.title, b.task.title], [a.examName, b.examName]));
      planned.push({
        id: `tasks-${key}`,
        title: `${items.length} task in scadenza oggi`,
        body: items.map((item) => `${item.task.title} (${item.examName})`).join(', '),
        fireDate,
      });
    }
  }

  return planned.sort((a, b) => compareBy([a.fireDate.getTime(), b.fireDate.getTime()], [a.id, b.id]));
}
