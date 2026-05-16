"use strict";

const QUALITY_OPTIONS = [
  "2160p (4K)",
  "1440p (2K)",
  "1080p",
  "720p",
  "480p",
  "360p",
  "Audio only",
  "Best available"
];

const FORMAT_OPTIONS = ["MP4", "MKV", "MP3", "M4A", "WebM"];
const api = window.starDownloader;
const state = {
  outputDirectory: "",
  convertFilePath: "",
  repairFilePath: "",
  last: null
};

function $(id) {
  return document.getElementById(id);
}

function setOptions(select, values) {
  select.innerHTML = values.map((value) => `<option>${escapeHtml(value)}</option>`).join("");
}

function toast(message) {
  const el = $("toast");
  if (!el) return;
  el.textContent = message;
  el.classList.add("visible");
  window.clearTimeout(toast.timer);
  toast.timer = window.setTimeout(() => el.classList.remove("visible"), 4200);
}

function requireBridge() {
  if (!api) {
    toast("Open the desktop app to use that action.");
    return false;
  }
  return true;
}

function render(appState) {
  state.last = appState;
  const settings = appState.settings || {};
  state.outputDirectory = state.outputDirectory || settings.defaultOutputDirectory || appState.defaultOutputDirectory || "Downloads";

  renderLicense(appState.license || {});
  renderStatusPills(appState);
  renderTools(appState.tools || {});
  renderQueue(appState.downloads || []);
  renderHistory(appState.history || []);
  renderStats(appState.history || [], appState.downloads || []);
  renderSettings(settings, appState.defaultOutputDirectory || "Downloads");

  $("outputDirectory").textContent = state.outputDirectory;
  $("subtitlesCheck").checked = Boolean(settings.downloadSubtitlesByDefault);
  $("sponsorBlockCheck").checked = Boolean(settings.sponsorBlockEnabled);
  $("qualitySelect").value = settings.defaultQuality || "1080p";
  $("formatSelect").value = settings.defaultFormat || "MP4";
}

function renderLicense(license) {
  $("licenseSummary").innerHTML = `
    <div class="muted-label">License</div>
    <strong>${license.isPro ? "Pro active" : "Free tier"}</strong>
    <p>${license.isPro ? "Unlimited downloads unlocked." : `${license.dailyDownloadsRemaining ?? 5} of ${license.freeDailyDownloadLimit ?? 5} free downloads left today.`}</p>
    ${license.maskedLicenseKey ? `<p>${escapeHtml(license.maskedLicenseKey)}</p>` : ""}
  `;
}

function renderStatusPills(appState) {
  const license = appState.license || {};
  const tools = appState.tools || {};
  const settings = appState.settings || {};
  const activeJobs = (appState.downloads || []).filter((job) => job.status === "running").length;

  $("statusPills").innerHTML = [
    pill(license.isPro ? "Pro" : "Free", license.isPro ? "success" : "warn"),
    pill(tools.ytdlpInstalled ? "yt-dlp ready" : "yt-dlp missing", tools.ytdlpInstalled ? "success" : "warn"),
    pill(tools.ffmpegInstalled ? "ffmpeg ready" : "ffmpeg missing", tools.ffmpegInstalled ? "success" : "warn"),
    pill(`${activeJobs} active`, activeJobs ? "success" : ""),
    settings.clipboardMonitoring ? pill("Clipboard on", "success") : ""
  ].join("");
}

function pill(label, tone = "") {
  return `<span class="status-pill ${tone}">${escapeHtml(label)}</span>`;
}

function renderTools(tools) {
  $("ytdlpStatus").textContent = tools.ytdlpInstalled
    ? `Installed${tools.ytdlpVersion ? ` - ${tools.ytdlpVersion}` : ""}`
    : "Not installed. Downloads need yt-dlp.exe.";
  $("ffmpegStatus").textContent = tools.ffmpegInstalled
    ? `Installed${tools.ffmpegVersion ? ` - ${tools.ffmpegVersion}` : ""}`
    : "Not installed. 8K merging, conversion, and repair need ffmpeg.exe.";
  $("toolMessage").textContent = tools.installMessage || "";
}

