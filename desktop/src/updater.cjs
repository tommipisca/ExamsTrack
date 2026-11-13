// Aggiornamenti dalle release di GitHub (electron-updater).
// L'installer scarica la nuova versione in background e la installa alla chiusura o con "Riavvia e aggiorna".
// La versione portable non si aggiorna da sola: avvisa e apre la pagina della release.

const { app, Notification, shell } = require('electron');

const RELEASES_URL = 'https://github.com/tommipisca/ExamsTrack/releases/latest';
const CHECK_INTERVAL = 6 * 60 * 60 * 1000;
const FIRST_CHECK_DELAY = 15 * 1000;

/** Versione portable: electron-builder imposta questa variabile all'avvio. */
const isPortable = Boolean(process.env.PORTABLE_EXECUTABLE_DIR);

let autoUpdater = null;
let options = null;
let timer = null;
let notifiedVersion = null;

/**
 * status: 'unsupported' (avvio con `npm start`), 'idle', 'checking', 'not-available',
 * 'available' (solo portable), 'downloading', 'downloaded', 'error'.
 */
const state = {
  status: 'idle',
  version: null,
  percent: 0,
  error: null,
  lastCheck: null,
  portable: isPortable,
};

function publish(changes) {
  Object.assign(state, changes);
  options.onState({ ...state });
}

function notify(title, body, onClick) {
  if (!Notification.isSupported()) return;
  const notification = new Notification({ title, body, icon: options.iconPath });
  notification.on('click', onClick);
  notification.show();
}

/** Messaggio comprensibile: senza rete o con GitHub irraggiungibile l'errore di electron-updater è tecnico. */
function errorMessage(error) {
  const text = String(error?.message ?? error);
  if (/ENOTFOUND|ECONNREFUSED|ETIMEDOUT|ECONNRESET|net::ERR_/i.test(text)) return 'Nessuna connessione a GitHub.';
  if (/\b404\b/.test(text)) return 'Nessuna informazione sugli aggiornamenti nell\'ultima release.';
  return 'Impossibile controllare gli aggiornamenti.';
}

function check() {
  if (!autoUpdater || ['checking', 'downloading', 'downloaded'].includes(state.status)) return;
  publish({ status: 'checking', error: null });
  autoUpdater.checkForUpdates().catch(() => {
    // L'errore arriva anche dall'evento 'error', che aggiorna lo stato.
  });
}

function schedule() {
  clearInterval(timer);
  timer = null;
  if (!autoUpdater || !options.isAutoCheckEnabled()) return;
  timer = setInterval(check, CHECK_INTERVAL);
}

/**
 * @param {object} opts
 * @param {string} opts.iconPath
 * @param {() => boolean} opts.isAutoCheckEnabled
 * @param {(state: object) => void} opts.onState  inviato alla finestra a ogni cambio
 * @param {() => void} opts.showWindow
 */
function init(opts) {
  options = opts;
  if (!app.isPackaged) {
    publish({ status: 'unsupported' });
    return;
  }

  ({ autoUpdater } = require('electron-updater'));
  autoUpdater.autoDownload = !isPortable;
  // L'installazione alla chiusura la fa `installOnQuit`: l'uscita dell'app usa app.exit(), che salta
  // l'evento 'quit' su cui si basa autoInstallOnAppQuit.
  autoUpdater.autoInstallOnAppQuit = false;
  // Le release non pubblicano i .blockmap: si scarica sempre l'installer completo.
  autoUpdater.disableDifferentialDownload = true;

  autoUpdater.on('update-available', (info) => {
    if (isPortable) {
      publish({ status: 'available', version: info.version, lastCheck: Date.now() });
      if (notifiedVersion !== info.version) {
        notifiedVersion = info.version;
        notify('Nuova versione di ExamsTrack', `La versione ${info.version} è disponibile: clicca per scaricarla.`, openReleasePage);
      }
    } else {
      publish({ status: 'downloading', version: info.version, percent: 0, lastCheck: Date.now() });
    }
  });
  autoUpdater.on('update-not-available', () => publish({ status: 'not-available', lastCheck: Date.now() }));
  autoUpdater.on('download-progress', (progress) => publish({ status: 'downloading', percent: Math.round(progress.percent) }));
  autoUpdater.on('update-downloaded', (info) => {
    publish({ status: 'downloaded', version: info.version, percent: 100 });
    if (notifiedVersion !== info.version) {
      notifiedVersion = info.version;
      notify('Aggiornamento pronto', `ExamsTrack ${info.version} si installerà alla chiusura. Apri Impostazioni per aggiornare subito.`, options.showWindow);
    }
  });
  autoUpdater.on('error', (error) => {
    console.warn('ExamsTrack: aggiornamenti', error);
    publish({ status: 'error', error: errorMessage(error), lastCheck: Date.now() });
  });

  if (options.isAutoCheckEnabled()) setTimeout(check, FIRST_CHECK_DELAY);
  schedule();
}

function openReleasePage() {
  shell.openExternal(RELEASES_URL);
}

/** Da chiamare dopo che la finestra ha salvato tutto: installa se c'è un aggiornamento scaricato. */
function installOnQuit({ restart }) {
  if (state.status !== 'downloaded' || !autoUpdater) return false;
  // Installazione silenziosa; con restart riapre l'app aggiornata.
  autoUpdater.quitAndInstall(true, restart);
  return true;
}

module.exports = {
  init,
  check,
  schedule,
  openReleasePage,
  installOnQuit,
  getState: () => ({ ...state }),
};
