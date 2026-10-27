---
title: "Apple Health export missing data? Troubleshoot Health.md"
description: "Fix empty Apple Health or Health Connect exports, missing sleep, CSV detail, failed file writes, and delayed schedules. Start with one verifiable day."
---

If an Apple Health or Health Connect export is missing data, first separate a **read problem** from a **file write problem**. Missing data is not a measured zero.

## Start with one day you can verify

1. Confirm a recorded value and its date in Apple Health or Health Connect. Let the watch or source app finish syncing first.
2. In Health.md, check the active profile, selected metric, date range, format, and destination. Start with one supported metric on one completed day.
3. Unlock the phone, open Health.md, and run Preview where available. Then export and inspect the actual result and destination. Preview does not prove that a file was saved.

For the first setup, follow [your first iPhone export](/docs/iphone-first-export/) or [Android setup](/docs/android/).

## The source has data, but the export is empty

On iPhone, review Health.md's allowed categories in Apple Health. **HealthKit does not reveal whether read permission was denied**, so an empty result alone cannot distinguish withheld access from no matching records. A successful permission request is not proof that every read category was allowed. See [Apple's authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

On Android, confirm that the source app actually wrote the record into Health Connect and that Health.md can read that supported type. Data visible only inside another app may not be available to export. See [Google's sync and permission checklist](https://support.google.com/android/answer/13770384).

Recheck the metric and date after changing permissions or syncing. Do not substitute zero for an absent value.

If a structured result reports `complete_empty`, keep it distinct from unsupported, partial, skipped, or failed output. It does not prove a measured zero or reveal a read-permission decision.

## Last night's sleep is missing from Today

Health.md assigns sleep to its **start day** on Apple and Android. On Tuesday morning, export **Yesterday** (Monday), or Monday and Tuesday. If the source syncs late, export the start day again. See [sleep dates](/docs/sleep-date-attribution/).

## Preview shows data, but the folder is empty

On iPhone, check whether the active profile writes to a local folder, Connected Mac, or API Endpoint. For folder exports, inspect the selected folder and subfolder, filename, and written, skipped, or failed result. A skipped file may reflect the chosen write behavior. Reselect an unavailable folder and verify its file provider before retrying. See [folders and vaults](/docs/folder-vault/) and [export profiles](/docs/export-profiles/).

## The CSV has totals, but not the readings I expected

On iPhone, Summary and Detailed Time-Series contain different detail. Check the selected Data Detail and metrics before expanding the date range. Metadata rows are not health measurements; preserve units and distinguish daily totals from source records. Lossless Health Records has a separate capture status, and a summary alone does not prove complete source capture. See the [format and coverage reference](/docs/reference/export-formats/).

## A scheduled export did not arrive

iOS background work and Android WorkManager use target times, not guaranteed delivery times. Unlock the device, open Health.md, and inspect history and pending recovery before starting another run. A notification is not proof of a successful write. Use [iPhone scheduling and recovery](/docs/scheduling/) or [Android automation](/docs/android/).

## CLI timeout

A timeout does not cancel an accepted job:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Before claiming completeness, inspect status, missing dates, coverage, `next_cursor`, version, and limitations. `--allow-partial` changes exit policy only.

## Ask for help without sharing health records

Report the app and OS version, platform, selected format, and whether the problem is empty data, skipped output, or a failed write. Redact screenshots or logs before sharing. Do not publish health values, routes, clinical documents, tokens, pairing codes, or private paths.

<div class="related"><a href="/docs/cli-jobs/"><span>Jobs</span>Resume and cancel safely.</a><a href="/docs/release-status/"><span>Versions</span>Check exact compatibility.</a></div>
