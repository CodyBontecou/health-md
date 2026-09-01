#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fdroid=${FDROID_BIN:-fdroid}
fdroiddata_commit=59141b3e3cce28d11481c57e5be5f4f8166d027f
command -v "$fdroid" >/dev/null 2>&1 || [[ -x "$fdroid" ]] || {
  echo "fdroidserver 2.4.5 is required (set FDROID_BIN)" >&2
  exit 1
}

recipe=fdroid/com.healthmd.android.yml
grep -Fq 'License: AGPL-3.0-only' "$recipe"
grep -Fq 'subdir: apps/android' "$recipe"
grep -Fq 'ndk: r27b' "$recipe"
grep -Fq 'rustup@1.28.2' "$recipe"
grep -Fq 'default-toolchain 1.88.0' "$recipe"
grep -Fq 'cargo install cargo-ndk --version 4.1.2 --locked' "$recipe"
grep -Fq 'gradle:' "$recipe"
grep -Fq '      - fdroid' "$recipe"
grep -Fq 'output: app/build/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk' "$recipe"
grep -Fq 'UpdateCheckMode: Tags ^android/v' "$recipe"
for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android; do
  grep -Fq "$target" "$recipe"
done
for locale in en-US de-DE; do
  test -s "fdroid/metadata/$locale/title.txt"
  test -s "fdroid/metadata/$locale/short_description.txt"
  test -s "fdroid/metadata/$locale/full_description.txt"
done
find fdroid/metadata/en-US/images/phoneScreenshots -type f -name '*.png' | grep -q .

work=$(mktemp -d "${TMPDIR:-/tmp}/healthmd-fdroid-metadata.XXXXXX")
trap 'rm -rf "$work"' EXIT
config_source=${FDROIDDATA_CONFIG_DIR:-}
if [[ -z "$config_source" ]]; then
  git -C "$work" init --quiet fdroiddata
  git -C "$work/fdroiddata" remote add origin https://gitlab.com/fdroid/fdroiddata.git
  git -C "$work/fdroiddata" fetch --quiet --depth=1 --filter=blob:none origin "$fdroiddata_commit"
  git -C "$work/fdroiddata" sparse-checkout init --cone
  git -C "$work/fdroiddata" sparse-checkout set config
  git -C "$work/fdroiddata" checkout --quiet FETCH_HEAD
  config_source="$work/fdroiddata/config"
fi
test -f "$config_source/categories.yml"
test -f "$config_source/antiFeatures.yml"

repo="$work/repo"
mkdir -p "$repo"
(
  cd "$repo"
  ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}} "$fdroid" init --keystore NONE >/dev/null
  chmod 600 config.yml
  cp -R "$config_source" ./config
  mkdir -p metadata/com.healthmd.android
  cp "$OLDPWD/$recipe" metadata/com.healthmd.android.yml
  cp -R "$OLDPWD/fdroid/metadata/." metadata/com.healthmd.android/
  ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}} "$fdroid" readmeta
  ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}} "$fdroid" lint com.healthmd.android
)

echo "Validated F-Droid metadata with fdroidserver and fdroiddata $fdroiddata_commit"
