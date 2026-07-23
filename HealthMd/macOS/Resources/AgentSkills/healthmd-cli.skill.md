---
name: healthmd-cli
description: Help a Health.md user operate the Health.md Mac CLI from a terminal or coding agent. Use whenever the user wants to install the healthmd command, check status/readiness, trigger Apple Health exports from an open connected iPhone, export yesterday/last N days/date ranges, request raw JSON, automate safe CLI runs, or understand/troubleshoot CLI JSON errors. This skill is for CLI users and consumers, not Health.md developers.
compatibility: Requires the Health.md macOS app running, local shell access, and an open connected Health.md iPhone app for exports. Use the installed `healthmd` command when available, or the bundled macOS app helper at `/Applications/Health.md.app/Contents/Helpers/healthmd`.
---

# Health.md CLI User Guide

Use this skill to help a Health.md user run the CLI safely. The CLI is a localhost client for the running Mac app. The Mac app coordinates with the already-open iPhone app, and the iPhone reads HealthKit.

## Mental model

```text
user or agent → healthmd CLI → Health.md Mac app → open iPhone app → HealthKit → canonical healthmd.health_data documents or Mac files
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

## Extract canonical data with selection pushdown

Prefer `healthmd extract` when a user or agent needs health values or source objects. It keeps `healthmd.health_data` v7 as the single source shape and tells the iPhone which metrics/detail to acquire before HealthKit queries run. Summary is the small default; lossless is explicit.

```bash
# Canonical Sleep-only daily documents; no lossless archive
NO_COLOR=1 TERM=dumb timeout 300 healthmd extract --category Sleep --last 7 </dev/null

# Only the canonical heart object, one document per line
NO_COLOR=1 TERM=dumb timeout 300 healthmd extract --metric resting_heart_rate --last 30 --object heart --format jsonl --output heart.jsonl </dev/null

# Lossless source records backing selected workouts
NO_COLOR=1 TERM=dumb timeout 300 healthmd extract --metric workouts --last 14 --object records --detail lossless --output workout-records.json </dev/null
```

Selectors are repeatable: `--metric`, `--category`, `--object`, `--field /JSON/POINTER`; explicit `--all-metrics` is available. `--source` currently accepts only `apple_health`. The CLI validates and removes raw job transport. JSON returns full v7 documents under `health_data`, or pointer/value/status entries under `projections`, plus an explicit receipt with every requested day and missing/partial diagnostics. A subtree projection never claims to be a complete v7 document. JSONL is one data item per line with its receipt on stderr or `OUTPUT.receipt.json`. Never interpret an omitted field as zero. Summary source documents correctly report `raw_capture_status: not_requested` because lossless records were not requested. Archive object selectors imply lossless detail. Partial runs do not emit retained data unless `--allow-partial` is explicit.

## Query arbitrary supported metrics

Metric queries are compatibility/derived views for calculations such as sessions, alignment, coverage, and comparison. Use canonical extraction above for original source objects. Queries carry their metric, source, date, and detail scope directly and do not change the iPhone's saved export metrics, formats, paths, or roll-ups. No pairing, token, credential, grant, or access profile is required; run doctor to check the local Mac/iPhone path.

```bash
NO_COLOR=1 TERM=dumb timeout 15 healthmd doctor --json </dev/null

# Discover canonical IDs
NO_COLOR=1 TERM=dumb timeout 15 healthmd metrics list --category Sleep </dev/null

# Fresh request-scoped iPhone acquisition, then a typed query
NO_COLOR=1 TERM=dumb timeout 300 healthmd query --category Sleep --from 2026-07-21 --to 2026-07-22 </dev/null

# Query the encrypted Mac context already acquired earlier
NO_COLOR=1 TERM=dumb timeout 30 healthmd query --metric sleep_total --yesterday --cached </dev/null

# First-class sessions automatically request lossless canonical stage metrics
NO_COLOR=1 TERM=dumb timeout 300 healthmd sleep sessions --last-nights 14 --all-pages </dev/null
```

Fresh queries request Apple Health only for the supplied metrics and dates and return a `healthmd.cli_metric_query` v1 envelope containing acquisition diagnostics plus the typed query response. A non-null nested `next_cursor` makes the outer status `partial_success`; use `--all-pages` for bounded automatic traversal, or follow cursors manually if its aggregate ceiling is reached. They never persist the temporary metric selection on iPhone. Fresh requested-scope success is tied to owner-day blobs replaced by that acquisition and to the requested source, so old cache cannot mask a failure.

HealthKit permission remains separate. Health.md checks decisions only for the requested ordinary types and never opens a surprise system sheet for a CLI request. If permission has not been decided, ask the user to authorize it on iPhone. Denied read access can still look like an empty result because of HealthKit privacy.

## Export commands

```bash
# Yesterday
NO_COLOR=1 TERM=dumb timeout 180 healthmd export --iphone --yesterday </dev/null

