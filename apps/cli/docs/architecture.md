# Architecture

## Product boundary

This repository owns the portable terminal client. The Health.md app repository owns HealthKit,
iPhone export generation, the foreground direct service, and the optional Mac companion.

The boundary between them is a versioned, language-neutral direct protocol. Swift and Rust must
both pass the same fixtures before either side advertises a protocol version.

## Supported platform matrix

| Capability | macOS | Linux | Windows |
|---|---:|---:|---:|
| Manual IP / Tailscale direct backend | Yes | Yes | Yes |
| Pair, status, raw export, extract, resume, cancel | Yes | Yes | Yes |
| Generated-file destination commits (protocol v1) | Yes | Yes | No |
| Nearby (MultipeerConnectivity) | Swift legacy only | No | No |
| Mac-app loopback backend | Reserved, not implemented | No | No |
| Direct HealthKit reads | No | No | No |

An iPhone running Health.md is always required for fresh Apple Health data.

## Crates

### `healthmd-protocol`

Pure models and deterministic transformations: explicit JSON envelopes, date/UUID encoding,
capability negotiation, handshake transcripts, authenticated encryption, request fingerprints,
partition hashes, and shared conformance vectors. It performs no networking, storage, or logging.

### `healthmd-client`

Platform-facing implementation: TCP listener, secure channel, OS credential storage, durable job
journal, disk-backed transfer receiver, strict raw validation, and safe destination commits.
Transport selection is explicit and never falls back.

### `healthmd-cli`

Argument grammar, validation, JSON results/errors, stderr progress, and exit status. The direct
backend is the portable default. A future optional Mac-app adapter may use the existing loopback
HTTP API on macOS; it must remain an explicit backend and may not become a fallback. This crate does
not contain protocol or filesystem-security logic.

## Compatibility policy

Protocol changes are additive within a version only when old decoders can safely ignore them.
Unknown enum discriminators, cryptographic transcript changes, canonicalization changes, or frame
changes require a new negotiated protocol version. Release notes publish the minimum compatible
iPhone app version.

Swift synthesized `Codable` layout is not the specification. Explicit schemas, normative byte
layouts, and test vectors are.
