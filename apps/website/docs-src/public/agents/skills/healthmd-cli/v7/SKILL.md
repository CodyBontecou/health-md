---
name: healthmd-cli
description: Safely install and use the Health.md CLI and MCP server to query user-authorized health data, chart typed metrics, inspect sleep and workouts, export scoped Apple Health or Health Connect data, and recover durable jobs on macOS, Linux, or Windows. Use for consumer workflows, not Health.md development.
compatibility: Requires matching `healthmd` and `healthmd-mcp` binaries plus an explicitly compatible Health.md mobile build. Direct typed queries and canonical extraction currently require iPhone; Android supports provider-native raw and generated-file exports. Live work requires Direct CLI Access and the selected phone to be available.
---

# Health.md CLI

Use the standalone `healthmd` command. Health.md for Mac is not required.

```text
agent/user → healthmd on macOS, Linux, or Windows
  ← authenticated encrypted Manual IP or Tailscale connection →
foreground Health.md mobile app → HealthKit or Health Connect
  → bounded typed results, canonical data, or generated files
```

The CLI listens on the computer; the phone connects to the displayed address. It can keep an unavailable request waiting while the user opens Health.md. Published alpha.6 binaries are wait-only; subsequent official builds also send one best-effort APNs notification when the selected iPhone has enrolled wake material. Android and unenrolled phones remain wait-only. A notification can restore user presence but never authorizes background health access or bypasses app activity, permissions, protected-data controls, quotas, or OS background limits. Direct is the portable default. Do not add `--backend mac-app` or `--transport nearby`.

## Authorization and privacy first

Treat the user's request as authority only for its stated device, operation, metrics/categories, dates, sources, detail, destination, and disclosure level. Ask before widening any of them.

- Default to the smallest useful date and metric scope.
- Get explicit approval before pairing, returning health values in chat, using `--all`, requesting lossless records, enabling `--allow-partial`, writing generated files, changing trust, or deleting state.
- Use a user-approved private absolute path outside a repository for health artifacts. Do not assume a synced or shared folder is private.
- Pairing QR images and fallback codes contain short-lived secrets. Render them only to the user; never transcribe, reconstruct, upload, or log them.
- Local stdio means Health.md itself needs no health-data cloud. It does **not** guarantee local model inference: the MCP host or model provider may process returned values under its own policies.
- Do not diagnose, recommend treatment, infer causation, or label a result healthy, harmful, better, or worse. Preserve exact metric IDs, statistics, units, dates/timezone, source, coverage, missingness, evidence, and limitations.
- Never merge HealthKit HRV SDNN with Health Connect or WHOOP HRV RMSSD.

## Verify release compatibility

The `0.1.0-alpha.6` package is an explicitly unqualified public preview. Physical QA has confirmed basic iPhone and Android connectivity, but no public CLI/mobile pair has completed and retained the full release qualification matrix yet. Its source snapshot contains these exact counterparts:

| Mobile source | Protocol | Exact counterpart in the release snapshot | Portable operations |
|---|---|---|---|
| iPhone exports | v1 | iOS 3.3.0 (build 202609032317) | status, raw, extract, files, resume, cancel |
| iPhone typed queries | v1 + query v3 | iOS 3.3.0 (build 202609032317) | the export operations plus fixed typed query tools |
| Android exports | v2 | Android 1.8.2 (`versionCode 31`) | status, provider-native raw, files, resume, cancel |
| Android typed queries | unavailable | not implemented | do not claim support |

The unqualified protocol floors remain iOS 3.0.3 and Android 1.5.4 (`versionCode 25`), but protocol implementation and basic connectivity are not release qualification. Check the exact package and mobile build before live work. Do not claim App Store or Play Store compatibility from a marketing version alone.

Authoritative ledger: <https://github.com/CodyBontecou/health-md/blob/main/apps/cli/docs/mobile-compatibility.md>

## Install or verify

```bash
healthmd --version
healthmd --help
```

On macOS or Linux, install the matching preview binaries together:

