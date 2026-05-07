const path = require('path');
const { app, BrowserWindow, ipcMain, screen } = require('electron');

let mainWindow;

function createWindow() {
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;

  mainWindow = new BrowserWindow({
    width: 360,
    height: 560,
    x: width - 380,
    y: height - 620,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    resizable: false,
    skipTaskbar: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.setAlwaysOnTop(true, 'screen-saver');
  mainWindow.loadFile(path.join(__dirname, 'src', 'index.html'));
}

app.whenReady().then(() => {
  createWindow();

  ipcMain.on('drag-window', (_event, delta) => {
    if (!mainWindow || !delta) return;
    const [x, y] = mainWindow.getPosition();
    mainWindow.setPosition(x + delta.dx, y + delta.dy);
  });

  ipcMain.on('quit-app', () => {
    app.quit();
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
