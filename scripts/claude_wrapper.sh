#!/usr/bin/env bash
# Wrapper to run the real Claude CLI, capture token usage lines, and append to
# ~/Library/Application Support/ai-usage-tracker/claude.json

REAL_CLAUDE_BIN="${REAL_CLAUDE_BIN:-/usr/local/bin/claude}"
if ! command -v "$REAL_CLAUDE_BIN" >/dev/null 2>&1; then
  echo "Real Claude binary not found at $REAL_CLAUDE_BIN. Set REAL_CLAUDE_BIN env var to actual path." >&2
  exec "$REAL_CLAUDE_BIN" "$@"
fi

OUTPUT="$('$REAL_CLAUDE_BIN' "$@" 2>&1)"
EXIT_CODE=$?

# print original output
printf '%s\n' "$OUTPUT"

# find a token usage line like: "↓ 10.7k tokens"
TOKEN_LINE=$(printf '%s\n' "$OUTPUT" | grep -Eo '↓ *[0-9]+(\.[0-9]+)?[kKmM]? *tokens' | tail -n1)
if [ -z "$TOKEN_LINE" ]; then
  exit $EXIT_CODE
fi

NUM=$(printf '%s\n' "$TOKEN_LINE" | grep -Eo '[0-9]+(\.[0-9]+)?' | head -n1)
SUFFIX=$(printf '%s\n' "$TOKEN_LINE" | grep -Eo '[kKmM]' | head -n1 || true)
TOKENS=$(awk -v n="$NUM" -v s="$SUFFIX" 'BEGIN { if (s=="k" || s=="K") printf("%.0f", n*1000); else if (s=="m" || s=="M") printf("%.0f", n*1000000); else printf("%.0f", n) }')
FILE="$HOME/Library/Application Support/ai-usage-tracker/claude.json"
mkdir -p "$(dirname "$FILE")"
DATE=$(date +%F)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if command -v python3 >/dev/null 2>&1; then
  python3 - <<PY
import json,os
path=os.path.expanduser("$FILE")
entry={"date":"$DATE","tokens":int($TOKENS),"timestamp":"$TIMESTAMP"}
data=[]
if os.path.exists(path):
  try:
    with open(path,'r') as f:
      data=json.load(f)
  except Exception:
    data=[]
data.append(entry)
with open(path,'w') as f:
  json.dump(data,f,indent=2)
PY
elif command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg date "$DATE" --argjson tokens $TOKENS --arg ts "$TIMESTAMP" '. + [{"date":$date,"tokens":$tokens, "timestamp":$ts}]' "$FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$FILE"
else
  # naive append (best-effort, not atomic)
  if [ ! -f "$FILE" ]; then
    echo "[{\"date\":\"$DATE\",\"tokens\":$TOKENS,\"timestamp\":\"$TIMESTAMP\"}]" > "$FILE"
  else
    # remove trailing ] and append
    sed -e '$d' "$FILE" > "$FILE.tmp" || true
    printf ',{"date":"%s","tokens":%s,"timestamp":"%s"}]\n' "$DATE" "$TOKENS" "$TIMESTAMP" >> "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"
  fi
fi

exit $EXIT_CODE
