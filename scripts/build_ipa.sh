#!/usr/bin/env bash
# 在 macOS + Xcode 上把 MMDStudio 工程打成 IPA。
# 默认不签名；设置 ADHOC_SIGN=1 可做 ad-hoc 签名（仅适合 TrollStore / 越狱 / 侧载）。
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
ADHOC_SIGN="${ADHOC_SIGN:-0}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：找不到 xcodebuild。本脚本必须在 macOS + Xcode 环境运行。" >&2
  exit 1
fi

# GitHub Actions 仓库里通常只有 zip；本地目录里通常直接有工程。
if [ ! -d "MMDStudio.xcodeproj" ] && [ ! -d "MMDStudio/MMDStudio.xcodeproj" ] && [ -f "MMDStudio-iOS27.zip" ]; then
  echo "解压 MMDStudio-iOS27.zip ..."
  unzip -q -o "MMDStudio-iOS27.zip"
fi

if [ -n "${PROJECT:-}" ]; then
  PROJECT_PATH="$PROJECT"
else
  PROJECT_PATH="$(find "$ROOT" -maxdepth 3 -name MMDStudio.xcodeproj -type d | head -n 1)"
fi
if [ -z "${PROJECT_PATH:-}" ] || [ ! -d "$PROJECT_PATH" ]; then
  echo "错误：找不到 MMDStudio.xcodeproj。" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA" "$STAGE_DIR"

echo "Project: $PROJECT_PATH"
echo "Scheme:  $SCHEME"
echo "Config:  $CONFIGURATION"

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
  echo "xcodebuild 失败，完整日志：$LOG_PATH" >&2
  exit "$STATUS"
fi

APP="$ARCHIVE_PATH/Products/Applications/MMDStudio.app"
if [ ! -d "$APP" ]; then
  echo "错误：archive 中找不到 MMDStudio.app：$APP" >&2
  exit 1
fi

if [ "$ADHOC_SIGN" = "1" ] || [ "$ADHOC_SIGN" = "true" ]; then
  echo "执行 ad-hoc 签名 ..."
  codesign --force --deep --sign - "$APP"
  IPA_PATH="$BUILD_DIR/MMDStudio-adhoc.ipa"
else
  IPA_PATH="$BUILD_DIR/MMDStudio-unsigned.ipa"
fi

mkdir -p "$STAGE_DIR/Payload"
if command -v ditto >/dev/null 2>&1; then
  ditto "$APP" "$STAGE_DIR/Payload/MMDStudio.app"
else
  cp -R "$APP" "$STAGE_DIR/Payload/MMDStudio.app"
fi

rm -f "$IPA_PATH"
(cd "$STAGE_DIR" && zip -qry "$IPA_PATH" Payload)

echo ""
echo "IPA 已生成：$IPA_PATH"
echo "大小：$(du -h "$IPA_PATH" | cut -f1)"