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
- Generated-file destination commits are supported on macOS and Linux. Protocol v1 cannot represent
  Windows destination paths; Windows raw export and extraction are supported.

Physical-iPhone release QA and external signing/publishing setup remain before the first public
release.
