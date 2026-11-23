#!/usr/bin/env bash
# Build MMDStudio for iOS on a macOS runner. Unsigned by default.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-MMDStudio}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
ARCHIVE_PATH="$BUILD_DIR/MMDStudio.xcarchive"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGE_DIR="$BUILD_DIR/ipa-stage"
LOG_PATH="$BUILD_DIR/xcodebuild.log"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found" >&2
  exit 1
fi

if [ ! -d "MMDStudio/MMDStudio.xcodeproj" ] && [ -f "MMDStudio-iOS27.zip" ]; then
  unzip -q "MMDStudio-iOS27.zip"
fi

PROJECT_PATH="$(find "$ROOT" -maxdepth 3 -name MMDStudio.xcodeproj -type d | head -n 1)"
if [ -z "${PROJECT_PATH:-}" ] || [ ! -d "$PROJECT_PATH" ]; then
  echo "MMDStudio.xcodeproj not found" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA" "$STAGE_DIR"

echo "Project: $PROJECT_PATH"
xcodebuild -project "$PROJECT_PATH" -list >/dev/null

set +e
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean archive 2>&1 | tee "$LOG_PATH"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  echo "xcodebuild failed" >&2
  exit "$STATUS"
fi

APP="$ARCHIVE_PATH/Products/Applications/MMDStudio.app"
test -d "$APP"
IPA_PATH="$BUILD_DIR/MMDStudio-unsigned.ipa"
mkdir -p "$STAGE_DIR/Payload"
cp -R "$APP" "$STAGE_DIR/Payload/MMDStudio.app"
rm -f "$IPA_PATH"
(cd "$STAGE_DIR" && zip -qry "$IPA_PATH" Payload)
echo "IPA: $IPA_PATH"