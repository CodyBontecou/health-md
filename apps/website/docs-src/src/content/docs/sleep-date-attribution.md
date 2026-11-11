---
title: "Sleep dates and daily notes"
description: "Choose the right sleep export date: understand Health.md's noon-to-noon journal window, after-midnight bedtimes, naps, and empty results."
---

**Night begins** is the default on iPhone and Android. For last night's sleep on Tuesday morning, export **Monday**, usually **Yesterday**. Health.md's daily sleep summary uses a local **12:00 to 12:00** journal window: Monday noon through Tuesday noon. It does not use the midnight boundary of ordinary activity summaries.

Choose **Morning ends** in export settings to assign each whole sleep session to the date it ends, in the export's time zone, without clipping at noon. For Monday night's sleep ending Tuesday, export **Tuesday (Today)**; Tuesday naps also belong to Tuesday. A changed setting applies to new operations; saved operations keep their accepted attribution.

<div id="sleep-journal-window"></div>

## Why sleep can appear in yesterday's note

The journal window keeps a typical night together even when bedtime is after midnight. The start noon is included; the following noon is excluded. Sleep crossing a noon boundary can contribute to adjacent daily summaries. Source timestamps are not rewritten to match a note's date.

Both sleep attribution modes are available on Apple and Android. Available metrics, stages, source records and aggregation can still differ by platform.

<div id="sleep-date-examples"></div>

## Which date should I export?

**Night begins:** These are fictional local-time examples, not health records:

| Sleep or activity | Export date |
| --- | --- |
| Monday 23:45 to Tuesday 07:30 | **Monday** |
| Tuesday 01:00 to Tuesday 07:30 | **Monday**, not Tuesday |
| Tuesday nap, 14:00 to 14:30 | **Tuesday** |
| Tuesday's steps and activity | **Tuesday** |
| Monday night's sleep and Tuesday's activity | **Monday and Tuesday** |

Use the export's local timezone when checking the window. A source app's wake-date label or a file's modification time does not establish Health.md's journal date.

<div id="sleep-empty-checks"></div>

## If the expected note is empty

1. Check the journal date above and enable the sleep metrics you want.
2. Let the watch or source app synchronize into Apple Health or Health Connect, then preview and export that journal day again.
3. Review category access. On iPhone, an empty HealthKit result cannot tell you whether read access was denied. On Android, confirm the source actually wrote the supported record to Health Connect.
4. Inspect the selected destination and written, skipped or failed result. Preview is not proof that a file was saved. Missing is not zero.

Daily Note Injection and API Endpoint summaries use the operation's selected sleep attribution. For late source updates, export the owner date for that mode or review the schedule's lookback. Background timing is a target, not a guaranteed successful write.

<div id="sleep-records-and-queries"></div>

## Summaries, source records and session queries

Raw or canonical records have their own ownership rules and retain original timestamps. Do not reconstruct session boundaries from a daily total or add source intervals to that total as extra sleep.

**Night begins:** On Apple, the raw archive assigns records by their source start within the local midnight-to-midnight day. The sleep summary instead clips intervals to the noon-to-noon journal window. A successful raw Sleep Analysis query can therefore contain morning records while that date's sleep summary is empty. Export the preceding journal date and check `time_context.calendar_timezone` before diagnosing a missing summary. For example, records from September 22 at 04:03–11:52 UTC belong entirely to September 21's summary in UTC; in Europe/Lisbon, the final 52 minutes fall after local noon and contribute to September 22 instead.

Staged sleep does not require an explicit `inBed` record: Apple summaries use the union of available asleep stages when it is absent. Missing in-bed data does not create an in-bed duration. A failed summary query should appear in `diagnostics.partial_failures`; a successful query with no qualifying intervals is valid absence. Resting heart rate uses a separate calendar-day query and requires an actual resting-heart-rate measurement; sleep stages or read permission alone do not supply one.

On a supported **Apple Health** CLI/MCP setup, `healthmd_sleep_sessions` provides session queries. Android typed MCP queries are not currently supported. Check [platform capabilities](/docs/guides/platform-features/) and the [MCP guide](/docs/mcp/) for the chosen setup.

See [scheduling](/docs/scheduling/) for lookback and timing, [troubleshooting](/docs/troubleshooting/) for empty reads versus failed writes, and [export formats](/docs/format/) for detail and coverage.
