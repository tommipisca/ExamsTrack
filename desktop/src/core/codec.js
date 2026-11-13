// Lettura e scrittura del JSON con le stesse regole dell'app iOS (JSONEncoder di Swift con
// .prettyPrinted e .sortedKeys, date ISO 8601). Il testo deve essere identico byte per byte:
// a parità di data di modifica, l'unione dei dati sceglie in base al contenuto codificato,
// e PC, iPhone e iPad devono arrivare tutti allo stesso risultato.

import { isoOf } from './calendar.js';

export class DecodeError extends Error {}

// MARK: Scrittura

function encodeString(text) {
  let out = '"';
  for (const char of text) {
    const code = char.codePointAt(0);
    switch (char) {
      case '"': out += '\\"'; break;
      case '\\': out += '\\\\'; break;
      case '/': out += '\\/'; break;
      case '\n': out += '\\n'; break;
      case '\r': out += '\\r'; break;
      case '\t': out += '\\t'; break;
      case '\b': out += '\\b'; break;
      case '\f': out += '\\f'; break;
      default:
        out += code < 0x20 ? `\\u${code.toString(16).padStart(4, '0')}` : char;
    }
  }
  return out + '"';
}

function encodeValue(value, level) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return encodeString(value);
  const pad = '  '.repeat(level + 1);
  const close = '  '.repeat(level);
  if (Array.isArray(value)) {
    if (value.length === 0) return `[\n\n${close}]`;
    return `[\n${value.map((item) => pad + encodeValue(item, level + 1)).join(',\n')}\n${close}]`;
  }
  // I valori nil di Swift non vengono scritti.
  const keys = Object.keys(value).filter((key) => value[key] !== null && value[key] !== undefined).sort();
  if (keys.length === 0) return `{\n\n${close}}`;
  return `{\n${keys.map((key) => `${pad}${encodeString(key)} : ${encodeValue(value[key], level + 1)}`).join(',\n')}\n${close}}`;
}

/** JSON come lo scrive l'app iOS. */
export function swiftJSON(value) {
  return encodeValue(value, 0);
}

/** Byte UTF-8 di `a` prima di quelli di `b` (come `Data.lexicographicallyPrecedes`). */
export function bytesPrecede(a, b) {
  const encoder = new TextEncoder();
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  const length = Math.min(x.length, y.length);
  for (let i = 0; i < length; i++) {
    if (x[i] !== y[i]) return x[i] < y[i];
  }
  return x.length < y.length;
}

// MARK: Lettura

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function newUUID() {
  return crypto.randomUUID().toUpperCase();
}

function fail(what) {
  throw new DecodeError(what);
}

function uuid(value, what) {
  if (typeof value !== 'string' || !uuidPattern.test(value)) fail(what);
  return value.toUpperCase();
}

function string(value, what) {
  if (typeof value !== 'string') fail(what);
  return value;
}

function bool(value, what) {
  if (typeof value !== 'boolean') fail(what);
  return value;
}

function int(value, what) {
  if (typeof value !== 'number' || !Number.isInteger(value)) fail(what);
  return value;
}

function number(value, what) {
  if (typeof value !== 'number' || !Number.isFinite(value)) fail(what);
  return value;
}

export function date(value, what) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:?\d{2})$/.test(value)) fail(what);
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) fail(what);
  return isoOf(parsed);
}

/** Campo facoltativo: assente o null → `fallback`. */
function optional(object, key, read, fallback = null) {
  const value = object[key];
  return value === undefined || value === null ? fallback : read(value, key);
}

export function decodeSubtask(object) {
  if (!object || typeof object !== 'object' || Array.isArray(object)) fail('subtask');
  return {
    id: uuid(object.id, 'subtask.id'),
    title: string(object.title, 'subtask.title'),
    isDone: bool(object.isDone, 'subtask.isDone'),
  };
}

export function decodeTask(object) {
  if (!object || typeof object !== 'object' || Array.isArray(object)) fail('task');
  const subtasks = optional(object, 'subtasks', (value) => {
    if (!Array.isArray(value)) fail('task.subtasks');
    return value.map(decodeSubtask);
  }, []);
  return {
    id: uuid(object.id, 'task.id'),
    title: string(object.title, 'task.title'),
    dueDate: date(object.dueDate, 'task.dueDate'),
    isDone: bool(object.isDone, 'task.isDone'),
    // Assenti nei dati salvati prima dei sotto-task. Come in Swift, si scrivono sempre (anche vuoti).
    subtasks,
  };
}

/** Un esame, con i valori predefiniti per i campi assenti nei dati più vecchi (come in Swift). */
export function decodeExam(object) {
  if (!object || typeof object !== 'object' || Array.isArray(object)) fail('exam');
  if (!Array.isArray(object.tasks)) fail('exam.tasks');
  const degree = optional(object, 'degree', (value) => {
    if (value !== 'triennale' && value !== 'magistrale') fail('exam.degree');
    return value;
  }, 'triennale');
  return {
    id: uuid(object.id, 'exam.id'),
    name: string(object.name, 'exam.name'),
    date: date(object.date, 'exam.date'),
    tasks: object.tasks.map(decodeTask),
    passed: optional(object, 'passed', bool),
    grade: optional(object, 'grade', int),
    honors: bool(object.honors, 'exam.honors'),
    degree,
    cfu: optional(object, 'cfu', int, 6),
    isFinalTest: optional(object, 'isFinalTest', bool, false),
    thesisPoints: optional(object, 'thesisPoints', number),
    isScheduled: optional(object, 'isScheduled', bool, true),
    startTime: optional(object, 'startTime', int),
    colorIndex: optional(object, 'colorIndex', int),
    modifiedAt: optional(object, 'modifiedAt', date),
    simulatedGrade: optional(object, 'simulatedGrade', int),
    simulationModifiedAt: optional(object, 'simulationModifiedAt', date),
    notes: optional(object, 'notes', string, ''),
  };
}

export function decodeExamList(value) {
  if (!Array.isArray(value)) fail('exams');
  return value.map(decodeExam);
}

/** id → data, per le eliminazioni. */
export function decodeDeletions(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('deletions');
  const result = {};
  for (const [key, stamp] of Object.entries(value)) {
    result[key] = date(stamp, 'deletion');
  }
  return result;
}

/** JSON.parse che segnala un testo illeggibile con DecodeError. */
export function parseJSON(text) {
  try {
    return JSON.parse(text);
  } catch {
    throw new DecodeError('json');
  }
}
