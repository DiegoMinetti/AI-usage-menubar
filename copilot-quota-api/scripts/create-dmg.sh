#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: create-dmg.sh <app-path> <out-dmg>" >&2
  exit 1
fi

APP="$1"
OUT="$2"

if [ "$(uname)" != "Darwin" ]; then
  echo "create-dmg.sh must run on macOS" >&2
  exit 1
fi

rm -f "$OUT"
hdiutil create -volname "copilot-quota-api" -srcfolder "$APP" -ov -format UDZO "$OUT"
echo "Created $OUT"
