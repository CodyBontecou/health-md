# Direct iPhone CLI backend

## Status

- **Implementation status:** complete; physical-device release QA remains required
- **Primary surfaces:** `healthmd` CLI and an open Health.md iPhone app
- **Source files:** `Packages/HealthMdConnectivity/`, `HealthMdCLI/Sources/healthmd/main.swift`, `HealthMd/iOS/IPhoneDirectCLIService.swift`, `HealthMd/iOS/IPhoneDirectExportCoordinator.swift`, `HealthMd/iOS/IPhoneDirectFileExportProducer.swift`

## What it does

The explicit direct backend lets the Mac `healthmd` process pair with an open iPhone and request Apple Health exports without launching the Health.md macOS SwiftUI app:

```text
healthmd --backend direct
  ← authenticated manual-IP/Tailscale or nearby connection →
open Health.md iPhone app → HealthKit → protected bounded spool
  → strict canonical JSON or production-generated export files → Mac
```

The compatible default remains `--backend mac-app`. The CLI never silently changes backend or transport. HealthKit reads still occur on iPhone, Direct CLI Access is opt-in, and iOS foreground/protected-data constraints still apply.

Direct mode supports pairing, device inspection, status, canonical `extract`, strict raw extraction, generated-file exports, durable status/resume, and explicit cancellation. Query, evidence, refresh, doctor, metrics-catalog, and MCP features require the Mac app because they use its encrypted context store or catalog API. They return deterministic `backend_unsupported` diagnostics in direct mode rather than switching backend.

## Requirements

- A current `healthmd` binary and current Health.md iOS build.
- Health.md open on an unlocked-enough iPhone.
- **Settings → Mac Sync → Direct CLI Access** enabled on iPhone.
- HealthKit permission and export quota available.
- For Manual IP: a reachable Mac address and TCP port `17647` by default. A Tailscale address is allowed.
- For Nearby: both devices on a network where Multipeer discovery is permitted and local-network permission granted.
- For file mode: an existing, absolute, writable Mac destination supplied with `--destination`.

Direct access is foreground-scoped. iOS can suspend the listener or HealthKit work after the app leaves the foreground. This is not a fully unattended background or cron interface.

## Backends and transports

| Choice | Default | Meaning |
|---|---|---|
| `--backend mac-app` | Yes | CLI uses the Mac app's loopback server and existing Mac↔iPhone connection. |
| `--backend direct` | No | CLI connects directly to the paired open iPhone. |
| `--transport manual-ip` | Yes in direct mode | iPhone connects to the CLI listener at an explicit LAN/Tailscale address and port. |
| `--transport nearby` | No | iPhone discovers the explicitly advertised `healthmd-cli` Multipeer service. |

Backend and transport options are global and precede the command:

```bash
healthmd --backend direct --transport manual-ip status
healthmd --backend direct --transport nearby export --yesterday --raw --output yesterday.json
```

No failed mode falls back to another backend, Manual IP, Nearby, or the Mac app.

## Pairing

Pairing creates a trust relationship distinct from the Health.md Mac app's own sync trust. The six-digit code is short-lived and is never sent over the wire or persisted.

### Manual IP or Tailscale

1. On Mac, start the listener:

   ```bash
   healthmd direct pair --transport manual-ip
   ```

2. Keep that command running and note the pairing code and port printed to stderr.
3. On iPhone, enable Direct CLI Access, select **Manual IP**, enter the Mac LAN/Tailscale address, port, and code, then tap Pair.
4. The CLI prints the final machine-readable pairing result on stdout.

Pairing accepts `--port PORT`, `--timeout SECONDS`, and `--pairing-code CODE` for controlled automation. If a non-default Manual IP port is saved on iPhone, pass the same global `--port PORT` before later status/export/resume/cancel commands. Avoid putting a pairing code in shell history unless necessary.

### Nearby

1. On Mac, advertise the explicit service:

   ```bash
   healthmd direct pair --transport nearby
   ```

2. On iPhone, enable Direct CLI Access, select **Nearby**, enter the displayed code, then tap Pair.
3. Keep both devices nearby and Health.md foregrounded until both report success.

Pairing is one-time. After success, the iPhone stores the reconnect credential in Keychain and shows **Ready for healthmd** whenever Direct CLI Access is toggled on. A paired Nearby iPhone keeps one cancellable discovery wait active while foregrounded, so it does not cycle through timed loading states; each CLI command connects on demand without another code. Toggling access off cancels that wait without deleting trust. Use **Forget Pairing** only when the CLI should require a new code.

Nearby requires Multipeer's encrypted session and then applies the same Health.md application-layer authentication and encryption as Manual IP.

### Device records

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

