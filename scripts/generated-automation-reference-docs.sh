#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/generated-automation-reference-docs.sh <update|check>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
MODE="$1"
[[ "$MODE" == "update" || "$MODE" == "check" ]] || usage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GENERATED_RELATIVE="docs/reference/generated/automation"
GENERATED_DIR="$ROOT_DIR/$GENERATED_RELATIVE"
SCHEMA_FIXTURE_DIR="$ROOT_DIR/HealthMdTests/Fixtures/Export"
UPDATE_MARKER="$ROOT_DIR/HealthMdTests/.update-generated-automation-reference-docs"
OUTPUT_DIRECTORY_NAME="healthmd-generated-automation-reference-docs-current"
SEARCH_ROOTS=("$HOME/Library/Containers" "${TMPDIR:-/tmp}" "/tmp")

case "$GENERATED_DIR" in
  "$ROOT_DIR/docs/reference/generated/automation") ;;
  *) echo "error: refusing unexpected generated destination: $GENERATED_DIR" >&2; exit 1 ;;
esac
case "$GENERATED_DIR" in
  *HealthMdTests/Fixtures/Export*|*export_schema_signature*)
    echo "error: refusing schema-signature fixture destination" >&2
    exit 1
    ;;
esac

schema_fixture_digest() {
  /usr/bin/find "$SCHEMA_FIXTURE_DIR" -type f -name 'export_schema_signature_v*.json' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256 2>/dev/null \
    || true
}

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/healthmd-generated-automation-docs.XXXXXX")"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$TMP_ROOT/DerivedData}"
trap 'rm -f "$UPDATE_MARKER"; rm -rf "$TMP_ROOT"' EXIT

run_drift_test() {
  TZ=UTC \
  LC_ALL=C \
  LANG=C \
  LANGUAGE=en_US \
  AppleLocale=en_US_POSIX \
  xcodebuild test \
    -project HealthMd.xcodeproj \
    -scheme HealthMd-Tests-macOS \
    -destination 'platform=macOS' \
    -only-testing:HealthMdTests/GeneratedAutomationReferenceDocumentationTests/testGeneratedAutomationReferenceDocumentationHasNoDrift \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    -quiet
}

SCHEMA_BEFORE="$(schema_fixture_digest)"

if [[ "$MODE" == "check" ]]; then
  rm -f "$UPDATE_MARKER"
  run_drift_test
  SCHEMA_AFTER="$(schema_fixture_digest)"
  if [[ "$SCHEMA_BEFORE" != "$SCHEMA_AFTER" ]]; then
    echo "error: schema-signature fixture changed; refusing generated documentation operation" >&2
    exit 1
  fi
  echo "Generated automation documentation is current."
  exit 0
fi

for root in "${SEARCH_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r -d '' stale; do
    rm -rf "$stale"
  done < <(/usr/bin/find "$root" -type d -name "$OUTPUT_DIRECTORY_NAME" -print0 2>/dev/null || true)
done

touch "$UPDATE_MARKER"
run_drift_test
rm -f "$UPDATE_MARKER"

OUTPUT_DIR=""
for root in "${SEARCH_ROOTS[@]}"; do
  [[ -d "$root" ]] || continue
  candidate="$(/usr/bin/find "$root" -type d -name "$OUTPUT_DIRECTORY_NAME" -print -quit 2>/dev/null || true)"
  if [[ -n "$candidate" && -s "$candidate/.complete" ]]; then
    OUTPUT_DIR="$candidate"
    break
  fi
done

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "error: generator test did not stage $OUTPUT_DIRECTORY_NAME" >&2
  exit 1
fi

ARTIFACT_COUNT="$(<"$OUTPUT_DIR/.complete")"
if [[ ! "$ARTIFACT_COUNT" =~ ^[0-9]+$ ]]; then
  echo "error: invalid generated artifact count: $ARTIFACT_COUNT" >&2
  exit 1
fi

rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR"
cp -R "$OUTPUT_DIR/." "$GENERATED_DIR/"
rm -f "$GENERATED_DIR/.complete"

COPIED_COUNT="$(/usr/bin/find "$GENERATED_DIR" -type f | wc -l | tr -d ' ')"
if [[ "$COPIED_COUNT" != "$ARTIFACT_COUNT" || ! -s "$GENERATED_DIR/manifest.json" ]]; then
  echo "error: expected $ARTIFACT_COUNT artifacts but copied $COPIED_COUNT" >&2
  exit 1
fi

SCHEMA_AFTER="$(schema_fixture_digest)"
if [[ "$SCHEMA_BEFORE" != "$SCHEMA_AFTER" ]]; then
  echo "error: schema-signature fixture changed; refusing generated documentation operation" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
echo "Updated $ARTIFACT_COUNT artifacts under $GENERATED_RELATIVE."