```bash
brew install CodyBontecou/tap/healthmd
```

For Windows or direct archive installation, use the exact `healthmd-cli/v<version>` GitHub Release—not repository `/releases/latest`—and follow that release's checksum, Sigstore, and publisher-verification instructions. Do not mix `healthmd` and `healthmd-mcp` versions.

Authorized preview testers may build the exact tag from source:

```bash
git clone https://github.com/CodyBontecou/health-md.git
cd health-md
git checkout healthmd-cli/v0.1.0-alpha.6
cd apps/cli
cargo install --locked --path crates/healthmd-cli
```

Do not use `apps/apple/scripts/healthmd`; it runs the legacy Swift compatibility client. Linux requires an unlocked freedesktop Secret Service provider such as GNOME Keyring or KWallet. The CLI never falls back to plaintext credentials.

## Bound unfamiliar commands

Use the CLI's non-network discovery mode instead of guessing required flags. These commands exit
successfully with `healthmd.cli_guidance/1`, `status: guidance`, and `request_sent: false` without
opening credentials or contacting a phone:

```bash
healthmd export
healthmd extract
healthmd query
healthmd query healthmd_sleep_sessions
healthmd resume
healthmd cancel
healthmd direct
healthmd mcp
```

A selected query operation returns its complete `input_schema`, JSON examples, and an `argv` array.
Malformed or runtime failures return `healthmd.cli_error/1` with `help_command` and bounded
`next_actions`; follow those fields instead of scraping `message` or retrying blindly.

On macOS/Linux use non-interactive execution and a hard process timeout:

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd --version </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd direct devices </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
```

On Windows, use the automation host's process timeout. Give pairing and exports longer bounds than status. Interactive terminals render command guidance, failures, and structured results as readable text; non-interactive pipes and explicit `--json` emit JSON. Use `--json` whenever an agent must parse the result. Explicit health streams/artifacts retain their exact bytes, and MCP server startup/transport diagnostics cannot use stdout because MCP reserves it for JSON-RPC. Health-free progress and pairing instructions may use stderr. Parse `schema` and `status` or the receipt; never infer execution success from exit status alone—a zero exit can intentionally mean non-network guidance.

## Pair once

Pairing creates durable export authority, so obtain approval first:

```bash
NO_COLOR=1 TERM=dumb timeout 180 healthmd direct pair </dev/null
```

For iPhone:

1. In foreground Health.md, open **Sync → CLI** and enable **Direct CLI Access**.
2. Tap **Scan Pairing QR** and scan the displayed image. The in-app scan starts pairing; do not ask for a second Pair tap or open the QR as a custom URL.
3. If scanning is unavailable, select **Manual IP** and enter the printed address, port, and shared 20-digit code. The six-digit Apple code is only a legacy-CLI fallback.

For Android, open **Settings → Direct CLI**, tap **Scan pairing QR**, and scan the same universal image, or enter the same address, port, and shared 20-digit code manually. Camera access is optional. Keep the selected app active through success.

Confirm stdout is `healthmd.direct_pairing_result` with `status: success` for the intended phone. After an unknown outcome, inspect `healthmd direct devices`; do not pair again blindly. Use global `--device DEVICE_UUID` when several phones are trusted and global `--port PORT` when the app saved a non-default port.

Local trust commands do not contact the phone:

```bash
healthmd direct devices
healthmd direct unpair DEVICE_UUID
```

Run `healthmd direct reset-trust --confirm` only with explicit approval. It removes every local pairing; the user must forget the CLI on each phone too.

## Bounded wake window

Live query, export, extract, resume, and cancel commands wait up to 120 seconds for the selected
phone to become active. Tell the user that the request is waiting and ask them to unlock the phone
and open Health.md; the same in-flight command should continue without a re-run. Use
`--wake-timeout SECONDS` for a different command window or `--wake-timeout 0` only when fail-fast
behavior is explicitly needed. Keep any outer process timeout longer than the wake window plus the
operation timeout.

MCP uses `HEALTHMD_WAKE_TIMEOUT` (`0` disables) and may emit `notifications/progress`. Inspect the
selected device's `wake_window`: published alpha.6 binaries do not send push, even if enrollment
metadata exists. In a subsequent official build, `available`/`enrolled` for an enrolled iPhone means
the wait sends one best-effort APNs notification through Health.md's health-free wake service. Only
tell the user to expect a notification when both the build and enrollment support it. Android and
unenrolled iPhones remain wait-only. A local timeout or MCP cancellation ends only the waiter; it is not phone-side
durable-job cancellation.

## Check readiness

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
```

