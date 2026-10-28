#!/usr/bin/env bash
set -euo pipefail
cd apps/practice
npm ci --ignore-scripts --no-audit --no-fund
npm run typecheck
npm exec -- vitest run --maxWorkers=1
npm run build
npm run check:synthetic
npm run check:scanner-canary
npm run check:security
