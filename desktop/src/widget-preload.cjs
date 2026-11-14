// Ponte tra il widget sul desktop e il processo principale.

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('widget', {
  ready: () => ipcRenderer.send('widget:ready'),
  onData: (callback) => ipcRenderer.on('widget:data', (_event, data) => callback(data)),
  toggleTask: (examID, taskID) => ipcRenderer.send('widget:toggleTask', examID, taskID),
  open: (examID) => ipcRenderer.send('widget:open', examID ?? null),
  menu: () => ipcRenderer.send('widget:menu'),
  dragStart: () => ipcRenderer.send('widget:dragStart'),
  drag: () => ipcRenderer.send('widget:drag'),
  dragEnd: () => ipcRenderer.send('widget:dragEnd'),
});
