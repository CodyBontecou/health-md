---
title: "Sleep dates and daily notes"
description: "Choose the right sleep export date: understand Health.md's noon-to-noon journal window, after-midnight bedtimes, naps, and empty results."
---

For last night's sleep on Tuesday morning, export **Monday**, usually **Yesterday**. Health.md's daily sleep summary uses a local **12:00 to 12:00** journal window: Monday noon through Tuesday noon. It does not use the midnight boundary of ordinary activity summaries.

<div id="sleep-journal-window"></div>

## Why sleep can appear in yesterday's note

The journal window keeps a typical night together even when bedtime is after midnight. The start noon is included; the following noon is excluded. Sleep crossing a noon boundary can contribute to adjacent daily summaries. Source timestamps are not rewritten to match a note's date.

This sleep-summary window is shared by Apple and Android compatibility exports. Available metrics, stages, source records and aggregation still differ by platform. There is no setting that moves the daily summary to a wake-date convention.

<div id="sleep-date-examples"></div>

## Which date should I export?

These are fictional local-time examples, not health records:

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

Daily Note Injection and API Endpoint summaries follow the same journal window. For late source updates, repeat the journal day or review the configured schedule's lookback. Background timing is a target, not a guaranteed successful write.

<div id="sleep-records-and-queries"></div>

## Summaries, source records and session queries

Raw or canonical records have their own ownership rules and retain original timestamps. Do not reconstruct session boundaries from a daily total or add source intervals to that total as extra sleep.

On a supported **Apple Health** CLI/MCP setup, `healthmd_sleep_sessions` provides session queries. Android typed MCP queries are not currently supported. Check [platform capabilities](/docs/guides/platform-features/) and the [MCP guide](/docs/mcp/) for the chosen setup.

See [scheduling](/docs/scheduling/) for lookback and timing, [troubleshooting](/docs/troubleshooting/) for empty reads versus failed writes, and [export formats](/docs/format/) for detail and coverage.
