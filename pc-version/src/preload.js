"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("starDownloader", {
  getState: () => ipcRenderer.invoke("app:getState"),
  openBuy: () => ipcRenderer.invoke("shell:openBuy"),
  revealPath: (filePath) => ipcRenderer.invoke("shell:revealPath", filePath),
  openExternal: (url) => ipcRenderer.invoke("shell:openExternal", url),
  activateLicense: (key) => ipcRenderer.invoke("license:activate", key),
  validateLicense: () => ipcRenderer.invoke("license:validate"),
  deactivateLicense: () => ipcRenderer.invoke("license:deactivate"),
  updateSettings: (patch) => ipcRenderer.invoke("settings:update", patch),
  clearHistory: () => ipcRenderer.invoke("history:clear"),
  exportHistory: (format) => ipcRenderer.invoke("history:export", format),
  exportQueue: () => ipcRenderer.invoke("queue:export"),
  importQueue: () => ipcRenderer.invoke("queue:import"),
  chooseOutputDirectory: () => ipcRenderer.invoke("dialog:chooseOutputDirectory"),
  chooseVideoFile: () => ipcRenderer.invoke("dialog:chooseVideoFile"),
  chooseCookiesFile: () => ipcRenderer.invoke("dialog:chooseCookiesFile"),
  chooseScriptFile: () => ipcRenderer.invoke("dialog:chooseScriptFile"),
  installYtDlp: () => ipcRenderer.invoke("tools:installYtDlp"),
  installFfmpeg: () => ipcRenderer.invoke("tools:installFfmpeg"),
  inspectDownload: (payload) => ipcRenderer.invoke("downloads:inspect", payload),
  startDownload: (payload) => ipcRenderer.invoke("downloads:start", payload),
  retryFailed: () => ipcRenderer.invoke("queue:retryFailed"),
  removeFailed: () => ipcRenderer.invoke("queue:removeFailed"),
  clearFinished: () => ipcRenderer.invoke("queue:clearFinished"),
  clearQueue: () => ipcRenderer.invoke("queue:clearAll"),
  convertFile: (payload) => ipcRenderer.invoke("media:convert", payload),
  repairFile: (payload) => ipcRenderer.invoke("media:repair", payload),
  onStateUpdate: (callback) => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on("state:update", listener);
    return () => ipcRenderer.removeListener("state:update", listener);
  },
  onToast: (callback) => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("app:toast", listener);
    return () => ipcRenderer.removeListener("app:toast", listener);
  }
});
