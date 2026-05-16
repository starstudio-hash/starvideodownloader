#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/run_website_checks.sh"

echo "Building app (Debug, unsigned)..."
xcodebuild \
  -project "$ROOT_DIR/Youtube downloader.xcodeproj" \
  -scheme "Youtube downloader" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/star-video-downloader-smoke-build.log

echo "Smoke checks passed."
