# Export Preview

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Preview
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Views/ExportPreviewView.swift`, `HealthMd/Shared/Managers/ExportOrchestrator.swift`

## What it does

Export Preview shows a dry run of what Health.md would write for the current date range, export target, and export settings. It lists the active destination, generated filenames, folder paths, formats, roll-up summary files, approximate file sizes, and rendered file contents without writing anything to disk.

Preview is for shape and confidence, not a full census of every date in a large range. It renders a limited number of recent days with data so the screen stays fast.

## Who it is for

- Users checking filenames and folder paths before exporting.
- Users comparing Markdown, JSON, CSV, and Obsidian Bases output.
- Users testing format customization and metric selection.
- Users about to run a large backfill.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Configure date range, metrics, formats, and output settings.
4. Choose **iPhone Folder** or **Connected Mac** as the target.
5. Tap **Preview** in the bottom export bar.
5. Tap a listed file to inspect its rendered contents.

## Prerequisites

- HealthKit permission granted.
- At least one export format selected.
- Health data available for at least one date in the selected range.
- A folder selection is useful for local iPhone path preview; Connected Mac preview can still show the Mac destination when the Mac reports readiness. Preview itself does not write files.

## Setup

1. Set the same options you plan to use for the real export.
2. Tap **Preview**.
3. Review the summary: date count, formats per day, enabled roll-up periods, and destination.
4. Review the **Roll-up summaries** section when weekly/monthly/yearly roll-ups are enabled.
5. Review any side effects, such as daily-note injection or individual entry files.
6. Open each file row to inspect content.
7. Tap **Done**.
8. Adjust settings or tap **Export**.

## Example preview

```text
Date range: 7 days
Formats per day: 3
Destination: Mac: MyVault

Roll-up summaries
MyVault/Health/Rollups/Weekly/2026-W20.md          Weekly Roll-up · Markdown · 9.4 KB
MyVault/Health/Rollups/Weekly/2026-W20.json        Weekly Roll-up · JSON · 7.1 KB
MyVault/Health/Rollups/Monthly/2026-05.md          Monthly Roll-up · Markdown · 9.4 KB
MyVault/Health/Rollups/Yearly/2026.md              Yearly Roll-up · Markdown · 9.4 KB

Tue, May 12, 2026
MyVault/Health/2026-05-12.md      Markdown · 4.2 KB
Health/2026-05-12.csv             CSV · 1.8 KB
Health/2026-05-12.json            JSON · 7.6 KB
```

If both Markdown and Obsidian Bases are enabled, the Bases file uses a suffix to avoid colliding with the Markdown file:

```text
2026-05-12.md
2026-05-12-bases.md
```

## Preview limits

Export Preview currently:

- renders up to 5 dates;
- attempts to fetch up to 14 recent dates from the selected range;
- walks newest to oldest;
- skips dates with no health data;
- does not write files or send Mac export jobs;
- renders weekly/monthly/yearly roll-up summary files for the previewed days when roll-up periods are enabled; full exports refresh the complete touched roll-up windows;
- hints at daily-note injection and individual entry tracking instead of rendering every side-effect file.

The full export still runs on every selected date and queries the complete touched roll-up windows when roll-up summaries are enabled.

## Tips

- Use Preview after changing filename, folder organization, or export target settings.
- Tap into a file row to verify frontmatter and field names.
- Preview multiple formats together to decide which ones you actually need.
- If Preview is empty, try a date you know has Apple Health data before changing export settings.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Preview button is disabled | HealthKit is not authorized or no format is selected | Grant Health access and select at least one format. |
| Preview says no data | Selected dates have no readable HealthKit data | Pick a recent date with known Apple Health data. |
| Only a few days are shown | Preview intentionally caps rendered dates | Run the export to process the full range. |
| Daily note content is not shown | Side effects are summarized, not fully rendered | Check the **Also writes** section and run a small test export. |
| File path looks wrong | Export target, subfolder, folder organization, or filename template is wrong | Adjust the target or **Export → Output** and reopen Preview. |

## Video outline

- **Suggested title:** Preview Health.md Exports Before Writing Files
- **Hook:** “Before you export a month of health data, preview exactly what the files will look like.”
- **Demo flow:**
  1. Configure a one-week date range.
  2. Enable Markdown and JSON.
  3. Switch between iPhone Folder and Connected Mac to show the destination row.
  4. Tap Preview.
  5. Open a Markdown preview and show frontmatter/body.
  6. Open JSON or CSV preview.
  7. Change the filename template and show preview updating.
  8. Export after confirming the output.
- **Key screenshot/recording moments:** Preview button, summary section, file rows, file content view, side-effects section.
- **CTA / next video:** “Next, we’ll customize exactly which metrics appear.”

## Implementation notes

- `ExportTabView` presents `ExportPreviewView` as a sheet.
- Preview calls the same HealthKit fetch path as export, using `includeGranularData` from settings.
- `ExportPreviewView.buildPreviews()` uses `ExportOrchestrator.dateRange(from:to:)`, then walks dates in reverse.
- `maxRenderedDates` is 5 and `maxFetchAttempts` is 14.
- File content is generated with `healthData.export(format:settings:)`, the same renderer used by real exports.
- Roll-up preview content is generated by `HealthRollupExporter.makeSummaries(from:settings:)` and `HealthRollupExporter.outputTargets(for:healthSubfolder:settings:)` from the previewed daily snapshots.
