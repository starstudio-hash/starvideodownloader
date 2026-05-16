"use strict";

const fs = require("node:fs");
const https = require("node:https");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { URL } = require("node:url");

const YTDLP_WINDOWS_URL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
const FFMPEG_WINDOWS_URL = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip";

function buildToolPaths(userDataPath) {
  const binDir = path.join(userDataPath, "bin");
  return {
    binDir,
    ytdlpPath: path.join(binDir, "yt-dlp.exe"),
    ffmpegPath: path.join(binDir, "ffmpeg.exe"),
    ffprobePath: path.join(binDir, "ffprobe.exe")
  };
}

function getToolStatus(userDataPath) {
  const paths = buildToolPaths(userDataPath);
  return {
    ...paths,
    ytdlpInstalled: fs.existsSync(paths.ytdlpPath) || Boolean(findOnPath("yt-dlp.exe")),
    ffmpegInstalled: fs.existsSync(paths.ffmpegPath) || Boolean(findOnPath("ffmpeg.exe")),
    ffprobeInstalled: fs.existsSync(paths.ffprobePath) || Boolean(findOnPath("ffprobe.exe")),
    ytdlpVersion: readVersion(fs.existsSync(paths.ytdlpPath) ? paths.ytdlpPath : findOnPath("yt-dlp.exe"), ["--version"]),
    ffmpegVersion: readVersion(fs.existsSync(paths.ffmpegPath) ? paths.ffmpegPath : findOnPath("ffmpeg.exe"), ["-version"])
  };
}

function getExecutablePath(userDataPath, executableName) {
  const paths = buildToolPaths(userDataPath);
  if (executableName === "yt-dlp.exe") {
    return fs.existsSync(paths.ytdlpPath) ? paths.ytdlpPath : findOnPath("yt-dlp.exe");
  }
  if (executableName === "ffmpeg.exe") {
    return fs.existsSync(paths.ffmpegPath) ? paths.ffmpegPath : findOnPath("ffmpeg.exe");
  }
  if (executableName === "ffprobe.exe") {
    return fs.existsSync(paths.ffprobePath) ? paths.ffprobePath : findOnPath("ffprobe.exe");
  }
  return findOnPath(executableName);
}

async function installYtDlp(userDataPath, onProgress = () => {}) {
  const paths = buildToolPaths(userDataPath);
  fs.mkdirSync(paths.binDir, { recursive: true });
  onProgress("Downloading yt-dlp.exe...");
  await downloadFile(YTDLP_WINDOWS_URL, paths.ytdlpPath);
  onProgress("yt-dlp.exe installed.");
  return getToolStatus(userDataPath);
}

async function installFfmpeg(userDataPath, onProgress = () => {}) {
  if (process.platform !== "win32") {
    throw new Error("Automatic ffmpeg install is only available from the Windows PC app.");
  }

  const paths = buildToolPaths(userDataPath);
  const archivePath = path.join(paths.binDir, "ffmpeg-windows.zip");
  const extractDir = path.join(paths.binDir, "ffmpeg-extract");
  fs.mkdirSync(paths.binDir, { recursive: true });
  fs.rmSync(extractDir, { recursive: true, force: true });

  onProgress("Downloading ffmpeg for Windows...");
  await downloadFile(FFMPEG_WINDOWS_URL, archivePath);

  onProgress("Extracting ffmpeg...");
  await runPowerShell([
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    `Expand-Archive -LiteralPath ${quotePowerShell(archivePath)} -DestinationPath ${quotePowerShell(extractDir)} -Force`
  ]);

  const ffmpeg = findFileRecursive(extractDir, "ffmpeg.exe");
  const ffprobe = findFileRecursive(extractDir, "ffprobe.exe");
  if (!ffmpeg) {
    throw new Error("Downloaded ffmpeg archive did not contain ffmpeg.exe.");
  }

  fs.copyFileSync(ffmpeg, paths.ffmpegPath);
  if (ffprobe) {
    fs.copyFileSync(ffprobe, paths.ffprobePath);
  }
  fs.rmSync(archivePath, { force: true });
  fs.rmSync(extractDir, { recursive: true, force: true });
  onProgress("ffmpeg installed.");
  return getToolStatus(userDataPath);
}

function makeProcessEnv(userDataPath) {
  const paths = buildToolPaths(userDataPath);
  const env = { ...process.env };
  const pathKey = Object.keys(env).find((key) => key.toLowerCase() === "path") || "PATH";
  env[pathKey] = [paths.binDir, env[pathKey]].filter(Boolean).join(path.delimiter);
  return env;
}

function findOnPath(executableName) {
  const pathKey = Object.keys(process.env).find((key) => key.toLowerCase() === "path") || "PATH";
  const entries = String(process.env[pathKey] || "").split(path.delimiter);
  for (const entry of entries) {
    if (!entry) {
      continue;
    }
    const candidate = path.join(entry, executableName);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return "";
}

function readVersion(executablePath, args) {
  if (!executablePath) {
    return "";
  }
  const result = spawnSync(executablePath, args, {
    encoding: "utf8",
    timeout: 5000,
    windowsHide: true
  });
  const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
  return output.split(/\r?\n/)[0] || "";
}

function downloadFile(url, destination) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const request = https.get(parsed, (response) => {
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        response.resume();
        downloadFile(response.headers.location, destination).then(resolve, reject);
        return;
      }

      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Download failed with HTTP ${response.statusCode}.`));
        return;
      }

      const tempPath = `${destination}.download`;
      const file = fs.createWriteStream(tempPath);
      response.pipe(file);
      file.on("finish", () => {
        file.close(() => {
          fs.renameSync(tempPath, destination);
          resolve(destination);
        });
      });
      file.on("error", reject);
    });

    request.on("error", reject);
    request.setTimeout(120000, () => {
      request.destroy(new Error("Download timed out."));
    });
  });
}

function runPowerShell(args) {
  return new Promise((resolve, reject) => {
    const child = spawn("powershell.exe", args, { windowsHide: true });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `PowerShell exited with code ${code}.`));
      }
    });
  });
}

function quotePowerShell(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function findFileRecursive(root, fileName) {
  const entries = fs.readdirSync(root, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);
    if (entry.isFile() && entry.name.toLowerCase() === fileName.toLowerCase()) {
      return fullPath;
    }
    if (entry.isDirectory()) {
      const found = findFileRecursive(fullPath, fileName);
      if (found) {
        return found;
      }
    }
  }
  return "";
}

module.exports = {
  FFMPEG_WINDOWS_URL,
  YTDLP_WINDOWS_URL,
  buildToolPaths,
  downloadFile,
  getExecutablePath,
  getToolStatus,
  installFfmpeg,
  installYtDlp,
  makeProcessEnv,
  quotePowerShell,
  readVersion
};
