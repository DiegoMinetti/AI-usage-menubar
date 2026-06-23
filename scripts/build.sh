#!/usr/bin/env bash
# build.sh — Build AI-usage-menubar.app for distribution
# Usage: ./scripts/build.sh [--sign "Developer ID: Your Name (TEAMID)"]
set -euo pipefail

###############################################################################
# Configuration
###############################################################################
BUNDLE_ID="com.diegominetti.ai-usage-menubar"
APP_NAME="AI Usage"
EXECUTABLE_NAME="AI-usage-menubar"
VERSION="1.0.3"
BUILD_NUMBER="9"
MAIN_COMMIT="${MAIN_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo local)}"
ENTITLEMENTS="$(pwd)/AI-usage-menubar.entitlements"
SIGN_IDENTITY=""

# Parse optional --sign argument
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN_IDENTITY="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

###############################################################################
# Paths
###############################################################################
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
APP_DIR="$REPO_ROOT/build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

###############################################################################
# Build
###############################################################################
echo "▶ Building Release binary..."
cd "$REPO_ROOT"
swift build -c release 2>&1

###############################################################################
# Assemble .app bundle
###############################################################################
echo "▶ Assembling .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"

# Write Info.plist into bundle (authoritative copy — not the Sources/ one)
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>ai-usage</string>
            </array>
        </dict>
    </array>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Diego Minetti. All rights reserved.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
    <key>AIUsageMainCommit</key>
    <string>${MAIN_COMMIT}</string>
</dict>
</plist>
PLIST

# Copy icon if it exists
ICON_SRC="$REPO_ROOT/Assets/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    # Add CFBundleIconFile to Info.plist
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || true
    echo "  ✓ Icon included"
else
    echo "  ⚠ No icon found at Assets/AppIcon.icns — skipping"
fi

if [[ -f "$REPO_ROOT/scripts/install_from_main.sh" ]]; then
    cp "$REPO_ROOT/scripts/install_from_main.sh" "$RESOURCES_DIR/install_from_main.sh"
    chmod +x "$RESOURCES_DIR/install_from_main.sh"
fi

###############################################################################
# Code signing
###############################################################################
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "▶ Signing with: $SIGN_IDENTITY"
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        "$APP_DIR"
    echo "  ✓ Signed"

    echo "▶ Verifying signature..."
    codesign --verify --deep --strict "$APP_DIR"
    spctl --assess --type execute "$APP_DIR" 2>/dev/null && echo "  ✓ Gatekeeper OK" || echo "  ⚠ Gatekeeper: needs notarization for distribution"
else
    echo "▶ Signing ad-hoc (no Developer ID — for local use only)..."
    codesign \
        --force \
        --deep \
        --entitlements "$ENTITLEMENTS" \
        --sign - \
        "$APP_DIR"
    echo "  ✓ Ad-hoc signed"
    echo "  ℹ To sign for distribution: $0 --sign \"Developer ID Application: Your Name (TEAMID)\""
fi

###############################################################################
# Done
###############################################################################
echo ""
echo "✅ Build complete: $APP_DIR"
echo "   Run: open \"$APP_DIR\""
