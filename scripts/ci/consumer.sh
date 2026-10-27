#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export HEALTHMD_OBSIDIAN_PLUGIN_REPO="$repo_root/.external/health-md-visualizations"
revision=$(node -p "require('./apps/website/external-sources.json').obsidian_plugin.revision")
[[ "$(git -C "$HEALTHMD_OBSIDIAN_PLUGIN_REPO" rev-parse HEAD)" == "$revision" ]]
# Fail if a warm checkout contains modified consumer code or fixtures.
[[ -z "$(git -C "$HEALTHMD_OBSIDIAN_PLUGIN_REPO" status --porcelain --untracked-files=no)" ]]
npm --prefix "$HEALTHMD_OBSIDIAN_PLUGIN_REPO" test
