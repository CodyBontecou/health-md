---
title: "Export OMRON connect data: Excel, PDF or CSV (both apps)"
description: "OMRON connect US/CAN/EMEA: History → Share for Excel/PDF. OMRON Connect: ･･･ → Export measurement data for CSV. Plus the Apple Health route."
lead: "OMRON ships two apps with different export menus. Find yours, follow its steps, and fix a missing Share, History or ･･･ button."
date: "2026-10-30"
updated: "2026-11-26"
verified: "2026-11-26"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-apple-health-blood-pressure
  - export-dexcom-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - omron
  - blood-pressure
  - apple-health
  - csv
---

**OMRON has two different apps, and the export lives in a different place in each.** Check which one you have, then use its route. You do not need Health.md for OMRON's own Excel, PDF or CSV file.

| App (App Store name / seller) | Where the export is | What you get |
| --- | --- | --- |
| **OMRON connect US/CAN/EMEA** (Omron Healthcare, Inc.) | **History** tab → **Share** icon → (**Standard Report**, if offered) → data type and date range → format → send | Excel or PDF report |
| **OMRON Connect** (OMRON HEALTHCARE Co., Ltd., the app used in Asia-Pacific and other regions) | Graph screen → **･･･** menu → **Export measurement data** | CSV file |

**Which app do you have?** Look at the app's name and seller in its App Store listing ([OMRON connect US/CAN/EMEA](https://apps.apple.com/us/app/omron-connect/id1166317885), [OMRON Connect](https://apps.apple.com/au/app/omron-connect/id1003177043)). The US/CAN/EMEA app's bottom tab bar has a **History** tab; if you have no History tab, you are probably on the other app.

Menu labels below are per OMRON's documentation, checked November 26, 2026; labels can vary by version and region, and neither route is promised for every account or plan.

## Export from OMRON connect US/CAN/EMEA (Excel or PDF)

OMRON's [UK support guide](https://www.omron-healthcare.co.uk/omronconnect-support) (last read October 30, 2026) describes:

1. Open **History**, then tap **Share**.
2. Choose **Standard Report** when it is shown (it is described for users who are not Premium subscribers).
3. Select the data type and the date range.
4. Select **Excel** or **PDF**.
5. Choose **Send to me** or **Send to other**, and check the destination before sending.

OMRON's [US app overview](https://omronhealthcare.com/omron-connect-app) distinguishes basic reports from Premium report features, so Premium reports are a plan feature, not something every account has.

This route produces Excel or PDF, not CSV. If you need a CSV, open the Excel file and use **Save as CSV** there. Never rename a PDF to .csv.

## Export from OMRON Connect (CSV)

OMRON's [Connect renewal page](https://www.omronconnect.com/renewal/en_def/), read November 26, 2026, says to tap the **･･･** button on the graph screen and then **Export measurement data** to output a CSV file.

1. Open the graph screen.
2. Tap **･･･**.
3. Tap **Export measurement data**.
4. Save or send the CSV file.

Open the CSV and check its date coverage before you rely on it.

## Can't find Share, History or the ･･･ button?

- You may be on the other app. Compare with the table above.
- Update the app from the App Store.
- Sync the monitor first. Readings not yet synced to your account are not in a cloud export (see the scope notice below).
- Report options can differ by plan and region.
- Don't delete readings or reset the app because a report looks short.

## What the native export does and does not include

OMRON's [EMEA data-porting notice](https://www.omron-healthcare.com/notice-for-data-act) describes measurement exports and excludes app settings and account information. It also limits the described export to stored account measurements, excluding data not yet synchronized to the cloud.

The notice describes CSV/PDF output, but this does not establish that CSV appears in every standard-report menu. Use the format actually offered by your app rather than renaming an Excel or PDF file to CSV.

That scope statement is not a promise about every local-only record or every regional app. Inspect the actual file and its date coverage. Do not delete a monitor's readings or reset an app merely because an exported report looks incomplete.

