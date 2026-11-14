// Widget sul desktop: una finestra trasparente senza bordi, subito sopra il desktop (vedi desktopHost.cjs),
// che mostra il prossimo esame come il widget extra large di iPad. I dati li calcola la finestra principale
// (vedi pushWidget in renderer/app.js) e passano da qui.

const { BrowserWindow, Menu, ipcMain, screen } = require('electron');
const path = require('node:path');
const host = require('./desktopHost.cjs');

/**
 * Misure della finestra per ogni dimensione. Il testo resta della stessa grandezza: nelle più piccole
 * countdown, anello e margini si riducono e si vedono meno righe (vedi widget.css).
 */
const SIZES = { small: [470, 245], medium: [560, 290], large: [660, 340] };
const MARGIN = 48;

let size = 'small';
const width = () => SIZES[size][0];
const height = () => SIZES[size][1];

let win = null;
let payload = null;
let timer = null;
let drag = null;
let options = null;

/**
 * options: { iconPath, getPosition(), savePosition({ x, y }), isLocked(), setLocked(locked),
 *            open(target), toggleTask(examID, taskID), hide() }
 * `target` è { examID } per aprire un esame, { tab } per una scheda.
 */
function init(widgetOptions) {
  options = widgetOptions;
  const fromWidget = (event) => win && !win.isDestroyed() && event.sender === win.webContents;

  ipcMain.on('widget:ready', (event) => {
    if (fromWidget(event)) send();
  });
  ipcMain.on('widget:toggleTask', (event, examID, taskID) => {
    if (fromWidget(event)) options.toggleTask(String(examID), String(taskID));
  });
  ipcMain.on('widget:open', (event, examID) => {
    if (fromWidget(event)) options.open(examID ? { examID: String(examID) } : { tab: 'today' });
  });
  ipcMain.on('widget:menu', (event) => {
    if (!fromWidget(event)) return;
    Menu.buildFromTemplate([
      { label: 'Apri ExamsTrack', click: () => options.open({ tab: 'today' }) },
      { label: 'Impostazioni del widget…', click: () => options.open({ tab: 'settings' }) },
      { type: 'separator' },
      { label: 'Blocca posizione', type: 'checkbox', checked: options.isLocked(), click: (item) => options.setLocked(item.checked) },
      { label: 'Nascondi widget', click: () => options.hide() },
    ]).popup({ window: win });
  });

  // Trascinamento: la finestra segue il cursore (in coordinate dello schermo, già in DIP).
  ipcMain.on('widget:dragStart', (event) => {
    if (!fromWidget(event) || options.isLocked()) return;
    drag = { cursor: screen.getCursorScreenPoint(), bounds: win.getBounds() };
  });
  ipcMain.on('widget:drag', (event) => {
    if (!fromWidget(event) || !drag) return;
    const cursor = screen.getCursorScreenPoint();
    win.setBounds({
      x: drag.bounds.x + cursor.x - drag.cursor.x,
      y: drag.bounds.y + cursor.y - drag.cursor.y,
      width: width(),
      height: height(),
    });
  });
  ipcMain.on('widget:dragEnd', (event) => {
    if (!fromWidget(event) || !drag) return;
    drag = null;
    const { x, y } = win.getBounds();
    options.savePosition({ x, y });
  });

  screen.on('display-removed', () => {
    if (win && !win.isDestroyed()) win.setBounds(initialBounds());
  });
}

/** Posizione salvata se è ancora su uno schermo, altrimenti in alto a destra dello schermo principale. */
function initialBounds() {
  const saved = options.getPosition();
  if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
    const onScreen = screen.getAllDisplays().some(({ workArea: area }) =>
      saved.x >= area.x - width() + 80 && saved.x <= area.x + area.width - 80
      && saved.y >= area.y && saved.y <= area.y + area.height - 80);
    if (onScreen) return { x: saved.x, y: saved.y, width: width(), height: height() };
  }
  const area = screen.getPrimaryDisplay().workArea;
  return { x: area.x + area.width - width() - MARGIN, y: area.y + MARGIN, width: width(), height: height() };
}

function show() {
  if (win && !win.isDestroyed()) return;
  win = new BrowserWindow({
    ...initialBounds(),
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    focusable: false,
    hasShadow: false,
    show: false,
    title: 'ExamsTrack (widget)',
    icon: options.iconPath,
    webPreferences: {
      preload: path.join(__dirname, 'widget-preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
    },
  });
  win.loadFile(path.join(__dirname, 'renderer', 'widget.html'));
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (event) => event.preventDefault());

  win.once('ready-to-show', () => {
    win.showInactive();
    host.placeAboveDesktop(win);
  });

  const restarted = host.taskbarCreatedMessage();
  if (restarted) win.hookWindowMessage(restarted, () => setTimeout(() => win && host.placeAboveDesktop(win), 1000));

  if (host.isAvailable()) timer = setInterval(() => win && host.keepVisible(win), 250);
  win.on('closed', () => {
    clearInterval(timer);
    timer = null;
    drag = null;
    win = null;
  });
}

function hide() {
  if (win && !win.isDestroyed()) win.destroy();
}

function setVisible(visible) {
  if (visible) show();
  else hide();
}

function send() {
  if (win && !win.isDestroyed() && payload) {
    win.webContents.send('widget:data', { ...payload, size, locked: options.isLocked() });
  }
}

/** Nuovi dati dalla finestra principale: si tengono per quando il widget si apre o si ricarica. */
function update(data) {
  payload = data;
  send();
}

/** 'small', 'medium' o 'large': la finestra cambia misura tenendo fermo l'angolo in alto a sinistra. */
function setSize(newSize) {
  size = SIZES[newSize] ? newSize : 'small';
  if (!win || win.isDestroyed()) return;
  const { x, y } = win.getBounds();
  win.setBounds({ x, y, width: width(), height: height() });
  send();
}

/** Le impostazioni sono cambiate (es. la posizione bloccata): si rimandano al widget. */
const refresh = send;

module.exports = { init, setVisible, setSize, update, refresh };
