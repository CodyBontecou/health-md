#!/usr/bin/env bash
# One ABI, one Play build, real SAF/export journey and native FFI smoke.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
: "${ANDROID_SERIAL:?Select exactly one already booted CI device}"
# Other CLI regression tests exercise port 18647. An ephemeral listener keeps
# concurrently running suites from connecting to each other's protocol fixture.
export HEALTHMD_LIVE_DIRECT_PORT=${HEALTHMD_LIVE_DIRECT_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')}
export HEALTHMD_LIVE_PAIRING_CODE=12345678901234567890
abi=${HEALTHMD_CI_ANDROID_ABI:-x86_64}
results=apps/android/build/ci-results
mkdir -p "$results"
rm -rf apps/android/healthmd-core/build/test-results/testDebugUnitTest apps/android/app/build/test-results/testPlayE2eUnitTest apps/android/direct-protocol/build/test-results/test apps/android/healthmd-core/build/outputs/androidTest-results/connected apps/android/app/build/outputs/androidTest-results/connected
log="$results/rust-listener.log"
# Launch the test executable directly so the cleanup PID owns the listener,
# rather than killing Cargo and leaving its child holding the TCP port.
cargo test --manifest-path apps/cli/Cargo.toml -p healthmd-client --all-features --locked \
    --test android_live_listener --no-run --message-format=json >"$results/interop-build.json"
listener=$(python3 -c 'import json,sys; a=[json.loads(line) for line in open(sys.argv[1])]; e=[x["executable"] for x in a if x.get("target",{}).get("name")=="android_live_listener" and x.get("executable")]; assert len(e)==1; print(e[0])' "$results/interop-build.json")
"$listener" --ignored --exact accepts_android_pairing_and_v2_negotiation --nocapture >"$log" 2>&1 &
listener_pid=$!
trap 'kill "$listener_pid" 2>/dev/null || true' EXIT
for _ in {1..450}; do
    if rg -q "ANDROID_LIVE_LISTENER_READY:$HEALTHMD_LIVE_DIRECT_PORT" "$log"; then break; fi
    if ! kill -0 "$listener_pid" 2>/dev/null; then cat "$log"; wait "$listener_pid"; exit 1; fi
    sleep 0.1
done
rg -q "ANDROID_LIVE_LISTENER_READY:$HEALTHMD_LIVE_DIRECT_PORT" "$log"
cd apps/android
common=(-Phealthmd.ciAbi="$abi" -PhealthmdInstrumentedTestBuildType=e2e --max-workers=2 --console=plain)
./scripts/run-ci-gradle.sh "${common[@]}" :app:testPlayE2eUnitTest \
    --tests com.healthmd.data.health.HealthConnectPinnedZoneRangeTest \
    --tests com.healthmd.domain.exportengine.ExportRepositoryEngineSeamTest \
    --tests com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotTest \
    --tests com.healthmd.data.settings.ConfigurationProtectionRepositoryTest \
    :direct-protocol:test :healthmd-core:testDebugUnitTest
wait "$listener_pid"
trap - EXIT
./gradlew "${common[@]}" :app:connectedPlayE2eAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class=com.healthmd.ci.CIExportRegressionTest,com.healthmd.domain.semantic.HealthMdSemanticInputAdapterInstrumentationTest,com.healthmd.domain.exportengine.DailyAggregateRustPlannerInstrumentationTest
./gradlew "${common[@]}" :healthmd-core:connectedDebugAndroidTest
cd "$repo_root"
python3 scripts/ci/verify_junit.py \
    apps/android/app/build/test-results/testPlayE2eUnitTest \
    apps/android/direct-protocol/build/test-results/test \
    apps/android/healthmd-core/build/test-results/testDebugUnitTest \
    apps/android/app/build/outputs/androidTest-results/connected \
    apps/android/healthmd-core/build/outputs/androidTest-results/connected \
    --require com.healthmd.ci.CIExportRegressionTest#productionExportWritesSdkValuesAndSettingsSurviveReopen \
    --require com.healthmd.domain.semantic.HealthMdSemanticInputAdapterInstrumentationTest#capturedModelEncodesOnceAndProcessesThroughPackagedRustCore \
    --require com.healthmd.domain.exportengine.DailyAggregateRustPlannerInstrumentationTest#packagedCorePlansExactNativeBytesForBothAndroidProfiles \
    --require com.healthmd.direct.protocol.LiveCliInteropTest#pairsAndNegotiatesWithRustListener \
    --require com.healthmd.core.HealthMdCoreInstrumentationTest#packagedNativeCorePassesBuildInfoSelfTestAndStableMalformedInputError \
    --require com.healthmd.core.HealthMdCoreInstrumentationTest#packagedProtocolFoundationMatchesPureV1V2CryptoAndTransferFixtures
