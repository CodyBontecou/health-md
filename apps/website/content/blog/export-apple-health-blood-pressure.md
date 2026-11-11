---
title: "How to export Apple Health blood pressure to CSV or JSON"
description: "Export Apple Health blood pressure with Health.md on iPhone. Choose daily statistics or paired readings, inspect CSV and JSON examples, and save files locally."
lead: "Choose both blood-pressure metrics in Health.md, enable Detailed Time-Series for paired readings, and preview one known day before saving CSV or JSON."
date: "2026-10-30"
updated: "2026-10-30"
category: "Workflow guide"
related:
  - export-apple-health-data-pdf
  - export-omron-connect-data
  - export-health-data-without-the-cloud
draft: false
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - apple-health
  - blood-pressure
  - csv
  - export
---

You can export blood-pressure data already stored in Apple Health to CSV or JSON with Health.md on iPhone. Choose daily statistics for a summary, or enable Detailed Time-Series for available timestamped systolic/diastolic pairs. Manual export needs no Mac.

## Choose CSV, JSON, or a PDF

| What you need | Start here |
| --- | --- |
| Sort or chart exported values | CSV, following the steps below. |
| Process paired readings with separate numeric fields | JSON, with Detailed Time-Series enabled. |
| Share a PDF of a completed Apple Blood Pressure Log | Apple's built-in **Export PDF** option. See [Apple's log instructions](https://support.apple.com/en-nz/122995) for requirements and availability. |
| Create a selected, multi-measurement PDF in Health.md | [Clinician Report walkthrough](/blog/export-apple-health-data-pdf/). |

Apple's log PDF and Health.md's data exports are different workflows. This guide covers files for your own inspection or processing; it does not interpret readings or recommend treatment. For Apple's full XML archive, see the [general Apple Health export guide](/apple-health-export/).

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

## 1. Select metrics and preview one day

1. Confirm the readings you want are present in Apple Health on this iPhone. Let your source app finish saving or syncing them first.
2. In Health.md, authorize the relevant health reads. Under **Health Metrics → Vitals**, select **Blood Pressure (Systolic)** and **Blood Pressure (Diastolic)**.
3. Choose **CSV** or **JSON**. Use **Summary** for daily statistics; enable **Detailed Time-Series** when you also need individual paired readings.
4. Choose one known day, use **YYYY-MM-DD** as the export date format for easy checking, and select a writable Files folder.
5. Tap **Preview**, check the dates, units and intended rows, then export. Open the saved file to confirm its contents and destination.

A longer range creates one file per day. Use the [first iPhone export guide](/docs/iphone-first-export/) for permissions and folder setup, or [troubleshooting](/docs/troubleshooting/) if Preview succeeds but saving fails.

Daily systolic and diastolic statistics come from separate quantity queries. Detailed readings come from actual HealthKit blood-pressure correlations, which group the two components. Health.md does not construct pairs by joining unrelated systolic and diastolic values. Apple's [blood-pressure correlation reference](https://developer.apple.com/documentation/healthkit/hkcorrelationtypeidentifier/bloodpressure) describes this paired representation.

## 2. Read the CSV without mixing statistics and readings

Inspect the [fictional daily CSV example](/docs/reference/generated/core/summary-day.csv). Its header is:

```csv
Date,Category,Metric,Value,Unit,Timestamp
```

These exact rows show two daily statistics and one paired reading:

```csv
2026-03-15,Vitals,Blood Pressure Systolic Avg,121.0,mmHg
2026-03-15,Vitals,Blood Pressure Diastolic Avg,79.0,mmHg
2026-03-15,Vitals,Blood Pressure Sample,121/79,mmHg,2026-03-15T01:23:20Z
```

Filter **Category = Vitals** and **Unit = mmHg**, then choose the exact Metric:

- **Blood Pressure Systolic Avg** or **Blood Pressure Diastolic Avg** for a daily average series. Separate Min and Max metrics may also be present.
- **Blood Pressure Sample** for individual paired readings. Its Value is text in systolic/diastolic order, such as `121/79`.

Keep the paired Value column as text when importing into a spreadsheet so a value containing `/` is not interpreted as a date. If you split it into two numeric columns, label them systolic and diastolic and retain the Timestamp. Do not turn `121/79` into a fraction or average it as one number.

The full Value column is mixed-type. Filter the intended metrics before converting cells to numbers. Summary rows above omit the final Timestamp field; the sample row has all six fields. Use a CSV-aware importer that preserves quoted fields and leaves an omitted final cell empty.

For spreadsheet import steps, use [Excel](/blog/apple-health-to-excel/) or [Google Sheets](/blog/apple-health-to-google-sheets/), applying the blood-pressure filters above. Keep daily averages and individual readings in separate series.

## 3. Use JSON for separate numeric components

The [fictional daily JSON example](/docs/reference/generated/core/summary-day.json) contains a nested `vitals` object. Daily fields include `bloodPressureSystolicAvg`, `bloodPressureDiastolicAvg`, and their Min/Max counterparts when available. The compatibility fields `bloodPressureSystolic` and `bloodPressureDiastolic` repeat the daily averages; they are not additional readings.

With detailed data available, `vitals.bloodPressureSamples` contains objects with separate numeric `systolic` and `diastolic` fields, `timestamp`, `endDate`, `unit`, and available identity/source metadata. In the fictional example, one object has systolic **121**, diastolic **79**, and unit **mmHg**. Those values demonstrate file structure, not a clinical example or a new device export.

Inspect the actual output's `units` and `time_context`. A timestamp ending in `Z` is UTC; the daily Date label follows the export calendar. Keep timezone conversion explicit when displaying readings. An omitted field or empty array is not a measured zero.

The example tests serializer output, not a complete day from which every daily statistic can be recomputed. Separate summary queries and paired-record queries can have different coverage. Do not assume that combining the two daily averages recreates a recorded pair.

## Check missing readings and saved copies

- **Statistics but no paired rows:** check Detailed Time-Series, selected metrics, the source day and permissions. A source may contain separate quantities without the correlations needed for paired rows.
- **No data:** confirm records, synchronization, date range and read access. An empty result does not prove that no measurement occurred or reveal whether access was denied.
- **Unexpected dates:** compare the export calendar and UTC timestamps before moving records between days.
- **Duplicate files:** keep the intended version of a re-exported day. Do not count repeated exports as new readings.

The local folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders and recipients govern their own copies. Inspect detailed timestamps and source information before sharing.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

For a non-synced destination, follow [export health data without the cloud](/blog/export-health-data-without-the-cloud/). Android users should start with the [Health Connect export guide](/health-connect-export/); this article's Apple field names and query behavior are not an Android contract.
