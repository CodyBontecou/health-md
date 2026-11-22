---
title: "Export Huawei Health data: request the ZIP, open it, or save daily files"
description: "Request your Huawei Health data in Privacy Centre, open the password ZIP, find JSON workouts in 15-day groups, or save daily Markdown, CSV or JSON files."
lead: "Request the copy in Privacy Centre, open the password-protected ZIP, expect JSON grouped by period, or save daily files from Apple Health or Health Connect."
date: "2026-10-31"
updated: "2026-11-22"
verified: "2026-11-22"
verified_by: "Claude (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-strava-data
  - export-zepp-amazfit-data
  - export-health-connect-to-obsidian
draft: false
tags:
  - huawei
  - export
  - strava
  - apple-health
  - health-connect
---

**To export your Huawei Health data, request a copy in your HUAWEI ID's Privacy Centre, wait for Huawei's email, then unzip the download with the password you set when you made the request.** Huawei's [Strava support article](https://consumer.huawei.com/es/support/content/es-es15919588/) (in Spanish) says the email can take several days and that workouts arrive as JSON files that each cover about 15 days, not one file per workout. Huawei's [HUAWEI ID data page](https://consumer.huawei.com/en/support/content/en-us00746223/) says a prepared copy stays downloadable for 21 days. Health.md does not sign in to Huawei or import this archive; it only saves daily files from records already in Apple Health or Health Connect.

## Request the full Huawei Health copy

1. Sign in to the HUAWEI ID you use for Huawei Health, in the app (**Settings → HUAWEI ID → Privacy center → Manage Your Data → Request Your Data**, per Huawei's [regional privacy statement](https://privacy-dre.dbankcdn.com/agreement/scope/huawei/health/privacy-statement/aspiegelgroup_b0_20250626_0/default/privacy-statement-en-us.htm?bgmode=white&ctype=huawei&timestamp=2025100217)) or on the [Huawei privacy portal](https://privacy.consumer.huawei.com/tool).
2. Open the Privacy Centre and choose **Request Your Data**, then select **Health**. Huawei's Spanish article gives the path as HUAWEI ID → Privacy Centre → Request Your Data → Health.
3. Confirm the request and set the password when asked. You need that password later.
4. Wait for Huawei's email saying the copy is ready, then download it.

What arrives, according to Huawei:

- **A ZIP** that you open with the password you set during the request.
- **A 21-day window.** Huawei's HUAWEI ID page says the prepared data can be downloaded for 21 days, after which you must request it again. That is Huawei's rule for HUAWEI ID data in general, not a promise specific to Health.
- **File types such as .json, .csv or .pdf** for app data, per the same page.
- **Workouts as JSON.** Huawei's Strava article says to look in the "motion path detail data & description" folder, where JSON files each cover about 15 days of exercise.
- **A converter requirement.** Huawei says you need to convert these files before Strava can use them; it does not name a converter.

Keep an untouched copy of the ZIP. Do not rename JSON files to `.csv` and expect spreadsheet columns.

## If your Huawei data never arrived

- Check that the email address on your HUAWEI ID is one you can read, and look in the spam folder.
- Remember Huawei says the copy can take several days; do not assume it failed after one day.
- If the link no longer works, the 21-day window may have passed. Request the copy again.

## Export a single workout route

Huawei's Strava article gives this in-app path: **Health → Exercise records**, pick an outdoor workout, open **Route**, choose **Export route**, then pick a format and save. Some formats may need converting before another service accepts them.

## Send workouts to Strava

Per the same article, update Huawei Health, then go to **Me → Privacy management → Data sharing and authorization → Strava**, connect, and sign in to Strava. Huawei presents this for new workouts and does not say it copies older ones. For older activities, use the full copy or a single-route export and upload manually. If you want to keep Strava activities in daily files, see the [Strava export guide](/blog/export-strava-data/).

## Moving to a new phone or account is a different job

A data copy is not the same as cloud sync or a phone-to-phone transfer. Huawei's [cloud-sync support page](https://consumer.huawei.com/en/support/content/en-us01057432/) describes syncing the app to Huawei's cloud. Nothing here shows that an old account can be merged into a new one, so do not rely on it. Keep the ZIP as your record.

## Check the phone-sharing route before installing an exporter

Huawei's [September 2026 regional statement](https://privacy-dre.dbankcdn.com/agreement/scope/huawei/health/privacy-statement/hkgroup_b0_20260910_0/default/privacy-statement-en-us.htm?bgmode=white&ctype=huawei&timestamp=2026100317) describes consent-based sharing of fitness and sleep data to **Apple Health Kit** and, on Android, **Health Connect**, pointing to **Me → Privacy management → Data sharing and authorization**. That is regional documentation, not proof that every account, app version or wearable offers both, and it does not establish a field mapping or historical backfill.

Before continuing:

1. Inspect the connection offered by your own Huawei Health app and authorize only the categories you need.
2. Open Apple Health or Health Connect and inspect a completed day that should contain those records.
3. Check the source app, dates, units and entries. A sharing toggle alone does not prove records arrived.
4. Check an older day separately if history matters. Today's successful sharing does not show earlier years were copied.

## Save daily files from Apple Health or Health Connect

If the records are present in the phone's health store, Health.md writes one readable Markdown, CSV or JSON file per day into a folder you choose, from records already on the phone. This is not a reconstruction of the Huawei archive.

**iPhone:** follow the [first iPhone export guide](/docs/iphone-first-export/). Give Health.md read authorization, select a writable folder and start with one completed day in Markdown. Preview before writing; add CSV or JSON afterwards.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

**Android:** use the [Health Connect export guide](/health-connect-export/) to check permissions, select metrics and dates, preview one day and save the output. What you get depends on the records and permissions on that device, not simply on owning a Huawei watch.

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md for Android</a>

Do not assume the phone export recreates Huawei's account download, training scores or original workout files. A daily summary is not the original sequence of sensor readings. On iPhone, the selected-day steps query sums authorized Apple Health records; it is not a Huawei-only source filter, so verify the source data if several apps write steps.

## Keep the two outputs separate

Label the Huawei copy and your daily phone exports separately. For a **fictional** example, a day with no shared step records stays missing in the daily file; it must not become an invented zero-step day. Compare a known completed day's date, metric and unit in the phone health store with its file, then check one older day before widening the range.

Use the [Excel guide](/blog/apple-health-to-excel/) for daily CSV, or the [Obsidian guide](/blog/export-apple-health-data-to-obsidian/) for Markdown notes. Neither turns a Huawei archive into a Health.md import.

Core folder export needs no Health.md account and creates no Health.md health-data server copy by default. Your chosen cloud folder or online spreadsheet has its own storage rules. Keep the Huawei ZIP and your exports private; see the [local-only workflow](/blog/export-health-data-without-the-cloud/).
