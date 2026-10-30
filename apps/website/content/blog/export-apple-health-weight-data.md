---
title: "Export Apple Health weight data to CSV or JSON"
description: "Export daily Apple Health weight values to CSV or JSON with Health.md. Check units, missing days and the latest-record rule, or choose an archive for original readings."
lead: "Save a daily weight value from Apple Health, check its units, and understand when you need original measurement records instead."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - apple-health-to-excel
  - export-health-data-without-the-cloud
  - export-withings-data
draft: false
tags:
  - apple-health
  - weight
  - csv
  - export
---

To export Apple Health weight data, first choose between a daily table and original measurement records. Health.md can save the latest available weight from each selected day's query as CSV or JSON. That daily value is not an average or a list of every weigh-in.

## Choose daily values or original records

| What you need | Export route |
| --- | --- |
| A daily weight table for a spreadsheet or script | Health.md Summary export with Weight selected |
| Apple's native archive, without installing an exporter | Apple Health → profile → Export All Health Data; the archive contains XML |
| Selected source records, identity and capture diagnostics | The separate Apple-only Lossless Health Records profile; review its coverage and warnings |

Apple's [Health data instructions](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) explain its native export. Health.md does not import that XML archive. See the [Apple Health XML guide](/blog/apple-health-xml-export/) for that route, or the [format guide](/docs/format/) and [canonical record reference](/docs/reference/canonical-healthkit-records/) before relying on a source-record archive.

For a daily CSV or JSON workflow:

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

## Export one known day first

1. Confirm the weight records you want are present in Apple Health on this iPhone. A scale's own app can contain measurements that it has not shared to Apple Health.
2. Grant Health.md read access to Weight. In **Health Metrics → Body Measurements**, enable **Weight**.
3. Choose **CSV** for a spreadsheet or **JSON** for a script. Select **Summary**, **Metric** units and one completed day with a known measurement.
4. Choose a writable folder in Files, then tap **Preview**. Check the date and weight output.
5. Export and open the actual saved file. Confirm its location, value and unit before extending the date range.

The [first iPhone export guide](/docs/iphone-first-export/) covers setup and folder access. A longer range creates separate daily files, not a combined weight workbook.

## Understand the latest-record rule

Apple defines [body mass](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass) as discrete measurements. Health.md's daily Weight query selects the most recent available record by its **end date** within the selected-day query. It does not average all weigh-ins or carry yesterday's weight into an empty day.

The result depends on available records and authorization. It is not a promise to reproduce the exact number or source prioritization shown in an Apple Health chart. Multiple apps can contribute weight records; this daily value is not a scale-specific history.

Switching to Detailed Time-Series does not turn the daily Weight field into an array of individual weigh-ins. If you need every original measurement, its identity or timestamps, use the native XML route or inspect the separate Lossless Health Records profile and its capture status. Neither route should be assumed to be a complete backup of every private device record.

## Read the CSV without mixing units or rows

The [fictional daily CSV sample](/docs/reference/generated/core/summary-day.csv) contains this exact header and weight row:

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Body,Weight,75.0,kg
```

The sample represents a daily **75.0 kg** value. It is synthetic output, not a real person's record or evidence of all measurements made that day. The row omits the final Timestamp field; use a CSV-aware importer that leaves that cell empty while keeping the first five columns aligned. Do not invent a measurement time from the Date label.

For this example, filter **Category = Body**, **Metric = Weight** and **Unit = kg**, then convert Value to numbers. The full export's Value column also contains text and metadata. Preserve quoted fields and line breaks rather than splitting arbitrary CSV rows on commas.

Metric exports use kilograms for weight; Imperial exports can use pounds. Inspect each file's actual Unit. Convert values when needed and label the resulting unit; changing the label alone does not convert a measurement. Do not pool kg and lb rows.

Import the filtered data using the [Apple Health to Excel guide](/blog/apple-health-to-excel/), substituting the exact weight filter above. Use Date and the numeric weight Value for a daily trend. Do not sum weights, append original measurement rows to daily values, or include overlapping re-exports twice. Keep the intended version of each daily file.

## Read the JSON equivalent

This is a **small excerpt**, not a complete document, from the [fictional daily JSON sample](/docs/reference/generated/core/summary-day.json):

```json
{
  "body": { "weight": 75 },
  "units": { "weight_kg": "kg" }
}
```

Use `body.weight` with the unit metadata in your actual file. The example uses Metric units; do not infer units from a bare number or assume every export contains the same optional fields. Preserve the file's date and time context separately when combining daily files.

## Check missing or unexpected values

- **No weight output:** check the selected day, Weight selection, read access and actual Apple Health records. An absent row or field is unavailable data, not zero.
- **A scale app shows more history:** verify that those records reached Apple Health. For Withings, check the [sharing eligibility and export guide](/blog/export-withings-data/) before expecting the phone's health store to contain them.
- **A daily value differs from another app:** compare available sources, units, dates and reduction rules. A latest record, daily average and source-specific view answer different questions.
- **You need several weigh-ins per day:** choose a source-record route above. A daily value cannot reconstruct the measurements that were not included in it.
- **Preview works but saving fails:** reselect the destination folder and check its file provider using [export troubleshooting](/docs/troubleshooting/).

Leave missing days visible instead of filling them with zero or an assumed carried-forward weight. This guide explains file contents and selection rules; it does not interpret weight changes or provide a healthy-weight target.

## Choose where the files are stored

Core folder exports require no Health.md account and create no Health.md server copy by default. Synced folders, online spreadsheets and services you share files with follow their own storage and privacy rules. Review the export before sharing it.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. Read the [retention policy](/privacy-policy.html#retention) and [local-only destination guide](/blog/export-health-data-without-the-cloud/) for destination and backup checks.

For broader choices, return to [Apple Health export](/apple-health-export/) or the [CSV walkthrough](/apple-health-to-csv/).
