#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: check-export-lab-release-absence.sh /path/to/release/binary [...]" >&2
  exit 2
fi

FORBIDDEN=(
  'healthmd://export-lab'
  'HealthMdPerformanceLab'
  'X-HealthMd-Export-Lab-Run'
  'Physical Export Lab'
  'telemetry_version'
)
TEMPORARY="$(mktemp -t healthmd-release-strings.XXXXXX)"
trap 'rm -f "$TEMPORARY"' EXIT

for binary in "$@"; do
  [[ -f "$binary" ]] || { echo "Release binary not found: $binary" >&2; exit 2; }
  strings -a "$binary" >"$TEMPORARY"
  for value in "${FORBIDDEN[@]}"; do
    if grep -Fq "$value" "$TEMPORARY"; then
      echo "Debug export-lab symbol leaked into Release binary $binary: $value" >&2
      exit 1
    fi
  done
done

echo "iOS and macOS Release binaries contain no physical export-lab control or telemetry strings."
