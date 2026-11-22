---
title: "How to export Samsung Health data (CSV, Excel, GPX)"
description: "Samsung Health's Download personal data saves your files to My Files → Downloads → Samsung Health. See what the download contains, how to open it in Excel or Sheets, why it may look empty, and how to get daily CSV via Health Connect."
lead: "Download personal data in Samsung Health is free and needs no extra app. Here is where the files land, how to open them, and when Health Connect plus Health.md gives you cleaner daily CSV."
date: "2026-10-30"
updated: "2026-11-22"
verified: "2026-11-22"
verified_by: "Claude Code (agent)"
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

> **Short answer:** In Samsung Health, tap **⋮ More options → Settings → Download personal data → Download**, then sign in to your Samsung account. The files appear in **My Files → Downloads → Samsung Health** ([Samsung's steps](https://www.samsung.com/us/support/answer/ANS10001379/)). Samsung's download is free and needs no extra app.
>
> Want one clean CSV per day instead? Use Health Connect + Health.md (see [below](#get-clean-daily-csv-through-health-connect)).

## Choose the export you need

| Your goal | Use |
| --- | --- |
| A full download of what Samsung holds about you | Samsung Health's **Download personal data**, described below. Health.md is not needed. |
| A spreadsheet of Samsung's files | Open the downloaded CSV files in Excel or Sheets; see [how to open them](#whats-in-samsungs-download-and-how-to-open-it). |
| One workout as GPX | Varies by Samsung Health version. Some versions offer a share or export option from that workout in the exercise history; check the workout's menu on your device. Samsung's download page does not document GPX, and Health.md does not export GPX. |
| Daily spreadsheet or Obsidian files (steps, sleep, heart rate) | Share supported records with Health Connect, then export with Health.md. |

Health Connect can contain records from several apps. A Health.md Health Connect export can therefore include other sources; review coverage before treating it as Samsung-only. The shared records are also a different representation from Samsung's downloaded files.

## Download Samsung's own data

Open Samsung Health, then **⋮ More options → Settings → Download personal data → Download**. Follow the permission and Samsung account prompts. Samsung's instructions place the files in **My Files → Downloads → Samsung Health**. Screens differ by device and app version, so use [Samsung's current download instructions](https://www.samsung.com/us/support/answer/ANS10001379/) if a menu looks different. This guide's Health Connect workflow does not import that download or restore Samsung app state.

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

That button is for daily CSV, JSON or Markdown files from Health Connect records you have confirmed are shared. You do not need it for Samsung's own download.

<div id="whats-in-samsungs-download-and-how-to-open-it"></div>

## What's in Samsung's download, and how to open it

Samsung's page covers the steps and location only; it does not document the file format or contents. Health.md has not run a test export, so nothing below is confirmed for your version. Treat it as a checklist for inspecting your own download, not a description of it:

- Open the Samsung Health folder and see what is in it. File names and formats vary by version; look for names containing `step`, `sleep` or `heart_rate`.
- **Daily steps vs individual records:** look for a file whose name suggests a daily total or trend (for example, containing `step_daily`) for one row per day. Open a candidate and check whether each row is a day or a shorter record.
- **Metadata line:** if the first line of a file is not column headers, they may sit on line 2. In Excel's text import or Sheets' import, start the import at row 2, or delete line 1 in a copy.
- **Time columns:** if a timestamp column holds a large number, it may be epoch milliseconds; it may also be UTC text. For epoch milliseconds in cell A2, use `=A2/86400000+DATE(1970,1,1)` and format the cell as date and time. The result is UTC; add your offset, for example `+5/24` for UTC+5. Check one known record against the Samsung Health app before trusting a whole column.
- **Columns in one cell:** if everything lands in column A, use Data → Text to Columns (Excel) or Split text to columns (Sheets) with a comma separator, or import the file instead of double-clicking it.

Keep the original download untouched and work on copies.

## Why your export looks empty or incomplete

These are things to check, not confirmed causes for every device:

- **Data still on the watch.** Galaxy Watch data reaches the phone when they synchronize. Open Samsung Health on the phone and confirm the day appears there before downloading. Samsung's [Health Connect setup article](https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect) describes the watch and phone as separate stages.
- **Data held only in Samsung's cloud.** If your history was saved to your Samsung account and is not on this device, the download from the phone may not contain it. Check your Samsung account and backup settings; Samsung's download page does not say what is included, so treat this as something to check.
- **The type you need is in a different file.** Each data type has its own file, so a file for one type will not show another. Search the folder for the type you need.
- **The CSV opened as one column or looks blank.** See the import steps above; a metadata line or missing column split can make a file look empty or unlike the app.
- **Numbers differ from the app.** Compare one known day between the app and the file before trusting either; Samsung does not document how the two relate.

<div id="get-clean-daily-csv-through-health-connect"></div>

## Get clean daily CSV through Health Connect

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

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

Use it for daily CSV/JSON/Markdown files from Health Connect records you've confirmed are shared.

## Export one known day with Health.md

Once the records are available in Health Connect:

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

## Short FAQ

### Can I export Samsung Health to Excel?

Yes, in two ways. Download your personal data and open the CSV files in Excel (import them, and start at row 2 if line 1 is metadata), or export daily CSV with Health.md and open that.

### Can I export Samsung Health to CSV?

Samsung's page does not document the file format, so check which file types your own download contains. For one tidy file per day, export CSV from Health Connect with Health.md.

### Can I export a single workout as GPX?

It varies by Samsung Health version. Look in that workout's menu in the exercise history for a share or export option. Health.md does not export GPX.

### Does Samsung Health export to Apple Health?

There is no direct path that this guide can promise, and Health.md does not transfer data between platforms. Files from either app are separate exports. See the [platform comparison](/blog/apple-health-vs-health-connect-data-models/).

### How often can I download my data?

Samsung's page does not state a limit, so this guide cannot give one. Repeat the same menu steps when you need a fresh copy, and check Samsung's current instructions if a request is refused.

## Keep copies and services separate

The local Health Connect-to-folder workflow requires no Health.md account and creates no Health.md server copy by default. Samsung services, source apps, synced folders and recipients have their own data handling rules. Inspect the contents before sharing an export.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

If your next destination is a vault, continue with [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). This is a file-export workflow; it does not migrate Samsung accounts, device settings or purchases. If you also have Fitbit history, the [Fitbit export guide](/blog/export-fitbit-data/) covers Google Takeout, TCX workouts and the same Health Connect route. Galaxy Watch owners comparing ecosystems may also want the [Garmin Connect export guide](/blog/export-garmin-connect-data/) or the [Google Fit export guide](/blog/export-google-fit-data/).
