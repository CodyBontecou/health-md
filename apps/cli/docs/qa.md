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
cargo test -p healthmd-protocol --test kotlin_v2_vectors --locked
cargo test -p healthmd-protocol --test swift_v3_query_vectors --locked
```

From the repository root, verify both host UniFFI binding generators, then run the CLI workspace:

```bash
make check-core-bindings
cd apps/cli
cargo fmt --all --check
cargo test --workspace --locked                    # shipped local-first feature set
cargo test --workspace --all-features --locked     # experimental remote profiles
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
rustup run 1.85.0 cargo check --workspace --locked
rustup run 1.85.0 cargo check --workspace --all-features --locked
rustup run 1.85.0 cargo check -p healthmd-cli --all-targets \
  --no-default-features --features streamable-http --locked
python3 -m unittest \
  scripts/test_verify_release.py \
  scripts/test_qualify_exact_ci.py \
  scripts/test_watch_cli_release.py
python3 scripts/verify-release.py
dist plan --allow-dirty
```

Do not run either workspace's Cargo command from the other directory or combine their lockfiles. CI must pass on macOS, Ubuntu, and Windows. The Android repository must also pass
`:direct-protocol:test`, `:app:testDebugUnitTest`, and `:app:assembleDebug`. Run the ignored
Rust/Kotlin live gate to verify real pairing, negotiation, status, binary artifact transfer, final
acknowledgement, and completion. Also run `:app:connectedDebugAndroidTest` for hermetic Direct CLI
Compose coverage. The opt-in real-app UI/transport gate is:

```bash
ANDROID_SERIAL=2C061FDH200CJN \
HEALTHMD_ANDROID_E2E_HOST=<reachable-computer-address> \
  apps/android/scripts/run-direct-cli-ui-e2e.sh
