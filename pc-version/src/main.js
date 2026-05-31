"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { spawn } = require("node:child_process");
const { app, BrowserWindow, dialog, ipcMain, shell } = require("electron");
const { BUY_PRO_URL } = require("./config");
const { buildYtDlpArgs, parseYtDlpProgress } = require("./download-command");
const { LicenseStore } = require("./license-store");
const { buildFfmpegConvertArgs, buildFfmpegRepairArgs } = require("./media-command");
const {
  buildToolPaths,
  getExecutablePath,
  getToolStatus,
  installFfmpeg,
  installYtDlp,
  makeProcessEnv
} = require("./tool-manager");

let mainWindow = null;
let licenseStore = null;
let jobs = [];
let toolInstallMessage = "";

if (process.env.STAR_PC_SMOKE_USER_DATA) {
  app.setPath("userData", process.env.STAR_PC_SMOKE_USER_DATA);
}

function initStores() {
  const userDataPath = app.getPath("userData");
  licenseStore = new LicenseStore({
    filePath: path.join(userDataPath, "license.json")
  });
}

function createWindow() {
  const smokeMode = process.env.STAR_PC_SMOKE === "1";
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 920,
    minHeight: 620,
    title: "Star Video Downloader",
    backgroundColor: "#f8fafc",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  mainWindow.loadFile(path.join(__dirname, "index.html"));
  if (smokeMode) {
    mainWindow.webContents.once("did-finish-load", () => runSmokeTest());
  }
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

function getState() {
  const userDataPath = app.getPath("userData");
  return {
    license: licenseStore.getPublicState(),
    tools: {
      ...getToolStatus(userDataPath),
      installMessage: toolInstallMessage
    },
    downloads: jobs,
    defaultOutputDirectory: app.getPath("downloads"),
    platform: process.platform
  };
}

function broadcastState() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("state:update", getState());
  }
}

function createJob(kind, details) {
  const job = {
    id: randomUUID(),
    kind,
    status: "queued",
    progress: 0,
    speed: "",
    eta: "",
    message: "",
    createdAt: new Date().toISOString(),
    ...details
  };
  jobs = [job, ...jobs].slice(0, 100);
  broadcastState();
  return job;
}

function updateJob(id, patch) {
  jobs = jobs.map((job) => (job.id === id ? { ...job, ...patch } : job));
  broadcastState();
}

function requirePro(featureName) {
  if (!licenseStore.isPro) {
    const error = new Error(`${featureName} requires Pro. Buy once for $5, then paste your Gumroad license key.`);
    error.code = "PRO_REQUIRED";
    throw error;
  }
}

function shouldUseSmokeFakeTool(executablePath) {
  return process.env.STAR_PC_SMOKE_FAKE_TOOLS === "1" &&
    Boolean(executablePath) &&
    path.resolve(executablePath).startsWith(path.resolve(app.getPath("userData")));
}

function runSmokeFakeProcess(job, executablePath, args) {
  updateJob(job.id, {
    status: "running",
    message: `Smoke-running ${path.basename(executablePath)}...`
  });

  setTimeout(() => updateJob(job.id, {
    status: "running",
    progress: 0.42,
    speed: "smoke/s",
    eta: "00:01",
    message: `${path.basename(executablePath)} smoke progress (${args.length} args).`
  }), 40);

  setTimeout(() => updateJob(job.id, {
    status: "completed",
    progress: 1,
    speed: "",
    eta: "",
    message: "Done."
  }), 120);
}

function waitForJobCompletion(jobId, timeoutMs = 5000) {
  const startedAt = Date.now();
  return new Promise((resolve, reject) => {
    const poll = () => {
      const job = jobs.find((candidate) => candidate.id === jobId);
      if (!job) {
        reject(new Error(`Smoke job ${jobId} was not found.`));
        return;
      }
      if (job.status === "completed") {
        resolve(job);
        return;
      }
      if (job.status === "failed") {
        reject(new Error(`Smoke job ${jobId} failed: ${job.message}`));
        return;
      }
      if (Date.now() - startedAt > timeoutMs) {
        reject(new Error(`Smoke job ${jobId} timed out in status ${job.status}.`));
        return;
      }
      setTimeout(poll, 40);
    };
    poll();
  });
}

function installSmokeFakeTools() {
  const paths = buildToolPaths(app.getPath("userData"));
  fs.mkdirSync(paths.binDir, { recursive: true });
  for (const toolPath of [paths.ytdlpPath, paths.ffmpegPath, paths.ffprobePath]) {
    fs.writeFileSync(toolPath, "Star Video Downloader smoke fake tool\n", "utf8");
    try {
      fs.chmodSync(toolPath, 0o755);
    } catch {
      // chmod is not meaningful on every Windows filesystem.
    }
  }
  process.env.STAR_PC_SMOKE_FAKE_TOOLS = "1";
  return paths;
}

