#!/usr/bin/env bash
# make_dmg.sh — Create a distributable DMG from the built .app
# Prerequisites: hdiutil (built-in macOS), optional: create-dmg (brew install create-dmg)
# Usage: ./scripts/make_dmg.sh
set -euo pipefail

###############################################################################
# Configuration
###############################################################################
APP_NAME="AI Usage"
VERSION="${VERSION:-1.0.3}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$REPO_ROOT/build/${APP_NAME}.app"
DMG_DIR="$REPO_ROOT/build"
DMG_NAME="${APP_NAME// /-}-${VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"
VOLUME_NAME="${APP_NAME} ${VERSION}"

###############################################################################
# Pre-flight check
###############################################################################
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ App bundle not found at: $APP_PATH"
    echo "   Run ./scripts/build_xcode.sh first so the app includes AIUsageWidget.appex."
    exit 1
fi

if [[ ! -d "$APP_PATH/Contents/PlugIns/AIUsageWidget.appex" ]]; then
    echo "❌ Widget extension not found in: $APP_PATH"
    echo "   Run ./scripts/build_xcode.sh first. The SwiftPM build cannot package the native widget."
    exit 1
fi

echo "▶ Creating DMG: $DMG_NAME"

###############################################################################
# Method 1: create-dmg (prettier, drag-to-Applications layout)
###############################################################################
if command -v create-dmg &>/dev/null; then
    echo "  Using create-dmg..."
    create-dmg \
        --volname "$VOLUME_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 175 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 425 190 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$APP_PATH"

###############################################################################
# Method 2: hdiutil (built-in, no extra dependencies)
###############################################################################
else
    echo "  create-dmg not found — using hdiutil (install 'create-dmg' via brew for a nicer DMG)"

    STAGING_DIR="$(mktemp -d)"
    trap "rm -rf $STAGING_DIR" EXIT

    # Copy app and create Applications symlink for drag-install UX
    cp -r "$APP_PATH" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    # Calculate size (add 20% headroom)
    APP_SIZE_KB=$(du -sk "$STAGING_DIR" | cut -f1)
    DMG_SIZE_KB=$(( APP_SIZE_KB * 2 + 51200 ))

    # Create temporary writable DMG
    TEMP_DMG="$(mktemp -u).dmg"
    hdiutil create \
        -srcfolder "$STAGING_DIR" \
        -volname "$VOLUME_NAME" \
        -fs HFS+ \
        -fsargs "-c c=64,a=16,b=16" \
        -format UDRW \
        -size "${DMG_SIZE_KB}k" \
        "$TEMP_DMG"

    # Convert to read-only compressed DMG
    rm -f "$DMG_PATH"
    hdiutil convert "$TEMP_DMG" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$DMG_PATH"
    rm -f "$TEMP_DMG"
fi

###############################################################################
# Notarization hint
###############################################################################
echo ""
echo "✅ DMG ready: $DMG_PATH"
echo ""
echo "── Notarization (required for Gatekeeper on other Macs) ──────────────────"
echo "  xcrun notarytool submit \"$DMG_PATH\" \\"
echo "      --apple-id \"your@apple.id\" \\"
echo "      --team-id  \"YOURTEAMID\" \\"
echo "      --password \"@keychain:notarytool-password\" \\"
echo "      --wait"
echo ""
echo "  xcrun stapler staple \"$DMG_PATH\""
echo "──────────────────────────────────────────────────────────────────────────"
