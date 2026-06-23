#!/usr/bin/env bash
# build_xcode.sh — Build the native macOS app with the WidgetKit extension.
# Usage:
#   ./scripts/build_xcode.sh
#   DEVELOPMENT_TEAM=TEAMID ./scripts/build_xcode.sh
#   ALLOW_UNSIGNED=1 ./scripts/build_xcode.sh   # compile-only; widget will not install
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/AI Usage.xcodeproj"
SCHEME="AI Usage"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="$REPO_ROOT/.build/xcode-native"

args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  -allowProvisioningUpdates
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

if [[ "${ALLOW_UNSIGNED:-0}" == "1" ]]; then
  args+=(CODE_SIGNING_ALLOWED=NO)
fi

echo "▶ Building native app + WidgetKit extension..."
xcodebuild "${args[@]}" build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/AI Usage.app"
DIST_APP="$REPO_ROOT/build/AI Usage.app"
if [[ "${ALLOW_UNSIGNED:-0}" != "1" && -d "$APP_PATH" ]]; then
  xattr -rd com.apple.quarantine "$APP_PATH" 2>/dev/null || true
  xattr -rd com.apple.provenance "$APP_PATH" 2>/dev/null || true
fi

if [[ -d "$APP_PATH" && "${COPY_TO_BUILD:-1}" == "1" ]]; then
  echo "▶ Copying native app bundle to build/..."
  rm -rf "$DIST_APP"
  mkdir -p "$REPO_ROOT/build"
  ditto "$APP_PATH" "$DIST_APP"

  if [[ "${ALLOW_UNSIGNED:-0}" != "1" ]]; then
    xattr -rd com.apple.quarantine "$DIST_APP" 2>/dev/null || true
    xattr -rd com.apple.provenance "$DIST_APP" 2>/dev/null || true
  fi
fi

echo ""
echo "✅ Build complete: $APP_PATH"
echo "   Run: open \"$APP_PATH\""
if [[ -d "$DIST_APP" ]]; then
  echo "   Distribution bundle: $DIST_APP"
fi
