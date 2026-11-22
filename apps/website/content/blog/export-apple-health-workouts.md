---
title: "Export Apple Fitness and Apple Health workouts (CSV, JSON)"
description: "Export Apple Fitness and Apple Watch workouts: Apple's native export.zip (export.xml plus GPX routes) or per-workout CSV and JSON with Health.md. Pick the right route."
lead: "Apple documents one export, in the Health app. For per-workout CSV or JSON from Apple Watch or Fitness workouts, select Workouts in Health.md, preview one known day, and export."
date: "2026-10-25"
updated: "2026-11-22"
category: "Workflow guide"
platform: apple
related:
  - export-apple-health-steps-data
  - export-apple-health-heart-rate
  - export-strava-data
draft: false
verified: "2026-11-22"
verified_by: "Claude (agent)"
verified_method: traced
tags:
  - apple-health
  - workouts
  - csv
  - json
---

**Can you export Apple Fitness data?** Apple documents its export in the **Health** app, not in Fitness: **Health → your picture or initials → Export All Health Data** produces `export.zip`. Workouts are `<Workout>` elements in `export.xml`, and recorded routes are GPX files in `workout-routes/`. For per-workout CSV or JSON you can open in Excel or script against, use Health.md to export workouts from Apple Watch or the Fitness app that are stored in Apple Health.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Health.md offers weekly, yearly and Lifetime access, and eligible subscriptions start with a 7-day free trial; see [purchase details](/docs/paywall/). Manual export runs on your iPhone and does not require a Mac.

## Where Apple Fitness workouts are stored

Health.md reads workouts from Apple Health. It does not connect to the Fitness app directly, and it cannot recover a workout that was never saved to Health. If a workout from your Apple Watch or iPhone is listed in Health, Health.md can read it, subject to your read authorization.

## Option 1: Apple's native export (export.zip)

Apple's [Share your health data guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) describes the export:

1. Open the **Health** app and tap your picture or initials.
2. Tap **Export All Health Data** and save or share the resulting `export.zip`.

For workouts, the archive contains:

- `<Workout>` elements in `export.xml`.
- GPX route files in `workout-routes/`, linked from each workout through `WorkoutRoute` → `FileReference`.

It is one large archive of everything in Health, not a per-workout spreadsheet. To parse it, see [where workout distance lives in export.xml](/blog/apple-health-export-xml-workout-distance/) and the [XML export guide](/blog/apple-health-xml-export/).

## Which route should you use?

| I want… | Use |
| --- | --- |
| The full archive or a backup | Apple's native export (`export.zip`) |
| The GPS route as GPX | Apple's archive: `workout-routes/`. Health.md does not write GPX. |
| Workouts in Excel or Sheets | Health.md CSV, then the [Excel](/blog/apple-health-to-excel/) and [Google Sheets](/blog/apple-health-to-google-sheets/) guides |
| One object per session, with IDs and start/end times | Health.md JSON |
| Upload to Strava or another service | Check that service's importer; Health.md does not write GPX, FIT or TCX. See the [Strava guide](/blog/export-strava-data/). |

For Health.md's own options beyond workouts, see [how to export Apple Health data](/apple-health-export/).

## Option 2: Health.md per-workout CSV or JSON

### Choose the format for the job

| Goal | Starting format | What to expect |
| --- | --- | --- |
| Inspect workout values in a spreadsheet | CSV | Several rows per workout, with Category, Metric, Value, Unit, and sometimes Timestamp. |
| Keep sessions separate for software or analysis | JSON | A `workouts` array with an object per exported workout, including ID, type, and exact start/end timestamps. |
| Read workout information beside daily notes | Markdown or Obsidian Bases | A readable daily projection; use structured output when source identity or detailed records matter. |
| Preserve selected public HealthKit source records | JSON or CSV with Lossless Health Records | An Apple-only canonical archive, with capture status, source identity, and query diagnostics to inspect. |

This walkthrough uses CSV and JSON, not a GPX, FIT, or TCX conversion. Route coordinates inside JSON are not automatically a file another fitness service can import. Check that service's accepted formats before choosing a workflow.

