#!/usr/bin/env bash
# All synthetic Cloud host regressions remain blocking inside the existing lane.
set -euo pipefail
cd apps/cloud
npm ci --ignore-scripts --no-audit --no-fund
npm run typecheck
npm run typecheck:vm
# No name/path filter: keep auth, persistence, encryption, tenant isolation,
# read/write authority, revocation, ambiguous commits and reconciliation coverage.
npm exec -- vitest run --maxWorkers=1
npm run verify:production-safety
npm audit --audit-level=moderate
