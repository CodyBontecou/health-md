#!/usr/bin/env bash
# check-tdd-evidence.sh — Validate that completed testing todos include TDD evidence.
#
# Usage: scripts/check-tdd-evidence.sh
#
# Scans .pi/todos/*.md for testing-related todos marked "done" and verifies
# each one contains RED, GREEN, and REFACTOR evidence sections.
#
# Environment:
#   TODOS_DIR — override path to the todos directory (default: .pi/todos)

set -euo pipefail

# Locate repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TODOS_DIR="${TODOS_DIR:-${REPO_ROOT}/.pi/todos}"

# --- Validate inputs ---

if [[ ! -d "${TODOS_DIR}" ]]; then
  echo "::error::Todos directory not found: ${TODOS_DIR}"
  echo "ERROR: Todos directory not found at ${TODOS_DIR}" >&2
  exit 1
fi

echo "━━━  TDD Evidence Guard  ━━━"
echo "Scanning: ${TODOS_DIR}"
echo ""

FAILURES=0
CHECKED=0
OFFENDERS=()

for todo_file in "${TODOS_DIR}"/*.md; do
  [[ -f "${todo_file}" ]] || continue

  # Read the file content
  content=$(cat "${todo_file}")

  # Check if this is a testing-related todo (has "testing" tag)
  if ! echo "${content}" | grep -q '"testing"'; then
    continue
  fi

  # Check if marked done
  if ! echo "${content}" | grep -q '"status": "done"'; then
    continue
  fi

  CHECKED=$((CHECKED + 1))
  todo_id=$(basename "${todo_file}" .md)
  missing=()

  # Check for RED evidence
  if ! echo "${content}" | grep -qi '### RED'; then
    missing+=("RED")
  fi

  # Check for GREEN evidence
  if ! echo "${content}" | grep -qi '### GREEN'; then
    missing+=("GREEN")
  fi

  # Check for REFACTOR evidence
  if ! echo "${content}" | grep -qi '### REFACTOR'; then
    missing+=("REFACTOR")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    FAILURES=$((FAILURES + 1))
    missing_str=$(IFS=', '; echo "${missing[*]}")
    OFFENDERS+=("TODO-${todo_id}: missing ${missing_str}")
    echo "::error::TODO-${todo_id} is marked done but missing TDD evidence: ${missing_str}"
    echo "  FAIL: TODO-${todo_id} — missing: ${missing_str}"
  else
    echo "  PASS: TODO-${todo_id}"
  fi
done

echo ""
echo "Checked ${CHECKED} completed testing todo(s)."

if [[ "${FAILURES}" -gt 0 ]]; then
  echo ""
  echo "::error::${FAILURES} testing todo(s) marked done without complete TDD evidence"
  echo "FAIL: ${FAILURES} todo(s) missing required TDD evidence:" >&2
  for offender in "${OFFENDERS[@]}"; do
    echo "  - ${offender}" >&2
  done
  echo "" >&2
  echo "Required evidence sections: ### RED, ### GREEN, ### REFACTOR" >&2
  echo "See docs/testing/TDD.md and docs/testing/TDD-COMPLETION-TEMPLATE.md" >&2
  exit 1
fi

echo "PASS: All completed testing todos have TDD evidence."
exit 0
