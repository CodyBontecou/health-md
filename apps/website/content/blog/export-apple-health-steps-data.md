---
title: "How to export steps from Apple Health (export.xml or daily CSV)"
description: "Apple Health has no steps-only export. Filter export.xml for StepCount records, or save one steps total per day as CSV or JSON with Health.md."
lead: "Apple's export is all-or-nothing, and its step records overlap. Find them in export.xml, or save one total per day."
date: "2026-10-26"
updated: "2026-11-24"
category: "Workflow guide"
platform: apple
related:
  - apple-health-xml-export
  - apple-health-to-excel
  - export-apple-health-walking-asymmetry
draft: false
verified: "2026-11-24"
verified_by: "Claude (agent)"
verified_method: traced
tags:
  - apple-health
  - steps
  - csv
  - export
---

**Apple Health has no export for steps alone.** Its native route is **Health → your picture or initials → Export All Health Data**, which creates `export.zip`. Inside, `export.xml` holds steps as `<Record>` elements whose `type` is `HKQuantityTypeIdentifierStepCount`. If you want one daily total per day as CSV or JSON without parsing XML, Health.md writes daily files from the Apple Health data you authorize.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Apple's [Health data instructions](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) document Export All Health Data. Health.md does not import that XML archive, and manual export needs no Mac.

## Choose every step record or one total per day

| What you need | Export route |
| --- | --- |
| Every interval record, with its source and times | Apple's native archive: Health → profile → Export All Health Data, then filter `export.xml` for StepCount records |
| One total per day for a spreadsheet or script | Health.md Summary export with Steps selected, as CSV or JSON (`Activity / Steps`, `activity.steps`) |
| Selected source records with identity and diagnostics | The separate Apple-only Lossless Health Records profile; review its coverage and warnings |

Health.md can also write steps into Markdown or Obsidian Bases daily notes. **Detailed Time-Series does not add step-sample or hourly-step rows to the daily steps export.** The archive represents selected public HealthKit API results, not Apple's private database; read the [format guide](/docs/format/) and [canonical Apple Health records reference](/docs/reference/canonical-healthkit-records/) before treating it as a source-record dataset.

## Find steps in Apple's export.xml

Apple's [step count type](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stepcount) is cumulative count data, and each `<Record>` is an interval count: not one footstep, and not a daily total. This fictional excerpt uses only attributes that the export DTDs declare for `Record` (`type`, `sourceName`, `unit`, `creationDate`, `startDate`, `endDate`, `value`), with an iPhone-like and a Watch-like source whose intervals overlap:

```xml
<Record type="HKQuantityTypeIdentifierStepCount" sourceName="Example iPhone" unit="count" creationDate="2026-03-15 09:06:00 +0000" startDate="2026-03-15 09:00:00 +0000" endDate="2026-03-15 09:05:00 +0000" value="25"/>
<Record type="HKQuantityTypeIdentifierStepCount" sourceName="Example Watch" unit="count" creationDate="2026-03-15 09:06:30 +0000" startDate="2026-03-15 09:01:00 +0000" endDate="2026-03-15 09:05:30 +0000" value="24"/>
```

The values are invented, and they are not a real person's steps. Both records describe the same walk.

