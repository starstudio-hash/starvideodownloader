"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { randomUUID } = require("node:crypto");

class HistoryStore {
  constructor(options = {}) {
    this.filePath = options.filePath || path.join(os.homedir(), ".star-video-downloader-pc-history.json");
    this.entries = this.load();
  }

  load() {
    try {
      const raw = fs.readFileSync(this.filePath, "utf8");
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed.map(normalizeEntry) : [];
    } catch {
      return [];
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    fs.writeFileSync(this.filePath, JSON.stringify(this.entries, null, 2), "utf8");
  }

  getEntries() {
    return [...this.entries];
  }

  recordJob(job) {
    const entry = normalizeEntry({
      id: randomUUID(),
      kind: job.kind || "download",
      title: job.title || job.url || job.inputPath || job.outputPath || "Media job",
      url: job.url || "",
      channelName: job.channelName || "",
      date: new Date().toISOString(),
      outputPath: job.outputPath || "",
      quality: job.quality || "",
      format: job.format || "",
      fileSize: readFileSize(job.outputPath),
      source: job.source || "app"
    });
    this.entries = [entry, ...this.entries].slice(0, 250);
    this.save();
    return entry;
  }

  clear() {
    this.entries = [];
    this.save();
    return [];
  }

  exportJson() {
    return JSON.stringify(this.entries, null, 2);
  }

  exportCsv() {
    const header = ["Kind", "Title", "URL", "Channel", "Date", "Quality", "Format", "File Size", "Output Path"];
    const rows = this.entries.map((entry) => [
      entry.kind,
      entry.title,
      entry.url,
      entry.channelName,
      entry.date,
      entry.quality,
      entry.format,
      entry.fileSize ? String(entry.fileSize) : "",
      entry.outputPath
    ]);

    return [header, ...rows]
      .map((row) => row.map(csvEscape).join(","))
      .join("\n");
  }
}

function normalizeEntry(entry) {
  return {
    id: typeof entry.id === "string" ? entry.id : randomUUID(),
    kind: typeof entry.kind === "string" ? entry.kind : "download",
    title: typeof entry.title === "string" ? entry.title : "Media job",
    url: typeof entry.url === "string" ? entry.url : "",
    channelName: typeof entry.channelName === "string" ? entry.channelName : "",
    date: typeof entry.date === "string" ? entry.date : new Date().toISOString(),
    outputPath: typeof entry.outputPath === "string" ? entry.outputPath : "",
    quality: typeof entry.quality === "string" ? entry.quality : "",
    format: typeof entry.format === "string" ? entry.format : "",
    fileSize: Number.isFinite(entry.fileSize) ? entry.fileSize : null,
    source: typeof entry.source === "string" ? entry.source : "app"
  };
}

function readFileSize(filePath) {
  if (!filePath) {
    return null;
  }
  try {
    const stats = fs.statSync(filePath);
    return stats.isFile() ? stats.size : null;
  } catch {
    return null;
  }
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\n]/.test(text)) {
    return `"${text.replace(/"/g, "\"\"")}"`;
  }
  return text;
}

module.exports = {
  HistoryStore
};