### 1. Check the source and authorize access

Confirm the workout from Apple Watch or the Fitness app is present in Apple Health on this iPhone. Health.md can read only records the watch or source app has written there and the public APIs make available under your authorization.

In Health.md, authorize the health categories you need and enable **Workouts** in **Health Metrics**. If you skipped access earlier, review Health.md's read permissions in Apple Health. Apple's [Health sharing and permissions guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) explains how to review app access and describes the separate native XML export.

A recorded workout does not guarantee that heart rate, distance, laps, power, cadence, or a route exists. Source apps, hardware, workout type, synchronization, and available permissions affect those fields. Selecting Workouts cannot reconstruct records that were never saved.

### 2. Preview one known workout day

1. Choose **CSV** or **JSON** and start with **Summary**. You can select both formats in the same export action.
2. Select the calendar day the workout **started**. Health.md's daily workout projection assigns sessions by their start time in the effective export calendar. For an overnight session, check the start day rather than only the day it ended.
3. Choose a writable folder in Files, such as a local folder or an explicitly chosen synced destination.
4. Tap **Preview**, inspect the date and workouts, then export. Open the saved file and confirm its contents and location.

A longer range produces daily files, not one combined workout workbook. Follow [your first iPhone export](/docs/iphone-first-export/) for setup, folder selection, and preview. For a non-synced destination, use the [local export guide](/blog/export-health-data-without-the-cloud/), including its separate backup checks.

### 3. Understand the workout CSV rows

Try the [synthetic daily CSV](/docs/reference/generated/core/summary-day.csv) before using personal records. It is generated by the exporter and contains fictional measurements, metadata, and several workout examples.

The header is `Date,Category,Metric,Value,Unit,Timestamp`. Filter `Category = Workouts`, then inspect Metric and Unit before treating Value as a number. Text labels, start times, formatted pace, and numeric measurements coexist in the same Value column.

The sample's running workout includes these source values:

| Metric | Value | Unit | Meaning |
| --- | --- | --- | --- |
| Workout Activity Type | Running | empty | Session type marker, timestamped at `2026-03-15T10:00:00Z`. |
| Running Duration | 3600.0 | seconds | 60 minutes of reported workout duration. |
| Running Distance | 10000 | meters | 10 kilometers. |
| Running Avg Pace | 6:00 /km | empty | Formatted pace text, not a decimal number. |
| Running Calories | 540.0 | kcal | Workout energy value. |
| Running Avg Heart Rate | 148 | bpm | An available workout statistic, not a heart-rate time series. |

**Several CSV rows describe one session.** Counting every Workouts row would count fields, not workouts. `Workout Activity Type` and `Workout Sport` are two descriptions of the same session, not two sessions.

Some identity/type rows have an exact Timestamp; many compatibility summary rows omit the final Timestamp field. Use a CSV-aware importer that keeps the remaining columns aligned and preserves quoted commas/newlines. Do not infer that every summary row has a unique session ID.

Two runs on the same day can have the same Metric labels. For reliable per-session grouping, use the JSON workout objects instead of grouping CSV rows only by date and the word “Running.” Keep distance, duration, calories, and heart-rate statistics separate rather than adding unlike units. See [Apple Health to CSV](/apple-health-to-csv/) for import rules.

### 4. Use JSON to keep workout sessions together

The [synthetic daily JSON](/docs/reference/generated/core/summary-day.json) contains a `workouts` array. Each workout object includes `id`, `type`, `sport`, `startTimeISO`, `endTimeISO`, `duration`, and `elapsedDuration`. Available source data can add distance, heart-rate statistics, laps, splits, device/source metadata, route points, or time-series arrays.

For the sample running object, `duration` is **3600 seconds** while `elapsedDuration` is **3900 seconds**. Its exact times run from **10:00 to 11:05 UTC**. Reported workout duration and elapsed start-to-end time can differ; do not overwrite one with the other or assume they measure the same thing.

Keep the workout ID and exact timestamps when combining daily JSON files. Review overlapping exports and source duplicates before counting sessions. Do not add an older and newer copy of the same workout together. Different IDs can still represent separate source recordings of the same activity, so an ID alone does not establish that two real-world sessions occurred.

