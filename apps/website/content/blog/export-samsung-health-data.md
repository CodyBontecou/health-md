---
title: "Export Samsung Health data to CSV through Health Connect"
description: "Choose Samsung's own data download or export shared Health Connect records to CSV with Health.md. Check permissions, history, source coverage, and sample rows."
lead: "Use Samsung's Download personal data option for its own files. For selected CSV exports, first check that Samsung Health has shared the records with Health Connect."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: android
category: "Workflow guide"
related:
  - export-health-connect-to-obsidian
  - apple-health-vs-health-connect-data-models
  - local-first-health-data-architecture
draft: false
tags:
  - samsung-health
  - health-connect
  - android
  - csv
---

Samsung Health provides its own data download. If you want selected daily files for a spreadsheet, Health.md can also export supported records that Samsung Health has shared with **Health Connect** on your Android phone.

## Choose the export you need

| Your goal | Use |
| --- | --- |
| Download Samsung's own files | Samsung Health's **Download personal data** option, described below. Health.md is not needed. |
| Save selected Health Connect metrics and dates as CSV, JSON or Markdown | Share supported Samsung Health records with Health Connect, then export with Health.md. |

Health Connect can contain records from several apps. A Health.md Health Connect export can therefore include other sources; review coverage before treating it as Samsung-only. The shared records are also a different representation from Samsung's downloaded files.

## Download Samsung's own data

In Samsung Health, open **More options → Settings → Download personal data → Download**. Follow the permission and Samsung account prompts. Samsung's instructions place the downloaded files in **My Files → Downloads → Samsung Health**.

Use [Samsung's current download instructions](https://www.samsung.com/us/support/answer/ANS10001379/) for the exact screens on your device. This is a useful first choice when you need the files Samsung provides. This guide's Health Connect workflow does not import that download or restore Samsung app state.

## Check the Health Connect path before installing an exporter

The path is:

```text
Galaxy Watch or another source → Samsung Health on your phone
                              → Health Connect → Health.md → your files
```

Each step needs available data and the appropriate permission. A record visible in Samsung Health is not proof that it reached Health Connect.

1. If the record comes from a Galaxy Watch, let it synchronize with Samsung Health on the phone first. Open Samsung Health and confirm a known day contains the data you want.
2. In **Samsung Health → Settings → Health Connect**, review sharing permissions. Allow Samsung Health to **write** the categories you want to make available. Read and write permissions are separate.
3. Open Health Connect's data view and check the relevant category, date and contributing app. Confirm Samsung Health records are present before expecting another app to read them.

Samsung documents supported sharing such as steps, exercise, heart rate and sleep in its [Health Connect FAQ](https://developer.samsung.com/health/health-connect-faq.html) and [setup guide](https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect). Availability varies by record type and version. Watch-to-phone synchronization and phone-to-Health Connect sharing are separate stages, so a watch reading may arrive later.

Samsung's published mapping ties some fields, including distance and calories, to exercise records rather than daily activity-tracker totals. Check the actual shared records for your version instead of expecting every dashboard figure to match.

The Health Connect path runs on the Android phone. Health.md's documented Samsung path uses that shared store; its direct Samsung provider adapter is unavailable.

## Export one known day with Health.md

Once the records are available in Health Connect:

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

1. Open Health.md's **Health Connect** setup and grant **read** access to the categories you want. Keep Health Connect as the data source.
2. Select a writable local folder using Android's folder picker.
3. Choose **CSV**, a small metric set and one completed day with known records. JSON and Markdown are other available file formats.
4. Preview the output, export, then open the actual saved file. Check the date, metric, unit and destination before trying a larger range.

The [Android setup guide](/docs/android/) covers app access, permissions and folder availability. The [Health Connect export guide](/health-connect-export/) explains formats and distribution channels. A multi-day daily export produces separate files for the selected days.

## Inspect a fictional CSV before using your records

[Download the Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv). It contains fictional Health Connect output, not a Samsung user's measurements or a complete Samsung export:

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Activity,Steps,12345,count,
2026-03-15,Activity,Walking Running Distance,9500.5,meters,
```

For a steps spreadsheet, filter **Category = Activity**, **Metric = Steps**, and **Unit = count** before converting Value to numbers. The complete Value column can contain metadata and other text. The empty final Timestamp cells in this excerpt identify daily summary rows; they are not individual timestamped measurements.

Keep the original file and use a CSV-aware spreadsheet importer. Other formats and detail settings have different structures. Android Health Connect data and Apple Health data also have distinct source profiles; the [platform comparison](/blog/apple-health-vs-health-connect-data-models/) explains why their fields should not be treated as identical.

## When values or older dates are missing

- **The record is absent from Health Connect:** check Samsung's write permissions and source synchronization. Health.md cannot read a record that was never shared there.
- **Health Connect has data but Health.md does not:** check Health.md's read access, metric selection and date range, then preview the same small range again.
- **An older day is empty:** history access and source backfill are separate limits. Health Connect normally permits reads from other apps starting up to 30 days before read permission was first granted to Health.md, plus data recorded afterward. Reading further back needs additional history access when supported and granted. See [Google's older-data guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). Choosing a longer range does not create missing history.
- **Totals differ from Samsung Health:** compare dates, source coverage, record types and the apps contributing to Health Connect. A daily summary is not Samsung's entire underlying record set.
- **The file is not in the expected folder:** review export results and the actual selected destination. A cloud document provider must expose persistent write access; otherwise export locally and use your chosen sync tool afterward.

For overnight sleep, check the [journal-date examples](/docs/sleep-date-attribution/#sleep-date-examples) before comparing files with a calendar-day view. Missing output is not a measured zero or proof that an activity never happened.

## Keep copies and services separate

The local Health Connect-to-folder workflow requires no Health.md account and creates no Health.md server copy by default. Samsung services, source apps, synced folders and recipients have their own data handling rules. Inspect the contents before sharing an export.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

If your next destination is a vault, continue with [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). This is a file-export workflow; it does not migrate Samsung accounts, device settings or purchases.
