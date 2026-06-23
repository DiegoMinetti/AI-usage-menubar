#!/usr/bin/env bash
# Build and install the latest app from the repository main branch.
# Usage:
#   ./scripts/install_from_main.sh
#   INSTALL_DIR=/Applications ./scripts/install_from_main.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/DiegoMinetti/AI-usage-menubar.git}"
BRANCH="${BRANCH:-main}"
APP_NAME="${APP_NAME:-AI Usage}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "▶ Fetching $REPO_URL#$BRANCH"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMP_DIR/repo"

cd "$TMP_DIR/repo"
MAIN_COMMIT="$(git rev-parse HEAD)"
echo "▶ Building commit $MAIN_COMMIT"

if [[ -d "AI Usage.xcodeproj" && -x "./scripts/build_xcode.sh" && -n "${DEVELOPMENT_TEAM:-}" ]]; then
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" ./scripts/build_xcode.sh
  BUILT_APP="$TMP_DIR/repo/.build/xcode-native/Build/Products/Release/${APP_NAME}.app"
else
  MAIN_COMMIT="$MAIN_COMMIT" ./scripts/build.sh
  BUILT_APP="$TMP_DIR/repo/build/${APP_NAME}.app"
fi

if [[ ! -d "$BUILT_APP" ]]; then
  echo "❌ Built app not found at $BUILT_APP" >&2
  exit 1
fi

DEST="$INSTALL_DIR/${APP_NAME}.app"
echo "▶ Installing to $DEST"
mkdir -p "$INSTALL_DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -x "AI-usage-menubar" >/dev/null 2>&1; then
  osascript -e 'tell application "AI Usage" to quit' >/dev/null 2>&1 || true
  sleep 2
fi

rm -rf "$DEST"
ditto "$BUILT_APP" "$DEST"
xattr -rd com.apple.quarantine "$DEST" 2>/dev/null || true
xattr -rd com.apple.provenance "$DEST" 2>/dev/null || true
open "$DEST"

echo "✅ Installed $APP_NAME from main ($MAIN_COMMIT)"