Require the selected phone to be authenticated, active enough for new work, and ready for the requested operation. Respect `active_job_id` and all protected-data, permission, and capability fields. `backend: direct` and `mac_app: bypassed` confirm the standalone path. Direct generated-file mode always uses the explicit `--destination`; it never uses a Mac bookmark.

## Query typed health data

Typed queries currently require a compatible foreground iPhone. For least privilege, pair outside the MCP host and configure:

```bash
healthmd mcp serve-read-only
```

This local stdio profile exposes only readiness, catalog, and typed-query tools. Use full `healthmd mcp serve` only when the user also approves in-host pairing or generated-file job authority. For Codex, `healthmd setup codex` configures the full local profile and can open pairing; review that broader authority with the user first.

Query workflow:

1. Call `healthmd_doctor` before reading health values.
2. Use `healthmd_metrics` to obtain canonical IDs instead of guessing.
3. Resolve relative dates to exact inclusive dates in the user's intended calendar/timezone.
4. Prefer `healthmd_metric_chart` for metric series, `healthmd_sleep_sessions` for sleep, and `healthmd_workouts` for workouts. Use fixed comparison, coverage, alignment, or evidence tools when they match the question.
5. Set `all_pages: true` only when complete bounded traversal is needed, or continue the exact opaque `next_cursor` unchanged.
6. Report requested-scope completion separately from unrelated corpus warnings.

Inspect the exact schema offline before constructing shell arguments. The `query OPERATION` form
returns the same nested schema plus an executable argv example:

```bash
healthmd query healthmd_metric_chart
healthmd query healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema healthmd_sleep_sessions
```

The shell can execute the identical fixed operation without an MCP envelope:

```bash
healthmd query healthmd_metric_chart \
  --arguments '{"metrics":{"type":"explicit","metric_ids":["resting_heart_rate"]},"dates":{"type":"exact","range":{"start_date":"2026-07-01","end_date":"2026-07-07"}},"all_pages":true}'
```

Dates are illustrative; resolve the user's actual request. `healthmd extract` is a source-data projection, not the typed query API.

## Export or extract only approved scope

Choose exactly one date range: `--yesterday`, `--last N`, `--from/--to`, or `--all`. Prefer an approved protected absolute output path so health data does not enter stdout, transcripts, or a repository. In the examples, first set `PRIVATE_HEALTH_DIR` to an existing private absolute directory selected by the user; never guess or create that location silently.

### iPhone strict raw and canonical extraction

```bash
healthmd export --yesterday --raw --output "$PRIVATE_HEALTH_DIR/yesterday.json"
healthmd extract --category Sleep --last 7 \
  --output "$PRIVATE_HEALTH_DIR/sleep.json"
healthmd extract --metric workouts --last 14 --object records --detail lossless \
  --output "$PRIVATE_HEALTH_DIR/workout-records.json"
```

Strict iPhone raw returns `healthmd.raw_result` v1 containing schema-v8 `healthmd.health_data` documents and temporarily requests canonical lossless records without changing saved settings. Extraction returns selected canonical documents or honest projections plus `healthmd.extract_receipt`. JSONL file output writes `OUTPUT.receipt.json`.

Complete-empty is success. Missing, failed, cancelled, unsupported, skipped, or partial requested capture yields `partial_success` and a nonzero exit unless the user explicitly accepts `--allow-partial`. Never interpret an omitted field as zero.

