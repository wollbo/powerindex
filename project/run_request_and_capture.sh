#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./run_request_and_capture.sh <requestId> <registryAddr> <rpcUrl> [outDir]
#
# Writes: <outDir>/latest.json (same schema as your workflow log)

REQUEST_ID="${1:-}"
REGISTRY="${2:-}"
RPC_URL="${3:-}"
OUT_DIR="${4:-out}"
MODE="${5:-demo}"   # demo|real


if [ -z "$REQUEST_ID" ] || [ -z "$REGISTRY" ] || [ -z "$RPC_URL" ]; then
  echo "Usage: $0 <requestId> <registryAddr> <rpcUrl> [outDir]"
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_PATH="$PROJECT_ROOT/$OUT_DIR/latest.json"
CFG="$PROJECT_ROOT/workflow/config.staging.json"
CFG_BAK="$PROJECT_ROOT/$OUT_DIR/config.staging.json.bak"

mkdir -p "$PROJECT_ROOT/$OUT_DIR"

echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "REQUEST_ID=$REQUEST_ID"
echo "REGISTRY=$REGISTRY"
echo "RPC_URL=$RPC_URL"
echo "OUT_PATH=$OUT_PATH"

# --- Read request from chain (robust parsing, avoid --json) ---
mapfile -t F < <(cast call "$REGISTRY" \
  "requests(uint256)(bytes32,bytes32,uint32,string,uint64,uint8,int256,bytes32,uint64)" \
  "$REQUEST_ID" \
  --rpc-url "$RPC_URL")

if [ "${#F[@]}" -lt 9 ]; then
  echo "ERROR: failed reading request. cast returned ${#F[@]} fields:"
  printf '%s\n' "${F[@]}"
  exit 1
fi

INDEX_ID="${F[0]}"
AREA_ID="${F[1]}"
YYYYMMDD="${F[2]}"
CURRENCY="${F[3]}"
CREATED_AT="${F[4]}"
STATUS="${F[5]}"
VALUE_1E6="${F[6]}"
DATASET_HASH="${F[7]}"
FULFILLED_AT="${F[8]}"

# cast prints numbers like: "20260125 [2.026e7]" — keep only the raw value
YYYYMMDD="$(echo "$YYYYMMDD" | awk '{print $1}')"
CREATED_AT="$(echo "$CREATED_AT" | awk '{print $1}')"
STATUS="$(echo "$STATUS" | awk '{print $1}')"
VALUE_1E6="$(echo "$VALUE_1E6" | awk '{print $1}')"
FULFILLED_AT="$(echo "$FULFILLED_AT" | awk '{print $1}')"

# currency sometimes comes quoted; strip quotes if present
CURRENCY="${CURRENCY%\"}"
CURRENCY="${CURRENCY#\"}"

echo "REQUEST: indexId=$INDEX_ID areaId=$AREA_ID yyyymmdd=$YYYYMMDD currency=$CURRENCY status=$STATUS"


if [ "$STATUS" != "1" ]; then
  echo "ERROR: Request $REQUEST_ID is not Pending (status=$STATUS)."
  exit 1
fi

# Convert yyyymmdd -> YYYY-MM-DD
DATE="$(python3 - <<PY
n=$YYYYMMDD
s=str(n)
print(f"{s[0:4]}-{s[4:6]}-{s[6:8]}")
PY
)"

# Resolve areaId -> area string by matching keccak256(area)
# Keep this list in sync with your frontend AREAS.
AREAS=("NO1" "NO2" "NO3" "NO4" "NO5" "SE1" "SE2" "SE3" "SE4" "FI" "DK1" "DK2")
AREA=""
for a in "${AREAS[@]}"; do
  h="$(cast keccak "$a")"
  if [ "${h,,}" = "${AREA_ID,,}" ]; then
    AREA="$a"
    break
  fi
done

if [ -z "$AREA" ]; then
  echo "ERROR: Could not map areaId=$AREA_ID to a known area string."
  echo "Add it to the AREAS list in this script."
  exit 1
fi

echo "Resolved request:"
echo "  indexId=$INDEX_ID"
echo "  areaId=$AREA_ID -> area=$AREA"
echo "  yyyymmdd=$YYYYMMDD -> date=$DATE"
echo "  currency=$CURRENCY"

# --- Patch config.staging.json temporarily ---
cp "$CFG" "$CFG_BAK"

python3 - <<PY
import json
cfg_path="$CFG"
with open(cfg_path,"r") as f:
    cfg=json.load(f)
cfg["area"]="$AREA"
cfg["date"]="$DATE"
cfg["currency"]="$CURRENCY"
cfg["demoMode"] = ("$MODE" != "real")
with open(cfg_path,"w") as f:
    json.dump(cfg,f,indent=2)
    f.write("\n")
print("Patched", cfg_path)
PY

# --- Run CRE workflow simulation (same as your existing script) ---
set +e
LOGS=$(
  cre workflow simulate workflow \
    -R "$PROJECT_ROOT" \
    -T staging-settings \
    --trigger-index 0 \
    --non-interactive
)
STATUS_CODE=$?
set -e

# Always restore config
mv "$CFG_BAK" "$CFG"

if [ "$STATUS_CODE" -ne 0 ]; then
  echo "$LOGS"
  echo "ERROR: CRE simulation failed (exit=$STATUS_CODE)."
  exit "$STATUS_CODE"
fi

JSON_LINE="$(echo "$LOGS" | sed -n 's/^.*POWERINDEX_JSON //p' | tail -n 1)"
if [ -z "$JSON_LINE" ]; then
  echo "$LOGS"
  echo "ERROR: Did not find POWERINDEX_JSON in logs."
  exit 1
fi

echo "$JSON_LINE" > "$OUT_PATH"

echo "Wrote $OUT_PATH"
ls -la "$OUT_PATH"
cat "$OUT_PATH"
