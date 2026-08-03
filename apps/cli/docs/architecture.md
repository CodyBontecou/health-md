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
| iOS generated-file destination commits (protocol v1) | Yes | Yes | Yes |
| Nearby (MultipeerConnectivity) | Swift legacy only | No | No |
| Mac-app loopback backend | Reserved, not implemented | No | No |
| Direct HealthKit/Health Connect reads | No | No | No |

A mobile device running Health.md is always required to acquire source health data. Local and
feature-enabled Streamable HTTP MCP queries contact a foreground iPhone; Health.md does not retain a
remote query corpus. Windows accepts existing local drive-root and UNC destinations, but rejects
verbatim/device namespaces, traversal,
reserved aliases, alternate data streams, symlinks, junctions, reparse points, and root replacement.

## Mobile protocol compatibility

| Mobile source | Protocol | Conservative source floor | Portable Rust behavior | Public status |
|---|---|---|---|---|
| Export-capable iPhone | selector 1 / v1 | iOS 3.0.3 at exact candidate SHA | Status, raw, extract, files, resume, cancel | Pending physical qualification |
| Query-capable iPhone | selector 1 / v1 + query v3 | iOS 3.0.3 at exact candidate SHA | V1 plus bounded MCP queries | Pending physical qualification |
| Android | selector 2 / v2 | Android 1.5.4 (25) at exact candidate SHA | Status, native raw, files, resume, cancel | Pending physical qualification |
| Android typed MCP query | N/A | Not implemented | Query tools require iPhone v3 | Unsupported |

No public CLI/mobile pair is qualified yet. V3 is additive to v1 pairing and transport, not a
pairing selector, transfer-frame version, Android protocol, or export protocol. The authoritative
[compatibility ledger](mobile-compatibility.md) and per-release evidence record exact mobile builds.

## Portable MCP contract

The publishable `healthmd-operations` crate owns the transport-independent backend contract, fixed
operation registry, typed normalization, canonical receipts, validation, and bounded pagination.
`healthmd-mcp` adapts those operations to MCP JSON-RPC, Apps, images, and HTTP. The shell
`healthmd query` command calls the same registry and query service directly, without an MCP envelope.

`healthmd mcp serve` preserves newline-delimited stdio and the direct Manual IP/Tailscale backend. It
exposes 19 fixed tools and one negotiated self-contained UI resource; it has no Mac-app, localhost,
shell, SQL, arbitrary URL, or arbitrary file-read authority. Two local-only tools start a bounded
background iPhone pairing listener, return its short-lived QR as MCP `image/png`, and poll a
health-free session receipt. The QR bearer secret is omitted from text/structured results, and the
pairing tools require local stdio identity. Pairing start is first-device onboarding only: existing
mobile trust or an explicit server device pin fails closed instead of creating ambiguous routing.
Query tools require a foreground query-capable iPhone and
v3. Generated-file export, resume, and cancellation remain durable protocol-v1 operations and
require host approval. Unix `healthmd-mcp` uses `exec(2)` to become the sibling `healthmd`.
Windows has no `exec(2)`, so `healthmd-mcp.exe` serves in-process and supervises its own same-file
helper against the same fixed Credential Manager service/account.

The default CLI feature set ends at local stdio and direct iPhone transport. The experimental
`streamable-http` and `oauth-resource-server` Cargo features add a read-only HTTP envelope but are
absent from release binaries. Feature-enabled `healthmd mcp serve-http` uses the same direct backend
and never substitutes server storage. It exposes only the 13 read-only tools; export paths and
durable file jobs are not remotely callable. Public TLS terminates at a reverse proxy while the Rust
listener remains loopback-only with an explicit Host allowlist. See
[Remote MCP architecture](remote-mcp.md).

One query page is bounded by its backend capability (at most 1,000 items and 1 MiB). Server-side
all-page traversal is additionally bounded to 4,096 pages and 2 MiB of aggregate MCP output, returns
an explicit continuation receipt when the aggregate limit is reached, and rejects cursor cycles.

## Rust workspace boundaries

