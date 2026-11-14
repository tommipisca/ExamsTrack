// Processo principale: finestra, icona nell'area di notifica, accesso ai file e notifiche di Windows.

const { app, BrowserWindow, Menu, Notification, Tray, dialog, ipcMain, nativeImage, nativeTheme, shell } = require('electron');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const updater = require('./updater.cjs');
const widget = require('./widget.cjs');

const APP_ID = 'com.Tommaso.ExamsTrack';
const iconPath = path.join(__dirname, '..', 'build', 'icon.png');
const startHidden = process.argv.includes('--hidden');

let mainWindow = null;
let tray = null;
let isQuitting = false;

// MARK: Preferenze del processo principale

const desktopSettingsPath = () => path.join(app.getPath('userData'), 'desktop-settings.json');
/** Widget sul desktop: spento finché non lo si attiva; senza esame scelto segue il prossimo esame. */
const WIDGET_DEFAULTS = { enabled: false, examID: null, includeOtherExams: false, size: 'small', locked: false, position: null };
let desktopSettings = { closeToTray: true, autoUpdate: true, widget: { ...WIDGET_DEFAULTS } };

function loadDesktopSettings() {
  try {
    const saved = JSON.parse(fs.readFileSync(desktopSettingsPath(), 'utf8'));
    desktopSettings = { ...desktopSettings, ...saved, widget: { ...WIDGET_DEFAULTS, ...saved.widget } };
  } catch {
    // Primo avvio.
  }
}

function saveDesktopSettings() {
  try {
    fs.writeFileSync(desktopSettingsPath(), JSON.stringify(desktopSettings, null, 2));
  } catch (error) {
    console.error('ExamsTrack: preferenze non salvate', error);
  }
}

// MARK: File

/** Scrittura atomica: file temporaneo nella stessa cartella, poi rinomina. */
async function writeAtomic(filePath, text) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
  const temp = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  await fsp.writeFile(temp, text, 'utf8');
  try {
    await fsp.rename(temp, filePath);
  } catch (error) {
    await fsp.rm(temp, { force: true });
    throw error;
  }
}

const dataDir = () => path.join(app.getPath('userData'), 'data');

function registerFileHandlers() {
  ipcMain.handle('fs:dataDir', () => dataDir());
  ipcMain.handle('fs:join', (_e, parts) => path.join(...parts));
  ipcMain.handle('fs:readText', async (_e, filePath) => {
    try {
      return await fsp.readFile(filePath, 'utf8');
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw error;
    }
  });
  ipcMain.handle('fs:writeText', (_e, filePath, text) => writeAtomic(filePath, text));
  ipcMain.handle('fs:writeTexts', async (_e, entries) => {
    for (const { path: filePath, text } of entries) await writeAtomic(filePath, text);
  });
  ipcMain.handle('fs:list', async (_e, dir) => {
    try {
      return await fsp.readdir(dir);
    } catch (error) {
      if (error.code === 'ENOENT') return [];
      throw error;
    }
  });
  ipcMain.handle('fs:mkdir', (_e, dir) => fsp.mkdir(dir, { recursive: true }));
  ipcMain.handle('fs:remove', (_e, filePath) => fsp.rm(filePath, { force: true }));
  ipcMain.handle('fs:rename', (_e, from, to) => fsp.rename(from, to));
  ipcMain.handle('fs:isDirectory', async (_e, dir) => {
    try {
      return (await fsp.stat(dir)).isDirectory();
    } catch {
      return false;
    }
  });
}

// MARK: Cartella di sincronizzazione

const iCloudRoot = () => path.join(os.homedir(), 'iCloudDrive');