# Last 7 complete days ending yesterday
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 </dev/null

# Explicit inclusive date range
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --from 2026-06-01 --to 2026-06-07 </dev/null

# Write only selected Sleep summaries using the normal configured formats
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 --category Sleep --detail summary </dev/null

# Strict canonical daily JSON in the response; no files written
NO_COLOR=1 TERM=dumb timeout 180 healthmd export --iphone --yesterday --raw </dev/null

# Keep a partial raw result and opt into exit 0 (diagnostics are still printed)
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --last 7 --raw --allow-partial </dev/null

# Stream a multi-year raw corpus to an atomically committed file
NO_COLOR=1 TERM=dumb timeout 86400 healthmd export --iphone --last 3650 --raw --output health-corpus.json </dev/null

# Mirror saved iPhone export settings exactly, including roll-ups
NO_COLOR=1 TERM=dumb timeout 300 healthmd export --iphone --yesterday --use-iphone-settings </dev/null
```

Default CLI exports use the iPhone's saved output subfolder, formats, metrics, templates, filenames, and write behavior, but disable weekly/monthly/yearly roll-up summaries and summary-only mode for that one request. `--metric`/`--category`/`--all-metrics` with `--detail` replace saved metric/lossless scope only for that file job and reduce actual iPhone acquisition. The selected Mac destination is the root; Health.md appends the iPhone subfolder and folder organization. Use `--use-iphone-settings` only when the user specifically wants the iPhone app's saved settings exactly, including roll-ups.

Multi-year ranges are supported with no calendar-day cap. `--timeout` must be between 5 and 900 seconds and is reset by validated progress.

`--raw` requests strict `canonical_source_records_v1`. It temporarily enables Lossless Health Records without changing the saved iPhone `includeGranularData` setting, retains complete-empty and warning-only days, and returns public schema-v7 `healthmd.health_data` documents under `healthmd.raw_result` v1. Any partial, failed, unsupported, skipped, cancelled, or missing requested day/type produces `partial_success` and a non-zero exit unless `--allow-partial` is explicit. Current apps use 32–64 MiB checksum partitions with no 2 GiB aggregate cap, then stream the final validated JSON through a disk spool. Prefer `--output PATH` for a multi-year raw corpus; one dense HealthKit day and available storage remain practical limits. Older peers retain the legacy 2 GiB ceiling.

## Report results

Summarize only what the JSON proves:

- status: `success`, `partial_success`, `failure`, `cancelled`, `unavailable`, or `timed_out`
- job ID if present
- success count / total count if present
- files written and destination path for file exports
- canonical dates/schema and requested fields/objects for `extract`; do not paste values unless requested
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
| `invalid_strict_raw_success` | The Mac returned HTTP 200 but the strict raw dates/schema/profile/archive did not match the request | Treat the run as failed, update both apps, and keep the printed validation diagnostics; never accept the nested server response as canonical |
| `mac_destination_unavailable` | No selected/writable Mac folder for file exports | Ask the user to choose/reselect a folder, or use `--raw` if they only need JSON |
| `export_limit_reached` | Free export quota is exhausted | User must unlock Full Access on iPhone |
| `healthKitNotAuthorized` / `healthKitFetchFailed` | Permission, lock-state, or HealthKit fetch issue | Ask the user to unlock iPhone and verify Health permissions |
| `timed_out` | Export or fresh query took longer than the wait window | Check the returned durable job before retrying; use a longer timeout for large ranges |
| `removed_endpoint` | A caller is using a removed profiles or activity route | Update the caller to send metric/source/date/detail scope directly |
| `healthKitNotAuthorized` during query | Requested HealthKit type has no recorded permission decision | Open Health.md on iPhone and explicitly authorize the requested type |

Do not blindly retry. Run `healthmd status`, explain the blocking readiness field, and ask the user for the needed Mac/iPhone action.

## Safety and privacy

- Keep the iPhone app open/unlocked during fresh queries and exports.
- Keep Health.md's control API on loopback. Any local process can call query routes while the Mac app is open; never expose or proxy the port to another machine.
- Do not call this a fully headless cron replacement; iOS availability still matters.
- Do not modify exported Health.md files to fix a failed export. Rerun through Health.md so history, quota, and schema stay consistent.
- Do not log or share raw health data unless the user explicitly requests it.
- Protect files created with `--output`; they contain the same sensitive health corpus that would otherwise go to stdout.
