# Export Preview

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `app/src/main/java/com/healthmd/presentation/export/ExportScreen.kt` (`ExportPreviewDialog`, `ExportPreviewFileList`), `ExportPreviewDisplayContent.kt`, `ExportViewModel.kt`

## What it does

Preview builds the exact files your export would write — without writing anything — and shows them in a dialog: a summary of requested days, formats, total size, and destination; per-day file lists with format and byte size; and a tap-through file viewer with the actual content. Problems surface before you spend a run: per-day warnings, failure reasons, and a clear no-data state.

## Who it is for

- Anyone verifying formats, filenames, and folder layout before writing.
- Free-plan users confirming a big batch looks right before spending one of 10 actions.
- Not needed for routine re-exports once your configuration is settled.

## Where to find it

1. Open Health.md → **Export** tab.
2. Configure range, target, and formats as usual.
3. Tap **Preview** — the "Export Preview" dialog builds and displays.

## Prerequisites

- Same as a real export: permissions, destination, and at least one format.
- Nothing is written to your folder and no free action is consumed by previewing.

## Setup

1. Tap **Preview**.
2. Read the summary card (days × formats, total files, total bytes, destination).
3. Tap any file row to view its content; use the back button inside the dialog to return to the list.
4. Tap **Export** to run for real, or **Done** to close.

## Example output

```text
Export Preview
Requested days: 3 · Formats per day: 2
6 files · 48.2 KB → My Vault

2026-05-12
  2026-05-12.md        Markdown · 6.1 KB
  2026-05-12.json      JSON · 10.1 KB
```

## Tips

- Large ranges preview only a bounded number of days; the dialog tells you when the preview is truncated, but the real export still covers the full range.
- Very large file contents are shown head-and-tail with an omitted-bytes marker instead of freezing the UI.
- Days with warnings show a yellow card listing each issue (e.g. a category with no data); failed days show the failure reason with "no exportable file" so you can fix configuration first.
- Range rollup artifacts show as one artifact entry covering the requested dates instead of per-day rows.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "No data to export" | Range has no readable data | Check permissions and pick a range with data |
| A day shows a failure reason | Destination, permission, or provider issue for that day | Read the listed issue; fix and re-preview |
| File content looks cut off | Content intentionally truncated for display | The written file is complete; truncation is preview-only |
| Preview is slow to build | Large range/many formats | Preview bounded days or narrow the range |
| Confirm button says Unlock | Free actions exhausted | Unlock, or reduce the batch (the preview itself cost nothing) |

## Video outline

- **Suggested title:** See Exactly What Health.md Will Write — Before It Writes It
- **Hook:** "Preview is free. Typos aren't."
- **Demo flow:**
  1. Configure a 3-day Markdown + JSON export.
  2. Preview; walk the summary card.
  3. Open one file's content, then Export from the dialog.
- **Key screenshot/recording moments:** summary card, file row tap, content viewer with truncation marker.
- **CTA / next video:** ./export-profiles.md.

## Implementation notes

`ExportViewModel.buildPreview()` renders the planned output into memory; `ExportPreviewDialog` (in `ExportScreen.kt`) shows a loading state ("Building preview…") with cancel, the summary card (`PreviewSummaryCard`: requested days, formats per day, destination, artifact/file count, total bytes), and `ExportPreviewFileList`. `PreviewFileDetails` carries head/tail content plus `previewOmittedByteCount` for bounded display of large files. Per-day `ExportPreviewIssue`s localize into warnings (`export_preview_warning_title`) or failure reasons; range-artifact mode (`isRangeArtifact`) collapses the list to artifact entries. Truncation of previewed days is disclosed via the `export_preview_limited_days` plural. The confirm button flips to Unlock (`hitExportLimit`) when the free quota is exhausted — but preview never consumes an action (`ExportAccountingPolicy` counts only successful user-triggered exports). Display logic is unit-tested in `ExportPreviewDisplayContentTest.kt`.
