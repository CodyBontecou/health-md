#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/generated-export-docs.sh <update|check>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
MODE="$1"
[[ "$MODE" == "update" || "$MODE" == "check" ]] || usage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GENERATED_RELATIVE="docs/reference/generated/core"
GENERATED_DIR="$ROOT_DIR/$GENERATED_RELATIVE"
SCHEMA_FIXTURE_DIR="$ROOT_DIR/HealthMdTests/Fixtures/Export"

case "$GENERATED_DIR" in
  "$ROOT_DIR/docs/reference/generated/core") ;;
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

SCHEMA_BEFORE="$(schema_fixture_digest)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/healthmd-generated-export-docs.XXXXXX")"
OUTPUT_DIR="$TMP_ROOT/output"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$TMP_ROOT/DerivedData}"
OUTPUT_MARKER="$ROOT_DIR/HealthMdTests/Fixtures/Documentation/.generated-export-docs-output"
cleanup() {
  rm -f "$OUTPUT_MARKER"
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
printf '%s\n' "$OUTPUT_DIR" > "$OUTPUT_MARKER"

TZ=UTC \
LC_ALL=C \
LANG=C \
LANGUAGE=en_US \
AppleLocale=en_US_POSIX \
GENERATED_EXPORT_DOCS_OUTPUT_DIR="$OUTPUT_DIR" \
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-macOS \
  -destination 'platform=macOS' \
  -only-testing:HealthMdTests/GeneratedExportDocumentationTests/testGeneratedExportDocumentationIsCurrent \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  -quiet

[[ -d "$OUTPUT_DIR" && -s "$OUTPUT_DIR/manifest.json" ]] || {
  echo "error: generator test did not produce a complete output directory" >&2
  exit 1
}

SCHEMA_AFTER="$(schema_fixture_digest)"
if [[ "$SCHEMA_BEFORE" != "$SCHEMA_AFTER" ]]; then
  echo "error: schema-signature fixture changed; refusing generated documentation operation" >&2
  exit 1
fi

if [[ "$MODE" == "update" ]]; then
  rm -rf "$GENERATED_DIR"
  mkdir -p "$GENERATED_DIR"
  cp -R "$OUTPUT_DIR/." "$GENERATED_DIR/"
  echo "Updated $GENERATED_RELATIVE"
  exit 0
fi

if [[ ! -d "$GENERATED_DIR" ]]; then
  echo "error: missing $GENERATED_RELATIVE; run scripts/generated-export-docs.sh update" >&2
  exit 1
fi

if ! diff -r -q "$GENERATED_DIR" "$OUTPUT_DIR" >/dev/null; then
  echo "error: generated export documentation drift detected" >&2
  diff -r -u "$GENERATED_DIR" "$OUTPUT_DIR" || true
  exit 1
fi

echo "Generated export documentation is current."
