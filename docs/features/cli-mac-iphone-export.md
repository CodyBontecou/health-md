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
scripts/healthmd export --iphone --last 7 --raw --allow-partial
scripts/healthmd export --iphone --yesterday --use-iphone-settings
```

The CLI prints JSON and exits non-zero when the Mac app is unreachable, no iPhone is connected, the destination is unavailable, the iPhone rejects the request, or the export fails before a usable result.

## Behavior

- Date ranges are capped at 366 days.
- Date range selection always comes from the CLI request.
- The selected Mac destination is the root folder. File exports append the iPhone's saved Health.md output subfolder and folder organization so local iPhone, Connected Mac, and CLI exports use the same relative path. Select the equivalent vault/root folder on Mac rather than a nested Health.md output folder.
- Jobs from older iPhone versions that do not include an output subfolder fall back to the Mac app's saved subfolder for compatibility.
- Pass `--raw` to request the strict `canonical_source_records_v1` profile instead of writing files. Each retained day is the public canonical `healthmd.health_data` JSON document (including its schema version, time context, and canonical archive), wrapped in a versioned `healthmd.raw_result` envelope.
- Strict raw capture temporarily forces granular source-record capture without changing the iPhone's saved granular-data setting. Complete empty days and warning-only days are retained. Per-day outcomes and the capture summary report records, query statuses, integrity warnings, partial failures, and missing dates.
- A failed, cancelled, missing, unsupported/skipped, or otherwise partial requested day/type returns `status: partial_success`. Raw CLI requests exit non-zero for that status unless `--allow-partial` is passed; diagnostics are always printed. Complete empty capture remains a success.
- Raw responses do not require a selected Mac destination folder, but still require the Mac app, connected/open iPhone app, HealthKit authorization, available export quota, and a peer advertising the required canonical archive/raw-result versions. Strict requests reject old peers rather than downgrading.
- By default, CLI requests use `settings_policy: requested_dates_only`, which disables weekly/monthly/yearly roll-up summaries and summary-only mode for that one request without changing the iPhone's saved settings.
- The output subfolder, export formats, metrics, templates, write mode, daily note injection, and time-series settings still come from the iPhone app's saved settings.
- Pass `--use-iphone-settings` to use the iPhone app's saved export settings exactly, including roll-ups and summary-only mode.
- File-writing requests use the existing `MacExportJob` pipeline after the iPhone prepares HealthKit records.
- Current `--raw` requests return `raw_result`. Legacy API/sync requests that omit `raw_profile` remain decodable and receive the prior `raw_data` internal-Codable shape and semantics; strict clients never accept that shape as a downgrade. Legacy external provider sidecars remain on that legacy response path.
- A successful Mac-initiated file export or raw response records history and counts as one export action on iPhone.

## Local control boundary

The Mac control API listens only on IPv4 `127.0.0.1` and IPv6 `::1` and rejects accepted peer endpoints that are not loopback. Requests have a 16 KiB header limit, a 256 KiB body limit, and a 10-second receive deadline. `POST /v1/exports` requires `Content-Type: application/json` and an explicit content length. `wait_timeout_seconds` must be finite and between 5 and 900 seconds. There is no bearer token in this version; loopback is the current authorization boundary and the server is structured so authentication can be added later.

Coordinator timeouts and iPhone disconnects send the existing `iphoneExportCancel` message when possible. A result arriving after completion/cancellation is ignored.

## Limitations

This is not a fully headless cron replacement. If iOS suspends the app, the phone is locked, HealthKit is protected, or the Multipeer connection is unavailable, the request returns a structured failure instead of silently retrying forever.