### Android provider-native raw

```bash
healthmd export --last 7 --raw --provider health_connect --raw-format ndjson \
  --output "$PRIVATE_HEALTH_DIR/health-connect.ndjson"
```

Android raw remains provider-native. Never relabel it as HealthKit-shaped `healthmd.health_data`, and never fabricate typed-query or canonical-extraction support.

### Production-generated files

Use an existing user-approved absolute non-symlink destination:

```bash
healthmd export --yesterday --destination "$PRIVATE_HEALTH_DIR"
healthmd export --yesterday --use-device-settings --destination "$PRIVATE_HEALTH_DIR"
healthmd export --last 7 --profile PROFILE_UUID --destination "$PRIVATE_HEALTH_DIR"
```

`--output` is for raw/extract; `--destination` is for generated files. `--use-device-settings` mirrors the selected phone's saved behavior and cannot combine with selectors. A profile resolves frozen mobile output settings while `--destination` remains the required explicit computer folder. Android generated-file jobs use saved settings or a profile; iPhone-only metric/category/detail selectors must not be sent to Android.

The CLI validates manifests, digests, paths, symlinks, destination identity, and restart-safe overwrite/append/Markdown merge commits. Do not manually repair generated files after an interrupted job.

## Recover durable jobs

Jobs persist for seven days. Timeout, Ctrl-C, process exit, disconnect, or exhausted phone background time does not cancel them.

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output "$PRIVATE_HEALTH_DIR/recovered.json"
healthmd cancel JOB_UUID
```

Inspect status before deciding what to do. Resume the same immutable request against the same phone; never create a duplicate after an unknown outcome. Cancel only on request. Cancellation is terminal only after phone acknowledgement.

## Report safely

Unless the user explicitly asked for health values, report only:

- operation and exact approved scope;
- status and durable job ID;
- requested, processed, and retained dates/counts;
- schema, source, detail, and traversal completion;
- files written and explicit destination;
- missing/partial diagnostics, limitations, and error code/message.

When values were requested, also preserve canonical units/statistics, owner dates/timezone, source evidence, coverage, and missing intervals. Do not paste raw records, routes, clinical text, medications, mood entries, attachments, device/source metadata, or credentials without separate explicit need.

## Troubleshooting order

1. `healthmd direct devices` — local trust and selected identity.
2. `healthmd status --job JOB_UUID` — durable state after any started operation.
3. `healthmd status` or `healthmd_doctor` — live readiness.
4. Verify the selected phone, foreground state, Direct CLI Access, address/port, local-network permission, native credential storage, and LAN/Tailscale reachability.
5. Resume the same job when appropriate; never switch peer, transport, port, or backend silently.

Common actions:

| Error | Next action |
|---|---|
| `direct_not_paired` | Ask before pairing; no Mac app is involved. |
| `direct_device_selection_required` | Ask the user to select the intended trusted phone. |
| `direct_trust_invalid` | Preserve diagnostics; reset only with approval and forget both sides. |
| `direct_storage_unavailable` | Restore Keychain, Secret Service, or Credential Manager access; never use plaintext. |
| `direct_iphone_unavailable` | Check iPhone foreground state, access, address/port, permission, and reachability. |
| `direct_export_paused` | Inspect the durable job, reopen the same phone, and resume it. |
| `query_scope_too_large` | Partition dates or metric IDs; do not treat it as missing data. |
| `direct_cancellation_pending` | Reopen the same phone and retry cancellation until acknowledged. |
| `invalid_direct_raw_response` | Do not consume output; retain health-free validation diagnostics. |
| `invalid_direct_file_receipt` | Do not append or merge manually; inspect and resume if allowed. |
| `partial_canonical_extraction` | Review diagnostics; accept partial data only with explicit approval. |
| `transport_unsupported` | Use Manual IP over LAN/Tailscale, not Nearby. |
| `not_implemented` with `mac-app` | Remove the backend option; direct is default. |
