# Changelog

## 0.1.0-alpha.6

- Add RFC-0005's shared P1 agent-wake window: query/export/extract/resume/cancel now wait up to
  120 seconds for an unavailable paired phone, retry with bounded backoff, support
  `--wake-timeout`/`HEALTHMD_WAKE_TIMEOUT` and immediate local cancellation, report one shared
  readiness object, and emit health-free MCP progress notifications.
- Activate RFC-0005 P2: the wake doorbell ships as the dedicated `healthmd-wake` worker
  (`healthmd-wake.costream.workers.dev`, own D1 and APNs secret bindings) deployed as a
  self-contained script because the `healthmd-receipt-verifier` source was lost with an old
  machine and reconstructing that production worker blind was rejected; the receipt-verifier
  stays frozen and untouched. The CLI stores per-pairing wake credentials from the phone's
  opt-in enrollment, sends one best-effort `/wake/request` nudge at wait start (feature-gated
  `wake-worker` HTTP client; default builds keep no-remote-HTTP), and a locked-phone wait now
  completes after the owner taps the visible notification. See the
  `docs/architecture/rfc-0005-worker-spec.md` amendment and RFC-0005 decision 5.
- Key the wake request HMAC by the registered SHA-256 verification hash of the wake key so the
  worker never holds the raw key; the construction is pinned cross-language by a shared
  Rust/worker test vector.
- Report wake enrollment truthfully per selected device in the shared `wake_window`/`wake`
  readiness object: a stored wake credential reports `available`/`enrolled`, and an absent
  credential, unpaired state, or ambiguous selection honestly reports
  `unavailable`/`wait_only` (single implementation for CLI and MCP; RFC-0005 decision 2).
- Pin `tinyvec` to `>=1.8, <1.13` as a Rust 1.85 MSRV guard (1.13 uses `alloc::vec`, a Rust 1.87
  API, without declaring `rust-version`); drop the pin once tinyvec declares `rust-version` or
  the workspace MSRV moves past 1.87.
- Unify new iOS and Android Direct CLI onboarding around one 20-digit selector-3 pairing code and universal in-app QR, while preserving byte-exact Apple selector 1, Android selector 2, and trusted reconnect compatibility.
- Shorten protected CLI releases without weakening qualification: reuse exact-SHA main CI with
  immutable-tag recovery for missing/cancelled runs, build platform candidates in parallel, prepare
  the Apple shared-core XCFramework once, recover GitHub draft read-after-create lag in place, and
  provide a reviewer-driven watcher for prompt signing/publication approvals.
- Publish this as an explicitly unqualified preview through the checksummed GitHub release,
  Homebrew/Linuxbrew tap, and coordinated crates.io packages while stable qualification remains
  pending.
- Windows artifacts remain Authenticode-unsigned while the release identity ledger records pending
  external certificate provisioning; verify them through the Sigstore-signed checksum closure.

## 0.1.0-alpha.5

- Render structured command results, discovery, schemas, and errors as concise human-readable text
  on interactive terminals while preserving the existing JSON model for pipes and explicit
  `--json`; add `--human` for pagers and keep raw artifacts and MCP JSON-RPC byte-exact.
- Make incomplete commands a local, non-network discovery surface: `export`, `extract`, `query`,
  selected typed queries, durable job commands, and command groups now return structured
  `healthmd.cli_guidance/1` requirements, schemas, examples, and next actions with a successful exit
  instead of opaque missing-argument failures. Replace escaped Clap/runtime error strings with
  privacy-safe `healthmd.cli_error/1` envelopes, stable parser kinds, accepted forms, exact help,
  and code-specific recovery guidance; expand command help, automated tests, and agent-facing docs.
- Publish this as an explicitly unqualified preview through the checksummed GitHub release,
  Homebrew/Linuxbrew tap, and coordinated crates.io packages while stable qualification remains
  pending.
- Windows artifacts remain Authenticode-unsigned while the release identity ledger records pending
  external certificate provisioning; verify them through the Sigstore-signed checksum closure.

## 0.1.0-alpha.4

- Show a short, human-readable getting-started screen when `healthmd` is run without a command,
  instead of wrapping the full help text inside a JSON error.
- Publish this as an explicitly unqualified preview through the checksummed GitHub release,
  Homebrew/Linuxbrew tap, and coordinated crates.io packages while keeping stable publication
  blocked until fresh physical-device qualification is recorded.
- Windows artifacts remain Authenticode-unsigned while the release identity ledger records pending
  external certificate provisioning; verify them through the Sigstore-signed checksum closure.

## 0.1.0-alpha.3

- Supersede the unpublished `0.1.0-alpha.2` candidate after its release gates found that generated
  installer and Homebrew metadata retained pre-signing macOS archive hashes. Propagate every final
  signed archive digest back into the cargo-dist manifests before generating global artifacts, and
  fail closed unless each manifest, shell installer checksum, PowerShell archive selection, and
  Homebrew URL/checksum pair matches the exact final archive bytes.
- Carry forward the bounded heartbeat/TCP keepalive handling and exact iOS/Android source
  counterparts prepared for the previous candidate. Publish this explicitly unqualified preview
  through the checksummed GitHub release and Homebrew tap while keeping stable publication blocked
  until fresh physical-device qualification is recorded.
- Windows artifacts remain Authenticode-unsigned while the release identity ledger records pending
  external certificate provisioning; verify them through the Sigstore-signed checksum closure.

## 0.1.0-alpha.2

- This candidate was never published: final release qualification found stale pre-signing macOS
  archive hashes in generated installer and Homebrew metadata. It is retained only as failed-release
  evidence and is superseded by `0.1.0-alpha.3`.

- Detect silently dead direct-device channels with bounded heartbeat/TCP keepalive handling so a
  foreground paired iPhone can redial later one-shot CLI listeners without a manual disconnect.
  The CLI now answers heartbeat pings in every v1 receive path while preserving command deadlines.
- Prepare the portable release against the latest shared iOS and Android source while preserving
  the deployed protocol-v1, Android application-v2, and iPhone query-v3 contracts. Publish this
  explicitly unqualified preview through the checksummed GitHub release and Homebrew tap while
  keeping stable publication blocked until fresh physical-device qualification is recorded.
- Windows artifacts remain Authenticode-unsigned while the release identity ledger records pending
  external certificate provisioning; verify them through the Sigstore-signed checksum closure.

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
until then. The mobile compatibility ledger is authoritative: explicitly unqualified previews may
retain exact pending rows, while stable releases require the exact qualified iPhone and Android
records.
