"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { SettingsStore, sanitizeSettings } = require("../src/settings-store");

function tempFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), "star-settings-")), "settings.json");
}

test("sanitizes unsupported settings back to safe defaults", () => {
  const settings = sanitizeSettings({
    defaultQuality: "9000p",
    defaultFormat: "AVI",
    maxConcurrentDownloads: 999,
    duplicateHandling: "maybe",
    scheduledDownloadTime: "99:99",
    selectedVideoCodec: "mystery",
    organizeBy: "magic",
    postDownloadAction: "selfDestruct",
    sleepIntervalMin: -1,
    sleepIntervalMax: 99999
  });

  assert.equal(settings.defaultQuality, "1080p");
  assert.equal(settings.defaultFormat, "MP4");
  assert.equal(settings.maxConcurrentDownloads, 10);
  assert.equal(settings.duplicateHandling, "ask");
  assert.equal(settings.scheduledDownloadTime, "02:00");
  assert.equal(settings.selectedVideoCodec, "h264");
  assert.equal(settings.organizeBy, "none");
  assert.equal(settings.postDownloadAction, "none");
  assert.equal(settings.sleepIntervalMin, 0);
  assert.equal(settings.sleepIntervalMax, 3600);
});

test("persists settings updates to disk", () => {
  const filePath = tempFile();
  const store = new SettingsStore({ filePath });

  store.update({
    defaultQuality: "Best available",
    clipboardMonitoring: true,
    maxConcurrentDownloads: 6,
    autoOrganize: true,
    organizeBy: "playlist",
    postDownloadAction: "runScript"
  });

  const reloaded = new SettingsStore({ filePath });
  assert.equal(reloaded.getState().defaultQuality, "Best available");
  assert.equal(reloaded.getState().clipboardMonitoring, true);
  assert.equal(reloaded.getState().maxConcurrentDownloads, 6);
  assert.equal(reloaded.getState().autoOrganize, true);
  assert.equal(reloaded.getState().organizeBy, "playlist");
  assert.equal(reloaded.getState().postDownloadAction, "runScript");
});
