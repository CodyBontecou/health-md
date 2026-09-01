#!/usr/bin/env bash
set -euo pipefail

android_root=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(git -C "$android_root" rev-parse --show-toplevel)
repo_url=${FDROID_REPOSITORY_URL:-$repo_root}
source_ref=${FDROID_SOURCE_REF:-$(git -C "$repo_root" rev-parse HEAD)}
output_dir=${FDROID_REPRO_OUTPUT_DIR:-$android_root/app/build/reports/fdroid-reproducibility}
sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}

if [[ -z "$sdk_root" && -f "$android_root/local.properties" ]]; then
  sdk_root=$(sed -n 's/^sdk\.dir=//p' "$android_root/local.properties" | head -1 | sed 's/\\:/:/g; s/\\\\/\\/g')
fi
[[ -d "$sdk_root" ]] || { echo 'Android SDK is required' >&2; exit 1; }
[[ -d "$sdk_root/ndk/27.1.12297006" ]] || {
  echo 'Android NDK 27.1.12297006 is required' >&2
  exit 1
}
command -v rustup >/dev/null
command -v cargo-ndk >/dev/null
rustup run 1.88.0 rustc --version | grep -Fq 'rustc 1.88.0'
cargo ndk --version | grep -Fq 'cargo-ndk 4.1.2'

work=$(mktemp -d "${TMPDIR:-/tmp}/healthmd-fdroid-repro.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$output_dir"
source_epoch=$(git -C "$repo_root" show -s --format=%ct "$source_ref")

for run in 1 2; do
  checkout="$work/source-$run"
  home="$work/home-$run"
  mkdir -p "$home"
  git clone --no-local --no-checkout "$repo_url" "$checkout"
  git -C "$checkout" checkout --detach "$source_ref"
  test ! -e "$checkout/apps/android/local.properties"

  (
    cd "$checkout/apps/android"
    HOME="$home" \
    GRADLE_USER_HOME="$home/.gradle" \
    CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" \
    RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" \
    ANDROID_SDK_ROOT="$sdk_root" \
    ANDROID_HOME="$sdk_root" \
    ANDROID_NDK_HOME="$sdk_root/ndk/27.1.12297006" \
    ANDROID_NDK_ROOT="$sdk_root/ndk/27.1.12297006" \
    SOURCE_DATE_EPOCH="$source_epoch" \
      ./gradlew --no-daemon --max-workers=2 :app:assembleFdroidRelease
    FDROID_SKIP_DEPENDENCY_REPORT=false \
    ANDROID_SDK_ROOT="$sdk_root" \
      ./scripts/verify-fdroid-artifact.sh
  )

  artifact="$checkout/apps/android/app/build/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk"
  cp "$artifact" "$output_dir/build-$run.apk"
  sha256sum "$artifact" >"$output_dir/build-$run.sha256"
done

first=$(sha256sum "$output_dir/build-1.apk" | awk '{print $1}')
second=$(sha256sum "$output_dir/build-2.apk" | awk '{print $1}')
printf 'source_ref=%s\nsource_date_epoch=%s\nbuild_1_sha256=%s\nbuild_2_sha256=%s\n' \
  "$source_ref" "$source_epoch" "$first" "$second" >"$output_dir/result.txt"

if [[ "$first" != "$second" ]]; then
  echo "F-Droid builds differ; evidence retained in $output_dir" >&2
  if command -v diffoscope >/dev/null; then
    diffoscope "$output_dir/build-1.apk" "$output_dir/build-2.apk" \
      >"$output_dir/diffoscope.txt" || true
  fi
  exit 1
fi

echo "Reproducible F-Droid APK: $first"
echo "Evidence: $output_dir"
