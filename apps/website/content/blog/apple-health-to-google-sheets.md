---
title: "How to export Apple Health to Google Sheets"
description: "Export Apple Health to Google Sheets using CSV. Import daily files, filter steps or sleep, and build weekly pivot tables and charts with the right dates and units."
lead: "Export Apple Health as daily CSV files with Health.md, upload them to Google Sheets, then filter the metric and unit you want before making a weekly table or chart."
date: "2026-09-26T12:00:00.000Z"
updated: "2026-10-27"
category: "Workflow guide"
related:
  - apple-health-to-excel
  - export-apple-health-steps-data
  - apple-health-xml-export
draft: false
verified: "2026-10-27"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - healthmd
  - apple-health
  - csv
  - google-sheets
---

Apple Health's built-in **Export All Health Data** creates an XML archive. For Google Sheets, Health.md can read authorized data on your iPhone and write daily CSV files. This guide imports those files on a computer; it does not convert an existing XML archive or connect Sheets directly to Apple Health.

## Try the 28-day spreadsheet sample

[Download the complete sample pack](/assets/downloads/healthmd-spreadsheet-sample.zip), including **28 daily CSVs**, a combined CSV, and an [Excel workbook with steps and sleep charts](/assets/downloads/spreadsheet-sample/healthmd-health-data-sample.xlsx). You can also download [combined.csv](/assets/downloads/spreadsheet-sample/combined.csv) directly to practice the Sheets import.

All values are fictional, covering **September 28 to October 25, 2026**. These are illustrative two-metric samples, not complete exporter fixtures. There are **28 recorded step days** and **27 recorded sleep days**; October 8 deliberately has no sleep reading. Missing sleep is not zero, and sleep seconds must be divided by 3600 to chart hours.

![Rendered preview of the fictional Excel reference workbook with daily steps and sleep-duration charts and a gap for missing sleep.](/assets/downloads/spreadsheet-sample/workbook-preview.png)

The workbook is an Excel reference. For the Sheets exercise, create a new spreadsheet, choose **File → Import → Upload**, select **combined.csv**, and choose **Comma** as the separator. Uploading sends this fictional sample to Google. Then follow Step 2 below to preserve the raw table and Step 3 to build the filtered analysis. Native Excel chart conversion in Sheets has not been verified.

Your steps total should be **249,630** across 28 recorded days. Average sleep should be **7.49 hours** across 27 recorded days. Do not mix the fictional rows with your own exports, and do not replace the absent October 8 sleep row with zero. The sample workbook has fixed dates and ranges; it does not refresh from your phone.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Health.md includes **5 free export actions**, followed by a single lifetime unlock. You do not need a Mac to create the manual iPhone export. Use a computer and a Google account for the browser-based Sheets steps below.

## Step 1: Export one day as CSV

1. Install Health.md on the iPhone with your Apple Health data and authorize the categories you want to read.
2. Select **CSV** and **Summary** for daily totals. Choose Steps for this exercise, or Sleep for the sleep variation below.
3. Set the export date format to **YYYY-MM-DD** for the date conversion below. Preview one known day, then export to a writable folder in Files.
4. Make the daily CSV available on your computer through your chosen file provider or transfer method. If setup is incomplete, follow [your first iPhone export](/docs/iphone-first-export/).

A longer range produces **one CSV file per day**, not one combined spreadsheet. Each file has the header `Date,Category,Metric,Value,Unit,Timestamp`. The `Value` column is mixed-type: metadata and capture status appear alongside numbers, and selected data can add times, booleans, identifiers, or quoted JSON. Filter Category, Metric, and Unit before numeric analysis.

Keep your original CSV files. Detailed Time-Series adds selected samples and intervals; do not add those readings to daily summary totals or mix daily files with weekly/monthly rollups.

## Before uploading: choose the destination deliberately

This guide uses a **local folder export** followed by a file upload to Google Sheets. Health.md builds that folder export on the device, with no Health.md server copy by default. Google stores the file and spreadsheet you import under its own terms. A synced folder follows its provider's rules too. Try the [synthetic daily CSV sample](/docs/reference/generated/core/summary-day.csv), which contains fictional measurements and metadata, before uploading your own records.

