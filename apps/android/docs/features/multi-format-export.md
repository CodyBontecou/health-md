# Multi-format export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `domain/model/ExportFormat.kt`, `domain/model/ExportSettings.kt`, `presentation/export/ExportConfigurationSection.kt`, `presentation/export/ExportProfileEditorDialog.kt`

## What it does

Pick any combination of Markdown, Obsidian Bases, JSON, and CSV, and one export action writes every selected format for every day in your range. Selecting all four formats for a week still counts as **one export action** — the free counter tracks actions, not files.

## Who it is for

- Obsidian users who want readable Markdown daily notes *and* queryable Bases in the same run.
- Anyone feeding the Health.md Obsidian plugin (JSON) while keeping a human-readable Markdown journal.
- Spreadsheet users who want CSV without giving up the other formats.

## Where to find it

1. Open Health.md and go to the **Export** tab.
2. In the **Export Format** section, tap each format you want: **Markdown**, **Obsidian Bases**, **JSON**, **CSV**.
3. Choose your date range and run the export (or preview first).

The same multi-format selection is available inside each saved export profile.

## Prerequisites

- Health Connect permission granted for the categories you want to export.
- A folder (or other destination) selected through the Android folder picker.
- At least one format selected — export and preview block with a clear state while the selection is empty.

## Setup

1. Enable each format card you want in **Export Format**.
2. Tap preview to confirm the output looks right.
3. Export once; every enabled format lands in your destination.

## Example output

One export of May 12 with Markdown + Bases + JSON + CSV enabled:

```text
Health/
├── 2026-05-12.md           ← Markdown
├── 2026-05-12-bases.md     ← Obsidian Bases (auto-suffixed to avoid collisions)
├── 2026-05-12.json         ← JSON
└── 2026-05-12.csv          ← CSV
```

When Markdown and Obsidian Bases are both selected, the Bases file automatically gets a `-bases` suffix because both formats use the `.md` extension.

## Tips

- Preview checks all selected formats at once — use it before your first real export.
- Bases files are frontmatter-only; see [Obsidian Bases export](./obsidian-bases.md) for what lands inside.
- Changing formats for a recurring run? Save it as an [export profile](./export-profiles.md) so the combination is one tap.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "No formats selected" when exporting | Every format card was toggled off | Enable at least one format in **Export Format** |
| Only Markdown appeared | Other formats not toggled on for this profile | Check the format cards on the Export tab (profiles keep their own selection) |
| Two `.md` files per day and one looks empty | One is the Bases file; it contains only YAML frontmatter | Expected — Bases notes are query-only, open them in a database view |

## Video outline

- **Suggested title:** Every Format at Once: Markdown, Bases, JSON, and CSV in One Tap
- **Hook:** "One export action. Four file types. Zero extra taps."
- **Demo flow:**
  1. Enable all four format cards.
  2. Preview the same day as Markdown and JSON.
  3. Export a week and show the folder.
- **Key screenshot/recording moments:** format card row, the `-bases.md` suffix in a file manager, preview format switcher.
- **CTA / next video:** [Markdown export](./markdown-export.md) deep dive.

## Implementation notes

Formats are a `Set<ExportFormat>` (`MARKDOWN`, `OBSIDIAN_BASES`, `JSON`, `CSV`) on `ExportSettings`; an empty set is allowed while editing and blocked at export/preview time. The `-bases` suffix rule lives in `ExportSettings.aggregateRelativePath` and applies only when Markdown is also selected. Free-tier accounting counts actions, not files, per Google Play Billing policy (`domain/billing/`). Each exporter (`MarkdownExporter`, `ObsidianBasesExporter`, `JsonExporter`, `CsvExporter`) renders from the same `HealthData` model, so a multi-format run performs one Health Connect read and writes N files.
