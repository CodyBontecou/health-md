---
title: "Export Garmin data: account archive, CSV, FIT, Apple Health"
description: "Download your Garmin Connect archive, activity CSV or FIT files, or turn data Garmin shares with Apple Health or Health Connect into daily files."
lead: "Start with Garmin's own downloads: the account archive, the activity CSV or single activity files. Use Apple Health on iPhone or Health Connect on Android 14+ when you want shared records as daily files."
date: "2026-10-30"
updated: "2026-11-22"
verified: "2026-11-22"
verified_by: "Claude (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-health-connect-to-obsidian
  - export-strava-data
draft: false
tags:
  - garmin
  - health-connect
  - apple-health
  - iphone
  - android
  - csv
---

**Which Garmin export do you need?** You do not need Health.md for any of these Garmin downloads:

1. **Full account archive:** Garmin Account Data Management → **Export Your Data** → **Request Data Export**.
2. **Spreadsheet of activities or stats:** on Garmin Connect's website, **Activities → All Activities → Export CSV**, or **Reports** → a category and range → **Export**.
3. **One workout file:** open the activity, use its settings menu, and choose the original (FIT), TCX or GPX.

Each does a different job. The account archive is a large bundle of files, mostly JSON and FIT, not one spreadsheet. The All Activities CSV is a summary table with one row per activity. FIT is the original recording of a single activity. Garmin's [export instructions](https://support.garmin.com/en-US/?faq=W1TvTPW8JZ6LfJSfK512Q8) do not say how long an archive takes to arrive, so follow what Garmin shows after you request it.

If you instead want your Garmin numbers as daily CSV, JSON or Markdown files, there is a phone route: Garmin Connect shares selected data with **Apple Health** on iPhone or **Health Connect** on Android 14 or later, and Health.md exports what those hold. Check the shared records before installing anything.

## Choose the export that matches your task

| Your goal | Start here |
| --- | --- |
| A spreadsheet of activity summaries or Garmin reports | Garmin Connect's native CSV exports |
| An individual workout file for another compatible service | Garmin's activity download options, such as the original file, TCX or GPX |
| A Garmin account archive | Garmin Account Data Management |
| Daily CSV, JSON or Markdown files on iPhone from data Garmin shares with Apple Health | Garmin Connect → Apple Health → Health.md |
| Selected daily CSV, JSON or Markdown files from shared Android records | Garmin Connect → Health Connect → Health.md |

Health.md never reads Garmin's archive or FIT files, does not restore a Garmin account, and is not a direct connection to the Garmin Health API. It exports what Apple Health or Health Connect holds.

## Download Garmin's own files