/** Cerca ExamsTrack-sync.json in iCloud Drive (fino a 4 livelli), per proporre la cartella giusta. */
async function detectSyncFolder() {
  const root = iCloudRoot();
  const queue = [{ dir: root, depth: 0 }];
  while (queue.length > 0) {
    const { dir, depth } = queue.shift();
    let entries;
    try {
      entries = await fsp.readdir(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    if (entries.some((entry) => entry.name === 'ExamsTrack-sync.json')) return dir;
    if (depth >= 4) continue;
    for (const entry of entries) {
      if (entry.isDirectory() && !entry.name.startsWith('.') && entry.name !== 'Backup') {
        queue.push({ dir: path.join(dir, entry.name), depth: depth + 1 });
      }
    }
  }
  return null;
}

let watcher = null;
let watchTimer = null;

/** Avvisa la finestra quando cambia qualcosa nella cartella (es. iCloud scarica il file dell'iPhone). */
function watchFolder(folder) {
  watcher?.close();
  watcher = null;
  if (!folder) return;
  try {
    watcher = fs.watch(folder, (_event, name) => {
      if (name && !String(name).startsWith('ExamsTrack-sync')) return;
      if (name && String(name).includes('.tmp-')) return;
      clearTimeout(watchTimer);
      watchTimer = setTimeout(() => mainWindow?.webContents.send('sync:folderChanged'), 3000);
    });
    watcher.on('error', () => {
      watcher?.close();
      watcher = null;
    });
  } catch (error) {
    console.warn('ExamsTrack: impossibile osservare la cartella', error);
  }
}

function registerAppHandlers() {
  ipcMain.handle('sync:detect', () => detectSyncFolder());
  ipcMain.handle('sync:watch', (_e, folder) => watchFolder(folder));

  ipcMain.handle('dialog:chooseFolder', async () => {
    const root = iCloudRoot();
    const result = await dialog.showOpenDialog(mainWindow, {
      title: 'Scegli la cartella di sincronizzazione (la stessa di iPhone e iPad)',
      defaultPath: fs.existsSync(root) ? root : os.homedir(),
      properties: ['openDirectory'],
    });
    return result.canceled ? null : result.filePaths[0];
  });

  ipcMain.handle('dialog:openBackup', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: 'Importa backup',
      defaultPath: fs.existsSync(iCloudRoot()) ? iCloudRoot() : os.homedir(),
      filters: [{ name: 'Backup ExamsTrack', extensions: ['json'] }],
      properties: ['openFile'],
    });
    if (result.canceled) return null;
    return { path: result.filePaths[0], text: await fsp.readFile(result.filePaths[0], 'utf8') };
  });

  ipcMain.handle('dialog:saveBackup', async (_e, fileName, text) => {
    const result = await dialog.showSaveDialog(mainWindow, {
      title: 'Esporta dati',
      defaultPath: path.join(app.getPath('documents'), `${fileName}.json`),
      filters: [{ name: 'JSON', extensions: ['json'] }],
    });
    if (result.canceled || !result.filePath) return false;
    await fsp.writeFile(result.filePath, text, 'utf8');
    return true;
  });

  ipcMain.handle('shell:openFolder', (_e, folder) => shell.openPath(folder));

  ipcMain.handle('notify', (_e, title, body) => {
    if (!Notification.isSupported()) return;
    const notification = new Notification({ title, body, icon: iconPath });
    notification.on('click', showWindow);
    notification.show();
  });

  ipcMain.handle('app:getDesktopSettings', () => ({
    ...desktopSettings,
    openAtLogin: app.getLoginItemSettings().openAtLogin,
    version: app.getVersion(),
    dataDir: dataDir(),
  }));
  ipcMain.handle('app:setCloseToTray', (_e, value) => {
    desktopSettings.closeToTray = Boolean(value);
    saveDesktopSettings();
  });
  ipcMain.handle('app:setOpenAtLogin', (_e, value) => {
    app.setLoginItemSettings({ openAtLogin: Boolean(value), args: ['--hidden'] });
  });

  ipcMain.handle('widget:setConfig', (_e, change) => setWidgetConfig(change));
  ipcMain.on('widget:update', (event, data) => {
    if (event.sender === mainWindow?.webContents) widget.update(data);
  });

  ipcMain.handle('update:getState', () => updater.getState());
  ipcMain.handle('update:check', () => updater.check());
  ipcMain.handle('update:install', () => {
    if (updater.getState().status === 'downloaded') quit({ restart: true });
  });
  ipcMain.handle('update:openReleasePage', () => updater.openReleasePage());
  ipcMain.handle('app:setAutoUpdate', (_e, value) => {
    desktopSettings.autoUpdate = Boolean(value);
    saveDesktopSettings();
    updater.schedule();
    if (desktopSettings.autoUpdate) updater.check();
  });
}

// MARK: Widget sul desktop

/** Cambia le impostazioni del widget (dalle Impostazioni o dal menu dell'icona) e avvisa la finestra. */
function setWidgetConfig(change) {
  const allowed = {};
  if ('enabled' in change) allowed.enabled = Boolean(change.enabled);
  if ('examID' in change) allowed.examID = change.examID ? String(change.examID) : null;
  if ('includeOtherExams' in change) allowed.includeOtherExams = Boolean(change.includeOtherExams);
  if (['small', 'medium', 'large'].includes(change.size)) allowed.size = change.size;
  if ('locked' in change) allowed.locked = Boolean(change.locked);
  desktopSettings.widget = { ...desktopSettings.widget, ...allowed };
  saveDesktopSettings();
  widget.setSize(desktopSettings.widget.size);
  widget.setVisible(desktopSettings.widget.enabled);
  widget.refresh();
  updateTrayMenu();
  mainWindow?.webContents.send('app:desktopChanged');
}

