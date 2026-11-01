---
title: "Export Strava data: activity files or shared daily records"
description: "Download Strava activity files or an account archive, or export selected records shared to Apple Health or Health Connect as daily CSV, JSON and notes."
lead: "Use Strava's own downloads for original activity files. Use Health.md when selected records already shared to your phone belong in daily files or notes."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-polar-flow-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - strava
  - workouts
  - apple-health
  - health-connect
---

**Strava already provides activity downloads and an account archive. You do not need Health.md for those exports.** Start there when you need files for another fitness service or want the records Strava provides directly.

Health.md serves a different task: save selected records already available in Apple Health or Health Connect as daily CSV, JSON or Markdown files. This workflow does not connect directly to your Strava account or import its downloaded archive.

## Choose the right export

| Your goal | Start with |
| --- | --- |
| Keep an original activity file | Strava website → activity → Export Original |
| Get a GPX or TCX activity file | Strava's documented activity export, subject to GPS availability |
| Download an account archive | Strava website → Settings → My Account → Download your account |
| Keep selected shared records beside other daily health data or notes | Verify Apple Health or Health Connect records, then use Health.md |

The shared health-store representation is not a copy of Strava's account archive. A recorded activity, its route, sensor samples, social information and calculated scores are separate things. Do not assume a daily file preserves them all.

## Download directly from Strava

Use Strava's [official website export instructions](https://support.strava.com/en-us/articles/15401919-how-do-i-export-my-strava-data), checked **October 30, 2026**:

- **Original:** on your activity, choose **Export Original** from the ellipsis menu. The uploaded format is retained.
- **GPX:** choose **Export GPX**. Non-GPS activities can produce empty or unreadable files.
- **TCX:** append `/export_tcx` to your own GPS activity's URL; review the documented GPS restriction.
- **Archive:** open **Settings → My Account → Download your account → Get Started → Request download**, then use the emailed link.

Keep the original files and inspect their contents before converting or importing them elsewhere. Health.md's CSV/JSON workflow below does not produce a GPX, FIT or TCX replacement. Coordinates inside JSON are not automatically an activity file another service accepts.

## Check what Strava actually shared

Sharing into the phone's health store and reading from that store are separate permissions. A connected status does not prove that the activity or field you need is present.

### iPhone: Strava to Apple Health

Follow [Strava's Apple Health instructions](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava): open **You → settings → Manage Apps and Devices → Health**, connect and authorize the required sharing categories, then enable **Send to Health**.

Strava documents sending activity type, time, distance, calories and route information. It also says **route information from activities recorded in another company's app, such as Garmin or Zwift, does not sync to Apple Health**. Inspect the actual activity and available fields on your phone; do not infer a route from its distance total.

The reverse direction has different rules. Strava's **Automatic Uploads** reads eligible Apple Workout activities from Apple Health; it does not establish that Strava wrote an activity out. The documented 30-day limit applies to that Apple Workout-to-Strava direction, not a guaranteed Strava-to-Health backfill period.

### Android: Strava to Health Connect

Follow [Strava's Health Connect instructions](https://support.strava.com/en-us/articles/15401554-health-connect-and-strava): open **You → settings → Manage Apps and Devices → Health Connect** and complete the permission prompts.

Strava describes sending **time, distance and calories from GPS-based activities**, and receiving weight. Do not treat its weight import as a weight export or assume that this connection supplies indoor activities, heart-rate streams or route coordinates.

On Android 14 or later, find Health Connect in device settings; on earlier supported Android versions, use its app. Review Strava's permissions, then inspect one known activity's actual shared records. Health.md requires separate read access. For its Android requirements and history controls, use the [Health.md Android setup guide](/docs/android/).

## Export one known day with Health.md

Continue only after the records you need are visible in the phone's health store:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Grant Health.md read access to the relevant categories. On Android, choose the **Health Connect** source.
2. Select the metrics or workouts you verified. Start with a completed day containing one recognizable activity and choose a writable folder.
3. Choose **CSV** for table inspection, **JSON** for structured processing or **Markdown** for daily notes.
4. Preview, export and open the actual saved file. Compare its date, units and available fields with the source before increasing the date range.

Daily exports create separate files for the selected days. On iPhone, use the [Apple Health workout guide](/blog/export-apple-health-workouts/) for start-day assignment, JSON session grouping and the difference between reported and elapsed duration. On Android, follow the [Health Connect export guide](/health-connect-export/); do not assume Apple's archive or field rules apply.

Health.md reads authorized records available through the platform. It cannot retrieve a Strava-only field, rebuild an absent route or make unshared history appear. Other apps can contribute records to the same health store, so the output is not automatically a Strava-only report.

## Inspect a sample before your own files

The [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) demonstrate Health.md output, including workout examples. The separate [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) illustrates Android output. None is a Strava archive or proof that Strava supplies every illustrated field.

Use a CSV-aware importer and filter the intended Category, Metric and Unit before converting Value to numbers. The column can also contain labels, times and other text. Several rows can describe one workout; counting rows is not counting sessions. For iPhone per-session processing, use the workout guide's JSON instructions instead of grouping repeated CSV labels only by date.

Before combining files, check units, time context, overlapping dates and re-exports. Keep the intended version rather than counting a workout twice. Do not add laps, samples or daily totals to a complete session total. An absent value is unavailable, not zero.

## When an activity or field is missing

- **Absent from Apple Health or Health Connect:** check the sharing direction, source activity, relevant write permissions and Strava's supported fields first. An exporter cannot recover an unshared record.
- **Present in the health store but absent from the file:** check Health.md read access, selected metrics, dates, history access and saved destination.
- **Workout present but no route or sensor stream:** a session summary does not establish that the detailed records exist. Use Strava's original file if that is the representation you need.
- **Looking for older history:** neither a new app connection nor a wider Health.md date range promises that Strava backfilled it. Retain the native archive and compare actual coverage.
- **Preview succeeds but saving fails:** reselect the folder and inspect the file provider using [export troubleshooting](/docs/troubleshooting/).

## Protect location and health records

Activity exports can contain exact times, identifiers and location data. Review the actual file, including any optional detailed fields, before sharing it. Choosing a daily summary is not a universal guarantee that coordinates are absent.

Core folder exports need no Health.md account and create no Health.md server copy by default. Synced folders and recipient services follow their own storage rules. The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot.

See the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup checks. For another source ecosystem, use the [Garmin export guide](/blog/export-garmin-connect-data/) rather than assuming Strava's sharing rules apply to Garmin's own connection.
