---
title: "Export Suunto data: FIT, GPX or Apple Health files"
description: "Save Suunto workout or route files, or export records already shared to Apple Health as daily CSV, JSON or notes. Check format and sharing limits first."
lead: "Choose Suunto's own files for workout detail or navigation. Use a daily-file exporter only after verifying the records in Apple Health."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-zepp-amazfit-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - suunto
  - workouts
  - apple-health
  - export
---

**Use Suunto's native export when you need an activity file or a navigation route. Health.md is not required for that download.** On iPhone, Health.md offers a separate workflow for selected records already shared to Apple Health: daily Markdown, CSV or JSON files.

Those outputs are not interchangeable. A daily summary is not a training-service import file, and a route alone is not a complete workout record.

## Choose workout detail, a route or daily files

Suunto's [official file-export guide](https://www.suunto.com/Support/faq-articles/suunto-app/what-type-of-files-can-i-export-from-the-suunto-app/), checked **October 30, 2026**, distinguishes:

| Output | Documented purpose |
| --- | --- |
| Workout FIT | Training detail, with fields such as time, location and available sensor measurements |
| Workout GPX | Location and time, with heart rate where available; not all app information |
| Route GPX | The location track for navigation, rather than the workout's full measurements |

Open an available workout in the Suunto app, tap the upper-right three-dot menu and choose the format to save or open in a compatible app. Suunto documents this on iOS and Android. **For an exercise recorded without GPS, it documents FIT export rather than GPX.** A missing GPX option therefore does not by itself mean that the activity cannot be exported.

Keep the original download and inspect its actual fields before importing elsewhere. These instructions do not establish an account-wide backup, native daily CSV or a complete archive of every score visible in Suunto.

## Check what actually reached Apple Health

Suunto's [own App Store description](https://apps.apple.com/us/app/suunto/id1230327951) says its app connects to Apple Health and directs readers to app settings to start sharing. It separately describes social-sharing fields; **that social-sharing list is not an Apple Health field list**.

The listing does not establish that every daily metric, sleep record, sensor stream or historical activity is copied. A connection is not proof that your required data arrived. Before considering another exporter:

1. Synchronize the watch with the Suunto app and enable the relevant available Apple Health sharing choices.
2. In Apple's Health app, open the category you need and inspect a known day's records and sources.
3. Confirm that the required Suunto record, date and detail are present. If they are absent, check Suunto's outgoing sharing and synchronization first.

Do not install Health.md expecting it to recover an unshared Suunto measurement. It reads authorized Apple Health data; it does not sign in to Suunto, import FIT/GPX downloads or reconstruct proprietary scores. This guide does not establish a direct Suunto-to-Health Connect setup on Android.

## Save one verified day as CSV, JSON or notes

If Apple Health contains the records you need, [get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and use the [first-export setup guide](/docs/iphone-first-export/).

Start with one completed day, the relevant metrics and a writable folder. Grant Health.md its own read permissions; Suunto's sharing permission does not authorize another app to read. Preview the export, save it and open the result before increasing the range.

The setup guide starts with Markdown. Add CSV for a table or JSON for structured processing after the folder workflow succeeds. Longer ranges produce separate daily files. Data from other apps may also be present, so do not treat the result as automatically Suunto-only.

Compare the output with the source records using the same dates, units and representation. Several CSV rows can describe one workout; counting rows is not counting sessions. For session grouping, original timing and optional details, use the [workout export guide](/blog/export-apple-health-workouts/). Keep native FIT or GPX files when the destination requires those formats.

## Check the sample and the gaps

The [fictional Apple CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) show Health.md's format. They are not Suunto files or evidence that Suunto shares every example field.

Use a CSV-aware importer. Select the intended Category, Metric and Unit before converting Value to a number; that column also contains text and metadata. Check repeated exports, overlapping dates and multiple sources before combining files. A missing value is unavailable, not zero. Do not add summary totals to their underlying measurements or expect them to reproduce a proprietary dashboard calculation.

For sleep records that actually exist in Apple Health, Health.md's daily summaries use a local noon-to-noon journal window. The [sleep-date guide](/blog/why-sleep-is-in-yesterdays-note/) explains why a night may belong to the previous date. That date rule does not establish that Suunto shared sleep data.

## Keep detailed files in the intended destination

Routes and activity files can disclose precise locations and times. Inspect the file itself before sharing; do not assume that a map's visibility setting changes every downloaded field.

Core folder exports require no Health.md account and create no Health.md server copy by default. A synced folder or downstream service has separate storage rules. The optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup or automatic device sync, and is not generally available. This folder workflow does not upload to that pilot.

Use the [local destination guide](/blog/export-health-data-without-the-cloud/) and [retention policy](/privacy-policy.html#retention) to choose storage. Retain the original Suunto files until you have verified the coverage and meaning of any derived daily files.
