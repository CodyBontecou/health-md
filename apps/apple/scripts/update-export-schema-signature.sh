#!/usr/bin/env bash
set -euo pipefail

# Regenerates the committed export-schema signature fixtures: the current
# HealthMdExportSchema.version (apple-v8) and the separately versioned apple-v12
# successor profile. Once a schema version has shipped, bump the version (or
# introduce a successor profile) before changing a fixture. For an unshipped
# pre-production schema, set ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE=1 to
# intentionally replace that fixture and review the diff.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/healthmd-export-schema-signature}"
UPDATE_MARKER="HealthMdTests/Fixtures/Export/.update-export-schema-signature"
UPDATE_OUTPUT_NAMES=(
  "healthmd-export-schema-signature-current.json"
  "healthmd-export-schema-signature-apple-v12.json"
)

mkdir -p "$(dirname "$UPDATE_MARKER")"
SEARCH_ROOTS=("${TMPDIR:-/tmp}" "/tmp" "$HOME/Library/Containers")
for output_name in "${UPDATE_OUTPUT_NAMES[@]}"; do
  for search_root in "${SEARCH_ROOTS[@]}"; do
    find "$search_root" -name "$output_name" -delete 2>/dev/null || true
  done
done
touch "$UPDATE_MARKER"
trap 'rm -f "$UPDATE_MARKER"' EXIT

# xcodebuild forwards only TEST_RUNNER_-prefixed variables into the test process,
# so the rewrite permission is passed in that form (the update itself uses the marker).
UPDATE_EXPORT_SCHEMA_SIGNATURE=1 \
ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE="${ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE:-0}" \
TEST_RUNNER_ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE="${ALLOW_UNSHIPPED_SCHEMA_SIGNATURE_REWRITE:-0}" \
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-macOS \
  -destination 'platform=macOS' \
  -only-testing:HealthMdTests/ExportSchemaSignatureTests/testExportSchemaSignatureMatchesVersionedFixture \
  -only-testing:HealthMdTests/ExportSchemaSignatureTests/testAppleV12ExportSchemaSignatureMatchesVersionedFixture \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  -quiet

for output_name in "${UPDATE_OUTPUT_NAMES[@]}"; do
  UPDATE_OUTPUT=""
  for search_root in "${SEARCH_ROOTS[@]}"; do
    UPDATE_OUTPUT=$(find "$search_root" -name "$output_name" -print -quit 2>/dev/null || true)
    [[ -n "${UPDATE_OUTPUT:-}" ]] && break
  done
  if [[ -z "${UPDATE_OUTPUT:-}" || ! -s "$UPDATE_OUTPUT" ]]; then
    echo "error: schema signature test did not write $output_name" >&2
    exit 1
  fi

  schema_version=$(python3 - "$UPDATE_OUTPUT" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    print(json.load(f)['schemaVersion'])
PY
)
  fixture="HealthMdTests/Fixtures/Export/export_schema_signature_v${schema_version}.json"
  cp "$UPDATE_OUTPUT" "$fixture"

  echo "Updated $fixture"
done
