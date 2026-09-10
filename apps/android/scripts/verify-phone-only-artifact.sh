#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
aab=${1:-app/build/outputs/bundle/playRelease/app-play-release.aab}
[[ -f "$aab" ]] || { echo "Phone AAB unavailable: $aab" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
proto=$(find "$HOME/.gradle/caches/modules-2/files-2.1/com.android.tools.build/aapt2-proto" \
  -name 'aapt2-proto-*.jar' -print | sort -V | tail -1)
protobuf=$(find "$HOME/.gradle/caches/modules-2/files-2.1/com.google.protobuf/protobuf-java" \
  -name 'protobuf-java-*.jar' -print | sort -V | tail -1)
[[ -f "$proto" && -f "$protobuf" ]] || { echo 'protobuf dependencies unavailable' >&2; exit 1; }
javac -cp "$proto:$protobuf" -d "$tmp/classes" scripts/WearBundleManifestVerifier.java

build=app/build.gradle.kts
package=$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$build" | head -1)
code=$(sed -n 's/.*versionCode = \([0-9_]*\).*/\1/p' "$build" | head -1 | tr -d _)
name=$(sed -n 's/.*versionName = "\([^"]*\)".*/\1/p' "$build" | head -1)
min=$(sed -n 's/.*minSdk = \([0-9_]*\).*/\1/p' "$build" | head -1 | tr -d _)
target=$(sed -n 's/.*targetSdk = \([0-9_]*\).*/\1/p' "$build" | head -1 | tr -d _)
for value in "$package" "$code" "$name" "$min" "$target"; do
  [[ -n "$value" ]] || { echo 'Expected phone identity unavailable' >&2; exit 1; }
done

java -cp "$tmp/classes:$proto:$protobuf" WearBundleManifestVerifier phone-deferred \
  "$aab" "$package" "$code" "$name" "$min" "$target"
