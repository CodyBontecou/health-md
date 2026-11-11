---
title: "Export OMRON connect data: reports or Apple Health CSV"
description: "Save OMRON connect reports, or export readings already shared to Apple Health as daily CSV or JSON. Check regional menus, history and paired-reading limits."
lead: "Start with OMRON's own report for its measurements. Use Health.md for daily files only after checking the actual records in Apple Health."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-apple-health-blood-pressure
  - export-apple-health-weight-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - omron
  - blood-pressure
  - apple-health
  - csv
---

**OMRON connect already provides report exports. You do not need Health.md for OMRON's own files.** Use the native report when it contains the measurements and format you need.

Health.md offers a separate iPhone workflow: daily Markdown, CSV or JSON from selected, authorized Apple Health records. It does not connect directly to an OMRON account, read a monitor over Bluetooth or import an OMRON report.

## Export an OMRON report first

OMRON's [UK support guide](https://www.omron-healthcare.co.uk/omronconnect-support), checked **October 30, 2026**, describes:

1. Open **History** and its **Share** control.
2. Choose **Standard Report** if you are not a Premium subscriber, then select the data type and date range.
3. Select an offered **Excel or PDF** format.
4. Follow the recipient and send prompts, checking the destination before sending.

These are documented OMRON connect US/CAN/EMEA instructions. Check your regional app and its offered choices; report features and menus can differ. OMRON's [US app overview](https://omronhealthcare.com/omron-connect-app) distinguishes basic reports from Premium report features. Do not assume every report option is available on every plan.

Keep the original download. Its columns and grouping are not Health.md's daily-file contract, even when both outputs are CSV.

## Understand the native export's scope

OMRON's [EMEA data-porting notice](https://www.omron-healthcare.com/notice-for-data-act) describes measurement exports and excludes app settings and account information. It also limits the described export to stored account measurements, excluding data not yet synchronized to the cloud.

The notice describes CSV/PDF output, but this does not establish that CSV appears in every standard-report menu. Use the format actually offered by your app rather than renaming an Excel or PDF file to CSV.

That scope statement is not a promise about every local-only record or every regional app. Inspect the actual file and its date coverage. Do not delete a monitor's readings or reset an app merely because an exported report looks incomplete.

## Verify OMRON to Apple Health sharing

The same UK support guide uses **Profile → App settings → Share data with other apps → Apple Health → Link**, then category authorization. Its outgoing list includes blood-pressure readings. Enable the relevant available categories, let synchronization finish and inspect a known day's source records in Apple Health.

The native report, OMRON's dashboard and Apple Health can contain different representations or coverage. A linked app does not establish that every old reading, ECG, note, calculated insight or account setting has been copied. Start with records you can actually find on the phone.

This walkthrough qualifies the **iPhone Apple Health route**. Older references to Google Fit or Samsung Health do not establish current direct Health Connect menus, fields or history. If your Android phone already has the records in Health Connect, use the separate [Health Connect export guide](/health-connect-export/); this article does not supply an OMRON-specific Android setup.

## Make one daily export with Health.md

Once the required records are present, [get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and use the [blood-pressure CSV and JSON walkthrough](/blog/export-apple-health-blood-pressure/).

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
