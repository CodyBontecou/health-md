---
title: "Why last night's sleep appears in yesterday's note."
description: "Understand Health.md’s noon-to-noon sleep journal window, choose the right morning export date, and check empty notes without treating missing sleep as zero."
lead: "A night that starts Monday and ends Tuesday belongs to Monday's Health.md summary—even when another app emphasizes Tuesday's wake time."
date: "2026-09-22T13:30:00.000Z"
updated: "2026-10-27"
category: "Explainer"
related:
  - export-apple-health-sleep-data
  - export-apple-health-data-to-obsidian
  - export-apple-health-steps-data
draft: false
tags:
  - healthmd
  - sleep
  - daily-notes
  - apple-health
  - health-connect
verified: "2026-10-27"
verified_by: "Codex (agent)"
verified_method: traced
---

It is Tuesday morning. Your watch shows a completed night of sleep, but today's Health.md note looks empty. The data may not be missing at all—it may be in Monday's note.

Daily sleep summaries use a local **noon-to-noon journal window**. Monday’s window runs from Monday 12:00 to Tuesday 12:00. Sleep from Monday 23:45 to Tuesday 07:30 belongs to Monday; so does sleep from Tuesday 01:00 to 07:30. A Tuesday afternoon nap belongs to Tuesday. See the complete [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples).

For the complete metric-selection, preview, and CSV workflow, follow [how to export Apple Health sleep data](/blog/export-apple-health-sleep-data/).

## What to export in the morning

| What you want | Date to export |
|---|---|
| Last night's sleep on Tuesday morning | Yesterday (Monday) |
| Tuesday's steps and activity | Today (Tuesday) |
| Both in one run | Monday and Tuesday |

This rule applies to readable exports, Daily Note Injection, API Endpoint payloads, and compatible Apple and Android summaries.

<div id="section-why-use-the-start-date"></div>

## Why use a sleep journal window?

The journal window keeps a typical night together instead of splitting it at midnight. The opening noon is included and the next noon excluded. Sleep crossing noon can contribute to adjacent summaries; source timestamps are not rewritten.

Raw or canonical records retain original timestamps and their own ownership rules. Software must not infer session boundaries from a daily total. The typed `healthmd_sleep_sessions` query is available on supported Apple Health CLI/MCP paths; Android typed MCP queries are not currently supported. See [platform capabilities](/docs/guides/platform-features/).

Health Connect may present a night using the wake date in another interface. That display choice does not change Health.md's shared attribution rule. The rule is kept the same across compatible Apple and Android exports so a vault or consumer does not need a different daily-note convention for each phone.

## Configure a morning schedule

A practical morning automation exports **Yesterday** for sleep and, if needed, **Today** for same-day activity. On iPhone, use the “Export Yesterday's Health Data” Shortcut. On Android, select the equivalent date scope in the schedule or explicit automation action.

If a watch or source app synchronizes after the scheduled run, export the sleep journal day again. Health.md's file updates are designed for repeatable output, and Daily Note Injection replaces app-managed fields rather than appending duplicates.

## What an empty result does—and does not—mean

Before concluding that no sleep occurred, check:

- the HealthKit or Health Connect permission;
- whether the source app has synchronized;
- the previous day's file;
- the selected metric and date range;
- coverage or partial-status fields.

Denied access, unsupported data, late synchronization, and an empty matching range are possible causes, not states that can always be distinguished from an empty result. On iPhone, HealthKit does not reveal whether read access was denied. Review the actual coverage or error information and allowed categories; do not invent a permission state or turn a missing value into zero. See [export troubleshooting](/docs/troubleshooting/).

There is currently no setting that moves the daily sleep summary to the wake date. Keeping one documented rule protects stable filenames, automation, and downstream consumers.

<div class="cta-row">
<a class="button" href="/docs/sleep-date-attribution/">Read the sleep-date guide</a>
<a class="button secondary" href="/docs/scheduling/">Configure scheduling</a>
</div>
