"use strict";

function normalizeHttpUrl(value) {
  const target = String(value || "").trim();
  if (!target) {
    return "";
  }

  try {
    const parsed = new URL(target);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return "";
    }
    return parsed.toString();
  } catch {
    return "";
  }
}

function isSafeExternalUrl(value) {
  return Boolean(normalizeHttpUrl(value));
}

module.exports = {
  isSafeExternalUrl,
  normalizeHttpUrl
};
