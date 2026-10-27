#!/usr/bin/env bash
set -euo pipefail
export HEALTHMD_OBSIDIAN_PLUGIN_REPO="$PWD/.external/health-md-visualizations"
# The only consumer build is its small parser test harness, compiled from the pinned source.
npm --prefix "$HEALTHMD_OBSIDIAN_PLUGIN_REPO" ci --ignore-scripts --no-audit --no-fund
bash scripts/ci/consumer.sh
cd apps/website
npm ci --ignore-scripts --no-audit --no-fund
node --test test/csv-combiner.test.mjs test/visualization-catalog.test.mjs test/health-connect-sample.test.mjs test/sleep-export-sample.test.mjs
