// Date e calendario nel fuso locale, come `Calendar.current` dell'app iOS.
// Nel modello le date sono stringhe ISO 8601 al secondo ("2026-10-28T11:00:00Z"),
// lo stesso formato che usa l'app iOS: così si confrontano anche come testo.

/** Data → "AAAA-MM-GGTHH:MM:SSZ", senza millisecondi (l'app iOS non li accetta). */
export function iso(date) {
  return new Date(Math.floor(date.getTime() / 1000) * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function toDate(value) {
  return value instanceof Date ? value : new Date(value);
}

/** Accetta Date o stringa ISO e restituisce la stringa ISO normalizzata. */
export function isoOf(value) {
  return iso(toDate(value));
}

export function startOfDay(date) {
  const d = toDate(date);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function atTime(date, hour, minute = 0) {
  const d = toDate(date);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hour, minute, 0);
}

/** Lo stesso giorno a mezzogiorno: stabile ai cambi di fuso e di ora legale. */
export function noon(date) {
  return atTime(date, 12);
}

export function addDays(date, days) {
  const d = toDate(date);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days, d.getHours(), d.getMinutes(), d.getSeconds());
}

/** Aggiunge mesi fermandosi all'ultimo giorno del mese (31 marzo − 1 mese = 28 febbraio). */
export function addMonths(date, months) {
  const d = toDate(date);
  const target = new Date(d.getFullYear(), d.getMonth() + months, 1, d.getHours(), d.getMinutes(), d.getSeconds());
  const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate();
  target.setDate(Math.min(d.getDate(), lastDay));
  return target;
}

/** Giorni di calendario da `from` a `to` (0 = stesso giorno, negativo = passato). */
export function dayDiff(from, to) {
  const a = toDate(from);
  const b = toDate(to);
  const ua = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const ub = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((ub - ua) / 86_400_000);
}

export function isSameDay(a, b) {
  return dayDiff(a, b) === 0;
}

/** "AAAA-MM-GG" nel fuso locale, per i campi data e come chiave di un giorno. */
export function dayKey(date) {
  const d = toDate(date);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** "AAAA-MM-GG" → mezzogiorno di quel giorno locale. */
export function fromDayKey(key) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d, 12, 0, 0);
}

const longFormat = new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
const shortFormat = new Intl.DateTimeFormat('it-IT', { day: 'numeric', month: 'short' });
const weekdayFormat = new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'short' });
const monthYearFormat = new Intl.DateTimeFormat('it-IT', { month: 'short', year: '2-digit' });
const dayTimeFormat = new Intl.DateTimeFormat('it-IT', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });

/** "lunedì 10 novembre 2026" */
export const italianLong = (date) => longFormat.format(toDate(date));
/** "10 nov" */
export const italianShort = (date) => shortFormat.format(toDate(date)).replace('.', '');
/** "martedì 14 ott" */
export const italianWeekday = (date) => weekdayFormat.format(toDate(date)).replace('.', '');
/** "ott 26" */
export const italianMonthYear = (date) => monthYearFormat.format(toDate(date)).replace('.', '');
/** "lunedì 13 ottobre, 14:30" */
export const italianDayTime = (date) => dayTimeFormat.format(toDate(date));

const relativeFormat = new Intl.RelativeTimeFormat('it', { numeric: 'auto' });

/** "adesso", "5 minuti fa", "ieri"... */
export function relativeLabel(date, now = new Date()) {
  const seconds = Math.round((toDate(date).getTime() - now.getTime()) / 1000);
  const abs = Math.abs(seconds);
  if (abs < 45) return 'adesso';
  if (abs < 3600) return relativeFormat.format(Math.round(seconds / 60), 'minute');
  if (abs < 86_400) return relativeFormat.format(Math.round(seconds / 3600), 'hour');
  return relativeFormat.format(dayDiff(now, date), 'day');
}
