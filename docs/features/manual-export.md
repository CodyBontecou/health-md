# Manual Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Managers/ExportOrchestrator.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Manual Export writes Apple Health data for a selected date range to your chosen folder immediately. It uses the current metric selection, export formats, folder settings, filename template, write mode, and optional Markdown side effects like daily note injection or individual entry tracking.

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
4. Configure metrics, formats, output, and write mode.
5. Tap **Export** in the bottom export bar.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- At least one export format selected.
- At least one enabled metric with data for the selected dates.
- Free export quota remaining or Full Access unlocked.

## Setup

1. Confirm the **Health** badge is connected.
2. Confirm the **Vault** badge shows your target folder.
3. Set the date range.
4. Open **Health Metrics** and enable the metrics you want.
5. In **Export Formats**, select Markdown, Obsidian Bases, JSON, CSV, or any combination.
6. Optional: enable frontmatter, category grouping, time-series data, daily note injection, or individual entry tracking.
7. In **Output**, confirm subfolder, folder organization, and filename format.
8. Choose **When File Exists**: Overwrite, Append, or Update.
9. Tap **Preview** if you want a dry run.
10. Tap **Export**.

## Example output/path

Default settings for one Markdown export:

```text
MyVault/Health/2026-05-12.md
```

A successful status message may look like:

```text
Exported to Health/2026-05-12.md
```

If multiple formats are selected, one file is written per selected format per date:

```text
MyVault/Health/2026-05-12.md
MyVault/Health/2026-05-12.json
MyVault/Health/2026-05-12.csv
MyVault/Health/2026-05-12-bases.md
```

## Write modes

| Mode | Behavior |
|---|---|
| Overwrite | Replace existing files with newly generated health data. |
| Append | Add new export content to the end of an existing file. |
| Update | For Markdown, update Health.md-managed sections while preserving custom content; for non-Markdown formats, overwrite. |

## Tips

- Run a one-day export first to verify the path and content.
- Use **Preview** before exporting a long range.
- Use **Update** for Markdown files you also edit by hand.
- Use **Overwrite** for JSON, CSV, and Obsidian Bases when you want clean regenerated files.
- Include time-series data only when you need individual timestamped samples; it can make files larger.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export button is disabled | Missing permission, folder, format, or quota | Check Health badge, Vault badge, Export Formats, and unlock/free exports. |
| Some dates failed | No HealthKit data or file access issue for those dates | Narrow the range, verify Apple Health data, and retry failed dates. |
| Export stopped mid-range | Export was cancelled | Tap Export again for the remaining dates. |
| Existing content disappeared | Overwrite mode replaced the file | Use **Update** for hand-edited Markdown files. |
| No file was written | No health data or no formats selected | Select formats and verify Health data exists for the date. |

## Video outline

- **Suggested title:** Export Apple Health to Markdown Manually
- **Hook:** “One tap turns a date range of Apple Health data into files you own.”
- **Demo flow:**
  1. Show Health and Vault connected.
  2. Choose yesterday as the date range.
  3. Pick a few metrics and Markdown.
  4. Show output path preview.
  5. Tap Preview, then Export.
  6. Open the generated file in Files or Obsidian.
  7. Repeat with a multi-day range.
- **Key screenshot/recording moments:** date range controls, export formats, path preview, progress bar, success message, generated file.
- **CTA / next video:** “Next, we’ll preview an export before writing anything.”

## Implementation notes

- Manual export uses `ExportOrchestrator.exportDates(...)` with an inclusive date array from `dateRange(from:to:)`.
- Each date fetches HealthKit data through `healthKitManager.fetchHealthData(for:includeGranularData:)`.
- `VaultManager.exportHealthData(...)` writes each selected format and records a user-facing status message.
- `ExportResult` tracks successes, failures, cancellation, formats per date, and total files written.
- Markdown side effects run once per date when Markdown is selected.
