#!/bin/bash
# Diagnostic branch only: run the original full suite with phase measurements.
set -euo pipefail
cd apps/apple
out=build/logs/pr189-rss
mkdir -p "$out"
{
  git rev-parse HEAD
  xcodebuild -version
  xcrun --sdk macosx --show-sdk-version
  shasum -a 256 HealthMd/Shared/Sync/ConnectedCorpusApplicationItem.swift HealthMdTests/Sync/ConnectedCorpusPartitionFileTests.swift
} > "$out/provenance.txt"
git diff --exit-code a130bb5b2f0bb74fe319003bac9169dfafdc5bfd -- HealthMd HealthMdTests
git apply --check ../../.github/scripts/pr189-rss-diagnostic.patch
git apply ../../.github/scripts/pr189-rss-diagnostic.patch
git diff -- HealthMd/Shared/Sync/ConnectedCorpusApplicationItem.swift HealthMdTests/Sync/ConnectedCorpusPartitionFileTests.swift > "$out/applied.patch"
make build-macos-tests CORE_RUST_PREPARE=: MACOS_DERIVED_DATA_DIR=build/pr189-rss-derived MACOS_CODE_COVERAGE=YES 2>&1 | tee "$out/instrumented-build.log"
status=0
xcodebuild test-without-building \
  -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS \
  -derivedDataPath build/pr189-rss-derived \
  -destination "platform=macOS,arch=$(uname -m)" \
  -enableCodeCoverage YES \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  2>&1 | tee "$out/instrumented-fullsuite.log" || status=$?
# Require the actual target plus a full-suite execution, including on failure.
python3 - "$out/instrumented-fullsuite.log" "$status" <<'PY'
import re
import sys
from pathlib import Path
log = Path(sys.argv[1]).read_text()
cases = re.findall(r"Test Case '-\[([^\]]+)\]' (passed|failed|skipped) ", log)
target = [entry for entry in cases if entry[0].split('.')[-1] == 'ConnectedCorpusPartitionFileTests testStreamableDecoderMapsLargeProductionHealthDayDataWithoutItemSizedRSSCopy']
print(f'DIAGNOSTIC full-suite exit={sys.argv[2]} completed-cases={len(cases)} target={target}')
if len(cases) < 2900 or len(target) != 1:
    raise SystemExit('Incomplete diagnostic coverage; not a full-suite result')
PY
exit "$status"
