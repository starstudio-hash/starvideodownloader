#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_ZIP="$ROOT_DIR/exp/Star.Video.Downloader.Windows.zip"
WINDOWS_ZIP_URL="https://github.com/starstudio-hash/starvideodownloader/releases/latest/download/Star.Video.Downloader.Windows.zip"

echo "Checking website metadata..."
for file in "$ROOT_DIR"/*.html; do
  rg -q "<title>" "$file"
  rg -q "rel=\"canonical\"" "$file"
  rg -q "meta name=\"description\"" "$file"
done

echo "Checking Mac and PC landing page links and sitemap..."
rg -q "pc-video-downloader" "$ROOT_DIR/sitemap.xml"
rg -q "mac-video-downloader" "$ROOT_DIR/sitemap.xml"
rg -q "$WINDOWS_ZIP_URL" "$ROOT_DIR/index.html"
rg -q "$WINDOWS_ZIP_URL" "$ROOT_DIR/pc-video-downloader.html"
rg -q "$WINDOWS_ZIP_URL" "$ROOT_DIR/pricing.html"
rg -q "$WINDOWS_ZIP_URL" "$ROOT_DIR/about.html"
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

echo "Checking Windows release ZIP..."
windows_headers="$(curl -I -L -s "$WINDOWS_ZIP_URL")"
if ! print -r -- "$windows_headers" | rg -q "HTTP/[0-9.]+ 200"; then
  echo "Windows release ZIP URL did not return 200 OK" >&2
  print -r -- "$windows_headers" >&2
  exit 1
fi

if [[ -f "$WINDOWS_ZIP" ]]; then
  zip_size=$(stat -f%z "$WINDOWS_ZIP")
  if (( zip_size < 100000000 )); then
    echo "Windows ZIP looks too small: $zip_size bytes" >&2
    exit 1
  fi

  zip_listing="$(unzip -l "$WINDOWS_ZIP")"
  if ! print -r -- "$zip_listing" | rg -q "Star Video Downloader\\.exe"; then
    echo "Windows ZIP is missing Star Video Downloader.exe" >&2
    exit 1
  fi

  if ! print -r -- "$zip_listing" | rg -q "resources/app\\.asar"; then
    echo "Windows ZIP is missing resources/app.asar" >&2
    exit 1
  fi

  if print -r -- "$zip_listing" | rg -q "(^|/)__MACOSX|(^|/)\\._"; then
    echo "Windows ZIP contains macOS metadata files" >&2
    exit 1
  fi
else
  echo "Local Windows ZIP not present; remote release URL check passed."
fi

echo "Website checks passed."
