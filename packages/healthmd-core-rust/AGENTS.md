# Health.md Shared Rust Core Agent Instructions

## Ownership boundary

This workspace owns deterministic post-capture semantics and the transport-independent direct protocol. It does not own HealthKit, Health Connect, provider APIs, UI, app lifecycle, credentials, destination access, networking, or platform persistence.

- `healthmd-core` must remain synchronous, deterministic, platform-neutral, and free of filesystem/network/environment/logging behavior.
- `healthmd-protocol` contains pure direct-protocol models, encoding, crypto, fingerprints, and transfer frames. Wire changes require the cross-platform protocol workflow in the root `AGENTS.md`.
- `healthmd-core-uniffi` is a thin mobile boundary. Do not put business logic in generated bindings or the bridge crate.
- `xtask` and `scripts` own reproducible generation and packaging.

## Public contracts and cross-platform unification

Apple v8, Android frozen v4, Android analytical v5, and direct protocol v1/v2 are independent shipped contracts. Moving code into this workspace is not permission to alter bytes, schemas, units, meanings, profiles, canonicalization, crypto transcripts, or frames.

The shared core should implement common Apple/Android semantics whenever equivalence is proven, following `docs/architecture/cross-platform-unification-policy.md`. Shared code is not evidence of semantic equivalence: OS-specific and related-but-distinct data keeps explicit profiles, platform extensions, or distinct semantic IDs.

Before changing export or protocol behavior:

1. Read `docs/architecture/cross-platform-unification-policy.md`, `apps/apple/docs/features/export-schema.md`, the Android contract docs, and the relevant `packages/contracts` specification.
2. Identify all Apple, Android, CLI, website, and external Obsidian consumers.
3. Classify mappings using the registry's exact equivalence values and decide whether a common schema, platform profile/extension, or protocol version changes.
4. Preserve historical fixtures; never regenerate them merely to silence a test.
5. Run every affected language's contract and differential tests.

## Safety and FFI

- Keep `#![forbid(unsafe_code)]` in pure crates. Isolate generated or unavoidable FFI unsafe code in `healthmd-core-uniffi`.
- Expose coarse, versioned, owned request/result APIs. Never make one FFI call per health sample.
- Every native-facing failure uses a stable health-free code/message. Do not include values, paths, identities, credentials, payloads, or parser details.
- Panics must not cross the FFI boundary.
- No runtime downloads or unpinned code generation.
- Generated Swift/Kotlin source is never edited by hand. Compiled native binaries are build artifacts, not source.

## Required checks

```bash
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check -p healthmd-core -p healthmd-protocol -p healthmd-core-uniffi --all-features --locked
python3 ../contracts/validate.py
```

For protocol changes, additionally run the Swift v1 and Kotlin v2 vector tests and confirm canonical fixtures remain byte-identical to their package mirrors.
