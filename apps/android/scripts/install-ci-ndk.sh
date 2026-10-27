#!/usr/bin/env bash
set -euo pipefail

android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
test -n "$android_sdk"
test -n "${GITHUB_ENV:-}"
ndk_revision=27.1.12297006
install_log=$(mktemp)
trap 'rm -f "$install_log"' EXIT

# A truncated repository download has failed before any Gradle task can run.
# Retry that specific installer failure once, never test failures or arbitrary
# SDK errors. sdkmanager owns its staging paths; do not delete shared SDK state.
for attempt in 1 2; do
  set +e
  sdkmanager "ndk;$ndk_revision" 2>&1 | tee "$install_log"
  statuses=("${PIPESTATUS[@]}")
  set -e
  if [[ "${statuses[1]}" != 0 ]]; then
    exit "${statuses[1]}"
  fi
  if [[ "${statuses[0]}" == 0 ]]; then
    break
  fi
  if [[ "$attempt" == 2 ]] || ! grep -Fq 'Error on ZipFile unknown archive' "$install_log"; then
    exit "${statuses[0]}"
  fi
  echo 'Retrying pinned NDK installation once after a corrupt download archive.' >&2
done

grep -Eq '^Pkg\.Revision[[:space:]]*=[[:space:]]*27\.1\.12297006[[:space:]]*$' \
  "$android_sdk/ndk/$ndk_revision/source.properties"
echo "ANDROID_NDK_HOME=$android_sdk/ndk/$ndk_revision" >> "$GITHUB_ENV"
echo "ANDROID_NDK_ROOT=$android_sdk/ndk/$ndk_revision" >> "$GITHUB_ENV"
