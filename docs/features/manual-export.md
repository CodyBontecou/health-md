# Manual Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Managers/ExportOrchestrator.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Manual Export writes or sends Apple Health data for a selected date range immediately. It uses the current metric selection, export formats, folder settings, filename template, write mode, and optional export side effects like roll-up summaries, daily note injection, or individual entry tracking. The destination can be the selected iPhone folder, a connected Mac destination, or a user-configured API endpoint.

This is the fastest way to backfill a few days, test your settings, or export on demand without relying on schedules or Shortcuts.

## Who it is for

- Users doing their first Health.md export.
- Users backfilling a specific date range.
- Users testing folder, filename, format, or metric settings.
- Users who prefer manual control over automation.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Choose **Start Date** and **End Date**.
4. Pick an export target: **iPhone Folder**, **Connected Mac**, or **API Endpoint**.
5. Configure metrics, formats, output, and write mode.
6. Tap **Export** in the bottom export bar.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected for iPhone-folder exports, a connected Mac with a selected destination folder for Mac-target exports, or a configured API endpoint for API exports.
- At least one export format selected.
- At least one enabled metric with data for the selected dates.
- Free export quota remaining or Full Access unlocked.

## Setup

1. Confirm the **Health** badge is connected.
2. Choose the export target:
   - **iPhone Folder** writes to the folder selected on iPhone.
   - **Connected Mac** sends the iPhone-configured export job to Health.md on Mac, which writes to the folder selected on Mac.
   - **API Endpoint** POSTs a JSON envelope directly from iPhone to the endpoint you configure.
3. Confirm the selected target is ready.
4. Set the date range.
5. Open **Health Metrics** and enable the metrics you want.
6. In **Export Formats**, select Markdown, Obsidian Bases, JSON, CSV, or any combination.
7. Optional: enable frontmatter, category grouping, roll-up summaries, time-series data, daily note injection, or individual entry tracking.
8. In **Output**, confirm subfolder, folder organization, and filename format.
9. Choose **When File Exists**: Overwrite, Append, or Update.
10. Tap **Preview** if you want a dry run; preview shows the active destination.
11. Tap **Export**.

## Example output/path

Default settings for one Markdown export to the iPhone folder:

```text
MyVault/Health/2026-05-12.md
```

When roll-up summaries are enabled, Health.md also writes derived period files for the full week/month/year windows touched by the selected dates. Roll-ups are generated for every selected export format:

```text
MyVault/Health/Rollups/Weekly/2026-W20.md
MyVault/Health/Rollups/Weekly/2026-W20.json
MyVault/Health/Rollups/Weekly/2026-W20.csv
MyVault/Health/Rollups/Weekly/2026-W20-bases.md
MyVault/Health/Rollups/Monthly/2026-05.md
MyVault/Health/Rollups/Yearly/2026.md
```

Enable **Summary files only** when you want just those roll-up files, such as monthly files under `Health/Rollups/Monthly/`, without daily Markdown/Bases/JSON/CSV files. Summary-only mode skips daily-note injection and individual entry files for that export target.

If Daily Note Injection is enabled with Folder set to `Daily`, the injection target is resolved from the selected vault/root destination, not from the Health.md export subfolder:

```text
MyVault/Daily/2026-05-12.md
```

A successful status message may look like:

```text
Exported to Health/2026-05-12.md
```

If **Connected Mac** is selected, the same relative path is written under the destination folder chosen on Mac. If multiple formats are selected, one file is written per selected format per date:

```text
MyVault/Health/2026-05-12.md
MyVault/Health/2026-05-12.json
MyVault/Health/2026-05-12.csv
MyVault/Health/2026-05-12-bases.md
```

If **API Endpoint** is selected, Health.md does not write a file for that target. It sends a POST request to the configured endpoint:

```text
POST https://api.example.com/healthmd/ingest
```

The request body contains a `healthmd.api_export` envelope with one public Health.md JSON record per successful day. See [API Endpoint Export](./api-endpoint-export.md).

## Write modes

| Mode | Behavior |
|---|---|
| Overwrite | Replace existing files with newly generated health data. |
| Append | Add new export content to the end of an existing file. |
| Update | For Markdown, update Health.md-managed sections while preserving custom content; for non-Markdown formats, overwrite. |

## Tips

- Run a one-day export first to verify the path and content.
- Use **Preview** before exporting a long range, sending a job to Mac, or uploading to an API endpoint.
- Use **Update** for Markdown files you also edit by hand.
- Enable roll-up summaries only when you want aggregate weekly/monthly/yearly overview files; they are not daily records and remain off by default.
- Turn on **Summary files only** plus **Monthly summaries** to generate monthly files without daily files.
- Keep **Organize by File Type** off if an Obsidian plugin, shortcut, or script expects flat Health.md paths; update those integrations before turning it on.
- Use **Overwrite** for JSON, CSV, and Obsidian Bases when you want clean regenerated files.
- Include time-series data only when you need individual timestamped samples; it can make files larger.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export button is disabled | Missing permission, target readiness, format, or quota | Check Health badge, target status, Export Formats, and unlock/free exports. |
| Some dates failed | No HealthKit data or file access issue for those dates | Narrow the range, verify Apple Health data, and retry failed dates. |
| Export stopped mid-range | Export was cancelled | Tap Export again for the remaining dates. |
| Existing content disappeared | Overwrite mode replaced the file | Use **Update** for hand-edited Markdown files. |
| Daily note path conflict | The normal export output and Daily Note Injection target resolve to the same `.md` file | Change **Output** folder/filename or **Daily Note Injection** folder/filename. Health.md blocks the export instead of overwriting the daily note. |
| No file was written | No health data, no formats selected, or destination unavailable | Select formats, verify Health data exists, and confirm the iPhone folder or Mac destination is ready. |
| Connected Mac is unavailable | Mac is closed, incompatible, busy, or has no accessible destination folder | Open Health.md on Mac, update both apps, choose/re-select the destination folder, then retry from iPhone. |
| API export failed | Endpoint URL, auth token, server route, or server response failed | Check API Endpoint settings, server logs, and the HTTP status shown by Health.md. |

## Video outline

- **Suggested title:** Export Apple Health to Markdown Manually
- **Hook:** “One tap turns a date range of Apple Health data into files you own.”
- **Demo flow:**
  1. Show Health and Vault connected.
  2. Choose yesterday as the date range.
  3. Pick a few metrics and Markdown.
  4. Show output path preview.
  5. Optionally switch to Connected Mac and show the Mac destination path.
  6. Optionally switch to API Endpoint and show the configured POST target.
  7. Tap Preview, then Export.
  8. Open the generated file in Files, Obsidian, or the selected Mac folder, or inspect the received API payload.
  9. Repeat with a multi-day range.
- **Key screenshot/recording moments:** date range controls, export formats, path preview, progress bar, success message, generated file or API payload.
- **CTA / next video:** “Next, we’ll preview an export before writing anything.”

## Implementation notes

- Manual export uses `ExportOrchestrator.exportDates(...)` with an inclusive date array from `dateRange(from:to:)`.
- Each date fetches HealthKit data through `healthKitManager.fetchHealthData(for:includeGranularData:)`.
- Local iPhone exports call `VaultManager.exportHealthData(...)` directly; Mac-target exports build a `MacExportJob` and the Mac executor writes the same selected formats from the iOS settings snapshot; API-target exports build a `healthmd.api_export` JSON envelope and POST it from iPhone.
- `ExportResult` tracks successes, failures, cancellation, formats per date, and total files written.
- Daily Note Injection runs once per exported date when it is enabled and at least one export format is selected, including Manual Export.
