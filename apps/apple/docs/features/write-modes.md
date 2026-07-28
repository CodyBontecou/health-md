# Write Modes

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Write Mode
- **Source files:** `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`, `HealthMd/Shared/Export/MarkdownMerger.swift`

## What it does

Write Modes control what Health.md does when an export file already exists. The choices are Overwrite, Append, and Update.

This matters when you re-export the same date, run scheduled exports, or edit exported Markdown files by hand.

## Who it is for

- Users who re-export dates after Apple Health data changes.
- Obsidian users who add personal notes to generated Markdown files.
- Users testing templates, filenames, and formats repeatedly.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Find **Write Mode**.
4. Choose **Overwrite**, **Append**, or **Update**.

## Prerequisites

- A vault/folder selected.
- At least one export format selected.
- Existing files only matter when exporting the same path again.

## Setup

1. Choose a date that already has an export file, or export once to create one.
2. Set **Write Mode**:
   - **Overwrite** replaces the file with fresh output.
   - **Append** adds new output to the end of the existing file.
   - **Update** refreshes app-managed Markdown sections while preserving custom Markdown sections.
3. Re-export the same date.
4. Inspect the file to confirm the behavior.

## Mode behavior

| Mode | Markdown | JSON/CSV/Bases |
|---|---|---|
| Overwrite | Replaces the file | Replaces the file |
| Append | Adds another copy of the export to the end | Adds another copy of the export to the end |
| Update | Merges frontmatter and app-managed sections | Falls back to overwrite |

## Example Update behavior

Before re-export:

```markdown
# Health Data — 2026-05-12

## Sleep

- **Total:** 7h 10m

## Journal Notes

Felt tired after travel.
```

After Update:

```markdown
# Health Data — 2026-05-12

## Sleep

- **Total:** 7h 30m

## Journal Notes

Felt tired after travel.
```

Health.md refreshed the Sleep section and preserved the custom Journal Notes section.

## Tips

- Use **Update** for Markdown files you edit in Obsidian.
- Use **Overwrite** for JSON, CSV, and generated-only files.
- Avoid **Append** unless you intentionally want an audit-style repeated log in one file.
- Keep standard section headings if you rely on Update mode.
- Test write mode with one day before running a large date range.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| My custom section disappeared | Mode was Overwrite | Use Update for editable Markdown. |
| File has duplicate health sections | Mode was Append | Switch to Update or Overwrite and clean the file. |
| Update did not merge JSON/CSV | Update is Markdown-only | Use Overwrite for non-Markdown formats. |
| Update created duplicate custom-style sections | Custom headings do not match managed section names | Use headings like Sleep, Activity, Heart, Vitals, etc. |
| Frontmatter fields changed unexpectedly | New export overwrote matching keys | This is expected; Health.md updates app-provided frontmatter values. |

## Video outline

- **Suggested title:** Overwrite, Append, or Update? Health.md Write Modes Explained
- **Hook:** “The right write mode keeps your Obsidian notes safe when you re-export.”
- **Demo flow:**
  1. Export a Markdown file.
  2. Add a custom section in Obsidian.
  3. Re-export with Overwrite and show replacement.
  4. Re-export with Append and show duplication.
  5. Re-export with Update and show preserved custom section.
- **Key screenshot/recording moments:** write-mode picker, before/after Markdown, preserved custom section.
- **CTA / next video:** “Next, we’ll combine Update mode with Daily Note Injection.”

## Implementation notes

- `WriteMode` is defined in `AdvancedExportSettings.swift` with `.overwrite`, `.append`, and `.update`.
- `VaultManager.writeOneFormat(...)` applies write mode when the target file already exists.
- Append concatenates existing content, two newlines, and fresh content.
- Update calls `MarkdownMerger.merge(existing:new:)` only for `.markdown`.
- For non-Markdown formats, Update writes fresh content because there is no heading structure to merge.
