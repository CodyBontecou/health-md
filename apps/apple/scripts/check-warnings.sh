#!/usr/bin/env bash
# check-warnings.sh — Detect targeted compiler warnings in build/test logs.
#
# Usage: scripts/check-warnings.sh <build-log-file>
#
# Reads warning patterns and allowed count from .ci/warning-baseline.json.
# Exits non-zero if targeted warning count exceeds the allowed baseline.
# Prints actionable file/line details for each matched warning.
#
# Environment:
#   CI_CONFIG_DIR — override path to the directory containing warning-baseline.json

set -euo pipefail

LOG_FILE="${1:-}"

# Locate repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${CI_CONFIG_DIR:-${REPO_ROOT}/.ci}"
BASELINE_FILE="${CONFIG_DIR}/warning-baseline.json"

# --- Validate inputs ---

if [[ -z "${LOG_FILE}" ]]; then
  echo "::error::Usage: check-warnings.sh <build-log-file>"
  echo "ERROR: No log file path provided." >&2
  exit 1
fi

if [[ ! -f "${LOG_FILE}" ]]; then
  echo "::error::Log file not found: ${LOG_FILE}"
  echo "ERROR: Build log file not found at ${LOG_FILE}" >&2
  exit 1
fi

if [[ ! -f "${BASELINE_FILE}" ]]; then
  echo "::error::Warning baseline not found: ${BASELINE_FILE}"
  echo "ERROR: Warning baseline config not found at ${BASELINE_FILE}" >&2
  exit 1
fi

# --- Parse baseline config ---

ALLOWED_COUNT=$(python3 -c "import json; print(json.load(open('${BASELINE_FILE}'))['allowed_count'])")
PATTERNS_JSON=$(python3 -c "
import json
patterns = json.load(open('${BASELINE_FILE}'))['patterns']
print('|'.join(patterns))
")

# --- Scan log for warnings ---

echo "━━━  Warning Gate Check  ━━━"
echo "Scanning: ${LOG_FILE}"
echo "Patterns: ${PATTERNS_JSON}"
echo "Allowed:  ${ALLOWED_COUNT}"
echo ""

# Match lines containing "warning:" AND one of the targeted patterns
MATCHED_LINES=$(grep -En "warning:.*($PATTERNS_JSON)" "${LOG_FILE}" 2>/dev/null || true)
MATCH_COUNT=0

if [[ -n "${MATCHED_LINES}" ]]; then
  MATCH_COUNT=$(echo "${MATCHED_LINES}" | wc -l | tr -d ' ')
  echo "Found ${MATCH_COUNT} targeted warning(s):"
  echo ""
  echo "${MATCHED_LINES}" | while IFS= read -r line; do
    echo "  ${line}"
  done
  echo ""
else
  echo "No targeted warnings found."
  echo ""
fi

# --- Evaluate ---

if [[ "${MATCH_COUNT}" -gt "${ALLOWED_COUNT}" ]]; then
  DELTA=$((MATCH_COUNT - ALLOWED_COUNT))
  echo "::error::${MATCH_COUNT} targeted warnings found (allowed: ${ALLOWED_COUNT}, ${DELTA} over limit)"
  echo "FAIL: ${MATCH_COUNT} targeted warnings exceed allowed count of ${ALLOWED_COUNT}." >&2
  exit 1
fi

echo "PASS: ${MATCH_COUNT} targeted warnings within allowed count of ${ALLOWED_COUNT}."
exit 0
