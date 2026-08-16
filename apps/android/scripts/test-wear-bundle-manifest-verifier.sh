#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
aab=${1:-wear/build/outputs/bundle/release/wear-release.aab}
phone_aab=${2:-}
[[ -f "$aab" ]] || { echo "Wear AAB unavailable: $aab" >&2; exit 1; }
[[ -z "$phone_aab" || -f "$phone_aab" ]] || { echo "phone AAB unavailable: $phone_aab" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
proto=$(find "$HOME/.gradle/caches/modules-2/files-2.1/com.android.tools.build/aapt2-proto" -name 'aapt2-proto-*.jar' -print | sort -V | tail -1)
protobuf=$(find "$HOME/.gradle/caches/modules-2/files-2.1/com.google.protobuf/protobuf-java" -name 'protobuf-java-*.jar' -print | sort -V | tail -1)
[[ -f "$proto" && -f "$protobuf" ]] || { echo 'protobuf dependencies unavailable' >&2; exit 1; }
javac -cp "$proto:$protobuf" -d "$tmp/classes" \
  scripts/WearBundleManifestVerifier.java scripts/WearBundleFixtureMutator.java
wear_gradle=wear/build.gradle.kts
expected_package=$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$wear_gradle" | head -1)
expected_code=$(sed -n 's/.*versionCode = \([0-9_]*\).*/\1/p' "$wear_gradle" | head -1 | tr -d _)
expected_name=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' "$wear_gradle" | head -1)
expected_min=$(sed -n 's/.*minSdk = \([0-9_]*\).*/\1/p' "$wear_gradle" | head -1 | tr -d _)
expected_target=$(sed -n 's/.*targetSdk = \([0-9_]*\).*/\1/p' "$wear_gradle" | head -1 | tr -d _)
for value in "$expected_package" "$expected_code" "$expected_name" "$expected_min" "$expected_target"; do
  [[ -n "$value" ]] || { echo 'expected Wear identity unavailable' >&2; exit 1; }
done
verify() {
  java -cp "$tmp/classes:$proto:$protobuf" WearBundleManifestVerifier wear \
    "$1" "$expected_package" "$expected_code" "$expected_name" "$expected_min" "$expected_target"
}
verify "$aab"
different_same_length() {
  python3 - "$1" <<'PY'
import sys
value = sys.argv[1]
assert value
last = value[-1]
replacement = "0" if last != "0" else "1"
print(value[:-1] + replacement)
PY
}
negative() {
  local old=$1 new=$2 expected=$3 name=$4 target=${5:-base/manifest/AndroidManifest.xml}
  rm -rf "$tmp/bundle" "$tmp/bad.aab"
  unzip -q "$aab" -d "$tmp/bundle"
  python3 - "$tmp/bundle/$target" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
data = open(path, 'rb').read()
assert old in data, old
assert len(old) == len(new), (old, new)
open(path, 'wb').write(data.replace(old, new, 1))
PY
  (cd "$tmp/bundle" && zip -qr "$tmp/bad.aab" .)
  if verify "$tmp/bad.aab" >"$tmp/out" 2>"$tmp/error"; then
    echo "negative packaged-manifest fixture unexpectedly passed: $name" >&2
    exit 1
  fi
  grep -q "$expected" "$tmp/error"
}
negative "$expected_package" "$(different_same_length "$expected_package")" 'wrong package' package
negative "$expected_code" "$(different_same_length "$expected_code")" 'wrong packaged versionCode' version-code
negative "$expected_name" "$(different_same_length "$expected_name")" 'wrong packaged versionName' version-name
negative android.hardware.type.watch android.hardware.type.watci 'required watch feature missing' watch-feature
negative com.google.android.wearable.standalone com.google.android.wearable.standalonf 'standalone=false missing' standalone
negative healthmd_watch_sync healthmd_watch_synb 'compiled static capability set differs' capability base/resources.pb
negative DATA_CHANGED DATA_CHANGEE 'Wear Data Layer actions/path filter missing or split incorrectly' data-action
negative android.permission.DUMP android.permission.DUMQ 'diagnostics provider lacks DUMP protection' diagnostics-permission
negative RECEIVE_BOOT_COMPLETED RECEIVE_BOOT_COMPLETEE 'packaged permission set differs' permission-set
negative DailyActivityTileService DailyActivityTileServicf 'Tile identity set differs' tile-identity
negative StepsComplicationService StepsComplicationServicf 'complication identity set differs' complication-identity
negative BIND_COMPLICATION_PROVIDER BIND_COMPLICATION_PROVIDES 'bind permission missing' complication-permission
negative /healthmd/wear /healthmd/weas 'Wear Data Layer actions/path filter missing or split incorrectly' data-layer-path
structural_negative() {
  local artifact=$1 verifier=$2 target=$3 mode=$4 service=$5 expected=$6 name=$7
  rm -rf "$tmp/structural-bundle" "$tmp/structural-bad.aab" "$tmp/mutated.pb"
  unzip -q "$artifact" -d "$tmp/structural-bundle"
  if [[ "$target" == resources ]]; then
    java -cp "$tmp/classes:$proto:$protobuf" WearBundleFixtureMutator resources \
      "$tmp/structural-bundle/base/resources.pb" "$tmp/mutated.pb" "$mode"
    mv "$tmp/mutated.pb" "$tmp/structural-bundle/base/resources.pb"
  else
    java -cp "$tmp/classes:$proto:$protobuf" WearBundleFixtureMutator manifest \
      "$tmp/structural-bundle/base/manifest/AndroidManifest.xml" "$tmp/mutated.pb" "$mode" "$service"
    mv "$tmp/mutated.pb" "$tmp/structural-bundle/base/manifest/AndroidManifest.xml"
  fi
  (cd "$tmp/structural-bundle" && zip -qr "$tmp/structural-bad.aab" .)
  if "$verifier" "$tmp/structural-bad.aab" >"$tmp/structural-out" 2>"$tmp/structural-error"; then
    echo "structural packaged fixture unexpectedly passed: $name" >&2
    exit 1
  fi
  grep -q "$expected" "$tmp/structural-error"
}
structural_negative "$aab" verify resources extra-capability - 'compiled static capability set differs' capability-extra
structural_negative "$aab" verify resources reference-capability - 'compiled static capability set differs' capability-reference
structural_negative "$aab" verify resources qualified-capability - 'compiled static capability must use the unqualified default configuration' capability-qualified
structural_negative "$aab" verify manifest extra-filter com.healthmd.wear.sync.WearDataLayerService 'Wear Data Layer actions/path filter missing or split incorrectly' wear-extra-filter
structural_negative "$aab" verify manifest duplicate-service com.healthmd.wear.sync.WearDataLayerService 'Wear Data Layer listener inventory differs' wear-duplicate-listener
structural_negative "$aab" verify manifest duplicate-other-service com.healthmd.wear.sync.WearDataLayerService 'unexpected Wear Data Layer listener service' wear-extra-listener
structural_negative "$aab" verify manifest duplicate-other-action com.healthmd.wear.sync.WearDataLayerService 'unexpected Wear Data Layer listener service' wear-other-data-layer-action
rm -rf "$tmp/license-bundle" "$tmp/no-license.aab"
unzip -q "$aab" -d "$tmp/license-bundle"
rm "$tmp/license-bundle/base/assets/licenses/geist-ofl.txt"
(cd "$tmp/license-bundle" && zip -qr "$tmp/no-license.aab" .)
if verify "$tmp/no-license.aab" >"$tmp/license-out" 2>"$tmp/license-error"; then
  echo 'packaged Wear bundle without the Geist OFL unexpectedly passed' >&2
  exit 1
fi
grep -q 'bundled Geist license/source notice missing' "$tmp/license-error"

rm -rf "$tmp/license-bundle" "$tmp/no-app-license.aab"
unzip -q "$aab" -d "$tmp/license-bundle"
rm "$tmp/license-bundle/base/assets/licenses/healthmd-agpl-3.0.txt"
(cd "$tmp/license-bundle" && zip -qr "$tmp/no-app-license.aab" .)
if verify "$tmp/no-app-license.aab" >"$tmp/app-license-out" 2>"$tmp/app-license-error"; then
  echo 'packaged Wear bundle without the Health.md AGPL unexpectedly passed' >&2
  exit 1
fi
grep -q 'Health.md AGPL license missing from independent Wear bundle' "$tmp/app-license-error"

rm -rf "$tmp/license-bundle" "$tmp/truncated-app-license.aab"
unzip -q "$aab" -d "$tmp/license-bundle"
printf 'GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3, 19 November 2007\n' \
  >"$tmp/license-bundle/base/assets/licenses/healthmd-agpl-3.0.txt"
(cd "$tmp/license-bundle" && zip -qr "$tmp/truncated-app-license.aab" .)
if verify "$tmp/truncated-app-license.aab" >"$tmp/truncated-license-out" 2>"$tmp/truncated-license-error"; then
  echo 'packaged Wear bundle with a truncated Health.md AGPL unexpectedly passed' >&2
  exit 1
fi
grep -q 'bundled Health.md AGPL text differs from the complete governing license' \
  "$tmp/truncated-license-error"

if [[ -n "$phone_aab" ]]; then
  phone_gradle=app/build.gradle.kts
  phone_package=$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$phone_gradle" | head -1)
  phone_code=$(sed -n 's/.*versionCode = \([0-9_]*\).*/\1/p' "$phone_gradle" | head -1 | tr -d _)
  phone_name=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' "$phone_gradle" | head -1)
  phone_min=$(sed -n 's/.*minSdk = \([0-9_]*\).*/\1/p' "$phone_gradle" | head -1 | tr -d _)
  phone_target=$(sed -n 's/.*targetSdk = \([0-9_]*\).*/\1/p' "$phone_gradle" | head -1 | tr -d _)
  for value in "$phone_package" "$phone_code" "$phone_name" "$phone_min" "$phone_target"; do
    [[ -n "$value" ]] || { echo 'expected phone identity unavailable' >&2; exit 1; }
  done
  verify_phone() {
    java -cp "$tmp/classes:$proto:$protobuf" WearBundleManifestVerifier phone \
      "$1" "$phone_package" "$phone_code" "$phone_name" "$phone_min" "$phone_target"
  }
  verify_phone "$phone_aab"
  phone_negative() {
    local old=$1 new=$2 expected=$3 name=$4 target=${5:-base/manifest/AndroidManifest.xml}
    rm -rf "$tmp/phone-bundle" "$tmp/bad-phone.aab"
    unzip -q "$phone_aab" -d "$tmp/phone-bundle"
    python3 - "$tmp/phone-bundle/$target" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
data = open(path, 'rb').read()
assert old in data, old
assert len(old) == len(new), (old, new)
open(path, 'wb').write(data.replace(old, new, 1))
PY
    (cd "$tmp/phone-bundle" && zip -qr "$tmp/bad-phone.aab" .)
    if verify_phone "$tmp/bad-phone.aab" >"$tmp/phone-out" 2>"$tmp/phone-error"; then
      echo "negative packaged phone-manifest fixture unexpectedly passed: $name" >&2
      exit 1
    fi
    grep -q "$expected" "$tmp/phone-error"
  }
  phone_negative "$phone_package" "$(different_same_length "$phone_package")" 'wrong package' phone-package
  phone_negative "$phone_code" "$(different_same_length "$phone_code")" 'wrong packaged versionCode' phone-version-code
  phone_negative "$phone_name" "$(different_same_length "$phone_name")" 'wrong packaged versionName' phone-version-name
  phone_negative healthmd_phone_sync healthmd_phone_synb 'compiled static capability set differs' phone-capability base/resources.pb
  phone_negative CAPABILITY_CHANGED CAPABILITY_CHANGEE 'phone capability-change listener missing or path-restricted' phone-capability-change
  structural_negative "$phone_aab" verify_phone manifest extra-filter com.healthmd.wear.WearPhoneDataLayerService 'phone Data Layer intent-filter inventory differs' phone-extra-filter
  structural_negative "$phone_aab" verify_phone manifest combine-actions com.healthmd.wear.WearPhoneDataLayerService 'phone message listener missing or mis-scoped' phone-combined-actions
  structural_negative "$phone_aab" verify_phone manifest duplicate-service com.healthmd.wear.WearPhoneDataLayerService 'phone Data Layer listener inventory differs' phone-duplicate-listener
  structural_negative "$phone_aab" verify_phone manifest duplicate-other-service com.healthmd.wear.WearPhoneDataLayerService 'unexpected phone Data Layer listener service' phone-extra-listener
fi

echo 'Paired packaged-manifest verifier positive and negative checks passed'
