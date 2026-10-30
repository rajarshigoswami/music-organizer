const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  isElectron: true,
  selectFolder: (defaultPath) => ipcRenderer.invoke('dialog:openDirectory', defaultPath),
  scanFolder: (options) => ipcRenderer.invoke('organizer:scan', options),
  executePlan: (plan, options) => ipcRenderer.invoke('organizer:execute', { plan, options }),
  onProgress: (callback) => {
    const subscription = (event, data) => callback(data);
    ipcRenderer.on('organizer:progress', subscription);
    return () => ipcRenderer.removeListener('organizer:progress', subscription);
  },
  openPath: (folderPath) => ipcRenderer.invoke('shell:openPath', folderPath),
});
