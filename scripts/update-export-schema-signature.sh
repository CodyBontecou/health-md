#!/usr/bin/env bash
set -euo pipefail

# Regenerates the committed export-schema signature fixture for the current
# HealthMdExportSchema.version. The XCTest refuses to update an existing fixture
# when the fingerprint changed without first bumping the schema version.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/healthmd-export-schema-signature}"
UPDATE_MARKER="HealthMdTests/Fixtures/Export/.update-export-schema-signature"
UPDATE_OUTPUT_NAME="healthmd-export-schema-signature-current.json"

mkdir -p "$(dirname "$UPDATE_MARKER")"
find "$HOME/Library/Containers" -name "$UPDATE_OUTPUT_NAME" -delete 2>/dev/null || true
touch "$UPDATE_MARKER"
trap 'rm -f "$UPDATE_MARKER"' EXIT

UPDATE_EXPORT_SCHEMA_SIGNATURE=1 xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-macOS \
  -destination 'platform=macOS' \
  -only-testing:HealthMdTests/ExportSchemaSignatureTests/testExportSchemaSignatureMatchesVersionedFixture \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -quiet

UPDATE_OUTPUT=$(find "$HOME/Library/Containers" -name "$UPDATE_OUTPUT_NAME" -print 2>/dev/null | head -n 1)
if [[ -z "${UPDATE_OUTPUT:-}" || ! -s "$UPDATE_OUTPUT" ]]; then
  echo "error: schema signature test did not write $UPDATE_OUTPUT_NAME" >&2
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
