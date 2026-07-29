# Shared Rust core M7 direct-protocol baseline

Status: deterministic protocol authority implemented; production defaults remain legacy and physical-device acceptance remains pending

Date: 2026-07-26

This baseline records Milestone 7 implementation without changing Apple application protocol v1, Android application protocol v2, shared transport framing v1, pairing selectors, public export schemas, ports, limits, or durable-job lifetimes. The language-neutral specifications and immutable interoperability vectors remain under [`packages/contracts/direct-protocol`](../../packages/contracts/direct-protocol/README.md).

## Authority boundary

`packages/healthmd-core-rust/crates/healthmd-protocol` is the transport-independent Rust authority. The CLI links the crate directly. Mobile apps use coarse synchronous UniFFI functions from `healthmd-core-uniffi`; they do not link the CLI or move platform services into Rust.

Protocol API revision 1 covers:

- deployed constants and compatibility metadata;
- strict Apple-v1 request fingerprints and complete control-message canonicalization;
- strict Android-v2 request fingerprints and complete envelope canonicalization, including Kotlin-default empty collections;
- exact `HMDDIRCT` binary transfer-frame encoding, decoding, and validation;
- transfer capability validation and negotiation;
- reviewed stateless pairing transcript, HMAC verifier, and session-key calculations.

The APIs are bounded, synchronous, panic-contained, and use stable health-free errors. The shared core does not parse health payload contents or retain production message bytes.

## Native responsibilities retained

Apple retains `NWConnection`, Multipeer Connectivity, Keychain trust, installation identity, pairing UI, AEAD objects, sequence/replay state, protected-data policy, background lifecycle, job spools, file reads/writes, and transfer side effects.

Android retains sockets and services, Keystore/trust state, installation identity, AEAD objects, sequence/replay state, WorkManager/lifecycle, no-backup journals, file reads/writes, and transfer side effects.

The CLI retains desktop networking, local storage, destination commits, command behavior, and direct Rust-crate consumption.

No socket, credential store, platform lifecycle, persistence, or health API moved behind UniFFI.

## Mobile authority adapters

Apple integrates `AppleDirectProtocolAuthority` behind the existing secure-channel canonicalization hook, manual-IP/nearby clients, direct CLI service, request producers, and transfer encoding. Android integrates `AndroidDirectProtocolAuthority` behind `DirectClient`, `DirectSecureChannel`, `ArtifactTransferClient`, and `DirectCliCoordinator`.

Both adapters support:

- `legacy`: native deterministic results are authoritative and Rust is not required;
- `shadow`: native results remain authoritative while health-free per-stage comparison/mismatch counts are recorded;
- `rust`: Rust results are authoritative and failures do not fall back to native results.

No raw messages, identifiers, paths, secrets, health values, or byte offsets are stored in comparison evidence.

Apple defaults to `legacy`. Internal builds may select `shadow` or `rust` with exactly one compile condition (`HEALTHMD_APPLE_DIRECT_PROTOCOL_SHADOW` or `HEALTHMD_APPLE_DIRECT_PROTOCOL_RUST`) or the `HEALTHMD_DIRECT_PROTOCOL_ENGINE` process environment value. Conflicting compile conditions fail compilation; unknown environment values do not select a nonlegacy mode.

Android defaults to `legacy`. Gradle property or environment variable `DIRECT_PROTOCOL_ENGINE` accepts only `legacy`, `shadow`, or `rust`; every other value is normalized to `legacy` in `BuildConfig`.

## Durable operation pins

A new nonlegacy direct operation captures a version-1 protocol pin containing the engine, core API version, protocol API revision, platform application version, transfer version, crate version, and source-revision provenance. Compatibility is controlled by versioned API values; source revision is diagnostic and is not an exact-equality gate.

Apple generated-file journals and raw-export journals use version 3 for protocol pins. Android direct-job journals use version 3. Version 1 and version 2 jobs decode as legacy protocol work even if unexpected newer fields are present. A persisted nonlegacy pin takes precedence over current defaults. An incompatible nonlegacy pin fails before operation work resumes; it is never silently executed as legacy.

Bootstrap status and pre-journal connection traffic intentionally run as legacy. The operation pin becomes active before request fingerprinting/corpus production and remains operation-wide through transfer finalization or failure.

## Secure-channel security gate

Stateful `HMDSC001` sequence allocation, replay-window authority, seal/open, nonce lifecycle, trusted reconnect state, trust rotation, and production secret custody remain native. Rust contains reviewed direct-crate primitives used by the CLI and stateless conformance tests, but those secret-bearing operations are not exported over UniFFI.

Generated UniFFI transport buffers cannot guarantee end-to-end zeroization. A dedicated security review is required before any mobile production secret is permitted to cross that boundary. Native channels now fail closed on sequence exhaustion, and malformed/replayed frames continue to be rejected by native state machines.

## Compatibility evidence

The immutable public vectors remain unchanged:

- Apple v1 fixture SHA-256: `372655a8a415b5256b86ef628f551515bc66440eae8412d28be0dd7dfbe0f4a1`;
- Android v2 fixture SHA-256: `a35b85e63f16d8f4beb46e02590ab52aac556e121c35f2219fac239f6e0ecf9b`.

Rust, Swift, and Kotlin verify exact canonical bytes, fingerprints, frames, pairing calculations, malformed/default/null/range cases, negotiation, sequence exhaustion, interruption, and resume behavior. Binding snapshots are regenerated from pinned UniFFI 0.32.0 and drift-checked. Apple XCFramework slices and Android ABI libraries continue to expose the same shared-core checksum.

Validated locally on 2026-07-26:

- shared-core formatting, full workspace tests, strict Clippy, Rust 1.85 runtime-crate MSRV checks, Rust 1.88 tooling checks, crate packaging, and deterministic Swift/Kotlin binding checks;
- CLI formatting, locked workspace tests, packaging metadata, direct consumption of the shared protocol crate, and bounded offline help/version/device/unsupported-backend smoke checks;
- contract validation with unchanged direct fixture hashes and mirrors;
- Swift package protocol-foundation and connectivity tests;
- Apple authority/pin migration tests and iOS Simulator application build/tests;
- Android direct-protocol interoperability, authority, journal migration, shared-core unit/instrumentation tests, app unit tests, debug build, and API-35 emulator instrumentation.

## Remaining acceptance gates

Milestone 7 is not operationally complete until old-CLI/new-mobile and new-CLI/old-mobile physical LAN/Tailscale pair, status, export, resume, and cancel matrices pass for both iPhone and Android. Release authority remains legacy until that evidence and the Milestone 6 rollout approvals exist.

Stateful secure-channel migration remains deferred behind the security-review gate. This is an intentional native boundary, not permission to weaken replay, sequence, nonce, trust, or key-custody behavior.
