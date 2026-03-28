#!/usr/bin/env bash
# check-coverage.sh — Enforce minimum code coverage threshold.
#
# Usage: scripts/check-coverage.sh <path-to-xcresult>
#
# Reads thresholds from .ci/coverage-thresholds.json (relative to repo root).
# Exits non-zero if overall coverage is below minimum_coverage.
# Emits a warning if coverage is below warn_below but above minimum.
#
# Environment:
#   CI_CONFIG_DIR — override path to the directory containing coverage-thresholds.json

set -euo pipefail

XCRESULT_PATH="${1:-}"

# Locate repo root (directory containing this script's parent)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${CI_CONFIG_DIR:-${REPO_ROOT}/.ci}"
CONFIG_FILE="${CONFIG_DIR}/coverage-thresholds.json"

# --- Validate inputs ---

if [[ -z "${XCRESULT_PATH}" ]]; then
  echo "::error::Usage: check-coverage.sh <path-to-xcresult>"
  echo "ERROR: No xcresult path provided." >&2
  exit 1
fi

if [[ ! -d "${XCRESULT_PATH}" ]]; then
  echo "::error::xcresult not found: ${XCRESULT_PATH}"
  echo "ERROR: xcresult bundle not found at ${XCRESULT_PATH}" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "::error::Coverage config not found: ${CONFIG_FILE}"
  echo "ERROR: Coverage threshold config not found at ${CONFIG_FILE}" >&2
  exit 1
fi

# --- Parse config ---

MINIMUM=$(python3 -c "import json,sys; print(json.load(open('${CONFIG_FILE}'))['minimum_coverage'])")
WARN_BELOW=$(python3 -c "import json,sys; print(json.load(open('${CONFIG_FILE}'))['warn_below'])")

# --- Extract coverage ---

COVERAGE_OUTPUT=$(xcrun xccov view --report --only-targets "${XCRESULT_PATH}" 2>/dev/null || true)

if [[ -z "${COVERAGE_OUTPUT}" ]]; then
  echo "::error::No coverage data found in ${XCRESULT_PATH}"
  echo "ERROR: No coverage data found in xcresult bundle." >&2
  exit 1
fi

# Parse the overall coverage percentage from the xccov report.
# xccov outputs lines like: "TargetName.app  45.23% (123/456)"
# We compute a weighted average across all targets.

TOTAL_COVERED=0
TOTAL_LINES=0

while IFS= read -r line; do
  # Extract covered/total from parenthesized fraction like (123/456)
  if [[ "${line}" =~ \(([0-9]+)/([0-9]+)\) ]]; then
    COVERED="${BASH_REMATCH[1]}"
    TOTAL="${BASH_REMATCH[2]}"
    TOTAL_COVERED=$((TOTAL_COVERED + COVERED))
    TOTAL_LINES=$((TOTAL_LINES + TOTAL))
  fi
done <<< "${COVERAGE_OUTPUT}"

if [[ "${TOTAL_LINES}" -eq 0 ]]; then
  echo "::error::Could not parse coverage numbers from xccov output"
  echo "ERROR: Could not parse any coverage data." >&2
  exit 1
fi

OVERALL=$(python3 -c "print(round(${TOTAL_COVERED} / ${TOTAL_LINES} * 100, 2))")

echo "━━━  Coverage Threshold Check  ━━━"
echo "Overall coverage: ${OVERALL}% (${TOTAL_COVERED}/${TOTAL_LINES} lines)"
echo "Minimum required: ${MINIMUM}%"
echo "Warning below:    ${WARN_BELOW}%"
echo ""

# --- Evaluate ---

FAIL=$(python3 -c "print(1 if ${OVERALL} < ${MINIMUM} else 0)")
WARN=$(python3 -c "print(1 if ${OVERALL} < ${WARN_BELOW} else 0)")

if [[ "${FAIL}" == "1" ]]; then
  echo "::error::Coverage ${OVERALL}% is below minimum threshold ${MINIMUM}%"
  echo "FAIL: Coverage ${OVERALL}% is below minimum threshold ${MINIMUM}%." >&2
  exit 1
fi

if [[ "${WARN}" == "1" ]]; then
  echo "::warning::Coverage ${OVERALL}% is below warning threshold ${WARN_BELOW}%"
  echo "WARNING: Coverage ${OVERALL}% is below warning threshold ${WARN_BELOW}%."
fi

echo "PASS: Coverage ${OVERALL}% meets minimum threshold ${MINIMUM}%."
exit 0
