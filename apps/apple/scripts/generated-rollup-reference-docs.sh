#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-check}"
case "$MODE" in
  check|update) ;;
  *)
    echo "usage: scripts/generated-rollup-reference-docs.sh [check|update]" >&2
    exit 2
    ;;
esac

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/healthmd-generated-rollup-reference-docs}"
OUTPUT_DIRECTORY_NAME="healthmd-generated-rollup-reference-docs-current"
REFERENCE_DIRECTORY="docs/reference/generated/rollups"
UPDATE_MARKER="HealthMdTests/.update-generated-rollup-reference-docs"
SEARCH_ROOTS=("$HOME/Library/Containers" "${TMPDIR:-/tmp}" "/tmp")

run_drift_gate() {
  local update_flag="$1"
  TZ=UTC \
  LANG=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8 \
  UPDATE_GENERATED_ROLLUP_REFERENCE_DOCS="$update_flag" \
  xcodebuild test \
    -project HealthMd.xcodeproj \
    -scheme HealthMd-Tests-macOS \
    -destination 'platform=macOS' \
    -only-testing:HealthMdTests/GeneratedRollupReferenceDocsTests/testGeneratedRollupReferenceDocsMatchProductionOutput \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -testLanguage en \
    -testRegion US \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    -quiet
}

if [[ "$MODE" == "check" ]]; then
  rm -f "$UPDATE_MARKER"
  run_drift_gate 0
  echo "Generated roll-up reference docs are current."
  exit 0
fi

for root in "${SEARCH_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r -d '' stale; do
    rm -rf "$stale"
  done < <(find "$root" -type d -name "$OUTPUT_DIRECTORY_NAME" -print0 2>/dev/null || true)
done

touch "$UPDATE_MARKER"
trap 'rm -f "$UPDATE_MARKER"' EXIT
run_drift_gate 1

UPDATE_OUTPUT=""
for root in "${SEARCH_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  UPDATE_OUTPUT="$(find "$root" -type d -name "$OUTPUT_DIRECTORY_NAME" -print -quit 2>/dev/null || true)"
  [[ -n "$UPDATE_OUTPUT" ]] && break
done

if [[ -z "$UPDATE_OUTPUT" || ! -d "$UPDATE_OUTPUT" ]]; then
  echo "error: generated roll-up reference test did not write $OUTPUT_DIRECTORY_NAME" >&2
  exit 1
fi

rm -rf "$REFERENCE_DIRECTORY"
mkdir -p "$REFERENCE_DIRECTORY"
cp -R "$UPDATE_OUTPUT"/. "$REFERENCE_DIRECTORY"/

echo "Updated $REFERENCE_DIRECTORY"
