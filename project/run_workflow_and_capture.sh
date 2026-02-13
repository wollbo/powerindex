#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-out}"
OUT_PATH="$PROJECT_ROOT/$OUT_DIR/latest.json"

mkdir -p "$PROJECT_ROOT/$OUT_DIR"

echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "OUT_PATH=$OUT_PATH"

LOGS=$(
  cre workflow simulate workflow \
    -R "$PROJECT_ROOT" \
    -T staging-settings \
    --trigger-index 0 \
    --non-interactive
)

# Extract the JSON payload (last occurrence)
JSON_LINE="$(echo "$LOGS" | sed -n 's/^.*POWERINDEX_JSON //p' | tail -n 1)"

if [ -z "$JSON_LINE" ]; then
  echo "ERROR: Did not find POWERINDEX_JSON in logs."
  exit 1
fi

echo "$JSON_LINE" > "$OUT_PATH"

echo "Wrote $OUT_PATH"
ls -la "$OUT_PATH"
cat "$OUT_PATH"
