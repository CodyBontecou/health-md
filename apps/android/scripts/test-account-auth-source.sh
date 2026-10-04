#!/bin/bash
# Invoke VIA BASH through the unchanged, coordinator-approved heavy-slot guard.
# Standalone JVM evidence only: no Gradle, Android/core preparation, downloads or cache writes.
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd -P)
cache=${GRADLE_USER_HOME:-"$HOME/.gradle"}/caches/modules-2/files-2.1
jar() {
  local result
  result=$(find "$cache/$1/$2/$3" -maxdepth 2 -type f -name "$2-$3.jar" -print -quit)
  if [ -z "$result" ]; then printf 'Missing admitted read-only cached jar: %s/%s/%s\n' "$1" "$2" "$3" >&2; exit 69; fi
  printf '%s' "$result"
}
compiler=$(jar org.jetbrains.kotlin kotlin-compiler-embeddable 2.1.0)
stdlib=$(jar org.jetbrains.kotlin kotlin-stdlib 2.1.0)
reflect=$(jar org.jetbrains.kotlin kotlin-reflect 2.1.0)
script=$(jar org.jetbrains.kotlin kotlin-script-runtime 2.1.0)
daemon=$(jar org.jetbrains.kotlin kotlin-daemon-embeddable 2.1.0)
trove=$(jar org.jetbrains.intellij.deps trove4j 1.0.20200330)
coroutines=$(jar org.jetbrains.kotlinx kotlinx-coroutines-core-jvm 1.6.4)
annotations=$(jar org.jetbrains annotations 13.0)
junit=$(jar junit junit 4.13.2)
json=$(jar org.jetbrains.kotlinx kotlinx-serialization-json-jvm 1.7.3)
core=$(jar org.jetbrains.kotlinx kotlinx-serialization-core-jvm 1.7.3)
compiler_cp="$compiler:$stdlib:$reflect:$script:$daemon:$trove:$coroutines:$annotations"
target_cp="$stdlib:$annotations:$junit:$json:$core"
mkdir -p "$root/apps/android/build/account-auth-source"
out=$(mktemp -d "$root/apps/android/build/account-auth-source/run.XXXXXX")
printf 'Source HEAD=%s\nOutput=%s\nCompiler CP=%s\nTarget/harness CP=%s\n' "$(git -C "$root" rev-parse HEAD)" "$out" "$compiler_cp" "$target_cp"
java -version 2>&1
java -Xmx768m -Djava.io.tmpdir="$out" -cp "$compiler_cp" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -version
sources=()
while IFS= read -r path; do sources+=("$path"); done < <(find \
  "$root/apps/android/app/src/main/java/com/healthmd/accountauth" \
  "$root/apps/android/app/src/test/java/com/healthmd/accountauth" -type f -name '*.kt' | sort)
shasum -a 256 "${sources[@]}" "$root/apps/android/scripts/test-account-auth-source.sh"
java -Xmx768m -Djava.io.tmpdir="$out" -cp "$compiler_cp" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
  -no-stdlib -no-reflect -jvm-target 17 -Werror -classpath "$target_cp" \
  "${sources[@]}" -d "$out/account-auth-source.jar"
java -Xmx256m -Djava.io.tmpdir="$out" -cp "$out/account-auth-source.jar:$target_cp" com.healthmd.accountauth.AccountAuthSourceHarnessKt "$root"
printf 'Retained source output: %s\n' "$out"
