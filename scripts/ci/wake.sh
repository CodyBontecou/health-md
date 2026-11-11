#!/usr/bin/env bash
set -euo pipefail
# Independent components share only this process budget, never runtime resources.
(
  cd apps/wake
  npm ci --ignore-scripts --no-audit --no-fund
  npm exec -- vitest run --maxWorkers=1
  npm run check
)
bash scripts/ci/cloud.sh
