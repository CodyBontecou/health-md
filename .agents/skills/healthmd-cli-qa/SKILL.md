---
name: healthmd-cli-qa
description: Test the standalone Health.md CLI, portable healthmd-mcp server, and direct iPhone path. Use for CLI/MCP QA, Rust↔Swift protocol compatibility, Manual IP/Tailscale pairing, typed query/UI/image checks, status/raw/extract/file/resume/cancel, cross-platform release gates, failure diagnosis, or physical-device plans without the Health.md macOS app.
compatibility: Automated CLI checks require the independently locked shared-core and CLI Rust workspaces; iPhone-side checks require the Health.md app repository and Apple build tools. Live E2E requires a current iPhone build with Direct CLI Access, HealthKit/local-network permission, and a disposable destination for file tests.
---

# Standalone Health.md CLI QA

Validate the Rust CLI, portable Rust MCP server, and iPhone direct service. The macOS app, loopback API, Mac destination bookmark, and legacy Swift CLI are out of scope unless explicitly requested.

## Rules

- Treat this as a three-component contract: shared protocol under `packages/healthmd-core-rust`, portable client under `apps/cli`, and the iPhone service/exporters under `apps/apple`.
- Keep CLI commands bounded and non-interactive. On macOS/Linux use `NO_COLOR=1 TERM=dumb`, `timeout`, and stdin from `/dev/null`.
- Use stdout JSON, artifacts, durable job records, and commit receipts as evidence.
- Never put raw health payloads in logs, issues, fixtures, or reports. Record only counts, dates, statuses, diagnostics, and digests.
- Separate automated checks from physical-iPhone checks. Never claim live coverage without observations.
- Do not weaken crypto, digest, path, schema, peer-binding, or partial-result validation to pass a test.

## Layers

1. Independently locked shared-core and CLI Rust format/build/lint/workspace tests.
2. Swift-generated protocol-v1 export and protocol-v3 query fixture conformance from `healthmd-protocol`.
3. Connectivity package, focused direct-service/query/export tests, and iOS build.
4. Local CLI/MCP help, initialize/tools/resources, and offline trust smoke.
5. Live LAN pair/status/raw/extract/file/durability plus every direct MCP query/export/UI/PNG path.
6. Live Tailscale network coverage.
7. macOS/Linux/Windows release matrix with both packaged binaries.

Do not insert a Mac-app control-server smoke test: the portable client listens directly for iPhone.

## Rust gate

Validate the shared-core workspace first:

```bash
cd packages/healthmd-core-rust
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
cargo test -p healthmd-protocol --test swift_v1_vectors --locked
cargo test -p healthmd-protocol --test swift_v3_query_vectors --locked
```

From the repository root run `make check-core-bindings`, then validate the CLI workspace separately:

```bash
cd apps/cli
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
dist plan --allow-dirty
cargo run --bin healthmd -- --help
cargo run --bin healthmd -- setup codex --help
cargo run --bin healthmd -- mcp serve --help
cargo run --bin healthmd-mcp -- --help
python3 scripts/update-mcp-shared-assets.py --check
```

Never run these as one Cargo workspace or rewrite both lockfiles. The focused protocol test validates the canonical `packages/contracts/direct-protocol/v1/fixtures/swift-reference.json` through its byte-identical Rust packaging mirror: pairing proofs, Swift encoding, request fingerprints, and transfer frames. Changes to cryptographic transcripts, canonical JSON, enum layout, UUID/date encoding, or frames require protocol-version analysis. Never regenerate this fixture from Rust just to silence failure.

CI must pass on macOS, Ubuntu, and Windows. Verify release checksums plus `healthmd --version`, `healthmd --help`, idempotent isolated `healthmd setup codex --skip-pairing`, same-binary and compatibility-launcher MCP handshakes, and isolated `healthmd direct devices`. `HEALTHMD_CLI_DATA_DIR` changes file state but does not namespace native credentials.

