"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const DEFAULT_SETTINGS = Object.freeze({
  defaultQuality: "1080p",
  defaultFormat: "MP4",
  downloadSubtitlesByDefault: false,
  defaultOutputDirectory: "",
  maxConcurrentDownloads: 3,
  duplicateHandling: "ask",
  sponsorBlockEnabled: false,
  sponsorBlockMode: "all",
  cookiesFromBrowser: "none",
  cookiesFilePath: "",
  rateLimitEnabled: false,
  rateLimitSpeed: "2M",
  useDownloadArchive: false,
  concurrentFragments: 1,
  playlistItemsFilter: "",
  matchFilter: "",
  notificationsEnabled: true,
  clipboardMonitoring: false,
  clipboardAction: "notify",
  launchAtLogin: false,
  scheduledDownloadEnabled: false,
  scheduledDownloadTime: "02:00",
  filenameTemplate: "%(title).200B.%(ext)s",
  autoOrganize: false,
  organizeBy: "none",
  embedThumbnail: false,
  embedMetadata: false,
  embedChapters: false,
  splitChapters: false,
  embedSubtitles: false,
  liveFromStart: false,
  waitForVideo: false,
  geoBypass: false,
  geoBypassCountry: "",
  fileConflictBehavior: "rename",
  convertThumbnailsFormat: "",
  selectedVideoCodec: "h264",
  selectedAudioCodec: "aac",
  encodingQuality: "medium",
  macCompatibleEncoding: true,
  postDownloadAction: "none",
  postDownloadScript: "",
  sleepIntervalEnabled: false,
  sleepIntervalMin: 3,
  sleepIntervalMax: 10,
  formatSortString: ""
});

const QUALITY_OPTIONS = new Set([
  "2160p (4K)",
  "1440p (2K)",
  "1080p",
  "720p",
  "480p",
  "360p",
  "Audio only",
  "Best available"
]);

const FORMAT_OPTIONS = new Set(["MP4", "MKV", "MP3", "M4A", "WebM"]);
const DUPLICATE_HANDLING = new Set(["ask", "skip", "allow"]);
const SPONSORBLOCK_MODES = new Set(["all", "sponsor", "intro", "outro", "selfpromo"]);
const BROWSER_COOKIE_SOURCES = new Set(["none", "chrome", "edge", "firefox", "brave"]);
const CLIPBOARD_ACTIONS = new Set(["notify", "addToQueue"]);
const ORGANIZE_BY_OPTIONS = new Set(["none", "playlist", "channel", "format", "date"]);
const FILE_CONFLICT_BEHAVIORS = new Set(["rename", "skip", "overwrite"]);
const THUMBNAIL_FORMATS = new Set(["", "jpg", "png", "webp"]);
const VIDEO_CODECS = new Set(["h264", "hevc", "vp9", "copy"]);
const AUDIO_CODECS = new Set(["aac", "opus", "flac", "copy"]);
const ENCODING_QUALITIES = new Set(["high", "medium", "low"]);
const POST_DOWNLOAD_ACTIONS = new Set(["none", "openFolder", "openFile", "runScript"]);

