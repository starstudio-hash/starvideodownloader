"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { GUMROAD_PRODUCT_ID } = require("../src/config");
const { LicenseStore, maskLicenseKey, todayKey } = require("../src/license-store");

function tempFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), "star-license-")), "license.json");
}

test("activates with the same Gumroad product id and increments uses", async () => {
  const requests = [];
  const store = new LicenseStore({
    filePath: tempFile(),
    httpPost: async (url, body, headers) => {
      requests.push({ url, body: new URLSearchParams(body), headers });
      return { statusCode: 200, data: { success: true } };
    }
  });

  const result = await store.activateLicense("STAR-1234-KEY");

  assert.equal(result.ok, true);
  assert.equal(store.isPro, true);
  assert.equal(requests[0].body.get("product_id"), GUMROAD_PRODUCT_ID);
  assert.equal(requests[0].body.get("license_key"), "STAR-1234-KEY");
  assert.equal(requests[0].body.get("increment_uses_count"), "true");
  assert.equal(requests[0].headers["Content-Type"], "application/x-www-form-urlencoded");
});

test("validates without incrementing Gumroad uses", async () => {
  const requests = [];
  const store = new LicenseStore({
    filePath: tempFile(),
    httpPost: async (_url, body) => {
      requests.push(new URLSearchParams(body));
      return { statusCode: 200, data: { success: true } };
    }
  });

  await store.activateLicense("STAR-1234-KEY");
  await store.validateLicense();

  assert.equal(requests[1].get("increment_uses_count"), "false");
});

test("network validation failures do not revoke an already active pro license", async () => {
  let shouldFail = false;
  const store = new LicenseStore({
    filePath: tempFile(),
    httpPost: async () => {
      if (shouldFail) {
        throw new Error("offline");
      }
      return { statusCode: 200, data: { success: true } };
    }
  });

  await store.activateLicense("STAR-1234-KEY");
  shouldFail = true;
  const result = await store.validateLicense();

  assert.equal(result.ok, true);
  assert.equal(store.isPro, true);
});

test("free daily downloads reset on a new day", () => {
  const store = new LicenseStore({ filePath: tempFile() });
  const dayOne = new Date("2026-05-14T10:00:00");
  const dayTwo = new Date("2026-05-15T10:00:00");

  store.recordDownload(dayOne);
  assert.equal(store.getPublicState(dayOne).dailyDownloadsRemaining, 4);
  assert.equal(store.state.lastDownloadDateKey, todayKey(dayOne));

  store.resetDailyCountIfNeeded(dayTwo);
  assert.equal(store.state.dailyDownloadCount, 0);
  assert.equal(store.canStartDownload(dayTwo), true);
});

test("license keys are masked before reaching the renderer", () => {
  assert.equal(maskLicenseKey("abcd-efgh-ijkl"), "abcd...ijkl");
  assert.equal(maskLicenseKey("short"), "****");
  assert.equal(maskLicenseKey(""), "");
});
