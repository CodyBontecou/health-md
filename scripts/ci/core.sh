#!/usr/bin/env bash
set -euo pipefail
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
# The Ubuntu runner already includes this toolchain. LLD avoids repeated slow
# GNU-linker work across the contract test binaries without reducing coverage.
if [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] \
    && command -v clang-18 >/dev/null && command -v ld.lld-18 >/dev/null; then
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=clang-18
    export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-fuse-ld=lld"
fi
cd packages/healthmd-core-rust
cargo test --locked -j 2 -p healthmd-core -p healthmd-protocol -- --quiet
