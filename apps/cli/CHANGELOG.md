# Changelog

## Unreleased

- Detect silently dead direct-device channels with bounded heartbeat/TCP keepalive handling so a
  foreground paired iPhone can redial later one-shot CLI listeners without a manual disconnect.
  The CLI now answers heartbeat pings in every v1 receive path while preserving command deadlines.

## 0.1.0-alpha.1

- Establish the standalone Rust workspace and portable CLI architecture.
- Implement protocol-v1 pairing and trusted reconnect with Swift-compatible X25519, HMAC-SHA256,
  ChaCha20-Poly1305, canonical request fingerprints, and binary transfer frames.
- Add Manual IP/Tailscale pair, device, unpair, live status, raw export, canonical JSON/JSONL
  extract, generated-file export, durable job status/resume, and cancellation commands.
- Add bounded disk-backed raw and generated-file receivers with per-document schema/date/archive
  validation, corruption-aware retransmission, capability-relative no-follow traversal, atomic
  compare-and-swap destination commits, Markdown merge support, crash-idempotent receipts, and
  cross-process 64-job/128-GiB retained-storage admission with a 512-MiB free-space floor and
  lifecycle capacity for validation, assembly, staging, and extraction amplification. Generated
  append/merge manifests reject destination-dependent amplification before partitions transfer,
  duplicate Markdown headings cannot multiply replacements, and standalone panic diagnostics are
  fixed and health-free.
- Store reconnect credentials in the native macOS, Linux, or Windows credential service.
- Add byte-for-byte Swift↔Rust fixtures, cross-platform/MSRV CI, checksummed release archives,
  auditable dependency metadata, GitHub provenance attestations, shell and PowerShell installers,
  Homebrew formula generation, and protected staged crates.io publishing.
- Require release-tag artifacts to pass Developer ID signing and notarization, stapled DMGs,
  Authenticode for both Windows binaries and the PowerShell installer, native signed-upgrade probes,
  a Sigstore-signed checksum closure, and byte-for-byte remote draft revalidation.
- Add capability-gated direct iPhone query protocol v3 and the portable `healthmd-mcp` binary with
  19 local fixed tools, typed analysis/evidence, bounded paging, MCP Apps UI, portable PNG charts,
  durable generated-file export controls, cancellation recovery, and no Mac-app dependency.
- Let local stdio MCP clients start a bounded iPhone pairing session, render its short-lived QR as
  `image/png`, request a dedicated inline MCP App pairing card on negotiated hosts, and poll a
  health-free session receipt. Scanning the QR with Health.md's in-app
  Direct CLI scanner starts the authenticated connection immediately without a second Pair tap;
  external custom-URL opens are not pairing consent. Pairing remains unavailable to
  HTTP/OAuth profiles, and its one-time code, host address, and deep link never appear in text
  results. Pairing start fails closed when existing trust or a device pin would make later MCP
  routing ambiguous.
- Support generated-file destination commits on macOS, Linux, and Windows by treating the desktop
  destination as opaque on iPhone while the receiving host validates and binds native filesystem
  identity.
- Add `healthmd mcp serve` and `healthmd setup codex` so pairing, native credentials, Codex
  configuration, and MCP use the installed `healthmd`; retain `healthmd-mcp` as a compatibility
  launcher that execs `healthmd` on Unix and uses an authenticated same-file helper on Windows.
- Defer Windows Authenticode behind the signing-identity ledger: while
  `release-identities.json` records `pending_external_certificate_provisioning`, release tags are
  permitted, the Windows signing jobs skip, and the Windows archive plus PowerShell installer
  publish unsigned with integrity carried by the Sigstore-signed checksum closure. Committing a
  qualified publisher subject re-enables mandatory signing for both Windows executables, the
  installer, and native post-extraction gates.
- Expand typed MCP tool discovery with complete nested date/metric/source/page/operation schemas,
  concrete call examples, explicit typed-tool routing, and offline `healthmd mcp schema [TOOL]`
  inspection so agents do not fall back to shell help or canonical extraction to infer query JSON.
- Clamp v3 page requests to negotiated peer/local limits, validate complete returned response
  shapes/counts, reject unknown nested query fields, and bind iPhone paging cursors to the trusted
  CLI installation.
- Make local stdio/direct-iPhone MCP the empty-feature default for `healthmd-cli` and release
  artifacts. Add `healthmd mcp serve-read-only` as a separate cloud-free local stdio profile with
  only the 13 readiness/query tools, a read-only caller identity, no pairing resource, and
  fail-closed rejection of all pairing/export-job calls. Keep the direct-backed Streamable HTTP and
  OAuth resource-server transports available only through explicit experimental Cargo features.
- Add the publishable transport-neutral `healthmd-operations` crate as the shared authority for
  backend contracts, fixed operation definitions, typed query/export/date/selection normalization,
  canonical receipts, validation, and traversal limits. Generate the packaged MCP catalog from its
  registry, add `healthmd query` for the same canonical operations, and prove CLI/MCP request and
  payload parity across every query operation.
- Extract the vendor-neutral `healthmd-mcp` crate and add an optional read-only Streamable HTTP
  profile with loopback-only listener, external TLS-termination contract, exact OAuth owner/scope/
  issuer/audience validation, bounded no-redirect JWKS retrieval, and per-session grant binding.
- Remove the experimental synchronized health-data corpus, its upload/account APIs, and its CLI
  server command. Remote MCP remains a live direct relay to the paired foreground iPhone; Health.md
  does not store users' health data for later queries. The hosted experiment had no production
  endpoint or production OAuth client and accepted no user data, so no server corpus migration is required.

Windows artifacts publish Authenticode-unsigned until a signing identity is qualified in
`release-identities.json`; verify Windows downloads against the Sigstore-signed checksum manifest
until then. The mobile compatibility ledger records the qualified iPhone and Android release pair.
