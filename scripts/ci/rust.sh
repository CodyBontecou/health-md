#!/usr/bin/env bash
# One toolchain and OS, fresh tests, independent component target directories.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
python3 packages/contracts/validate.py
python3 packages/healthmd-core-rust/scripts/import-native-registry.py --check
python3 packages/healthmd-core-rust/scripts/generate-registry-adapters.py --check
(
    cd packages/healthmd-core-rust
    cargo fmt --all --check
    cargo test --workspace --all-features --locked
)
(
    cd apps/cli
    cargo fmt --all --check
    cargo test --workspace --all-features --locked
    python3 scripts/update-mcp-shared-assets.py --check
)
