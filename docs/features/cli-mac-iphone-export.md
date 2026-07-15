# Mac CLI iPhone Export Trigger

## Status

- **Docs status:** draft
- **Primary surfaces:** Health.md macOS app, `scripts/healthmd` CLI, open Health.md iOS app
- **Source files:** `HealthMd/Shared/Sync/SyncPayload.swift`, `HealthMd/iOS/IPhoneExportRequestHandler.swift`, `HealthMd/macOS/Managers/HealthMdControlServer.swift`, `HealthMd/macOS/Managers/MacIPhoneExportRequestCoordinator.swift`, `HealthMdCLI/`, `scripts/healthmd`

## What it does

The Health.md Mac app exposes a local control interface that can ask a connected, already-open iPhone app to export Apple Health data to the Mac destination folder. The iPhone still reads HealthKit. By default, CLI requests use the iPhone's saved output subfolder, formats, metrics, filenames, and write behavior, but disable derived weekly/monthly/yearly roll-up summaries and summary-only mode so only the requested dates are fetched and written. The Mac still owns the selected destination root and performs all file writes.

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
- The selected Mac destination is the root folder. File exports append the iPhone's saved Health.md output subfolder and folder organization so local iPhone, Connected Mac, and CLI exports use the same relative path. Select the equivalent vault/root folder on Mac rather than a nested Health.md output folder.
- Jobs from older iPhone versions that do not include an output subfolder fall back to the Mac app's saved subfolder for compatibility.
- Pass `--raw` to return filtered raw `HealthData` JSON in the CLI response instead of writing files.
- Raw responses do not require a selected Mac destination folder, but still require the Mac app, connected/open iPhone app, HealthKit authorization, and available export quota.
- By default, CLI requests use `settings_policy: requested_dates_only`, which disables weekly/monthly/yearly roll-up summaries and summary-only mode for that one request without changing the iPhone's saved settings.
- The output subfolder, export formats, metrics, templates, write mode, daily note injection, and time-series settings still come from the iPhone app's saved settings.
- Pass `--use-iphone-settings` to use the iPhone app's saved export settings exactly, including roll-ups and summary-only mode.
- File-writing requests use the existing `MacExportJob` pipeline after the iPhone prepares HealthKit records.
- Raw requests return a structured `raw_data` payload containing source device, requested date range, total days, filtered `records`, failed date details, and the settings snapshot used for the fetch. When the WHOOP rollout flag is enabled and an account is connected, `externalDailyRecords` contains schema-v1 WHOOP sidecars for requested days that also follow the canonical Apple Health export path.
- A successful Mac-initiated file export or raw response records history and counts as one export action on iPhone.

## Limitations

This is not a fully headless cron replacement. If iOS suspends the app, the phone is locked, HealthKit is protected, or the Multipeer connection is unavailable, the request returns a structured failure instead of silently retrying forever.
