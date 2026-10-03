---
title: "Why last night's sleep appears in yesterday's note."
description: "Health.md assigns an overnight sleep session to its start date. Learn what to export in the morning and why the rule preserves session meaning."
lead: "A night that starts Monday and ends Tuesday belongs to Monday's Health.md summary—even when another app emphasizes Tuesday's wake time."
date: "2026-09-22T13:30:00.000Z"
updated: "2026-09-22T13:30:00.000Z"
category: "Explainer"
draft: false
tags:
  - healthmd
  - sleep
  - daily-notes
  - apple-health
  - health-connect
---

It is Tuesday morning. Your watch shows a completed night of sleep, but today's Health.md note looks empty. The data may not be missing at all—it may be in Monday's note.

Health.md assigns a sleep session to the local calendar day on which the session **started**. A session from Monday at 11:45 PM to Tuesday at 7:30 AM belongs to Monday.

## What to export in the morning

| What you want | Date to export |
|---|---|
| Last night's sleep on Tuesday morning | Yesterday (Monday) |
| Tuesday's steps and activity | Today (Tuesday) |
| Both in one run | Monday and Tuesday |

This rule applies to readable exports, Daily Note Injection, API Endpoint payloads, and compatible Apple and Android summaries.

## Why use the start date?

An overnight sleep session is one interval. Assigning it to the start date keeps the night together and makes repeated exports deterministic. Health.md does not invent a Monday half and a Tuesday half merely to fit midnight boundaries.

Canonical records still preserve the original start and end times. Software that needs session-level semantics should use the typed `healthmd_sleep_sessions` operation rather than inferring a session from a daily total.

Health Connect may present a night using the wake date in another interface. That display choice does not change Health.md's shared attribution rule. The rule is kept the same across compatible Apple and Android exports so a vault or consumer does not need a different daily-note convention for each phone.

## Configure a morning schedule

A practical morning automation exports **Yesterday** for sleep and, if needed, **Today** for same-day activity. On iPhone, use the “Export Yesterday's Health Data” Shortcut. On Android, select the equivalent date scope in the schedule or explicit automation action.

If a watch or source app synchronizes after the scheduled run, export the sleep-start day again. Health.md's file updates are designed for repeatable output, and Daily Note Injection replaces app-managed fields rather than appending duplicates.

## What an empty result does—and does not—mean

Before concluding that no sleep occurred, check:

- the HealthKit or Health Connect permission;
- whether the source app has synchronized;
- the previous day's file;
- the selected metric and date range;
- coverage or partial-status fields.

“Permission not granted,” “unsupported,” “not synchronized yet,” and “complete but empty” are different states. Health.md preserves those distinctions instead of treating every missing value as zero.

There is currently no setting that moves the daily sleep summary to the wake date. Keeping one documented rule protects stable filenames, automation, and downstream consumers.

<div class="cta-row">
<a class="button" href="/docs/sleep-date-attribution/">Read the sleep-date guide</a>
<a class="button secondary" href="/docs/scheduling/">Configure scheduling</a>
</div>
