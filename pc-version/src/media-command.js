"use strict";

const path = require("node:path");
const { DEFAULT_SETTINGS } = require("./settings-store");

const CONVERSION_FORMATS = ["MP4", "MKV", "WebM", "MP3", "M4A"];
const VIDEO_ENCODERS = {
  h264: "libx264",
  hevc: "libx265",
  vp9: "libvpx-vp9",
  copy: "copy"
};
const AUDIO_ENCODERS = {
  aac: "aac",
  opus: "libopus",
  flac: "flac",
  copy: "copy"
};
const QUALITY_PRESETS = {
  high: {
    crf: "18",
    aacBitrate: "256k",
    opusBitrate: "192k"
  },
  medium: {
    crf: "22",
    aacBitrate: "192k",
    opusBitrate: "128k"
  },
  low: {
    crf: "28",
    aacBitrate: "128k",
    opusBitrate: "96k"
  }
};

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
  const settings = {
    ...DEFAULT_SETTINGS,
    ...(options.settings && typeof options.settings === "object" ? options.settings : {})
  };
  const format = CONVERSION_FORMATS.includes(options.format) ? options.format : "MP4";
  const outputPath = options.outputPath || buildDefaultOutputPath(options.inputPath, "converted", format);
  const args = ["-y", "-i", options.inputPath];
  const qualityPreset = QUALITY_PRESETS[settings.encodingQuality] || QUALITY_PRESETS.medium;
  const videoCodec = settings.macCompatibleEncoding && format === "MP4" && settings.selectedVideoCodec !== "copy"
    ? "h264"
    : settings.selectedVideoCodec;
  const audioCodec = settings.macCompatibleEncoding && format === "MP4" && settings.selectedAudioCodec !== "copy"
    ? "aac"
    : settings.selectedAudioCodec;
  const videoEncoder = VIDEO_ENCODERS[videoCodec] || VIDEO_ENCODERS.h264;
  const audioEncoder = AUDIO_ENCODERS[audioCodec] || AUDIO_ENCODERS.aac;

  if (format === "MP3") {
    args.push("-vn", "-codec:a", "libmp3lame", "-q:a", "2");
  } else if (format === "M4A") {
    args.push("-vn", "-codec:a", audioEncoder === "copy" ? "aac" : audioEncoder);
    if (audioEncoder === "aac") {
      args.push("-b:a", qualityPreset.aacBitrate);
    } else if (audioEncoder === "libopus") {
      args.push("-b:a", qualityPreset.opusBitrate);
    }
  } else if (format === "MP4") {
    pushVideoArgs(args, videoEncoder, qualityPreset);
    pushAudioArgs(args, audioEncoder, qualityPreset);
    args.push("-movflags", "+faststart");
  } else {
    if (videoEncoder === "copy" && audioEncoder === "copy") {
      args.push("-c", "copy");
    } else {
      pushVideoArgs(args, format === "WebM" && videoEncoder === "copy" ? VIDEO_ENCODERS.vp9 : videoEncoder, qualityPreset);
      pushAudioArgs(args, format === "WebM" && audioEncoder === "copy" ? AUDIO_ENCODERS.opus : audioEncoder, qualityPreset);
    }
  }

  args.push(outputPath);
  return { args, outputPath, format };
}

function buildFfmpegRepairArgs(options) {
  assertInputPath(options.inputPath);
  const settings = {
    ...DEFAULT_SETTINGS,
    ...(options.settings && typeof options.settings === "object" ? options.settings : {})
  };
  const mode = options.mode === "transcode" ? "transcode" : "rewrap";
  const outputPath = options.outputPath || buildDefaultOutputPath(options.inputPath, "repaired", "mp4");
  const args = ["-y", "-err_detect", "ignore_err", "-i", options.inputPath, "-map", "0"];
  const qualityPreset = QUALITY_PRESETS[settings.encodingQuality] || QUALITY_PRESETS.medium;
  const videoCodec = settings.macCompatibleEncoding && settings.selectedVideoCodec !== "copy"
    ? "h264"
    : settings.selectedVideoCodec;
  const audioCodec = settings.macCompatibleEncoding && settings.selectedAudioCodec !== "copy"
    ? "aac"
    : settings.selectedAudioCodec;
  const videoEncoder = VIDEO_ENCODERS[videoCodec] || VIDEO_ENCODERS.h264;
  const audioEncoder = AUDIO_ENCODERS[audioCodec] || AUDIO_ENCODERS.aac;

  if (mode === "transcode") {
    pushVideoArgs(args, videoEncoder === "copy" ? VIDEO_ENCODERS.h264 : videoEncoder, qualityPreset);
    pushAudioArgs(args, audioEncoder === "copy" ? AUDIO_ENCODERS.aac : audioEncoder, qualityPreset);
  } else {
    args.push("-c", "copy");
  }

  args.push("-movflags", "+faststart", outputPath);
  return { args, outputPath, mode };
}

function pushVideoArgs(args, encoder, qualityPreset) {
  if (encoder === "copy") {
    args.push("-c:v", "copy");
    return;
  }

  args.push("-c:v", encoder);
  if (encoder === "libvpx-vp9") {
    args.push("-crf", qualityPreset.crf, "-b:v", "0", "-row-mt", "1");
    return;
  }
  args.push("-preset", "medium", "-crf", qualityPreset.crf);
}

function pushAudioArgs(args, encoder, qualityPreset) {
  if (encoder === "copy") {
    args.push("-c:a", "copy");
    return;
  }

  args.push("-c:a", encoder);
  if (encoder === "aac") {
    args.push("-b:a", qualityPreset.aacBitrate);
  } else if (encoder === "libopus") {
    args.push("-b:a", qualityPreset.opusBitrate);
  }
}

module.exports = {
  CONVERSION_FORMATS,
  buildDefaultOutputPath,
  buildFfmpegConvertArgs,
  buildFfmpegRepairArgs
};
