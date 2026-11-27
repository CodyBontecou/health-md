---
title: "Export Strava data: bulk archive, GPX and CSV"
description: "Export Strava data from strava.com only: Settings → My Account → Download your account, then an emailed link. Also GPX, TCX and spreadsheet steps."
lead: "Strava exports are website-only. Request the full archive from Settings, export one activity as GPX, original or TCX, then open activities.csv in a spreadsheet."
date: "2026-10-30"
updated: "2026-11-20"
verified: "2026-11-20"
verified_by: "Claude (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - apple-health-to-excel
  - export-nike-run-club-data
draft: false
tags:
  - strava
  - workouts
  - apple-health
  - health-connect
---

**You can't export Strava data from the Strava mobile app; use strava.com in a browser.** For everything: **Settings → My Account → Download your account → Get Started → Request download**, then use the link Strava emails you. For one activity: open it on the website and choose **Export Original** or **Export GPX** from the ellipsis menu, or add `/export_tcx` to its URL.

Strava's own export covers these tasks. Health.md only matters later, if you want activities shared to Apple Health or Health Connect in daily files next to your other health data.

## Download all your Strava data (bulk export)

Steps from [Strava's export article](https://support.strava.com/en-us/articles/15401919-how-do-i-export-my-strava-data) (article dated September 14, 2026; checked **November 20, 2026**):

1. On strava.com, log in to the account you want to export.
2. Hover over your name at the upper right and choose **Settings**, then open the **My Account** tab.
3. Under **Download your account**, click **Get Started**.
4. On the next page, click **Request download**.
5. Strava emails a download link to the address on your profile. It can take a few hours, so check that address and your spam folder.

## What's in the Strava archive

Strava's article doesn't list the archive's contents. Tools that parse real archives describe a common layout, for example [geo-activity-playground's Strava notes](https://github.com/martin-ueding/geo-activity-playground/blob/main/docs/moving-from-strava.md) and [Redback's export description](https://redback-operations.github.io/redback-documentation/docs/project-3/research/strava-bulk-export-data-description). **Check your own download**, because contents can change:

- `activities.csv`: one row per activity, with an `Activity ID` and a `Filename` column pointing to that activity's file. Manually entered activities may have no file.
- `activities/`: per-activity files named by ID, often `.fit.gz` (gzip-compressed FIT), or `.gpx`/`.tcx` (sometimes also `.gz`). Unzip `.gz` files before opening them.
- `media/` (uploaded photos and videos, listed in `media.csv`), `routes/` (routes you created in Strava, not activity tracks), and dozens of other account CSVs such as `profile.csv` and `comments.csv`.

Some values in `activities.csv` may be Strava estimates rather than sensor measurements.

## Export a single activity (GPX, original or TCX)

Per Strava's article (checked November 20, 2026), on the website:

- **Original:** on the activity page, open the **More** (ellipsis) menu and choose **Export Original**. The file keeps the format it was uploaded in, often FIT.
- **GPX:** choose **Export GPX** from the same menu. GPX records GPS points, so an activity without GPS produces an empty or unreadable file. Power from a power meter is included; estimated power is not.
- **TCX:** add `/export_tcx` to the end of the activity's URL and press Enter. It works only for activities with GPS data, so some indoor activities may not export.

## Can I export from the Strava app?

No. Strava says exporting your data is only available on the Strava website. Use a browser on a computer.

Coming from Huawei Health? See [exporting Huawei Health data](/blog/export-huawei-health-data/) for its password-protected ZIP and Strava connection.

## Open Strava activities in Excel or Google Sheets

1. Unzip the archive and find `activities.csv`.
2. Use the spreadsheet's CSV import rather than double-clicking: Excel's **Data → From Text/CSV**, Numbers' **File → Open**, or Google Sheets' **File → Import**. Set the delimiter and locale so dates and decimal separators parse correctly.
3. Read the header row and check units before calculating. Distance, time and elevation columns may use different units; don't assume. Column headers follow your Strava account language (for example German headers and day-first dates), and Strava changes the column set over time ([source](https://github.com/martin-ueding/geo-activity-playground/blob/main/src/geo_activity_playground/features/strava/checkout_importer.py)).

Our [Apple Health to Excel](/blog/apple-health-to-excel/) and [Apple Health to Google Sheets](/blog/apple-health-to-google-sheets/) guides cover Health.md files, not Strava's CSV columns, but the import and cleanup habits carry over.

## Choose the right export

| Your goal | Start with |
| --- | --- |
| Everything in your account | Strava website → Settings → My Account → Download your account |
| Keep an original activity file | Strava website → activity → Export Original |
| Get a GPX or TCX activity file | Export GPX or `/export_tcx`, subject to GPS availability |
| Activities in a spreadsheet | Import `activities.csv` from the archive |
| Selected shared records in daily files or notes | Verify Apple Health or Health Connect records, then use Health.md |

A daily health file is not a copy of Strava's archive. A recorded activity, its route, sensor samples and social information are separate things.

## Keep Strava activities in daily health files with Health.md

Health.md does not connect to your Strava account, import the Strava archive, or create GPX, FIT or TCX files. It reads records Strava has already shared to Apple Health or Health Connect and saves them as daily CSV, JSON or Markdown. Sharing into the health store and reading from it are separate permissions.

### iPhone: Strava to Apple Health

Follow [Strava's Apple Health instructions](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava) (dated September 21, 2026; checked November 20, 2026): open **You → settings → Manage Apps and Devices → Health**, connect and authorize the required sharing categories, then enable **Send to Health**.

Strava documents sending activity type, time, distance, calories and route information. It also says **route information from activities recorded in another company's app, such as Garmin or Zwift, does not sync to Apple Health**. Inspect the actual activity and available fields on your phone; do not infer a route from its distance total.

The reverse direction has different rules. Strava's **Automatic Uploads** reads eligible Apple Workout activities from Apple Health; it does not establish that Strava wrote an activity out. The documented 30-day limit applies to that Apple Workout-to-Strava direction, not a guaranteed Strava-to-Health backfill period.

### Android: Strava to Health Connect

Follow [Strava's Health Connect instructions](https://support.strava.com/en-us/articles/15401554-health-connect-and-strava) (dated September 18, 2026; checked November 20, 2026): open **You → settings → Manage Apps and Devices → Health Connect** and complete the permission prompts.

Strava describes sending **time, distance and calories from GPS-based activities**, and receiving weight. Do not treat its weight import as a weight export or assume that this connection supplies indoor activities, heart-rate streams or route coordinates.

On Android 14 or later, find Health Connect in device settings; on earlier supported Android versions, use its app. Review Strava's permissions, then inspect one known activity's actual shared records. Health.md requires separate read access. For its Android requirements and history controls, use the [Health.md Android setup guide](/docs/android/).

## Export one known day with Health.md

Continue only after the records you need are visible in the phone's health store. Want your Strava activities in daily CSV, JSON or Markdown files with the rest of your health data? Get Health.md for [iPhone](https://apps.apple.com/us/app/health-md/id6757763969) or [Android](https://play.google.com/store/apps/details?id=com.healthmd.android).

1. Grant Health.md read access to the relevant categories. On Android, choose the **Health Connect** source.
2. Select the metrics or workouts you verified. Start with a completed day containing one recognizable activity and choose a writable folder.
3. Choose **CSV** for table inspection, **JSON** for structured processing or **Markdown** for daily notes. For notes in Obsidian, see [Apple Health data in Obsidian](/blog/export-apple-health-data-to-obsidian/) (iPhone) or [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/) (Android).
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

## FAQ

### How long does the Strava export take?

Strava says the download link may take a few hours to arrive by email. Strava's article gives no timing for single-activity downloads.

### Does the export include routes and photos?

Strava's article says GPX files record GPS points and TCX export needs GPS data, so a single-activity GPX or TCX file can carry a route only for GPS activities. Third-party descriptions of the archive show a `media/` folder for uploaded photos and videos, and per-activity files that carry GPS tracks when one was recorded. Strava doesn't document this, so check your download.

### Can I export another athlete's activity?

Strava's article covers exporting your own data. Don't assume another athlete's activities can be downloaded this way.

### Can I re-import an export into another app?

Use the other app's importer and check which formats it accepts. Strava's files are standard formats, but we can't promise any app reads them fully.
