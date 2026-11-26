---
title: "How to export weight data from Apple Health (every weigh-in or daily CSV)"
description: "Apple Health can't export weight alone. Filter its export.xml for every weigh-in, or save one value per day as CSV or JSON with Health.md."
lead: "Apple's export is all-or-nothing. Find every weigh-in in export.xml, or save one weight per day as CSV or JSON."
date: "2026-10-30"
updated: "2026-11-24"
verified: "2026-11-24"
verified_by: "Claude (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - apple-health-xml-export
  - export-withings-data
  - export-renpho-data
draft: false
tags:
  - apple-health
  - weight
  - csv
  - export
---

**Apple Health has no export for weight alone.** Its native route is **Health → your picture or initials → Export All Health Data**, which creates `export.zip`. Inside, each weigh-in is a `<Record>` element whose `type` is `HKQuantityTypeIdentifierBodyMass`, with its own `value`, `unit` and dates. If you want one weight per day as CSV or JSON without parsing XML, Health.md writes daily files from the Apple Health data you authorize.

## Choose every weigh-in or one value per day

| What you need | Export route |
| --- | --- |
| Every weigh-in, with its own time, source and unit | Apple's native archive: Health → profile → Export All Health Data, then filter `export.xml` for BodyMass records |
| One weight per day for a spreadsheet or script | Health.md Summary export with Weight selected, as CSV or JSON |
| Selected source records, identity and capture diagnostics | The separate Apple-only Lossless Health Records profile; review its coverage and warnings |

Apple's [Health data instructions](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) document Export All Health Data. Health.md does not import that XML archive. For a daily CSV or JSON workflow:

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

For source-record archives, read the [format guide](/docs/format/) and [canonical record reference](/docs/reference/canonical-healthkit-records/) first.

## Find weight in Apple's export.xml

Apple defines [body mass](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass) as discrete measurements, and they appear in the archive as `<Record>` elements. This fictional excerpt uses only attributes that the export DTDs declare for `Record` (`type`, `sourceName`, `unit`, `creationDate`, `startDate`, `endDate`, `value`):

```xml
<Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Example Scale App" unit="kg" creationDate="2026-03-15 07:31:10 +0000" startDate="2026-03-15 07:30:00 +0000" endDate="2026-03-15 07:30:00 +0000" value="75.0"/>
<Record type="HKQuantityTypeIdentifierBodyMass" sourceName="Example Manual Entry" unit="lb" creationDate="2026-03-15 20:05:00 +0000" startDate="2026-03-15 20:04:00 +0000" endDate="2026-03-15 20:04:00 +0000" value="165.4"/>
```

The values are invented. They are not a real person's weigh-ins, and nothing here says how many weigh-ins a real export holds. Two things to expect:

- **Several sources.** One person can have BodyMass records from a scale app, manual entry and apps paired with a Watch. Each source writes its own records, so `sourceName` can differ row to row.
- **Mixed units.** The `unit` is per record, so one file can hold both `kg` and `lb` rows. Read `unit` on every row before charting.

To pull weight out, filter rows where `type` equals `HKQuantityTypeIdentifierBodyMass`. Read your own file's inline DTD (`<!DOCTYPE HealthData [ … ]>`) for the attributes your export version declares; the [DTD copies cited in the workout-distance guide](/blog/apple-health-export-xml-workout-distance/) show how to check. That guide covers the same XML for another metric. For unzipping and finding `export.xml`, see the [Apple Health XML guide](/blog/apple-health-xml-export/), and for opening the result in a spreadsheet, the [Apple Health to Excel guide](/blog/apple-health-to-excel/).

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

## Weight from a scale app that's missing in Apple Health

If a scale app (Withings, RENPHO, Zepp Life and others) never shared a reading to Apple Health, neither Apple's archive nor a Health.md export will contain it. Use that app's own export instead:

- Withings: [sharing eligibility and export guide](/blog/export-withings-data/)
- RENPHO: [RENPHO export guide](/blog/export-renpho-data/)
- Zepp Life and Amazfit: [Zepp and Amazfit export guide](/blog/export-zepp-amazfit-data/)

## Check missing or unexpected values

- **No weight output:** check the selected day, Weight selection, read access and actual Apple Health records. An absent row or field is unavailable data, not zero.
- **A daily value differs from another app:** compare available sources, units, dates and reduction rules. A latest record, daily average and source-specific view answer different questions.
- **You need several weigh-ins per day:** choose the native archive or a source-record route above. A daily value cannot reconstruct the measurements that were not included in it.
- **Preview works but saving fails:** reselect the destination folder and check its file provider using [export troubleshooting](/docs/troubleshooting/).

Leave missing days visible instead of filling them with zero or an assumed carried-forward weight. This guide explains file contents and selection rules; it does not interpret weight changes or provide a healthy-weight target.

## Choose where the files are stored

Core folder exports require no Health.md account and create no Health.md server copy by default. Synced folders, online spreadsheets and services you share files with follow their own storage and privacy rules. Review the export before sharing it.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. Read the [retention policy](/privacy-policy.html#retention) and [local-only destination guide](/blog/export-health-data-without-the-cloud/) for destination and backup checks.

For broader choices, return to [Apple Health export](/apple-health-export/) or the [CSV walkthrough](/apple-health-to-csv/).
