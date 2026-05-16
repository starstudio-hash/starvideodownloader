"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const {
  buildDefaultOutputPath,
  buildFfmpegConvertArgs,
  buildFfmpegRepairArgs
} = require("../src/media-command");

test("builds conversion args for mp4 output", () => {
  const inputPath = path.join("C:", "Videos", "clip.mkv");
  const result = buildFfmpegConvertArgs({ inputPath, format: "MP4" });

  assert.ok(result.args.includes("-i"));
  assert.ok(result.args.includes(inputPath));
  assert.ok(result.args.includes("libx264"));
  assert.equal(result.outputPath, buildDefaultOutputPath(inputPath, "converted", "MP4"));
});

test("builds repair args for fast rewrap", () => {
  const inputPath = path.join("C:", "Videos", "broken.mp4");
  const result = buildFfmpegRepairArgs({ inputPath, mode: "rewrap" });

  assert.ok(result.args.includes("-err_detect"));
  assert.ok(result.args.includes("ignore_err"));
  assert.ok(result.args.includes("-c"));
  assert.ok(result.args.includes("copy"));
  assert.equal(result.mode, "rewrap");
});

test("builds repair args for deep transcode", () => {
  const result = buildFfmpegRepairArgs({
    inputPath: path.join("C:", "Videos", "broken.mov"),
    mode: "transcode"
  });

  assert.ok(result.args.includes("libx264"));
  assert.ok(result.args.includes("aac"));
  assert.equal(result.mode, "transcode");
});
