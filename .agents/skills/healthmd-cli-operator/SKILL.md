---
name: healthmd-cli-operator
description: Operate the standalone Health.md CLI against an open, paired iPhone. Use when the user asks to run pairing/status/export/extract/resume/cancel, automate an Apple Health export, inspect CLI JSON, or troubleshoot Manual IP/Tailscale connectivity without the Health.md macOS app.
compatibility: Requires the installed portable `healthmd` command on macOS, Linux, or Windows and a current Health.md iPhone app. Direct CLI Access is required for live commands. Generated-file destinations work on macOS/Linux in protocol v1; Windows supports raw and extract.
---

# Health.md CLI Operator

Use the installed standalone `healthmd`. Do not use the monorepo's `apps/apple/scripts/healthmd`; it runs the legacy Swift compatibility client. The Health.md macOS app is not required.

## Rules

- Direct Manual IP/Tailscale is the portable default. Never add `--backend mac-app` or `--transport nearby`.
- On macOS/Linux use `NO_COLOR=1 TERM=dumb`, a hard `timeout`, and stdin from `/dev/null`. Give exports longer bounds than status.
- Parse stdout JSON or the explicit output artifact. Pairing instructions and health-free progress may use stderr.
- Never infer success from exit status alone.
- Ask for physical iPhone actions when needed: open/unlock Health.md, enable Direct CLI Access, enter a code, approve local-network access, or grant HealthKit read access.
- Never print health values unless explicitly requested. Counts, dates, paths, statuses, and diagnostics are enough.
- Never retry an unknown-outcome export blindly. Inspect its durable job first.

```text
user/agent → standalone healthmd listener :17647
  ← authenticated encrypted LAN/Tailscale connection →
open paired iPhone → HealthKit → protected spool → output/destination
```

The Mac app, loopback port `17645`, Mac destination bookmark, and Mac app connection state are irrelevant.

## Preflight

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd --version </dev/null
NO_COLOR=1 TERM=dumb timeout 30 healthmd direct devices </dev/null
```

`direct devices` reads local trust without contacting iPhone. Pair if the intended iPhone is absent.

### Pair

```bash
NO_COLOR=1 TERM=dumb timeout 180 healthmd direct pair </dev/null
```

While it waits, tell the user to:

1. Open **Health.md → Settings → Mac Sync → Direct CLI Access** on iPhone.
2. Enable it and select **Manual IP**.
3. Enter a printed LAN/Tailscale address, port, and six-digit code.
4. Keep Health.md foregrounded through success.

Confirm stdout has `healthmd.direct_pairing_result`, `status: success`, and the intended device. After an unknown outcome, inspect `healthmd direct devices` rather than pairing again.

Pairing is normally one-time. Keep Direct CLI Access enabled and Health.md open for later commands. If several devices are trusted, add global `--device DEVICE_UUID`. If iPhone saved a non-default port, add global `--port PORT` to every network operation.

## Live readiness

```bash
NO_COLOR=1 TERM=dumb timeout 30 healthmd status </dev/null
```

Require:

- `backend == "direct"` and `mac_app == "bypassed"`;
- `iphone.connected == true`;
- `iphone.app_active == true` for new work;
- `iphone.protected_data_available == true`;
- `iphone.can_trigger_raw_exports == true` for raw/extract;
- `iphone.can_trigger_exports == true` for generated files;
- no conflicting `iphone.active_job_id`.

Ignore status `destination.selected`: direct file mode uses the command's explicit destination. If status fails, report its JSON and ask for the minimum action. Never switch device, port, transport, or backend silently.

## Strict raw

Prefer output files so health data does not enter logs:

```bash
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd export --yesterday --raw --output yesterday.json </dev/null

NO_COLOR=1 TERM=dumb timeout 600 \
  healthmd export --last 7 --raw --output week.json </dev/null

NO_COLOR=1 TERM=dumb timeout 600 \
  healthmd export --from 2026-07-01 --to 2026-07-07 \
    --raw --output range.json </dev/null
```

Use `--all` only when explicitly requested, with a protected path and a large outer timeout. Afterward inspect only status, job ID, requested/retained days, capture summary, missing dates, schema versions, and counts. Never dump the corpus.

A strict partial result exits nonzero unless `--allow-partial` is explicit. Do not add that flag merely to make automation green.

## Canonical extraction

```bash
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output sleep.json </dev/null

NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --metric workouts --last 14 \
    --object records --detail lossless --output workout-records.json </dev/null

NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 \
    --format jsonl --output sleep.jsonl </dev/null
```

Validate the receipt, selected dates/source/detail, and day outcomes. JSONL file output creates `OUTPUT.receipt.json`. Omitted fields are not zero. Incomplete extraction withholds values unless `--allow-partial` is explicit.

## Generated files

On macOS/Linux, use only an existing absolute destination chosen or approved by the user:

```bash
mkdir -p "$HOME/Documents/HealthVault"
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd export --yesterday \
    --destination "$HOME/Documents/HealthVault" </dev/null

NO_COLOR=1 TERM=dumb timeout 600 \
  healthmd export --last 7 --category Sleep --detail summary \
    --destination "$HOME/Documents/HealthVault" </dev/null
```

Do not guess a path, use a relative path, or reuse a Mac app bookmark. `--output` is raw/extract; `--destination` is generated-file mode.

Default jobs preserve saved formats, subfolder, templates, filenames, write mode, and Daily Note behavior while suppressing roll-ups and summary-only mode. Use `--use-iphone-settings` only when the user explicitly wants all saved behavior. Generated-file mode works on macOS, Linux, and Windows after validating an existing native absolute non-symlink destination.

## Durable jobs

After timeout, disconnect, `direct_export_paused`, or unknown final outcome:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300 --output recovered.json
```

`status --job` is local. Resume requires the same paired iPhone, device, port, and immutable request. Do not start a replacement job because the waiter stopped.

Cancel only on request:

```bash
healthmd cancel JOB_UUID
```

`direct_cancellation_pending` is not terminal. Keep the same iPhone open and retry cancel until acknowledged. Ctrl-C does not cancel.

## Report safely

Report only what CLI JSON, extraction receipt, or file receipt proves:

- status and job ID;
- requested/processed/retained days;
- files written and explicit destination;
- raw/extract schema and selection;
- missing/partial diagnostics;
- failure code and message.

Examples:

```text
Health.md completed the direct export: 7/7 days, 14 files committed under /Users/.../HealthVault.
```

```text
Health.md produced a complete strict raw result for yesterday: 1/1 day retained in yesterday.json.
```

Do not paste source records, routes, clinical content, measurements, or full raw output.

## Troubleshooting order

1. `healthmd direct devices` — local identity/trust.
2. `healthmd status --job JOB_UUID` — durable state after a started command.
3. `healthmd status` — live iPhone readiness.
4. Verify Direct CLI Access, foreground/protected-data state, address/port, local-network permission, device selection, and LAN/Tailscale reachability.
5. Resume the same durable job when appropriate.

| Error | Action |
|---|---|
| `direct_not_paired` | Pair once; do not open the Mac app. |
| `direct_device_selection_required` | Add the intended `--device`. |
| `direct_trust_invalid` | Preserve diagnostics; reset only with approval and forget on iPhone too. |
| `direct_storage_unavailable` | Restore native credentials. On macOS authorize the installed signed binary in Keychain Access or explicitly remove stale Health.md direct trust on both sides and re-pair; the CLI does not wait on hidden authorization UI. On Linux unlock/configure Secret Service. |
| `direct_iphone_unavailable` | Check app foreground, access toggle, address/port, permission, and reachability. |
| `direct_export_paused` | Inspect local job, reopen iPhone, and resume it. |
| `direct_cancellation_pending` | Reopen iPhone and retry cancel. |
| `invalid_direct_raw_response` | Do not consume output; retain validation diagnostics. |
| `invalid_direct_file_receipt` | Do not manually append/merge; inspect and resume if permitted. |
| `job_expired` | The seven-day deadline elapsed; confirm before starting a new request. |
| `transport_unsupported` | Use Manual IP/LAN/Tailscale, not Nearby. |
| `not_implemented` for `mac-app` | Remove the backend option; direct is default. |

## Privacy

- Never log raw stdout or use health values as troubleshooting evidence.
- Keep output and destination paths private and appropriately permissioned.
- Do not alter generated files to repair interrupted overwrite/append/merge operations.
- Do not claim fully unattended operation. Pairing and new work need a foreground iPhone; an active export gets only finite iOS background time.
