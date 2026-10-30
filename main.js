const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const { scanAndPlan, executePlan } = require('./lib/organizer');

let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1140,
    height: 820,
    minWidth: 860,
    minHeight: 640,
    backgroundColor: '#0b0f19',
    autoHideMenuBar: true,
    title: 'Sonix Media & Playlist Organizer',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// Native folder picker
ipcMain.handle('dialog:openDirectory', async (event, defaultPath) => {
  if (!mainWindow) return null;
  const result = await dialog.showOpenDialog(mainWindow, {
    defaultPath: defaultPath || undefined,
    properties: ['openDirectory', 'createDirectory'],
  });
  if (result.canceled || result.filePaths.length === 0) {
    return null;
  }
  return result.filePaths[0];
});

// Scan & Plan
ipcMain.handle('organizer:scan', async (event, options) => {
  try {
    const plan = await scanAndPlan(options);
    return { success: true, plan };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// Execute Plan
ipcMain.handle('organizer:execute', async (event, { plan, options }) => {
  try {
    const summary = await executePlan(plan, options, (progressEvent) => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('organizer:progress', progressEvent);
      }
    });
    return { success: true, summary };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// Open Folder in System File Manager
ipcMain.handle('shell:openPath', async (event, folderPath) => {
  if (folderPath) {
    await shell.openPath(folderPath);
  }
});
