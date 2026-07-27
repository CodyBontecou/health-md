# Architecture

## Product boundary

`apps/cli` owns the portable terminal client. The Apple and Android components own HealthKit/Health Connect/provider reads, source-platform capture, foreground direct services, and the optional Mac companion. Shared Rust protocol and post-capture export code lives in `packages/healthmd-core-rust`.

The boundary is a versioned, language-neutral direct protocol. Swift, Kotlin, and Rust must pass the
applicable shared fixtures before advertising a protocol version.

## Supported platform matrix

| Capability | macOS | Linux | Windows |
|---|---:|---:|---:|
| Manual IP / Tailscale direct backend | Yes | Yes | Yes |
| iOS pair, status, raw, extract, resume, cancel | Yes | Yes | Yes |
| Android pair, status, raw, generated files, resume, cancel | Yes | Yes | Yes |
| iOS generated-file destination commits (protocol v1) | Yes | Yes | No |
| Nearby (MultipeerConnectivity) | Swift legacy only | No | No |
| Mac-app loopback backend | Reserved, not implemented | No | No |
| Direct HealthKit/Health Connect reads | No | No | No |

A mobile device running Health.md is always required for fresh source health data.

## Rust workspace boundaries

The shared-core workspace at `packages/healthmd-core-rust` and CLI workspace at `apps/cli` keep independent manifests, lockfiles, and target directories. The CLI uses the shared protocol crate by path in the repository; Cargo packaging replaces that path hint with its exact crates.io version requirement.

### `healthmd-protocol` (shared-core workspace)

Pure models and deterministic transformations: explicit JSON envelopes, date/UUID encoding, capability negotiation, handshake transcripts, authenticated encryption, request fingerprints, partition hashes, and shared conformance vectors. It performs no networking, storage, or logging. Its source is under `packages/healthmd-core-rust/crates/healthmd-protocol`. The CLI consumes that Rust implementation directly. Apple and Android retain native networking, trust, lifecycle, AEAD state, and persistence while packaged UniFFI adapters can make the same crate authoritative for stateless deterministic protocol behavior.

### Shared export core (shared-core workspace)

Post-capture DTO validation, profile-specific projection, deterministic serialization, and the coarse-grained UniFFI boundary live in the shared-core workspace. Its independently versioned protocol API also validates and canonicalizes existing direct-protocol messages without changing their wire versions. Native products still own platform capture, networking, secret custody, persistence, and destination writes. No shared-core migration implies a public export-schema change.

### `healthmd-client` (CLI workspace)

Platform-facing implementation: TCP listener, secure channel, OS credential storage, separate v1
and v2 durable jobs, product-aware disk-backed receivers, raw validation, and safe destination
commits. Transport and product selection are explicit and never fall back.

### `healthmd-cli` (CLI workspace)

Argument grammar, validation, JSON results/errors, stderr progress, and exit status. The direct
backend is the portable default. A future optional Mac-app adapter may use the existing loopback
HTTP API on macOS; it must remain an explicit backend and may not become a fallback. This crate does
not contain protocol or filesystem-security logic.

## Compatibility policy

Protocol changes are additive within a version only when old decoders can safely ignore them.
Unknown enum discriminators, cryptographic transcript changes, canonicalization changes, or frame
changes require a new negotiated application or transport version. Release notes publish minimum
compatible iOS and Android app versions. Application v2 reuses the deployed v1 pairing, encrypted
transport, and binary frames while using explicit Android control envelopes.

Swift synthesized `Codable` layout is not the specification. Explicit schemas, normative byte
layouts, and test vectors are.
