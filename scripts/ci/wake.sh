#!/usr/bin/env bash
set -euo pipefail
cd apps/wake
npm ci --ignore-scripts --no-audit --no-fund
npm exec -- vitest run --maxWorkers=1
npm run check
