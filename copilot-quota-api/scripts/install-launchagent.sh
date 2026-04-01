#!/usr/bin/env bash
set -euo pipefail

# Install LaunchAgent for copilot-quota-api (user-level, autostart)
BASEDIR="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="$(command -v node)"
PLIST="$HOME/Library/LaunchAgents/com.copilot.quota.plist"
OUT_LOG="$HOME/Library/Logs/copilot-quota-api.out.log"
ERR_LOG="$HOME/Library/Logs/copilot-quota-api.err.log"

if [ -z "$NODE_BIN" ]; then
  echo "node not found in PATH. Install Node 18+ and retry." >&2
  exit 1
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.copilot.quota</string>
    <key>ProgramArguments</key>
    <array>
      <string>$NODE_BIN</string>
      <string>$BASEDIR/copilot-quota-api/index.js</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$OUT_LOG</string>
    <key>StandardErrorPath</key>
    <string>$ERR_LOG</string>
  </dict>
</plist>
EOF

echo "Installing LaunchAgent at $PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded. Logs: $OUT_LOG $ERR_LOG"
