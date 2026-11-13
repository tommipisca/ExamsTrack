// Sincronizzazione con ExamsTrack-sync.json nella cartella scelta (la stessa usata da iPhone e iPad
// su iCloud Drive). Come SyncService.swift: legge il file, unisce esame per esame, salva un backup
// giornaliero e riscrive il file solo se il contenuto cambia.

import { decodeSnapshot, encodeSnapshot, makeSnapshot, merge, mergeAll, hasSameContent, SYNC_FILE_NAME,
  BACKUP_FOLDER, backupFileName, backupsToDelete } from './sync.js';
import { DecodeError } from './codec.js';
import { isSameDay } from './calendar.js';

export class SyncFailure extends Error {
  /** kind: 'folderMissing' | 'unreadable' | 'timedOut' | 'failed' */
  constructor(kind, cause) {
    super(kind);
    this.kind = kind;
    this.cause = cause;
  }
}

export const SYNC_MESSAGES = {
  folderMissing: 'La cartella di sincronizzazione non è più accessibile: scollegala e sceglila di nuovo.',
  unreadable: `Il file ${SYNC_FILE_NAME} non è leggibile: non è stato modificato.`,
  timedOut: 'iCloud non risponde: la sincronizzazione riproverà tra poco.',
  failed: 'Sincronizzazione non riuscita. Controlla che iCloud sia attivo e che la cartella esista ancora.',
};

/** Copie in conflitto lasciate dal client di sincronizzazione accanto al file (es. "ExamsTrack-sync (1).json"). */
const conflictPattern = /^ExamsTrack-sync.+\.json$/i;

/**
 * fs: { readText(path) → testo o null se manca, writeText(path, text) (atomico), list(dir) → nomi,
 *       mkdir(dir), remove(path), isDirectory(path), join(...parti) }
 */
export class SyncEngine {
  constructor({ fs, timeoutMs = 30_000, now = () => new Date() }) {
    this.fs = fs;
    this.timeoutMs = timeoutMs;
    this.now = now;
  }

  /** Smette di aspettare un'operazione su iCloud rimasta bloccata. */
  #withTimeout(promise) {
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new SyncFailure('timedOut')), this.timeoutMs);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  }

  /**
   * Una sincronizzazione completa. Restituisce la data dell'ultimo backup automatico
   * (aggiornata se ne è stato scritto uno). Lancia SyncFailure.
   */
  async syncOnce(store, folder, { lastAutoBackup = null } = {}) {
    const { fs } = this;
    try {
      if (!(await this.#withTimeout(fs.isDirectory(folder)))) throw new SyncFailure('folderMissing');
      const fileURL = fs.join(folder, SYNC_FILE_NAME);
      const remoteText = await this.#withTimeout(fs.readText(fileURL));
      const current = remoteText === null ? makeSnapshot() : decodeSnapshot(remoteText);

      // Le copie in conflitto si uniscono, non si scartano; si eliminano solo quelle lette e unite.
      const names = await this.#withTimeout(fs.list(folder));
      const conflicts = [];
      const conflictFiles = [];
      for (const name of names) {
        if (name === SYNC_FILE_NAME || !conflictPattern.test(name)) continue;
        try {
          const text = await this.#withTimeout(fs.readText(fs.join(folder, name)));
          if (text === null) continue;
          conflicts.push(decodeSnapshot(text));
          conflictFiles.push(fs.join(folder, name));
        } catch {
          // Non è una copia leggibile: resta dov'è.
        }
      }

      const merged = mergeAll(store.syncSnapshot, [current, ...conflicts]);
      // Backup del giorno con i dati di questo dispositivo, prima di applicare quelli dell'altro.
      const backupDate = await this.#dailyBackupIfNeeded(store, folder, lastAutoBackup);
      // Le modifiche fatte qui durante le attese vincono comunque, se più recenti.
      const final = merge(store.syncSnapshot, merged);
      store.applySynced(final);

      // L'ordine degli esami può differire tra dispositivi: si riscrive solo se cambia il contenuto.
      if (remoteText === null || conflictFiles.length > 0 || !hasSameContent(final, current)) {
        await this.#withTimeout(fs.writeText(fileURL, encodeSnapshot(final)));
        for (const path of conflictFiles) {
          try {
            await this.#withTimeout(fs.remove(path));
          } catch {
            // Si riproverà alla prossima sincronizzazione.
          }
        }
      }
      return { lastAutoBackup: backupDate };
    } catch (error) {
      if (error instanceof SyncFailure) throw error;
      if (error instanceof DecodeError) throw new SyncFailure('unreadable', error);
      throw new SyncFailure('failed', error);
    }
  }

  /** Un backup al giorno nella sottocartella "Backup", tenendo solo gli ultimi 14. */
  async #dailyBackupIfNeeded(store, folder, lastAutoBackup) {
    const now = this.now();
    if (lastAutoBackup && isSameDay(lastAutoBackup, now)) return lastAutoBackup;
    const { fs } = this;
    try {
      const backups = fs.join(folder, BACKUP_FOLDER);
      await this.#withTimeout(fs.mkdir(backups));
      const name = backupFileName(now);
      const path = fs.join(backups, name);
      // Già scritto (anche dall'altro dispositivo): niente doppioni.
      const names = await this.#withTimeout(fs.list(backups));
      if (!names.includes(name)) {
        await this.#withTimeout(fs.writeText(path, store.exportBackup(now)));
        names.push(name);
      }
      for (const old of backupsToDelete(names)) {
        try {
          await this.#withTimeout(fs.remove(fs.join(backups, old)));
        } catch {
          // Non importante.
        }
      }
      return now;
    } catch (error) {
      console.warn('ExamsTrack: backup automatico non riuscito', error);
      return lastAutoBackup;
    }
  }
}
