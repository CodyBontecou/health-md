#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

apk=${1:-app/build/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk}
report=${FDROID_DEPENDENCY_REPORT:-app/build/reports/fdroid-release-runtime-classpath.txt}
mkdir -p "$(dirname "$report")"

if [[ ! -f "$apk" ]]; then
  echo "F-Droid release APK is missing: $apk" >&2
  exit 1
fi
if [[ $(basename "$apk") != app-fdroid-release-unsigned.apk ]]; then
  echo "Unexpected F-Droid artifact name: $apk" >&2
  exit 1
fi

if [[ ${FDROID_SKIP_DEPENDENCY_REPORT:-false} != true ]]; then
  ./gradlew --no-daemon :app:dependencies \
    --configuration fdroidReleaseRuntimeClasspath >"$report"
fi
[[ -s "$report" ]] || { echo "F-Droid dependency report is missing: $report" >&2; exit 1; }

forbidden_coordinates=(
  'com.android.billingclient:'
  'com.android.installreferrer:'
  'com.google.android.play:review'
  'com.google.android.gms:play-services-wearable'
  'project :wearable-contract'
)
for coordinate in "${forbidden_coordinates[@]}"; do
  if grep -Fq "$coordinate" "$report"; then
    echo "Forbidden F-Droid runtime dependency: $coordinate" >&2
    grep -F "$coordinate" "$report" >&2 || true
    exit 1
  fi
done

manifest=$(find app/build/intermediates/merged_manifests/fdroidRelease \
  -type f -name AndroidManifest.xml -print -quit)
[[ -n "$manifest" && -f "$manifest" ]] || {
  echo "Merged fdroidRelease manifest is missing" >&2
  exit 1
}
archive_entries=$(zipinfo -1 "$apk")
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  grep -Fxq "lib/$abi/libhealthmd_core_uniffi.so" <<<"$archive_entries" || {
    echo "Shared Rust core missing for Android ABI: $abi" >&2
    exit 1
  }
done
forbidden_manifest_values=(
  'com.android.vending.BILLING'
  'com.android.installreferrer'
  'com.google.android.play.core.review'
  'com.google.android.gms.wearable'
  'WearPhoneDataLayerService'
  'OAuthCallbackActivity'
)
for value in "${forbidden_manifest_values[@]}"; do
  if grep -Fq "$value" "$manifest"; then
    echo "Forbidden F-Droid manifest component: $value" >&2
    exit 1
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -p "$apk" 'classes*.dex' >"$tmp/classes.dex.concat"
strings "$tmp/classes.dex.concat" >"$tmp/dex-strings.txt"
forbidden_packages=(
  'com/android/billingclient'
  'com.android.billingclient'
  'com/android/installreferrer'
  'com.android.installreferrer'
  'com/google/android/play/core/review'
  'com.google.android.play.core.review'
  'com/google/android/gms/wearable'
  'com.google.android.gms.wearable'
  'com/healthmd/data/attribution'
  'com.healthmd.data.attribution'
  'com/healthmd/data/onboardinganalytics'
  'com.healthmd.data.onboardinganalytics'
  'com/healthmd/data/health/oauth'
  'com.healthmd.data.health.oauth'
  'com/healthmd/data/health/providers/cloud'
  'com.healthmd.data.health.providers.cloud'
  'com/healthmd/data/health/providers/direct'
  'com.healthmd.data.health.providers.direct'
  'PlayHealthProviderDefinitions'
  'FITBIT_RANGE_REQUIRED'
  'Fitbit raw export requires'
  'api.fitbit.com'
  'www.fitbit.com/oauth2'
  'wbsapi.withings.net'
  'account.withings.com/oauth2'
  'api.ouraring.com'
  'cloud.ouraring.com/oauth'
  'polarremote.com'
  'flow.polar.com/oauth'
  'api.prod.whoop.com'
  'health-md-pricing-analytics.costream.workers.dev'
  'com/healthmd/presentation/oauth/OAuthCallbackActivity'
  'com.healthmd.presentation.oauth.OAuthCallbackActivity'
  'com/healthmd/rawexport/CloudRawHealthDataProvider'
  'com.healthmd.rawexport.CloudRawHealthDataProvider'
  'com/healthmd/wear/'
  'com.healthmd.wear.'
  'FITBIT_CLIENT_ID'
  'WITHINGS_CLIENT_ID'
  'OURA_CLIENT_ID'
  'POLAR_CLIENT_ID'
  'WHOOP_CLIENT_ID'
  'CAMPAIGN_ATTRIBUTION_ENDPOINT_URL'
  'CAMPAIGN_ATTRIBUTION_INGEST_TOKEN'
  'ONBOARDING_ANALYTICS_ENDPOINT_URL'
)
for package in "${forbidden_packages[@]}"; do
  if grep -Fq "$package" "$tmp/dex-strings.txt"; then
    echo "Forbidden F-Droid APK package reference: $package" >&2
    exit 1
  fi
