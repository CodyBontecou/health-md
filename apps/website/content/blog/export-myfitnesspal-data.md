---
title: "Export MyFitnessPal data: CSV, reports or shared records"
description: "Compare MyFitnessPal's paid CSV export, free printable report and shared Apple Health or Health Connect records. Check meal details and history before exporting."
lead: "Choose native CSV for MyFitnessPal's meal-level history, a website report for printing, or daily Health.md files for selected records already shared to your phone."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-cronometer-data
  - export-apple-health-weight-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - myfitnesspal
  - nutrition
  - csv
  - health-connect
---

MyFitnessPal offers different ways to get information out of your account. **Its native CSV export requires Premium or Premium+. Free accounts can use a printable website report or diary sharing.** You do not need Health.md for those options.

Health.md serves a separate task: daily CSV, JSON or Markdown files from selected records already available in Apple Health or Health Connect. It does not unlock MyFitnessPal's paid export, import its downloaded ZIP or reproduce its complete account history.

## Choose the output before installing anything

| What you need | Start with |
| --- | --- |
| MyFitnessPal's meal-level nutrition, progress and exercise files | Native CSV export with an eligible subscription |
| A printable food report from a free account | MyFitnessPal website report |
| Ongoing diary access for another person | MyFitnessPal diary sharing; the viewer needs an account |
| Selected shared records beside other daily health data or notes | Verify Apple Health or Health Connect records, then use Health.md |

These routes preserve different information. A printable page, a meal-level CSV and a daily nutrient total are not interchangeable exports.

## Download MyFitnessPal's native CSV files

MyFitnessPal's [file export instructions](https://support.myfitnesspal.com/hc/en-us/articles/360032273352-Export-your-nutrition-progress-and-exercise-data), checked **October 30, 2026**, describe these routes:

- **Website:** open **Reports → Export**, select dates and export.
- **iPhone:** open **More** or the profile icon, then **Nutrition → Export → Date Range → Export My Information**.
- **Android:** open **More → Progress or Nutrition → Export**, confirm the email address and dates, then export.

Use the emailed download link on a computer and unzip the files. Each export includes three CSVs: **Your Nutrition**, **Your Progress** and **Your Exercise**. The nutrition file contains meal-level details; the other files cover measurements and exercise history. Inspect the actual headers, dates and units before analysis.

Keep the originals. A meal summary does not establish that you have an individual-food or recipe library that another app can import.

## Use the free website report when printing is enough

MyFitnessPal's [free-account instructions](https://support.myfitnesspal.com/hc/en-us/articles/360032623371-Export-your-data-or-share-your-diary-with-a-Trainer-Doctor-or-Nutritionist) use **Food → View Full Report (Printable)** on the website. Choose the date range, select **Change Report**, then print or use your computer's PDF option where available.

The printable report is a separate option from downloadable CSV. Diary sharing instead grants another MyFitnessPal user ongoing access to your Food and Exercise Diary. Choose deliberately if the goal is a one-time file rather than continued viewing.

## Check the iPhone sharing limits

Follow MyFitnessPal's [Apple Health connection guide](https://support.myfitnesspal.com/hc/en-us/articles/360032271092-Apple-Health-connection-and-syncing): open **More** or the profile icon, then **Settings → Sharing & Privacy → HealthKit Sharing**. Authorize the categories you intend to share; later changes are made in the iPhone's Health access settings.

The documented directions matter:

- **Food goes to Apple Health** as meal summaries and supported nutrients. **Caffeine, vitamin A and original food timestamps do not sync.** A timestamp present in a health-store record should not be assumed to preserve the original meal time.
- **Weight moves both ways.** Inspect the source and actual value before exporting it.
- **Exercise and sleep go into MyFitnessPal from Apple Health.** Seeing them inside MyFitnessPal does not mean MyFitnessPal wrote them out.

MyFitnessPal also advises against connecting Apple Health when different people's MyFitnessPal accounts share one iPhone, because Health cannot separate those accounts. Resolve that account setup before relying on shared records.

