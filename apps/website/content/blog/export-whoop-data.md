---
title: "Export WHOOP data: native CSV or shared daily files"
description: "Download WHOOP's own CSV files for recovery and strain, or save records shared to Apple Health or Health Connect as daily files. Check coverage before installing."
lead: "Start with WHOOP's native CSV download for its own metrics. Use Health.md when you want selected records already shared to your phone's health store organized into daily files or notes."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
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

**WHOOP already exports CSV files. You do not need Health.md for that download.** Start there when you need WHOOP's recovery, strain or journal data for a spreadsheet.

There is a different task: organizing selected records already shared to Apple Health or Health Connect into daily CSV, JSON or Markdown files alongside other health information. This guide uses Health.md for that phone-based workflow. It does not import WHOOP's downloaded CSV files or describe direct WHOOP account setup.

## Choose your source before exporting

| You want | Start with |
| --- | --- |
| WHOOP's own recovery, strain and journal information | WHOOP's native data export |
| Selected shared records in daily files or Obsidian notes | Apple Health or Health Connect, then Health.md |
| WHOOP-specific scores or fields missing from the shared store | WHOOP's native files or official developer documentation |

A daily total from a shared health store is not automatically a WHOOP-only total. A native WHOOP CSV and a Health.md daily CSV also have different structures; do not append them into one table merely because both end in .csv.

## Download WHOOP's native CSV files

Follow [WHOOP's export instructions](https://support.whoop.com/s/article/How-to-Export-Your-Data?language=en_US):

1. On iPhone, open **More → App Settings → Data Export**. On Android, open **More → Data Export**.
2. Confirm the email address and choose **Create Export**.
3. Download using the emailed link. WHOOP says requests usually complete within 24 hours; links expire after seven days.

WHOOP documents multiple CSVs covering physiological cycles, sleep, workouts and journal entries. Keep the original files, inspect their headers and units, and select the file that answers your question. The current instructions list standard exports for One, Peak and Life memberships, with additional MG health-data exports for eligible Life members.

If that download already supplies the fields you need, continue with it. Health.md's shared-store route below is not required.

## Check what WHOOP actually shares

Use the detailed outgoing list for your platform rather than assuming the word “Recovery” means its score is shared. Authorizing an integration does not create every field visible in the WHOOP app.

### Apple Health on iPhone

WHOOP's [Apple Health guide](https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US) uses **More → App Settings → Integrations → Apple Health → Connect**. Choose the relevant categories, then inspect WHOOP's write permissions in Apple Health. Health.md needs separate read authorization.

The outgoing list includes sleep, workouts, active energy, heart rate, resting heart rate, respiratory rate, blood oxygen and steps when enabled. WHOOP explicitly says it does **not export HRV to Apple Health**; its HRV calculation differs from Apple's. ECG and Blood Pressure Insights are also excluded from that connection.

If another source contributes HRV to Apple Health, exporting it does not turn it into WHOOP HRV. Check the record's source before comparing values.

### Health Connect on Android

WHOOP's [Android integration guide](https://support.whoop.com/s/article/Google-Health-Integration-For-Android?language=en_US) uses **More → Account & Settings → Integrations → Health Connect → Set Up**. Select the relevant categories and verify that WHOOP can write them. Health.md needs separate read access.

WHOOP lists exercise, calories, steps, sleep, resting heart rate, respiratory rate and blood oxygen as outgoing types. Its page says category availability depends on membership. It excludes Heart Screener data, Blood Pressure Insights, WHOOP Age, Pace of Aging and VO2 Max from Health Connect.

Check the actual record before expecting a file. A type WHOOP imports from Health Connect is not necessarily a type it exports there.

## Save one known day with Health.md

First synchronize WHOOP and inspect a completed day in Apple Health or Health Connect. Confirm that the metric and date you need are present. This workflow cannot recreate an unshared score from heart-rate or sleep records.

Choose the app for your phone:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Grant read access to the metrics you verified. On Android, select the **Health Connect** source.
2. Choose a writable destination folder, a small metric set and the completed day.
3. Select **CSV** for a table, **JSON** for a script or **Markdown** for notes.
4. Preview and export, then open the saved file. Check its date, units, values and destination before widening the range.

Daily exports produce separate files for the selected days. Follow the [iPhone CSV walkthrough](/apple-health-to-csv/) or [Android setup guide](/docs/android/) for the relevant controls. For a journal, use [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/) or [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/).

## Inspect samples without mixing export formats

The [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) demonstrate Health.md files. Neither is a WHOOP capture or a sample of WHOOP's native export.

Filter the intended Category, Metric and Unit before converting Value to numbers; other rows can contain text. Keep daily summaries separate from timed records and overlapping exports. Consult the [steps explanation](/blog/export-apple-health-steps-data/) or [Health Connect format guide](/health-connect-export/) for the platform's aggregation and units.

Do not rename a general heart-rate or sleep field to WHOOP Recovery or Strain. Similar-looking numbers do not establish equivalent calculations, source coverage or dates.

## Missing history and duplicate records

If the record is absent from the phone's health store, check WHOOP's sharing and synchronization. If it exists there but is absent from the file, check Health.md's read access, metric and date selection, and destination. Missing output is not a measured zero.

Health Connect normally allows reads from up to 30 days before read permission was first granted to Health.md, plus later data. Broader access is conditional; see [Android's history guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). That window is separate from how much history WHOOP shared.

Other apps can contribute overlapping records. Do not sum every source record or combine repeated exports as independent daily totals. For sleep crossing midnight, compare timezone and journal date using the [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples). The platform guides describe their own source and reduction rules.

## Keep exported files under your control

WHOOP's account services and emailed downloads have their own data handling rules. The separate local Health.md folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders, spreadsheets and recipients have separate storage policies.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup, no automatic device sync, and the pilot is not generally available. This folder workflow does not upload to it. Read the [privacy policy's retention boundaries](/privacy-policy.html#retention) before selecting a destination.
