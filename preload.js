const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('desktopPet', {
  dragWindow: (dx, dy) => ipcRenderer.send('drag-window', { dx, dy }),
  quit: () => ipcRenderer.send('quit-app')
});
