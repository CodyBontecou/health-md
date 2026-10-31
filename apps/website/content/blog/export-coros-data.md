---
title: "Export COROS data: workout files or Apple Health CSV"
description: "Download COROS workout files, request daily data, or export records already shared to Apple Health as CSV, JSON or notes. Check sharing and history limits."
lead: "Choose native COROS files for training history. For daily files and notes, verify which COROS records actually reached Apple Health first."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-suunto-data
  - export-zepp-amazfit-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - coros
  - apple-health
  - workouts
  - csv
---

**COROS provides its own workout downloads and a separate support-request route for daily data. You do not need Health.md for those options.** Start there when you need COROS's original files or records.

For daily CSV, JSON or Markdown files, Health.md can export selected records already present in Apple Health on your iPhone. It does not connect to your COROS account, import COROS downloads or restore missing watch history.

## Choose the output you need

| Your task | Start with |
| --- | --- |
| Save one workout for another training service | COROS's individual activity export |
| Download available activity history | COROS Training Hub's bulk export |
| Request daily metrics, sleep or heart-rate data directly from COROS | COROS's daily-data support request |
| Keep selected shared measurements in daily files or notes | Verify Apple Health records, then export with Health.md |

A native activity file and a daily summary answer different questions. Keep the original download when you need its workout detail.

## Download workout files from COROS

The official [individual-workout instructions](https://support.coros.com/hc/en-us/articles/360043975752-Exporting-Workout-Data-and-Uploading-to-3rd-Party-Apps), checked **October 30, 2026**, describe opening an activity in the COROS app, opening its settings and choosing **Export Data**. Select an available format and save the result. COROS suggests FIT when heart-rate detail matters; do not assume its GPX choice contains that detail.

For many workouts, use the [bulk activity export](https://support.coros.com/hc/en-us/articles/33125636125204-Bulk-Export-Historical-Activity-Data): sign in to [COROS Training Hub](https://t.coros.com/) on a desktop, open **Activity List**, then **Export Data**. COROS documents FIT or TCX and an email destination for the files.

Inspect the resulting files before importing them elsewhere. These instructions establish activity downloads, not a universal export of every daily measurement or calculated score. Health.md's daily CSV does not replace a FIT, TCX or GPX file for training-service imports.

## Request sleep and daily data separately

COROS's [daily-data request instructions](https://support.coros.com/hc/en-us/articles/25002333092500-Requesting-a-Bulk-Export-of-COROS-Data) distinguish non-activity data from Training Hub's workout export. Synchronize your device, then use **Profile → Customer Support → Contact Support** in the COROS app. Specify the desired date range, review the privacy agreement and submit the request. Wait for submission to finish before closing it.

The page names daily metrics, sleep and heart rate as examples. It does not establish a CSV schema, delivery deadline or complete list of returned fields. Inspect the response rather than promising a particular archive layout.

The older individual-workout page says daily data cannot be exported. That statement does not erase the separate support-request route documented above. Neither route proves that the same data was copied into Apple Health.

## Check COROS sharing to Apple Health

COROS's [Apple Health instructions](https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App) describe **Profile → Setting → 3rd Party Apps → Data Sync → Apple Health**. Choose the categories to share. In Apple's Health app, COROS also points to your profile's **Privacy → Apps → COROS** controls for changing supported categories.

Its list includes steps, heart rate, sleep analysis and cycling, swimming, and walking/running distances. This is evidence of a COROS-to-Apple Health route, not proof that every watch, field or historical day has arrived. It does not promise that a connection copies your entire account history or that COROS receives Apple Health data in reverse.

Before using an exporter, inspect a known day's relevant category in Apple Health and check that COROS appears among its actual source records. A connection toggle alone is insufficient. If the required record is absent, return to COROS synchronization and outgoing permissions; Health.md cannot recover it from the watch or account.

This walkthrough qualifies the **iPhone Apple Health route**. It does not establish a direct COROS-to-Health Connect setup on Android. Use COROS's native downloads when those are the files you need.

## Export one verified day with Health.md

Once the required records are present in Apple Health, [get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and follow [your first iPhone export](/docs/iphone-first-export/).

1. Grant Health.md separate read access to the categories you need. COROS's write permission does not grant another app read access.
2. Start with one completed day, a writable folder and the metrics you verified. Preview the export before saving it.
3. Use Markdown for daily notes, CSV for table inspection or JSON for structured processing. The first-export guide starts with Markdown; add the other formats after the folder workflow succeeds.
4. Open the saved file and compare dates, units and values with the source records before increasing the range.

A longer range produces separate daily files. Apple Health can contain records from several sources, so an export is not automatically a COROS-only dataset. Missing data is unavailable, not zero. A daily total also need not reproduce the calculation shown in a COROS dashboard.

For sleep, use the [journal-date explanation](/blog/why-sleep-is-in-yesterdays-note/): Health.md's daily sleep summaries use a local noon-to-noon window. Workout grouping has its own rules in the [workout export guide](/blog/export-apple-health-workouts/). Do not move records between dates merely to make two dashboards agree.

## Inspect a sample before combining files

The [fictional Apple CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) show Health.md's output shape. They are not native COROS exports or proof that COROS supplies every example field.

Use a CSV-aware importer and keep the header. Filter the intended Category, Metric and Unit before interpreting Value as a number; that column also contains text and metadata. Check overlapping dates, repeated exports and multiple sources before combining files. Counting rows is not counting workouts, and daily summaries should not be added to their underlying samples.

Retain native activity files for route and sensor-stream requirements. A daily summary cannot establish that detailed coordinates, every sample or a proprietary training calculation are available. Health.md does not reconstruct missing COROS scores or turn these summaries into COROS-importable workouts.

## Keep exports in the intended destination

Detailed activity files can contain exact times and locations. Inspect their contents before sharing. A selected summary is not a universal guarantee that location information is absent from every export configuration.

Core folder exports require no Health.md account and create no Health.md server copy by default. A synced destination or downstream service has separate storage rules. The optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it; it has no public signup, no automatic device sync and is not generally available. This folder workflow does not upload to that pilot.

Use the [local destination guide](/blog/export-health-data-without-the-cloud/) and [retention policy](/privacy-policy.html#retention) when choosing storage. Keep original COROS files until you have checked the representation and coverage of any derived daily files.
