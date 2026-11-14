#!/usr/bin/env bash
set -euo pipefail
# Independent components share only this process budget, never runtime resources.
(
  cd apps/wake
  npm ci --ignore-scripts --no-audit --no-fund
  npm exec -- vitest run --maxWorkers=1
  npm run check
) &
wake_pid=$!
bash scripts/ci/cloud.sh &
cloud_pid=$!
# Both components remain blocking. Wait for both even when the first fails, so
# the lane never leaves an unobserved checker running or loses its verdict.
status=0
wait "$wake_pid" || status=$?
wait "$cloud_pid" || status=$?
exit "$status"
