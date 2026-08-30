# Filename templates

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `domain/model/ExportSettings.kt`, `presentation/export/ExportConfigurationSection.kt`

## What it does

Controls the name of every exported file with date placeholders. The default is simply `{date}`, producing `2026-05-12.md`. Compose placeholders with fixed text to build names like `health-{year}-{month}.md` or `{year}_Q{quarter}`.

## Who it is for

- Anyone organizing exports by naming convention instead of (or alongside) subfolders.
- Users of scripts or Obsidian plugins that expect specific filename patterns.

## Where to find it

1. Open the **Export** tab.
2. Edit the **Filename Template** field in the export configuration section.

The template applies to every format in a [multi-format export](./multi-format-export.md) run; the correct extension is appended per format.

## Prerequisites

- A folder selected through the Android folder picker.
- Nothing else — the template is plain text with placeholders.

## Setup

1. Type your template, mixing fixed text and placeholders.
2. Preview an export to see the resolved names.
3. Export.

## Placeholders

| Placeholder | Becomes | Example (May 12, 2026) |
|---|---|---|
| `{date}` | `yyyy-MM-dd` | `2026-05-12` |
| `{year}` | `yyyy` | `2026` |
| `{month}` | `MM` | `05` |
| `{day}` | `dd` | `12` |
| `{weekday}` | Weekday name (device locale) | `Tuesday` |
| `{monthName}` | Month name (device locale) | `May` |
| `{quarter}` | `Q1`–`Q4` | `Q2` |

## Example output

Template `health-{year}-{month}-{day}` on May 12, 2026:

```text
Health/
├── health-2026-05-12.md
├── health-2026-05-12-bases.md
└── health-2026-05-12.json
```

## Tips

- `{weekday}` and `{monthName}` follow your device locale — switch to fixed `{year}-{month}-{day}` if you need locale-independent names.
- When Markdown and Obsidian Bases are both enabled, the Bases file keeps your template and gains a `-bases` suffix before the extension.
- Filenames and [folder organization](./folder-organization.md) use the same placeholder set, so you can mirror the two.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Literal `{date}` in the filename | Typo in the placeholder | Use exactly `{date}` with braces |
| Files overwrite each other | Template has no date placeholder (for example fixed text only) | Include `{date}` or `{day}` so each day is unique |
| Names show unexpected language | `{weekday}`/`{monthName}` use device locale | Use numeric placeholders instead |

## Video outline

- **Suggested title:** Name Your Health Files Exactly How You Want
- **Hook:** "Your naming convention, your rules."
- **Demo flow:**
  1. Show the default `{date}` output.
  2. Change to `health-{year}-{month}-{day}`.
  3. Preview and export.
- **Key screenshot/recording moments:** template field, file manager with renamed files.
- **CTA / next video:** [Folder organization](./folder-organization.md).

## Implementation notes

`ExportSettings.applyDatePlaceholders` performs literal sequential replacement for the seven placeholders above; unknown text is left untouched. `formatFilename(date)` resolves the template per exported day, and `aggregateRelativePath` combines subfolder + folder structure + resolved filename + per-format extension. Quarter is computed as `(monthValue - 1) / 3 + 1`. The default template constant is `{date}`.
