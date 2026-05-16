#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_INSTALLER="$ROOT_DIR/exp/Star.Video.Downloader.Setup.exe"
WINDOWS_INSTALLER_URL="https://github.com/starstudio-hash/starvideodownloader/releases/latest/download/Star.Video.Downloader.Setup.exe"

echo "Checking website metadata..."
for file in "$ROOT_DIR"/*.html; do
  rg -q "<title>" "$file"
  rg -q "rel=\"canonical\"" "$file"
  rg -q "meta name=\"description\"" "$file"
done

echo "Checking Mac and PC landing page links and sitemap..."
rg -q "pc-video-downloader" "$ROOT_DIR/sitemap.xml"
rg -q "mac-video-downloader" "$ROOT_DIR/sitemap.xml"
rg -q "$WINDOWS_INSTALLER_URL" "$ROOT_DIR/index.html"
rg -q "$WINDOWS_INSTALLER_URL" "$ROOT_DIR/pc-video-downloader.html"
rg -q "$WINDOWS_INSTALLER_URL" "$ROOT_DIR/pricing.html"
rg -q "$WINDOWS_INSTALLER_URL" "$ROOT_DIR/about.html"
rg -q "Star.Video.Downloader.zip" "$ROOT_DIR/mac-video-downloader.html"
rg -q "YouTube video downloader for Mac" "$ROOT_DIR/mac-video-downloader.html"
rg -q "Star.Video.Downloader.zip" "$ROOT_DIR/index.html"
rg -q "Download Mac Free" "$ROOT_DIR/index.html"
rg -q "Download PC Free" "$ROOT_DIR/index.html"
rg -q "Windows PC" "$ROOT_DIR/index.html"
rg -q "Mac and Windows PC" "$ROOT_DIR/guides.html"
rg -q "Windows PC" "$ROOT_DIR/comparisons.html"
rg -q "Start with your platform" "$ROOT_DIR/guides.html"
rg -q "Windows PC" "$ROOT_DIR/pricing.html"
rg -q "Windows PC" "$ROOT_DIR/help.html"
rg -q "Mac and Windows PC" "$ROOT_DIR/about.html"
rg -q "Mac and Windows PC" "$ROOT_DIR/privacy.html"
rg -q "Mac or Windows PC" "$ROOT_DIR/safety.html"

echo "Checking JSON-LD..."
node - "$ROOT_DIR" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const root = process.argv[2];
const pages = ["index.html", "pricing.html", "mac-video-downloader.html", "pc-video-downloader.html", "guides.html", "comparisons.html"];

for (const page of pages) {
  const html = fs.readFileSync(path.join(root, page), "utf8");
  const scripts = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];

  if (scripts.length === 0) {
    throw new Error(`${page} has no JSON-LD`);
  }

  for (const script of scripts) {
    JSON.parse(script[1].trim());
  }
}
NODE

echo "Checking Windows installer release..."
windows_headers="$(curl -I -L -s "$WINDOWS_INSTALLER_URL")"
if ! print -r -- "$windows_headers" | rg -q "HTTP/[0-9.]+ 200"; then
  echo "Windows installer URL did not return 200 OK" >&2
  print -r -- "$windows_headers" >&2
  exit 1
fi

if [[ -f "$WINDOWS_INSTALLER" ]]; then
  installer_size=$(stat -f%z "$WINDOWS_INSTALLER")
  if (( installer_size < 90000000 )); then
    echo "Windows installer looks too small: $installer_size bytes" >&2
    exit 1
  fi

  installer_type="$(file "$WINDOWS_INSTALLER")"
  if ! print -r -- "$installer_type" | rg -q "Nullsoft Installer|PE32 executable"; then
    echo "Windows installer does not look like a Windows setup executable" >&2
    print -r -- "$installer_type" >&2
    exit 1
  fi

  installer_listing="$(bsdtar -tf "$WINDOWS_INSTALLER")"
  if ! print -r -- "$installer_listing" | rg -q "Star Video Downloader\\.exe"; then
    echo "Windows installer is missing Star Video Downloader.exe" >&2
    exit 1
  fi

  if ! print -r -- "$installer_listing" | rg -q "resources/app\\.asar"; then
    echo "Windows installer is missing resources/app.asar" >&2
    exit 1
  fi

  if print -r -- "$installer_listing" | rg -q "(^|/)__MACOSX|(^|/)\\._"; then
    echo "Windows installer contains macOS metadata files" >&2
    exit 1
  fi
else
  echo "Local Windows installer not present; remote release URL check passed."
fi

echo "Website checks passed."