function ensureString(value, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function sanitizePath(value) {
  const raw = ensureString(value).trim();
  if (!raw) {
    return "";
  }
  return path.normalize(raw);
}

function sanitizeTimeString(value) {
  const raw = ensureString(value, DEFAULT_SETTINGS.scheduledDownloadTime).trim();
  if (!/^\d{2}:\d{2}$/.test(raw)) {
    return DEFAULT_SETTINGS.scheduledDownloadTime;
  }
  const [hour, minute] = raw.split(":").map((part) => Number(part));
  if (Number.isNaN(hour) || Number.isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return DEFAULT_SETTINGS.scheduledDownloadTime;
  }
  return raw;
}

function sanitizeSettings(value) {
  const source = value && typeof value === "object" ? value : {};
  const defaultOutputDirectory = sanitizePath(source.defaultOutputDirectory) || DEFAULT_SETTINGS.defaultOutputDirectory;

  return {
    defaultQuality: QUALITY_OPTIONS.has(source.defaultQuality) ? source.defaultQuality : DEFAULT_SETTINGS.defaultQuality,
    defaultFormat: FORMAT_OPTIONS.has(source.defaultFormat) ? source.defaultFormat : DEFAULT_SETTINGS.defaultFormat,
    downloadSubtitlesByDefault: Boolean(source.downloadSubtitlesByDefault),
    defaultOutputDirectory,
    maxConcurrentDownloads: clampInteger(source.maxConcurrentDownloads, 1, 10, DEFAULT_SETTINGS.maxConcurrentDownloads),
    duplicateHandling: DUPLICATE_HANDLING.has(source.duplicateHandling) ? source.duplicateHandling : DEFAULT_SETTINGS.duplicateHandling,
    sponsorBlockEnabled: Boolean(source.sponsorBlockEnabled),
    sponsorBlockMode: SPONSORBLOCK_MODES.has(source.sponsorBlockMode) ? source.sponsorBlockMode : DEFAULT_SETTINGS.sponsorBlockMode,
    cookiesFromBrowser: BROWSER_COOKIE_SOURCES.has(source.cookiesFromBrowser) ? source.cookiesFromBrowser : DEFAULT_SETTINGS.cookiesFromBrowser,
    cookiesFilePath: sanitizePath(source.cookiesFilePath),
    rateLimitEnabled: Boolean(source.rateLimitEnabled),
    rateLimitSpeed: ensureString(source.rateLimitSpeed, DEFAULT_SETTINGS.rateLimitSpeed).trim() || DEFAULT_SETTINGS.rateLimitSpeed,
    useDownloadArchive: Boolean(source.useDownloadArchive),
    concurrentFragments: clampInteger(source.concurrentFragments, 1, 8, DEFAULT_SETTINGS.concurrentFragments),
    playlistItemsFilter: ensureString(source.playlistItemsFilter).trim(),
    matchFilter: ensureString(source.matchFilter).trim(),
    notificationsEnabled: Boolean(source.notificationsEnabled),
    clipboardMonitoring: Boolean(source.clipboardMonitoring),
    clipboardAction: CLIPBOARD_ACTIONS.has(source.clipboardAction) ? source.clipboardAction : DEFAULT_SETTINGS.clipboardAction,
    launchAtLogin: Boolean(source.launchAtLogin),
    scheduledDownloadEnabled: Boolean(source.scheduledDownloadEnabled),
    scheduledDownloadTime: sanitizeTimeString(source.scheduledDownloadTime),
    filenameTemplate: ensureString(source.filenameTemplate, DEFAULT_SETTINGS.filenameTemplate).trim() || DEFAULT_SETTINGS.filenameTemplate,
    autoOrganize: Boolean(source.autoOrganize),
    organizeBy: ORGANIZE_BY_OPTIONS.has(source.organizeBy) ? source.organizeBy : DEFAULT_SETTINGS.organizeBy,
    embedThumbnail: Boolean(source.embedThumbnail),
    embedMetadata: Boolean(source.embedMetadata),
    embedChapters: Boolean(source.embedChapters),
    splitChapters: Boolean(source.splitChapters),
    embedSubtitles: Boolean(source.embedSubtitles),
    liveFromStart: Boolean(source.liveFromStart),
    waitForVideo: Boolean(source.waitForVideo),
    geoBypass: Boolean(source.geoBypass),
    geoBypassCountry: ensureString(source.geoBypassCountry).trim(),
    fileConflictBehavior: FILE_CONFLICT_BEHAVIORS.has(source.fileConflictBehavior) ? source.fileConflictBehavior : DEFAULT_SETTINGS.fileConflictBehavior,
    convertThumbnailsFormat: THUMBNAIL_FORMATS.has(source.convertThumbnailsFormat) ? source.convertThumbnailsFormat : DEFAULT_SETTINGS.convertThumbnailsFormat,
    selectedVideoCodec: VIDEO_CODECS.has(source.selectedVideoCodec) ? source.selectedVideoCodec : DEFAULT_SETTINGS.selectedVideoCodec,
    selectedAudioCodec: AUDIO_CODECS.has(source.selectedAudioCodec) ? source.selectedAudioCodec : DEFAULT_SETTINGS.selectedAudioCodec,
    encodingQuality: ENCODING_QUALITIES.has(source.encodingQuality) ? source.encodingQuality : DEFAULT_SETTINGS.encodingQuality,
    macCompatibleEncoding: source.macCompatibleEncoding === false ? false : DEFAULT_SETTINGS.macCompatibleEncoding,
    postDownloadAction: POST_DOWNLOAD_ACTIONS.has(source.postDownloadAction) ? source.postDownloadAction : DEFAULT_SETTINGS.postDownloadAction,
    postDownloadScript: sanitizePath(source.postDownloadScript),
    sleepIntervalEnabled: Boolean(source.sleepIntervalEnabled),
    sleepIntervalMin: clampInteger(source.sleepIntervalMin, 0, 3600, DEFAULT_SETTINGS.sleepIntervalMin),
    sleepIntervalMax: clampInteger(source.sleepIntervalMax, 0, 3600, DEFAULT_SETTINGS.sleepIntervalMax),
    formatSortString: ensureString(source.formatSortString).trim()
  };
}

function clampInteger(value, min, max, fallback) {
  const numeric = Number(value);
  if (!Number.isInteger(numeric)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, numeric));
}

class SettingsStore {
  constructor(options = {}) {
    this.filePath = options.filePath || path.join(os.homedir(), ".star-video-downloader-pc-settings.json");
    this.settings = this.load();
  }

  load() {
    try {
      const raw = fs.readFileSync(this.filePath, "utf8");
      return sanitizeSettings(JSON.parse(raw));
    } catch {
      return sanitizeSettings({
        defaultOutputDirectory: path.join(os.homedir(), "Downloads")
      });
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    fs.writeFileSync(this.filePath, JSON.stringify(this.settings, null, 2), "utf8");
  }

  getState() {
    return { ...this.settings };
  }

  update(patch = {}) {
    this.settings = sanitizeSettings({
      ...this.settings,
      ...(patch && typeof patch === "object" ? patch : {})
    });
    this.save();
    return this.getState();
  }
}

module.exports = {
  AUDIO_CODECS,
  DEFAULT_SETTINGS,
  ENCODING_QUALITIES,
  FILE_CONFLICT_BEHAVIORS,
  FORMAT_OPTIONS,
  ORGANIZE_BY_OPTIONS,
  POST_DOWNLOAD_ACTIONS,
  QUALITY_OPTIONS,
  SettingsStore,
  VIDEO_CODECS,
  sanitizeSettings
};
