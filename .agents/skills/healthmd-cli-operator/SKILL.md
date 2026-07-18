---
name: healthmd-cli-operator
description: Use the Health.md Mac CLI to check readiness and trigger Apple Health exports from an already-open connected iPhone to the Mac destination folder. Use whenever the user asks to run healthmd export/status, automate a Health.md export from terminal, trigger an iPhone export from Mac, export yesterday/last N days/date ranges via CLI, inspect CLI JSON output, or troubleshoot why the CLI cannot reach the Mac app/iPhone.
compatibility: Requires this repo checkout, the Health.md macOS app running, an open connected Health.md iOS app for exports, and local shell access. Uses scripts/healthmd and localhost 127.0.0.1:17645.
---

# Health.md CLI Operator

Use this skill to operate the project CLI from any automation-capable coding environment. The CLI talks to the running Health.md Mac app over `127.0.0.1:17645`; the Mac app forwards export requests to an already-open connected iPhone, then writes files under the selected Mac destination root using the iPhone's saved output subfolder and folder organization. CLI exports default to requested dates only: they keep the iPhone's saved output path, formats, metrics, and write behavior but disable weekly/monthly/yearly roll-up summaries and summary-only mode for that one request.

## Agent-agnostic operating rules

- Treat `scripts/healthmd` as the stable entry point from this repo. Do not rely on a specific assistant product, IDE, or proprietary tool.
- Use bounded, non-interactive shell commands: set `NO_COLOR=1 TERM=dumb`, wrap with `timeout`, and redirect stdin from `/dev/null`.
- Parse the JSON the CLI prints; do not infer success from prose, app UI assumptions, or exit code alone.
- Ask the user for physical-device actions when needed: launch the Mac app, open/unlock the iPhone app, grant HealthKit access, or select a Mac destination folder.
- Report only operational facts proven by CLI JSON or direct file/history inspection.

## Mental model

```text
agent/user → scripts/healthmd → Health.md Mac app → open iPhone app → HealthKit read → Mac export job → Mac destination folder
```

The CLI does not read HealthKit, does not wake iOS reliably, and does not bypass iPhone lock-state protections. Treat failures as useful readiness signals, not as reasons to retry blindly.

## First checks

From the repo root:

```bash
NO_COLOR=1 TERM=dumb timeout 15 scripts/healthmd status </dev/null
```

Read the JSON:

- `mac_app == "running"`: localhost control server is reachable.
- `iphone.connected == true`: Mac app has a Multipeer connection to iPhone.
- `iphone.can_trigger_exports == true`: iPhone supports Mac-initiated exports and Mac destination is ready.
- `destination.selected == true` and `destination.writable == true`: Mac can write export files.
- `iphone.can_trigger_raw_exports == true`: the connected iPhone can return raw JSON to the CLI. This does not require a selected Mac destination folder.
- `active_export != null`: wait for current export to finish before starting another.

If `mac_app_unreachable`, ask the user to launch the Health.md macOS app, then re-run status.

## Export commands

Use generous timeouts because HealthKit reads and large Mac transfers can take time.

```bash
# Yesterday
NO_COLOR=1 TERM=dumb timeout 180 scripts/healthmd export --iphone --yesterday </dev/null

# Last 7 complete days ending yesterday
NO_COLOR=1 TERM=dumb timeout 300 scripts/healthmd export --iphone --last 7 </dev/null

# Explicit date range, inclusive
NO_COLOR=1 TERM=dumb timeout 300 scripts/healthmd export --iphone --from 2026-06-01 --to 2026-06-07 </dev/null

# Return strict canonical daily JSON instead of writing files
NO_COLOR=1 TERM=dumb timeout 180 scripts/healthmd export --iphone --yesterday --raw </dev/null

# Explicitly accept partial raw capture while retaining diagnostics
NO_COLOR=1 TERM=dumb timeout 300 scripts/healthmd export --iphone --last 7 --raw --allow-partial </dev/null

# Use the iPhone app's saved settings exactly, including roll-ups
NO_COLOR=1 TERM=dumb timeout 300 scripts/healthmd export --iphone --yesterday --use-iphone-settings </dev/null
```

The command prints JSON. File exports retain their existing successful `success`/`partial_success` exit behavior. Strict `--raw` returns versioned `raw_result` canonical documents and exits non-zero on `partial_success` unless `--allow-partial` is explicit; always report its per-day diagnostics. Treat `failure`, `unavailable`, `timed_out`, and `cancelled` as non-successes and report the `message` plus `failure_reason`.

## Before running an export

1. Run `scripts/healthmd status`.
2. Confirm `iphone.can_trigger_exports` is true for file-writing exports, or `iphone.can_trigger_raw_exports` is true for `--raw` exports.
3. Confirm no `active_export` is present.
4. Confirm the requested date range is valid; multi-year corpus exports are supported.
5. Tell the user if the operation depends on the iPhone staying open/unlocked and that very large raw exports remain subject to transport-byte and memory limits.

## After running an export

Summarize only what the JSON proves:

- status
- job ID
- success count / total count
- files written, or retained-day and sample/record/query counts plus missing/partial diagnostics when using `--raw`
- destination path if present
- failure reason/message if not successful

Example response:

```text
Health.md export completed: 7/7 days, 14 files written to /Users/.../Vault.
```

For partial success:

```text
Health.md exported 5/7 days and wrote 10 files. Two days had no HealthKit data; check Export History for details.
```

## Troubleshooting map

| JSON/error | Likely cause | Next action |
|---|---|---|
| `mac_app_unreachable` | Mac app/control server is not running | Ask user to open Health.md Mac app |
| `iphone_not_connected` | iPhone app is not connected to Mac | Ask user to open Health.md on iPhone and Mac Destination screen if needed |
| `unsupported_iphone` | iPhone build lacks this protocol | Ask user to update/build the iOS app |
| `unsupported_raw_profile` | iPhone lacks the strict canonical archive/raw-result versions | Update both apps; do not downgrade the raw request |
| `invalid_strict_raw_success` | HTTP 200 contained wrong dates or incompatible/missing strict schemas/archive | Treat as failure, preserve the printed validation diagnostics, and update both apps; do not consume `server_response` as canonical data |
| `mac_destination_unavailable` | No folder, denied bookmark, or Mac busy for a file-writing export | Ask user to choose/reselect destination folder, wait, or use `--raw` if they only need JSON |
| Duplicated/nested output path | Mac destination is a nested Health.md output folder instead of the equivalent vault/root | Re-select the equivalent vault/root on Mac; the iPhone subfolder is appended automatically |
| `export_limit_reached` | Free quota exhausted | User must unlock Full Access on iPhone |
| `healthKitNotAuthorized` / `healthKitFetchFailed` | HealthKit permission/lock/data issue | Ask user to unlock iPhone and verify Health permissions |
| `timed_out` | Export preparation/transfer exceeded wait window | Check status and Export History before retrying |

## Safety and privacy constraints

- By default, CLI exports should not create weekly/monthly/yearly roll-up summary files or use summary-only mode. If they do, confirm the command included `--use-iphone-settings` intentionally and that both apps are current.
- Do not claim the CLI is fully headless cron unless the user keeps iPhone available/open.
- Do not request or expose health data in chat unless the user explicitly asks and the CLI output includes it. The CLI normally returns counts and paths, not health samples.
- Do not modify export files to “fix” a failed export; rerun through Health.md so history, quota, and schema remain consistent.
