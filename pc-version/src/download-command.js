"use strict";

const path = require("node:path");
const { DEFAULT_SETTINGS } = require("./settings-store");

const QUALITIES = [
  "2160p (4K)",
  "1440p (2K)",
  "1080p",
  "720p",
  "480p",
  "360p",
  "Audio only",
  "Best available"
];

const FORMATS = ["MP4", "MKV", "MP3", "M4A", "WebM"];

const QUALITY_FORMATS = {
  "2160p (4K)": "bestvideo[height<=2160]+bestaudio/best[height<=2160]",
  "1440p (2K)": "bestvideo[height<=1440]+bestaudio/best[height<=1440]",
  "1080p": "bestvideo[height<=1080]+bestaudio/best[height<=1080]",
  "720p": "bestvideo[height<=720]+bestaudio/best[height<=720]",
  "480p": "bestvideo[height<=480]+bestaudio/best[height<=480]",
  "360p": "bestvideo[height<=360]+bestaudio/best[height<=360]",
  "Audio only": "bestaudio/best",
  "Best available": "bestvideo+bestaudio/best"
};

const PRO_ONLY_QUALITIES = new Set(["2160p (4K)", "1440p (2K)", "Best available"]);
const DEFAULT_QUALITY = "1080p";
const DEFAULT_FORMAT = "MP4";

function normalizeQuality(quality) {
  return QUALITIES.includes(quality) ? quality : DEFAULT_QUALITY;
}

function normalizeFormat(format) {
  return FORMATS.includes(format) ? format : DEFAULT_FORMAT;
}

function clampQualityForTier(quality, hasFullAccess) {
  const normalized = normalizeQuality(quality);
  if (!hasFullAccess && PRO_ONLY_QUALITIES.has(normalized)) {
    return DEFAULT_QUALITY;
  }
  return normalized;
}