## Put OMRON readings in Apple Health

For OMRON connect US/CAN/EMEA, the same UK support guide uses **Profile → App settings → Share data with other apps → Apple Health → Link**, then category authorization. Its outgoing list includes blood-pressure readings. Enable the relevant available categories, let synchronization finish and inspect a known day's source records in Apple Health.

The native report, OMRON's dashboard and Apple Health can contain different representations or coverage. A linked app does not establish that every old reading, ECG, note, calculated insight or account setting has been copied. For OMRON Connect, its [App Store listing](https://apps.apple.com/au/app/omron-connect/id1003177043) says data can be shared with Apple's Health; this guide gives no menu path for it. Either way, open Apple Health and verify one known day's readings before relying on them. Start with records you can actually find on the phone.

This walkthrough qualifies the **iPhone Apple Health route**. Older references to Google Fit or Samsung Health do not establish current direct Health Connect menus, fields or history. If your Android phone already has the records in Health Connect, use the separate [Health Connect export guide](/health-connect-export/); this article does not supply an OMRON-specific Android setup.


To turn the readings in Apple Health into daily CSV, JSON or Markdown files in a folder you choose, [get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969). It is not a replacement for OMRON's own report.

For other routes: [Apple Health to Excel](/blog/apple-health-to-excel/), [a PDF from Apple Health](/blog/export-apple-health-data-pdf/).

## Make one daily export with Health.md (iPhone)

Once the required records are present, use the [blood-pressure CSV and JSON walkthrough](/blog/export-apple-health-blood-pressure/).

1. Grant Health.md separate read permissions. OMRON's permission to write does not authorize another app to read.
2. Select **Blood Pressure (Systolic)** and **Blood Pressure (Diastolic)** under **Vitals**.
3. Start with one known day, CSV or JSON and a writable Files folder. Preview, export and open the result.
4. Use **Summary** for daily statistics. Enable **Detailed Time-Series** when you also need available timestamped pairs.

Daily systolic and diastolic statistics come from separate quantity queries. Detailed pairs require actual Apple Health blood-pressure correlations. Health.md does not manufacture a pair from unrelated quantities or from two daily averages. **A source can provide statistics without the correlations needed for paired rows.** Keep the native OMRON report when it is the better record of your original readings.

For folder and access checks, use [your first iPhone export](/docs/iphone-first-export/). A longer range creates separate daily files, and records from other apps may contribute; the output is not automatically OMRON-only.

## Compare the correct representation

The [fictional Apple CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) show Health.md output. They are not native OMRON files or proof that your monitor supplied every example field.

Follow the blood-pressure guide's exact row and field examples. A paired CSV value such as its fictional `121/79` stays text, rather than a spreadsheet date or fraction. JSON can keep the components as separate numbers. Keep daily averages, minimums and maximums separate from individual readings; do not count summary rows as additional measurements.

Check units, source dates, timestamps, repeated exports and multiple sources before combining files. A missing reading is unavailable data, not zero. This guide explains file handling; it does not interpret blood-pressure values or recommend treatment.

For weight records that actually reached Apple Health, use the [weight export guide](/blog/export-apple-health-weight-data/) and its latest-daily-value distinction. A shared weight measurement does not prove that every body-composition estimate is available.

## Choose the saved destination and recipients

An emailed report and a synced folder create copies governed by their recipients and providers. Inspect the actual file before sharing it, including detailed times and any source information.

Core Health.md folder exports require no Health.md account and create no Health.md server copy by default. The optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it; it has no public signup or automatic device sync and is not generally available. This folder workflow does not upload to that pilot.

Use the [local destination guide](/blog/export-health-data-without-the-cloud/) and [retention policy](/privacy-policy.html#retention) for storage choices. Keep the original OMRON report until you have checked the dates, records and representation in any derived daily files.
