---
title: "Export Apple Health data to Excel (from export.zip or as daily CSV)"
description: "Have an Apple Health export.zip? See why Excel struggles with export.xml, then get daily or single-day CSV files from Health.md into Excel."
lead: "Apple exports XML, not a spreadsheet. Pick your route: convert the export.zip you already have, or export daily CSV files from your iPhone and import them into desktop Excel."
date: "2026-10-25"
updated: "2026-11-21"
category: "Workflow guide"
related:
  - apple-health-to-google-sheets
  - export-apple-health-steps-data
  - apple-health-to-notion
draft: false
verified: "2026-11-21"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - apple-health
  - excel
  - csv
  - export
---

**Apple Health exports XML, not a spreadsheet.** If you already have `export.zip` from **Export All Health Data**, Excel will not give you tidy columns by double-clicking its `export.xml`; convert the records you need first (see below). If you would rather start from daily totals or one day's entries, Health.md writes CSV files that Excel can import.

| What you have or want | Best route |
| --- | --- |
| I already have **export.zip** from the Health app | [Convert it locally](#section-if-you-already-have-export-zip), filtering the record type you need |
| I want **daily totals** (steps, sleep, weight) in a sheet | Health.md daily CSV: follow [steps 1–4](#section-1-export-one-day-before-a-longer-range) |
| I want **every entry for one day** | Health.md [Detailed Time-Series CSV for a single day](#section-every-entry-for-one-day) |

Health.md does not convert an existing Apple XML archive, and it does not export an Excel workbook directly. It reads authorized data on your iPhone and writes CSV.

## If you already have export.zip

Apple's [Health sharing guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) documents **Export All Health Data**, which produces an XML archive. Unzip a copy and keep the original. The records live in `export.xml`; see [Apple Health XML export](/blog/apple-health-xml-export/) for what the archive holds and how its records map to a table.

**Why export.xml is a poor fit for double-clicking in Excel:**

- Years of history make it very large, so it is slow to open and can freeze.
- It is one long list of `<Record>` elements whose values sit in attributes (type, unit, source, start and end dates), not a grid of days and metrics.
- A worksheet holds at most 1,048,576 rows ([Microsoft's Excel limits](https://support.microsoft.com/en-us/office/excel-specifications-and-limits-1672b34d-7043-467e-8e27-269d656771c3)), and a full-history archive can contain more raw records than that.

**Realistic options:**

1. **Filter one record type with a local script or converter.** Run it on your own computer and write a CSV of just the type you need, then import that CSV with the steps below. See [Apple Health to Python](/blog/apple-health-to-python/) for a worked filter, and [workout distance in export.xml](/blog/apple-health-export-xml-workout-distance/) for an XML example.
2. **Excel's own XML import.** Microsoft documents a [Power Query XML connector](https://learn.microsoft.com/en-us/power-query/connectors/xml) and [which connectors each Excel version has](https://support.microsoft.com/en-gb/excel/power-query-data-sources-in-excel-versions?nochrome=true). We did not try it on a real export.xml in Windows or Mac Excel, so we do not give menu paths or promise it works; expect it to struggle on a large archive.

## Try the 28-day spreadsheet sample

[Download the complete sample pack](/assets/downloads/healthmd-spreadsheet-sample.zip), or open the [Excel workbook](/assets/downloads/spreadsheet-sample/healthmd-health-data-sample.xlsx) on its own. No app installation or health permissions are needed to inspect these fictional files.

The pack includes **28 daily CSVs**, a [combined CSV](/assets/downloads/spreadsheet-sample/combined.csv), and a workbook with editable steps and sleep charts. It reuses the starter vault's fictional dates, **September 28 to October 25, 2026**. These are illustrative two-metric samples, not complete exporter fixtures or an XLSX export feature in the app.

Open **Overview** in the workbook to see the charts. **Daily metrics** calculates the daily values from **Raw data**. Sleep is stored in seconds and converted to hours. There are **28 recorded step days** and **27 recorded sleep days**: October 8 deliberately has no sleep reading, and the sleep chart has a gap there.

![Preview of the fictional workbook with daily steps and sleep-duration charts, showing 28 step days and 27 sleep days.](/assets/downloads/spreadsheet-sample/workbook-preview.png)

Rendered workbook preview. All values are fictional.

| Check | Expected result |
| --- | ---: |
| Total steps over 28 recorded days | 249,630 |
| Average sleep over 27 recorded days | 7.49 hours |
| Missing sleep date | October 8, 2026 |

To try recalculation, edit an existing numeric **Value** in **Raw data**. A zero remains a recorded value; an empty value is excluded. The separate **Checked value** column validates inputs, and the sleep chart uses an intentional `#N/A` helper for the missing day. The example has fixed dates and input ranges; appending rows does not extend it automatically. Keep your own records separate and use the walkthrough below to build your own workbook.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Health.md includes **5 free export actions**, followed by a single lifetime unlock. You need desktop Excel for the import steps below. A Mac is not required to create the export on your iPhone.

## 1. Export one day before a longer range

1. Install Health.md on the iPhone with your Apple Health data and authorize the metrics you need.
2. Choose **CSV** and **Summary** for a compact daily view. Select Steps for this exercise, or Sleep if you want a sleep chart.
3. Set the date format to **YYYY-MM-DD** for the date formula below. Preview a known day and save it to a writable folder in Files.
4. Transfer the CSV to your computer using your chosen file destination or transfer method. For setup details, follow [your first iPhone export](/docs/iphone-first-export/).

A longer range produces **one CSV file per day**, not a combined workbook. Keep daily files separate from weekly or monthly rollups and from older copies of the same exports. Detailed Time-Series adds selected samples and intervals; do not add those readings to daily summary totals.

## 2. Import CSV into Excel without changing the raw values

Try the [synthetic daily CSV sample](/docs/reference/generated/core/summary-day.csv) first. It contains fictional measurements and metadata generated by the exporter. Save the downloaded file to your computer, then:

1. In desktop Excel, start a blank workbook and choose **Data → Get Data → From Text/CSV**. Some Windows versions show **From Text/CSV** directly on Data. In Microsoft 365 for Mac, use **Data → Get Data (Power Query)** and the Text/CSV source.
2. Choose the file. In the preview, set the delimiter to **Comma** and the file origin to **UTF-8**. Turn off automatic data type detection so all columns initially remain text.
3. Choose **Transform Data**. Confirm the first row is used as headers, with these six columns in order: `Date,Category,Metric,Value,Unit,Timestamp`. If an automatic Changed Type step has already been added, remove it before loading.
4. Keep the raw columns as text and load the query to a worksheet named **Raw data**. Save the workbook as **.xlsx** so you retain worksheets and formulas when you save your work.

Microsoft documents the [Text/CSV import settings](https://learn.microsoft.com/en-us/power-query/connectors/text-csv) and [Power Query availability by Excel version](https://support.microsoft.com/en-gb/excel/power-query-data-sources-in-excel-versions?nochrome=true). Labels and available connectors vary by version; this walkthrough uses desktop Excel rather than the browser or iPhone app.

The `Value` column is mixed-type. Metadata, capture status, times, booleans, identifiers, and quoted JSON can appear alongside numbers. Do not convert the whole column to Number. Some summary rows omit the final `Timestamp` field; a CSV reader should leave that cell empty while keeping the other five columns aligned. Preserve quoted commas and newlines; do not split the file manually on commas.

## 3. Make a steps table from the matching rows

1. Filter **Raw data** to `Category = Activity`, `Metric = Steps`, and `Unit = count`.
2. Copy **only the visible matching data rows**, with all six columns and one header row, into a new worksheet called **Steps**. Do not copy hidden rows. Clear the raw sheet's filters when finished.
3. Check that there is at most one daily total per Date. If the same date appears twice, investigate overlapping exports and keep the intended copy before continuing. Summing both would count the day twice.
4. Add column G named **Numeric value**. In G2 enter the following and fill it down through the copied rows:

```excel
=IF(D2="","",NUMBERVALUE(D2,".",","))
```

This preserves an empty source cell instead of turning it into zero. The explicit decimal separator matches the export's numeric text. Conversion errors need inspection; do not replace them with zero. Microsoft explains [NUMBERVALUE and its separator arguments](https://support.microsoft.com/en-us/excel/functions/numbervalue-function). These formulas use English function names and comma argument separators; localized Excel installations may require localized names or semicolons.

Add column H named **Calendar date**. Because the raw Date column was imported as text in the specified YYYY-MM-DD format, use:

```excel
=DATE(LEFT(A2,4),MID(A2,6,2),RIGHT(A2,2))
```

Fill down and format H as Date. Check each result against the original Date column. If your files use another date format, re-export with YYYY-MM-DD or adapt the conversion before continuing. Add column I named **Week starting**:

```excel
=H2-WEEKDAY(H2,2)+1
```

Fill down and format I as Date. Each week label is its Monday. See Microsoft's [date function reference](https://support.microsoft.com/en-us/excel/date-and-time-functions-reference) for DATE and WEEKDAY.

With the synthetic sample, the Steps filter leaves one daily row: **2026-03-15, 12500 steps**. Its Monday is **2026-03-09**. One sample day verifies the setup; use multiple real dates for a meaningful trend.

## 4. Combine days, then build a weekly PivotTable

For a small range on either desktop platform, import each additional daily CSV into a temporary worksheet using the same text settings. Append its data rows to **Raw data**, keeping the six columns in order and only one header. Check for duplicate dates in the selected metric, then rebuild the Steps copy and fill the helper formulas through all dates.

For larger ranges in **Excel for Windows**, use **Data → Get Data → From File → From Folder** on a dedicated folder of daily CSV files. Filter the file list to the intended CSVs, then choose **Combine & Transform Data**. Inspect the generated sample-file transformation: promote the header once per file, preserve text types, and remove automatic type conversion before combining. Check the combined output for repeated headers and duplicate daily totals. Microsoft's [folder import guide](https://support.microsoft.com/en-us/excel/import-data-from-a-folder-with-multiple-files-power-query) covers the connector. Keep the workbook itself and unrelated exports outside the source folder.

Microsoft's Mac connector table lists local-folder refresh but not local-folder import. Use the individual-file method above on Mac rather than assuming the Windows From Folder menu is available.

Once the Steps worksheet contains all intended dates:

1. Select its populated range, including the helper columns and headers, and choose **Insert → Table**. Confirm the table has headers.
2. With that table selected, choose **Insert → PivotTable** and place it on a new worksheet.
3. Put **Week starting** in Rows and **Numeric value** in Values. In the value field settings, choose **Average** for average daily steps over recorded days, or **Sum** for recorded weekly totals. If Excel shows Count, check the numeric conversion and select the intended summary function. See Microsoft's [PivotTable aggregation reference](https://support.microsoft.com/en-us/excel/sum-values-in-a-pivottable).
4. To chart daily steps, select Calendar date and Numeric value from the Steps table and insert a line chart. Sort the rows by Calendar date first and label the value axis **Steps**.

A day absent from the export is missing data, not a zero-step day. A weekly average covers only the available numeric daily values; it does not establish a complete seven-day record.

When new files arrive, refresh the import query (or append the newly imported rows), rebuild the filtered Steps copy, extend its table and helper formulas, then refresh the PivotTable. Refreshing a raw query alone does not update a manually copied analysis sheet.

## Every entry for one day

To get a spreadsheet of the individual entries from one day, choose **CSV**, then **Detailed Time-Series**, then one completed date in Health.md. Summary rows still appear, and timestamped samples are added where the metric supports them and the day has data. Do not assume every metric has samples; a metric with none produces no sample rows.

The file has the same six columns as the daily CSV: `Date,Category,Metric,Value,Unit,Timestamp`. In the exporter's [generated reference CSV](/docs/reference/generated/core/summary-day.csv), the timestamped rows are `Heart Rate Sample`, `HRV Sample`, `Blood Oxygen Sample`, `Blood Glucose Sample`, `Respiratory Rate Sample`, `Blood Pressure Sample` and `Sleep Stage`, with a UTC ISO 8601 `Timestamp`. Fictional example rows in that format:

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Heart,Heart Rate Sample,61.0,bpm,2026-03-15T00:30:00Z
2026-03-15,Heart,Heart Rate Sample,92.0,bpm,2026-03-15T01:00:00Z
2026-03-15,Vitals,Blood Pressure Sample,121/79,mmHg,2026-03-15T01:23:20Z
```

Import it with the Text/CSV steps above, then filter **Metric** for the sample type you want. Keep these rows out of daily totals.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Export a single day as Detailed CSV with Health.md</a>

## Excel for the web, iPhone or iPad?

The import steps in this guide use desktop Excel. We did not test the browser or mobile versions, so we make no claim about what they can import; once a workbook exists you can open or share it from any Excel you use.

## Use sleep instead of steps

Repeat the filtered-copy workflow with `Category = Sleep`, `Metric = Total Duration`, and `Unit = seconds`. After numeric conversion, add an **Hours** column with `=IF(G2="","",G2/3600)` and chart that column against Calendar date. The synthetic sample's **27900.0 seconds = 7.75 hours**.

Daily sleep summaries use a local noon-to-noon journal window. For Monday night, select Monday even if bedtime is after midnight. See the [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples). Stage rows are not extra daily totals. Follow the [Apple Health sleep export guide](/blog/export-apple-health-sleep-data/) for date selection, stages, and missing nights.

## Fix common import problems

- **export.xml opens as one column, or Excel freezes:** it is not a CSV and is too large for a worksheet. Close it, and convert one record type to CSV with a local tool first.
- **Everything appears in one column:** re-import with Comma as the delimiter.
- **A number becomes an error or text:** inspect the original cell and separators after filtering the metric. Keep errors visible until resolved.
- **Weekly totals look too high:** check duplicate exports, repeated headers, mixed units, and samples combined with summaries.
- **Dates look wrong:** inspect the raw text and conversion, including the selected export date format. Formatting text as Date alone does not parse it.
- **Your metric is absent:** check the selected day, metrics, Apple Health source records, and read authorization. An absent row does not prove a zero or identify a specific permission state. See [export troubleshooting](/docs/troubleshooting/).

## FAQ

### Can I export Apple Health directly to Excel?

No. Apple's built-in export is an XML archive, not a spreadsheet. Convert records to CSV first, or export CSV from Health.md.

### Why won't export.xml open in Excel?

It is a very large list of `<Record>` elements rather than rows and columns, and a long history can exceed the worksheet row limit. Filter the record type you need into CSV first.

### Does Apple Health export CSV?

Not as its main export, which is the XML archive. Health.md writes CSV from your iPhone instead.

### Can I export one metric only?

Apple's built-in export covers everything. Health.md lets you choose the metrics and dates before exporting.

## Where the files are stored

The core folder workflow needs no Health.md account. Health.md reads authorized data on the device and saves it to the folder you select, with no Health.md server copy by default. A synced folder, a workbook saved to OneDrive, or a file uploaded to Excel for the web follows that provider's storage and privacy rules.

The separate optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. It has no public signup and no automatic device sync. This folder-to-Excel workflow does not upload files to that pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

For the file contract and other spreadsheet apps, return to [Apple Health to CSV](/apple-health-to-csv/). For Apple's native XML archive and other export methods, see [how to export Apple Health data](/apple-health-export/).

To append daily Health.md files before importing, use the free [browser CSV combiner](/apple-health-to-csv/#combine-csv-files). It keeps one header and preserves values and duplicate rows. Review overlapping dates before calculating totals; your files are processed in the browser rather than uploaded.
