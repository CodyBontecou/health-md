---
title: "How to export WHOOP data (CSV), and what the export leaves out"
description: "Export WHOOP data as CSV from the app. The files have no step count, so get WHOOP steps as daily CSV, JSON or Markdown files from your phone."
lead: "WHOOP emails you a set of CSV files, usually within 24 hours. Here is the exact menu path, what each file contains, what is missing (steps, strength sets, HRV in Apple Health), and how to get WHOOP steps into daily files."
date: "2026-10-30"
updated: "2026-11-19"
verified: "2026-11-19"
verified_by: "Claude (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-data-to-obsidian
  - export-health-connect-to-obsidian
  - export-oura-data
draft: false
tags:
  - whoop
  - csv
  - apple-health
  - health-connect
---

**To export WHOOP data, open the WHOOP app and tap More. On iPhone go to App Settings → Data Export; on Android go straight to Data Export. Confirm your email and tap Create Export.** WHOOP emails a download link, usually within 24 hours, and the link expires after 7 days. The download is a set of CSV files. These steps come from WHOOP's [How to Export Your Data](https://support.whoop.com/s/article/How-to-Export-Your-Data?language=en_US) article, checked on November 19, 2026.

You don't need Health.md for that download. Read on if you need to know what the files contain, or if you already exported and found your step count missing.

## What's in the WHOOP export

WHOOP's support article lists four standard CSV files for all WHOOP One, Peak and Life members:

| CSV file | What WHOOP says it contains |
| --- | --- |
| Physiological Cycles | Recovery score, resting heart rate, HRV, strain, energy burned, heart rate, sleep onset and wake times, sleep stages, SpO2 and skin temperature (SpO2 and skin temperature on WHOOP 4.0 and later) |
| Sleeps | Total sleep time, sleep debt, sleep efficiency, sleep performance, respiratory rate, time in light, deep and REM sleep |
| Workouts | Activity name, duration, strain, heart rate zones, energy burned, GPS data if enabled |
| Journal Entries | Your answers to the journal's behavior, habit and routine questions |

Users who have posted about their exports in the WHOOP Community name the files `physiological_cycles.csv`, `sleeps.csv`, `workouts.csv` and `journal_entries.csv`. WHOOP Life members with WHOOP MG get additional health-data exports. Open the files in Excel, Google Sheets or any spreadsheet tool, and check the headers and units before you combine anything.

## What the WHOOP export leaves out

These gaps are as of November 19, 2026. WHOOP can change its export, so check the headers in your own files.

- **Step count.** WHOOP's file table lists no steps. Members report the same gap in the WHOOP Community: one [user report from April 2026](https://www.community.whoop.com/t/exporting-step-count/14416) says the exported CSVs contain no step count, and a [September 2026 user request](https://www.community.whoop.com/t/expose-step-count-in-the-developer-api-and-the-data-export/16226) says none of the four CSVs has a steps column. A later post in that thread, and a separate [community announcement](https://www.community.whoop.com/t/step-count-now-available-in-the-whoop-developer-api/16424), say that from September 23, 2026, cycles in the WHOOP **Developer API** include a `step_count` field. Neither post says the CSV export gained a steps column.
- **Strength-training detail.** The Workouts file is described as name, duration, strain, heart rate zones, energy burned and GPS. WHOOP's table lists no sets, reps or weights.
- **HRV in Apple Health.** This one isn't about the CSV, but people often look for it. WHOOP's [Apple Health article](https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US) says WHOOP does not export HRV to Apple Health, because Apple Health stores SDNN and WHOOP calculates RMSSD. Your HRV stays in the Physiological Cycles CSV.
- **Membership-dependent data.** WHOOP MG data (ECG, IHRN and Blood Pressure Insights) is part of the additional WHOOP Life exports, not the standard set.

## Choose your route

| You want | Start with |
| --- | --- |
| WHOOP's recovery, strain, sleep, workout and journal history | WHOOP's native CSV export (above) |
| Steps or other daily totals WHOOP doesn't put in the CSV | WHOOP → Apple Health or Health Connect, then Health.md |
| Selected shared records as daily files or Obsidian notes | Apple Health or Health Connect, then Health.md |
| WHOOP-specific scores missing from the shared health store | WHOOP's native files or the WHOOP Developer API |

WHOOP's CSVs and a Health.md daily file have different structures. Don't append them into one table just because both end in .csv. Health.md does not import WHOOP's CSV files.

## Get WHOOP steps as daily files

WHOOP writes steps to your phone's health store when you turn that on. Health.md reads them from there and saves each day as a CSV, JSON or Markdown file.

### 1. Turn on WHOOP sharing