function renderQueue(jobs) {
  const queue = $("queueList");
  const counts = countBy(jobs, "status");
  $("queueSummary").textContent = `${jobs.length} jobs - ${counts.running || 0} running, ${counts.queued || 0} queued, ${counts.scheduled || 0} scheduled, ${counts.completed || 0} done, ${counts.failed || 0} failed.`;

  if (!jobs.length) {
    queue.innerHTML = '<div class="empty-state">No jobs yet.</div>';
    return;
  }

  queue.innerHTML = jobs.map((job) => {
    const title = job.title || job.url || job.inputPath || job.outputPath || "Media job";
    const pct = Math.round((job.progress || 0) * 100);
    const outputAction = job.outputPath
      ? `<button class="button ghost" data-reveal="${escapeAttr(job.outputPath)}">Show File</button>`
      : "";

    return `
      <article class="queue-item">
        <div class="queue-row">
          <div>
            <div class="queue-title">${escapeHtml(title)}</div>
            <div class="muted-label">${escapeHtml(job.kind || "job")} ${job.quality ? `- ${escapeHtml(job.quality)}` : ""} ${job.format ? `- ${escapeHtml(job.format)}` : ""}</div>
          </div>
          <div class="status">${escapeHtml(job.status || "queued")}</div>
        </div>
        <div class="progress"><span style="width:${pct}%"></span></div>
        <div class="queue-row">
          <span>${pct}% ${escapeHtml(job.speed || "")} ${job.eta ? `ETA ${escapeHtml(job.eta)}` : ""}</span>
          <span>${job.scheduledStartAt ? `Scheduled ${formatDate(job.scheduledStartAt)}` : ""}</span>
        </div>
        ${job.message ? `<p>${escapeHtml(job.message)}</p>` : ""}
        ${job.outputPath ? `<code>${escapeHtml(job.outputPath)}</code>` : ""}
        ${outputAction}
      </article>
    `;
  }).join("");
}

function renderHistory(entries) {
  const history = $("historyList");
  $("historySummary").textContent = `${entries.length} completed items saved.`;

  if (!entries.length) {
    history.innerHTML = '<div class="empty-state">No history yet.</div>';
    return;
  }

  history.innerHTML = entries.slice(0, 60).map((entry) => `
    <article class="history-item">
      <div class="history-row">
        <div>
          <div class="history-title">${escapeHtml(entry.title || entry.url || entry.outputPath || "Media job")}</div>
          <div class="muted-label">${escapeHtml(entry.kind || "download")} - ${escapeHtml(entry.format || "file")} - ${formatDate(entry.date)}</div>
        </div>
        <div class="panel-actions">
          ${entry.url ? `<button class="button ghost" data-open-url="${escapeAttr(entry.url)}">Open URL</button>` : ""}
          ${entry.outputPath ? `<button class="button ghost" data-reveal="${escapeAttr(entry.outputPath)}">Show File</button>` : ""}
        </div>
      </div>
      ${entry.outputPath ? `<code>${escapeHtml(entry.outputPath)}</code>` : ""}
    </article>
  `).join("");
}

function renderStats(entries, jobs) {
  const totalSize = entries.reduce((sum, entry) => sum + (Number(entry.fileSize) || 0), 0);
  const completed = entries.length;
  const failed = jobs.filter((job) => job.status === "failed").length;
  const formats = countBy(entries, "format");
  const qualities = countBy(entries, "quality");
  const kinds = countBy(entries, "kind");

  $("statsGrid").innerHTML = [
    statCard("Completed", completed),
    statCard("Stored Size", formatBytes(totalSize)),
    statCard("Formats", Object.keys(formats).filter(Boolean).length),
    statCard("Failures", failed)
  ].join("");

  $("statsByFormat").innerHTML = renderMetricRows(formats);
  $("statsByQuality").innerHTML = renderMetricRows(qualities);
  $("statsByKind").innerHTML = renderMetricRows(kinds);
}

function statCard(label, value) {
  return `
    <div class="stat-card">
      <span class="muted-label">${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
    </div>
  `;
}

function renderMetricRows(counts) {
  const entries = Object.entries(counts).filter(([key]) => key).sort((a, b) => b[1] - a[1]);
  if (!entries.length) {
    return '<div class="empty-state">No data yet.</div>';
  }
  const max = entries[0][1] || 1;
  return entries.map(([label, count]) => `
    <div class="metric-row">
      <div class="metric-head"><span>${escapeHtml(label)}</span><span>${count}</span></div>
      <div class="metric-bar"><span style="width:${Math.max(4, Math.round((count / max) * 100))}%"></span></div>
    </div>
  `).join("");
}