function setupWidget() {
  widget.init({
    iconPath,
    getPosition: () => desktopSettings.widget.position,
    savePosition: (position) => {
      desktopSettings.widget.position = position;
      saveDesktopSettings();
    },
    isLocked: () => desktopSettings.widget.locked,
    setLocked: (locked) => setWidgetConfig({ locked }),
    open: (target) => {
      const existed = Boolean(mainWindow);
      showWindow();
      if (existed) mainWindow.webContents.send('widget:open', target);
    },
    toggleTask: (examID, taskID) => mainWindow?.webContents.send('widget:toggleTask', { examID, taskID }),
    hide: () => setWidgetConfig({ enabled: false }),
  });
  widget.setSize(desktopSettings.widget.size);
  widget.setVisible(desktopSettings.widget.enabled);
}

// MARK: Finestra e area di notifica

function showWindow() {
  if (!mainWindow) {
    createWindow(true);
    return;
  }
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
}

function createWindow(show = !startHidden) {
  mainWindow = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 920,
    minHeight: 620,
    show: false,
    title: 'ExamsTrack',
    icon: iconPath,
    backgroundColor: '#0E1117',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: true,
    },
  });
  Menu.setApplicationMenu(null);
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  mainWindow.once('ready-to-show', () => {
    if (show) mainWindow.show();
  });

  // I link esterni si aprono nel browser, mai dentro l'app.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event) => event.preventDefault());
  mainWindow.webContents.on('before-input-event', (_event, input) => {
    if (input.type === 'keyDown' && input.key === 'F12') mainWindow.webContents.toggleDevTools();
  });

  mainWindow.on('focus', () => mainWindow.webContents.send('app:focus'));
  mainWindow.on('close', (event) => {
    if (!isQuitting && desktopSettings.closeToTray) {
      // Resta attiva per promemoria e sincronizzazione; prima invia le modifiche.
      event.preventDefault();
      mainWindow.hide();
      mainWindow.webContents.send('app:hidden');
    }
  });
  mainWindow.on('closed', () => {
    mainWindow = null;
    // Il widget è una finestra a parte: senza l'icona nell'area di notifica l'app si chiude comunque.
    if (!desktopSettings.closeToTray) quit();
  });
}

function createTray() {
  tray = new Tray(nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 }));
  tray.setToolTip('ExamsTrack');
  updateTrayMenu();
  tray.on('click', showWindow);
}

function updateTrayMenu() {
  tray?.setContextMenu(Menu.buildFromTemplate([
    { label: 'Apri ExamsTrack', click: showWindow },
    { label: 'Sincronizza ora', click: () => mainWindow?.webContents.send('sync:now') },
    { label: 'Controlla aggiornamenti', click: () => updater.check() },
    { type: 'separator' },
    {
      label: 'Widget sul desktop',
      type: 'checkbox',
      checked: desktopSettings.widget.enabled,
      click: (item) => setWidgetConfig({ enabled: item.checked }),
    },
    {
      label: 'Blocca posizione del widget',
      type: 'checkbox',
      checked: desktopSettings.widget.locked,
      enabled: desktopSettings.widget.enabled,
      click: (item) => setWidgetConfig({ locked: item.checked }),
    },
    { type: 'separator' },
    { label: 'Esci', click: quit },
  ]));
}

/**
 * Uscita: aspetta che la finestra invii le ultime modifiche alla cartella (al massimo 15 secondi),
 * poi installa l'aggiornamento scaricato, se c'è. Con `restart` riapre l'app aggiornata.
 */
let quitPromise = null;
function quit({ restart = false } = {}) {
  if (quitPromise) return quitPromise;
  isQuitting = true;
  quitPromise = new Promise((resolve) => {
    if (!mainWindow) return resolve();
    const timer = setTimeout(resolve, 15_000);
    ipcMain.once('app:readyToQuit', () => {
      clearTimeout(timer);
      resolve();
    });
    mainWindow.webContents.send('app:beforeQuit');
  }).then(() => {
    if (updater.installOnQuit({ restart })) {
      // quitAndInstall chiude l'app da solo; se l'installer non parte, si esce comunque.
      setTimeout(() => app.exit(0), 10_000);
    } else {
      app.exit(0);
    }
  });
  return quitPromise;
}

// MARK: Avvio

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', showWindow);
  app.setAppUserModelId(APP_ID);
  nativeTheme.themeSource = 'dark';

  app.whenReady().then(() => {
    loadDesktopSettings();
    registerFileHandlers();
    registerAppHandlers();
    createWindow();
    createTray();
    setupWidget();
    updater.init({
      iconPath,
      isAutoCheckEnabled: () => desktopSettings.autoUpdate,
      onState: (state) => mainWindow?.webContents.send('update:state', state),
      showWindow,
    });
  });

  app.on('before-quit', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      quit();
    }
  });
  app.on('window-all-closed', () => {
    // Con l'icona nell'area di notifica l'app resta attiva; altrimenti si chiude.
    if (!desktopSettings.closeToTray) quit();
  });
}
