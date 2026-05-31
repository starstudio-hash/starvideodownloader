"use strict";

const path = require("node:path");

const CONVERSION_FORMATS = ["MP4", "MKV", "WebM", "MP3", "M4A"];

function assertInputPath(inputPath) {
  if (!inputPath || typeof inputPath !== "string") {
    const error = new Error("Choose an input file first.");
    error.code = "MISSING_INPUT";
    throw error;
  }
}

function buildDefaultOutputPath(inputPath, suffix, format) {
  const ext = `.${format.toLowerCase()}`;
  const parsed = path.parse(inputPath);
  return path.join(parsed.dir, `${parsed.name}-${suffix}${ext}`);
}

function buildFfmpegConvertArgs(options) {
  assertInputPath(options.inputPath);
  const format = CONVERSION_FORMATS.includes(options.format) ? options.format : "MP4";
  const outputPath = options.outputPath || buildDefaultOutputPath(options.inputPath, "converted", format);
  const args = ["-y", "-i", options.inputPath];

  if (format === "MP3") {
    args.push("-vn", "-codec:a", "libmp3lame", "-q:a", "2");
  } else if (format === "M4A") {
    args.push("-vn", "-codec:a", "aac", "-b:a", "192k");
  } else if (format === "MP4") {
    args.push("-c:v", "libx264", "-preset", "medium", "-crf", "22", "-c:a", "aac", "-movflags", "+faststart");
  } else {
    args.push("-c", "copy");
  }

  args.push(outputPath);
  return { args, outputPath, format };
}

function buildFfmpegRepairArgs(options) {
  assertInputPath(options.inputPath);
  const mode = options.mode === "transcode" ? "transcode" : "rewrap";
  const outputPath = options.outputPath || buildDefaultOutputPath(options.inputPath, "repaired", "mp4");
  const args = ["-y", "-err_detect", "ignore_err", "-i", options.inputPath, "-map", "0"];

  if (mode === "transcode") {
    args.push("-c:v", "libx264", "-preset", "medium", "-crf", "22", "-c:a", "aac");
  } else {
    args.push("-c", "copy");
  }

  args.push("-movflags", "+faststart", outputPath);
  return { args, outputPath, mode };
}

module.exports = {
  CONVERSION_FORMATS,
  buildDefaultOutputPath,
  buildFfmpegConvertArgs,
  buildFfmpegRepairArgs
};
