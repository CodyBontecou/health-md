# Release QA

Automated checks are necessary but do not replace physical iPhone and Android runs against the
exact Health.md builds advertised by a release.

## Automated gate

Run the independently locked shared-core workspace first:

```bash
cd packages/healthmd-core-rust
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
cargo test -p healthmd-protocol --test swift_v1_vectors --locked
```

From the repository root, verify both host UniFFI binding generators, then run the CLI workspace:

```bash
make check-core-bindings
cd apps/cli
cargo fmt --all --check
cargo test --workspace --all-features --locked
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --all-features --locked
dist generate --check
dist plan
```

Do not run either workspace's Cargo command from the other directory or combine their lockfiles. CI must pass on macOS, Ubuntu, and Windows. The Android repository must also pass
`:direct-protocol:test`, `:app:testDebugUnitTest`, and `:app:assembleDebug`. Run the ignored
Rust/Kotlin live gate to verify real pairing, negotiation, status, binary artifact transfer, final
acknowledgement, and completion. Verify the release archive's checksum and assert that it contains both `healthmd` and
`healthmd-mcp` (`.exe` on Windows). Run `healthmd --version`, `healthmd --help`,
`healthmd setup codex --help`, `healthmd mcp serve --help`, `healthmd-mcp --version`, same-binary
and compatibility-launcher MCP initialize/tools/resources handshakes, an isolated idempotent Codex
configuration test, and isolated `healthmd direct devices` smoke tests.

## Physical iPhone gate

Use a disposable destination and test account/data policy appropriate for sensitive health data.
Never attach raw output to an issue or CI log.

1. Pair on LAN with a generated code; reject a wrong code and an untrusted peer.
2. Reconnect without a code, list/select multiple devices, unpair both sides, and explicitly test
   `reset-trust --confirm` only with disposable trust.
3. Repeat status and a raw export through a Tailscale IPv4 address.
4. Exercise protected-data unavailable, app backgrounding, local-network denial, timeout, and
   reconnect behavior.
5. Export one day, seven days, complete-empty data, warning-only data, and an honest partial result.
6. Run summary and lossless extraction with category, metric, object, and JSON Pointer selectors;
   confirm partial extraction emits no retained values without `--allow-partial`.
7. Interrupt during a multi-partition raw job, inspect `status --job`, resume, compare the final
   digest/result, and test explicit cancellation plus cancellation-pending delivery.
8. On macOS and Linux, test overwrite, append, both Markdown merge modes, nested directories,
   duplicate/case/Unicode-alias paths, symlink ancestors/files, destination mutation, low disk, and
   interruption between destination commit and final confirmation.
9. On Windows, verify status/raw/extract/resume/cancel plus protocol-v1 generated-file export into
   an existing NTFS destination, including drive-root and UNC-path validation where available.
10. Run `healthmd setup codex` and verify first-pair, idempotent rerun, safe preservation of existing
    Codex settings, explicit multi-iPhone selection, export approval policy, and that the generated
    command uses the same `healthmd` executable with `mcp serve`. Then test status, metric catalog,
    metric chart, sleep, workouts, comparison, coverage, evidence, explicit raw query, multipage
    traversal, generated-file export, status/resume/cancel, MCP cancellation, interactive-App
    structured content, and PNG fallback. Confirm the `healthmd-mcp` compatibility launcher delegates
    without creating a second credential identity. Repeat on macOS, Linux, and Windows without
    Health.md for Mac installed.
11. Confirm stdout contains only the documented JSON/result stream, stderr contains no health
    payload, and private state/output permissions are appropriate on each platform.

## Physical Android gate

Use a disposable destination and a device with test health data. Never attach raw output to an issue
or CI log.

1. Pair from **Settings → Direct CLI** over LAN with the 20-digit Android code, verify wrong-code rejection, reconnect, forget, and re-pair. Confirm the six-digit iOS code cannot authenticate Android.
2. Run `status`, Health Connect raw JSON and NDJSON, and generated Markdown/JSON/CSV/Bases exports.
3. Repeat through Tailscale and with a non-default listener port.
4. Verify one explicit provider per raw request, unsupported-provider rejection, selected/all scope,
   permission-required, historical access, device-before-first-unlock, no-data, partial, and quota
   behavior.
5. Interrupt before the first partition, mid-partition, after a partition acknowledgement, during
   destination commit, and after final acknowledgement. Resume and compare exact artifact digests.
6. Kill and restart the app during preparation and verify a non-transactional raw job returns
   `spool_missing_restart_required` instead of regenerating under the accepted job ID.
7. Exercise Disconnect, CLI cancellation, notification actions, service timeout, low storage, and
   seven-day cleanup.
8. On macOS, Linux, and Windows, test generated-file traversal/symlink/collision defenses, all write
   modes, nested directories, destination replacement, and idempotent commit recovery.
9. Confirm Android Keystore invalidation fails closed and requires pairing again; inspect backup
   output to ensure direct credentials and health spools are absent.
10. Confirm logs, notifications, CLI JSON errors, and diagnostics contain no health values, raw
    provider payloads, credentials, or desktop paths.

Record the mobile app version/build, source platform, CLI version, source commits, OS versions,
architecture, network path, commands, job IDs, statuses, and artifact digests. Record counts and
diagnostics only—never health values.
