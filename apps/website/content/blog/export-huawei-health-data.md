---
title: "Export Huawei Health data: account copy or daily files"
description: "Request a Huawei Health data copy first, or save daily files from records already shared to Apple Health or Health Connect. Check regional and history limits."
lead: "Choose between preserving your Huawei account data and organizing the records already available on your phone."
date: "2026-10-31"
updated: "2026-10-31"
verified: "2026-10-31"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-zepp-amazfit-data
  - export-health-connect-to-obsidian
  - export-health-data-without-the-cloud
draft: false
tags:
  - huawei
  - export
  - apple-health
  - health-connect
---

**Request your data from Huawei first if you want a copy of the information held in your Huawei Health account.** Health.md serves a separate task: saving daily files from selected records already available in Apple Health or Android Health Connect. It does not sign in to Huawei or import a Huawei account archive.

## Request the native Huawei data copy

Huawei's [regional privacy statement](https://privacy-dre.dbankcdn.com/agreement/scope/huawei/health/privacy-statement/aspiegelgroup_b0_20250626_0/default/privacy-statement-en-us.htm?bgmode=white&ctype=huawei&timestamp=2025100217) documents a data request through **Settings → HUAWEI ID → Privacy center → Manage Your Data → Request Your Data**, or the [Huawei privacy portal](https://privacy.consumer.huawei.com/tool). Use the instructions and statement applicable to your account's region. This download does not require Health.md.

Keep an untouched copy of the result. Check its actual files, dates, units and categories before choosing a spreadsheet or conversion workflow. The cited statement describes a machine-readable copy, not a guaranteed CSV layout, delivery deadline or complete device-history archive. Do not rename an unfamiliar file to `.csv` and expect spreadsheet columns.

Huawei's [cloud-sync support page](https://consumer.huawei.com/en/support/content/en-us01057432/) describes syncing the app to Huawei's cloud. That is a different operation from writing records to Apple Health or Health Connect. Enabling cloud sync alone is not evidence that another phone app can read your data.

## Check the phone-sharing route before installing an exporter

Huawei's [September 2026 regional statement](https://privacy-dre.dbankcdn.com/agreement/scope/huawei/health/privacy-statement/hkgroup_b0_20260910_0/default/privacy-statement-en-us.htm?bgmode=white&ctype=huawei&timestamp=2026100317) describes consent-based sharing of fitness and sleep data to **Apple Health Kit** and, on Android, **Health Connect**. It points to **Me → Privacy management → Data sharing and authorization**.

That is regional documentation, not proof that every Huawei account, app version, phone or wearable exposes both connections. It does not establish a field-by-field mapping or a historical backfill guarantee. If your app does not offer the relevant destination, use the native data request rather than buying an exporter to solve a missing connection.

Before continuing:

1. Inspect the connection offered by your own Huawei Health app and authorize only the categories you need.
2. Open Apple Health or Health Connect and inspect a completed day that should contain those records.
3. Check the source app, dates, units and available entries. A sharing toggle alone does not prove that records arrived.
4. Check an older day separately if history matters. Today's successful sharing does not demonstrate that earlier years were copied.

## Save the available records as daily files

Continue only when the required records are present in the phone's health store and you want Markdown, CSV or JSON files for personal notes or analysis.

**iPhone:** follow the [first iPhone export guide](/docs/iphone-first-export/). Give Health.md separate read authorization, select a writable folder and start with one completed day in Markdown. Preview before writing; add CSV or JSON after that small export works.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

**Android:** use the [Health Connect export guide](/health-connect-export/) to check permissions, select metrics and dates, preview one day and save the output. Availability depends on the records and permissions on that Android device, not simply having a Huawei watch.

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md for Android</a>

Do not assume the phone export recreates Huawei's account download, training scores or original workout files. Available categories and export profiles differ between platforms. A daily summary is also not the original sequence of sensor readings.

For example, on iPhone, Health.md's selected-day steps query calculates a sum over authorized Apple Health records. It is not a Huawei-account query or a Huawei-only source filter. If multiple apps write records, verify the source data before interpreting the result as a watch-specific total. Missing records must not become invented zero values.

## Keep the two outputs separate

Label your native account copy and daily phone exports separately. For a **fictional** example, a day with no shared step records should remain missing; it must not become a fabricated zero-step day. For your own export, compare a known completed day's date, metric and unit in the phone health store with the corresponding daily file. Then check one older day before extending the export range. This checks the workflow you actually have; it does not validate every metric or reconstruct absent history.

Use the [Excel guide](/blog/apple-health-to-excel/) for the daily CSV you actually exported, or the [Obsidian guide](/blog/export-apple-health-data-to-obsidian/) for Markdown notes. Neither workflow turns a Huawei archive into a Health.md import.

Core folder export needs no Health.md account and creates no Health.md health-data server copy by default. Your chosen cloud folder or online spreadsheet has its own storage rules. Keep account archives and personal exports private; see the [local-only workflow](/blog/export-health-data-without-the-cloud/).