Garmin's [export instructions](https://support.garmin.com/en-US/?faq=W1TvTPW8JZ6LfJSfK512Q8) distinguish several outputs. Garmin's own [Account Data Management](https://www.garmin.com/en-US/account/datamanagement/) page is the starting point for the archive:

- **Account archive:** use **Garmin Account Data Management → Export Your Data → Request Data Export** and follow Garmin's delivery instructions. Expect a bundle of mostly JSON and FIT files rather than a single table.
- **Activity summaries:** on Garmin Connect's website, use **Activities → All Activities → Export CSV**. This is a summary table rather than a complete workout recording.
- **Reports:** open **Reports**, choose a category and available range, then **Export**. These reports use CSV.
- **Weight or blood pressure reports:** open **Health Stats**, choose the relevant report and range, then export.
- **Activity files:** open an activity and use its settings menu to choose the available format. Garmin's original device file is typically FIT.

Keep the original files. A report CSV, an activity file and an account archive preserve different information; do not assume their contents or columns are interchangeable. Use Garmin's current instructions for your product and task.

## iPhone: check what Garmin shares with Apple Health

Garmin documents sharing from Garmin Connect to Apple Health in [Sharing your Garmin Connect data with Apple Health](https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA). Read that page for the current settings, the conditions under which data transfers, and how much history comes across; those details can change, and this guide does not restate them. Garmin controls what is shared, and it depends on your settings and device. Garmin-specific scores such as Body Battery stay in Garmin's own export.

Apple Health can hold the same data type from several sources and shows the highest-priority one, so check **Data Sources & Access** as described in [Apple's data source guide](https://support.apple.com/guide/iphone/iph5ede58c3d/ios).

Before installing anything, confirm the records are really there:

1. Open **Garmin Connect**, sync your device, and note one completed day with a value you can check.
2. In the Health app, open the category → that day → **Show All Data**.
3. Confirm **Garmin Connect** is listed as a source for the records you want.

## Export one known day on iPhone with Health.md

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md on the App Store</a>

1. Open Health.md and grant **read** access to the Health categories you need.
2. Choose a destination folder.
3. Select **CSV** and a small set of metrics.
4. Export one completed day you already checked, then open the file and compare it with the Health app.

See [Apple Health export](/apple-health-export/) and the [first iPhone export guide](/docs/iphone-first-export/). Health.md exports what Apple Health holds, from any source, so the result is not a Garmin-only file.

## Android 14+: Health Connect route

Garmin documents a one-way connection from Garmin Connect into Health Connect, with sharing after a successful device sync. Its [Health Connect support page](https://support.garmin.com/en-US/?faq=JToBEy0jfe6pIygark2Ui5) lists supported examples including steps, heart rate, sleep stages and weight. Available records depend on the device, app version and permissions; the list is not a promise that every dashboard value will appear.

On an **Android 14 or later** phone:

1. Synchronize your Garmin device with Garmin Connect. Confirm one completed day with a metric you can check.
2. Enable the Garmin Connect connection in Health Connect and allow Garmin Connect to **write** the categories you want. Follow Garmin's support page and [Google's connection instructions](https://support.google.com/android/answer/12201227) for your phone's screens.
3. In Health Connect, inspect the relevant category, day and contributing app. Verify that Garmin Connect records are actually present.

Garmin does not read data back through this connection. Health Connect sharing is not a Garmin account migration or a route for importing someone else's files into Garmin.

If the phone does not meet Garmin's Android requirement, use Garmin's native download options above. A direct Garmin account connection is unavailable in this workflow; keep Health Connect selected as your source in Health.md.

## Export one known day on Android with Health.md

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

iPhone CSVs use the same daily layout; see [Apple Health to CSV](/apple-health-to-csv/). Use a CSV-aware importer and retain the original export. Garmin's native reports can use different headers, units and aggregation; check those separately. Health.md's Health Connect export can include other contributing apps, so it should not be treated as a Garmin-only file.

## When records or older dates are missing

- **No record in Health Connect:** check Garmin synchronization and write permissions first. Health.md cannot export a record that Garmin never shared there.
- **A record exists but the file is empty:** check Health.md's read permissions, selected metric, day and destination. Start with the same known day again.
- **Older history is missing:** source backfill and app history access are separate limits. Health Connect normally permits reads starting up to 30 days before permission was first granted to Health.md, plus later data. Broader history needs supported, granted access. See [Google's older-data guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data).
- **iPhone, no Garmin record in Apple Health:** check Garmin's FAQ for when data transfers (for example, whether Garmin Connect must be open) and whether the connection is on. Then check source priority in **Data Sources & Access**.
- **iPhone, older dates missing:** Garmin limits how much history comes across when sharing is turned on; see its FAQ. Health.md cannot export a record Garmin never wrote to Apple Health.
- **Values differ from Garmin reports:** compare record type, date boundaries and contributing sources before combining files. Missing output is not a measured zero, and a daily summary is not a full device recording.

For overnight sleep, read the [journal-date examples](/docs/sleep-date-attribution/#sleep-date-examples). Exporting a longer date range cannot reconstruct history or proprietary scores absent from the shared records.

## Keep the destination explicit

This local Apple Health or Health Connect-to-folder workflow requires no Health.md account and creates no Health.md server copy by default. Garmin services, other source apps and synced folders retain their own data handling rules. Check file contents before sharing them.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup and no automatic device sync; the pilot is not generally available. This folder workflow does not upload to that pilot; see [retention and destination boundaries](/privacy-policy.html#retention).

For notes rather than spreadsheets, continue with [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). Recording workouts on your phone's Health data? See how to [export Apple Health workouts](/blog/export-apple-health-workouts/). Keep native Garmin files for tasks that require Garmin's own archive or activity representation. Coming from Strava? The [Strava export guide](/blog/export-strava-data/) covers its bulk archive, GPX and CSV. Using a Galaxy Watch instead? See how to [export Samsung Health data](/blog/export-samsung-health-data/), both Samsung's own download and the Health Connect route. Switching from Fitbit? The [Fitbit export guide](/blog/export-fitbit-data/) explains what to save from Google Health first, since Health Connect does not carry Fitbit history into Garmin.
