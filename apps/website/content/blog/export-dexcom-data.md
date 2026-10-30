---
title: "Export Dexcom data: Clarity CSV or Apple Health files"
description: "Download Dexcom Clarity CSV for original glucose data, or export daily files from readings already shared to Apple Health. Check the three-hour delay and limits."
lead: "Keep original Dexcom readings with Clarity, or choose a separate daily Apple Health export for your personal files."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - apple-health-to-excel
  - export-apple-health-data-to-obsidian
  - export-health-data-without-the-cloud
draft: false
tags:
  - dexcom
  - glucose
  - apple-health
  - csv
---

**Use Dexcom Clarity first if you want your original glucose data in CSV.** Health.md offers a different route: daily files from selected records that are already available in Apple Health. It does not sign in to Dexcom, import Clarity CSV or connect directly to a sensor.

Choose the file you need before installing another app. Neither a delayed Apple Health copy nor a daily summary is a replacement for your Dexcom readings, alerts or treatment guidance.

## Download Dexcom Clarity CSV

Dexcom's [raw-data export instructions](https://www.dexcom.com/en-us/faqs/can-i-export-raw-data), checked **October 30, 2026**, describe a built-in CSV download:

1. Open [Dexcom Clarity](https://clarity.dexcom.com/) in a browser and sign in to your own account.
2. Open a **Reports** page and choose its **export** icon.
3. Select the date range you need and save the CSV.
4. Keep an untouched original. Inspect its dates, event types, glucose units and available columns before filtering it in a spreadsheet.

This route is the better starting point for original Dexcom data. It does not require Health.md. Check that the required history has reached Clarity; an export cannot include readings missing from the selected account or date range.

Need a report rather than spreadsheet rows? The same Dexcom support page distinguishes Clarity's PDF reports from CSV export. Use the appropriate report for your purpose rather than renaming a PDF with a CSV extension.

## Connect Dexcom G7 to Apple Health

For a personal daily file alongside other Apple Health metrics, first verify the handoff from Dexcom. The current [G7 Apple Health instructions](https://www.dexcom.com/en-us/m/faqs/how-do-i-share-my-glucose-data-with-the-apple-health-app) specify:

1. Open **Connections** in the Dexcom G7 app.
2. Choose **Apple Health**, then **Activate**.
3. Enable **Blood Glucose** on the Health Access screen and allow sharing.

Dexcom says these instructions also apply to G7 15 Day. They are not universal menu instructions for G6, ONE, Stelo or every country-specific app.

**Apple Health receives the G7 information after a three-hour delay, not in real time.** Health.md cannot remove that upstream delay. Additional export timing can make a saved file older still.

Before continuing, inspect a completed day's Blood Glucose records in Apple Health. Check the source, timestamps and units against the data you expected. A sharing switch alone does not establish that older history was copied, and a missing value is not a zero reading.

## Save a daily file with Health.md

Continue only if the required readings are actually in Apple Health and a retrospective daily export suits your task.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

1. Follow the [first iPhone export guide](/docs/iphone-first-export/) to authorize Health.md and choose a writable folder in Files.
2. Select **Blood Glucose** in Health Metrics and grant its separate read access. Dexcom's permission to write does not authorize Health.md to read.
3. Start with one completed day and **Summary** detail. Preview the output before writing it. The first-export guide starts with Markdown; add CSV or JSON once the small export works.
4. Open the saved file and compare its date, units and available daily values with the source records before extending the range.

For the iPhone Summary route, Health.md calculates available daily **average, minimum and maximum** glucose values from the selected-day query. CSV labels these **Blood Glucose Avg**, **Blood Glucose Min** and **Blood Glucose Max**, in **mg/dL**. JSON uses **bloodGlucoseAvg**, **bloodGlucoseMin** and **bloodGlucoseMax** when present; its legacy **bloodGlucose** key repeats the average, not an additional reading.

These are statistics over available authorized Apple Health records, not necessarily Dexcom-only records. Do not treat the average as the latest sensor reading, infer the original series from three summary values, or assume the file recreates Clarity reports, alerts, trend arrows, time-in-range or GMI.

If you need available timestamped readings instead, Health.md's **Detailed Time-Series** option can include glucose samples from Apple Health. That still does not make the output an original Clarity CSV or guarantee all sensor readings, event types or historical data. Use the native Clarity download when preserving the Dexcom source data is the priority.

## Check dates, units and destinations

Check the selected dates using the [first-export guide](/docs/iphone-first-export/) before combining days. A longer daily export produces separate day files. Preserve each file's units; do not silently relabel mg/dL as mmol/L. Missing or inaccessible records must remain distinguishable from recorded values.

For spreadsheet work, use the [Excel walkthrough](/blog/apple-health-to-excel/) with the columns in the file you actually downloaded. Keep Clarity's schema separate from Health.md's daily table. For Markdown notes, use the [Obsidian export guide](/blog/export-apple-health-data-to-obsidian/).

Health.md's core folder export needs no Health.md account and creates no Health.md server copy by default. A cloud-synced folder, emailed file or online spreadsheet follows that destination's storage rules. Keep glucose files private and review them before sharing; see the [local-only export guide](/blog/export-health-data-without-the-cloud/).

## What about Android and Health Connect?

Clarity CSV remains the native starting point. Dexcom's [regional sharing overview](https://www.dexcom.com/en-GB/faqs/data-sharing?ipc=US) also describes Health Connect sharing with a three-hour delay and says availability depends on the phone and Dexcom system.

Check your exact app, system and region. If the required records are already visible in Android Health Connect, use the separate [Health Connect export guide](/health-connect-export/) and verify one day first. This article's labels and JSON keys describe the iPhone route; they are not an Android schema or a promise of universal Dexcom-to-Health-Connect support.

This guide covers retrospective file organization. Use your Dexcom system and its instructions for readings, alerts and treatment decisions, rather than a Health.md export.
