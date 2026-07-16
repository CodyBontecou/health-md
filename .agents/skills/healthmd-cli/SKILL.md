---
name: healthmd-cli
description: Help a Health.md user operate the Health.md Mac CLI from a terminal or coding agent. Use whenever the user wants to install the healthmd command, check status/readiness, trigger Apple Health exports from an open connected iPhone, export yesterday/last N days/date ranges, request raw JSON, automate safe CLI runs, or understand/troubleshoot CLI JSON errors. This skill is for CLI users and consumers, not Health.md developers.
compatibility: Requires the Health.md macOS app running, local shell access, and an open connected Health.md iPhone app for exports. Use the installed `healthmd` command when available, or the bundled macOS app helper at `/Applications/Health.md.app/Contents/Helpers/healthmd`.
---

# Health.md CLI User Guide

Use this skill to help a Health.md user run the CLI safely. The CLI is a localhost client for the running Mac app. The Mac app coordinates with the already-open iPhone app, and the iPhone reads HealthKit.

## Mental model

```text
user or agent → healthmd CLI → Health.md Mac app → open iPhone app → HealthKit → Mac destination folder or raw JSON response
```

The CLI does not read HealthKit itself, does not reliably wake the iPhone app, and does not bypass lock-state or permission protections. Treat failures as readiness signals with clear next steps.

## Use bounded commands

When running commands from an agent or script, use non-interactive bounded shell commands:

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd status </dev/null
```

For exports, use longer timeouts because HealthKit fetches and Mac transfers can take time:

```bash
NO_COLOR=1 TERM=dumb timeout 180 healthmd export --iphone --yesterday </dev/null
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 </dev/null
```

If `healthmd` is not on PATH, use the bundled helper path shown in the Health.md Mac app's CLI tab, usually:

```bash
/Applications/Health.md.app/Contents/Helpers/healthmd
```

## Install or verify the CLI

First verify the command exists:

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd --help </dev/null
```

If it is not installed, ask the user to use the Health.md Mac app's CLI tab to copy either:

- a shell alias for the current terminal session, or
- a symlink command for `~/.local/bin/healthmd`.

Do not edit shell startup files unless the user explicitly approves. If `~/.local/bin` is not on PATH, tell the user the line to add:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Check readiness before exporting

Run:

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd status </dev/null
```

Read the JSON fields:

- `mac_app == "running"`: the Mac app's local control server is reachable.
- `iphone.connected == true`: the iPhone app is connected to the Mac app.
- `iphone.can_trigger_exports == true`: file-writing exports can run.
- `iphone.can_trigger_raw_exports == true`: raw JSON exports can run.
- `destination.selected == true` and `destination.writable == true`: Mac file exports can write to the chosen folder.
- `active_export == null`: no export is currently running.

For file-writing exports, require `iphone.can_trigger_exports == true`.
For raw JSON exports, require `iphone.can_trigger_raw_exports == true`; raw mode can work without a selected Mac destination folder.

## Export commands

```bash
# Yesterday
NO_COLOR=1 TERM=dumb timeout 180 healthmd export --iphone --yesterday </dev/null

# Last 7 complete days ending yesterday
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 </dev/null

# Explicit inclusive date range
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --from 2026-06-01 --to 2026-06-07 </dev/null

# Strict canonical daily JSON in the response; no files written
NO_COLOR=1 TERM=dumb timeout 180 healthmd export --iphone --yesterday --raw </dev/null

# Keep a partial raw result and opt into exit 0 (diagnostics are still printed)
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 --raw --allow-partial </dev/null

# Mirror saved iPhone export settings exactly, including roll-ups
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --yesterday --use-iphone-settings </dev/null
```

Default CLI exports use the iPhone's saved output subfolder, formats, metrics, templates, filenames, and write behavior, but disable weekly/monthly/yearly roll-up summaries and summary-only mode for that one request. The selected Mac destination is the root; Health.md appends the iPhone subfolder and folder organization. Use `--use-iphone-settings` only when the user specifically wants the iPhone app's saved settings exactly, including roll-ups.

Date ranges are capped at 366 days. `--timeout` must be between 5 and 900 seconds.

`--raw` requests the strict `canonical_source_records_v1` profile. It temporarily enables granular source-record capture without changing the saved iPhone toggle, retains complete empty and warning-only days, and returns public `healthmd.health_data` documents under a versioned `raw_result` envelope. Any partial, failed, cancelled, or missing day/type produces `partial_success` and a non-zero CLI exit unless `--allow-partial` is explicit. An older iPhone that cannot advertise the required canonical archive/raw-result versions is rejected rather than silently downgraded.

## Report results

Summarize only what the JSON proves:

- status: `success`, `partial_success`, `failure`, `cancelled`, `unavailable`, or `timed_out`
- job ID if present
- success count / total count if present
- files written and destination path for file exports
- retained day count, per-day status, sample/record/query counts, integrity/partial diagnostics, and missing dates for `--raw`
- failure reason and message for non-success responses

Good concise examples:

```text
Health.md export completed: 7/7 days, 14 files written to /Users/.../Vault.
```

```text
Health.md returned complete canonical raw JSON for yesterday: 1/1 day retained, 42 source records. No files were written.
```

Do not paste health samples into chat unless the user explicitly asks and understands that raw mode may expose health data.

## Troubleshooting

| JSON/error | What it usually means | Next action |
|---|---|---|
| `mac_app_unreachable` | Health.md Mac app is not running or not reachable | Ask the user to open Health.md on Mac, then run status again |
| `iphone_not_connected` | iPhone app is not connected to Mac | Ask the user to unlock iPhone, open Health.md, and wait for Mac Destination connection |
| `unsupported_iphone` | iPhone app version lacks the CLI export protocol | Ask the user to update Health.md on iPhone |
| `unsupported_raw_profile` | Connected iPhone cannot provide strict canonical raw results | Update Health.md on both Mac and iPhone; do not retry as a downgraded raw request |
| `mac_destination_unavailable` | No selected/writable Mac folder for file exports | Ask the user to choose/reselect a folder, or use `--raw` if they only need JSON |
| `export_limit_reached` | Free export quota is exhausted | User must unlock Full Access on iPhone |
| `healthKitNotAuthorized` / `healthKitFetchFailed` | Permission, lock-state, or HealthKit fetch issue | Ask the user to unlock iPhone and verify Health permissions |
| `timed_out` | Export took longer than the wait window | Check status and app history before retrying; use a longer timeout for large ranges |

Do not blindly retry. Run `healthmd status`, explain the blocking readiness field, and ask the user for the needed Mac/iPhone action.

## Safety and privacy

- Keep the iPhone app open/unlocked during exports.
- Do not call this a fully headless cron replacement; iOS availability still matters.
- Do not modify exported Health.md files to fix a failed export. Rerun through Health.md so history, quota, and schema stay consistent.
- Do not log or share raw health data unless the user explicitly requests it.