## Check the Android sharing limits

MyFitnessPal's [current connection comparison](https://support.myfitnesspal.com/hc/en-us/articles/49553147148685-The-difference-between-Google-Health-Fitbit-and-Health-Connect) requires **Android 10 or later** and **MyFitnessPal 22.22.0 or later** for its Health Connect integration. Use **More** or the profile icon, then **Apps & Devices → Health Connect → Connect**, and complete the permission prompts.

That article also explains why MyFitnessPal asks users to choose between Health Connect and an existing Google Health or Samsung Health connection. Review the effect on your current setup before changing connections; duplicate activity inputs can affect calorie adjustments. Health Connect is the phone's sharing layer, distinct from Google Health.

The [Health Connect FAQ](https://support.myfitnesspal.com/hc/en-us/articles/10553948248973-Health-Connect-FAQ-and-Troubleshooting) adds these limits:

- Food is shared as **meal summaries, not individual foods**, starting from the linking day. Default meal headings map to their meals; custom headings are grouped as **Other**.
- Water logged in MyFitnessPal goes to Health Connect. Do not assume the reverse direction.
- MyFitnessPal can send logged cardio exercise, but exercises it received through other third-party apps are excluded from that outgoing route.

Inspect one known day's actual records in Health Connect. A connected status does not establish that a specific nutrient, food field or older record is present. A wider export date range cannot create unshared history.

## Save selected shared records with Health.md

Continue if the records you need are already visible in the phone's health store:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Grant Health.md read access to the relevant categories. On Android, choose the **Health Connect** source.
2. Select the **Nutrition** metrics or other measurements you verified. Start with one completed day and a writable folder.
3. Choose **CSV** for a table, **JSON** for structured processing or **Markdown** for daily notes.
4. Preview, export and open the saved file. Compare its date, values, units and destination with the source before extending the range.

Use [your first iPhone export](/docs/iphone-first-export/) or the [Android guide](/docs/android/) for setup and platform history access. Daily exports produce separate files for the selected days. Daily nutrition totals summarize returned health-store records; they do not recreate MyFitnessPal's native files, account-specific calorie adjustments or meal times that were not shared.

Other apps can contribute records to the same store, so the result is not automatically MyFitnessPal-only. Platform fields and optional detail can differ. Check the [format reference](/docs/format/) and actual output instead of assuming Apple and Android write identical data.

## Inspect the files before combining them

Try the [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) or [fictional Apple JSON](/docs/reference/generated/core/summary-day.json). The separate [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) contains activity examples. These are Health.md examples, not MyFitnessPal native exports or proof that MyFitnessPal supplies every sample field.

For a nutrition example and its exact CSV filter, see the [Cronometer guide's sample section](/blog/export-cronometer-data/#section-check-a-sample-and-its-units). The row contract illustrates Health.md output; Cronometer and MyFitnessPal have different sharing rules.

Use a CSV-aware importer. Select the intended Category, Metric and Unit before converting Value to numbers, because metadata and text can share that column. Keep grams, milligrams, energy and water units distinct. Follow [Apple Health to Excel](/blog/apple-health-to-excel/) for spreadsheet setup, adapting the filters to the actual file.

Keep native meal totals, daily health-store totals and exercise energy separate. Calories eaten, calories burned, net calories and an app's calorie adjustment measure different things. Check overlapping dates and re-exports rather than counting them twice. For weight, use the [latest-record explanation](/blog/export-apple-health-weight-data/) instead of summing values.

An absent field is unavailable data, not zero. Missing nutrients, food names or original meal times cannot be recovered from a daily total. Compare the same completed day, sources, units and time context before treating different apps' figures as equivalent.

## Choose the storage and sharing boundary

Core folder exports require no Health.md account and create no Health.md server copy by default. Synced folders, online spreadsheets and recipients follow their own storage and privacy rules. Review the actual file before sharing it.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. See the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup checks.
