#!/bin/bash
# Temporary synthetic JVM diagnosis only; preserve failure and the established 1800s bound.
set -euo pipefail
repo_root="$PWD"
cd apps/android
mkdir -p build/reports/pr189-jvm-diagnostic
out=build/reports/pr189-jvm-diagnostic
{
  git rev-parse HEAD
  java -version 2>&1
  lscpu
  cat /proc/meminfo
} > "$out/provenance.txt"
python3 "$repo_root/.github/scripts/pr189-jvm-sample.py" "$out" &
sampler_pid=$!
cleanup() {
  kill "$sampler_pid" 2>/dev/null || true
  wait "$sampler_pid" 2>/dev/null || true
}
trap cleanup EXIT
if timeout --signal=TERM --kill-after=30s 1800s \
  ./scripts/run-ci-gradle.sh --no-daemon --max-workers=2 \
  --init-script "$repo_root/.github/scripts/pr189-jvm-trace.init.gradle" \
  :app:testPlayReleaseUnitTest --stacktrace 2>&1 | tee "$out/gradle.log"; then
  status=0
else
  status=$?
fi
echo "diagnostic_exit=$status" | tee "$out/outcome.txt"
exit "$status"
