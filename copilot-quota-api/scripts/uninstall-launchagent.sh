#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.copilot.quota.plist"

if [ -f "$PLIST" ]; then
  echo "Unloading and removing $PLIST"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed."
else
  echo "No launch agent found at $PLIST"
fi
