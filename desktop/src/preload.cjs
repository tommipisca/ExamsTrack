// Ponte tra la finestra e il processo principale: solo le operazioni che servono all'app.

const { contextBridge, ipcRenderer } = require('electron');

const invoke = (channel) => (...args) => ipcRenderer.invoke(channel, ...args);
const on = (channel) => (callback) => {
  const listener = () => callback();
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
};

contextBridge.exposeInMainWorld('api', {
  fs: {
    dataDir: invoke('fs:dataDir'),
    join: invoke('fs:join'),
    readText: invoke('fs:readText'),
    writeText: invoke('fs:writeText'),
    writeTexts: invoke('fs:writeTexts'),
    list: invoke('fs:list'),
    mkdir: invoke('fs:mkdir'),
    remove: invoke('fs:remove'),
    rename: invoke('fs:rename'),
    isDirectory: invoke('fs:isDirectory'),
  },
  detectSyncFolder: invoke('sync:detect'),
  watchSyncFolder: invoke('sync:watch'),
  chooseFolder: invoke('dialog:chooseFolder'),
  openBackup: invoke('dialog:openBackup'),
  saveBackup: invoke('dialog:saveBackup'),
  openFolder: invoke('shell:openFolder'),
  notify: invoke('notify'),
  getDesktopSettings: invoke('app:getDesktopSettings'),
  setCloseToTray: invoke('app:setCloseToTray'),
  setOpenAtLogin: invoke('app:setOpenAtLogin'),
  readyToQuit: () => ipcRenderer.send('app:readyToQuit'),
  onFocus: on('app:focus'),
  onHidden: on('app:hidden'),
  onBeforeQuit: on('app:beforeQuit'),
  onSyncNow: on('sync:now'),
  onFolderChanged: on('sync:folderChanged'),
});
