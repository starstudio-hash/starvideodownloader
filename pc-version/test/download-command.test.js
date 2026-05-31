"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const {
  buildYtDlpArgs,
  clampQualityForTier,
  parseYtDlpProgress
} = require("../src/download-command");

test("free tier clamps Pro-only quality to 1080p", () => {
  assert.equal(clampQualityForTier("2160p (4K)", false), "1080p");
  assert.equal(clampQualityForTier("Best available", false), "1080p");
  assert.equal(clampQualityForTier("720p", false), "720p");
  assert.equal(clampQualityForTier("2160p (4K)", true), "2160p (4K)");
});

test("builds Windows-safe yt-dlp args for a standard MP4 download", () => {
  const outputDirectory = path.join("C:", "Users", "Tester", "Downloads");
  const result = buildYtDlpArgs({
    url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    quality: "2160p (4K)",
    format: "MP4",
    outputDirectory,
    hasFullAccess: false
  });

  assert.equal(result.effectiveQuality, "1080p");
  assert.equal(result.effectiveFormat, "MP4");
  assert.ok(result.args.includes("--no-playlist"));
  assert.ok(result.args.includes("--merge-output-format"));
  assert.ok(result.args.includes("mp4"));
  assert.ok(result.args.includes(path.join(outputDirectory, "%(title).200B.%(ext)s")));
});

test("playlist downloads require Pro", () => {
  assert.throws(() => buildYtDlpArgs({
    url: "https://www.youtube.com/playlist?list=123",
    playlist: true,
    hasFullAccess: false
  }), /Playlist downloads require Pro/);
});

test("SponsorBlock removal requires Pro and emits yt-dlp flags", () => {
  assert.throws(() => buildYtDlpArgs({
    url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    sponsorBlock: true,
    hasFullAccess: false
  }), /SponsorBlock removal requires Pro/);

  const result = buildYtDlpArgs({
    url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    sponsorBlock: true,
    hasFullAccess: true
  });
  assert.ok(result.args.includes("--sponsorblock-remove"));
  assert.ok(result.args.includes("all"));
});

test("audio jobs use extraction flags", () => {
  const result = buildYtDlpArgs({
    url: "https://example.com/video",
    quality: "Audio only",
    format: "MP3",
    hasFullAccess: true
  });

  assert.ok(result.args.includes("-x"));
  assert.ok(result.args.includes("--audio-format"));
  assert.ok(result.args.includes("mp3"));
});

test("parses yt-dlp progress lines", () => {
  const progress = parseYtDlpProgress("[download]  42.7% of 100.00MiB at 4.21MiB/s ETA 00:13");

  assert.equal(progress.progress, 0.427);
  assert.equal(progress.speed, "4.21MiB/s");
  assert.equal(progress.eta, "00:13");
});