function renderSettings(settings, defaultOutputDirectory) {
  const controls = document.querySelectorAll("[data-setting]");
  for (const control of controls) {
    const key = control.dataset.setting;
    const value = settings[key];
    if (control.type === "checkbox") {
      control.checked = Boolean(value);
    } else {
      control.value = value ?? "";
    }
  }
  $("defaultOutputDirectoryLabel").textContent = settings.defaultOutputDirectory || defaultOutputDirectory || "Downloads";
  $("cookiesFileLabel").textContent = settings.cookiesFilePath || "No cookies file selected";
  $("postDownloadScriptLabel").textContent = settings.postDownloadScript || "No script selected";
}

function countBy(items, key) {
  const counts = {};
  for (const item of items) {
    const value = item && item[key] ? String(item[key]) : "";
    if (value) {
      counts[value] = (counts[value] || 0) + 1;
    }
  }
  return counts;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/'/g, "&#39;");
}

function formatDate(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function formatBytes(value) {
  const bytes = Number(value) || 0;
  if (bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = bytes;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(size >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}

async function call(label, fn, options = {}) {
  try {
    const result = await fn();
    if (result && result.ok === false) {
      toast(result.message || `${label} failed.`);
    } else if (!options.quiet) {
      toast(options.success || `${label} started.`);
    }
    await refresh();
    return result;
  } catch (error) {
    if (error.code === "DUPLICATE_CONFIRM_REQUIRED" || String(error.message).includes("already in your queue")) {
      const proceed = window.confirm("This URL is already in your queue or history. Add it again?");
      if (proceed && options.retryDuplicate) {
        return options.retryDuplicate();
      }
    }
    toast(error.message || `${label} failed.`);
    return null;
  }
}

async function refresh() {
  if (!api) {
    render(demoState());
    return;
  }
  render(await api.getState());
}

function downloadPayload(extra = {}) {
  const scheduledValue = $("scheduleInput").value;
  return {
    url: $("urlInput").value,
    quality: $("qualitySelect").value,
    format: $("formatSelect").value,
    subtitles: $("subtitlesCheck").checked,
    playlist: $("playlistCheck").checked,
    sponsorBlock: $("sponsorBlockCheck").checked,
    outputDirectory: state.outputDirectory,
    scheduledStartAt: scheduledValue ? new Date(scheduledValue).toISOString() : "",
    ...extra
  };
}

function bindEvents() {
  document.querySelectorAll(".nav-link").forEach((link) => {
    link.addEventListener("click", () => {
      document.querySelectorAll(".nav-link").forEach((candidate) => candidate.classList.remove("active"));
      link.classList.add("active");
    });
  });

  $("buyProTop").addEventListener("click", () => api ? api.openBuy() : toast("Open Gumroad from the website."));
  $("buyProLicense").addEventListener("click", () => api ? api.openBuy() : toast("Open Gumroad from the website."));

  $("chooseOutput").addEventListener("click", async () => {
    if (!requireBridge()) return;
    const chosen = await api.chooseOutputDirectory();
    if (chosen) {
      state.outputDirectory = chosen;
      $("outputDirectory").textContent = chosen;
    }
  });

  $("inspectUrl").addEventListener("click", () => requireBridge() && call("Inspection", async () => {
    $("inspectionCard").classList.remove("hidden");
    $("inspectionTitle").textContent = "Inspecting...";
    $("inspectionBadge").textContent = "Working";
    const result = await api.inspectDownload(downloadPayload());
    const inspection = result.inspection || {};
    $("inspectionTitle").textContent = inspection.title || $("urlInput").value || "Detected media";
    $("inspectionChannel").textContent = inspection.channelName || "-";
    $("inspectionDuration").textContent = inspection.duration || "-";
    $("inspectionPlaylist").textContent = inspection.isPlaylist ? `${inspection.playlistCount || 0} items` : "No";
    $("inspectionBadge").textContent = "Ready";
    $("inspectionBadge").className = "status-chip success";
    return { ok: true };
  }, { success: "Inspection finished." }));

  $("installYtDlp").addEventListener("click", () => requireBridge() && call("yt-dlp install", () => api.installYtDlp(), { success: "yt-dlp updated." }));
  $("installFfmpeg").addEventListener("click", () => requireBridge() && call("ffmpeg install", () => api.installFfmpeg(), { success: "ffmpeg updated." }));

  $("startDownload").addEventListener("click", () => {
    if (!requireBridge()) return;
    call("Download", () => api.startDownload(downloadPayload()), {
      success: "Download queued.",
      retryDuplicate: () => api.startDownload(downloadPayload({ allowDuplicateOverride: true })).then(refresh)
    });
  });

  $("retryFailed").addEventListener("click", () => requireBridge() && call("Retry failed", () => api.retryFailed(), { success: "Failed jobs queued again." }));
  $("removeFailed").addEventListener("click", () => requireBridge() && call("Remove failed", () => api.removeFailed(), { success: "Failed jobs removed." }));
  $("clearFinished").addEventListener("click", () => requireBridge() && call("Clear finished", () => api.clearFinished(), { success: "Finished jobs cleared." }));
  $("clearQueue").addEventListener("click", () => requireBridge() && window.confirm("Clear all queue items?") && call("Clear queue", () => api.clearQueue(), { success: "Queue cleared." }));
  $("exportQueue").addEventListener("click", () => requireBridge() && call("Queue export", () => api.exportQueue(), { success: "Queue exported." }));
  $("importQueue").addEventListener("click", () => requireBridge() && call("Queue import", () => api.importQueue(), { success: "Queue imported." }));

  $("activateLicense").addEventListener("click", () => requireBridge() && call("License activation", () => api.activateLicense($("licenseKeyInput").value), { success: "License activated." }));
  $("validateLicense").addEventListener("click", () => requireBridge() && call("License validation", () => api.validateLicense(), { success: "License checked." }));
  $("deactivateLicense").addEventListener("click", () => requireBridge() && call("License deactivation", () => api.deactivateLicense(), { success: "License deactivated." }));

  $("chooseConvertFile").addEventListener("click", async () => {
    if (!requireBridge()) return;
    const chosen = await api.chooseVideoFile();
    if (chosen) {
      state.convertFilePath = chosen;
      $("convertFilePath").textContent = chosen;
    }
  });
  $("chooseRepairFile").addEventListener("click", async () => {
    if (!requireBridge()) return;
    const chosen = await api.chooseVideoFile();
    if (chosen) {
      state.repairFilePath = chosen;
      $("repairFilePath").textContent = chosen;
    }
  });
  $("convertFile").addEventListener("click", () => requireBridge() && call("Conversion", () => api.convertFile({
    inputPath: state.convertFilePath,
    format: $("convertFormat").value
  }), { success: "Conversion queued." }));
  $("repairFile").addEventListener("click", () => requireBridge() && call("Repair", () => api.repairFile({
    inputPath: state.repairFilePath,
    mode: $("repairMode").value
  }), { success: "Repair queued." }));

  $("chooseDefaultOutputDirectory").addEventListener("click", async () => {
    if (!requireBridge()) return;
    const chosen = await api.chooseOutputDirectory();
    if (chosen) {
      await api.updateSettings({ defaultOutputDirectory: chosen });
      await refresh();
    }
  });

  $("chooseCookiesFile").addEventListener("click", async () => {
    if (!requireBridge()) return;
    const chosen = await api.chooseCookiesFile();
    if (chosen) {
      await api.updateSettings({ cookiesFilePath: chosen });
      await refresh();
    }
  });

  $("choosePostDownloadScript").addEventListener("click", async () => {
    if (!requireBridge()) return;
    const chosen = await api.chooseScriptFile();
    if (chosen) {
      await api.updateSettings({ postDownloadScript: chosen, postDownloadAction: "runScript" });
      await refresh();
    }
  });

  document.querySelectorAll("[data-setting]").forEach((control) => {
    control.addEventListener("change", () => updateSettingFromControl(control));
  });

  $("exportHistoryJson").addEventListener("click", () => requireBridge() && call("History export", () => api.exportHistory("json"), { success: "History exported." }));
  $("exportHistoryCsv").addEventListener("click", () => requireBridge() && call("History export", () => api.exportHistory("csv"), { success: "History exported." }));
  $("clearHistory").addEventListener("click", () => requireBridge() && window.confirm("Clear all history?") && call("Clear history", () => api.clearHistory(), { success: "History cleared." }));

  document.addEventListener("click", (event) => {
    const revealButton = event.target.closest("[data-reveal]");
    if (revealButton && api) {
      api.revealPath(revealButton.dataset.reveal);
    }
    const urlButton = event.target.closest("[data-open-url]");
    if (urlButton && api) {
      api.openExternal(urlButton.dataset.openUrl);
    }
  });

  if (api) {
    api.onStateUpdate(render);
    api.onToast((payload) => toast(payload.message || ""));
  }
}

async function updateSettingFromControl(control) {
  if (!requireBridge()) {
    return;
  }
  const key = control.dataset.setting;
  const rawValue = control.type === "checkbox" ? control.checked : control.value;
  const value = control.type === "number" ? Number(rawValue) : rawValue;
  await api.updateSettings({ [key]: value });
  await refresh();
}

function demoState() {
  const now = new Date();
  const completedDate = new Date(now.getTime() - 1000 * 60 * 32).toISOString();
  return {
    license: {
      isPro: false,
      dailyDownloadsRemaining: 5,
      freeDailyDownloadLimit: 5
    },
    settings: {
      defaultQuality: "1080p",
      defaultFormat: "MP4",
      downloadSubtitlesByDefault: false,
      defaultOutputDirectory: "Downloads",
      maxConcurrentDownloads: 3,
      duplicateHandling: "ask",
      sponsorBlockEnabled: false,
      sponsorBlockMode: "all",
      cookiesFromBrowser: "none",
      cookiesFilePath: "",
      rateLimitEnabled: false,
      rateLimitSpeed: "2M",
      useDownloadArchive: false,
      concurrentFragments: 1,
      playlistItemsFilter: "",
      matchFilter: "",
      notificationsEnabled: true,
      clipboardMonitoring: false,
      clipboardAction: "notify",
      launchAtLogin: false,
      scheduledDownloadEnabled: false,
      scheduledDownloadTime: "02:00",
      filenameTemplate: "%(title).200B.%(ext)s",
      autoOrganize: false,
      organizeBy: "none",
      embedThumbnail: false,
      embedMetadata: false,
      embedChapters: false,
      splitChapters: false,
      embedSubtitles: false,
      liveFromStart: false,
      waitForVideo: false,
      geoBypass: false,
      geoBypassCountry: "",
      fileConflictBehavior: "rename",
      convertThumbnailsFormat: "",
      selectedVideoCodec: "h264",
      selectedAudioCodec: "aac",
      encodingQuality: "medium",
      macCompatibleEncoding: true,
      postDownloadAction: "none",
      postDownloadScript: "",
      sleepIntervalEnabled: false,
      sleepIntervalMin: 3,
      sleepIntervalMax: 10,
      formatSortString: ""
    },
    tools: {
      ytdlpInstalled: true,
      ytdlpVersion: "2026.05.12",
      ffmpegInstalled: true,
      ffmpegVersion: "ffmpeg 7.x",
      installMessage: ""
    },
    downloads: [
      {
        id: "demo-1",
        kind: "download",
        status: "running",
        progress: 0.62,
        speed: "4.2MiB/s",
        eta: "00:18",
        url: "https://www.youtube.com/watch?v=example",
        title: "Creator tutorial sample",
        quality: "1080p",
        format: "MP4",
        message: "Downloading video and audio streams..."
      },
      {
        id: "demo-2",
        kind: "repair",
        status: "scheduled",
        progress: 0,
        inputPath: "C:\\Videos\\broken-clip.mp4",
        mode: "rewrap",
        scheduledStartAt: new Date(now.getTime() + 1000 * 60 * 60).toISOString(),
        message: "Scheduled for later."
      }
    ],
    history: [
      {
        id: "history-1",
        kind: "download",
        title: "Finished demo download",
        url: "https://www.youtube.com/watch?v=finished",
        date: completedDate,
        quality: "1080p",
        format: "MP4",
        fileSize: 148000000,
        outputPath: "C:\\Users\\You\\Downloads\\Finished demo download.mp4"
      },
      {
        id: "history-2",
        kind: "convert",
        title: "clip-converted.mp4",
        date: completedDate,
        format: "MP4",
        fileSize: 42000000,
        outputPath: "C:\\Videos\\clip-converted.mp4"
      }
    ],
    defaultOutputDirectory: "Downloads",
    platform: navigator.platform
  };
}

document.addEventListener("DOMContentLoaded", () => {
  setOptions($("qualitySelect"), QUALITY_OPTIONS);
  setOptions($("formatSelect"), FORMAT_OPTIONS);
  setOptions($("settingDefaultQuality"), QUALITY_OPTIONS);
  setOptions($("settingDefaultFormat"), FORMAT_OPTIONS);
  $("qualitySelect").value = "1080p";
  $("formatSelect").value = "MP4";
  bindEvents();
  refresh();
});
