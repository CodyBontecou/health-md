# Mac CLI iPhone Export Trigger

## Status

- **Docs status:** draft
- **Primary surfaces:** Health.md macOS app, `scripts/healthmd` CLI, open Health.md iOS app
- **Source files:** `HealthMd/Shared/Sync/SyncPayload.swift`, `HealthMd/iOS/IPhoneExportRequestHandler.swift`, `HealthMd/macOS/Managers/HealthMdControlServer.swift`, `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift`, `HealthMdCLI/`, `scripts/healthmd`

## What it does

The Health.md Mac app exposes a local control interface that can ask a connected, already-open iPhone app to export Apple Health data to the Mac destination folder. The iPhone still reads HealthKit. By default, CLI requests use the iPhone's saved formats, metrics, filenames, and write behavior, but disable derived weekly/monthly/yearly roll-up summaries so only the requested dates are fetched and written. The Mac still writes files to its selected destination folder.

This is intended for power users who want shell/automation entry points without moving HealthKit reads to macOS.

## Requirements

- Health.md is running on Mac.
- Health.md is open on iPhone and connected to the Mac over the existing Mac Destination connection.
- The Mac destination folder is selected and writable.
- HealthKit access is already granted on iPhone.
- The iPhone is unlocked enough for HealthKit reads.
- The iPhone app version supports Mac-initiated export requests.

## CLI examples

From the repo checkout, app bundle, or standalone install:

```bash
scripts/healthmd status
scripts/healthmd export --iphone --yesterday
scripts/healthmd export --iphone --last 7
scripts/healthmd export --iphone --from 2026-06-01 --to 2026-06-07
scripts/healthmd export --iphone --yesterday --raw
scripts/healthmd export --iphone --yesterday --use-iphone-settings
```

The CLI prints JSON and exits non-zero when the Mac app is unreachable, no iPhone is connected, the destination is unavailable, the iPhone rejects the request, or the export fails before a usable result.

## Behavior

- Date ranges are capped at 366 days.
- Date range selection always comes from the CLI request.
+- By default, the Mac app writes export files to the selected Mac destination folder.
+- Pass `--raw` to return filtered raw `HealthData` JSON in the CLI response instead of writing files.
+- Raw responses do not require a selected Mac destination folder, but still require the Mac app, connected/open iPhone app, HealthKit authorization, and available export quota.
- By default, CLI requests use `settings_policy: requested_dates_only`, which disables weekly/monthly/yearly roll-up summaries for that one request without changing the iPhone's saved settings.
- Export formats, metrics, templates, write mode, daily note injection, and time-series settings still come from the iPhone app's saved settings.
- Pass `--use-iphone-settings` to use the iPhone app's saved export settings exactly, including roll-ups.
- File-writing requests use the existing `MacExportJob` pipeline after the iPhone prepares HealthKit records.
- Raw requests return a structured `raw_data` payload containing source device, requested date range, total days, filtered `records`, failed date details, and the settings snapshot used for the fetch.
- A successful Mac-initiated file export or raw response records history and counts as one export action on iPhone.

## Limitations

This is not a fully headless cron replacement. If iOS suspends the app, the phone is locked, HealthKit is protected, or the Multipeer connection is unavailable, the request returns a structured failure instead of silently retrying forever.
