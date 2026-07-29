# HealthMdCoreRust

Local Swift package for the Apple side of the Health.md shared Rust core.

- `Sources/HealthMdCoreRust/Generated/HealthmdCore.swift`, `Bindings/HealthmdCoreFFI.h`, and `Bindings/HealthmdCoreFFI.modulemap` are committed, unedited UniFFI 0.32.0 snapshots.
- `HealthMdCoreService.swift` is the handwritten, health-free Swift boundary, including cancellation-capable semantic/render sessions, profile-exact Markdown merge, bounded planned lossless streams, and synchronous pure direct-protocol revision-1 helpers for exact v1/v2 fixtures, opaque transfer frames, negotiation, and reviewed stateless crypto.
- `Artifacts/HealthmdCore.xcframework` is a source-built static artifact and is intentionally ignored.
- The package is linked only by the iOS app, macOS app, and unit-test targets. M5 render sessions remain internal/test-shadow inputs and do not change public exporter authority or capability status.
- Direct helpers do not replace Apple networking, pairing/trust lifecycle, secure-channel sequence/seal/open state, sockets, or persistence. Returned session-key bytes are caller-owned and must be wiped promptly; stateful migration remains security-review gated.

Prepare the ignored artifact before resolving this package:

```sh
make -C apps/apple prepare-healthmd-core-rust
```

Update generated bindings only after an intentional reviewed UniFFI API change:

```sh
packages/healthmd-core-rust/scripts/generate-apple-bindings.sh --update
```

CI uses `--check` generation plus XCFramework slice, symbol, module-map, and no-dylib validation to detect drift.
