#!/usr/bin/env bash
set -euo pipefail

android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
test -n "$android_sdk"
package='system-images;android-35;google_apis;x86_64'
image="$android_sdk/system-images/android-35/google_apis/x86_64"
install_log=$(mktemp)
trap 'rm -f "$install_log"' EXIT

valid_image() {
  grep -Eq '^AndroidVersion\.ApiLevel[[:space:]]*=[[:space:]]*35[[:space:]]*$' "$image/source.properties" &&
    grep -Eq '^SystemImage\.Abi[[:space:]]*=[[:space:]]*x86_64[[:space:]]*$' "$image/source.properties" &&
    grep -Eq '^SystemImage\.TagId[[:space:]]*=[[:space:]]*google_apis[[:space:]]*$' "$image/source.properties" &&
    test -s "$image/system.img" && test -s "$image/ramdisk.img" &&
    { test -s "$image/kernel-ranchu" || test -s "$image/kernel-ranchu-64"; }
}

# Keep installation ahead of the emulator action so a truncated SDK archive
# does not discard an otherwise prepared worker. Never retry test failures,
# other installer errors, or delete sdkmanager's shared staging state.
for attempt in 1 2; do
  set +e
  sdkmanager --install "$package" 2>&1 | tee "$install_log"
  statuses=("${PIPESTATUS[@]}")
  set -e
  if [[ "${statuses[1]}" != 0 ]]; then exit "${statuses[1]}"; fi
  corrupt=false
  if grep -Fq 'Error on ZipFile unknown archive' "$install_log"; then corrupt=true; fi
  if [[ "${statuses[0]}" == 0 && "$corrupt" == false ]] && valid_image; then
    echo 'Verified API 35 Google APIs x86_64 system image.'
    exit 0
  fi
  if [[ "$attempt" == 1 && "$corrupt" == true ]]; then
    echo 'Retrying the API 35 system image once after a corrupt download archive.' >&2
    continue
  fi
  status="${statuses[0]}"
  if [[ "$status" == 0 ]]; then status=1; fi
  echo 'System image installation or verification failed.' >&2
  exit "$status"
done
