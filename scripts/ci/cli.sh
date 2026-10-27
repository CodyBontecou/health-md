#!/usr/bin/env bash
set -euo pipefail
# Two workers alongside the core group's two fit the hosted runner's four CPUs.
# Share the limit with the catalog generator's Cargo invocation as well.
export CARGO_BUILD_JOBS=2 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
cd apps/cli
cargo test --locked -p healthmd-operations
# Reuse this same profile/target instead of recompiling the generator in another group.
python3 scripts/update-mcp-shared-assets.py --check