function finishSmoke(ok, details) {
  const payload = {
    ok,
    platform: process.platform,
    details
  };
  const line = `[STAR_PC_SMOKE_RESULT] ${JSON.stringify(payload)}`;
  if (ok) {
    console.log(line);
    app.exit(0);
    return;
  }
  console.error(line);
  app.exit(1);
}

async function runSmokeTest() {
  const timeout = setTimeout(() => {
    finishSmoke(false, { error: "Smoke test timed out." });
  }, 15000);

  try {
    const state = getState();
    const dom = await mainWindow.webContents.executeJavaScript(`
      (async () => {
        const bridge = window.starDownloader;
        const state = bridge ? await bridge.getState() : null;
        const requiredIds = [
          "urlInput",
          "qualitySelect",
          "formatSelect",
          "startDownload",
          "installYtDlp",
          "installFfmpeg",
          "licenseKeyInput",
          "activateLicense",
          "validateLicense",
          "convertFile",
          "repairFile",
          "queueList"
        ];
        return {
          title: document.title,
          heading: document.querySelector("h1")?.textContent || "",
          hasBridge: Boolean(bridge),
          requiredIdsPresent: requiredIds.every((id) => Boolean(document.getElementById(id))),
          qualityOptions: Array.from(document.querySelectorAll("#qualitySelect option")).map((option) => option.textContent),
          formatOptions: Array.from(document.querySelectorAll("#formatSelect option")).map((option) => option.textContent),
          licenseSummary: document.getElementById("licenseSummary")?.textContent || "",
          outputDirectory: document.getElementById("outputDirectory")?.textContent || "",
          bridgeState: state
        };
      })();
    `);

    const downloadResult = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.startDownload({
        url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        quality: "1080p",
        format: "MP4",
        subtitles: false,
        playlist: false,
        sponsorBlock: false,
        outputDirectory: ${JSON.stringify(os.tmpdir())}
      }).then(
        () => ({ ok: true }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);

    const fakeToolPaths = installSmokeFakeTools();
    const freeDownloadJob = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.startDownload({
        url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        quality: "1080p",
        format: "MP4",
        subtitles: false,
        playlist: false,
        sponsorBlock: false,
        outputDirectory: ${JSON.stringify(os.tmpdir())}
      }).then(
        (job) => ({ ok: true, job }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);
    const freeDownloadCompleted = freeDownloadJob.ok
      ? await waitForJobCompletion(freeDownloadJob.job.id)
      : null;

    const playlistGate = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.startDownload({
        url: "https://www.youtube.com/playlist?list=PLtest",
        quality: "1080p",
        format: "MP4",
        subtitles: false,
        playlist: true,
        sponsorBlock: false,
        outputDirectory: ${JSON.stringify(os.tmpdir())}
      }).then(
        () => ({ ok: true }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);
    const sponsorBlockGate = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.startDownload({
        url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        quality: "1080p",
        format: "MP4",
        subtitles: false,
        playlist: false,
        sponsorBlock: true,
        outputDirectory: ${JSON.stringify(os.tmpdir())}
      }).then(
        () => ({ ok: true }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);

    licenseStore.state.licenseKey = "SMOKE-PRO-LICENSE-KEY";
    licenseStore.state.instanceID = "SMOKE-PRO-LICENSE-KEY";
    licenseStore.state.activationDate = new Date().toISOString();
    licenseStore.save();
    broadcastState();

    const proDownloadJob = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.startDownload({
        url: "https://www.youtube.com/playlist?list=PLtest",
        quality: "Best available",
        format: "MP4",
        subtitles: true,
        playlist: true,
        sponsorBlock: true,
        outputDirectory: ${JSON.stringify(os.tmpdir())}
      }).then(
        (job) => ({ ok: true, job }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);
    const proDownloadCompleted = proDownloadJob.ok
      ? await waitForJobCompletion(proDownloadJob.job.id)
      : null;

    const tempMedia = path.join(os.tmpdir(), `star-pc-smoke-${Date.now()}.mp4`);
    fs.writeFileSync(tempMedia, "");
    const convertGate = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.convertFile({
        inputPath: ${JSON.stringify(tempMedia)},
        format: "MP4"
      }).then(
        (job) => ({ ok: true, job }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);
    const convertCompleted = convertGate.ok
      ? await waitForJobCompletion(convertGate.job.id)
      : null;
    const repairGate = await mainWindow.webContents.executeJavaScript(`
      window.starDownloader.repairFile({
        inputPath: ${JSON.stringify(tempMedia)},
        mode: "rewrap"
      }).then(
        (job) => ({ ok: true, job }),
        (error) => ({ ok: false, message: error.message, code: error.code || "" })
      );
    `);
    const repairCompleted = repairGate.ok
      ? await waitForJobCompletion(repairGate.job.id)
      : null;

    fs.rmSync(tempMedia, { force: true });

    const failures = [];
    if (!dom.hasBridge) failures.push("Missing preload bridge.");
    if (!dom.requiredIdsPresent) failures.push("Missing required controls.");
    if (!dom.title.includes("Star Video Downloader for PC")) failures.push("Unexpected document title.");
    if (!dom.heading.includes("Download, convert, and repair videos on PC")) failures.push("Unexpected heading.");
    if (!dom.qualityOptions.includes("1080p") || !dom.qualityOptions.includes("Best available")) failures.push("Quality options did not render.");
    if (!dom.formatOptions.includes("MP4") || !dom.formatOptions.includes("MP3")) failures.push("Format options did not render.");
    if (!dom.licenseSummary.includes("Free tier")) failures.push("Free license summary did not render.");
    if (!state.defaultOutputDirectory || !dom.bridgeState.defaultOutputDirectory) failures.push("Default output directory missing.");
    if (dom.bridgeState.platform !== process.platform) failures.push("Renderer state platform mismatch.");
    if (!downloadResult.message.includes("Install yt-dlp")) failures.push(`Expected missing yt-dlp gate, got ${downloadResult.code || downloadResult.message}.`);
    if (!freeDownloadJob.ok || freeDownloadCompleted.status !== "completed") failures.push(`Expected fake free download to complete, got ${freeDownloadJob.message || freeDownloadCompleted?.status}.`);
    if (!playlistGate.message.includes("Playlist downloads require Pro")) failures.push(`Expected playlist Pro gate, got ${playlistGate.code || playlistGate.message}.`);
    if (!sponsorBlockGate.message.includes("SponsorBlock removal requires Pro")) failures.push(`Expected SponsorBlock Pro gate, got ${sponsorBlockGate.code || sponsorBlockGate.message}.`);
    if (!proDownloadJob.ok || proDownloadCompleted.status !== "completed") failures.push(`Expected fake Pro playlist download to complete, got ${proDownloadJob.message || proDownloadCompleted?.status}.`);
    if (!convertGate.ok || convertCompleted.status !== "completed") failures.push(`Expected fake conversion to complete, got ${convertGate.message || convertCompleted?.status}.`);
    if (!repairGate.ok || repairCompleted.status !== "completed") failures.push(`Expected fake repair to complete, got ${repairGate.message || repairCompleted?.status}.`);

    clearTimeout(timeout);
    finishSmoke(failures.length === 0, {
      failures,
      dom: {
        title: dom.title,
        heading: dom.heading,
        qualityOptions: dom.qualityOptions,
        formatOptions: dom.formatOptions,
        outputDirectory: dom.outputDirectory
      },
      state: {
        platform: state.platform,
        defaultOutputDirectory: state.defaultOutputDirectory,
        license: state.license,
        tools: state.tools,
        fakeToolPaths
      },
      gates: {
        missingToolDownload: downloadResult,
        freeDownload: freeDownloadCompleted,
        playlist: playlistGate,
        sponsorBlock: sponsorBlockGate,
        proDownload: proDownloadCompleted,
        convert: convertGate,
        convertCompleted,
        repair: repairGate,
        repairCompleted
      }
    });
  } catch (error) {
    clearTimeout(timeout);
    finishSmoke(false, {
      error: error.message,
      stack: error.stack
    });
  }
}

function spawnTrackedProcess(job, executablePath, args) {
  if (shouldUseSmokeFakeTool(executablePath)) {
    runSmokeFakeProcess(job, executablePath, args);
    return;
  }

  updateJob(job.id, {
    status: "running",
    message: `Running ${path.basename(executablePath)}...`
  });

  const child = spawn(executablePath, args, {
    env: makeProcessEnv(app.getPath("userData")),
    windowsHide: true
  });

  child.stdout.on("data", (chunk) => {
    const text = chunk.toString();
    const lines = text.split(/\r?\n/).filter(Boolean);
    let latestProgress = null;
    for (const line of lines) {
      latestProgress = parseYtDlpProgress(line) || latestProgress;
    }
    if (latestProgress) {
      updateJob(job.id, {
        status: "running",
        progress: latestProgress.progress,
        speed: latestProgress.speed,
        eta: latestProgress.eta,
        message: lines[lines.length - 1] || "Downloading..."
      });
    } else if (lines.length) {
      updateJob(job.id, { message: lines[lines.length - 1] });
    }
  });

  child.stderr.on("data", (chunk) => {
    const message = chunk.toString().trim();
    if (message) {
      updateJob(job.id, { message });
    }
  });

  child.on("error", (error) => {
    updateJob(job.id, {
      status: "failed",
      message: error.message
    });
  });

  child.on("close", (code) => {
    updateJob(job.id, {
      status: code === 0 ? "completed" : "failed",
      progress: code === 0 ? 1 : job.progress,
      message: code === 0 ? "Done." : `Process exited with code ${code}.`
    });
  });
}

app.whenReady().then(() => {
  initStores();
  registerIpc();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

function registerIpc() {
  ipcMain.handle("app:getState", () => getState());

  ipcMain.handle("shell:openBuy", async () => {
    await shell.openExternal(BUY_PRO_URL);
    return true;
  });

  ipcMain.handle("license:activate", async (_event, key) => {
    const result = await licenseStore.activateLicense(key);
    broadcastState();
    return result;
  });

  ipcMain.handle("license:validate", async () => {
    const result = await licenseStore.validateLicense();
    broadcastState();
    return result;
  });

  ipcMain.handle("license:deactivate", () => {
    const state = licenseStore.clear();
    broadcastState();
    return { ok: true, state };
  });

  ipcMain.handle("dialog:chooseOutputDirectory", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Choose output folder",
      properties: ["openDirectory", "createDirectory"]
    });
    return result.canceled ? "" : result.filePaths[0];
  });

  ipcMain.handle("dialog:chooseVideoFile", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Choose video file",
      properties: ["openFile"],
      filters: [
        { name: "Video and audio", extensions: ["mp4", "mov", "mkv", "webm", "avi", "m4v", "mp3", "m4a", "wav"] },
        { name: "All files", extensions: ["*"] }
      ]
    });
    return result.canceled ? "" : result.filePaths[0];
  });

  ipcMain.handle("tools:installYtDlp", async () => {
    toolInstallMessage = "Preparing yt-dlp install...";
    broadcastState();
    const status = await installYtDlp(app.getPath("userData"), (message) => {
      toolInstallMessage = message;
      broadcastState();
    });
    toolInstallMessage = "";
    broadcastState();
    return { ok: true, status };
  });

  ipcMain.handle("tools:installFfmpeg", async () => {
    toolInstallMessage = "Preparing ffmpeg install...";
    broadcastState();
    const status = await installFfmpeg(app.getPath("userData"), (message) => {
      toolInstallMessage = message;
      broadcastState();
    });
    toolInstallMessage = "";
    broadcastState();
    return { ok: true, status };
  });

  ipcMain.handle("downloads:start", async (_event, payload) => {
    const userDataPath = app.getPath("userData");
    const ytdlpPath = getExecutablePath(userDataPath, "yt-dlp.exe");
    if (!ytdlpPath) {
      const error = new Error("Install yt-dlp before starting a download.");
      error.code = "MISSING_YTDLP";
      throw error;
    }
    if (!licenseStore.canStartDownload()) {
      const error = new Error("Free downloads are finished for today. Upgrade to Pro for unlimited downloads.");
      error.code = "FREE_LIMIT_REACHED";
      throw error;
    }

    const options = buildYtDlpArgs({
      ...payload,
      outputDirectory: payload.outputDirectory || app.getPath("downloads"),
      hasFullAccess: licenseStore.isPro
    });
    const job = createJob("download", {
      url: payload.url,
      quality: options.effectiveQuality,
      format: options.effectiveFormat,
      outputDirectory: options.outputDirectory,
      playlist: Boolean(payload.playlist)
    });

    licenseStore.recordDownload();
    spawnTrackedProcess(job, ytdlpPath, options.args);
    return job;
  });

  ipcMain.handle("media:convert", async (_event, payload) => {
    requirePro("Video conversion");
    const ffmpegPath = getExecutablePath(app.getPath("userData"), "ffmpeg.exe");
    if (!ffmpegPath) {
      const error = new Error("Install ffmpeg before converting files.");
      error.code = "MISSING_FFMPEG";
      throw error;
    }

    const options = buildFfmpegConvertArgs(payload);
    const job = createJob("convert", {
      inputPath: payload.inputPath,
      outputPath: options.outputPath,
      format: options.format
    });
    spawnTrackedProcess(job, ffmpegPath, options.args);
    return job;
  });

  ipcMain.handle("media:repair", async (_event, payload) => {
    requirePro("Video repair");
    const ffmpegPath = getExecutablePath(app.getPath("userData"), "ffmpeg.exe");
    if (!ffmpegPath) {
      const error = new Error("Install ffmpeg before repairing files.");
      error.code = "MISSING_FFMPEG";
      throw error;
    }

    const options = buildFfmpegRepairArgs(payload);
    const job = createJob("repair", {
      inputPath: payload.inputPath,
      outputPath: options.outputPath,
      mode: options.mode
    });
    spawnTrackedProcess(job, ffmpegPath, options.args);
    return job;
  });
}
