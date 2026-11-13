// Servizi della finestra: preferenze, file dei dati, sincronizzazione e promemoria.

import { SyncEngine, SyncFailure, SYNC_MESSAGES } from '../core/syncEngine.js';
import { planNotifications, DEFAULT_NOTIFICATION_SETTINGS } from '../core/notifications.js';
import { visible } from '../core/logic.js';

const api = window.api;

// MARK: Preferenze

const defaults = {
  startTab: 'today',
  careerFilter: 'triennale',
  thesisType: 'withReviewer',
  careerSort: 'date',
  degreeVisibility: 'both',
  notificationSettings: DEFAULT_NOTIFICATION_SETTINGS,
  syncFolder: null,
  syncLastDate: null,
  syncLastAutoBackup: null,
  notificationsCheckedAt: null,
  studySession: null,
  studyLastMinutes: 25,
};

export const prefs = {
  get(key) {
    try {
      const raw = localStorage.getItem(key);
      return raw === null ? structuredClone(defaults[key]) : JSON.parse(raw);
    } catch {
      return structuredClone(defaults[key]);
    }
  },
  set(key, value) {
    try {
      if (value === null || value === undefined) localStorage.removeItem(key);
      else localStorage.setItem(key, JSON.stringify(value));
    } catch {
      // Preferenza non salvata: resta valida finché l'app è aperta.
    }
  },
};

// MARK: File

/** Percorsi Windows senza passare dal processo principale (servono in modo sincrono). */
export function joinPath(...parts) {
  return parts.map((part, index) => (index === 0 ? part.replace(/[\\/]+$/, '') : part.replace(/^[\\/]+|[\\/]+$/g, ''))).join('\\');
}

/** I file dei dati (exams.json, deletions.json) nella cartella dell'app. */
export async function makePersistence() {
  const dir = await api.fs.dataDir();
  const at = (name) => joinPath(dir, name);
  return {
    dir,
    readText: (name) => api.fs.readText(at(name)),
    writeTexts: (files) => api.fs.writeTexts(files.map(({ name, text }) => ({ path: at(name), text }))),
    rename: (from, to) => api.fs.rename(at(from), at(to)),
    remove: (name) => api.fs.remove(at(name)),
  };
}

const syncFS = {
  readText: (path) => api.fs.readText(path),
  writeText: (path, text) => api.fs.writeText(path, text),
  list: (dir) => api.fs.list(dir),
  mkdir: (dir) => api.fs.mkdir(dir),
  remove: (path) => api.fs.remove(path),
  isDirectory: (path) => api.fs.isDirectory(path),
  join: joinPath,
};

// MARK: Sincronizzazione

/** Sincronizza con la cartella scelta (es. su iCloud Drive), come SyncService dell'app iOS. */
export class SyncService {
  folder = prefs.get('syncFolder');
  lastSync = prefs.get('syncLastDate');
  lastAutoBackup = prefs.get('syncLastAutoBackup');
  errorMessage = null;
  isSyncing = false;
  /** Cartella trovata in iCloud Drive, proposta finché non se ne collega una. */
  suggestedFolder = null;
  #engine = new SyncEngine({ fs: syncFS });
  #running = null;
  #needsAnotherPass = false;
  #onChange;

  constructor(onChange) {
    this.#onChange = onChange;
    api.watchSyncFolder(this.folder);
  }

  get isEnabled() {
    return Boolean(this.folder);
  }

  get folderName() {
    return this.folder ? this.folder.split(/[\\/]/).filter(Boolean).at(-1) : null;
  }

  async detect() {
    if (this.folder) return;
    this.suggestedFolder = await api.detectSyncFolder().catch(() => null);
    this.#onChange();
  }

  link(folder) {
    this.folder = folder;
    this.errorMessage = null;
    this.lastSync = null;
    prefs.set('syncFolder', folder);
    prefs.set('syncLastDate', null);
    api.watchSyncFolder(folder);
    this.#onChange();
  }

  unlink() {
    this.folder = null;
    this.errorMessage = null;
    this.lastSync = null;
    prefs.set('syncFolder', null);
    prefs.set('syncLastDate', null);
    api.watchSyncFolder(null);
    this.#onChange();
    this.detect();
  }

  /** Legge il file condiviso, unisce con i dati locali e riscrive il file se serve. */
  async sync(store) {
    if (!this.isEnabled) return;
    if (this.#running) {
      // Una sincronizzazione è già in corso: ne servirà un'altra subito dopo.
      this.#needsAnotherPass = true;
      return this.#running;
    }
    this.#running = this.#runPasses(store);
    try {
      await this.#running;
    } finally {
      this.#running = null;
    }
  }

  async #runPasses(store) {
    this.isSyncing = true;
    this.#onChange();
    do {
      this.#needsAnotherPass = false;
      await this.#syncOnce(store);
    } while (this.#needsAnotherPass && this.isEnabled);
    this.isSyncing = false;
    this.#onChange();
  }

  async #syncOnce(store) {
    const folder = this.folder;
    try {
      // I salvataggi locali in corso prima: il file condiviso deve partire da dati già scritti.
      await store.flush();
      const result = await this.#engine.syncOnce(store, folder, {
        lastAutoBackup: this.lastAutoBackup ? new Date(this.lastAutoBackup) : null,
      });
      if (folder !== this.folder) return;
      this.lastAutoBackup = result.lastAutoBackup ? result.lastAutoBackup.toISOString() : null;
      this.lastSync = new Date().toISOString();
      prefs.set('syncLastAutoBackup', this.lastAutoBackup);
      prefs.set('syncLastDate', this.lastSync);
      this.errorMessage = null;
    } catch (error) {
      console.error('ExamsTrack: sincronizzazione fallita', error);
      this.errorMessage = SYNC_MESSAGES[error instanceof SyncFailure ? error.kind : 'failed'];
    }
  }
}

// MARK: Promemoria

/**
 * Notifiche di Windows mentre l'app è aperta (anche nascosta nell'area di notifica).
 * Ogni mezzo minuto invia quelle con l'orario appena passato; all'avvio recupera quelle
 * dell'ultima ora, se l'app era chiusa.
 */
export class Notifier {
  #getExams;

  constructor(getExams) {
    this.#getExams = getExams;
    const saved = prefs.get('notificationsCheckedAt');
    const hourAgo = Date.now() - 3_600_000;
    this.checkedAt = Math.max(saved ? new Date(saved).getTime() : hourAgo, hourAgo);
    setInterval(() => this.check(), 30_000);
    setTimeout(() => this.check(), 5_000);
  }

  check() {
    const now = new Date();
    const settings = prefs.get('notificationSettings');
    const exams = visible(this.#getExams(), prefs.get('degreeVisibility'));
    const since = new Date(this.checkedAt);
    // Pianifica da "since": così compaiono anche le notifiche il cui orario è appena passato.
    for (const planned of planNotifications(exams, settings, since)) {
      if (planned.fireDate > now) break;
      api.notify(planned.title, planned.body);
    }
    this.checkedAt = now.getTime();
    prefs.set('notificationsCheckedAt', now.toISOString());
  }
}
