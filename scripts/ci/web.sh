#!/usr/bin/env bash
# Dependencies and Chromium are installed by CI before this regression lane.
# Each component retains its own lockfile, build and runtime boundary.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
bash scripts/ci/consumer.sh
export HEALTHMD_OBSIDIAN_PLUGIN_REPO="$repo_root/.external/health-md-visualizations"
(
    cd apps/practice
    npm run check:ci
)
python3 docs/product/practice/fixtures/generate_synthetic_ingest_pdf.py --check
(
    cd apps/wake
    npm test
    npm run check
    npm exec -- wrangler deploy --dry-run --outdir .wrangler/ci-dry-run
)
(
    cd apps/website
    npm test
    npm run build:ci
    npm run docs:check-built
)
