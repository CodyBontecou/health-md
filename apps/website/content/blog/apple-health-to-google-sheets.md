---
title: "From Apple Health to Google Sheets."
description: "Export Apple Health as CSV with Health.md, import it into Google Sheets, and build pivot tables and charts from your own data."
lead: "The CSV export is the bridge: one file per day, ready for Sheets."
date: "2026-09-26T12:00:00.000Z"
updated: "2026-09-26T12:00:00.000Z"
category: "Workflow guide"
draft: false
verified: "2026-09-26"
verified_by: "Edison (agent)"
verified_method: mixed
tags:
  - healthmd
  - apple-health
  - csv
  - google-sheets
---

Google Sheets is the underrated home for health data. It is free, it is familiar, sharing a tab is easier than sharing a database, and its charts are good enough for anything short of a research paper. The problem is getting Apple Health into it: the built-in export (Health app, profile picture, Export All Health Data) hands you one giant XML file that no spreadsheet can open directly. You need CSV — one row per measurement, plain columns — and that is exactly what Health.md writes.

## Step 1: Export the CSV from Health.md

1. Install Health.md on the iPhone that has access to Apple Health.
2. Grant Health permissions for the metrics you want to analyze.
3. Choose CSV as the export format and pick a date range, then preview and export.

Every export produces one CSV file per day with the header `Date,Category,Metric,Value,Unit,Timestamp`. The `Value` column is mixed-type: alongside numbers, it contains schema identifiers, time-zone metadata, and raw-capture status. Depending on the metrics and data detail you export, it can also contain clock times, booleans, UUIDs, or quoted JSON. Populated `Timestamp` cells are ISO-8601; many summary rows have no timestamp. Save the files somewhere you can reach from a browser — iCloud Drive, the Files app, or AirDrop them to a Mac.

This guide uses a local folder export followed by a file upload to Google Sheets. Health.md does not upload that local export to its own server; Google stores the file and spreadsheet you import under its own terms. If you choose a synced folder, its provider's rules apply too.

This workflow doesn't use the separate opt-in, single-owner Health.md Cloud pilot. That pilot retains only API exports intentionally sent to it, has no public signup or automatic device sync, and is not generally available. See the [privacy policy](/privacy-policy.html) for that separate destination's boundaries.

## Step 2: Import into Google Sheets

1. Create a blank spreadsheet in Google Sheets.
2. Go to File > Import > Upload and pick the first daily CSV file.
3. Choose "Replace spreadsheet" for the first file, then name its tab "Raw data".
4. Append the remaining daily files to this one raw-data table. For each file, import with "Insert new sheet(s)", then copy its data rows below the last row in "Raw data", keeping the columns in the same order. Skip the imported header row so the combined table has only one header. The extra import tabs are temporary; the analysis will read "Raw data".
5. Check that all exported dates appear in the `Date` column and that you haven't appended a day twice.

Do this before building the weekly pivot. A pivot sourced from one daily file cannot see the other days on separate tabs. Leave the mixed `Value` cells intact in the raw table; you'll select and convert the numeric rows for analysis next.

## Step 3: Your first analysis

A pivot table is the fastest way to see patterns. Here is a weekly view of your daily steps:

1. On "Raw data", use Data > Create a filter. Keep only `Category` = `Activity`, `Metric` = `Steps`, and `Unit` = `count`. Copy only those matching rows into an analysis tab, keeping all six columns and one header row. These are the daily step totals, not metadata or sample rows.
2. Check that `Date` in column A contains spreadsheet dates. If a date imported as text, convert it in a spare column with `=DATEVALUE(A2)`, then paste the resulting values (not the formulas) into column A of the analysis tab and format it as Date.
3. Add a column G called "Numeric value". Enter `=VALUE(D2)` and fill down through the selected rows. This converts numbers stored as text. Check for conversion errors and blanks; don't replace failed conversions or missing values with zero.
4. Add a column H called "Week starting". Enter `=A2-WEEKDAY(A2,2)+1`, fill down, and format that column as Date. Each label is the Monday that starts the week.
5. Select the entire analysis table, including both helper columns and all imported dates. Go to Insert > Pivot table and create it on a new sheet.
6. In the pivot table editor, add "Week starting" under Rows. Add "Numeric value" under Values and set it to summarize by AVERAGE.

You now have one row per week with average daily steps for the dates that have a recorded value. Change AVERAGE to SUM if you want weekly totals. Days absent from the export aren't zero-step days.

For a sleep trend line, repeat the filtering and numeric conversion with `Category` = `Sleep`, `Metric` = `Total Duration`, and `Unit` = `seconds`. Copy the dates and numeric durations into a small table, select both columns, and go to Insert > Chart. Pick a line chart and label the values as seconds, or divide by 3,600 first to chart hours.

## Tips for multi-day exports

- A month of history is roughly thirty daily files. If you combine them locally before importing instead, use a CSV-aware tool that preserves quoted fields and keeps only the first header. Quoted JSON cells can contain commas and newlines.
- Keep the raw import values untouched. Do your analysis on filtered copies — if an import goes sideways, you re-import instead of re-exporting. After appending more days, refresh the analysis copy and expand the pivot's source range to include them.
- Some summary rows have five fields, omitting `Timestamp`; other rows have all six fields with an empty timestamp. Timestamped sample rows include all six fields. Keep them aligned under the same header.

## Troubleshooting notes

- If Sheets splits the CSV into a single column, re-import and confirm the separator is a comma — this usually happens when a browser locale defaults to semicolons.
- If your selected numeric metric charts as text, use `VALUE` on those cells and check the spreadsheet's locale if decimal separators aren't recognized. Formatting the whole mixed `Value` column as Number won't turn metadata or JSON into measurements. Remove any repeated header rows from the combined table.
- If a week is missing from the pivot, check the imported dates and the selected metric rows. A day with no exported value is missing data, not a zero to add to the average.

## What to read next

For the exact CSV contract — row shapes, fixtures, and omission rules — see [Export Apple Health to CSV](/apple-health-to-csv/).

<div class="cta-row">
<a class="button" href="/apple-health-to-csv/">Export Apple Health to CSV</a>
<a class="button secondary" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">Download on the App Store</a>
</div>