```

It uses the isolated `com.healthmd.android.e2e` app and concurrently runs the ignored Rust listener
`accepts_android_ui_pair_reconnect_disconnect_status_and_repair`; it verifies the foreground
notification Disconnect action, requests status only, and retains no health payload. Verify the
release archive's checksum and assert that it contains both `healthmd` and
`healthmd-mcp` (`.exe` on Windows). Run `healthmd --version`, `healthmd --help`,
`healthmd setup codex --help`, `healthmd query --help`, `healthmd mcp serve --help`,
`healthmd mcp serve-read-only --help`, and `healthmd mcp schema healthmd_sleep_sessions`. Also run
`healthmd export`, `healthmd extract`, `healthmd query`,
`healthmd query healthmd_sleep_sessions`, `healthmd resume`, `healthmd cancel`, `healthmd direct`,
`healthmd direct unpair`, `healthmd direct reset-trust`, `healthmd mcp`, and `healthmd setup` without
execution arguments while stdout is captured. Each must exit zero with one
`healthmd.cli_guidance/1` JSON document, `status: guidance`, and `request_sent: false`, without
opening credentials, starting a listener, mutating trust, or contacting a device. Repeat every
command with `--human` and require readable headings, examples or next steps, and no leading JSON
object syntax. Repeat representative commands with `--json` and require byte-equivalent JSON fields.
Invalid flags and invalid typed JSON must exit nonzero with one privacy-safe `healthmd.cli_error/1`
document when captured and readable recovery text with `--human`; rejected values and Clap's escaped
multiline rendering must be absent in both modes. Exercise the wake-window fake-peer cases for
unreachable source, authenticated `app_active: false`, late success, expiry, cancellation, and
`--wake-timeout 0`. Require the expiry error to remain `direct_source_unavailable` with only the
additive `wake_window_seconds`, and verify MCP progress-token calls emit bounded health-free
`notifications/progress` before the final response. `healthmd cancel` persists its durable marker
before the wake wait, so wake expiry or local interruption there reports `direct_cancellation_pending`
(the truthful pending state) rather than a terminal cancellation. Feed the
same bounded stdio initialize/tools calls to both serve modes: the complete mode must expose 19
tools, while read-only mode must expose exactly 13 tools with `readOnlyHint`, no pairing resource,
and no pairing/export-job declarations. Guess all six omitted tool names and require `Unknown tool`
before backend dispatch. Confirm that neither stdio mode starts an MCP HTTP listener, that the
default release rejects `mcp serve-http`, and that every build rejects the removed
`mcp serve-hosted` command. Separately run
source builds with `cargo run --features streamable-http -- mcp serve-http --help` and
`cargo run --features oauth-resource-server -- mcp serve-http --help`, `healthmd-mcp --version`,
generated-registry freshness, CLI↔MCP canonical query parity, same-binary and compatibility-launcher
MCP initialize/tools/resources handshakes with expanded nested schemas and examples, an isolated
idempotent Codex
configuration test, and isolated `healthmd direct devices` smoke tests. For Streamable HTTP, require
loopback binding (including OAuth mode), nonempty Host policy, fail-closed browser Origin policy,
rejection of every non-loopback Host or Origin when OAuth is absent, 2 MiB MCP framing, exact
protocol negotiation, and cancellation. Exercise protected-resource
metadata, missing/invalid/expired/wrong-issuer/wrong-audience/wrong-owner/unscoped tokens, bounded
no-redirect JWKS fetch, unknown-key refresh throttling, scope and session-owner isolation, removal of
the verified Authorization header, and exclusion of all mutation tools. A remote lab must terminate
TLS in a co-resident proxy that forwards only to loopback; never bind the Rust server publicly.
Verify that the HTTP relay has no synchronization routes, health-data storage directory, retention
job, account-data API, or query fallback when the paired foreground iPhone is unavailable. Audit the
proxy, OAuth service, and process logs to ensure they do not retain MCP arguments or health results.
Record the exact candidate in the [health-free release evidence template](release-evidence-template.md).

## Physical iPhone gate

Use a disposable destination and test account/data policy appropriate for sensitive health data.
Never attach raw output to an issue or CI log.

1. Pair on LAN by scanning the universal QR and by manually entering its shared 20-digit code; reject a wrong code, malformed or noncanonical QR payloads, and an untrusted peer. Verify that opening the same custom URL outside the in-app scanner never starts pairing, and that camera denial preserves manual entry. Separately verify a six-digit selector-1 legacy pairing fixture.
2. Reconnect without a code, list/select multiple devices, unpair both sides, and explicitly test
   `reset-trust --confirm` only with disposable trust.
3. Repeat status and a raw export through a Tailscale IPv4 address.
4. Exercise protected-data unavailable, app backgrounding, local-network denial, timeout, and
   reconnect behavior. With Health.md suspended, start a query using the default wake window, open
   the app before 120 seconds, and require that the original command completes without a re-run.
   Repeat with `--wake-timeout 0`, expiry, and Ctrl-C; local interruption must not report or persist
   phone-side cancellation. P1 has no APNs enrollment, so require status to report wait-only wake
   with enrollment unavailable and do not expect a notification.
5. Verify silent channel death self-heals without a manual in-app disconnect: keep Health.md
   foreground and connected, put the Mac to sleep (or toggle airplane mode on the phone) for at
   least 30 seconds, then run `healthmd status` on the Mac after waking it. The iPhone must
   redial on its own within roughly 20 seconds of its heartbeat/reconnect window (no toggle of
   Direct CLI Access, no QR re-scan), and the command must succeed. Repeat once over Tailscale.
6. Export one day, seven days, complete-empty data, warning-only data, and an honest partial result.
7. Run summary and lossless extraction with category, metric, object, and JSON Pointer selectors;
   confirm partial extraction emits no retained values without `--allow-partial`.
8. Interrupt during a multi-partition raw job, inspect `status --job`, resume, compare the final
   digest/result, and test explicit cancellation plus cancellation-pending delivery.
9. On macOS and Linux, test overwrite, append, both Markdown merge modes, nested directories,
   duplicate/case/Unicode-alias paths, symlink ancestors/files, destination mutation, low disk, and
   interruption between destination commit and final confirmation.
10. On Windows, verify status/raw/extract/resume/cancel plus protocol-v1 generated-file export into
   an existing NTFS destination, including drive-root and UNC-path validation where available.
11. Run `healthmd setup codex` and verify first-pair, idempotent rerun, safe preservation of existing
    Codex settings, explicit multi-iPhone selection, export approval policy, and that the generated
    command uses the same `healthmd` executable with `mcp serve`. Then test status, metric catalog,
    metric chart, sleep, workouts, comparison, coverage, evidence, explicit raw query, multipage
    traversal, and identical `healthmd query` canonical payloads for the same arguments; then test
    generated-file export, status/resume/cancel, MCP cancellation, interactive-App
    structured content, and PNG fallback. Confirm the `healthmd-mcp` compatibility launcher execs
    the sibling `healthmd` on Unix and, on Windows, serves in-process while successfully supervising
    its own same-file helper against the fixed Credential Manager service/account. Repeat on macOS,
    Linux, and Windows without Health.md for Mac installed.
12. Confirm stdout contains only the selected human, JSON, or exact artifact result stream; stderr contains no health
    payload, and private state/output permissions are appropriate on each platform.

### Wake-window command matrix (RFC-0005 P1)

Run each against one paired iPhone with Direct CLI Access enabled; keep the outer `timeout` above
wake plus the operation bound. Expect the identical in-flight command to complete after the app is
opened — never accept a re-run as success.

```bash
# unreachable/locked phone, default window: command holds, then completes when Health.md opens
NO_COLOR=1 TERM=dumb timeout 300 healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"}}' </dev/null

