---
title: "Export Cronometer data: native CSV or daily health files"
description: "Download Cronometer's native diary CSV, or save selected Apple Health and Health Connect records as daily files. Check sharing, units and meal-detail limits."
lead: "Keep Cronometer's native CSV for diary entries and meal groups. Use Health.md for selected shared records beside other daily health data or notes."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - apple-health-to-excel
  - export-myfitnesspal-data
  - export-dexcom-data
draft: false
tags:
  - cronometer
  - nutrition
  - csv
  - health-connect
---

**Cronometer already exports CSV files. You do not need Health.md to download its diary data.** Use the native export when you need the fields and meal organization Cronometer provides directly.

Health.md offers a separate workflow: daily CSV, JSON or Markdown files from selected records already shared to Apple Health or Health Connect. It does not import Cronometer's downloaded files or connect directly to your Cronometer account.

## Choose the data you want to keep

| Your task | Start with |
| --- | --- |
| Preserve Cronometer diary entries, notes or meal groups | Cronometer's native CSV export |
| Compare native daily nutrition totals with meal-group totals | Cronometer Daily Nutrition export options |
| Keep selected shared nutrition or biometric records beside daily notes | Verify phone health-store records, then use Health.md |
| Reproduce a nutrition report or its inclusion settings | Cronometer's report controls; a shared daily file is a different representation |

Food names, portions, recipes, targets, scores, diary groups and nutrient totals are not interchangeable. Choose a representation that retains the information you need before combining files or installing an exporter.

## Download CSV directly from Cronometer

Cronometer's [Account Settings instructions](https://support.cronometer.com/hc/en-us/articles/360018760151-Account-Settings), checked **October 30, 2026**, describe **Account Data → Export Data**. Choose the export type and date range, then download the CSV. Available types include diary entries, exercises, biometrics, notes and nutrition summaries.

For **Daily Nutrition**, check **Include diary group rows** when you want a meal-group breakdown; leave it off for daily totals. Keep the original file and inspect its headers, units and dates before spreadsheet import.

The [mobile Nutrition Report guide](https://support.cronometer.com/hc/en-us/articles/360019864891-Mobile-Nutrition-Report) directs printing and exporting to the website. Cronometer's [subscription documentation](https://support.cronometer.com/hc/en-us/articles/360028026971-Subscription-Types) lists raw-data export among Basic account features. Report and chart options are separate; do not assume a report's access or date-range rules also define native CSV availability.

If that native file meets your needs, use it directly. Health.md does not convert it.

## Check sharing into the phone's health store

First verify one completed day with records you recognize. Cronometer needs permission to write the relevant categories; Health.md needs its own permission to read them. An app connection alone does not prove that a particular nutrient or historical entry reached the health store.

### iPhone: Cronometer to Apple Health

Follow Cronometer's [Apple Health setup guide](https://support.cronometer.com/hc/en-us/articles/360020734212-Apple-Health-Apple-Watch): open **More → Connect Apps & Devices → Apple Health**, then review the read and write categories you authorize.

Cronometer's [Apple Health integration overview](https://cronometer.com/blog/apple-health/) describes exporting selected nutrients and biometrics into Apple Health. It does not establish that every diary field is shared. Inspect the actual records for the day and nutrient you need.

The setup guide's **Backfill** control imports Apple Health data **into Cronometer**. It is not a promise to send your entire Cronometer diary back into Apple Health. Check the sharing direction before using a history or troubleshooting instruction.

### Android: Cronometer to Health Connect

Cronometer's [current Health Connect instructions](https://support.cronometer.com/hc/en-us/articles/22731903751316-Health-Connect), updated September 30, 2026, list **Food** and **Water** among outgoing data, along with supported biometrics. Do not assume that every nutrient or native diary field is included in those categories.

Open **More → Connect Apps & Devices → Health Connect → Sync with Health Connect** and authorize the categories you intend to share. Review Cronometer under Health Connect's app permissions, then inspect actual shared records for your known day. Follow the [Health.md Android guide](/docs/android/) for system availability, read permissions and history access.

Import and export lists differ. Receiving sleep or exercise in Cronometer does not establish that Cronometer writes those records out through the same connection. A new connection or wider export date range also does not guarantee historical backfill.

## Make one daily export with Health.md

Continue once the records you need are available in Apple Health or Health Connect:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Grant read access to the relevant health categories. On Android, choose the **Health Connect** source.
2. Select the **Nutrition** metrics you verified, or the specific biometric you need. Start with one completed day and a writable folder.
3. Choose **CSV** for table inspection, **JSON** for structured processing or **Markdown** for daily notes.
4. Preview, export and open the actual saved file. Compare the date, metric, value and unit with the phone's source records before extending the range.

A longer range creates separate daily files. Use [your first iPhone export](/docs/iphone-first-export/) or the [Android walkthrough](/docs/android/) for setup. Daily nutrition values summarize the records returned for that day; they do not reconstruct a complete Cronometer diary, recipes or native report settings.

Apple and Android can expose different fields and detail. Review the [format guide](/docs/format/) and the fields actually present instead of assuming that the same format name makes exports identical. Other apps can write nutrition or water records too, so the result is not automatically a Cronometer-only report.

## Check a sample and its units

The [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) contains this exact example:

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Nutrition,Protein,120.0,g
```

This is synthetic Health.md output, not a Cronometer file or proof that Cronometer supplied every sample field. The final Timestamp field is omitted in this daily row; use a CSV-aware importer that leaves it empty while keeping the other columns aligned.

For this example, filter **Category = Nutrition**, **Metric = Protein** and **Unit = g** before converting Value to numbers. The complete CSV also contains text and metadata. Other nutrients can use different units, such as mg, kcal or L; inspect each row instead of treating all numbers as grams.

The [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) and separate [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) illustrate their respective outputs. The Android excerpt contains activity examples, not a Cronometer meal export. Do not transfer the Apple row filter to another schema without inspecting its actual labels and units.

For spreadsheet setup, follow [Apple Health to Excel](/blog/apple-health-to-excel/), adapting the filter to the metric you verified. Keep native diary rows, meal-group subtotals and daily health-store totals separate; summing them together can count the same intake more than once. Check overlapping re-exports and retain the intended version of each day's file.

## Explain differences before combining data

- **A record is missing from the phone:** check Cronometer's outgoing category, write permissions and synchronization. Health.md cannot export an unshared entry.
- **The phone has it but the file does not:** check Health.md read access, metric selection, dates, history access and the saved destination.
- **Totals differ:** compare the same completed day, sources, units, timezone and detail level. Cronometer report averages and day-inclusion settings are different from a selected day's exported values.
- **A food name, recipe or meal group is missing:** use Cronometer's native export for its diary representation. A nutrient total cannot reconstruct the foods that contributed to it.
- **Weight needs a separate interpretation:** follow the [Apple Health weight guide](/blog/export-apple-health-weight-data/) for the latest-record rule; weight is not a sum like a nutrient total.

An absent row or field is unavailable data, not measured zero. A partial day is not necessarily a full day's intake, and a shared file alone does not establish dietary completeness. This guide explains export choices and file contents, not nutrition targets or clinical interpretation.

## Choose the destination deliberately

Core folder exports require no Health.md account and create no Health.md server copy by default. Synced folders, online spreadsheets and services you share files with follow their own storage and privacy rules. Review the actual export before sharing it.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. Read the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup checks.
