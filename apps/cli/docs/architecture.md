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

| Mobile source | Protocol | Exact tag-SHA counterpart / unqualified compatibility floor | Portable Rust behavior | Public status |
|---|---|---|---|---|
| Export-capable iPhone | pairing selector 3 current (1 legacy) / application v1 | iOS 3.3.0 (build 202609032317) / iOS 3.0.3 | Status, raw, extract, files, resume, cancel | Connectivity confirmed; full qualification pending |
| Query-capable iPhone | pairing selector 3 current (1 legacy) / application v1 + query v3 | iOS 3.3.0 (build 202609032317) / iOS 3.0.3 | V1 plus bounded MCP queries | Connectivity confirmed; full qualification pending |
| Android | pairing selector 3 current (2 legacy) / application v2 | Android 1.8.2 (31) / Android 1.5.4 (25) | Status, native raw, files, resume, cancel | Connectivity confirmed; full qualification pending |
| Android typed MCP query | N/A | Not implemented | Query tools require iPhone v3 | Unsupported |

Physical pairing/connectivity has been owner-confirmed for both mobile sources, but no public
CLI/mobile pair has completed the full retained qualification matrix yet. Shared pairing selector 3
is separate from iPhone query v3 and changes neither application protocol nor transfer framing. The authoritative
[compatibility ledger](mobile-compatibility.md) and per-release evidence record exact mobile builds.

## Portable MCP contract

The publishable `healthmd-operations` crate owns the transport-independent backend contract, fixed
operation registry, typed normalization, canonical receipts, validation, and bounded pagination.
`healthmd-mcp` adapts those operations to MCP JSON-RPC, Apps, images, and HTTP. The shell
`healthmd query` command calls the same registry and query service directly, without an MCP envelope.

`healthmd mcp serve` preserves newline-delimited stdio and the direct Manual IP/Tailscale backend. It
exposes 19 fixed tools plus negotiated self-contained analysis and local-only pairing UI resources;
it has no Mac-app, localhost, shell, SQL, arbitrary URL, or arbitrary file-read authority. Two
local-only tools start a bounded background iPhone pairing listener, return its short-lived QR as MCP
`image/png`, request an inline pairing card on MCP Apps hosts, and poll a health-free session receipt.
The QR bearer secret is omitted from text/structured results, and the pairing tools and resource
require local stdio identity. Pairing start is first-device onboarding only: existing
mobile trust or an explicit server device pin fails closed instead of creating ambiguous routing.
Query tools require a foreground query-capable iPhone and
v3. Before query/export/resume/cancel dispatch, one shared `healthmd-client` wake window keeps the
listener bound for up to 120 seconds and retries authenticated readiness with 250 ms to 2 s
backoff. MCP cancellation drops this local wait immediately without creating phone-side job
cancellation, and stdio emits health-free `notifications/progress` when the caller supplied a
progress token. `HEALTHMD_WAKE_TIMEOUT=0` disables the MCP window. For an opted-in, enrolled
iPhone, every current-main desktop build also sends one bounded, health-free P2 request to the
dedicated `apps/wake` Worker at the start of the wait; `HEALTHMD_WAKE_WORKER_URL` is an explicit
test-environment override and `HEALTHMD_NO_WAKE=1` disables the nudge. Failure always degrades to
P1. Android FCM remains P3 and Android therefore stays wait-only. The experimental feature-gated
Streamable HTTP relay additionally bounds each request at 300 seconds — a pre-existing transport
limit that the wake window does not extend — so keep `HEALTHMD_WAKE_TIMEOUT` low or disable it
behind that relay. Generated-file export, resume,
and cancellation remain durable protocol-v1 operations and require host approval. Unix `healthmd-mcp` uses `exec(2)` to become the sibling `healthmd`.
Windows has no `exec(2)`, so `healthmd-mcp.exe` serves in-process and supervises its own same-file
helper against the same fixed Credential Manager service/account.

`healthmd mcp serve-read-only` is a second default-build stdio entry for local least-privilege
hosts. It uses a distinct `local_read_only` application profile and a caller identity carrying only
`healthmd:read`. Catalog filtering and call authorization independently exclude both pairing tools
and all four export-job tools, including status; the pairing UI resource and local destination
authority are also absent. Pairing happens separately with `healthmd direct pair`. This entry starts
no MCP HTTP listener and introduces no cloud, OAuth, tunnel, or iPhone protocol dependency.

The default CLI feature set contains local stdio/direct iPhone transport plus the bounded P2 wake
HTTPS client; it does not contain an MCP HTTP listener or a health-data cloud path. The experimental
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
and v2 durable jobs, the shared bounded/cancellable active-source wake window, product-aware
disk-backed receivers, raw validation, and safe destination commits. Transport and product
selection are explicit and never fall back.

### `healthmd-mcp` (CLI workspace)

Vendor-neutral MCP adaptation, MCP Apps and PNG rendering, and stdio/Streamable HTTP transport
adapters over `healthmd-operations`. The local profile includes approval-gated durable export
tools. The remote profile is read-only and adds OAuth protected-resource/JWT/JWKS/session-owner
isolation. Its HTTP socket is loopback-only even in OAuth mode and requires a co-resident TLS reverse
proxy for remote deployment; Host and browser Origin allowlists remain mandatory boundaries.

### `healthmd-cli` (CLI workspace)

Argument grammar, local `healthmd.cli_guidance/1` discovery, actionable `healthmd.cli_error/1`
envelopes, TTY-aware human rendering, direct-mobile adapters, stderr progress, exit status, and
transport startup. The canonical `serde_json::Value` remains the sole command model: terminals render
it as text, pipes and `--json` serialize it unchanged, and `--human` forces text without modifying the
underlying contract. Raw artifacts bypass this renderer. Incomplete commands are resolved before
credentials or network work; malformed and operational failures remain nonzero.
`healthmd query <operation> --arguments <JSON>` and MCP use identical registry normalization
and canonical query execution, while query discovery embeds that shared registry's schema and
examples; adapter envelopes alone differ.
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
