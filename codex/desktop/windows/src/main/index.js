const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const EngineManager = require('./engine');

let mainWindow = null;
let engine = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1240,
    height: 840,
    minWidth: 860,
    minHeight: 620,
    frame: false,
    titleBarStyle: 'hidden',
    backgroundColor: '#212121',
    icon: path.join(__dirname, '..', '..', 'assets', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  // Initialize engine manager
  const sendToRenderer = (channel, data) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send(channel, data);
    }
  };

  engine = new EngineManager(app.getPath('userData'), sendToRenderer);
  engine.start();

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// Window control IPC
ipcMain.on('window:minimize', () => {
  if (mainWindow) mainWindow.minimize();
});

ipcMain.on('window:maximize', () => {
  if (mainWindow) {
    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow.maximize();
    }
  }
});

ipcMain.on('window:close', () => {
  if (mainWindow) mainWindow.close();
});

// Engine IPC Handlers
ipcMain.handle('engine:initialize', async () => {
  return { ready: engine.ready, models: engine.models, account: engine.account };
});

ipcMain.handle('engine:listModels', async () => {
  return engine.models;
});

ipcMain.handle('engine:listConversations', async () => {
  return engine.getConversations();
});

ipcMain.handle('engine:startConversation', async (_event, params) => {
  const convs = engine.getConversations();
  const id = `conv-${Date.now()}`;
  const newConv = {
    id,
    title: params?.title || 'Nova conversa',
    cwd: engine.storageDir,
    createdAt: Date.now(),
    messages: []
  };
  convs.unshift(newConv);
  engine.saveConversations(convs);
  return newConv;
});

ipcMain.handle('engine:deleteConversation', async (_event, id) => {
  let convs = engine.getConversations();
  convs = convs.filter(c => c.id !== id);
  engine.saveConversations(convs);
  return { success: true };
});

ipcMain.handle('engine:sendTurn', async (_event, data) => {
  return engine.sendTurn(data);
});

ipcMain.handle('engine:abortTurn', async () => {
  if (engine.activeTurnProcess) {
    engine.activeTurnProcess.kill();
    engine.activeTurnProcess = null;
  }
  return { success: true };
});

// Accounts & API Keys IPC
ipcMain.handle('engine:listAccounts', async () => {
  try {
    const data = JSON.parse(require('fs').readFileSync(engine.accountsPath, 'utf-8'));
    return data.accounts || [];
  } catch {
    return [];
  }
});

ipcMain.handle('engine:switchAccount', async (_event, id) => {
  try {
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync(engine.accountsPath, 'utf-8'));
    data.accounts.forEach(a => a.active = (a.id === id));
    data.activeId = id;
    fs.writeFileSync(engine.accountsPath, JSON.stringify(data, null, 2));
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('engine:getApiKeys', async () => {
  try {
    return JSON.parse(require('fs').readFileSync(engine.apiKeysPath, 'utf-8'));
  } catch {
    return {};
  }
});

ipcMain.handle('engine:saveApiKey', async (_event, provider, key) => {
  try {
    const fs = require('fs');
    const keys = JSON.parse(fs.readFileSync(engine.apiKeysPath, 'utf-8'));
    keys[provider] = key;
    fs.writeFileSync(engine.apiKeysPath, JSON.stringify(keys, null, 2));
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

ipcMain.handle('engine:deleteApiKey', async (_event, provider) => {
  try {
    const fs = require('fs');
    const keys = JSON.parse(fs.readFileSync(engine.apiKeysPath, 'utf-8'));
    delete keys[provider];
    fs.writeFileSync(engine.apiKeysPath, JSON.stringify(keys, null, 2));
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// Space Items
ipcMain.handle('space:listItems', async () => {
  try {
    return JSON.parse(require('fs').readFileSync(engine.spacePath, 'utf-8'));
  } catch {
    return [];
  }
});

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