done

sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [[ -z "$sdk_root" && -f local.properties ]]; then
  sdk_root=$(sed -n 's/^sdk\.dir=//p' local.properties | head -1 | sed 's/\\:/:/g; s/\\\\/\\/g')
fi
[[ -n "$sdk_root" ]] || { echo 'ANDROID_SDK_ROOT, ANDROID_HOME, or sdk.dir is required' >&2; exit 1; }
aapt=$(find "$sdk_root/build-tools" -type f -name aapt -perm -111 | sort -V | tail -1)
aapt2=$(find "$sdk_root/build-tools" -type f -name aapt2 -perm -111 | sort -V | tail -1)
apksigner=$(find "$sdk_root/build-tools" -type f -name apksigner -perm -111 | sort -V | tail -1)
[[ -x "$aapt" ]] || { echo 'Android aapt was not found' >&2; exit 1; }
[[ -x "$aapt2" ]] || { echo 'Android aapt2 was not found' >&2; exit 1; }
[[ -x "$apksigner" ]] || { echo 'Android apksigner was not found' >&2; exit 1; }
"$aapt2" dump resources "$apk" >"$tmp/aapt2-resources.txt"
for resource_name in backup_rules data_extraction_rules; do
  resource_path=$(
    grep -F -A1 "xml/$resource_name" "$tmp/aapt2-resources.txt" |
      sed -n 's/.*(file) \(res\/[^ ]*\.xml\).*/\1/p' |
      head -1
  )
  [[ -n "$resource_path" ]] || {
    echo "F-Droid backup resource was not found: $resource_name" >&2
    exit 1
  }
  "$aapt2" dump xmltree --file "$resource_path" "$apk" >>"$tmp/backup-rules.txt"
done
for state_name in \
  health_md_oauth_tokens \
  wear-sync-private \
  campaign_attribution \
  onboarding_analytics; do
  if grep -Fq "$state_name" "$tmp/backup-rules.txt"; then
    echo "Forbidden Play-only F-Droid backup state: $state_name" >&2
    exit 1
  fi
done
"$aapt" dump resources "$apk" >"$tmp/resources.txt"
for resource in \
  wear_settings_title \
  health_provider_sign_in_failed \
  health_provider_connected \
  health_provider_sign_in_denied \
  health_provider_sign_in_invalid_callback \
  health_provider_sign_in_connection_failed \
  health_provider_samsung_health_summary \
  health_provider_huawei_health_summary \
  health_provider_fitbit_summary \
  health_provider_garmin_summary \
  health_provider_withings_summary \
  health_provider_oura_summary \
  health_provider_polar_summary \
  health_provider_whoop_summary \
  health_provider_integration_cloud_api \
  health_provider_direct_export_requires_oauth_credentials \
  direct_cli_failure_fitbit_range; do
  if grep -Fq "string/$resource" "$tmp/resources.txt"; then
    echo "Forbidden Play-only F-Droid resource: $resource" >&2
    exit 1
  fi
done
if "$apksigner" verify "$apk" >/dev/null 2>&1; then
  echo "fdroidRelease must remain unsigned for fdroidserver signing" >&2
  exit 1
fi
badging=$($aapt dump badging "$apk")
expected_version_code=$(sed -n 's/.*versionCode = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)
expected_version_name=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' app/build.gradle.kts | head -1)
expected_min_sdk=$(sed -n 's/.*minSdk = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)
expected_target_sdk=$(sed -n 's/.*targetSdk = \([0-9][0-9]*\).*/\1/p' app/build.gradle.kts | head -1)
grep -Fq "package: name='com.healthmd.android' versionCode='$expected_version_code' versionName='$expected_version_name'" <<<"$badging"
grep -Fq "sdkVersion:'$expected_min_sdk'" <<<"$badging"
grep -Fq "targetSdkVersion:'$expected_target_sdk'" <<<"$badging"

sha256sum "$apk" | tee "${apk}.sha256"
echo "Verified F-Droid artifact: $apk"
echo "Dependency report: $report"
echo "Merged manifest: $manifest"
