"use strict";

const path = require("node:path");

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

  const hasFullAccess = Boolean(options.hasFullAccess);
  const playlist = Boolean(options.playlist);
  if (playlist && !hasFullAccess) {
    const error = new Error("Playlist downloads require Pro.");
    error.code = "PRO_REQUIRED";
    throw error;
  }
  if (options.sponsorBlock && !hasFullAccess) {
    const error = new Error("SponsorBlock removal requires Pro.");
    error.code = "PRO_REQUIRED";
    throw error;
  }

  const outputDirectory = options.outputDirectory || process.cwd();
  const format = normalizeFormat(options.format);
  const quality = clampQualityForTier(options.quality, hasFullAccess);
  const isAudioJob = format === "MP3" || format === "M4A" || quality === "Audio only";
  const mergeFormat = format.toLowerCase();

  const args = [
    "--newline",
    "--no-color",
    "--paths",
    outputDirectory,
    "-o",
    path.join(outputDirectory, "%(title).200B.%(ext)s")
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

  if (options.subtitles) {
    args.push("--write-subs", "--write-auto-subs", "--sub-langs", "all", "--convert-subs", "srt");
  }

  if (options.sponsorBlock) {
    args.push("--sponsorblock-remove", "all");
  }

  args.push(url);

  return {
    args,
    effectiveQuality: quality,
    effectiveFormat: format,
    outputDirectory
  };
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
  clampQualityForTier,
  normalizeFormat,
  normalizeQuality,
  parseYtDlpProgress
};