# fail-fast and custom window
NO_COLOR=1 TERM=dumb timeout 60 healthmd export --yesterday --raw --wake-timeout 0 \
  --output /tmp/healthmd-raw.json </dev/null
NO_COLOR=1 TERM=dumb timeout 200 healthmd extract --category Sleep --yesterday \
  --wake-timeout 60 --output /tmp/healthmd-sleep.json </dev/null

# expiry keeps the public error plus the additive window field
NO_COLOR=1 TERM=dumb timeout 200 healthmd status </dev/null   # wake_window.enrollment.state == unavailable
```

- Expiry of query/export/extract/resume must print `direct_source_unavailable` with
  `wake_window_seconds`; `healthmd cancel` expiry must print `direct_cancellation_pending`
  (its durable marker is already persisted) and deliver on the next reconnect.
- Ctrl-C mid-wait exits promptly and never persists or reports phone-side cancellation;
  `healthmd status --job <id>` still shows the true durable state afterwards.
- MCP progress: run `healthmd mcp serve` and issue a `tools/call` whose `params._meta.progressToken`
  is set (for example `"wake-1"`); while the phone is closed, expect health-free
  `notifications/progress` at wait start and roughly every 10 seconds, then a
  `notifications/cancelled`-free prompt return after sending `notifications/cancelled` for that id.

## Physical Android gate

Use a disposable destination and a device with test health data. Never attach raw output to an issue
or CI log.

1. Pair from **Settings → Direct CLI** over LAN by scanning the universal selector-3 QR and by entering the same shared 20-digit code manually. Verify malformed, wrong-origin, public-host, duplicate-field, percent-encoded, and six-digit QR rejection; wrong-code rejection; reconnect; forget; and re-pair. Against an old CLI that explicitly rejects selector 3, verify selector-2 fallback; verify transport failure and coroutine cancellation never trigger that downgrade. The isolated live E2E script covers pairing/reconnect/fallback/scanner-open/rotation on both Play and F-Droid flavors; the runtime camera-denial dialogs and a camera scan of a malformed physical QR remain manual steps because the system dialog is not automatable under instrumentation.
2. Run `status`, Health Connect raw JSON and NDJSON, and generated Markdown/JSON/CSV/Bases exports.
3. Repeat through Tailscale and with a non-default listener port. Exercise camera denial, permanent denial, no-camera fallback, rotation, and immediate pairing after a valid scan in both Play and F-Droid builds.
4. Verify one explicit provider per raw request, unsupported-provider rejection, selected/all scope,
   permission-required, historical access, device-before-first-unlock, no-data, partial, and quota
   behavior. Stop the direct session, start a CLI export with the default wake window, reopen the
   Direct CLI screen before expiry, and require the same request to continue. Repeat disabled,
   expired, and locally cancelled waits. P1 sends no FCM notification.
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
