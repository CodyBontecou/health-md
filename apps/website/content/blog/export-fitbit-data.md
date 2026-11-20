---
title: "Export Fitbit data in 2026: Takeout, TCX, CSV and Health Connect"
description: "How to export Fitbit data after the October 30, 2026 Fitbit Web API shutdown: Google Takeout archives, TCX workouts, CSV in Excel, and daily Health Connect files."
lead: "Fitbit data now lives under the Google Health name, and tools that logged in to the Fitbit Web API lost support on October 30, 2026. Here are the routes that still work, and which one fits an archive, a workout, a spreadsheet or a move to another app."
date: "2026-10-30"
updated: "2026-11-18"
verified: "2026-11-18"
verified_by: "Claude (agent)"
verified_method: traced
platform: android
category: "Workflow guide"
related:
  - export-garmin-connect-data
  - export-google-fit-data
  - export-health-connect-to-obsidian
draft: false
tags:
  - fitbit
  - google-health
  - health-connect
  - csv
---

To export Fitbit data in 2026, use Google's own routes first. Google's current [export help](https://support.google.com/googlehealth/answer/14236615?hl=en) calls the product **Google Health**, so older Fitbit screenshots may show different menus.

> **Quick answer**
>
> - **Everything, as an archive:** use [Google Takeout](https://takeout.google.com/) with **Google Health** selected. You get a ZIP or TGZ download of your account data, not one tidy spreadsheet.
> - **One workout:** in the Google Health app, open the activity and choose **More → Export**. GPS exercises save as a **TCX** file you can share or upload elsewhere.
> - **Ongoing daily CSV, JSON or Markdown on Android:** let Google Health write to Health Connect, then export selected days with an app that reads Health Connect, such as Health.md. This covers new days going forward, not your full history.

**You do not need Health.md to download Google's archive or export a TCX workout.** Health.md does not read a Takeout ZIP, does not call any Fitbit or Google Health API, and does not migrate a Fitbit account to another service.

## What changed on October 30, 2026

Google's [connection notice](https://support.google.com/googlehealth/answer/14236613?hl=en) says: starting **October 30, 2026**, Fitbit Web APIs are no longer supported.

**What stopped.** Tools that log in to the Fitbit Web API lost their supported connection. That includes many older export scripts, spreadsheet add-ons and third-party sync apps. Google says the app developer has to enable reconnection; Google Health Support cannot restore a broken connection. Some developers have updated their apps to work with Google Health, and Google lists affected apps under **Connections → Partner apps** in the Google Health app.

**What still works.**

- **Health Connect and Apple Health connections.** Google says people using these connections are not affected and their data keeps syncing.
- **Data already in your account.** Google says data already synced to your Google Health account is kept, not deleted.
- **The native export routes.** The [export help](https://support.google.com/googlehealth/answer/14236615?hl=en) still documents the Takeout download and the in-app TCX export. The connection notice does not say either is changing.

**What it means for you.** If a tutorial asks you to create a Fitbit developer app, paste an API token or authorize a script against the Fitbit Web API, expect it to fail. Ask the tool's developer whether it now supports Google Health. Otherwise use one of the routes below.

## Choose the export you need

| Your goal | Use |
| --- | --- |
| Keep a full copy of your account data | Google Takeout with **Google Health** selected |
| Save one GPS workout for another app | The Google Health app's **TCX** export |
| Open your history in Excel or Google Sheets | Any CSV files inside the unzipped Takeout archive |
| Get new daily CSV, JSON or Markdown files on Android | Google Health → Health Connect → Health.md |

## Download everything with Google Takeout

For a **Google Account** sign-in, Google points you to its data download tool:

1. Open [Google Takeout](https://takeout.google.com/) with the account that holds your Fitbit/Google Health data.
2. Select **Google Health**, review the export options and create the export.
3. Choose a delivery method and file type. Google's [Takeout help](https://support.google.com/accounts/answer/3024190?hl=en) lists email links or Google Drive, Dropbox, OneDrive and Box, and ZIP or TGZ archives. ZIP opens on almost any computer.
4. Wait for the archive. Google says it can take from a few minutes to a few days, and archives larger than the size limit you picked are split into several files. Keep every part.

If you still sign in with an **original Fitbit login**, the same help page sends you to **Data Export** on the Fitbit settings page instead. There you can request a full archive, or use **Export a selection of your Fitbit data** to choose a time period, data types and a file format. Google's page does not list which file formats that form offers.

### What is inside the archive

Google does not publish a folder-by-folder layout of the Google Health archive, and it can vary by account, devices and the data types you used. Here is what Google does document:

- The [export help](https://support.google.com/googlehealth/answer/14236615?hl=en) names activity, exercise, sleep and heart rate as examples of exported data.
- The [Takeout help](https://support.google.com/accounts/answer/3024190?hl=en) says each archive includes an **archive_browser.html** file that explains the file formats and how to open them.

Google's pages do not say which Google Health files are CSV and which are JSON, so this guide does not list them. Open `archive_browser.html` first. It describes your own archive, which is more reliable than a third-party list, including this one.

### Open the CSV files in Excel or Google Sheets

Unzip the archive first. Spreadsheet apps cannot read files that are still inside the ZIP. Check `archive_browser.html` or the file extensions to see which files are CSV.

1. Find the `.csv` files you want and copy them somewhere else, so the original archive stays unchanged.
2. In Excel, use **Data → From Text/CSV**. In Google Sheets, use **File → Import**. These importers let you check the delimiter, encoding and column types before loading.
3. Check the date and time columns and the units before you sum or chart anything.

JSON files are not spreadsheets. Open them in a text editor, or convert them with a tool you trust. Our [Excel](/blog/apple-health-to-excel/) and [Google Sheets](/blog/apple-health-to-google-sheets/) guides are written for Apple Health files, but their tips on importing, typing columns and building pivot tables apply to any health CSV.

## Export a single workout as TCX

Google documents a separate GPS exercise export. In the Google Health app, open **Fitness**, choose the activity, then tap **More → Export** and save or share the file. The result is a Training Center XML (**TCX**) activity file, not a daily CSV table.

TCX is the format Google provides; the help page does not offer GPX. If a destination asks for GPX, check that service's own importer or converter for TCX support first. Keep the original file either way.

## Moving to Garmin or another platform

Every destination accepts different files, and a Takeout archive is a backup, not a migration format. The CSV and JSON files are not built to be imported into another company's account. Check your new service's own import help for the file types it accepts. Individual workout files such as TCX are the most portable part of a Fitbit export.

Health Connect does not move your history either. It is a shared store on your Android phone where each app chooses whether to write data, read data or both. Garmin, for example, documents a one-way connection: [Garmin Connect writes to Health Connect](/blog/export-garmin-connect-data/) but does not read data back through it. Your old Fitbit records will not appear in a Garmin account because both apps use Health Connect.

For a fresh start, keep your Takeout archive as your Fitbit record, export the workouts you care about as TCX, and let your new device write new data from now on. Our [Garmin Connect export guide](/blog/export-garmin-connect-data/) covers Garmin's own downloads.

## Ongoing daily files on Android: Health Connect → Health.md

This route gives you new, selected daily files on your phone. It reads records Google Health has shared with Health Connect. It does not use a Fitbit API, and it cannot recover data that was never shared.

### Connect Google Health to Health Connect

Google's [Health Connect setup guide](https://support.google.com/googlehealth/answer/14506680?hl=en) requires **Android 9 or later** and an **adult Google Account** signed in to Google Health. Google notes that Fitbit accounts may need to move to a Google Account first.

1. Synchronize your Fitbit device with its app and identify one completed day with data you can check.
2. In Google Health, open **Connections → Partner apps**. Under **Add connections**, choose **Sync your favorite health apps → Set up**.
3. Review the information and permissions. For this fitness CSV workflow, choose the relevant fitness and wellness categories; medical-record access is not needed.
4. In Health Connect permissions, allow Google Health to **write** the categories you want to make available. Health.md needs separate **read** access to those categories.
5. Inspect an actual record for the chosen day in Health Connect before expecting an exporter to read it.

A successful connection indicator does not prove that every desired metric or historical day reached Health Connect. The shared store can contain several apps' records, and Google Health can also read from other connected apps. This workflow should not be treated as Fitbit-only output or a copy of every Google Health dashboard value.

### Export one known day with Health.md

Once you have verified the record in Health Connect:

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

1. Keep **Health Connect** selected in Health.md and authorize read access for the metrics you need.
2. Choose a writable local folder through Android's folder picker.
3. Select **CSV**, a small metric set and the completed day you checked.
4. Preview, export and open the saved file. Verify its date, units, values and destination before increasing the range.

Daily exports produce separate files for the selected days, and JSON and Markdown are available too. Once a manual export works, the [Android scheduling guide](/docs/android/#scheduling-and-automation) covers repeating exports. The [Android setup guide](/docs/android/) covers permissions and folders, and the [Health Connect export guide](/health-connect-export/) covers formats and history limits.

### Inspect a fictional CSV first

[Download the Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv):

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Activity,Steps,12345,count,
2026-03-15,Activity,Walking Running Distance,9500.5,meters,
```

These are fictional Health Connect rows, not a Fitbit user's records or Google's archive format. To build a steps table, filter **Category = Activity**, **Metric = Steps** and **Unit = count** before converting Value to numbers. Other rows may contain text. Empty Timestamp cells in this excerpt identify daily summary rows.

Use a CSV-aware importer. Do not apply these column rules to a Takeout file or TCX activity without checking that file's own structure. Health Connect records are also shaped differently from Apple Health data; the [data model comparison](/blog/apple-health-vs-health-connect-data-models/) explains why.

## Separate missing history from missing permissions

If the expected record is absent from Health Connect, check Google Health sharing and source synchronization first. If it is present but missing from the export, check Health.md read permissions, metric and date selection, and the saved destination.

Source backfill and app history access are separate limits. Health Connect normally permits reads from up to 30 days before read permission was first granted to Health.md, plus later data. Older access is conditional; see [Google's history guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). A longer range does not reconstruct records that were never shared. For your full Fitbit history, use the Takeout archive.

Missing output is not a measured zero. For overnight sleep, check the [journal-date examples](/docs/sleep-date-attribution/#sleep-date-examples) before comparing a daily file with another app's calendar view.

## Keep the account and file destinations distinct

Google Health and Takeout use Google's account services. The separate local Health Connect-to-folder workflow requires no Health.md account and creates no Health.md server copy by default. Google, other source apps and synced folders have their own data handling rules.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. There is no public signup and no automatic device sync; the pilot is not generally available. This folder workflow does not upload to it. Read the [privacy policy's retention boundaries](/privacy-policy.html#retention) before choosing a destination.

## Common questions

### Can I export Fitbit data to Excel?

Yes, for any CSV files in your Google Takeout archive. Select Google Health, download and unzip the archive, then import those files with Excel's Data → From Text/CSV. JSON files need converting first; the archive's archive_browser.html file explains its formats.

### Does Fitbit export CSV?

Google's help does not promise a CSV file. The Takeout archive includes an archive_browser.html file that lists its formats, and original Fitbit logins can choose a file format in Export a selection of your Fitbit data. Single GPS workouts export as TCX. On Android, Health.md can write new days from Health Connect as CSV.

### Why did my Fitbit export app stop working?

Google stopped supporting the Fitbit Web API on October 30, 2026. Tools that log in to that API lose their connection unless their developer has updated them for Google Health. Google Takeout, in-app TCX export and Health Connect sharing still work.

### Can I move Fitbit data to Garmin?

Not as a full history transfer. Export the workouts you want as TCX and check what Garmin Connect accepts. Keep a Takeout archive as your record, and let the new device write new data from then on.

For daily notes instead of spreadsheets, continue with [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/). If you used Google Fit rather than a Fitbit device, Fit history is a separate Takeout product: see the [Google Fit export guide](/blog/export-google-fit-data/) for the Takeout steps and the Google Health migration Google has announced.
