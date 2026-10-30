---
title: "Export RENPHO data: native files or Apple Health CSV"
description: "Export RENPHO scale data using the current app's History flow, or save daily CSV and JSON from records already shared to Apple Health. Check format and history limits."
lead: "Choose RENPHO's original export or a daily file from Apple Health, with separate instructions for current and legacy apps."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-apple-health-weight-data
  - apple-health-to-excel
  - export-health-data-without-the-cloud
draft: false
tags:
  - renpho
  - weight
  - apple-health
  - csv
---

**RENPHO has its own data export. Start there if you want the measurements in its app.** Health.md provides a separate iPhone route: daily Markdown, CSV or JSON from selected, authorized records already present in Apple Health.

Health.md does not sign in to a RENPHO account, read a scale over Bluetooth or import a RENPHO export. Choose the route that contains the records you need before downloading another app.

## Export from the current Renpho Health app

RENPHO's [current scale FAQ](https://renpho.com/pages/faq-for-renpho-health-app), checked **October 30, 2026**, documents this route:

1. Open the **Body Fat Scale** homepage in **Renpho Health**.
2. Open **History**. The FAQ also describes reaching it through **Trends** and the upper-right history control.
3. Choose a date containing measurements, then **Export data**.
4. Set **Start date** and **End date**, then **Confirm**.

Inspect the resulting export and the save or share choices in your app. Check the selected user, date range, column names and units. Keep the original file before transforming it for a spreadsheet.

These are documented scale-app instructions, not a guarantee for every RENPHO device or app version. They do not establish one universal file format or column schema.

## Can RENPHO export CSV?

RENPHO's [legacy Bluetooth scale manual](https://renpho.com/pages/001) explicitly describes downloading or emailing CSV from the older **RENPHO** app's **Chart** history. That is a different app and menu from the current Renpho Health flow above.

Use CSV if your app offers it. If it offers another format, preserve that file and use the appropriate spreadsheet importer; changing its extension to <code>.csv</code> does not convert it. Do not assume the legacy Chart instructions or a smart tape measure's export menu apply to your scale.

RENPHO's [current app page](https://renpho.com/pages/apps-download-renpho) identifies Renpho Health as the original app's replacement. Before removing an older app, verify that the history you need is present and keep an available export. This guide does not promise recovery of missing account or guest-mode history.

## Check RENPHO to Apple Health sharing

The current app page describes authorizing Health access, then reviewing **Apple Health → profile → Apps → Renpho Health**. Enable the categories you want to share and inspect actual records after synchronization.

RENPHO explicitly names **Body Fat Percentage, Body Mass Index and Lean Body Mass** on that page. It also says new measurements synchronize after they are saved in Renpho Health. A category permission alone does not prove that a measurement or older history reached Apple Health.

If you want a weight CSV, first find a known day's Weight records in Apple Health and check their source. Continue with Health.md only when the data you need is actually there. Do not assume that every scale estimate, body-composition report or older reading is shared.

## Export a daily CSV or JSON with Health.md

For records you have verified in Apple Health:

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

1. Grant Health.md its own read permission for the needed categories. RENPHO's write authorization does not authorize Health.md to read.
2. For weight, enable **Health Metrics → Body Measurements → Weight** and choose **Summary**, **CSV** or **JSON**, and **Metric** units.
3. Select one completed day with a known record and a writable folder in Files.
4. Use **Preview**, export, and open the saved file. Confirm the date, value and unit before extending the range.

The [first iPhone export guide](/docs/iphone-first-export/) covers folder setup. The [weight CSV and JSON walkthrough](/blog/export-apple-health-weight-data/) supplies exact fictional rows, units and spreadsheet filters.

Health.md's daily Weight value selects the most recent available record by end date within the selected-day query. It is not an average, every weigh-in, or a RENPHO-only source filter. Another app's later record can affect the daily result. A longer range creates separate daily files.

Missing records are unavailable data, not zero. For original readings and timestamps, inspect RENPHO's native export or the source-record routes in the weight guide. A daily table cannot reconstruct measurements it does not contain.

## What about Android?

The native RENPHO export is the starting point on either platform. RENPHO's current page names **Google Health**, while older instructions mention Google Fit and Samsung Health. Those names do not establish a universal Health Connect setup, shared-field list or history transfer.

If your Android phone already contains the required records in Health Connect, follow the separate [Health Connect export guide](/health-connect-export/). This article qualifies the iPhone route and does not provide a RENPHO-specific Android connection procedure.

## Choose where your files go

Health.md's core folder export requires no Health.md account and creates no Health.md server copy by default. A synced folder, emailed RENPHO export or online spreadsheet follows the destination's storage and privacy rules. Review the file before sharing it.

For storage checks, use the [local-only export guide](/blog/export-health-data-without-the-cloud/). For a spreadsheet, use the [Excel guide](/blog/apple-health-to-excel/) with the actual file's columns and units.
