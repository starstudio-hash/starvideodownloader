"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("starDownloader", {
  getState: () => ipcRenderer.invoke("app:getState"),
  openBuy: () => ipcRenderer.invoke("shell:openBuy"),
  activateLicense: (key) => ipcRenderer.invoke("license:activate", key),
  validateLicense: () => ipcRenderer.invoke("license:validate"),
  deactivateLicense: () => ipcRenderer.invoke("license:deactivate"),
  chooseOutputDirectory: () => ipcRenderer.invoke("dialog:chooseOutputDirectory"),
  chooseVideoFile: () => ipcRenderer.invoke("dialog:chooseVideoFile"),
  installYtDlp: () => ipcRenderer.invoke("tools:installYtDlp"),
  installFfmpeg: () => ipcRenderer.invoke("tools:installFfmpeg"),
  startDownload: (payload) => ipcRenderer.invoke("downloads:start", payload),
  convertFile: (payload) => ipcRenderer.invoke("media:convert", payload),
  repairFile: (payload) => ipcRenderer.invoke("media:repair", payload),
  onStateUpdate: (callback) => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on("state:update", listener);
    return () => ipcRenderer.removeListener("state:update", listener);
  }
});
