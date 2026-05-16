"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { spawn } = require("node:child_process");
const { URL } = require("node:url");
const { app, BrowserWindow, clipboard, dialog, ipcMain, Notification, shell } = require("electron");
const {
  BUY_PRO_URL,
  FREE_MAX_CONCURRENT_DOWNLOADS,
  PRO_MAX_CONCURRENT_DOWNLOADS
} = require("./config");
const { buildYtDlpArgs, parseYtDlpProgress } = require("./download-command");
const { HistoryStore } = require("./history-store");
const { LicenseStore } = require("./license-store");
const { buildFfmpegConvertArgs, buildFfmpegRepairArgs } = require("./media-command");
const { SettingsStore } = require("./settings-store");
const {
  buildToolPaths,
  getExecutablePath,
  getToolStatus,
  installFfmpeg,
  installYtDlp,
  makeProcessEnv
} = require("./tool-manager");

const QUEUE_FILE = "queue.json";
const HISTORY_FILE = "history.json";
const SETTINGS_FILE = "settings.json";
const LICENSE_FILE = "license.json";
const DOWNLOAD_ARCHIVE_FILE = "download-archive.txt";
const QUEUE_PERSIST_DELAY_MS = 120;
const SCHEDULE_POLL_MS = 15000;
const CLIPBOARD_POLL_MS = 2000;
const TERMINAL_STATUSES = new Set(["completed", "failed", "cancelled"]);

let mainWindow = null;
let historyStore = null;
let licenseStore = null;
let settingsStore = null;
let jobs = [];
let jobProcesses = new Map();
let queuePersistTimer = null;
let clipboardTimer = null;
let schedulerTimer = null;
let toolInstallMessage = "";
let lastClipboardText = "";

if (process.env.STAR_PC_SMOKE_USER_DATA) {
  app.setPath("userData", process.env.STAR_PC_SMOKE_USER_DATA);
}

function appFile(name) {
  return path.join(app.getPath("userData"), name);
}

function initStores() {
  const userDataPath = app.getPath("userData");
  settingsStore = new SettingsStore({
    filePath: path.join(userDataPath, SETTINGS_FILE)
  });
  licenseStore = new LicenseStore({
    filePath: path.join(userDataPath, LICENSE_FILE)
  });
  historyStore = new HistoryStore({
    filePath: path.join(userDataPath, HISTORY_FILE)
  });
  jobs = loadJobs();
}

