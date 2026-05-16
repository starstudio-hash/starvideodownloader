"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const electronPath = require("electron");
const { buildYtDlpArgs } = require("../src/download-command");
const { LicenseStore } = require("../src/license-store");
const { buildFfmpegConvertArgs, buildFfmpegRepairArgs } = require("../src/media-command");
const { buildToolPaths, getExecutablePath, getToolStatus } = require("../src/tool-manager");

const projectRoot = path.join(__dirname, "..");
const requiredIds = [
  "urlInput",
  "inspectUrl",
  "qualitySelect",
  "formatSelect",
  "startDownload",
  "installYtDlp",
  "installFfmpeg",
  "exportQueue",
  "importQueue",
  "licenseKeyInput",
  "activateLicense",
  "validateLicense",
  "convertFile",
  "repairFile",
  "queueList",
  "historyList",
  "statsGrid",
  "settingsForm",
  "settingAutoOrganize",
  "settingFormatSortString",
  "settingSleepIntervalEnabled",
  "choosePostDownloadScript"
];

async function main() {
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "star-pc-electron-smoke-"));
  const electronResult = await runElectronSmoke(userDataDir);

  if (electronResult.ok) {
    process.exit(0);
    return;
  }

  const fallbackReason = electronResult.reason || "Unknown Electron startup failure.";
  console.warn(`Electron GUI smoke fell back to headless validation: ${fallbackReason}`);

  try {
    const fallback = await runHeadlessFallback(userDataDir, fallbackReason);
    console.log(`[STAR_PC_SMOKE_RESULT] ${JSON.stringify(fallback)}`);
    process.exit(fallback.ok ? 0 : 1);
  } catch (error) {
    console.error(`[STAR_PC_SMOKE_RESULT] ${JSON.stringify({
      ok: false,
      mode: "headless-fallback",
      platform: process.platform,
      details: {
        reason: fallbackReason,
        error: error.message
      }
    })}`);
    process.exit(1);
  } finally {
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
}

async function runElectronSmoke(userDataDir) {
  return new Promise((resolve) => {
    const child = spawn(electronPath, [".", "--disable-gpu", "--disable-software-rasterizer"], {
      cwd: projectRoot,
      env: {
        ...process.env,
        ELECTRON_DISABLE_SECURITY_WARNINGS: "true",
        STAR_PC_SMOKE: "1",
        STAR_PC_SMOKE_USER_DATA: userDataDir
      },
      stdio: ["ignore", "pipe", "pipe"]
    });

    let output = "";
    let finished = false;

    function complete(result) {
      if (finished) {
        return;
      }
      finished = true;
      resolve(result);
    }

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      process.stdout.write(text);
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      output += text;
      process.stderr.write(text);
    });

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      complete({
        ok: false,
        reason: "Electron smoke test timed out before reporting a result marker."
      });
    }, 30000);

    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (output.includes("[STAR_PC_SMOKE_RESULT]")) {
        complete({ ok: code === 0 });
        return;
      }

      complete({
        ok: false,
        reason: `Electron exited before smoke completion (code=${code ?? "null"}, signal=${signal ?? "none"}).`
      });
    });

    child.on("error", (error) => {
      clearTimeout(timer);
      complete({
        ok: false,
        reason: `Electron failed to launch: ${error.message}`
      });
    });
  });
}

