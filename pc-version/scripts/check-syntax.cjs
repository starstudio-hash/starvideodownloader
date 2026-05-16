"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const groups = [
  ["src", (name) => name.endsWith(".js")],
  ["test", (name) => name.endsWith(".test.js")],
  ["scripts", (name) => name.endsWith(".cjs")]
];

let failed = false;

for (const [directory, predicate] of groups) {
  const dir = path.join(root, directory);
  if (!fs.existsSync(dir)) {
    continue;
  }

  for (const name of fs.readdirSync(dir).filter(predicate).sort()) {
    const file = path.join(dir, name);
    const result = spawnSync(process.execPath, ["--check", file], {
      encoding: "utf8",
      stdio: "pipe"
    });

    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);

    if (result.status !== 0) {
      failed = true;
    }
  }
}

if (failed) {
  process.exit(1);
}
