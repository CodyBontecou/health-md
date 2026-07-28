# Changelog

## 0.1.0-alpha.1

- Establish the standalone Rust workspace and portable CLI architecture.
- Implement protocol-v1 pairing and trusted reconnect with Swift-compatible X25519, HMAC-SHA256,
  ChaCha20-Poly1305, canonical request fingerprints, and binary transfer frames.
- Add Manual IP/Tailscale pair, device, unpair, live status, raw export, canonical JSON/JSONL
  extract, generated-file export, durable job status/resume, and cancellation commands.
- Add bounded disk-backed raw and generated-file receivers with per-document schema/date/archive
  validation, corruption-aware retransmission, capability-relative no-follow traversal, atomic
  compare-and-swap destination commits, Markdown merge support, and crash-idempotent receipts.
- Store reconnect credentials in the native macOS, Linux, or Windows credential service.
- Add byte-for-byte Swift↔Rust fixtures, cross-platform/MSRV CI, checksummed release archives,
  auditable dependency metadata, GitHub provenance attestations, shell and PowerShell installers,
  Homebrew formula generation, and protected staged crates.io publishing.
- Add capability-gated direct iPhone query protocol v3 and the portable `healthmd-mcp` binary with
  17 fixed tools, typed analysis/evidence, bounded paging, MCP Apps UI, portable PNG charts,
  durable generated-file export controls, cancellation recovery, and no Mac-app dependency.
- Support generated-file destination commits on macOS, Linux, and Windows by treating the desktop
  destination as opaque on iPhone while the receiving host validates and binds native filesystem
  identity.
- Add `healthmd mcp serve` and `healthmd setup codex` so pairing, native credentials, Codex
  configuration, and MCP use one signed executable identity; retain `healthmd-mcp` as a delegating
  compatibility launcher.
- Expand typed MCP tool discovery with complete nested date/metric/source/page/operation schemas,
  concrete call examples, explicit typed-tool routing, and offline `healthmd mcp schema [TOOL]`
  inspection so agents do not fall back to shell help or canonical extraction to infer query JSON.

Physical-iPhone release QA and external signing/publishing setup remain before the first public
release.
