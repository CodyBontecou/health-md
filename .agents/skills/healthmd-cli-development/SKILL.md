---
name: healthmd-cli-development
description: Develop or debug the standalone Rust Health.md CLI, portable healthmd-mcp server, and iPhone direct service. Use when changing CLI/MCP tools, Manual IP pairing/transport, Rust protocol/client/storage, Swift↔Rust fixtures, direct query protocol v3, durable raw/file transfer, canonical extraction, or iPhone HealthKit work without the Health.md macOS app.
compatibility: Requires the Health.md monorepo. Rust lives in the independent `packages/healthmd-core-rust` and `apps/cli` workspaces; Apple tools are required only for changes under `apps/apple`.
---

# Standalone Health.md CLI Development

The public portable CLI does not depend on the Health.md macOS app. Treat the Rust CLI and iPhone direct service as one cross-component product joined by a versioned protocol.

```text
standalone Rust healthmd (`mcp serve`) on macOS / Linux / Windows
  TCP listener :17647
  ← authenticated encrypted Manual IP/Tailscale channel →
foreground Health.md iPhone direct service
  → HealthKit / production exporters / protected spool
  → bounded query pages or durable transfer → MCP/JSON output or explicit destination
```

The iPhone owns HealthKit permission, protected-data checks, quota, canonical capture, and production file generation. Rust owns pairing identity, native credentials, listener transport, durable receiver state, validation, output, and safe destination commits.

The legacy Swift CLI, Mac loopback backend, encrypted Mac query context, bundled Swift MCP helper, and `apps/apple/scripts/healthmd` wrapper are compatibility surfaces, not standalone implementation targets. The portable Rust MCP server uses direct iPhone query protocol v3. Never make portable commands depend on Mac app availability or localhost.

## Code map

### Rust workspaces

`packages/healthmd-core-rust` and `apps/cli` are independent Cargo workspaces with independent lockfiles. Run Cargo in the workspace that owns the changed crate; do not regenerate one lockfile while validating the other.

| Area | Files |
|---|---|
| CLI grammar / JSON output | `apps/cli/crates/healthmd-cli/src/main.rs` |
| Portable MCP / Apps / PNG | `apps/cli/crates/healthmd-cli/src/mcp`, `assets/`; compatibility launcher in `src/bin/healthmd-mcp` |
| Codex onboarding | `apps/cli/crates/healthmd-cli/src/onboarding.rs`, `healthmd setup codex` |
| Protocol models / wire | `packages/healthmd-core-rust/crates/healthmd-protocol/src/models.rs`, `wire.rs` |
| Encoding / time / crypto | `packages/healthmd-core-rust/crates/healthmd-protocol/src/encoding.rs`, `time.rs`, `crypto.rs` |
| Transfer frames | `packages/healthmd-core-rust/crates/healthmd-protocol/src/transfer.rs` |
| Connection orchestration | `apps/cli/crates/healthmd-client/src/direct.rs` |
| Handshake / channel / packets | `apps/cli/crates/healthmd-client/src/handshake.rs`, `secure_channel.rs`, `packet.rs` |
| Native trust / credentials | `apps/cli/crates/healthmd-client/src/trust.rs`, `credentials.rs` |
| Durable state | `apps/cli/crates/healthmd-client/src/job.rs`, `storage.rs` |
| Raw validation / extraction | `apps/cli/crates/healthmd-client/src/raw_receiver.rs` |
| File commit / Markdown | `apps/cli/crates/healthmd-client/src/file_receiver.rs`, `markdown.rs` |
| Canonical Swift fixture | `packages/contracts/direct-protocol/v1/fixtures/swift-reference.json` |
| Normative protocols | `packages/contracts/direct-protocol/v1/protocol.md`, `v2/protocol.md`, `v3/protocol.md` |

### Apple component

| Area | Files |
|---|---|
| Shared direct protocol/crypto | `apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore` |
| iPhone listener/reconnect | `apps/apple/HealthMd/iOS/IPhoneDirectCLIService.swift` |
| Raw capture/spool | `apps/apple/HealthMd/iOS/IPhoneDirectExportCoordinator.swift` |
| Production file staging | `apps/apple/HealthMd/iOS/IPhoneDirectFileExportProducer.swift` |
| Direct query execution | `apps/apple/HealthMd/iOS/IPhoneDirectQueryCoordinator.swift` |
| App wiring | `apps/apple/HealthMd/iOS/HealthMdApp.swift` |
| Pairing UI | `apps/apple/HealthMd/iOS/Views/SyncSettingsView.swift` |
| Selection contracts | `apps/apple/HealthMd/Shared/Sync/CanonicalRawCLIModels.swift` |
| Production exporters | `apps/apple/HealthMd/Shared/Export`, `apps/apple/HealthMd/Shared/Managers/VaultManager.swift` |
| Tests | `apps/apple/Packages/HealthMdConnectivity/Tests`, `apps/apple/HealthMdTests/iOS`, `apps/apple/HealthMdTests/Sync` |

