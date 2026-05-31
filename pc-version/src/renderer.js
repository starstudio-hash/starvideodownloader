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
  select.innerHTML = values.map((value) => `<option>${value}</option>`).join("");
}

function toast(message) {
  const el = $("toast");
  el.textContent = message;
  el.classList.add("visible");
  window.clearTimeout(toast.timer);
  toast.timer = window.setTimeout(() => el.classList.remove("visible"), 4200);
}

function requireBridge() {
  if (!api) {
    toast("Run this inside the Star Video Downloader desktop app to use that action.");
    return false;
  }
  return true;
}

function render(appState) {
  state.last = appState;
  state.outputDirectory = state.outputDirectory || appState.defaultOutputDirectory || "Downloads";

  const license = appState.license || {};
  $("licenseSummary").innerHTML = `
    <div class="muted-label">License</div>
    <strong>${license.isPro ? "Pro active" : "Free tier"}</strong>
    <p>${license.isPro ? "Unlimited downloads unlocked." : `${license.dailyDownloadsRemaining} of ${license.freeDailyDownloadLimit} free downloads left today.`}</p>
    ${license.maskedLicenseKey ? `<p>${license.maskedLicenseKey}</p>` : ""}
  `;

  const tools = appState.tools || {};
  $("ytdlpStatus").textContent = tools.ytdlpInstalled
    ? `Installed${tools.ytdlpVersion ? ` - ${tools.ytdlpVersion}` : ""}`
    : "Not installed. Downloads need yt-dlp.exe.";
  $("ffmpegStatus").textContent = tools.ffmpegInstalled
    ? `Installed${tools.ffmpegVersion ? ` - ${tools.ffmpegVersion}` : ""}`
    : "Not installed. 8K merging, conversion, and repair need ffmpeg.exe.";
  $("toolMessage").textContent = tools.installMessage || "";
  $("outputDirectory").textContent = state.outputDirectory;

  renderQueue(appState.downloads || []);
}

function renderQueue(jobs) {
  const queue = $("queueList");
  if (!jobs.length) {
    queue.innerHTML = '<div class="empty-state">No jobs yet.</div>';
    return;
  }

  queue.innerHTML = jobs.map((job) => {
    const title = job.url || job.inputPath || job.outputPath || "Media job";
    const pct = Math.round((job.progress || 0) * 100);
    return `
      <article class="queue-item">
        <div class="queue-row">
          <div class="queue-title">${escapeHtml(title)}</div>
          <div class="status">${escapeHtml(job.status || "queued")}</div>
        </div>
        <div class="progress"><span style="width:${pct}%"></span></div>
        <div class="queue-row">
          <span>${job.kind || "job"}${job.quality ? ` - ${job.quality}` : ""}${job.format ? ` - ${job.format}` : ""}</span>
          <span>${pct}% ${job.speed || ""} ${job.eta ? `ETA ${job.eta}` : ""}</span>
        </div>
        ${job.message ? `<p>${escapeHtml(job.message)}</p>` : ""}
      </article>
    `;
  }).join("");
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function call(label, fn) {
  try {
    const result = await fn();
    if (result && result.ok === false) {
      toast(result.message || `${label} failed.`);
    } else {
      toast(`${label} started.`);
    }
    await refresh();
    return result;
  } catch (error) {
    toast(error.message || `${label} failed.`);
    return null;
  }
}

async function refresh() {
  if (!api) {
    render({
      license: {
        isPro: false,
        dailyDownloadsRemaining: 5,
        freeDailyDownloadLimit: 5
      },
      tools: {
        ytdlpInstalled: false,
        ffmpegInstalled: false
      },
      downloads: [],
      defaultOutputDirectory: "Downloads"
    });
    return;
  }
  render(await api.getState());
}

function bindEvents() {
  $("buyProTop").addEventListener("click", () => api ? api.openBuy() : toast("Open Gumroad from the website."));
  $("buyProLicense").addEventListener("click", () => api ? api.openBuy() : toast("Open Gumroad from the website."));

  $("chooseOutput").addEventListener("click", async () => {
    if (!requireBridge()) {
      return;
    }
    const chosen = await api.chooseOutputDirectory();
    if (chosen) {
      state.outputDirectory = chosen;
      $("outputDirectory").textContent = chosen;
    }
  });

  $("installYtDlp").addEventListener("click", () => requireBridge() && call("yt-dlp install", () => api.installYtDlp()));
  $("installFfmpeg").addEventListener("click", () => requireBridge() && call("ffmpeg install", () => api.installFfmpeg()));

  $("startDownload").addEventListener("click", () => requireBridge() && call("Download", () => api.startDownload({
    url: $("urlInput").value,
    quality: $("qualitySelect").value,
    format: $("formatSelect").value,
    subtitles: $("subtitlesCheck").checked,
    playlist: $("playlistCheck").checked,
    sponsorBlock: $("sponsorBlockCheck").checked,
    outputDirectory: state.outputDirectory
  })));

  $("activateLicense").addEventListener("click", () => requireBridge() && call("License activation", () => api.activateLicense($("licenseKeyInput").value)));
  $("validateLicense").addEventListener("click", () => requireBridge() && call("License validation", () => api.validateLicense()));
  $("deactivateLicense").addEventListener("click", () => requireBridge() && call("License deactivation", () => api.deactivateLicense()));

  $("chooseConvertFile").addEventListener("click", async () => {
    if (!requireBridge()) {
      return;
    }
    const chosen = await api.chooseVideoFile();
    if (chosen) {
      state.convertFilePath = chosen;
      $("convertFilePath").textContent = chosen;
    }
  });
  $("chooseRepairFile").addEventListener("click", async () => {
    if (!requireBridge()) {
      return;
    }
    const chosen = await api.chooseVideoFile();
    if (chosen) {
      state.repairFilePath = chosen;
      $("repairFilePath").textContent = chosen;
    }
  });
  $("convertFile").addEventListener("click", () => requireBridge() && call("Conversion", () => api.convertFile({
    inputPath: state.convertFilePath,
    format: $("convertFormat").value
  })));
  $("repairFile").addEventListener("click", () => requireBridge() && call("Repair", () => api.repairFile({
    inputPath: state.repairFilePath,
    mode: $("repairMode").value
  })));

  if (api) {
    api.onStateUpdate(render);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  setOptions($("qualitySelect"), QUALITY_OPTIONS);
  setOptions($("formatSelect"), FORMAT_OPTIONS);
  $("qualitySelect").value = "1080p";
  $("formatSelect").value = "MP4";
  bindEvents();
  refresh();
});
