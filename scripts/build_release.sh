#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Youtube downloader.xcodeproj"
SCHEME="Youtube downloader"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/StarVideoDownloaderRelease}"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products/Release"
APP_PATH="$BUILD_DIR/Youtube downloader.app"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/exp/Star Video Downloader.zip}"

echo "Building Release app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release app not found at $APP_PATH" >&2
  exit 1
fi

if [[ -n "${STAR_SIGNING_IDENTITY:-}" ]]; then
  echo "Re-signing with identity: $STAR_SIGNING_IDENTITY"
  codesign --force --deep --options runtime --sign "$STAR_SIGNING_IDENTITY" "$APP_PATH"
fi

if [[ -n "${STAR_NOTARY_PROFILE:-}" ]]; then
  echo "Submitting app for notarization with profile: $STAR_NOTARY_PROFILE"
  xcrun notarytool submit "$APP_PATH" --keychain-profile "$STAR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
fi

mkdir -p "$(dirname "$ZIP_PATH")"
rm -f "$ZIP_PATH"
echo "Creating ZIP at $ZIP_PATH"
ditto -c -k --keepParent --norsrc "$APP_PATH" "$ZIP_PATH"

if unzip -l "$ZIP_PATH" | rg -q '(^|/)\._|__MACOSX'; then
  echo "ZIP contains AppleDouble or __MACOSX metadata entries. Refusing to continue." >&2
  exit 1
fi

echo "ZIP contents:"
unzip -l "$ZIP_PATH" | rg "_CodeSignature|MacOS/Youtube downloader|Info.plist" || true

if [[ -n "${STAR_RELEASE_TAG:-}" ]]; then
  echo "Uploading ZIP to GitHub release tag: $STAR_RELEASE_TAG"
  gh release upload "$STAR_RELEASE_TAG" "$ZIP_PATH" --clobber --repo starstudio-hash/starvideodownloader
fi

if [[ -z "${STAR_SIGNING_IDENTITY:-}" || -z "${STAR_NOTARY_PROFILE:-}" ]]; then
  echo
  echo "Note: public macOS releases should use a Developer ID Application identity and notarization."
fi

echo "Done."
