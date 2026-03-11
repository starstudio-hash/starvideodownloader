#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Building app (Debug, unsigned)..."
xcodebuild \
  -project "$ROOT_DIR/Youtube downloader.xcodeproj" \
  -scheme "Youtube downloader" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/star-video-downloader-smoke-build.log

echo "Checking website metadata..."
for file in "$ROOT_DIR"/*.html; do
  rg -q "<title>" "$file"
  rg -q "rel=\"canonical\"" "$file"
  rg -q "meta name=\"description\"" "$file"
done

echo "Smoke checks passed."
