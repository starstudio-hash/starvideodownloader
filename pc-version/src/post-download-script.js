"use strict";

const path = require("node:path");

function buildPostDownloadScriptCommand(scriptPath, job = {}, platform = process.platform) {
  const target = String(scriptPath || "").trim();
  const outputPath = String(job.outputPath || "");
  const sourceUrl = String(job.url || "");
  const extension = path.extname(target).toLowerCase();

  if (!target) {
    throw new Error("Post-download script is enabled, but no script file is selected.");
  }

  if (platform === "win32") {
    if (extension === ".ps1") {
      return {
        command: "powershell.exe",
        args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", target, outputPath, sourceUrl]
      };
    }

    if (extension === ".bat" || extension === ".cmd") {
      return {
        command: "cmd.exe",
        args: ["/d", "/s", "/c", target, outputPath, sourceUrl]
      };
    }

    return {
      command: target,
      args: [outputPath, sourceUrl]
    };
  }

  if (extension === ".sh") {
    return {
      command: "/bin/sh",
      args: [target, outputPath, sourceUrl]
    };
  }

  if (extension === ".py") {
    return {
      command: "python3",
      args: [target, outputPath, sourceUrl]
    };
  }

  return {
    command: target,
    args: [outputPath, sourceUrl]
  };
}

module.exports = {
  buildPostDownloadScriptCommand
};
