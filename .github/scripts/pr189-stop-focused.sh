#!/bin/bash
# Manual diagnostic branch only. Production source and authority fences remain exact.
set -euo pipefail
cd candidate/apps/apple
out=build/logs/pr189-stop
mkdir -p "$out"
{
  git rev-parse HEAD
  git rev-parse HEAD^{tree}
  xcodebuild -version
  xcrun --sdk macosx --show-sdk-version
  shasum -a 256 HealthMd/Shared/Export/AgentBridgeNativeConfigurationReader.swift HealthMdTests/Export/AgentBridgeExportPlanningTests.swift
} > "$out/provenance.txt"
git diff --exit-code
cases=(
  testNativeTransferConfirmsSourceStopAtEachACKAndHostCommitWithoutAnotherReader
  testNativeTransferSourceStopSurvivesUnavailableReadConfiguration
)
case "${APPLY_STOP_FIXTURE_CANDIDATE:-false}" in
  false) ;;
  true)
    patch="$GITHUB_WORKSPACE/.github/scripts/pr189-stop-fixture-phases.patch"
    git apply --check "$patch"
    git apply "$patch"
    test "$(git diff --name-only)" = apps/apple/HealthMdTests/Export/AgentBridgeExportPlanningTests.swift
    test "$(shasum -a 256 HealthMdTests/Export/AgentBridgeExportPlanningTests.swift | awk '{print $1}')" = f038e989ded5fd1c61daa395a54e7c007e164c21adcf3c5c02bb5b8307dec72c
    git diff -- HealthMdTests/Export/AgentBridgeExportPlanningTests.swift > "$out/applied.patch"
    shasum -a 256 "$patch" HealthMdTests/Export/AgentBridgeExportPlanningTests.swift >> "$out/provenance.txt"
    cases=(
      testNativeTransferConfirmsSourceStopAtDispositionWithoutAnotherReader
      testNativeTransferConfirmsSourceStopAtChunkACKWithoutAnotherReader
      testNativeTransferConfirmsSourceStopAtPartitionACKWithoutAnotherReader
      testNativeTransferConfirmsSourceStopAtFinalACKWithoutAnotherReader
      testNativeTransferConfirmsSourceStopAtHostCommitWithoutAnotherReader
      testNativeTransferSourceStopSurvivesUnavailableReadConfiguration
      testNativeTransferRevocationDuringGuardedWriteCannotConfirmSourceStop
      testNativeReceiveCancelsRetainedJobsWithoutCatalogOrReadPermissionAndReplaysExactReceipt
      testNativeStopDuringPreparationWaitsForWorkerCleanupBeforeAcknowledging
    )
    ;;
  *) exit 2 ;;
esac
printf '%s\n' "${cases[@]}" > "$out/expected-cases.txt"
test_args=()
for name in "${cases[@]}"; do test_args+=("-only-testing:HealthMdTests/AgentBridgeExportPlanningTests/$name"); done
make build-macos-tests CORE_RUST_PREPARE=: MACOS_DERIVED_DATA_DIR=build/pr189-stop-derived MACOS_CODE_COVERAGE=YES 2>&1 | tee "$out/build.log"
status=0
xcodebuild test-without-building \
  -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS \
  -derivedDataPath build/pr189-stop-derived \
  -destination "platform=macOS,arch=$(uname -m)" \
  -resultBundlePath build/pr189-stop.xcresult \
  -enableCodeCoverage YES \
  "${test_args[@]}" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  2>&1 | tee "$out/cases.log" || status=$?
python3 - "$out/cases.log" "$status" "$out/expected-cases.txt" <<'PY'
from pathlib import Path
import re
import sys
expected = set(Path(sys.argv[3]).read_text().splitlines())
cases = re.findall(r"Test Case '-\[HealthMdTests.AgentBridgeExportPlanningTests ([^\]]+)\]' (passed|failed|skipped) ", Path(sys.argv[1]).read_text())
print(f'DIAGNOSTIC native exit={sys.argv[2]} cases={cases}')
if len(cases) != len(expected) or {name for name, _ in cases} != expected or any(result == 'skipped' for _, result in cases):
    raise SystemExit('Incomplete focused diagnostic; no runtime qualification claim')
if sys.argv[2] == '0' and any(result != 'passed' for _, result in cases):
    raise SystemExit('Native success contradicts recorded test outcomes')
PY
exit "$status"