JSON uses nested fields and arrays rather than CSV columns. Inspect the `units` and `time_context` metadata and the actual fields present. An omitted field is unavailable in that export, not automatically zero. Formatted distance or pace strings are display helpers; use numeric fields with their documented units for calculations.

## Routes, laps, and detailed records

A workout total, a route, and a stream of heart-rate samples are different data. Apple's [workout route documentation](https://developer.apple.com/documentation/healthkit/hkworkoutroute) describes route data as location samples associated with a workout. A distance total is not enough to rebuild those coordinates. Want the GPX route itself? Apple's native archive keeps recorded routes as GPX files in `workout-routes/`; Health.md does not write GPX. Parsing distance out of Apple's own `export.xml` instead? See [where workout distance lives in export.xml](/blog/apple-health-export-xml-workout-distance/).

Health.md's JSON renderer can include route and time-series data when the workout read returns them. **Inspect even a Summary JSON export before sharing it:** selecting Summary is not a guarantee that workout objects contain no detailed fields or coordinates. The synthetic JSON intentionally exercises optional fields; it is not a promise that every real workout includes them.

Detailed Time-Series adds selected samples and intervals where supported. Lossless Health Records adds Health.md's representation of selected public HealthKit/WorkoutKit records; it is Apple-only and not a copy of Apple's private database. Inspect capture status, query results, and warnings rather than assuming every possible record was captured. Read the [format guide](/docs/format/) and [canonical Apple Health record reference](/docs/reference/canonical-healthkit-records/) before using an archive.

Using Strava? Its own downloads and what it shares to Apple Health differ; see the [Strava export guide](/blog/export-strava-data/).

Laps and splits describe parts of a workout. Do not add their distance or duration to the complete workout total. Not every sport has every statistic, and running cadence in steps per minute is distinct from cycling cadence in revolutions per minute.

## FAQ

**Can you export Apple Fitness data?** Apple documents the export in the Health app (Export All Health Data, giving `export.zip`). For per-workout CSV or JSON, use Health.md on workouts stored in Health.

**Can I export workouts to Excel?** Yes: export CSV with Health.md and follow the [Excel guide](/blog/apple-health-to-excel/). Apple's `export.xml` is not a spreadsheet.

**Can I get the GPS route?** Apple's archive stores recorded routes as GPX in `workout-routes/`. Health.md JSON can include route points when the workout read returns them, but it is not a GPX file.

**Does Health.md export GPX or FIT?** No. It writes CSV, JSON and the other formats in the [format guide](/docs/format/), not GPX, FIT or TCX.

## Troubleshooting

- **No workouts on the selected day:** check the start date, Workouts selection, source records in Apple Health, read authorization, and source synchronization. Empty output does not reveal a specific permission-denial state.
- **Workout present, detail missing:** inspect the source and available permissions. A route, lap, or sample stream may not exist even when the workout total does.
- **Too many sessions or inflated totals:** do not count CSV metric rows as sessions, add laps/splits to totals, combine samples with summaries, or sum overlapping re-exports.
- **Unexpected date or duration:** compare the export calendar/timezone, ISO timestamps, reported duration, and elapsed duration before changing values.
- **Preview works but saving fails:** reselect the destination folder and check the provider's availability. See [export troubleshooting](/docs/troubleshooting/).

## Protect the exported files

The core local folder export requires no Health.md account and creates no Health.md server copy by default. Synced folders, recipient services, and AI uploads follow those providers' storage and privacy rules. Workout files can include exact times, device/source identifiers, and route locations; protect them as sensitive records.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. See [retention and destination boundaries](/privacy-policy.html#retention).

For spreadsheet analysis, continue with [Apple Health to Excel](/blog/apple-health-to-excel/) or [Google Sheets](/blog/apple-health-to-google-sheets/), adapting the metric filters and keeping sessions separate. For Android data, use the [Health Connect export guide](/health-connect-export/); its source semantics and archive capabilities must not be assumed identical to Apple's.
