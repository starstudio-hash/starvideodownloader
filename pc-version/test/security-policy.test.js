"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { buildPostDownloadScriptCommand } = require("../src/post-download-script");
const { isSafeExternalUrl, normalizeHttpUrl } = require("../src/url-policy");

test("external URL policy allows only http and https URLs", () => {
  assert.equal(isSafeExternalUrl("https://example.com/watch?v=1"), true);
  assert.equal(isSafeExternalUrl(" http://example.com/video "), true);
  assert.equal(normalizeHttpUrl("https://example.com/a b"), "https://example.com/a%20b");

  assert.equal(isSafeExternalUrl("file:///C:/Windows/System32/calc.exe"), false);
  assert.equal(isSafeExternalUrl("javascript:alert(1)"), false);
  assert.equal(isSafeExternalUrl("mailto:support@example.com"), false);
  assert.equal(isSafeExternalUrl("not a url"), false);
  assert.equal(normalizeHttpUrl(""), "");
});

test("post-download script command keeps user URL as an argument, not a shell command", () => {
  const job = {
    outputPath: "C:\\Users\\Tester\\Videos\\clip.mp4",
    url: "https://example.com/watch?v=1&after=calc"
  };

  const batch = buildPostDownloadScriptCommand("C:\\Scripts\\after-download.cmd", job, "win32");
  assert.equal(batch.command, "cmd.exe");
  assert.deepEqual(batch.args, [
    "/d",
    "/s",
    "/c",
    "C:\\Scripts\\after-download.cmd",
    job.outputPath,
    job.url
  ]);

  const powershell = buildPostDownloadScriptCommand("C:\\Scripts\\after-download.ps1", job, "win32");
  assert.equal(powershell.command, "powershell.exe");
  assert.deepEqual(powershell.args.slice(0, 4), ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]);
  assert.equal(powershell.args[4], "C:\\Scripts\\after-download.ps1");
  assert.equal(powershell.args[5], job.outputPath);
  assert.equal(powershell.args[6], job.url);

  const shellScript = buildPostDownloadScriptCommand("/Users/tester/after-download.sh", job, "darwin");
  assert.equal(shellScript.command, "/bin/sh");
  assert.deepEqual(shellScript.args, ["/Users/tester/after-download.sh", job.outputPath, job.url]);
});
