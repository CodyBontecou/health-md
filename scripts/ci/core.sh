#!/usr/bin/env bash
set -euo pipefail
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
cd packages/healthmd-core-rust
cargo test --locked -j 2 -p healthmd-core -p healthmd-protocol