This workflow does not use the separate opt-in, single-owner Health.md Cloud pilot. That pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. See the [privacy policy and retention boundaries](/privacy-policy.html#retention).

## Step 2: Import and combine daily files

1. On a computer, create a blank spreadsheet in Google Sheets. For this recipe, use **File → Settings → Locale → United States** before importing; the export's numeric text uses a decimal point. The formulas below use English function names and comma separators. Google's [spreadsheet settings guide](https://support.google.com/docs/answer/58515?hl=en) explains locale and function language.
2. Choose **File → Import → Upload**, then select the synthetic sample or your first daily CSV. Use **Replace spreadsheet** only in this new, empty workbook; it replaces the open spreadsheet's contents. Set the separator to **Comma**, import, and name the tab **Raw data**.
3. Inspect the six headers and a few source rows. Sheets can recognize numbers and dates during import, so compare them with the original CSV before analyzing. Some summary rows have five fields and omit Timestamp; that last cell should remain empty. Quoted commas or newlines must stay inside their original cells.
4. To append the remaining daily files into one Raw data table, import each file using **Insert new sheets**. Copy its data rows below the last populated row in Raw data, keeping all six columns in order. **Skip the imported header row**, so the combined table has only one header. These temporary import tabs are not separate pivot sources.
5. Check that **all exported dates** reached Raw data. Keep one intended version of each daily file; re-exports of the same day can duplicate totals. Keep rollups and unrelated files out of this table.

Google documents the [CSV import options and separators](https://support.google.com/docs/answer/40608?hl=en) and the [Upload workflow](https://support.google.com/docs/answer/12236443?hl=en). This is a manual snapshot: later exports on your phone do not appear in Sheets until you import them.

## Step 3: Build a weekly steps table

1. Select Raw data's populated range and use **Data → Create a filter**. Keep only `Category` = `Activity`, `Metric` = `Steps`, and `Unit` = `count`. Copy only the visible matching rows into a new **Steps** tab, with all six columns and one header. Inspect the copied rows to confirm every row matches all three filters. Remove the raw sheet's filter when finished. See Google's [filter instructions](https://support.google.com/docs/answer/3540681?hl=en).
2. Check the Steps table for duplicate dates. There should be at most one daily total per Date. If there are two, investigate overlapping exports and keep the intended copy rather than summing both.
3. If Date in column A imported as text, use this formula in a temporary spare column for each such row: `=DATE(VALUE(LEFT(A2,4)),VALUE(MID(A2,6,2)),VALUE(RIGHT(A2,2)))`. It reconstructs the specified YYYY-MM-DD text. Copy the converted dates, then **Paste special → Values only** back into the matching column A cells and format them as Date. Leave already recognized date values alone. Check the displayed dates against the original CSV. Other export date formats need a different conversion.
4. Add column G called **Numeric value**. Enter `=IF(D2="","",VALUE(D2))` in G2 and fill down through the selected rows. The blank guard preserves missing cells. Check errors and the original text; **do not replace failed conversions or missing values with zero**. Changing the whole mixed Value column's number format cannot turn metadata into measurements.
5. Add column H called **Week starting**. Enter `=A2-WEEKDAY(A2,2)+1`, fill down, and format that column as Date. Each label is the Monday that starts the week. These formulas follow Google's [VALUE](https://support.google.com/docs/answer/3094220?hl=en), [DATE](https://support.google.com/docs/answer/3092969?hl=en), and [WEEKDAY](https://support.google.com/docs/answer/3092985?hl=en) references.
6. Select the entire Steps table, including both helper columns and all imported dates. Choose **Insert → Pivot table** and place it on a new sheet. In the pivot editor, add **Week starting** under Rows and **Numeric value** under Values. Set the summary to **AVERAGE** for average daily steps over recorded days, or **SUM** for recorded weekly totals. Google's [pivot table guide](https://support.google.com/docs/answer/1272900?hl=en) explains source ranges and fields.

With the synthetic sample, filtering leaves one steps row: **2026-03-15, 12500 steps**. Its Monday label is **2026-03-09**. This single day checks your setup; import multiple dates for a useful weekly view.

A weekly average covers only dates with recorded numeric values. Missing days are not zero-step days, and an incomplete week is not a full seven-day record. If a pivot counts rows instead of showing the intended values, inspect the numeric helper cells and the selected summary function.

For a sleep trend, repeat the workflow in a separate **Sleep** tab with `Category` = `Sleep`, `Metric` = `Total Duration`, and `Unit` = `seconds`. Convert only those numeric duration rows, then add **Hours** with `=IF(G2="","",G2/3600)`. The synthetic sample's **27900.0 seconds = 7.75 hours**. Sleep Stage rows are not additional daily totals. Daily sleep summaries use a local noon-to-noon journal window, not always the source session’s calendar start date; see the [Apple Health sleep export guide](/blog/export-apple-health-sleep-data/) for choosing the right day.

## Step 4: Add a chart and keep it current

For a simple daily chart, copy the Steps tab's Date and Numeric value columns into adjacent columns on a new **Chart data** tab, using Values only. Keep one header row, sort both columns together by Date, and select the populated range. Choose **Insert → Chart**, then a line chart in the chart editor. Use Date for the horizontal axis and label the series **Steps**. For sleep, use Date and Hours instead. Google's [chart instructions](https://support.google.com/docs/answer/63824?hl=en) cover the data range and chart type.

After importing more daily files, rebuild the filtered analysis copy, extend the helper formulas, and expand the pivot source range to include the new rows. Sheets updates a pivot when its source cells change, but it cannot include rows outside its configured range. Rebuild the manual Chart data copy and expand the chart's range too. Appending Raw data alone does not update those copied sheets.

## Troubleshooting

- **Everything is in one column:** re-import with Comma as the separator.
- **Numbers or dates look wrong:** compare the CSV and Sheets cells, check the spreadsheet locale, and inspect the conversion before continuing. Formatting text as Date alone does not parse it.
- **Totals look too large:** check duplicated dates, repeated headers, mixed units, rollups, and sample rows added to daily summaries.
- **A day or metric is absent:** check the export date, selected metrics, source records, and authorization. An absent row does not establish zero or identify a specific permission state. See [export troubleshooting](/docs/troubleshooting/).
- **New days do not appear:** check the analysis copy, helper formulas, pivot source range, and chart range. Uploads are snapshots, not live synchronization.

For the CSV contract and other spreadsheet apps, see [Apple Health to CSV](/apple-health-to-csv/). If you prefer a desktop workbook, follow [Apple Health to Excel](/blog/apple-health-to-excel/). For Apple's native XML archive and other export methods, see [how to export Apple Health data](/apple-health-export/).

To append daily Health.md files before importing, use the free [browser CSV combiner](/apple-health-to-csv/#combine-csv-files). It keeps one header and preserves values and duplicate rows. Review overlapping dates before calculating totals; your files are processed in the browser rather than uploaded.
