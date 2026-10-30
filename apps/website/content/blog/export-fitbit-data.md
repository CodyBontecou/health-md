---
title: "Export Fitbit data: Google Takeout or Health Connect CSV"
description: "Choose Google Takeout for a Fitbit archive, TCX for a workout, or shared Health Connect records for daily CSV files. Verify permissions before installing Health.md."
lead: "Google's current Fitbit export help uses the Google Health name. Choose an account download, an individual workout file, or selected daily files from shared Android records."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: android
category: "Workflow guide"
related:
  - export-health-connect-to-obsidian
  - export-oura-data
  - export-google-fit-data
draft: false
tags:
  - fitbit
  - google-health
  - health-connect
  - csv
---

If you want to export Fitbit data, first choose what you need to preserve. An account archive, a workout file and daily spreadsheet rows are different outputs. Google's current [export help](https://support.google.com/googlehealth/answer/14236615?hl=en) describes the Google Health account route; older Fitbit screenshots may show different menus.

**You do not need Health.md to download Google's archive or export a workout as TCX.** Health.md offers a separate workflow for selected records already available in Health Connect on an Android phone. It does not import a Google Takeout ZIP or convert an old Fitbit archive.

## Choose the file you need

| Your goal | Use |
| --- | --- |
| Keep Google's downloadable account data | Google Takeout with **Google Health** selected |
| Save a supported GPS workout as an activity file | The Google Health app's **TCX** export |
| Save selected shared fitness records as daily CSV, JSON or Markdown | Google Health → Health Connect → Health.md |

This guide's Health.md route uses the shared store on your phone. It does not require a direct Fitbit API connection, and it is not a device or account migration tool.

## Download an account archive with Google Takeout

For a **Google Account** sign-in, Google directs users to its data download tool:

1. Open [Google Takeout](https://takeout.google.com/) with the account that holds your Fitbit/Google Health data.
2. Select **Google Health**, then review the export options and create the download.
3. Follow Google's delivery instructions. Keep all parts of the original archive and inspect the supplied files before transforming them.

This is an account download, not a promise of a single CSV with your chosen dates and columns. Health.md cannot turn that ZIP into daily exports. If you use a different sign-in or cannot find the expected data, follow [Google's account-specific export instructions](https://support.google.com/googlehealth/answer/14236615?hl=en).

## Use native TCX export for a workout

Google documents a separate GPS exercise export. In the Google Health app, open **Fitness**, choose the activity, then use **More → Export** and save or share the file. The result is a Training Center XML (**TCX**) activity file, not a daily CSV table.

Use that route when the destination expects a supported activity file. Keep it separate from an account archive or Health.md summary files rather than treating the formats as interchangeable.

## Check the Health Connect route before installing an exporter

Google's [Health Connect setup guide](https://support.google.com/googlehealth/answer/14506680?hl=en) requires **Android 9 or later** and an **adult Google Account** signed in to Google Health. Confirm that the connection is available on your phone.

1. Synchronize your Fitbit device with its app and identify one completed day with data you can check.
2. In Google Health, open **Connections → Partner apps**. Under **Add connections**, choose **Sync your favorite health apps → Set up**.
3. Review the information and permissions. For this fitness CSV workflow, choose the relevant fitness and wellness categories; medical-record access is not needed.
4. In Health Connect permissions, allow Google Health to **write** the categories you want to make available. Health.md needs separate **read** access to those categories.
5. Inspect an actual record for the chosen day in Health Connect before expecting an exporter to read it.

A successful connection indicator does not prove that every desired metric or historical day reached Health Connect. The shared store can contain several apps' records, and Google Health can also read from other connected apps. This workflow should not be treated as Fitbit-only output or a copy of every Google Health dashboard value.

### Fitbit Web API changes are a separate connection

Google's [current connection notice](https://support.google.com/googlehealth/answer/14236613?hl=en) says Fitbit Web APIs stop being supported starting October 30, 2026, while Health Connect and Apple Health connections are unaffected by that transition. This guide follows the Health Connect route. It does not promise that an older third-party Fitbit login or API integration will work.

## Export one known day with Health.md

Once you have verified the records in Health Connect:

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

1. Keep **Health Connect** selected in Health.md and authorize read access for the metrics you need.
2. Choose a writable local folder through Android's folder picker.
3. Select **CSV**, a small metric set and the completed day you checked.
4. Preview, export and open the saved file. Verify its date, units, values and destination before increasing the range.

Daily exports produce separate files for the selected days. The [Android setup guide](/docs/android/) covers permissions and folders, and the [Health Connect export guide](/health-connect-export/) covers formats and history limits.

## Inspect a fictional CSV first

[Download the Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv):

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Activity,Steps,12345,count,
2026-03-15,Activity,Walking Running Distance,9500.5,meters,
```

These are fictional Health Connect rows, not a Fitbit user's records or Google's archive format. To build a steps table, filter **Category = Activity**, **Metric = Steps** and **Unit = count** before converting Value to numbers. Other rows may contain text. Empty Timestamp cells in this excerpt identify daily summary rows.

Use a CSV-aware importer. Do not apply these column rules to a Takeout file or TCX activity without checking that file's own structure.

## Separate missing history from missing permissions

If the expected record is absent from Health Connect, check Google Health sharing and source synchronization first. If it is present but missing from the export, check Health.md read permissions, metric and date selection, and the saved destination.

Source backfill and app history access are separate limits. Health Connect normally permits reads from up to 30 days before read permission was first granted to Health.md, plus later data. Older access is conditional; see [Google's history guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). A longer range does not reconstruct records that were never shared.

Missing output is not a measured zero. For overnight sleep, check the [journal-date examples](/docs/sleep-date-attribution/#sleep-date-examples) before comparing a daily file with another app's calendar view.

## Keep the account and file destinations distinct

Google Health and Takeout use Google's account services. The separate local Health Connect-to-folder workflow requires no Health.md account and creates no Health.md server copy by default. Google, other source apps and synced folders have their own data handling rules.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup and no automatic device sync; the pilot is not generally available. This folder workflow does not upload to it. Read the [privacy policy's retention boundaries](/privacy-policy.html#retention) before choosing a destination.

For daily notes, continue with [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). For an existing Google archive or a workout file, keep the native options above as the starting point.
