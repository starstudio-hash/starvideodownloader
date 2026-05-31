"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

const electronPath = require("electron");
const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "star-pc-electron-smoke-"));
const child = spawn(electronPath, [".", "--disable-gpu", "--disable-software-rasterizer"], {
  cwd: path.join(__dirname, ".."),
  env: {
    ...process.env,
    ELECTRON_DISABLE_SECURITY_WARNINGS: "true",
    STAR_PC_SMOKE: "1",
    STAR_PC_SMOKE_USER_DATA: userDataDir
  },
  stdio: ["ignore", "pipe", "pipe"]
});

let output = "";

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
  console.error("Electron smoke test timed out.");
  process.exitCode = 1;
}, 30000);

child.on("close", (code) => {
  clearTimeout(timer);
  fs.rmSync(userDataDir, { recursive: true, force: true });

  if (!output.includes("[STAR_PC_SMOKE_RESULT]")) {
    console.error("Electron smoke test did not emit a smoke result marker.");
    process.exit(1);
  }

  process.exit(code);
});

child.on("error", (error) => {
  clearTimeout(timer);
  fs.rmSync(userDataDir, { recursive: true, force: true });
  console.error(error);
  process.exit(1);
});
