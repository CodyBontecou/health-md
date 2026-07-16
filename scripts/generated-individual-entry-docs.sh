#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-check}"
case "$MODE" in
  update|check) ;;
  *)
    echo "usage: $0 [update|check]" >&2
    exit 64
    ;;
esac

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/healthmd-generated-individual-entry-docs-derived}"
UPDATE_MARKER="HealthMdTests/Documentation/.update-generated-individual-entry-docs"
TEST_IDENTIFIER="HealthMdTests/IndividualEntryDocumentationTests/testGeneratedIndividualEntryDocumentationHasNoDrift"
XCODE_FLAGS=(
  -project HealthMd.xcodeproj
  -scheme HealthMd-Tests-macOS
  -destination 'platform=macOS'
  -only-testing:"$TEST_IDENTIFIER"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  DEVELOPMENT_TEAM=""
  PROVISIONING_PROFILE_SPECIFIER=""
  -quiet
)

if [[ "$MODE" == "check" ]]; then
  rm -f "$UPDATE_MARKER"
  TZ=UTC LC_ALL=C xcodebuild test "${XCODE_FLAGS[@]}"
  echo "Individual Entry Tracking generated documentation is current."
  exit 0
fi

OUTPUT_BASENAME="healthmd-generated-individual-entry-docs-$$"
SEARCH_ROOTS=("${TMPDIR:-/tmp}" "/tmp" "$HOME/Library/Containers")
for root in "${SEARCH_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  find "$root" -type d -name "$OUTPUT_BASENAME" -prune -exec rm -rf {} + 2>/dev/null || true
done

printf '%s\n' "$OUTPUT_BASENAME" > "$UPDATE_MARKER"
trap 'rm -f "$UPDATE_MARKER"' EXIT

GENERATED_INDIVIDUAL_ENTRY_DOCS_MODE=update \
GENERATED_INDIVIDUAL_ENTRY_DOCS_OUTPUT_BASENAME="$OUTPUT_BASENAME" \
TZ=UTC LC_ALL=C \
xcodebuild test "${XCODE_FLAGS[@]}"

OUTPUT_DIR=""
for root in "${SEARCH_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  candidate="$(find "$root" -type d -name "$OUTPUT_BASENAME" -print -quit 2>/dev/null || true)"
  if [[ -n "$candidate" && -f "$candidate/.complete" ]]; then
    OUTPUT_DIR="$candidate"
    break
  fi
done

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "error: documentation test did not stage generated artifacts" >&2
  exit 1
fi

ARTIFACT_COUNT="$(<"$OUTPUT_DIR/.complete")"
if [[ ! "$ARTIFACT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "error: invalid generated artifact count: $ARTIFACT_COUNT" >&2
  exit 1
fi

TARGET_DIR="docs/reference/generated/individual"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
find "$OUTPUT_DIR" -type f -name '*.md' -exec cp {} "$TARGET_DIR/" \;

COPIED_COUNT="$(find "$TARGET_DIR" -type f -name '*.md' | wc -l | tr -d ' ')"
if [[ "$COPIED_COUNT" != "$ARTIFACT_COUNT" ]]; then
  echo "error: expected $ARTIFACT_COUNT artifacts but copied $COPIED_COUNT" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
echo "Updated $ARTIFACT_COUNT artifacts under $TARGET_DIR."
