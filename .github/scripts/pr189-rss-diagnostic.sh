#!/bin/bash
# Diagnostic branch only. No test assertions, inputs or limits are changed.
set -euo pipefail
cd apps/apple
mkdir -p build/logs/pr189-rss
out=build/logs/pr189-rss
{
  git rev-parse HEAD
  xcodebuild -version
  xcrun --sdk macosx --show-sdk-version
  shasum -a 256 HealthMd/Shared/Sync/ConnectedCorpusApplicationItem.swift HealthMdTests/Sync/ConnectedCorpusPartitionFileTests.swift
} > "$out/provenance.txt"
git diff --exit-code a130bb5b2f0bb74fe319003bac9169dfafdc5bfd -- HealthMd HealthMdTests
make build-macos-tests CORE_RUST_PREPARE=: MACOS_DERIVED_DATA_DIR=build/pr189-rss-derived MACOS_CODE_COVERAGE=YES 2>&1 | tee "$out/baseline-build.log"
failed=0
run_cases() {
  local phase="$1"
  local iteration status
  for iteration in 1 2 3; do
    if xcodebuild test-without-building \
      -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS \
      -derivedDataPath build/pr189-rss-derived \
      -destination "platform=macOS,arch=$(uname -m)" \
      -enableCodeCoverage YES \
      -only-testing:HealthMdTests/ConnectedCorpusPartitionFileTests/testStreamableDecoderMapsLargeProductionHealthDayDataWithoutItemSizedRSSCopy \
      -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
      -maximum-test-execution-time-allowance 300 \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
      DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
      2>&1 | tee "$out/$phase-$iteration.log"; then
      status=0
    else
      status=$?
      failed=1
    fi
    count=$(grep -Ec 'testStreamableDecoderMapsLargeProductionHealthDayDataWithoutItemSizedRSSCopy.* (passed|failed) ' "$out/$phase-$iteration.log" || true)
    if [[ "$count" != 1 ]]; then
      echo "Missing exact production-model case result: $phase iteration=$iteration count=$count" >&2
      failed=1
      if [[ "$status" == 0 ]]; then status=1; fi
    fi
    echo "$phase iteration=$iteration exit=$status cases=$count" | tee -a "$out/outcomes.txt"
  done
}
# Isolate the original production-model case before earlier class tests can warm allocators.
run_cases original
git apply --check ../../.github/scripts/pr189-rss-diagnostic.patch
git apply ../../.github/scripts/pr189-rss-diagnostic.patch
git diff -- HealthMd/Shared/Sync/ConnectedCorpusApplicationItem.swift HealthMdTests/Sync/ConnectedCorpusPartitionFileTests.swift > "$out/applied.patch"
make build-macos-tests CORE_RUST_PREPARE=: MACOS_DERIVED_DATA_DIR=build/pr189-rss-derived MACOS_CODE_COVERAGE=YES 2>&1 | tee "$out/instrumented-build.log"
run_cases instrumented
exit "$failed"