Portable logic belongs in Rust; HealthKit/export generation stays on iPhone. Do not implement standalone behavior in `apps/apple/HealthMdCLI/` unless explicitly maintaining the legacy Swift client too.

## Invariants

- Direct is standalone default. `mac-app` is reserved/unimplemented and never an implicit fallback.
- Manual IP/Tailscale is portable. Nearby must return `transport_unsupported` in Rust.
- Outcomes and argument failures are JSON on stdout. Help/version are text. Pairing instructions and health-free progress may use stderr.
- Never place health payloads in logs, diagnostics, fixtures, panic text, telemetry, or test reports.
- Direct CLI Access is opt-in. Pairing, idle reconnect, and new work need foreground iPhone. Only an already-connected export gets finite iOS background time; expiration pauses durable work.
- Direct trust is separate from Mac sync trust. Credentials use Keychain, Secret Service, or Windows Credential Manager. Never fall back to plaintext.
- Preserve explicit device and port. Never switch peer, port, backend, or transport silently.
- Peer/install binding, dates, destination, settings, request fingerprint, manifests, partition chain, and committed frontier are immutable across resume.
- Timeout, Ctrl-C, process death, disconnect, or background expiry never means cancellation. Only iPhone acknowledgement is terminal.
- Strict raw/extract validate the complete disk spool before exposure. Incomplete extract emits no values without `--allow-partial`.
- File mode requires an existing absolute destination, production iPhone exporters, bounded transfer, and restart-safe overwrite/append/Markdown merge receipts.
- Protocol v1 destination text is opaque on iPhone. The receiving host validates and binds an existing native absolute non-symlink directory before sending; file mode works on macOS, Linux, and Windows.
- `healthmd.health_data` is the public source shape. Projections must not masquerade as complete daily documents.
- Before changing exporter/metric/unit/JSON/CSV/Markdown/frontmatter/data-dictionary/schema output, read `apps/apple/docs/features/export-schema.md` and follow version/signature rules.

## Protocol v1

Port `17647` is distinct from old Mac sync/control ports. Preserve deployed bounds unless a negotiated version changes them:

- maximum outer JSON packet: 2 MiB;
- binary chunk body: 512 KiB;
- partitions: 32–64 MiB, 48 MiB preferred;
- bounded in-flight window;
- pairing code lifetime: 10 minutes;
- durable job lifetime: seven days;
- SHA-256 request/partition/result digests;
- ChaCha20-Poly1305 channel with monotonic direction sequences.

Protocol v1 still advertises wire role `macos_cli` for deployed compatibility even though Rust is portable. Do not rename it casually.

Swift synthesized `Codable` is not the specification. The normative contract is `packages/contracts/direct-protocol/v1/protocol.md` plus the Swift-generated fixture in `packages/contracts/direct-protocol/v1/fixtures/swift-reference.json`. The Rust crate-local copy is a packaging mirror and must remain byte-identical.

These normally require a new negotiated version rather than an additive v1 edit:

- cryptographic transcripts/domain strings;
- canonical JSON/fingerprint rules;
- associated-value enum layout;
- packet/binary-frame encoding;
- UUID, `Data`, optional, or date encoding;
- unknown discriminators old decoders cannot safely ignore.

## Cross-component workflow

1. Classify ownership: CLI grammar/output in Rust; HealthKit/export generation on iPhone; wire behavior in both.
2. Decide if local, additive v1, capability-gated, or protocol v2.
3. Update explicit/normative protocol contracts before implementation accidents become the spec.
4. Implement pure protocol behavior in `healthmd-protocol` without networking/storage/logging.
5. Put transport, credentials, durable state, validation, and commits in `healthmd-client`.
6. Keep `healthmd-cli` to arguments, JSON, progress, artifacts, and exit status.
7. Implement matching Swift and persist immutable scope before capture/transfer.
8. Update conformance fixtures/tests; fixture changes require evidence Swift generated them.
9. Run both automated gates and physical iPhone QA.
10. Update docs, changelogs, compatibility version, and release notes in both repos.

Never update one side of a wire change and call it complete.

## Common changes

### CLI flag or command

