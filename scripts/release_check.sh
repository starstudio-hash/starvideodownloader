#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/Star.Video.Downloader.zip" >&2
  exit 1
fi

ZIP_PATH="$1"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "File not found: $ZIP_PATH" >&2
  exit 1
fi

echo "Checking ZIP structure..."
unzip -l "$ZIP_PATH" | rg "_CodeSignature|MacOS/Youtube downloader|Info.plist"

if unzip -l "$ZIP_PATH" | rg -q '(^|/)\._|__MACOSX'; then
  echo
  echo "Release ZIP contains AppleDouble or __MACOSX metadata entries." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ditto -x -k "$ZIP_PATH" "$TMP_DIR"
APP_PATH="$(find "$TMP_DIR" -maxdepth 2 -name 'Youtube downloader.app' -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "App bundle not found after unzip." >&2
  exit 1
fi

echo
echo "codesign:"
codesign --verify --deep --strict "$APP_PATH" && echo "codesign verify passed"

echo
echo "spctl:"
SPCTL_OUTPUT="$(spctl -a -vv "$APP_PATH" 2>&1 || true)"
echo "$SPCTL_OUTPUT"

if echo "$SPCTL_OUTPUT" | rg -q "rejected"; then
  echo
  echo "Warning: Gatekeeper rejected this build. Public downloads should be signed with Developer ID Application and notarized." >&2
  if [[ "${REQUIRE_TRUSTED_RELEASE:-0}" == "1" ]]; then
    exit 1
  fi
fi
