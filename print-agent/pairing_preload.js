const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("printAgent", {
  pair: (serverUrl, pairingCode) => ipcRenderer.invoke("pair", { serverUrl, pairingCode })
});
