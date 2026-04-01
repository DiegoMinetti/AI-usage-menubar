#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: package-app.sh <binary-path> [out-app-dir]" >&2
  exit 1
fi

BINARY="$1"
OUT_DIR="${2:-dist/copilot-quota-api.app}"
BINNAME="copilot-quota-api"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/Contents/MacOS"
mkdir -p "$OUT_DIR/Contents/Resources"

cp "$BINARY" "$OUT_DIR/Contents/MacOS/$BINNAME"
chmod +x "$OUT_DIR/Contents/MacOS/$BINNAME"

cat > "$OUT_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>copilot-quota-api</string>
  <key>CFBundleIdentifier</key>
  <string>com.copilot.quota</string>
  <key>CFBundleExecutable</key>
  <string>$BINNAME</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
EOF

echo "Created app bundle: $OUT_DIR"
