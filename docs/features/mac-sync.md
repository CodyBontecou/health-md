# Mac Destination

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** iPhone → Mac Destination / Export; Mac → Mac Destination
- **Source files:** `HealthMd/iOS/Views/SyncSettingsView.swift`, `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Sync/SyncService.swift`, `HealthMd/Shared/Sync/SyncPayload.swift`, `README.md`

## What it does

Mac Destination lets Health.md for Mac appear as a local export target in the iPhone Export tab. The iPhone still owns HealthKit reads and every export setting: date range, metrics, formats, filename/folder templates, write mode, time-series data, daily note injection, and individual entry tracking.

The Mac app does one job: choose a local destination folder, receive the iPhone-configured export job over Apple Multipeer Connectivity, write the generated Markdown/Bases/JSON/CSV files to disk, and report progress/results back to the iPhone.

No HealthKit samples, Markdown files, or vault contents are uploaded to a Health.md server. The transfer is direct over local Wi‑Fi/Bluetooth.

## Who it is for

- Users who keep their Obsidian vault on a Mac.
- Users who prefer desktop filesystem paths while configuring exports on iPhone.
- Users who want iOS-only HealthKit reads with Mac-local file writes.
- Users exporting larger files, such as multi-format or granular time-series exports, to a Mac folder.

If you only export from iPhone to Files or iCloud Drive, Mac Destination is optional.

## Where to find it

On iPhone:

1. Open Health.md.
2. Tap **Mac Destination**.
3. Enable **Mac Destination**.
4. Go to **Export** and choose **Connected Mac** as the export target when the Mac is ready.

On Mac:

1. Open Health.md for macOS.
2. Stay on **Mac Destination**.
3. Connect to the iPhone if needed.
4. Choose the destination folder where received exports should be saved.

## Prerequisites

- Health.md installed on both iPhone and Mac.
- HealthKit permission granted on iPhone.
- Both devices on the same Wi‑Fi network or within Bluetooth range.
- Local network/Bluetooth permissions allowed if iOS/macOS asks.
- Health.md open on the Mac while exporting.
- A Mac destination folder selected and accessible.
- Compatible app versions on both devices. Older Mac builds can still use legacy sync, but cannot receive iPhone-configured export jobs.

## Setup

1. Install or open Health.md on the Mac.
2. On iPhone, open **Mac Destination** and turn on **Enable Mac Destination**.
3. Keep both devices nearby.
4. Wait for the status to change from **Waiting for Mac** to **Connected to [Mac name]**.
5. On Mac, choose a destination folder such as your Obsidian vault.
6. On iPhone, open **Export**.
7. Configure dates, metrics, formats, time-series data, filename/folder templates, write mode, and optional Markdown actions.
8. Select **Connected Mac** as the export target.
9. Tap **Preview** to inspect what will be written, or **Export** to send the job to Mac.

## Export behavior

Mac-target exports use the same iPhone settings as local iPhone exports:

- selected metrics from **Export → Health Metrics**;
- selected formats: Markdown, Obsidian Bases, JSON, CSV;
- filename and folder templates;
- write mode: overwrite, append, or update;
- daily note injection, if enabled;
- individual entry tracking, if enabled;
- time-series/granular data, if enabled.

The iPhone reads HealthKit, builds a portable job payload, and sends it to the Mac. The Mac validates destination-folder access, writes the files with the shared exporter, and returns accepted/progress/result/failure messages. A successful Mac export counts as one export action against the free quota, not one per file and not once on each device.

## Example output/path

If the Mac destination folder is an Obsidian vault named `MyVault`, a multi-format export can write:

```text
MyVault/Health/2026-05-12.md
MyVault/Health/2026-05-12.json
MyVault/Health/2026-05-12.csv
MyVault/Health/2026-05-12-bases.md
```

With time-series data enabled, the same filenames are used, but the contents can be much larger because they include timestamped samples.

## Legacy sync and cache

Older Health.md versions used a Mac health-data cache: the Mac requested records from iPhone, stored one JSON file per date, and exported later from that cache. The current model does not require that cache for new exports.

If legacy cached records exist, the Mac app shows a **Legacy Synced Cache** section and offers **Delete Legacy Cache**. Deleting it does not affect Apple Health on iPhone or files already exported to your destination folder.

## Tips

- Keep both apps open during export, especially for large date ranges or granular time-series payloads.
- Choose the Mac destination folder before selecting **Connected Mac** on iPhone.
- Use **Preview** on iPhone to verify filenames and destination before sending to Mac.
- Export a single day first when enabling time-series data or several formats.
- If you edit Markdown by hand, use **Update** mode so Health.md-managed sections are refreshed without replacing your notes.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| iPhone says no Mac connected | Mac app is closed, not browsing, or on a different network | Open Health.md on Mac, keep both devices nearby, enable Wi‑Fi/Bluetooth, and allow local network access. |
| Connected Mac option is disabled | Mac is connected but not ready | Check the Mac Destination screen for folder/access/status details. |
| Mac has no folder selected | The Mac destination folder has not been chosen | On Mac, click **Choose…** in Destination Folder and pick your vault/folder. |
| Mac folder access denied | The saved security-scoped bookmark no longer grants write access | Re-select the destination folder on Mac. |
| Incompatible app versions | One device is running an older build that lacks Mac export-job support | Update Health.md on both iPhone and Mac. |
| Mac app closed during export | Multipeer connection dropped before the job completed | Reopen the Mac app, reconnect, and run the export again from iPhone. |
| Large granular payload transfer fails | Time-series data or long ranges created a large resource transfer and the local connection dropped | Keep both apps foregrounded, devices nearby, and retry with a smaller date range if needed. |
| Files are written but counts look high | Multiple formats multiply file count | This is expected: `days × selected formats`, plus optional export side effects like Daily Note Injection or individual entries. |

## Video outline

- **Suggested title:** Use Your Mac as a Local Destination for iPhone Health.md Exports
- **Hook:** “Configure everything on iPhone, then save the files directly into your Mac Obsidian vault.”
- **Demo flow:**
  1. Show the Mac app explaining that it is a destination only.
  2. Choose a destination folder on Mac.
  3. Open iPhone → Mac Destination and enable the Mac destination toggle.
  4. Show connection/readiness status on both devices.
  5. Open iPhone → Export, configure formats/metrics/time-series data, and select **Connected Mac**.
  6. Tap Preview, then Export.
  7. Show Mac progress/activity and the generated files in the Mac folder.
- **Key screenshot/recording moments:** iPhone Mac Destination toggle, Mac Destination folder card, Connected Mac target option, preview destination row, Mac active export progress, generated Markdown/JSON/CSV files.
- **CTA / next video:** “Next, we’ll automate local iPhone exports with Scheduled Exports and Shortcuts.”

## Implementation notes

- `SyncService` wraps Multipeer Connectivity with `MCNearbyServiceAdvertiser` on iOS and `MCNearbyServiceBrowser` on macOS.
- The service type is `healthmd-sync`; sessions use required encryption.
- Current Mac-export messages include capabilities/status, `macExportRequest`, `macExportAccepted`, `macExportProgress`, `macExportResult`, `macExportFailed`, and `macExportCancel`.
- `MacDestinationStatus` tells iPhone whether the Mac is connected, compatible, has a selected folder, has healthy folder access, or is busy.
- `MacExportJob` carries iPhone-provided settings snapshots and per-date HealthKit export records; the Mac executor writes those records without reading HealthKit.
- Large payloads can use Multipeer resource transfer for reliability.