`devices` does not contact an iPhone. It reports the CLI installation ID and locally trusted devices. Unpairing deletes that Mac-side trust; use **Forget Paired CLI** on iPhone to delete its side too.

When multiple devices are trusted, select one explicitly:

```bash
healthmd --backend direct --device DEVICE_UUID status
```

## Status

```bash
healthmd --backend direct --transport manual-ip status
healthmd --backend direct --transport manual-ip --port 18000 status
healthmd --backend direct --transport nearby status
healthmd --backend direct status --job JOB_UUID
```

Live status authenticates the selected paired iPhone and reports direct access, protected-data, HealthKit/export readiness, and active work without exposing health values. Job status is read from the CLI's durable local record and does not require a live iPhone connection.

## Strict raw export

Raw mode requests the same public schema-v7 `healthmd.health_data` daily documents and strict validation used by the Mac-app backend:

```bash
healthmd --backend direct export --yesterday --raw --output yesterday.json
healthmd --backend direct --transport nearby export --last 7 --raw --output week.json
healthmd --backend direct export --from 2026-07-01 --to 2026-07-07 --raw --output week.json
healthmd --backend direct export --all --raw --output complete-health-corpus.json
```

`--raw` writes no generated export files. Without `--output`, the validated JSON is streamed to stdout. Prefer an output file for sensitive or large results. `--allow-partial` changes only the exit status for a validated `partial_success`; it does not remove missing/capture diagnostics.

Direct raw mode captures one logical day at a time into protected iPhone storage. The resolved settings snapshot, source timezone, exact day labels, and request fingerprint are pinned before capture so resume cannot mix changed preferences or travel boundaries. Logical days may span multiple 32–64 MiB physical partitions. The transport uses 512 KiB binary frames, SHA-256 validation, chained partition digests, durable receiver checkpoints, and disk-backed final strict-response assembly. Before acknowledging completion, the CLI runs the existing bounded strict date/profile/schema/archive validator; the iPhone then durably records completion/quota and sends a separate confirmation. A lost final message therefore remains resumable rather than producing a false terminal state. The path does not keep a complete corpus in memory or impose a 2 GiB aggregate product cap. Available storage and one unusually dense day remain practical limits.

Selection-pushed canonical extraction also works directly and emits ordinary v7 documents or honest pointer projections after validating the disk-spooled transport:

```bash
healthmd --backend direct extract --category Sleep --last 7 --output sleep.json
healthmd --backend direct extract --metric workouts --last 14 \
  --object records --detail lossless --output workout-records.json
```

The current canonical source is Apple Health. Summary does not capture a hidden lossless archive; record/archive selectors imply lossless. Partial extraction emits no retained data unless `--allow-partial` is explicit.

## Generated-file export

Direct file mode uses the iPhone's production exporters and then securely transfers their generated files to an explicit Mac destination:

```bash
mkdir -p "$HOME/Documents/HealthVault"
healthmd --backend direct export --yesterday \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct --transport nearby export --last 7 \
  --category Sleep --detail summary \
  --destination "$HOME/Documents/HealthVault"

healthmd --backend direct export --yesterday --use-iphone-settings \
  --destination "$HOME/Documents/HealthVault"
```

The destination must already exist and be absolute. Direct mode never uses or guesses a Mac app bookmark. `--output` is for raw JSON and is separate from `--destination`.

Default `requested_dates_only` behavior keeps the iPhone's saved formats, Health subfolder, filenames/templates, write mode, Daily Note Injection, and Daily Notes Only, while disabling roll-ups and summary-only mode for this request. Repeatable `--metric`/`--category` or `--all-metrics` plus `--detail summary|lossless` replace saved metric/detail scope only for that job. `--use-iphone-settings` mirrors saved settings exactly, including roll-ups and summary-only mode.

The iPhone generates the same JSON, CSV, Markdown, ZIP, data-dictionary, roll-up, individual-record, Daily Note, and provider sidecar outputs through `VaultManager`; direct mode does not define a second export schema. Public export schema version 7 is unchanged.

Before committing any received file, the CLI validates its declared path, byte count, SHA-256 digest, file manifest, and job fingerprint. It binds the destination root device/inode, rejects absolute child paths, traversal, symlink destinations/ancestors, conflicting destination mutation, and digest changes, then walks and installs relative to `O_NOFOLLOW` directory descriptors with `openat`/`renameat` so an intermediate-directory race cannot escape the approved root. Overwrite is atomic. Append and Markdown merge use a persisted digest-bound commit plan so retrying an acknowledged or interrupted partition does not append the same content twice.

## Durable jobs, resume, and cancellation

