# Multi-Format Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Export Formats
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`, `HealthMd/Shared/Views/ExportPreviewView.swift`

## What it does

Multi-Format Export lets one export action write the same day’s Apple Health data in any combination of Markdown, Obsidian Bases, JSON, and CSV. Health.md writes one file per selected format per date.

Use it when you want human-readable notes, Obsidian database rows, structured data for scripts, and spreadsheet-compatible data from the same export run.

## Who it is for

- Obsidian users who want both readable Markdown and Bases frontmatter records.
- Users who analyze health data in spreadsheets or scripts.
- Users who want a portable backup in more than one format.
- Users testing which format best fits their workflow.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. In **Export Formats**, toggle Markdown, Obsidian Bases, JSON, and/or CSV.
4. Tap **Preview** or **Export**.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected for real exports.
- At least one metric enabled.
- At least one export format selected.
- Health data available for the selected date range.

## Setup

1. Go to **Export → Export Formats**.
2. Enable the formats you want.
3. If Markdown is enabled, optionally choose **Include Frontmatter Metadata** and **Group by Category**.
4. Configure **Format Customization** if you need specific date, unit, time, frontmatter, or Markdown settings.
5. Check **Export Path Preview**. Multiple formats show as a grouped extension list.
6. Tap **Preview** to inspect each format.
7. Tap **Export**.

## Format guide

| Format | Extension | Best for |
|---|---|---|
| Markdown | `.md` | Human-readable Obsidian notes with optional frontmatter and sections. |
| Obsidian Bases | `.md` | Frontmatter-only records for Obsidian Bases tables. |
| JSON | `.json` | Structured data for scripts, analysis, and backups. |
| CSV | `.csv` | Spreadsheet-compatible rows. |

## Filename behavior

For one date with all formats selected:

```text
Health/2026-05-12.md
Health/2026-05-12-bases.md
Health/2026-05-12.json
Health/2026-05-12.csv
```

Obsidian Bases also uses `.md`. When both Markdown and Obsidian Bases are selected, Health.md adds `-bases` to the Bases file so it does not overwrite the readable Markdown file.

For a three-day export with four formats selected, Health.md writes up to 12 files: `3 days × 4 formats`.

## Side effects

Some features only run when Markdown is selected:

- Daily Note Injection.
- Individual Entry Tracking.

These run once per date, not once per format.

## Tips

- Use Markdown + Obsidian Bases when you want both readable notes and database rows.
- Use JSON for downstream scripts and CSV for spreadsheet tools.
- Disable formats you do not use before large backfills to reduce file count.
- Preview multi-format exports to confirm filenames before writing a range.
- Keep filename templates stable if another tool depends on the files.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export says select at least one format | All format toggles are off | Enable Markdown, Obsidian Bases, JSON, or CSV. |
| Bases file has `-bases` suffix | Markdown and Bases are both selected | This is intentional to prevent `.md` filename collision. |
| Daily note injection did not run | Markdown format is not selected | Enable Markdown along with any other formats. |
| Too many files were written | Multiple formats multiplied by multiple dates | Disable unneeded formats or reduce the date range. |
| Non-Markdown update overwrote content | Update mode only merges Markdown | Treat JSON, CSV, and Bases as regenerated outputs. |

## Video outline

- **Suggested title:** Export Apple Health as Markdown, JSON, CSV, and Obsidian Bases
- **Hook:** “One export can create every format your workflow needs.”
- **Demo flow:**
  1. Show Export Formats toggles.
  2. Enable Markdown and Obsidian Bases.
  3. Add JSON and CSV.
  4. Show path preview with multiple extensions.
  5. Open Preview and inspect each format.
  6. Export one date and show all generated files.
- **Key screenshot/recording moments:** format toggles, format description text, path preview, preview file list, generated folder.
- **CTA / next video:** “Next, we’ll automate these same settings with scheduled exports.”

## Implementation notes

- `ExportFormat` cases are `.markdown`, `.obsidianBases`, `.json`, and `.csv`.
- `AdvancedExportSettings.exportFormats` is a set, and exports sort formats by raw value before writing.
- `AdvancedExportSettings.primaryFormat` prefers Markdown when selected for representative previews and single-format paths.
- `AdvancedExportSettings.filename(for:format:)` adds `-bases` only when Markdown and Obsidian Bases are both selected.
- `VaultManager.writeOneFormat(...)` writes each selected format and applies write mode behavior.