function isProbablyUrl(value) {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

function buildYtDlpArgs(options) {
  const url = String(options.url || "").trim();
  if (!isProbablyUrl(url)) {
    const error = new Error("Enter a valid http or https video URL.");
    error.code = "INVALID_URL";
    throw error;
  }

  const settings = {
    ...DEFAULT_SETTINGS,
    ...(options.settings && typeof options.settings === "object" ? options.settings : {})
  };
  const hasFullAccess = Boolean(options.hasFullAccess);
  const playlist = Boolean(options.playlist);
  const sponsorBlockRequested = Boolean(options.sponsorBlock || settings.sponsorBlockEnabled);
  if (playlist && !hasFullAccess) {
    const error = new Error("Playlist downloads require Pro.");
    error.code = "PRO_REQUIRED";
    throw error;
  }
  if (sponsorBlockRequested && !hasFullAccess) {
    const error = new Error("SponsorBlock removal requires Pro.");
    error.code = "PRO_REQUIRED";
    throw error;
  }

  const outputDirectory = options.outputDirectory || settings.defaultOutputDirectory || process.cwd();
  const format = normalizeFormat(options.format);
  const quality = clampQualityForTier(options.quality, hasFullAccess);
  const isAudioJob = format === "MP3" || format === "M4A" || quality === "Audio only";
  const mergeFormat = format.toLowerCase();
  const subtitlesEnabled = Boolean(options.subtitles || settings.downloadSubtitlesByDefault);
  const sponsorBlockEnabled = sponsorBlockRequested;
  const outputTemplate = buildOutputTemplate(outputDirectory, settings.filenameTemplate, settings);

  const args = [
    "--newline",
    "--no-color",
    "--paths",
    outputDirectory,
    "-o",
    outputTemplate
  ];

  if (isAudioJob) {
    const audioFormat = format === "M4A" ? "m4a" : "mp3";
    args.push("-x", "--audio-format", audioFormat, "--audio-quality", "0");
  } else {
    args.push("-f", QUALITY_FORMATS[quality], "--merge-output-format", mergeFormat);
  }

  if (playlist) {
    args.push("--yes-playlist");
  } else {
    args.push("--no-playlist");
  }

  if (subtitlesEnabled) {
    args.push("--write-subs", "--write-auto-subs", "--sub-langs", "all", "--convert-subs", "srt");
  }

  if (sponsorBlockEnabled) {
    args.push("--sponsorblock-remove", settings.sponsorBlockMode || "all");
  }

  if (settings.rateLimitEnabled && settings.rateLimitSpeed) {
    args.push("--limit-rate", settings.rateLimitSpeed);
  }

  if (settings.useDownloadArchive && options.downloadArchivePath) {
    args.push("--download-archive", options.downloadArchivePath);
  }

  if (settings.concurrentFragments > 1) {
    args.push("--concurrent-fragments", String(settings.concurrentFragments));
  }

  if (settings.formatSortString) {
    args.push("-S", settings.formatSortString);
  }

  if (settings.sleepIntervalEnabled) {
    const min = Math.max(0, Number(settings.sleepIntervalMin) || 0);
    const max = Math.max(min, Number(settings.sleepIntervalMax) || min);
    args.push("--sleep-interval", String(min));
    if (max > min) {
      args.push("--max-sleep-interval", String(max));
    }
  }

  if (settings.matchFilter) {
    args.push("--match-filter", settings.matchFilter);
  }

  if (playlist && settings.playlistItemsFilter) {
    args.push("--playlist-items", settings.playlistItemsFilter);
  }

  if (settings.cookiesFromBrowser && settings.cookiesFromBrowser !== "none") {
    args.push("--cookies-from-browser", settings.cookiesFromBrowser);
  }

  if (settings.cookiesFilePath) {
    args.push("--cookies", settings.cookiesFilePath);
  }

  if (settings.embedThumbnail) {
    args.push("--embed-thumbnail");
  }

  if (settings.embedMetadata) {
    args.push("--embed-metadata");
  }

  if (settings.embedChapters) {
    args.push("--embed-chapters");
  }

  if (settings.splitChapters) {
    args.push("--split-chapters");
  }

  if (settings.embedSubtitles) {
    args.push("--embed-subs");
  }

  if (settings.liveFromStart) {
    args.push("--live-from-start");
  }

  if (settings.waitForVideo) {
    args.push("--wait-for-video", "60");
  }

  if (settings.geoBypass) {
    args.push("--geo-bypass");
    if (settings.geoBypassCountry) {
      args.push("--geo-bypass-country", settings.geoBypassCountry);
    }
  }

  if (settings.convertThumbnailsFormat) {
    args.push("--convert-thumbnails", settings.convertThumbnailsFormat);
  }

  if (settings.fileConflictBehavior === "skip") {
    args.push("--no-overwrites");
  } else if (settings.fileConflictBehavior === "overwrite") {
    args.push("--force-overwrites");
  }

  args.push(url);

  return {
    args,
    effectiveQuality: quality,
    effectiveFormat: format,
    outputDirectory
  };
}

function buildOutputTemplate(outputDirectory, filenameTemplate, settings = {}) {
  const template = String(filenameTemplate || "").trim() || "%(title).200B.%(ext)s";
  const filename = template.includes("%(ext)") ? template : `${template}.%(ext)s`;
  const organizer = organizationTemplate(settings);
  return organizer ? path.join(outputDirectory, organizer, filename) : path.join(outputDirectory, filename);
}

function organizationTemplate(settings) {
  if (!settings || !settings.autoOrganize) {
    return "";
  }

  switch (settings.organizeBy) {
    case "playlist":
      return "%(playlist_title)s";
    case "channel":
      return "%(channel)s";
    case "format":
      return "%(ext)s";
    case "date":
      return "%(upload_date)s";
    default:
      return "";
  }
}

function parseYtDlpProgress(line) {
  const text = String(line || "");
  const percentMatch = text.match(/\[download]\s+([0-9]+(?:\.[0-9]+)?)%/);
  if (!percentMatch) {
    return null;
  }

  const speedMatch = text.match(/\bat\s+([^\s]+\/s)/);
  const etaMatch = text.match(/\bETA\s+([0-9:]+)/);

  const progress = Math.round((Number(percentMatch[1]) / 100) * 10000) / 10000;

  return {
    progress: Math.max(0, Math.min(1, progress)),
    speed: speedMatch ? speedMatch[1] : "",
    eta: etaMatch ? etaMatch[1] : ""
  };
}

module.exports = {
  DEFAULT_FORMAT,
  DEFAULT_QUALITY,
  FORMATS,
  PRO_ONLY_QUALITIES,
  QUALITIES,
  QUALITY_FORMATS,
  buildYtDlpArgs,
  buildOutputTemplate,
  clampQualityForTier,
  organizationTemplate,
  normalizeFormat,
  normalizeQuality,
  parseYtDlpProgress
};