Direct jobs are persisted before the request starts and expire at a fixed seven-day deadline. Both peers persist the exact request fingerprint, installation binding, partition chain, and committed frontier.

```bash
healthmd --backend direct status --job JOB_UUID
healthmd --backend direct --transport manual-ip resume JOB_UUID --timeout 300
healthmd --backend direct resume JOB_UUID --output recovered.json --allow-partial
healthmd --backend direct cancel JOB_UUID
```

A wait timeout, Ctrl-C, process exit, or connection loss does not cancel work. Reopen Health.md on the same paired iPhone and resume the same job. Resume never changes dates, settings, destination, or peer. Transport remains an explicit per-command choice (`manual-ip` is the default); use `--transport nearby` for a Nearby resume and repeat a custom Manual IP global `--port`. A cancel command records a cross-process durable cancellation request, so an already-running export CLI can deliver it over its authenticated channel. Only the iPhone acknowledgement makes cancellation terminal; an unavailable iPhone leaves `cancellation_pending` so cancellation can be delivered on a later retry. A file job's destination is bound into the stored request; the resume command does not accept a replacement destination.

## Security and storage

- Pairing uses ephemeral Curve25519 key agreement and domain-separated HMAC transcript proofs. A random reconnect secret is issued only inside the authenticated encrypted session.
- Every connection proves the stored reconnect secret, binds both installation IDs and fresh nonces/keys, and derives a fresh session key.
- Application messages and transfer frames use ChaCha20-Poly1305 authentication/encryption with serialized monotonic sequence envelopes that reject replay/out-of-order packets, including over already encrypted Nearby sessions.
- Manual IP is not plaintext even on LAN or Tailscale. Nearby requires `MCEncryptionPreference.required` and retains the application security layer.
- iPhone trust is in Keychain. Transfer spools are protected, backup-excluded app-container files. Terminal journals/spools are retained for idempotent acknowledgement/recovery until the fixed seven-day expiry, then activation/export cleanup removes them; unpairing removes trust, not an unexpired job ledger.
- Mac identity/jobs/spools live under `~/Library/Application Support/Health.md/CLI/Direct/v1` with owner-only directory/file permissions and are excluded from backup where supported. Pairing trust is stored in the Mac Keychain.
- `healthmd` has destination filesystem authority because direct file mode writes an explicitly supplied path. `healthmd-mcp` remains sandboxed and cannot use the direct backend.
- Status/progress logs may contain IDs, dates, counts, byte counts, and safe errors, but must not contain health samples, routes, clinical content, or raw payloads.

## Deterministic direct errors

Common machine-readable errors include:

| Error | Meaning |
|---|---|
| `direct_not_paired` | No matching trusted iPhone; pair or select `--device`. |
| `direct_device_not_paired` / `direct_device_selection_required` / `direct_unexpected_device` | The requested device is untrusted, multiple trusted devices require `--device`, or a job/connection does not match its pinned iPhone. |
| `direct_iphone_unavailable` | The selected explicit transport could not reach/authenticate the paired iPhone. |
| `backend_unsupported` | The command needs Mac-only encrypted context/catalog/MCP behavior. |
| `invalid_request` or an exit-2 usage error | A direct generated-file export omitted `--destination`, or a backend/option combination is invalid. |
| `invalid_direct_raw_response` | Raw manifest/body/date/schema/digest validation failed. |
| `unvalidated_response_too_large` | A result could not be exposed under bounded strict validation. |
| `invalid_direct_file_receipt` | Generated-file manifest/commit receipt did not validate. |
| `direct_cancellation_pending` | Local cancellation is durable but has not yet been acknowledged by the paired iPhone; keep it open and retry cancel. |
| `job_expired` | The fixed seven-day durable job/spool lifetime elapsed. |

Do not retry an unknown-outcome mutation blindly. Inspect `status --job`, reopen the same iPhone if needed, and use `resume`.

## Manual QA matrix

Physical-device release QA should cover both transports and at least:

1. first pairing, trusted reconnect, wrong code, wrong peer, and unpair on both sides;
2. Manual IP on LAN and a Tailscale address, plus Nearby discovery with no fallback;
3. status while foregrounded, backgrounding/foregrounding, locked/protected-data-unavailable state, and local-network denial;
4. one-day and seven-day strict raw, complete-empty and partial capture, a logical day spanning partitions, interrupted transfer, resume, and cancel;
5. overwrite, append, Markdown merge, Daily Notes Only, ZIP, roll-ups, provider sidecars, and idempotent interrupted replay into a disposable explicit destination;
6. traversal/symlink/destination-mutation rejection and insufficient disk space;
7. confirmation that query/evidence/refresh/MCP return `backend_unsupported` and never switch to the Mac app.