function loadJobs() {
  try {
    const raw = fs.readFileSync(appFile(QUEUE_FILE), "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.map(normalizeJob).filter(Boolean) : [];
  } catch {
    return [];
  }
}

function saveJobs() {
  clearTimeout(queuePersistTimer);
  queuePersistTimer = null;
  fs.mkdirSync(app.getPath("userData"), { recursive: true });
  fs.writeFileSync(appFile(QUEUE_FILE), JSON.stringify(jobs.map(serializeJob), null, 2), "utf8");
}

function persistJobsSoon() {
  clearTimeout(queuePersistTimer);
  queuePersistTimer = setTimeout(saveJobs, QUEUE_PERSIST_DELAY_MS);
}

function normalizeJob(raw) {
  if (!raw || typeof raw !== "object") {
    return null;
  }

  const status = normalizeRestoredStatus(raw.status, raw.scheduledStartAt);
  return {
    id: typeof raw.id === "string" ? raw.id : randomUUID(),
    kind: ["download", "convert", "repair"].includes(raw.kind) ? raw.kind : "download",
    status,
    progress: Number.isFinite(raw.progress) ? raw.progress : 0,
    speed: typeof raw.speed === "string" ? raw.speed : "",
    eta: typeof raw.eta === "string" ? raw.eta : "",
    message: typeof raw.message === "string" ? raw.message : "",
    createdAt: typeof raw.createdAt === "string" ? raw.createdAt : new Date().toISOString(),
    updatedAt: typeof raw.updatedAt === "string" ? raw.updatedAt : new Date().toISOString(),
    source: typeof raw.source === "string" ? raw.source : "app",
    url: typeof raw.url === "string" ? raw.url : "",
    title: typeof raw.title === "string" ? raw.title : "",
    channelName: typeof raw.channelName === "string" ? raw.channelName : "",
    duration: typeof raw.duration === "string" ? raw.duration : "",
    quality: typeof raw.quality === "string" ? raw.quality : "",
    format: typeof raw.format === "string" ? raw.format : "",
    subtitles: Boolean(raw.subtitles),
    playlist: Boolean(raw.playlist),
    sponsorBlock: Boolean(raw.sponsorBlock),
    outputDirectory: typeof raw.outputDirectory === "string" ? raw.outputDirectory : "",
    outputPath: typeof raw.outputPath === "string" ? raw.outputPath : "",
    inputPath: typeof raw.inputPath === "string" ? raw.inputPath : "",
    mode: typeof raw.mode === "string" ? raw.mode : "",
    duplicateKey: typeof raw.duplicateKey === "string" ? raw.duplicateKey : "",
    scheduledStartAt: typeof raw.scheduledStartAt === "string" ? raw.scheduledStartAt : "",
    downloadCounted: Boolean(raw.downloadCounted)
  };
}

function normalizeRestoredStatus(status, scheduledStartAt) {
  if (status === "running") {
    return "failed";
  }
  if (status === "scheduled" && scheduledStartAt) {
    const scheduled = Date.parse(scheduledStartAt);
    if (Number.isFinite(scheduled) && scheduled > Date.now()) {
      return "scheduled";
    }
  }
  if (status === "queued" || status === "scheduled") {
    return "queued";
  }
  return TERMINAL_STATUSES.has(status) ? status : "queued";
}

function serializeJob(job) {
  return {
    id: job.id,
    kind: job.kind,
    status: job.status,
    progress: job.progress,
    speed: job.speed,
    eta: job.eta,
    message: job.message,
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
    source: job.source,
    url: job.url,
    title: job.title,
    channelName: job.channelName,
    duration: job.duration,
    quality: job.quality,
    format: job.format,
    subtitles: job.subtitles,
    playlist: job.playlist,
    sponsorBlock: job.sponsorBlock,
    outputDirectory: job.outputDirectory,
    outputPath: job.outputPath,
    inputPath: job.inputPath,
    mode: job.mode,
    duplicateKey: job.duplicateKey,
    scheduledStartAt: job.scheduledStartAt,
    downloadCounted: job.downloadCounted
  };
}

function createWindow() {
  const smokeMode = process.env.STAR_PC_SMOKE === "1";
  mainWindow = new BrowserWindow({
    width: 1320,
    height: 900,
    minWidth: 1000,
    minHeight: 720,
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
  const settings = settingsStore.getState();

  return {
    license: licenseStore.getPublicState(),
    settings,
    tools: {
      ...getToolStatus(userDataPath),
      installMessage: toolInstallMessage
    },
    downloads: jobs,
    history: historyStore.getEntries(),
    defaultOutputDirectory: settings.defaultOutputDirectory || app.getPath("downloads"),
    platform: process.platform
  };
}

function broadcastState() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("state:update", getState());
  }
}

function sendToast(message) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send("app:toast", { message });
  }
}

function createJob(kind, details) {
  const scheduledStatus = shouldJobWaitForSchedule(details.scheduledStartAt) || shouldWaitForGlobalSchedule()
    ? "scheduled"
    : "queued";

  const job = {
    id: randomUUID(),
    kind,
    status: scheduledStatus,
    progress: 0,
    speed: "",
    eta: "",
    message: scheduledStatus === "scheduled" ? scheduledMessage(details.scheduledStartAt) : "",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    source: "app",
    title: "",
    channelName: "",
    duration: "",
    outputPath: "",
    downloadCounted: false,
    ...details
  };

  jobs = [job, ...jobs].slice(0, 150);
  persistJobsSoon();
  broadcastState();
  return job;
}

function updateJob(id, patchOrBuilder) {
  let updatedJob = null;
  jobs = jobs.map((job) => {
    if (job.id !== id) {
      return job;
    }
    const patch = typeof patchOrBuilder === "function" ? patchOrBuilder(job) : patchOrBuilder;
    updatedJob = {
      ...job,
      ...patch,
      updatedAt: new Date().toISOString()
    };
    return updatedJob;
  });
  if (updatedJob) {
    persistJobsSoon();
    broadcastState();
  }
  return updatedJob;
}

function removeJobs(predicate) {
  jobs = jobs.filter((job) => !predicate(job));
  persistJobsSoon();
  broadcastState();
}

function exportQueueJson() {
  return JSON.stringify({
    version: 1,
    exportedAt: new Date().toISOString(),
    jobs: jobs.map(serializeJob)
  }, null, 2);
}