## iPhone-side gate

From the monorepo root:

```bash
cd apps/apple
swift test --package-path Packages/HealthMdConnectivity

xcodebuild -project HealthMd.xcodeproj \
  -scheme HealthMd \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

Run focused tests relevant to the change, especially:

- `apps/apple/Packages/HealthMdConnectivity/Tests/HealthMdConnectionCoreTests`
- `apps/apple/Packages/HealthMdConnectivity/Tests/HealthMdDirectClientCoreTests`
- `apps/apple/HealthMdTests/iOS/IPhoneDirectCLIReconnectPolicyTests.swift`
- `apps/apple/HealthMdTests/Sync/ConnectedCorpus*Tests.swift`
- `apps/apple/HealthMdTests/Sync/ConnectedTransferTests.swift`
- touched exporter contracts

The portable client does not require a macOS app build. If public exporter/metric/unit/JSON/CSV/Markdown/frontmatter/data-dictionary output changes, follow `apps/apple/docs/features/export-schema.md`, including schema bump/signature fixture when required.

## Offline CLI smoke

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd --version </dev/null
NO_COLOR=1 TERM=dumb timeout 15 healthmd --help </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd direct devices </dev/null
```

Pass:

- direct is default and Manual IP is portable;
- commands are status/export/extract/resume/cancel/direct trust management;
- `direct devices` needs no network or Mac app;
- failures are deterministic JSON on stdout;
- pairing/progress may use stderr but never health payloads.

Negative smoke:

- `--transport nearby` → `transport_unsupported`;
- `--backend mac-app status` → deterministic `not_implemented` without opening/looking for the app;
- invalid date/selector/output combinations → `invalid_request`;
- missing/unsafe file destination fails before network work;
- Windows file mode → validated native absolute destination with traversal/symlink/identity protections.

## Extraction contract

Verify:

1. `extract --category Sleep --yesterday` sends `health_data_projection` with resolved Sleep selection and summary detail.
2. iPhone clones settings and does not persist selection.
3. Summary returns schema-v7 documents with `raw_capture_status: not_requested` and no hidden archive.
4. `--object records` or archive pointers imply lossless and return honest projections, not falsely complete documents.
5. Receipts cover every requested day; JSONL writes to stderr or `OUTPUT.receipt.json`.
6. Incomplete extraction emits no retained data without `--allow-partial`.
7. Unknown metrics/categories/sources/pointers and unsupported peers fail closed.
8. JSONL enforces its per-item bound; unusually dense days use JSON.

## Live prerequisites

- Exact CLI and iOS builds under test.
- Health.md open on unlocked-enough iPhone.
- **Settings → Mac Sync → Direct CLI Access** enabled with **Manual IP**.
- Local-network and selected HealthKit permissions.
- Reachable LAN/Tailscale computer address and matching port.
- Native credential storage available.
- Existing disposable absolute destination on macOS/Linux.
- A plan that excludes health payloads from logs.

Pairing/new commands need foreground iPhone. An already-connected export may receive finite iOS background time; expiration must pause rather than corrupt or falsely complete.

## Live LAN E2E

```bash
NO_COLOR=1 TERM=dumb timeout 180 healthmd direct pair </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null

NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd export --yesterday --raw --output /tmp/healthmd-raw.json </dev/null

NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --yesterday \
    --output /tmp/healthmd-sleep.json </dev/null

mkdir -p /tmp/healthmd-destination
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd export --yesterday \
    --destination /tmp/healthmd-destination </dev/null
```

Pass:

