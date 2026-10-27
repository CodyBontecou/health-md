#!/usr/bin/env bash
set -euo pipefail
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
cd apps/cli
cargo test --locked -j 1 -p healthmd-operations
# Reuse this same profile/target instead of recompiling the generator in another group.
python3 scripts/update-mcp-shared-assets.py --check
