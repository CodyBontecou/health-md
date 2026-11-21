---
title: "How to export Dexcom G7 data: Clarity CSV or Apple Health"
description: "The Dexcom G7 app has no file export. Download a CSV from Dexcom Clarity on the web, or save daily Apple Health files (three-hour delay) with Health.md."
lead: "Download your Dexcom G7 readings as a CSV from Clarity, or add daily files from Apple Health when you want them beside other metrics."
date: "2026-10-30"
updated: "2026-11-21"
verified: "2026-11-21"
verified_by: "Claude (agent)"
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
  - dexcom-g7
  - clarity
---

**The Dexcom G7 app has no CSV export button. To download your G7 data, sign in to [Dexcom Clarity](https://clarity.dexcom.com/) in a browser, open a Reports page, choose the export icon, pick a date range and save the CSV.** Receiver readings reach Clarity after an upload from a computer. If you also want daily files beside other health metrics, [Health.md can save them from Apple Health](#section-choose-a-route). It does not sign in to Dexcom or import Clarity CSV.

## Choose a route

- **Original data as a spreadsheet:** [download the Clarity CSV](#section-download-dexcom-clarity-csv).
- **A report for a clinic:** use Clarity's PDF reports instead of CSV.
- **Readings still on a receiver:** [upload the receiver to Clarity first](#section-download-data-from-a-dexcom-g7-receiver), then export.
- **Your own daily files with other Apple Health metrics:** [connect G7 to Apple Health](#section-connect-dexcom-g7-to-apple-health) and [save daily files with Health.md](#section-save-a-daily-file-with-health-md).

Neither a delayed Apple Health copy nor a daily summary is a replacement for your Dexcom readings, alerts or treatment guidance.

## Can I export from the Dexcom G7 app?

Not as a file, as far as Dexcom documents. Dexcom's [raw-data page](https://www.dexcom.com/en-us/faqs/can-i-export-raw-data), checked **November 21, 2026**, places the CSV option in Clarity: go to clarity.dexcom.com, log in and click the export icon on a Reports page. The G7 app's **Connections** tab is where Dexcom's Apple Health instructions start, below. Dexcom's [Clarity help](https://www.dexcom.com/en-us/faqs/clarity/using-clarity) says the Clarity app creates PDF reports for 2, 7, 14, 30 or 90 days that you can view, save, print or email; the CSV instructions refer to Clarity's Reports pages. Check that the readings you need have reached your Clarity account before exporting.

## Download Dexcom Clarity CSV

Dexcom's [raw-data export instructions](https://www.dexcom.com/en-us/faqs/can-i-export-raw-data), checked **November 21, 2026**, describe a built-in CSV download:

1. Open [Dexcom Clarity](https://clarity.dexcom.com/) in a browser and sign in to your own account.
2. Open a **Reports** page and choose its **export** icon.
3. Select the date range you need and save the CSV.
4. Keep an untouched original. Inspect its dates, event types, glucose units and available columns before filtering it in a spreadsheet.

Dexcom describes the file as a CSV "viewable in Excel" but its help pages, as checked, do not list the columns. Treat the columns you actually download as the reference: expect timestamps, event types and glucose values only if the file shows them, and read the unit from the file (mg/dL or mmol/L, depending on how you view glucose) rather than assuming one. Do not convert between units by hand without keeping the original. Dexcom says the CSV is viewable in Excel; for import tips see the [Excel walkthrough](/blog/apple-health-to-excel/), and check the dates after opening.

This route is the better starting point for original Dexcom data. It does not require Health.md. Check that the required history has reached Clarity; an export cannot include readings missing from the selected account or date range.

Need a report rather than spreadsheet rows? The same Dexcom support page distinguishes Clarity's PDF reports from CSV export. Use the appropriate report for your purpose rather than renaming a PDF with a CSV extension.

## Download data from a Dexcom G7 receiver

Readings stored on a receiver reach Clarity through an upload. Dexcom's [receiver upload instructions](https://www.dexcom.com/en-us/faqs/upload-dexcom-receiver-to-clarity), checked **November 21, 2026**, say:

1. Log in at clarity.dexcom.com, choose **Dexcom Clarity for Home Users** and enter your Dexcom account details.
2. Click **Upload**. On first use of the updated Clarity Uploader, click **Download** to install it, follow the onscreen instructions, then refresh your browser.
3. Connect your USB cable from your computer to your receiver, make sure the receiver is powered on, click **Upload** and follow the prompts.

Then [export the CSV from Clarity](#section-download-dexcom-clarity-csv) as above. Dexcom's page does not specify operating systems or supported receiver models, so check Dexcom's instructions for your model.

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

This button is for daily Apple Health files, not for a Clarity export.

1. Follow the [first iPhone export guide](/docs/iphone-first-export/) to authorize Health.md and choose a writable folder in Files.
2. Select **Blood Glucose** in Health Metrics and grant its separate read access. Dexcom's permission to write does not authorize Health.md to read.
3. Start with one completed day and **Summary** detail. Preview the output before writing it. The first-export guide starts with Markdown; add CSV or JSON once the small export works.
4. Open the saved file and compare its date, units and available daily values with the source records before extending the range.

For the iPhone Summary route, Health.md calculates available daily **average, minimum and maximum** glucose values from the selected-day query. CSV labels these **Blood Glucose Avg**, **Blood Glucose Min** and **Blood Glucose Max**, in **mg/dL**. JSON uses **bloodGlucoseAvg**, **bloodGlucoseMin** and **bloodGlucoseMax** when present; its legacy **bloodGlucose** key repeats the average, not an additional reading.

These are statistics over available authorized Apple Health records, not necessarily Dexcom-only records. Do not treat the average as the latest sensor reading, infer the original series from three summary values, or assume the file recreates Clarity reports, alerts, trend arrows, time-in-range or GMI.

If you need available timestamped readings instead, Health.md's **Detailed Time-Series** option can include glucose samples from Apple Health. That still does not make the output an original Clarity CSV or guarantee all sensor readings, event types or historical data. Use the native Clarity download when preserving the Dexcom source data is the priority.

## Check dates, units and destinations

Check the selected dates using the [first-export guide](/docs/iphone-first-export/) before combining days. A longer daily export produces separate day files. Preserve each file's units; do not silently relabel mg/dL as mmol/L. Missing or inaccessible records must remain distinguishable from recorded values.

For spreadsheet work, use the [Excel walkthrough](/blog/apple-health-to-excel/) with the columns in the file you actually downloaded. Keep Clarity's schema separate from Health.md's daily table. For Markdown notes, use the [Obsidian export guide](/blog/export-apple-health-data-to-obsidian/), or see the [glucose range chart preview](/visualizations/vitals-metabolism/glucose-range/default-colors/) for how to chart daily glucose ranges in Obsidian. The [Apple Health export hub](/apple-health-export/) compares all routes.

Health.md's core folder export needs no Health.md account and creates no Health.md server copy by default. A cloud-synced folder, emailed file or online spreadsheet follows that destination's storage rules. Keep glucose files private and review them before sharing; see the [local-only export guide](/blog/export-health-data-without-the-cloud/).

## Other tools people use

Dexcom says that once a receiver is uploaded to your personal Clarity account, you can [share your data with your clinic](https://www.dexcom.com/en-us/faqs/can-i-export-raw-data). Dexcom's help pages checked here do not describe third-party platforms, so check their own documentation for any exports.

## What about Android and Health Connect?

Clarity CSV remains the native starting point. Dexcom's [regional sharing overview](https://www.dexcom.com/en-GB/faqs/data-sharing?ipc=US) also describes Health Connect sharing with a three-hour delay and says availability depends on the phone and Dexcom system.

Check your exact app, system and region. If the required records are already visible in Android Health Connect, use the separate [Health Connect export guide](/health-connect-export/) and verify one day first. This article's labels and JSON keys describe the iPhone route; they are not an Android schema or a promise of universal Dexcom-to-Health-Connect support.

This guide covers retrospective file organization. Use your Dexcom system and its instructions for readings, alerts and treatment decisions, rather than a Health.md export.

## FAQ

**Does the Dexcom G7 app export CSV?** Dexcom's raw-data page describes the CSV export in Clarity, on a Reports page, not in the G7 app.

**How far back can I export from Clarity?** Dexcom's pages checked here do not state an export limit; they say you choose a date range and that uploaded data remains accessible while the product is available.

**Why is Apple Health glucose three hours behind?** Dexcom says Apple Health receives G7 information after a three-hour delay, not in real time.

**Can Health.md read Dexcom directly?** No. It reads only records already in Apple Health that you authorize.
