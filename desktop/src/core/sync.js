// Contenuto del file di sincronizzazione e unione dei dati di due dispositivi, esame per esame.
// Stesse regole di Sync.swift: per ogni esame vince la versione modificata più di recente,
// un'eliminazione vince sulle modifiche precedenti.

import { bytesPrecede, decodeDeletions, decodeExamList, DecodeError, parseJSON, swiftJSON } from './codec.js';

export const SYNC_FILE_NAME = 'ExamsTrack-sync.json';

export function makeSnapshot(exams = [], deletions = {}) {
  return { version: 1, exams, deletions };
}

export function encodeSnapshot(snapshot) {
  return swiftJSON({ version: snapshot.version ?? 1, exams: snapshot.exams, deletions: snapshot.deletions });
}

export function decodeSnapshot(text) {
  const object = parseJSON(text);
  if (!object || typeof object !== 'object' || typeof object.version !== 'number') throw new DecodeError('snapshot');
  return makeSnapshot(decodeExamList(object.exams), decodeDeletions(object.deletions));
}

/** Testo canonico di un esame: due esami sono uguali se hanno lo stesso testo. */
export const examKey = (exam) => swiftJSON(exam);

export function examsEqual(a, b) {
  return a.length === b.length && a.every((exam, index) => examKey(exam) === examKey(b[index]));
}

export function deletionsEqual(a, b) {
  const keys = Object.keys(a);
  return keys.length === Object.keys(b).length && keys.every((key) => a[key] === b[key]);
}

/** Stesso contenuto, a prescindere dall'ordine degli esami (che può differire tra dispositivi). */
export function hasSameContent(a, b) {
  if (!deletionsEqual(a.deletions, b.deletions) || a.exams.length !== b.exams.length) return false;
  const left = a.exams.map(examKey).sort();
  const right = b.exams.map(examKey).sort();
  return left.every((key, index) => key === right[index]);
}

/** Un solo esame per id (il primo). */
export function unique(exams) {
  const seen = new Set();
  return exams.filter((exam) => {
    if (seen.has(exam.id)) return false;
    seen.add(exam.id);
    return true;
  });
}

/** La versione più recente; a parità di data sceglie in base al contenuto, come fa l'app iOS. */
export function newer(a, b) {
  const dateA = a.modifiedAt ?? '';
  const dateB = b.modifiedAt ?? '';
  if (dateA !== dateB) return dateA > dateB ? a : b;
  const textA = examKey(a);
  const textB = examKey(b);
  if (textA === textB) return a;
  return bytesPrecede(textA, textB) ? b : a;
}

/** Il resto dell'esame dalla versione più recente; la simulazione dalla simulazione più recente. */
export function combine(local, remote) {
  const winner = { ...newer(remote, local) };
  const localSimulation = local.simulationModifiedAt ?? '';
  const remoteSimulation = remote.simulationModifiedAt ?? '';
  if (localSimulation !== remoteSimulation) {
    const source = localSimulation > remoteSimulation ? local : remote;
    winner.simulatedGrade = source.simulatedGrade;
    winner.simulationModifiedAt = source.simulationModifiedAt;
  }
  return winner;
}

/** L'ordine è quello locale, poi gli esami arrivati dall'altro dispositivo. */
export function merge(local, remote) {
  const deletions = { ...local.deletions };
  for (const [id, deletedAt] of Object.entries(remote.deletions)) {
    const current = deletions[id];
    deletions[id] = current && current > deletedAt ? current : deletedAt;
  }

  const survives = (exam) => {
    const deletedAt = deletions[exam.id];
    return !deletedAt || (exam.modifiedAt ?? '') > deletedAt;
  };

  const localExams = unique(local.exams);
  const remoteExams = unique(remote.exams);
  const remoteByID = new Map(remoteExams.map((exam) => [exam.id, exam]));
  const localIDs = new Set(localExams.map((exam) => exam.id));
  const merged = [];
  for (const exam of localExams) {
    const other = remoteByID.get(exam.id);
    const winner = other ? combine(exam, other) : exam;
    if (survives(winner)) merged.push(winner);
  }
  for (const exam of remoteExams) {
    if (!localIDs.has(exam.id) && survives(exam)) merged.push(exam);
  }
  return makeSnapshot(merged, deletions);
}

/** Unisce più versioni remote, per esempio le copie in conflitto create da iCloud. */
export function mergeAll(local, remotes) {
  return remotes.reduce((result, remote) => merge(result, remote), local);
}

// MARK: Backup automatici

export const BACKUP_FOLDER = 'Backup';
export const BACKUP_KEEP = 14;
const BACKUP_PREFIX = 'ExamsTrack-backup-';

/** "ExamsTrack-backup-AAAA-MM-GG.json": il nome ordina i file per data. */
export function backupFileName(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${BACKUP_PREFIX}${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}.json`;
}

/** I backup più vecchi oltre i `keep` più recenti; altri file nella cartella non vengono toccati. */
export function backupsToDelete(names, keep = BACKUP_KEEP) {
  const backups = names.filter((name) => name.startsWith(BACKUP_PREFIX) && name.endsWith('.json')).sort().reverse();
  return backups.slice(keep);
}