- pair code/instructions only on stderr and one success object on stdout;
- scanning the QR from **Sync → Direct CLI Access → Scan Pairing QR** starts pairing automatically without a second Pair tap; camera denial recovers after Settings, malformed/noncanonical private hosts and external custom-URL opens cannot pair, and manual code entry remains available;
- local trust records intended iPhone and reconnect needs no new code;
- status says `backend: direct`, `mac_app: bypassed`, reports protected/readiness state, and no health values;
- raw validates exact dates, profile/result/archive/schema, manifests, byte counts, partition chain, and final digest before atomic output;
- extract and receipt match requested scope and empty/incomplete distinctions;
- production file output stays under explicit destination and has valid receipt;
- default file job suppresses roll-ups/summary-only; `--use-iphone-settings` mirrors them only when tested intentionally;
- iPhone history/quota agrees with acknowledged job.

Repeat network-sensitive flows through a Tailscale IPv4 address. Tailscale remains Manual IP; no fallback is acceptable.

## Durability/cancel E2E

1. Interrupt a multi-partition raw and file job after at least one committed partition.
2. Record job ID without payload.
3. Run `healthmd status --job JOB_UUID` offline.
4. Reopen same iPhone and `healthmd resume JOB_UUID`.
5. Verify final digest/result and idempotent destination commit.
6. Cancel another disposable job.
7. With iPhone unavailable, verify `direct_cancellation_pending`; reconnect and deliver cancel.

Pass:

- timeout, Ctrl-C, death, disconnect, or background expiry does not cancel;
- resume pins peer, request fingerprint, dates, destination, manifests, and frontier;
- committed partitions are not retransmitted/applied twice;
- overwrite is atomic and append/Markdown merge idempotent;
- only iPhone acknowledgement is terminal cancellation;
- jobs expire at fixed seven days.

## Negative matrix

| Scenario | Expected |
|---|---|
| No pairing | `direct_not_paired`; no Mac fallback. |
| Multiple devices, no selection | `direct_device_selection_required`. |
| Wrong code/peer | Authentication failure; no trust/job. |
| Corrupt native trust | `direct_trust_invalid`; no silent reset/plaintext. |
| macOS Keychain denies the current binary | Prompt-free bounded `direct_storage_unavailable`; no hang or plaintext fallback. |
| Linux Secret Service absent | `direct_storage_unavailable`; secret not written to file. |
| Wrong address/port or network denial | Bounded `direct_iphone_unavailable`; no switch. |
| Locked/protected data unavailable | Safe failure without disclosure. |
| Altered packet/frame/manifest/digest/replay | Rejected before acknowledgement/output. |
| Traversal/symlink/alias/mutation | Rejected before escaping/corrupting root. |
| Interrupted append/merge | Resume commits once. |
| Partial strict raw | Validated partial, nonzero without `--allow-partial`. |
| Partial extract | No values without `--allow-partial`. |
| Windows file destination | Generated files commit under the exact validated bound destination; raw/extract remain unaffected. |
| Nearby | `transport_unsupported`; no hidden Manual IP fallback. |
| Mac backend | `not_implemented`; no app/localhost dependency. |

## Platform matrix

- **macOS:** Keychain; raw/extract/files; safe commits; archive/Homebrew/signing/notarization.
- **Linux:** Secret Service; XDG state; raw/extract/files; filesystem hardening; archive/Linuxbrew.
- **Windows:** Credential Manager; LocalAppData; raw/extract/generated files/resume/cancel; PowerShell/archive; native destination validation.

Verify private state/output permissions and checksums. Do not describe unsigned alpha artifacts as stable signed releases.

## Report

```markdown
## Standalone Health.md CLI QA

- Rust fmt/build/lint/tests: pass/fail
- Swift protocol fixture: pass/fail
- iOS build/direct tests: pass/fail
- Local CLI smoke: pass/fail
- Live LAN: pass/fail/not run
- Live Tailscale: pass/fail/not run
- Platforms: macOS/Linux/Windows

### Evidence
- versions, commits, commands, exit codes, JSON statuses, job IDs
- counts, paths, receipts, artifact digests only

### Result
[summary]

### Follow-ups
- [ ] item
```

Securely remove disposable raw and destination data after authorized QA.