**iPhone (Apple Health).** In WHOOP, tap **More → App Settings → Integrations → Apple Health → Connect**, then turn on all categories or pick specific ones, and tap **Allow** ([WHOOP's Apple Health guide](https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US)). WHOOP lists these as exported to Apple Health: workouts, active energy, heart rate, sleep, resting heart rate, respiratory rate, blood oxygen, and **steps if enabled in WHOOP settings**. It does not export HRV, and WHOOP MG does not export ECG or Blood Pressure Insights.

**Android (Health Connect).** In WHOOP, tap **More**, then under **Account & Settings** choose **Integrations → Health Connect → Set Up** and grant the categories you want ([WHOOP's Health Connect guide](https://support.whoop.com/s/article/Google-Health-Integration-For-Android?language=en_US)). WHOOP lists exercise, calories, **steps**, sleep, resting heart rate, respiratory rate and blood oxygen as exported to Health Connect. It does not sync Heart Screener data, Blood Pressure Insights, WHOOP Age, Pace of Aging or VO2 Max. WHOOP says some categories depend on your membership.

A type WHOOP *reads* from the health store (such as weight or distance) is not one it necessarily *writes* there.

### 2. Confirm one completed day

Sync WHOOP, then open Apple Health or Health Connect and check that steps (or whichever metric you need) appear for a finished day. Health.md can only read what's in the health store. It can't recreate a WHOOP score from heart-rate or sleep records.

### 3. Export that day with Health.md

If the records you need appear in Apple Health or Health Connect, Health.md can save them as files:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Grant read access to the metrics you checked. On Android, choose the **Health Connect** source.
2. Pick a writable folder, a small set of metrics and the completed day.
3. Choose **CSV** for a spreadsheet, **JSON** for a script or **Markdown** for notes.
4. Preview and export, then open the file and check the date, units and values before you export a wider range.

A date range produces one file per day. The [iPhone CSV walkthrough](/apple-health-to-csv/) and [Android setup guide](/docs/android/) cover the controls. For a journal, use [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/) or [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). The [steps export guide](/blog/export-apple-health-steps-data/) explains how a daily step total is calculated.

### Why the totals can differ from WHOOP's app

WHOOP counts steps per **physiological cycle**, from when you wake up until you next wake up, according to the [Developer API step-count announcement](https://www.community.whoop.com/t/step-count-now-available-in-the-whoop-developer-api/16424). A Health.md daily file covers a calendar day, and the health store may also hold steps from your phone, watch or other apps. So the numbers won't always match WHOOP's own display. Compare the same date, timezone and sources before treating a difference as an error.

A missing value is unknown, not zero. The same announcement says the API returns `null` rather than `0` for a cycle with no step data (for example when the strap wasn't worn). In a Health.md file, a missing Steps row means no record was read for that day, not that you took no steps.

## Inspect sample files first

The [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) show the Health.md format. Neither is WHOOP data or a sample of WHOOP's export.

Filter the Category, Metric and Unit you want before converting Value to numbers, because other rows can contain text. See the [Health Connect format guide](/health-connect-export/) for Android aggregation and units. Don't rename a heart-rate or sleep field to WHOOP Recovery or Strain: similar-looking numbers aren't the same calculation.

## Missing history and duplicate records

If a record isn't in the health store, check WHOOP's sharing settings and sync. If it's in the store but not in the file, check Health.md's read access, metric and date selection, and destination.

On Android, Health Connect normally lets an app read data from up to 30 days before it was first granted permission, plus everything after. Older reads need extra permission; see [Android's history guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). For older WHOOP history, use WHOOP's own CSV export.

Other apps can write overlapping records, and WHOOP notes that duplicate workouts can appear in Apple Health when several sources write them. Don't sum every source record or add repeated exports together as separate days. For sleep that crosses midnight, compare timezone and journal date using the [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples).

## Keep exported files under your control

WHOOP's account services and emailed downloads have their own data handling rules. The separate local Health.md folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders, spreadsheets and recipients have separate storage policies.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup, no automatic device sync, and the pilot is not generally available. This folder workflow does not upload to it. Read the [privacy policy's retention boundaries](/privacy-policy.html#retention) before selecting a destination.

## Common questions

### Does the WHOOP export include steps?

Not as of November 19, 2026. WHOOP's list of export files has no step count, and members report that the CSVs contain none. A WHOOP Community announcement says the Developer API added a step_count field to cycles in September 2026. To get steps as a file, share them to Apple Health or Health Connect and export them from there.

### What format is the WHOOP export?

CSV. WHOOP emails a link to several CSV files (Physiological Cycles, Sleeps, Workouts and Journal Entries) that open in Excel, Google Sheets or any spreadsheet tool. The link expires after 7 days; request a new export if it does.

### Can I export WHOOP HRV to Apple Health?

No. WHOOP says it does not export HRV to Apple Health, because Apple Health uses SDNN and WHOOP calculates RMSSD. WHOOP's HRV is in the Physiological Cycles CSV of its native export.

### How long does a WHOOP data export take?

WHOOP says most requests are processed within 24 hours. If the email hasn't arrived after that, check your spam folder or contact WHOOP Member Support.

For a similar wearable, see the [Oura export guide](/blog/export-oura-data/).
