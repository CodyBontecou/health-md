#!/usr/bin/env bash
# Check the four app-generated reference groups in one build and test session.
# DERIVED_DATA_PATH optionally reuses caller-owned build products. Set
# REFERENCE_DOCS_XCRESULT_PATH to retain the result bundle; otherwise all temporary
# products and results are removed when the command exits.
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: scripts/check-generated-reference-docs.sh" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# A generation marker makes a drift test write output instead of comparing it.
# Refuse an overlapping update rather than removing another command's marker.
for marker in \
  HealthMdTests/Fixtures/Documentation/.generated-export-docs-output \
  HealthMdTests/Documentation/.update-generated-individual-entry-docs \
  HealthMdTests/.update-generated-rollup-reference-docs \
  HealthMdTests/.update-generated-automation-reference-docs; do
  if [[ -e "$marker" || -L "$marker" ]]; then
    echo "error: reference generation marker exists: $marker; finish the update before checking" >&2
    exit 1
  fi
done

# The former core output-directory diff also rejected hidden entries and extra
# directories. Its XCTest compares regular, visible filenames and file bytes;
# retain the stricter directory-inventory check around that same assertion.
python3 - <<'PY'
from pathlib import Path

directory = Path("docs/reference/generated/core")
unexpected = [entry.name for entry in directory.iterdir()
              if entry.name.startswith(".") or not entry.is_file()]
if unexpected:
    raise SystemExit(f"error: unexpected core reference entries: {sorted(unexpected)}")
PY

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/healthmd-reference-check.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$TMP_ROOT/DerivedData}"
RESULT_BUNDLE="${REFERENCE_DOCS_XCRESULT_PATH:-$TMP_ROOT/ReferenceDocs.xcresult}"

schema_fixture_digest() {
  find HealthMdTests/Fixtures/Export -type f -name 'export_schema_signature_v*.json' -print0 \
    | LC_ALL=C sort -z | xargs -0 shasum -a 256
}
SCHEMA_BEFORE="$(schema_fixture_digest)"

env -u GENERATED_EXPORT_DOCS_OUTPUT_DIR \
  -u GENERATED_INDIVIDUAL_ENTRY_DOCS_OUTPUT_BASENAME \
  -u GENERATED_INDIVIDUAL_ENTRY_DOCS_MODE \
  -u UPDATE_GENERATED_ROLLUP_REFERENCE_DOCS \
  TZ=UTC LC_ALL=C LANG=C LANGUAGE=en_US AppleLocale=en_US_POSIX \
  xcodebuild test \
    -project HealthMd.xcodeproj \
    -scheme HealthMd-Tests-macOS \
    -destination 'platform=macOS' \
    -parallel-testing-enabled NO \
    -only-testing:HealthMdTests/GeneratedExportDocumentationTests/testGeneratedExportDocumentationIsCurrent \
    -only-testing:HealthMdTests/IndividualEntryDocumentationTests/testGeneratedIndividualEntryDocumentationHasNoDrift \
    -only-testing:HealthMdTests/GeneratedRollupReferenceDocsTests/testGeneratedRollupReferenceDocsMatchProductionOutput \
    -only-testing:HealthMdTests/GeneratedAutomationReferenceDocumentationTests/testGeneratedAutomationReferenceDocumentationHasNoDrift \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -testLanguage en -testRegion US \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" -quiet

if [[ "$SCHEMA_BEFORE" != "$(schema_fixture_digest)" ]]; then
  echo "error: schema-signature fixture changed during reference checks" >&2
  exit 1
fi

# Xcode can succeed with no tests after a selector is renamed. Require all four
# checks to have executed successfully, with no skipped or expected failures.
xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" > "$TMP_ROOT/summary.json"
python3 - "$TMP_ROOT/summary.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    summary = json.load(source)
expected = {
    "totalTestCount": 4,
    "passedTests": 4,
    "failedTests": 0,
    "skippedTests": 0,
    "expectedFailures": 0,
    "result": "Passed",
}
actual = {key: summary.get(key) for key in expected}
if actual != expected:
    raise SystemExit(f"error: expected four passing documentation checks; received {actual}")
print("Generated export reference checks passed: 4 tests, 0 skips.")
PY