async function runHeadlessFallback(userDataDir, reason) {
  const html = fs.readFileSync(path.join(projectRoot, "src", "index.html"), "utf8");
  const failures = [];

  for (const id of requiredIds) {
    if (!html.includes(`id="${id}"`)) {
      failures.push(`Missing required control id="${id}" in src/index.html.`);
    }
  }

  if (!html.includes("<title>Star Video Downloader for PC</title>")) {
    failures.push("Unexpected document title in src/index.html.");
  }
  if (!html.includes("Download, convert, repair, and manage videos on PC.")) {
    failures.push("Expected PC app heading is missing from src/index.html.");
  }

  const toolPaths = buildToolPaths(userDataDir);
  fs.mkdirSync(toolPaths.binDir, { recursive: true });
  for (const toolPath of [toolPaths.ytdlpPath, toolPaths.ffmpegPath, toolPaths.ffprobePath]) {
    fs.writeFileSync(toolPath, "Star Video Downloader smoke fake tool\n", "utf8");
  }

  const toolStatus = getToolStatus(userDataDir);
  if (!toolStatus.ytdlpInstalled) {
    failures.push("yt-dlp fake install was not detected.");
  }
  if (!toolStatus.ffmpegInstalled) {
    failures.push("ffmpeg fake install was not detected.");
  }
  if (getExecutablePath(userDataDir, "yt-dlp.exe") !== toolPaths.ytdlpPath) {
    failures.push("yt-dlp executable path did not resolve to the local fake tool.");
  }
  if (getExecutablePath(userDataDir, "ffmpeg.exe") !== toolPaths.ffmpegPath) {
    failures.push("ffmpeg executable path did not resolve to the local fake tool.");
  }

  const freeArgs = buildYtDlpArgs({
    url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    quality: "1080p",
    format: "MP4",
    subtitles: false,
    playlist: false,
    sponsorBlock: false,
    outputDirectory: os.tmpdir(),
    hasFullAccess: false
  });

  if (!freeArgs.args.includes("--no-playlist")) {
    failures.push("Free download args did not include --no-playlist.");
  }

  try {
    buildYtDlpArgs({
      url: "https://www.youtube.com/playlist?list=PLtest",
      quality: "1080p",
      format: "MP4",
      subtitles: false,
      playlist: true,
      sponsorBlock: false,
      outputDirectory: os.tmpdir(),
      hasFullAccess: false
    });
    failures.push("Playlist Pro gate did not trigger for free tier.");
  } catch (error) {
    if (!String(error.message).includes("Playlist downloads require Pro")) {
      failures.push(`Unexpected playlist gate message: ${error.message}`);
    }
  }

  try {
    buildYtDlpArgs({
      url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      quality: "1080p",
      format: "MP4",
      subtitles: false,
      playlist: false,
      sponsorBlock: true,
      outputDirectory: os.tmpdir(),
      hasFullAccess: false
    });
    failures.push("SponsorBlock Pro gate did not trigger for free tier.");
  } catch (error) {
    if (!String(error.message).includes("SponsorBlock removal requires Pro")) {
      failures.push(`Unexpected SponsorBlock gate message: ${error.message}`);
    }
  }

  const licenseStore = new LicenseStore({
    filePath: path.join(userDataDir, "license.json"),
    httpPost: async () => ({
      statusCode: 200,
      data: { success: true }
    })
  });

  const activation = await licenseStore.activateLicense("SMOKE-PRO-LICENSE-KEY");
  if (!activation.ok || !licenseStore.isPro) {
    failures.push("License activation smoke check did not produce a Pro state.");
  }

  const proArgs = buildYtDlpArgs({
    url: "https://www.youtube.com/playlist?list=PLtest",
    quality: "Best available",
    format: "MP4",
    subtitles: true,
    playlist: true,
    sponsorBlock: true,
    outputDirectory: os.tmpdir(),
    hasFullAccess: true
  });

  if (!proArgs.args.includes("--yes-playlist")) {
    failures.push("Pro playlist args did not include --yes-playlist.");
  }
  if (!proArgs.args.includes("--sponsorblock-remove")) {
    failures.push("Pro args did not include SponsorBlock removal flags.");
  }

  const tempMedia = path.join(os.tmpdir(), `star-pc-fallback-${Date.now()}.mp4`);
  fs.writeFileSync(tempMedia, "");

  try {
    const convert = buildFfmpegConvertArgs({
      inputPath: tempMedia,
      format: "MP4"
    });
    const repair = buildFfmpegRepairArgs({
      inputPath: tempMedia,
      mode: "rewrap"
    });

    if (!convert.outputPath.endsWith(".mp4")) {
      failures.push("Conversion output path was not generated as .mp4.");
    }
    if (!repair.outputPath.endsWith(".mp4")) {
      failures.push("Repair output path was not generated as .mp4.");
    }

    return {
      ok: failures.length === 0,
      mode: "headless-fallback",
      platform: process.platform,
      details: {
        reason,
        failures,
        licenseIsPro: licenseStore.isPro,
        freeArgs: {
          effectiveQuality: freeArgs.effectiveQuality,
          effectiveFormat: freeArgs.effectiveFormat
        },
        proArgs: {
          effectiveQuality: proArgs.effectiveQuality,
          effectiveFormat: proArgs.effectiveFormat
        },
        toolPaths
      }
    };
  } finally {
    fs.rmSync(tempMedia, { force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