function importQueueJson(raw) {
  const parsed = JSON.parse(raw);
  const sourceJobs = Array.isArray(parsed) ? parsed : parsed.jobs;
  if (!Array.isArray(sourceJobs)) {
    throw new Error("Queue import must be a Star Video Downloader queue JSON file.");
  }

  const knownIds = new Set(jobs.map((job) => job.id));
  const importedJobs = [];
  for (const rawJob of sourceJobs) {
    const normalized = normalizeJob(rawJob);
    if (!normalized) {
      continue;
    }
    if (knownIds.has(normalized.id)) {
      normalized.id = randomUUID();
    }
    knownIds.add(normalized.id);
    importedJobs.push({
      ...normalized,
      updatedAt: new Date().toISOString()
    });
  }

  jobs = [...importedJobs, ...jobs].slice(0, 150);
  persistJobsSoon();
  broadcastState();
  processQueues();
  return importedJobs.length;
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

function runSmokeFakeProcess(job, executablePath, args, onClose) {
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

  setTimeout(() => {
    updateJob(job.id, {
      status: "completed",
      progress: 1,
      speed: "",
      eta: "",
      message: "Done."
    });
    onClose(0);
  }, 120);
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
        url: "https://www.youtube.com/watch?v=starSmokeFree001",
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
        url: "https://www.youtube.com/watch?v=starSmokeSponsor001",
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
        url: "https://www.youtube.com/playlist?list=PLprotest",
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
    if (!dom.heading.includes("Download, convert, repair, and manage videos on PC")) failures.push("Unexpected heading.");
    if (!dom.qualityOptions.includes("1080p") || !dom.qualityOptions.includes("Best available")) failures.push("Quality options did not render.");
    if (!dom.formatOptions.includes("MP4") || !dom.formatOptions.includes("MP3")) failures.push("Format options did not render.");
    if (!dom.licenseSummary.includes("Free tier")) failures.push("Free license summary did not render.");
    if (!state.defaultOutputDirectory || !dom.bridgeState.defaultOutputDirectory) failures.push("Default output directory missing.");
    if (dom.bridgeState.platform !== process.platform) failures.push("Renderer state platform mismatch.");
    if (!String(downloadResult.message || "").includes("Install yt-dlp")) failures.push(`Expected missing yt-dlp gate, got ${downloadResult.code || downloadResult.message}.`);
    if (!freeDownloadJob.ok || freeDownloadCompleted.status !== "completed") failures.push(`Expected fake free download to complete, got ${freeDownloadJob.message || freeDownloadCompleted?.status}.`);
    if (!String(playlistGate.message || "").includes("Playlist downloads require Pro")) failures.push(`Expected playlist Pro gate, got ${playlistGate.code || playlistGate.message}.`);
    if (!String(sponsorBlockGate.message || "").includes("SponsorBlock removal requires Pro")) failures.push(`Expected SponsorBlock Pro gate, got ${sponsorBlockGate.code || sponsorBlockGate.message}.`);
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
        settings: state.settings,
        tools: state.tools,
        fakeToolPaths
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

function startJob(job) {
  if (job.kind === "download") {
    startDownloadJob(job);
    return;
  }

  if (job.kind === "convert") {
    startMediaJob(job, "Video conversion", "ffmpeg.exe", buildFfmpegConvertArgs({
      inputPath: job.inputPath,
      outputPath: job.outputPath,
      format: job.format,
      settings: settingsStore.getState()
    }));
    return;
  }

  startMediaJob(job, "Video repair", "ffmpeg.exe", buildFfmpegRepairArgs({
    inputPath: job.inputPath,
    outputPath: job.outputPath,
    mode: job.mode,
    settings: settingsStore.getState()
  }));
}

function startDownloadJob(job) {
  const userDataPath = app.getPath("userData");
  const ytdlpPath = getExecutablePath(userDataPath, "yt-dlp.exe");
  if (!ytdlpPath) {
    updateJob(job.id, {
      status: "failed",
      message: "Install yt-dlp before starting a download."
    });
    processQueues();
    return;
  }

  if (!licenseStore.canStartDownload()) {
    updateJob(job.id, {
      status: "failed",
      message: "Free downloads are finished for today. Upgrade to Pro for unlimited downloads."
    });
    processQueues();
    return;
  }

  const options = buildYtDlpArgs({
    url: job.url,
    quality: job.quality || settingsStore.getState().defaultQuality,
    format: job.format || settingsStore.getState().defaultFormat,
    subtitles: job.subtitles,
    playlist: job.playlist,
    sponsorBlock: job.sponsorBlock,
    outputDirectory: job.outputDirectory || settingsStore.getState().defaultOutputDirectory || app.getPath("downloads"),
    hasFullAccess: licenseStore.isPro,
    downloadArchivePath: appFile(DOWNLOAD_ARCHIVE_FILE),
    settings: settingsStore.getState()
  });

  if (!job.downloadCounted) {
    licenseStore.recordDownload();
  }

  updateJob(job.id, {
    status: "queued",
    quality: options.effectiveQuality,
    format: options.effectiveFormat,
    outputDirectory: options.outputDirectory,
    message: "",
    downloadCounted: true
  });

  spawnTrackedProcess(job.id, ytdlpPath, options.args, (result) => {
    if (result.ok) {
      const completedJob = jobs.find((candidate) => candidate.id === job.id);
      if (completedJob) {
        historyStore.recordJob(completedJob);
        onSuccessfulJob(completedJob);
      }
    }
    processQueues();
  });
}

function startMediaJob(job, proName, executableName, options) {
  requirePro(proName);
  const executablePath = getExecutablePath(app.getPath("userData"), executableName);
  if (!executablePath) {
    updateJob(job.id, {
      status: "failed",
      message: `Install ${executableName} before running this job.`
    });
    processQueues();
    return;
  }

  updateJob(job.id, {
    outputPath: options.outputPath,
    format: options.format || job.format
  });

  spawnTrackedProcess(job.id, executablePath, options.args, (result) => {
    if (result.ok) {
      const completedJob = jobs.find((candidate) => candidate.id === job.id);
      if (completedJob) {
        historyStore.recordJob(completedJob);
        onSuccessfulJob(completedJob);
      }
    }
    processQueues();
  });
}

function spawnTrackedProcess(jobId, executablePath, args, onClose = () => {}) {
  const job = jobs.find((candidate) => candidate.id === jobId);
  if (!job) {
    return;
  }

  if (shouldUseSmokeFakeTool(executablePath)) {
    runSmokeFakeProcess(job, executablePath, args, (code) => {
      onClose({ ok: code === 0, code });
    });
    return;
  }

  updateJob(jobId, {
    status: "running",
    message: `Running ${path.basename(executablePath)}...`
  });

  const child = spawn(executablePath, args, {
    env: makeProcessEnv(app.getPath("userData")),
    windowsHide: true
  });
  jobProcesses.set(jobId, child);

  child.stdout.on("data", (chunk) => {
    const text = chunk.toString();
    const lines = text.split(/\r?\n/).filter(Boolean);
    let latestProgress = null;

    for (const line of lines) {
      latestProgress = parseYtDlpProgress(line) || latestProgress;
      const extractedPath = extractOutputPath(line);
      const metadata = extractMetadata(line);
      updateJob(jobId, (currentJob) => ({
        ...(latestProgress ? {
          status: "running",
          progress: latestProgress.progress,
          speed: latestProgress.speed,
          eta: latestProgress.eta
        } : null),
        ...(extractedPath ? { outputPath: extractedPath } : null),
        ...(metadata ? metadata : null),
        message: lines[lines.length - 1] || currentJob.message || "Working..."
      }));
    }
  });

  child.stderr.on("data", (chunk) => {
    const message = chunk.toString().trim();
    if (message) {
      updateJob(jobId, { message });
    }
  });

  child.on("error", (error) => {
    jobProcesses.delete(jobId);
    updateJob(jobId, {
      status: "failed",
      message: error.message
    });
    onClose({ ok: false, error });
  });

  child.on("close", (code) => {
    jobProcesses.delete(jobId);
    updateJob(jobId, (currentJob) => ({
      status: code === 0 ? "completed" : "failed",
      progress: code === 0 ? 1 : currentJob.progress,
      speed: "",
      eta: "",
      message: code === 0 ? "Done." : `Process exited with code ${code}.`
    }));
    onClose({ ok: code === 0, code });
  });
}

function extractOutputPath(line) {
  const text = String(line || "");
  const destinationMatch = text.match(/Destination:\s+(.+)$/);
  if (destinationMatch) {
    return destinationMatch[1].trim().replace(/^"|"$/g, "");
  }
  const mergeMatch = text.match(/Merging formats into\s+"(.+)"$/);
  if (mergeMatch) {
    return mergeMatch[1].trim();
  }
  return "";
}

function extractMetadata(line) {
  const text = String(line || "");
  const channelMatch = text.match(/\[download]\s+Downloading item \d+ of \d+\s+from\s+(.+)$/);
  if (channelMatch) {
    return {
      channelName: channelMatch[1].trim()
    };
  }
  return null;
}

function onSuccessfulJob(job) {
  if (job.kind !== "download") {
    maybeNotify(`${job.kind[0].toUpperCase()}${job.kind.slice(1)} finished.`, job.title || path.basename(job.outputPath || ""));
    return;
  }

  maybeNotify("Download finished.", job.title || job.url || "Star Video Downloader");
  runPostDownloadAction(job);
}

function maybeNotify(message, title) {
  const settings = settingsStore.getState();
  if (!settings.notificationsEnabled) {
    return;
  }

  try {
    const notification = new Notification({
      title: title || "Star Video Downloader",
      body: message
    });
    notification.show();
  } catch {
    sendToast(message);
  }
}

function runPostDownloadAction(job) {
  const settings = settingsStore.getState();
  if (settings.postDownloadAction === "runScript") {
    runPostDownloadScript(job, settings.postDownloadScript);
    return;
  }
  if (settings.postDownloadAction === "openFile" && job.outputPath) {
    shell.openPath(job.outputPath).catch(() => {});
    return;
  }
  if (settings.postDownloadAction === "openFolder") {
    if (job.outputPath) {
      shell.showItemInFolder(job.outputPath);
      return;
    }
    if (job.outputDirectory) {
      shell.openPath(job.outputDirectory).catch(() => {});
    }
  }
}

function runPostDownloadScript(job, scriptPath) {
  const target = String(scriptPath || "").trim();
  if (!target) {
    sendToast("Post-download script is enabled, but no script file is selected.");
    return;
  }
  if (!fs.existsSync(target)) {
    sendToast("The selected post-download script could not be found.");
    return;
  }

  try {
    const child = spawn(target, [job.outputPath || "", job.url || ""], {
      detached: true,
      env: {
        ...makeProcessEnv(app.getPath("userData")),
        STAR_VIDEO_JOB_ID: job.id,
        STAR_VIDEO_JOB_KIND: job.kind,
        STAR_VIDEO_TITLE: job.title || "",
        STAR_VIDEO_URL: job.url || "",
        STAR_VIDEO_OUTPUT_PATH: job.outputPath || "",
        STAR_VIDEO_OUTPUT_DIRECTORY: job.outputDirectory || ""
      },
      shell: true,
      stdio: "ignore",
      windowsHide: true
    });
    child.unref();
    sendToast("Post-download script started.");
  } catch (error) {
    sendToast(error.message || "Post-download script could not be started.");
  }
}

function processQueues() {
  const now = new Date();
  updateScheduledStatuses(now);
  let activeDownloads = jobs.filter((job) => job.kind === "download" && jobProcesses.has(job.id)).length;
  const maxDownloads = maxConcurrentDownloads();

  for (const job of [...jobs].reverse()) {
    if (jobProcesses.has(job.id)) {
      continue;
    }
    if (job.status !== "queued") {
      continue;
    }
    if (!canStartNow(job, now)) {
      continue;
    }

    if (job.kind === "download") {
      if (activeDownloads >= maxDownloads) {
        continue;
      }
      activeDownloads += 1;
    }

    try {
      startJob(job);
    } catch (error) {
      updateJob(job.id, {
        status: "failed",
        message: error.message || "Job failed before it could start."
      });
    }
  }
}

function updateScheduledStatuses(now = new Date()) {
  let changed = false;
  jobs = jobs.map((job) => {
    if (TERMINAL_STATUSES.has(job.status) || jobProcesses.has(job.id)) {
      return job;
    }

    const waiting = !canStartNow(job, now);
    const nextStatus = waiting ? "scheduled" : "queued";
    if (job.status === nextStatus && (!waiting || job.message === scheduledMessage(job.scheduledStartAt))) {
      return job;
    }

    changed = true;
    return {
      ...job,
      status: nextStatus,
      message: waiting ? scheduledMessage(job.scheduledStartAt) : "",
      updatedAt: new Date().toISOString()
    };
  });

  if (changed) {
    persistJobsSoon();
    broadcastState();
  }
}

function canStartNow(job, now = new Date()) {
  if (shouldJobWaitForSchedule(job.scheduledStartAt, now)) {
    return false;
  }
  if (shouldWaitForGlobalSchedule(now)) {
    return false;
  }
  return true;
}

function shouldJobWaitForSchedule(scheduledStartAt, now = new Date()) {
  if (!scheduledStartAt) {
    return false;
  }
  const scheduled = Date.parse(scheduledStartAt);
  return Number.isFinite(scheduled) && scheduled > now.getTime();
}

function shouldWaitForGlobalSchedule(now = new Date()) {
  const settings = settingsStore.getState();
  if (!settings.scheduledDownloadEnabled) {
    return false;
  }
  const [hour, minute] = settings.scheduledDownloadTime.split(":").map((part) => Number(part));
  const scheduledToday = new Date(now);
  scheduledToday.setHours(hour, minute, 0, 0);
  return now.getTime() < scheduledToday.getTime();
}

function scheduledMessage(scheduledStartAt) {
  if (scheduledStartAt) {
    return `Scheduled for ${new Date(scheduledStartAt).toLocaleString()}`;
  }
  const settings = settingsStore.getState();
  return `Waiting for the daily schedule at ${settings.scheduledDownloadTime}`;
}

function maxConcurrentDownloads() {
  const settings = settingsStore.getState();
  const tierCap = licenseStore.isPro ? PRO_MAX_CONCURRENT_DOWNLOADS : FREE_MAX_CONCURRENT_DOWNLOADS;
  return Math.max(1, Math.min(settings.maxConcurrentDownloads, tierCap));
}

function isProbablyUrl(value) {
  try {
    const parsed = new URL(String(value || "").trim());
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

function normalizeUrl(value) {
  try {
    const parsed = new URL(String(value || "").trim());
    parsed.hash = "";
    for (const volatileKey of ["t", "si", "pp"]) {
      parsed.searchParams.delete(volatileKey);
    }
    return parsed.toString();
  } catch {
    return String(value || "").trim();
  }
}

function findDuplicate(duplicateKey) {
  if (!duplicateKey) {
    return false;
  }
  if (jobs.some((job) => job.duplicateKey === duplicateKey && job.status !== "cancelled")) {
    return true;
  }
  return historyStore.getEntries().some((entry) => normalizeUrl(entry.url) === duplicateKey);
}

function buildDownloadPayload(payload = {}) {
  const settings = settingsStore.getState();
  return {
    source: payload.source || "app",
    url: String(payload.url || "").trim(),
    quality: payload.quality || settings.defaultQuality,
    format: payload.format || settings.defaultFormat,
    subtitles: Boolean(payload.subtitles ?? settings.downloadSubtitlesByDefault),
    playlist: Boolean(payload.playlist),
    sponsorBlock: Boolean(payload.sponsorBlock),
    outputDirectory: payload.outputDirectory || settings.defaultOutputDirectory || app.getPath("downloads"),
    duplicateKey: normalizeUrl(payload.url),
    scheduledStartAt: payload.scheduledStartAt || ""
  };
}

async function inspectUrl(payload) {
  const userDataPath = app.getPath("userData");
  const ytdlpPath = getExecutablePath(userDataPath, "yt-dlp.exe");
  if (!ytdlpPath) {
    const error = new Error("Install yt-dlp before inspecting a URL.");
    error.code = "MISSING_YTDLP";
    throw error;
  }

  if (shouldUseSmokeFakeTool(ytdlpPath)) {
    return {
      title: "Smoke test media",
      channelName: "Smoke channel",
      duration: "03:33",
      isPlaylist: Boolean(payload.playlist),
      playlistCount: payload.playlist ? 12 : 0
    };
  }

  const isPlaylist = Boolean(payload.playlist) || String(payload.url || "").includes("list=");
  const args = isPlaylist
    ? ["--flat-playlist", "--dump-single-json", "--no-warnings", payload.url]
    : ["--dump-single-json", "--skip-download", "--no-playlist", "--no-warnings", payload.url];
  const stdout = await runProcessCapture(ytdlpPath, args, makeProcessEnv(userDataPath));
  const json = JSON.parse(stdout || "{}");
  return {
    title: String(json.title || payload.url || "").trim(),
    channelName: String(json.uploader || json.channel || "").trim(),
    duration: formatDuration(Number(json.duration || 0)),
    isPlaylist,
    playlistCount: Array.isArray(json.entries) ? json.entries.length : 0,
    playlistTitle: String(json.title || "").trim()
  };
}

function runProcessCapture(executablePath, args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(executablePath, args, {
      env,
      windowsHide: true
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) {
        resolve(stdout);
      } else {
        reject(new Error(stderr.trim() || `Process exited with code ${code}.`));
      }
    });
  });
}

function formatDuration(totalSeconds) {
  if (!Number.isFinite(totalSeconds) || totalSeconds <= 0) {
    return "";
  }
  const seconds = Math.floor(totalSeconds);
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  if (hours > 0) {
    return [hours, minutes, remainder].map((value) => String(value).padStart(2, "0")).join(":");
  }
  return [minutes, remainder].map((value) => String(value).padStart(2, "0")).join(":");
}

function restartClipboardMonitor() {
  clearInterval(clipboardTimer);
  clipboardTimer = null;

  const settings = settingsStore.getState();
  if (!settings.clipboardMonitoring) {
    return;
  }

  lastClipboardText = clipboard.readText().trim();
  clipboardTimer = setInterval(() => {
    const nextText = clipboard.readText().trim();
    if (!nextText || nextText === lastClipboardText || !isProbablyUrl(nextText)) {
      lastClipboardText = nextText;
      return;
    }
    lastClipboardText = nextText;

    if (settingsStore.getState().clipboardAction === "addToQueue") {
      try {
        const userDataPath = app.getPath("userData");
        const ytdlpPath = getExecutablePath(userDataPath, "yt-dlp.exe");
        if (!ytdlpPath) {
          sendToast("Clipboard URL detected. Install yt-dlp to add it to the queue.");
          return;
        }
        const job = createJob("download", {
          ...buildDownloadPayload({
            url: nextText,
            source: "clipboard"
          }),
          message: "Added from clipboard."
        });
        sendToast("Clipboard URL added to the queue.");
        processQueues();
        return job;
      } catch (error) {
        sendToast(error.message);
      }
      return;
    }

    sendToast("Copied video URL detected in the clipboard.");
  }, CLIPBOARD_POLL_MS);
}

function restartScheduler() {
  clearInterval(schedulerTimer);
  schedulerTimer = setInterval(() => {
    processQueues();
  }, SCHEDULE_POLL_MS);
}

function applySettingsUpdate(patch) {
  const nextSettings = settingsStore.update(patch);
  broadcastState();
  restartClipboardMonitor();
  applyLaunchAtLoginSetting(nextSettings);
  processQueues();
  return nextSettings;
}

function applyLaunchAtLoginSetting(settings = settingsStore?.getState()) {
  if (process.platform !== "win32" || !settings) {
    return;
  }

  try {
    app.setLoginItemSettings({
      openAtLogin: Boolean(settings.launchAtLogin),
      path: process.execPath
    });
  } catch {
    // Some portable or unsigned Windows builds may not allow login item writes.
  }
}

app.whenReady().then(() => {
  initStores();
  applyLaunchAtLoginSetting();
  registerIpc();
  createWindow();
  restartClipboardMonitor();
  restartScheduler();
  processQueues();

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

app.on("before-quit", () => {
  clearInterval(clipboardTimer);
  clearInterval(schedulerTimer);
  saveJobs();
});

function registerIpc() {
  ipcMain.handle("app:getState", () => getState());

  ipcMain.handle("shell:openBuy", async () => {
    await shell.openExternal(BUY_PRO_URL);
    return true;
  });

  ipcMain.handle("shell:revealPath", async (_event, filePath) => {
    const target = String(filePath || "").trim();
    if (!target) {
      return false;
    }
    if (fs.existsSync(target)) {
      shell.showItemInFolder(target);
      return true;
    }
    return false;
  });

  ipcMain.handle("shell:openExternal", async (_event, url) => {
    const target = String(url || "").trim();
    if (!target) {
      return false;
    }
    await shell.openExternal(target);
    return true;
  });

  ipcMain.handle("license:activate", async (_event, key) => {
    const result = await licenseStore.activateLicense(key);
    broadcastState();
    processQueues();
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

  ipcMain.handle("settings:update", (_event, patch) => ({
    ok: true,
    settings: applySettingsUpdate(patch)
  }));

  ipcMain.handle("history:clear", () => {
    historyStore.clear();
    broadcastState();
    return { ok: true };
  });

  ipcMain.handle("history:export", async (_event, format) => {
    const extension = format === "csv" ? "csv" : "json";
    const result = await dialog.showSaveDialog(mainWindow, {
      title: `Export history as ${extension.toUpperCase()}`,
      defaultPath: `star-video-downloader-history.${extension}`
    });
    if (result.canceled || !result.filePath) {
      return { ok: false, cancelled: true };
    }

    const body = format === "csv" ? historyStore.exportCsv() : historyStore.exportJson();
    fs.writeFileSync(result.filePath, body, "utf8");
    return { ok: true, filePath: result.filePath };
  });

  ipcMain.handle("queue:export", async () => {
    const result = await dialog.showSaveDialog(mainWindow, {
      title: "Export queue",
      defaultPath: "star-video-downloader-queue.json",
      filters: [
        { name: "JSON files", extensions: ["json"] },
        { name: "All files", extensions: ["*"] }
      ]
    });
    if (result.canceled || !result.filePath) {
      return { ok: false, cancelled: true };
    }

    fs.writeFileSync(result.filePath, exportQueueJson(), "utf8");
    return { ok: true, filePath: result.filePath };
  });

  ipcMain.handle("queue:import", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Import queue",
      properties: ["openFile"],
      filters: [
        { name: "JSON files", extensions: ["json"] },
        { name: "All files", extensions: ["*"] }
      ]
    });
    if (result.canceled || !result.filePaths[0]) {
      return { ok: false, cancelled: true };
    }

    const count = importQueueJson(fs.readFileSync(result.filePaths[0], "utf8"));
    return { ok: true, count };
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

  ipcMain.handle("dialog:chooseCookiesFile", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Choose cookies.txt file",
      properties: ["openFile"],
      filters: [
        { name: "Text files", extensions: ["txt", "cookies"] },
        { name: "All files", extensions: ["*"] }
      ]
    });
    return result.canceled ? "" : result.filePaths[0];
  });

  ipcMain.handle("dialog:chooseScriptFile", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "Choose post-download script",
      properties: ["openFile"],
      filters: [
        { name: "Scripts and apps", extensions: ["bat", "cmd", "ps1", "exe", "js", "py", "sh"] },
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
    processQueues();
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
    processQueues();
    return { ok: true, status };
  });

  ipcMain.handle("downloads:inspect", async (_event, payload) => {
    const result = await inspectUrl(payload || {});
    return { ok: true, inspection: result };
  });

  ipcMain.handle("downloads:start", async (_event, payload = {}) => {
    const userDataPath = app.getPath("userData");
    const ytdlpPath = getExecutablePath(userDataPath, "yt-dlp.exe");
    if (!ytdlpPath) {
      const error = new Error("Install yt-dlp before starting a download.");
      error.code = "MISSING_YTDLP";
      throw error;
    }

    const nextPayload = buildDownloadPayload(payload);
    const settings = settingsStore.getState();
    if (!licenseStore.isPro && nextPayload.playlist) {
      const error = new Error("Playlist downloads require Pro. Buy once for $5, then paste your Gumroad license key.");
      error.code = "PRO_REQUIRED";
      throw error;
    }
    if (!licenseStore.isPro && (nextPayload.sponsorBlock || settings.sponsorBlockEnabled)) {
      const error = new Error("SponsorBlock removal requires Pro. Buy once for $5, then paste your Gumroad license key.");
      error.code = "PRO_REQUIRED";
      throw error;
    }

    const duplicateExists = findDuplicate(nextPayload.duplicateKey);
    if (duplicateExists && !payload.allowDuplicateOverride) {
      if (settings.duplicateHandling === "skip") {
        return { ok: false, code: "DUPLICATE_SKIPPED", message: "This URL is already in your queue or history." };
      }
      if (settings.duplicateHandling === "ask") {
        const error = new Error("This URL is already in your queue or history.");
        error.code = "DUPLICATE_CONFIRM_REQUIRED";
        throw error;
      }
    }

    const job = createJob("download", nextPayload);
    processQueues();
    return job;
  });

  ipcMain.handle("queue:retryFailed", () => {
    jobs = jobs.map((job) => {
      if (job.status !== "failed") {
        return job;
      }
      return {
        ...job,
        status: canStartNow(job) ? "queued" : "scheduled",
        progress: 0,
        speed: "",
        eta: "",
        message: canStartNow(job) ? "" : scheduledMessage(job.scheduledStartAt),
        updatedAt: new Date().toISOString()
      };
    });
    persistJobsSoon();
    broadcastState();
    processQueues();
    return { ok: true };
  });

  ipcMain.handle("queue:removeFailed", () => {
    removeJobs((job) => job.status === "failed");
    return { ok: true };
  });

  ipcMain.handle("queue:clearFinished", () => {
    removeJobs((job) => job.status === "completed" || job.status === "cancelled");
    return { ok: true };
  });

  ipcMain.handle("queue:clearAll", () => {
    for (const child of jobProcesses.values()) {
      child.kill("SIGTERM");
    }
    jobProcesses = new Map();
    jobs = [];
    persistJobsSoon();
    broadcastState();
    return { ok: true };
  });

  ipcMain.handle("media:convert", async (_event, payload) => {
    requirePro("Video conversion");
    const ffmpegPath = getExecutablePath(app.getPath("userData"), "ffmpeg.exe");
    if (!ffmpegPath) {
      const error = new Error("Install ffmpeg before converting files.");
      error.code = "MISSING_FFMPEG";
      throw error;
    }

    const options = buildFfmpegConvertArgs({
      ...payload,
      settings: settingsStore.getState()
    });
    const job = createJob("convert", {
      inputPath: payload.inputPath,
      outputPath: options.outputPath,
      format: options.format
    });
    processQueues();
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

    const options = buildFfmpegRepairArgs({
      ...payload,
      settings: settingsStore.getState()
    });
    const job = createJob("repair", {
      inputPath: payload.inputPath,
      outputPath: options.outputPath,
      mode: options.mode,
      format: "MP4"
    });
    processQueues();
    return job;
  });
}
