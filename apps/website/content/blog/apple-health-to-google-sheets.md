---
title: "From Apple Health to Google Sheets."
description: "Export Apple Health as CSV with Health.md, import it into Google Sheets, and build pivot tables and charts from your own data."
lead: "The CSV export is the bridge: one file per day, ready for Sheets."
date: "2026-09-26T12:00:00.000Z"
updated: "2026-09-26T12:00:00.000Z"
category: "Workflow guide"
draft: true
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

Every export produces one CSV file per day with the header `Date,Category,Metric,Value,Unit,Timestamp`. The `Value` column is numeric and `Timestamp` is ISO-8601, so spreadsheets recognize the types without a cleanup pass. Save the files somewhere you can reach from a browser — iCloud Drive, the Files app, or AirDrop them to a Mac.

## Step 2: Import into Google Sheets

1. Create a blank spreadsheet in Google Sheets.
2. Go to File > Import > Upload and pick one of the CSV files.
3. Choose "Replace spreadsheet" for the first file.

Because the columns are plain and typed, the import lands cleanly: dates sort as dates, values chart as numbers. There is no text-to-columns step and no delimiter guessing.

## Step 3: Your first analysis

A pivot table is the fastest way to see patterns. Here is weekly step volume:

1. Go to Data > Pivot table and create it on a new sheet.
2. In the pivot table editor, add `Date` under Rows and group it by week.
3. Add `Value` under Values and set it to summarize by AVERAGE.
4. Add a filter on `Metric` and keep only your step metric.

You now have one row per week with your average daily steps. If you prefer to build the week labels by hand instead, `=TEXT(A2,"YYYY-WW")` turns a date into a week label you can pivot on.

For a trend line, filter the `Metric` column to a sleep metric, copy the `Date` and `Value` columns into a small table, select both columns, and go to Insert > Chart. In the chart editor, pick a line chart — you get a night-by-night view of your own data in about a minute.

## Tips for multi-day exports

- A month of history is roughly thirty files. Import each into its own tab (File > Import, then "Insert new sheet(s)"), or concatenate the files locally before importing.
- Keep the raw import tab untouched. Do your analysis on pivot tables or copies that reference it — if an import goes sideways, you re-import instead of re-exporting.
- A few rows omit the timestamp column; those are compatibility summary rows. Timestamped sample rows always include all six fields. If a row looks sparse, that is why, not a broken export.

## Troubleshooting notes

- If Sheets splits the CSV into a single column, re-import and confirm the separator is a comma — this usually happens when a browser locale defaults to semicolons.
- If `Value` charts as text instead of numbers, check that the column imported as Number. A stray header row from concatenating files by hand is the usual cause; delete it and re-import.
- If the pivot table shows blank weeks, those are days with no samples for that metric — normal for anything you don't record daily.

## What to read next

For the exact CSV contract — row shapes, fixtures, and omission rules — see [Export Apple Health to CSV](/apple-health-to-csv/).

<div class="cta-row">
<a class="button" href="/apple-health-to-csv/">Export Apple Health to CSV</a>
<a class="button secondary" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">Download on the App Store</a>
</div>
