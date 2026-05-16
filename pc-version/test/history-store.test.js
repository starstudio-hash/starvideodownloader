"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { HistoryStore } = require("../src/history-store");

function tempFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), "star-history-")), "history.json");
}

test("records completed jobs and exports history", () => {
  const store = new HistoryStore({ filePath: tempFile() });
  const entry = store.recordJob({
    kind: "download",
    title: "Demo clip",
    url: "https://example.com/watch",
    quality: "1080p",
    format: "MP4"
  });

  assert.equal(entry.title, "Demo clip");
  assert.equal(store.getEntries().length, 1);
  assert.match(store.exportJson(), /Demo clip/);
  assert.match(store.exportCsv(), /Demo clip/);
});

test("clear removes saved history entries", () => {
  const store = new HistoryStore({ filePath: tempFile() });
  store.recordJob({ title: "One" });
  store.clear();

  assert.deepEqual(store.getEntries(), []);
});
