---
title: "Export Garmin Connect data to CSV: native or Health Connect"
description: "Download Garmin's own CSV reports and activity files, or export supported Health Connect records with Health.md on Android 14+. Check coverage before installing."
lead: "Start with Garmin's own exports for reports, activity files or an account archive. Use Health Connect on Android 14 or later when you want selected shared records in daily files."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: android
category: "Workflow guide"
related:
  - export-health-connect-to-obsidian
  - export-samsung-health-data
  - apple-health-vs-health-connect-data-models
draft: false
tags:
  - garmin
  - health-connect
  - android
  - csv
---

Garmin Connect already provides CSV reports, activity downloads and an account export. **You do not need Health.md for those downloads.** If your goal is selected daily files from records Garmin shares with Health Connect, Health.md offers a separate Android workflow.

**Garmin's Health Connect sharing requires Android 14 or later.** Check your phone and the actual shared records before installing an exporter. The Health Connect representation is different from Garmin's own files and may include records from other apps.

## Choose the export that matches your task

| Your goal | Start here |
| --- | --- |
| A spreadsheet of activity summaries or Garmin reports | Garmin Connect's native CSV exports |
| An individual workout file for another compatible service | Garmin's activity download options, such as the original file, TCX or GPX |
| A Garmin account archive | Garmin Account Data Management |
| Selected daily CSV, JSON or Markdown files from shared Android records | Garmin Connect → Health Connect → Health.md |

Health.md's Health Connect workflow does not import Garmin archives, parse FIT files or restore a Garmin account. It is also not a direct connection to the Garmin Health API.

## Download Garmin's own files first

Garmin's [export instructions](https://support.garmin.com/en-US/?faq=W1TvTPW8JZ6LfJSfK512Q8) distinguish several outputs:

- **Activity summaries:** on Garmin Connect's website, use **Activities → All Activities → Export CSV**. This is a summary table rather than a complete workout recording.
- **Reports:** open **Reports**, choose a category and available range, then **Export**. These reports use CSV.
- **Weight or blood pressure reports:** open **Health Stats**, choose the relevant report and range, then export.
- **Activity files:** open an activity and use its settings menu to choose the available format. Garmin's original device file is typically FIT.
- **Account archive:** use **Garmin Account Data Management → Export Your Data → Request Data Export** and follow Garmin's delivery instructions.

Keep the original files. A report CSV, an activity file and an account archive preserve different information; do not assume their contents or columns are interchangeable. Use Garmin's current instructions for your product and task.

## Check the Android Health Connect route

Garmin documents a one-way connection from Garmin Connect into Health Connect, with sharing after a successful device sync. Its [Health Connect support page](https://support.garmin.com/en-US/?faq=JToBEy0jfe6pIygark2Ui5) lists supported examples including steps, heart rate, sleep stages and weight. Available records depend on the device, app version and permissions; the list is not a promise that every dashboard value will appear.

On an **Android 14 or later** phone:

1. Synchronize your Garmin device with Garmin Connect. Confirm one completed day with a metric you can check.
2. Enable the Garmin Connect connection in Health Connect and allow Garmin Connect to **write** the categories you want. Follow Garmin's support page and [Google's connection instructions](https://support.google.com/android/answer/12201227) for your phone's screens.
3. In Health Connect, inspect the relevant category, day and contributing app. Verify that Garmin Connect records are actually present.

Garmin does not read data back through this connection. Health Connect sharing is not a Garmin account migration or a route for importing someone else's files into Garmin.

If the phone does not meet Garmin's Android requirement, use Garmin's native download options above. A direct Garmin account connection is unavailable in this workflow; keep Health Connect selected as your source in Health.md.

## Export one known day with Health.md

Once you have confirmed the shared records:

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

1. Open Health.md's **Health Connect** setup and grant **read** access to the needed categories. Keep Health Connect as the source.
2. Choose a writable local folder through Android's folder picker.
3. Select **CSV**, a small metric set and the completed day you checked.
4. Preview, export, then open the saved file. Compare its date, unit and values with the available source records before selecting a larger range.

The [Android setup guide](/docs/android/) covers permissions and destinations. The [Health Connect export guide](/health-connect-export/) explains formats and history limits. Daily exports create separate files for the chosen days; JSON and Markdown are also available.

## Inspect the CSV structure

[Download the fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) before using personal records:

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Activity,Steps,12345,count,
2026-03-15,Activity,Walking Running Distance,9500.5,meters,
```

These are fictional Health Connect rows, not a Garmin capture or Garmin's own CSV format. For a steps table, filter **Category = Activity**, **Metric = Steps** and **Unit = count** before treating Value as numeric. Other rows may contain text. The empty Timestamp cells here belong to daily summaries, not individual measurements.

Use a CSV-aware importer and retain the original export. Garmin's native reports can use different headers, units and aggregation; check those separately. Health.md's Health Connect export can include other contributing apps, so it should not be treated as a Garmin-only file.

## When records or older dates are missing

- **No record in Health Connect:** check Garmin synchronization and write permissions first. Health.md cannot export a record that Garmin never shared there.
- **A record exists but the file is empty:** check Health.md's read permissions, selected metric, day and destination. Start with the same known day again.
- **Older history is missing:** source backfill and app history access are separate limits. Health Connect normally permits reads starting up to 30 days before permission was first granted to Health.md, plus later data. Broader history needs supported, granted access. See [Google's older-data guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data).
- **Values differ from Garmin reports:** compare record type, date boundaries and contributing sources before combining files. Missing output is not a measured zero, and a daily summary is not a full device recording.

For overnight sleep, read the [journal-date examples](/docs/sleep-date-attribution/#sleep-date-examples). Exporting a longer date range cannot reconstruct history or proprietary scores absent from the shared records.

## Keep the destination explicit

This local Health Connect-to-folder workflow requires no Health.md account and creates no Health.md server copy by default. Garmin services, other source apps and synced folders retain their own data handling rules. Check file contents before sharing them.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup and no automatic device sync; the pilot is not generally available. This folder workflow does not upload to that pilot; see [retention and destination boundaries](/privacy-policy.html#retention).

For notes rather than spreadsheets, continue with [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). Keep native Garmin files for tasks that require Garmin's own archive or activity representation.
