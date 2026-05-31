"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const {
  FREE_DAILY_DOWNLOAD_LIMIT,
  FREE_MAX_CONCURRENT_DOWNLOADS,
  GUMROAD_PRODUCT_ID,
  GUMROAD_VERIFY_URL,
  PRO_MAX_CONCURRENT_DOWNLOADS
} = require("./config");

function todayKey(now = new Date()) {
  return [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0")
  ].join("-");
}

function defaultState() {
  return {
    licenseKey: "",
    instanceID: "",
    activationDate: null,
    dailyDownloadCount: 0,
    lastDownloadDateKey: null
  };
}

function normalizeState(value) {
  return {
    ...defaultState(),
    ...(value && typeof value === "object" ? value : {})
  };
}

class LicenseStore {
  constructor(options = {}) {
    this.filePath = options.filePath || path.join(os.homedir(), ".star-video-downloader-pc-license.json");
    this.productId = options.productId || GUMROAD_PRODUCT_ID;
    this.verifyUrl = options.verifyUrl || GUMROAD_VERIFY_URL;
    this.httpPost = options.httpPost || defaultHttpPost;
    this.state = this.load();
  }

  load() {
    try {
      const raw = fs.readFileSync(this.filePath, "utf8");
      return normalizeState(JSON.parse(raw));
    } catch {
      return defaultState();
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    fs.writeFileSync(this.filePath, JSON.stringify(this.state, null, 2), "utf8");
  }

  get isPro() {
    return Boolean(this.state.licenseKey && this.state.instanceID);
  }

  resetDailyCountIfNeeded(now = new Date()) {
    const key = todayKey(now);
    if (this.state.lastDownloadDateKey && this.state.lastDownloadDateKey !== key) {
      this.state.dailyDownloadCount = 0;
      this.state.lastDownloadDateKey = null;
      this.save();
    }
  }

  canStartDownload(now = new Date()) {
    if (this.isPro) {
      return true;
    }
    this.resetDailyCountIfNeeded(now);
    return this.state.dailyDownloadCount < FREE_DAILY_DOWNLOAD_LIMIT;
  }

  recordDownload(now = new Date()) {
    this.resetDailyCountIfNeeded(now);
    this.state.dailyDownloadCount += 1;
    this.state.lastDownloadDateKey = todayKey(now);
    this.save();
  }

  getPublicState(now = new Date()) {
    this.resetDailyCountIfNeeded(now);
    const remaining = this.isPro
      ? Number.MAX_SAFE_INTEGER
      : Math.max(0, FREE_DAILY_DOWNLOAD_LIMIT - this.state.dailyDownloadCount);

    return {
      isPro: this.isPro,
      maskedLicenseKey: maskLicenseKey(this.state.licenseKey),
      activationDate: this.state.activationDate,
      dailyDownloadCount: this.state.dailyDownloadCount,
      dailyDownloadsRemaining: remaining,
      freeDailyDownloadLimit: FREE_DAILY_DOWNLOAD_LIMIT,
      maxConcurrentDownloads: this.isPro ? PRO_MAX_CONCURRENT_DOWNLOADS : FREE_MAX_CONCURRENT_DOWNLOADS
    };
  }

  async activateLicense(key) {
    const licenseKey = String(key || "").trim();
    if (!licenseKey) {
      return { ok: false, code: "invalid_key", message: "Enter a license key." };
    }

    const result = await this.verifyLicense(licenseKey, true);
    if (!result.ok) {
      return result;
    }

    this.state.licenseKey = licenseKey;
    this.state.instanceID = licenseKey;
    this.state.activationDate = new Date().toISOString();
    this.save();
    return { ok: true, state: this.getPublicState() };
  }

  async validateLicense() {
    if (!this.state.licenseKey) {
      return { ok: false, code: "missing_key", message: "No license key is active." };
    }

    const result = await this.verifyLicense(this.state.licenseKey, false);
    if (result.ok) {
      return { ok: true, state: this.getPublicState() };
    }

    if (result.code === "network_error") {
      return { ok: this.isPro, warning: result.message, state: this.getPublicState() };
    }

    this.clear();
    return result;
  }

  clear() {
    this.state = defaultState();
    this.save();
    return this.getPublicState();
  }

  async verifyLicense(licenseKey, incrementUsesCount) {
    const body = new URLSearchParams({
      product_id: this.productId,
      license_key: licenseKey,
      increment_uses_count: incrementUsesCount ? "true" : "false"
    });

    try {
      const response = await this.httpPost(this.verifyUrl, body.toString(), {
        "Content-Type": "application/x-www-form-urlencoded"
      });
      const data = response && response.data ? response.data : {};
      const success = Boolean(data.success);

      if (response.statusCode === 200 && success) {
        return { ok: true, data };
      }

      const message = String(data.message || "Invalid license key.");
      if (response.statusCode === 404 || message.toLowerCase().includes("not found")) {
        return {
          ok: false,
          code: "invalid_key",
          message: "This license key was not found for Star Video Downloader."
        };
      }
      if (message.toLowerCase().includes("limit") || message.toLowerCase().includes("uses")) {
        return {
          ok: false,
          code: "activation_limit_reached",
          message: "This license key has already been used on too many devices."
        };
      }

      return { ok: false, code: "invalid_key", message };
    } catch (error) {
      return {
        ok: false,
        code: "network_error",
        message: `Network error: ${error.message}`
      };
    }
  }
}

async function defaultHttpPost(url, body, headers) {
  if (typeof fetch !== "function") {
    throw new Error("fetch is not available in this runtime");
  }

  const response = await fetch(url, {
    method: "POST",
    headers,
    body
  });
  let data = {};
  try {
    data = await response.json();
  } catch {
    data = {};
  }
  return { statusCode: response.status, data };
}

function maskLicenseKey(key) {
  if (!key) {
    return "";
  }
  if (key.length <= 8) {
    return "****";
  }
  return `${key.slice(0, 4)}...${key.slice(-4)}`;
}

module.exports = {
  LicenseStore,
  defaultState,
  maskLicenseKey,
  normalizeState,
  todayKey
};
