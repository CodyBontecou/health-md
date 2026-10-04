#!/bin/bash
# Invoke THROUGH an approved heavy admission guard. Cached jars read only: no Gradle/build/install/copies.
set -eu
root=$(cd "$(dirname "$0")/../../../.." && pwd)
out=${PROFILE_SYNC_BUILD_DIR:-"$root/packages/contracts/profile-sync/v1/.build/kotlin"}
cache=${GRADLE_USER_HOME:-"$HOME/.gradle"}/caches/modules-2/files-2.1
jar() {
  result=$(find "$cache/$1/$2/$3" -maxdepth 2 -name "$2-$3.jar" -print -quit)
  if [ -z "$result" ]; then printf 'Missing read-only cached jar: %s/%s/%s\n' "$1" "$2" "$3" >&2; exit 69; fi
  printf '%s' "$result"
}
compiler=$(jar org.jetbrains.kotlin kotlin-compiler-embeddable 2.1.0)
stdlib=$(jar org.jetbrains.kotlin kotlin-stdlib 2.1.0)
reflect=$(jar org.jetbrains.kotlin kotlin-reflect 2.1.0)
script=$(jar org.jetbrains.kotlin kotlin-script-runtime 2.1.0)
daemon=$(jar org.jetbrains.kotlin kotlin-daemon-embeddable 2.1.0)
plugin=$(jar org.jetbrains.kotlin kotlin-serialization-compiler-plugin-embeddable 2.1.0)
json=$(jar org.jetbrains.kotlinx kotlinx-serialization-json-jvm 1.7.3)
core=$(jar org.jetbrains.kotlinx kotlinx-serialization-core-jvm 1.7.3)
coroutines=$(jar org.jetbrains.kotlinx kotlinx-coroutines-core-jvm 1.6.4)
annotations=$(jar org.jetbrains annotations 13.0)
junit=$(jar junit junit 4.13.2)
cp="$stdlib:$json:$core:$annotations:$junit"
mkdir -p "$out"
java -Xmx768m -Djava.io.tmpdir="$out" -cp "$compiler:$stdlib:$reflect:$script:$daemon:$coroutines:$annotations" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
  -no-stdlib -no-reflect -jvm-target 17 -classpath "$cp" -Xplugin="$plugin" \
  "$root/apps/android/app/src/main/java/com/healthmd/sharedsetup/SharedSetupV2Models.kt" \
  "$root/apps/android/app/src/main/java/com/healthmd/sharedsetup/SharedSetupV2Codec.kt" \
  "$root/apps/android/app/src/main/java/com/healthmd/accountsync/ProfileSyncV1.kt" \
  "$root/apps/android/app/src/test/java/com/healthmd/accountsync/ProfileSyncV1Test.kt" \
  "$root/packages/contracts/profile-sync/v1/conformance/KotlinRegistryHost.kt" \
  "$root/packages/contracts/profile-sync/v1/conformance/KotlinMain.kt" \
  -d "$out/profile-sync-kotlin.jar"
java -Xmx256m -cp "$out/profile-sync-kotlin.jar:$cp" KotlinMainKt "$root"
