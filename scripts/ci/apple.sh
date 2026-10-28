#!/usr/bin/env bash
# The CI runner supplies Xcode, Rust 1.88, caches and an available iOS simulator.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
    echo 'Apple CI requires an arm64 Mac' >&2
    exit 1
}
export HEALTHMD_CORE_APPLE_SCOPE=ci-arm64
results=apps/apple/build/ci-results
mkdir -p "$results"
# Only this lane's disposable results are removed; incremental builds stay warm.
rm -rf "$results/macos.xcresult" "$results/ios.xcresult"
make -C apps/apple prepare-healthmd-core-rust
swift test --package-path apps/apple/Packages/HealthMdCoreRust
swift test --package-path apps/apple/Packages/HealthMdConnectivity
common=(
    -project apps/apple/HealthMd.xcodeproj
    -derivedDataPath apps/apple/build/ci-derived-data
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
    ONLY_ACTIVE_ARCH=YES ARCHS=arm64
)
mac_cases=(
    AppleLooseDailyExportPlannerTests/testConcreteShadowPlanAndAsyncPreviewAreTheExactNativeOraclePlan
    AppleLooseDailyExportPlannerTests/testVaultLegacyBytesUnchangedAndShadowAndRustCommitOnlySelectedAuthority
    ExportOrchestratorTests/testCIProductionExportReadsSDKValuesAndWritesRealMarkdown
    ExportOrchestratorTests/testExportDates_partialHealthKitFailure_writesSuccessfulCategoriesAndReturnsWarning
    ExportOrchestratorTests/testExportDates_midLoopCancellationKeepsPartialResults
    ExportProfileStoreTests/testMigrationCreatesDefaultProfileOnce
    ExportProfileStoreTests/testProfilesPersistAcrossStoreInstances
    ConfigurationProtectionManagerTests/testProtectedBindingRejectsChangesUntilProtectionIsDisabled
)
mac_selection=()
for test_case in "${mac_cases[@]}"; do
    mac_selection+=("-only-testing:HealthMdTests/$test_case")
done
xcodebuild test "${common[@]}" -quiet \
    -enableCodeCoverage NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 25 -maximum-test-execution-time-allowance 30 \
    -scheme HealthMd-Tests-macOS -configuration Debug -parallel-testing-enabled NO \
    -destination 'platform=macOS,arch=arm64' \
    -resultBundlePath "$results/macos.xcresult" "${mac_selection[@]}"
python3 scripts/ci/verify_xcresult.py "$results/macos.xcresult" "${mac_cases[@]}"
# Compile the iOS app against its real SDK. Simulator UI automation is retired:
# startup intermittently hangs before executing a test, exceeding this budget.
xcodebuild build "${common[@]}" -quiet \
    -scheme HealthMd -configuration Debug-iOS \
    -destination 'generic/platform=iOS Simulator'
