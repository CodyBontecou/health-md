#!/bin/bash
# Manual diagnostic branch only. Exact production source, no gate changes.
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
make build-macos-tests CORE_RUST_PREPARE=: MACOS_DERIVED_DATA_DIR=build/pr189-stop-derived MACOS_CODE_COVERAGE=YES 2>&1 | tee "$out/build.log"
status=0
xcodebuild test-without-building \
  -project HealthMd.xcodeproj -scheme HealthMd-Tests-macOS \
  -derivedDataPath build/pr189-stop-derived \
  -destination "platform=macOS,arch=$(uname -m)" \
  -resultBundlePath build/pr189-stop.xcresult \
  -enableCodeCoverage YES \
  -only-testing:HealthMdTests/AgentBridgeExportPlanningTests/testNativeTransferConfirmsSourceStopAtEachACKAndHostCommitWithoutAnotherReader \
  -only-testing:HealthMdTests/AgentBridgeExportPlanningTests/testNativeTransferSourceStopSurvivesUnavailableReadConfiguration \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  2>&1 | tee "$out/cases.log" || status=$?
python3 - "$out/cases.log" "$status" <<'PY'
from pathlib import Path
import re
import sys
expected = {
    'testNativeTransferConfirmsSourceStopAtEachACKAndHostCommitWithoutAnotherReader',
    'testNativeTransferSourceStopSurvivesUnavailableReadConfiguration',
}
cases = re.findall(r"Test Case '-\[HealthMdTests.AgentBridgeExportPlanningTests ([^\]]+)\]' (passed|failed|skipped) ", Path(sys.argv[1]).read_text())
print(f'DIAGNOSTIC native exit={sys.argv[2]} cases={cases}')
if len(cases) != 2 or {name for name, _ in cases} != expected or any(result == 'skipped' for _, result in cases):
    raise SystemExit('Incomplete focused diagnostic; no runtime qualification claim')
PY
exit "$status"
