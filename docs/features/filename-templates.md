# Filename Templates

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Filename Format
- **Source files:** `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Filename templates control the base name Health.md uses for exported files. The default is `{date}`, which creates one file per date, such as `2026-05-12.md`, `2026-05-12.json`, or `2026-05-12.csv`.

Templates support date placeholders so exports can match your vault naming scheme.

## Who it is for

- Obsidian users with custom daily-note naming conventions.
- Users who want filenames that include weekdays or month names.
- Users exporting multiple formats and needing predictable paths.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Find **Filename Format**.
4. Enter a template.

## Prerequisites

- A vault/folder selected.
- At least one export format selected.
- A filename pattern that produces valid filenames in iOS Files.

## Setup

1. Open **Export**.
2. Set **Filename Format** to a template such as `{date}` or `health-{date}`.
3. Export a date.
4. Check the status message or Files app path.
5. Reuse the same template for scheduled exports and Shortcuts.

## Supported placeholders

- `{date}` → `2026-05-12`
- `{year}` → `2026`
- `{month}` → `05`
- `{day}` → `12`
- `{weekday}` → `Tuesday`
- `{monthName}` → `May`
- `{quarter}` → `Q2`

## Example paths

| Filename template | Markdown path |
|---|---|
| `{date}` | `Health/2026-05-12.md` |
| `health-{date}` | `Health/health-2026-05-12.md` |
| `{year}-{month}-{day}-health` | `Health/2026-05-12-health.md` |
| `{weekday}-{date}` | `Health/Tuesday-2026-05-12.md` |

When both Markdown and Obsidian Bases are selected, Bases gets a suffix to avoid collision:

```text
Health/2026-05-12.md
Health/2026-05-12-bases.md
```

## Tips

- Use `{date}` or a template beginning with `{date}` for reliable chronological sorting.
- Avoid slashes in filename templates; use Folder Organization for folders.
- Keep filenames stable if other apps or Shortcuts depend on them.
- Remember that the file extension comes from the export format; do not type `.md`, `.json`, or `.csv` into the template.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Filename includes `{Date}` literally | Placeholders are case-sensitive | Use `{date}` exactly. |
| File was written with double extension | Extension included in template | Remove `.md`, `.json`, or `.csv` from Filename Format. |
| Bases file has `-bases` suffix | Markdown and Bases both selected | This is expected to prevent overwriting. |
| Files are hard to sort | Template starts with weekday or month name | Start with `{date}` or `{year}-{month}-{day}`. |
| Daily note injection target differs | Daily Note Injection has its own filename setting | Configure that screen separately. |

## Video outline

- **Suggested title:** Customize Health.md Export Filenames
- **Hook:** “Your health files should match the way your vault is already organized.”
- **Demo flow:**
  1. Show default `{date}` export.
  2. Try `health-{date}`.
  3. Try a weekday/month-name template.
  4. Enable Markdown + Bases and show `-bases` suffix.
  5. Explain why extensions are automatic.
- **Key screenshot/recording moments:** filename field, export status path, Files app output.
- **CTA / next video:** “Next, we’ll put exports into year and month folders.”

## Implementation notes

- `AdvancedExportSettings.defaultFilenameFormat` is `{date}`.
- `formatFilename(for:)` applies placeholders to the filename template.
- `filename(for:format:)` appends the correct extension for Markdown, Bases, JSON, or CSV.
- Bases gets `-bases` only when both `.markdown` and `.obsidianBases` are selected.
- Placeholder expansion uses fixed date formats and is independent of Format Customization date display settings.
