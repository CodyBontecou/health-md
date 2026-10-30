---
title: "Export Withings data: native CSV or shared daily files"
description: "Download Withings CSV files or export records shared to Apple Health or Health Connect. Check the October 2026 account eligibility rules before installing Health.md."
lead: "Start with Withings' own CSV download. For selected records in daily files or notes, first check your account's sharing eligibility and the data actually available on your phone."
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
  - export-apple-health-weight-data
draft: false
tags:
  - withings
  - csv
  - apple-health
  - health-connect
---

**You do not need Health.md to download Withings' native CSV files.** Use that download when you want the measurements and fields Withings provides directly.

Health.md offers a separate workflow: save selected records already shared to Apple Health or Health Connect as daily CSV, JSON or Markdown files. These instructions do not import a Withings archive or configure a direct Withings account connection.

## Choose the export route

| Your task | Start with |
| --- | --- |
| Download Withings' own measurements for a spreadsheet | Withings' native CSV export |
| Save selected shared records beside daily notes or other health data | Apple Health or Health Connect, then Health.md |
| Resolve account eligibility or missing source sharing | Withings' current sharing instructions and support |

An exporter cannot recover records that Withings never shared to the phone's health store. Check the account rule below before expecting that route to work.

## Download CSV directly from Withings

Withings' [native export instructions](https://support.withings.com/hc/en-us/articles/31647944317201-Withings-App-Exporting-your-data) use this app route:

1. Open **Profile → Settings → Export All Health Data**.
2. Select the user profile and choose **Start my archive**.
3. Follow the emailed download instructions. Keep the original files and inspect their headers, dates and units before spreadsheet import.

The documented contents depend on your device and recorded data. Distance and weight follow the account's selected units; exported temperatures use Celsius. The native export is separate from the Share tab and from partner-app synchronization.

Health.md does not convert these files. If the native download answers your question, you can use it directly.

## Check the October 2026 sharing rule first

As checked on **October 30, 2026**, Withings' [Health Connect policy notice](https://support.withings.com/hc/en-us/articles/23104637348241-Partner-Apps-What-is-Health-Connect) says accounts created **on or after October 13, 2026** need an active **Withings+** subscription to transfer data to third-party apps such as Apple Health and Health Connect. Accounts created before that date are exempt from this change.

An [official Withings staff clarification dated October 15](https://support.withings.com/hc/en-us/community/posts/51887047154577-Unacceptable-Apple-Health-Sync-is-now-behind-a-99-year-paywall-for-new-accounts) confirms that the cutoff follows the account rather than a newly purchased device, and that native CSV/PDF downloads remain available without membership. Read the staff response for the policy, rather than treating other forum replies as instructions.

Check your account's eligibility with Withings if it is unclear. Installing Health.md does not change those upstream sharing requirements or make unshared records available. This guide does not offer a subscription workaround.

## Make sure the records reached your phone

Use the **export** direction in Withings. Importing Apple Health or Health Connect data into Withings is a different connection and does not establish that Withings wrote your measurements out.

### On iPhone

Follow [Withings' Apple Health export guide](https://support.withings.com/hc/en-us/articles/46746224229777-Partner-Apps-Apple-Health-Exporting-Withings-data-into-Apple-Health): open **Profile → Settings → Export health data to Apple Health**, then choose the categories to share.

Withings documents refreshing by opening its app, opening Apple Health, then returning to Withings and pulling down on Home. Check a completed day's actual records in Apple Health. A connected status alone is insufficient.

Allow Withings to write the relevant categories and grant Health.md separate read access. Check the record's source; other apps and devices can contribute to the same metric.

### On Android

Follow [Withings' Health Connect export guide](https://support.withings.com/hc/en-us/articles/27322856325905-Partner-Apps-Health-Connect-Exporting-Withings-data-into-Health-Connect): open **Profile → Settings → Export health data to Health Connect**. Its permission flow directs you to **Edit Permissions → Withings** to choose categories.

Check that Withings may write the metrics you need, then inspect an actual record for the chosen day in Health Connect. Health.md needs its own read access. Availability depends on source data, eligibility and permissions, not just the presence of an app connection.

## Export one known day with Health.md

Once the required records are present, choose the download for your phone:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Authorize read access for the metrics you checked. On Android, use the **Health Connect** source.
2. Choose a writable folder, a completed day and a small metric selection.
3. Select **CSV** for a table, **JSON** for a script or **Markdown** for notes.
4. Preview, export and open the saved file. Compare its date, units, values and destination with the source before widening the range.

Daily exports produce separate files for the selected days. The [iPhone CSV walkthrough](/apple-health-to-csv/) and [Android setup guide](/docs/android/) cover each platform's controls. For notes, continue with [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/) or [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/).

## Inspect the correct sample and units

Try the [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) or [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv). These illustrate Health.md output, not a Withings native archive or a real user's measurements.

Filter the intended Category, Metric and Unit before converting Value to numbers; other rows can contain text. Preserve units, dates and the intended version of each daily file. Do not append native Withings CSV rows to Health.md rows without mapping and validating their different structures.

A daily summary is not necessarily one original device measurement. For blood pressure, follow the [daily statistics versus paired readings explanation](/blog/export-apple-health-blood-pressure/) before interpreting an iPhone export. Do not reconstruct a systolic/diastolic pair by matching unrelated daily values. For Android, use its [format and source guide](/health-connect-export/) rather than assuming the Apple profile applies.

## Separate source history from app access

If the record is absent from Apple Health or Health Connect, check Withings eligibility, sharing and synchronization first. If it exists there but is absent from your file, check Health.md read access, selected metrics and dates, and the saved destination. Missing output is not a measured zero.

Health Connect normally permits reads from up to 30 days before read permission was first granted to Health.md, plus later records. Broader access is conditional; see [Android's older-data guidance](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). That permission window is separate from source backfill. A larger export range cannot recreate unshared history.

Shared stores can contain multiple origins. This workflow does not promise a Withings-only daily total or exact agreement with its app. Compare the same dates and units; use the [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples) for overnight records.

## Keep account services and destinations distinct

Withings' account download and sharing services have their own data handling rules. The separate local Health.md folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders, spreadsheets and recipients follow their own storage policies.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. It has no public signup, no automatic device sync and is not generally available. This folder workflow does not upload to the pilot. See the [privacy policy's retention boundaries](/privacy-policy.html#retention).
