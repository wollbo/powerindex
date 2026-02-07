#!/usr/bin/env bash
set -euo pipefail

# This script assumes it lives inside the CRE project root folder (where project.yaml is).
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-out}"

mkdir -p "$PROJECT_ROOT/$OUT_DIR"

LOGS=$(
  cre workflow simulate workflow \
    -R "$PROJECT_ROOT" \
    -T staging-settings \
    --trigger-index 0 \
    --non-interactive
)

echo "$LOGS"

# Extract the JSON line from logs
echo "$LOGS" | sed -n 's/^.*POWERINDEX_JSON //p' | tail -n 1 > "$PROJECT_ROOT/$OUT_DIR/latest.json"

echo "Wrote $PROJECT_ROOT/$OUT_DIR/latest.json"
cat "$PROJECT_ROOT/$OUT_DIR/latest.json"
