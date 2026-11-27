const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('wisdAI', {
  // Engine actions
  initialize: () => ipcRenderer.invoke('engine:initialize'),
  listModels: () => ipcRenderer.invoke('engine:listModels'),
  listConversations: () => ipcRenderer.invoke('engine:listConversations'),
  startConversation: (params) => ipcRenderer.invoke('engine:startConversation', params),
  deleteConversation: (id) => ipcRenderer.invoke('engine:deleteConversation', id),
  sendTurn: (data) => ipcRenderer.invoke('engine:sendTurn', data),
  abortTurn: () => ipcRenderer.invoke('engine:abortTurn'),
  
  // Accounts & API keys
  getAccountStatus: () => ipcRenderer.invoke('engine:getAccountStatus'),
  listAccounts: () => ipcRenderer.invoke('engine:listAccounts'),
  switchAccount: (id) => ipcRenderer.invoke('engine:switchAccount', id),
  saveAccount: (account) => ipcRenderer.invoke('engine:saveAccount', account),
  removeAccount: (id) => ipcRenderer.invoke('engine:removeAccount', id),
  getApiKeys: () => ipcRenderer.invoke('engine:getApiKeys'),
  saveApiKey: (provider, key) => ipcRenderer.invoke('engine:saveApiKey', provider, key),
  deleteApiKey: (provider) => ipcRenderer.invoke('engine:deleteApiKey', provider),

  // Space / Files
  listSpaceItems: () => ipcRenderer.invoke('space:listItems'),
  saveSpaceItem: (item) => ipcRenderer.invoke('space:saveItem', item),
  deleteSpaceItem: (id) => ipcRenderer.invoke('space:deleteItem', id),

  // Window Controls
  minimizeWindow: () => ipcRenderer.send('window:minimize'),
  maximizeWindow: () => ipcRenderer.send('window:maximize'),
  closeWindow: () => ipcRenderer.send('window:close'),

  // Event Listeners
  onStreamChunk: (callback) => {
    const handler = (_event, chunk) => callback(chunk);
    ipcRenderer.on('engine:streamChunk', handler);
    return () => ipcRenderer.removeListener('engine:streamChunk', handler);
  },
  onStreamEnd: (callback) => {
    const handler = (_event, result) => callback(result);
    ipcRenderer.on('engine:streamEnd', handler);
    return () => ipcRenderer.removeListener('engine:streamEnd', handler);
  },
  onEngineStatus: (callback) => {
    const handler = (_event, status) => callback(status);
    ipcRenderer.on('engine:status', handler);
    return () => ipcRenderer.removeListener('engine:status', handler);
  }
});