The shared-core workspace at `packages/healthmd-core-rust` and CLI workspace at `apps/cli` keep independent manifests, lockfiles, and target directories. The CLI uses the shared protocol crate by path in the repository; Cargo packaging replaces that path hint with its exact crates.io version requirement.

### `healthmd-protocol` (shared-core workspace)

Pure models and deterministic transformations: explicit JSON envelopes, date/UUID encoding, capability negotiation, handshake transcripts, authenticated encryption, request fingerprints, partition hashes, and shared conformance vectors. It performs no networking, storage, or logging. Its source is under `packages/healthmd-core-rust/crates/healthmd-protocol`. The CLI consumes that Rust implementation directly. Apple and Android retain native networking, trust, lifecycle, AEAD state, and persistence while packaged UniFFI adapters can make the same crate authoritative for stateless deterministic protocol behavior.

### Shared export core (shared-core workspace)

Post-capture DTO validation, profile-specific projection, deterministic serialization, and the coarse-grained UniFFI boundary live in the shared-core workspace. Its independently versioned protocol API also validates and canonicalizes existing direct-protocol messages without changing their wire versions. Native products still own platform capture, networking, secret custody, persistence, and destination writes. No shared-core migration implies a public export-schema change.

### `healthmd-operations` (CLI workspace)

Transport-neutral operation authority: `HealthDataBackend`, caller/cancellation context, fixed
operation definitions, input schemas, typed query and export normalization, canonical receipt
validation, and aggregate traversal limits. CLI and MCP adapters call the same `HealthOperations`
service. A deterministic generator writes the packaged MCP catalog from this registry, and CI rejects
a stale mirror. It has no Clap, JSON-RPC, HTTP, OAuth, credentials, networking, or HealthKit behavior.

### `healthmd-client` (CLI workspace)

Platform-facing implementation: TCP listener, secure channel, OS credential storage, separate v1
and v2 durable jobs, product-aware disk-backed receivers, raw validation, and safe destination
commits. Transport and product selection are explicit and never fall back.

### `healthmd-mcp` (CLI workspace)

Vendor-neutral MCP adaptation, MCP Apps and PNG rendering, and stdio/Streamable HTTP transport
adapters over `healthmd-operations`. The local profile includes approval-gated durable export
tools. The remote profile is read-only and adds OAuth protected-resource/JWT/JWKS/session-owner
isolation. Its HTTP socket is loopback-only even in OAuth mode and requires a co-resident TLS reverse
proxy for remote deployment; Host and browser Origin allowlists remain mandatory boundaries.

### `healthmd-cli` (CLI workspace)

Argument grammar, direct-mobile adapters, JSON results/errors, stderr progress, exit status, and
transport startup. `healthmd query <operation> --arguments <JSON>` and MCP use identical registry
normalization and canonical query execution; adapter envelopes alone differ.
The direct backend is the portable default.
Pairing and local stdio MCP run through one installed `healthmd` executable (`healthmd mcp serve`) so
Keychain/Secret Service/Credential Manager trust has one executable owner. `healthmd setup codex`
performs bounded, lock-protected, atomic Codex configuration and pairing; `healthmd-mcp` is only a
compatibility launcher. It execs the sibling `healthmd` on Unix; on Windows it serves in-process and
supervises its own same-file helper against the same fixed Credential Manager service/account.
The opt-in `streamable-http` command selects the read-only direct profile; adding
`oauth-resource-server` accepts OAuth only as a complete single-owner configuration. Neither feature
adds a health-data store, and each query still requires the paired foreground iPhone. A future
optional Mac-app adapter may use the existing loopback HTTP API on macOS; it must remain explicit and
may not become a fallback. This crate does not contain direct wire or local
filesystem-security policy.

## Compatibility policy

Protocol changes are additive within a version only when old decoders can safely ignore them.
Unknown enum discriminators, cryptographic transcript changes, canonicalization changes, or frame
changes require a new negotiated application or transport version. Release notes publish minimum
compatible iOS and Android app versions. Application v2 reuses the deployed v1 pairing, encrypted
transport, and binary frames while using explicit Android control envelopes.

Swift synthesized `Codable` layout is not the specification. Explicit schemas, normative byte
layouts, and test vectors are.