1. Parse/validate in `apps/cli/crates/healthmd-cli/src/main.rs`.
2. Keep domain/security logic outside the parser.
3. Add explicit Rust/Swift protocol fields when semantics cross the wire.
4. Pin exact request before network work.
5. Return deterministic JSON for invalid combinations and runtime errors.
6. Update parser/client/protocol/iPhone tests, help, README, operator guidance, and QA.

Do not add `--iphone` or require `--backend direct`; standalone already means direct iPhone.

### Pairing/reconnect

Preserve six-digit out-of-band code, ephemeral Curve25519, HMAC transcript proofs, fresh nonces/session keys, installation binding, native credentials, replay rejection, and separate trust domain. Codes never cross wire or persist. Write trust durably before success acknowledgement.

Test wrong code/peer, replaced identity, corrupt credentials, multiple devices, unpair on both sides, explicit reset, and unavailable Linux Secret Service.

### Raw/export extraction

- Build immutable `DirectExportRequest` and fingerprint before capture.
- Capture logical owner days in protected iPhone storage; allow days across bounded partitions.
- Validate exact dates, profiles/versions/schema, manifests, digest chain, and final digest before output.
- Keep assembly disk-backed.
- Summary extract has no hidden archive; record/archive selectors imply lossless.
- Preserve empty, warning, partial, failed, skipped, unsupported, cancelled, and missing distinctions.

### Generated files

Use production `VaultManager`; never duplicate exporters in Rust. Validate paths, IDs, byte counts, digests, fingerprint, root identity, symlinks, alias/case/Unicode collisions, and destination mutation. Overwrite is atomic. Append/Markdown merge use persisted digest-bound plans for idempotent replay.

Never reinterpret a desktop destination as an iPhone path. Keep it opaque on iPhone and require host-native absolute-path, symlink, identity, and traversal validation before transfer.

### Resume/cancel

Persist exact peer, request, destination, session, manifests, partition descriptors, digest chain, and frontier. Pending bytes may be discarded; committed partitions cannot be reinterpreted. Mismatches fail closed.

Cancellation remains pending until iPhone acknowledges. Never report terminal cancellation from local intent.

### Query/analysis and MCP

Portable `healthmd mcp serve` uses capability-gated application protocol v3 over the existing v1 authenticated encrypted iPhone channel. Pairing and MCP must remain in the same installed executable identity; the `healthmd-mcp` compatibility binary may delegate but must not become a second credential owner. Query capture and the shared typed evaluator run on foreground iPhone; only bounded `healthmd.query_response` pages cross the wire. Preserve exact dates/metrics/sources/detail/page scope, stable health-free rejection codes, authenticated dataset-bound cursors, explicit coverage/missingness/evidence/limitations, and logical `all_available` scope.

The Rust MCP server exposes only fixed operations. It must retain strict stdio bounds, concurrent ping/cancellation behavior, duplicate-ID protection, bounded cursor traversal, approval annotations for exports/resume/cancel, exact JSON text, negotiated self-contained MCP Apps resources, and unit-safe PNG fallback. It must not add shell, SQL, arbitrary URL, arbitrary file-read, localhost, or Mac-app dependencies.

## Tests

Rust shared core and protocol:

```bash
cd packages/healthmd-core-rust
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
cargo test -p healthmd-protocol --test swift_v1_vectors --locked
```

From the repository root run `make check-core-bindings`, then validate the CLI workspace separately:

```bash
cd apps/cli
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
python3 scripts/update-mcp-shared-assets.py --check
dist plan --allow-dirty
cargo run --bin healthmd -- --help
cargo run --bin healthmd -- setup codex --help
cargo run --bin healthmd -- mcp serve --help
cargo run --bin healthmd -- mcp schema healthmd_sleep_sessions
cargo run --bin healthmd-mcp -- --help
```

App/iPhone:

```bash
cd apps/apple
swift test --package-path Packages/HealthMdConnectivity
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd \
  -configuration Debug -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

Run focused reconnect/background, protected spool, direct query, export coordination, transfer, and exporter tests. CI must cover macOS, Ubuntu, and Windows. Physical QA must cover LAN pairing/reconnect, Tailscale, status, raw, extract, interruption/resume, cancellation, background expiry, protected-data denial, file commits on all desktop OSes, and the complete direct MCP tool/UI/PNG path without Health.md for Mac.

## Finish checklist

- Standalone works without installing/launching the Mac app.
- No Mac/localhost/Nearby fallback exists.
- Rust and Swift protocol tests/fixtures agree.
- iOS build and focused direct tests pass.
- Platform behavior matches docs.
- Export schema version/signature was handled if output changed.
- Docs/skills use portable `healthmd`, not `apps/apple/scripts/healthmd` or bundled helper.
- Logs/test artifacts contain no health payloads.