**Adding up every row can double count.** iPhone, Apple Watch and other apps each write their own StepCount records, and those intervals can overlap. Apple Health shows a total that uses [source priority](https://support.apple.com/en-us/108779) for the data type. A naive sum of every row in the XML would count the overlapping walk twice, so it can come out higher than Health shows. Health.md's daily value instead comes from a HealthKit cumulative-sum statistics query ([HKStatisticsQuery](https://developer.apple.com/documentation/healthkit/hkstatisticsquery)), which matches the daily statistic rather than a naive sum. It is still not guaranteed to match every view or app.

To pull steps out, filter rows where `type` equals `HKQuantityTypeIdentifierStepCount`. Read your own file's inline DTD (`<!DOCTYPE HealthData [ … ]>`) for the attributes your export version declares; the [DTD copies cited in the workout-distance guide](/blog/apple-health-export-xml-workout-distance/) show how to check. For unzipping and finding `export.xml`, see the [Apple Health XML guide](/blog/apple-health-xml-export/). The [weight guide](/blog/export-apple-health-weight-data/) follows the same native-first pattern for another metric.

## Export one known day first

1. Confirm that steps appear in Apple Health on this iPhone. Health.md reads authorized HealthKit data; it does not create missing step measurements.
2. In Health.md, authorize the relevant health categories. Open **Health Metrics → Activity** and enable **Steps**.
3. Choose **CSV** or **JSON**, start with **Summary**, and select one known day. Use **YYYY-MM-DD** date formatting to make comparisons straightforward.
4. Select a writable Files folder. Tap **Preview** and check the date and total, then run the export.
5. Open the saved file in that folder and confirm its contents and location. Preview alone does not establish that writing succeeded.

Follow [your first iPhone export](/docs/iphone-first-export/) for setup and folder selection. Apple's [Health access instructions](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) explain how to review app read permissions.

Choose a completed day for the first comparison. Today's count can change as the phone, watch, or another source writes more data. If records arrive later, re-export the affected date and keep the intended version rather than adding both exports together.

## Verify the CSV and JSON fields

Download the [synthetic daily CSV](/docs/reference/generated/core/summary-day.csv) to test an import without personal records. It contains fictional values and metadata generated by the exporter. Its header is `Date,Category,Metric,Value,Unit,Timestamp`, and its steps row is:

```csv
2026-03-15,Activity,Steps,12500,count
```

That is **12500 steps for the daily summary**, not one timed walking interval. The row has five fields and omits the final Timestamp; a CSV-aware importer should leave that last cell empty while keeping the first five aligned.

For steps analysis, filter exactly `Category = Activity`, `Metric = Steps`, and `Unit = count`. The full Value column is mixed-type and also contains metadata, text, and other metrics. Convert only the filtered values to numbers; a different metric that also uses `count` is not another step total.

The [synthetic daily JSON](/docs/reference/generated/core/summary-day.json) represents the same total as `activity.steps = 12500`. JSON is nested rather than a CSV table. Its units dictionary labels `steps` as `steps`, while the compatibility CSV row uses `count`; inspect the format's actual metadata instead of expecting identical labels everywhere.

An omitted step field or row is unavailable data in that export, not automatically zero. Preserve any explicitly recorded numeric zero separately from missing data.

## Make a daily or weekly spreadsheet view

A longer range produces **one file per day**, not one combined workbook. Import the daily CSV files into one source table with a single header, keeping the columns in order and checking that every intended date appears. Follow the [Excel walkthrough](/blog/apple-health-to-excel/) or [Google Sheets walkthrough](/blog/apple-health-to-google-sheets/) for the import and combination steps.

After applying the exact Steps filter:

- Keep one intended daily total per Date. Investigate duplicates from overlapping exports before calculating.
- Parse Date using the selected export format and inspect it against the original file. Formatting text as Date alone does not parse it.
- Convert the selected Value cells to numbers and keep Unit visible. Inspect conversion errors; do not replace errors or missing dates with zero.
- For a daily chart, sort by Date and chart the numeric Steps value. A line between dates does not prove that the missing dates were recorded.
- For a weekly report, use SUM for recorded totals or AVERAGE for average daily steps over recorded numeric days. Report the recorded-day count, missing dates, and partial weeks.

Do not mix daily summaries with weekly/monthly rollups, duplicated exports, or source records. They can describe overlapping activity. Seven daily files also do not establish seven recorded step values if some dates have no Steps row.

Walking metrics such as step length and walking asymmetry export the same way; see [walking asymmetry on iPhone](/blog/export-apple-health-walking-asymmetry/).

## Why steps can differ between views

If two views disagree, compare the same completed date, timezone/calendar, source availability, and synchronization state. Inspect the data sources contributing to Steps in Apple Health, and see the double-counting explanation above for raw XML sums. Do not assume this guide guarantees equality with every third-party app's reduction. Some wearables also count steps on their own schedule and leave them out of their native export; the [WHOOP export guide](/blog/export-whoop-data/) covers a strap whose CSV has no step count and whose steps follow a wake-to-wake cycle.

For canonical source records, preserve the original UUID, type, exact start/end intervals, source information, units, capture status and warnings. Repeated copies of the same source UUID are different from two independently recorded objects that overlap in time. Do not deduplicate different source records merely because a value or timestamp matches, and do not add the canonical records to the daily total.

Daily statistics and source-record ownership also use different query semantics. Check the archive's ownership/time context and the selected range before attempting to reconstruct a total. A record spanning a boundary is not a reason to copy the full value into both days yourself.

## Troubleshooting

- **No Steps row:** check the source records, selected day, Steps toggle, source synchronization, and read authorization. Absence does not establish zero or identify a particular permission-denial state.
- **No hourly rows after enabling detail:** the current daily Steps output remains a total; Detailed Time-Series does not create an hourly series for it.
- **A recent total changed:** source data may have arrived since the earlier export. Inspect the original records and keep the intended replacement file.
- **My XML total is much higher than Health shows:** overlapping sources. iPhone, Watch and apps each write StepCount records, and Health applies source priority; see "Find steps in Apple's export.xml" above.
- **Weekly total looks too high:** check duplicate dates, repeated headers, other count metrics, rollups, and raw records mixed with summaries.
- **Preview works but no file is saved:** reselect the folder and check its provider's availability. See [export troubleshooting](/docs/troubleshooting/).

## Keep control of the exported files

The core local folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders, recipients, online spreadsheets, and model providers follow their own storage and privacy rules. Source archives can preserve exact timestamps, identifiers, and provenance; inspect them before sharing.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

For a non-synced folder and backup checks, follow [export health data without the cloud](/blog/export-health-data-without-the-cloud/). For exact row contracts, use [Apple Health to CSV](/apple-health-to-csv/). Android readers should follow the [Health Connect export guide](/health-connect-export/) and its documented aggregation behavior rather than assume identical source semantics.
