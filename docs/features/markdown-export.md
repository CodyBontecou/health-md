# Markdown Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Export Formats; Export → Format Customization → Markdown Template
- **Source files:** `HealthMd/Shared/Export/MarkdownExporter.swift`, `HealthMd/iOS/Views/FormatCustomizationView.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Markdown export writes one human-readable `.md` health note per exported date. Each note can include YAML frontmatter, a title, an optional summary line, and grouped sections for Sleep, Activity, Heart, Vitals, Body, Nutrition, Mindfulness, Mobility, Hearing, Workouts, and other enabled Apple Health categories.

Sleep is assigned to the night that starts on the exported date. For example, exporting `2026-06-11` includes daytime data from `2026-06-11` and sleep from the evening of `2026-06-11` through the morning of `2026-06-12`.

This is the default Health.md format and the best choice for reading health data in Obsidian, Files, or any Markdown app.

## Who it is for

- Obsidian users who want readable daily health notes.
- Users who want health summaries they can edit by hand.
- Users who want Markdown plus optional Daily Note Injection or individual entry tracking.

Use JSON or CSV instead when another tool needs structured machine-readable data.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. In **Export Formats**, enable **Markdown**.
4. Optional: open **Format Customization → Markdown Template**.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- At least one health metric enabled under **Health Metrics**.
- **Markdown** selected in Export Formats.

## Setup

1. Enable **Markdown** in **Export Formats**.
2. Decide whether **Include Metadata** should add frontmatter.
3. Open **Format Customization** to choose date/time formats and units.
4. Open **Markdown Template** to set header level, bullet style, emoji headers, and summary behavior.
5. Choose filename and folder settings on the Export screen.
6. Export one date or a date range.

## Example output

```markdown
---
date: 2026-05-12
type: health-data
---

# Health Data — 2026-05-12

7h 30m sleep · 8,432 steps · 1 workout

## Sleep

- **Total:** 7h 30m
- **Bedtime:** 23:15
- **Wake:** 06:45

## Activity

- **Steps:** 8,432
- **Active Calories:** 420 kcal
```

Example path:

```text
MyVault/Health/2026-05-12.md
```

## Tips

- Use **Update** write mode if you add your own Markdown sections and want Health.md to refresh only app-managed sections.
- Use **Frontmatter Fields** when you want Markdown notes to also work with Obsidian properties.
- Turn off emoji headers if you prefer cleaner section names for search and automation.
- Keep Markdown selected if you want Daily Note Injection or individual entry files.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No `.md` file was written | Markdown format is disabled | Enable **Markdown** in Export Formats. |
| File is empty or missing sections | No data or metric disabled for that date | Check Apple Health data and enabled Health Metrics. |
| Custom writing disappeared | Write mode was Overwrite | Use **Update** for editable Markdown files. |
| Sections duplicated | Write mode was Append | Use **Update** instead of Append for repeat exports. |
| Units look wrong | Unit preference set differently than expected | Change **Format Customization → Units** and re-export. |

## Video outline

- **Suggested title:** Export Apple Health to Markdown with Health.md
- **Hook:** “Turn yesterday’s Apple Health data into a readable Obsidian note.”
- **Demo flow:**
  1. Enable Markdown export.
  2. Pick a vault and date.
  3. Show Format Customization basics.
  4. Export and open the generated note.
  5. Re-export with Update mode after adding a custom section.
- **Key screenshot/recording moments:** Export Formats, Markdown Template preview, generated `.md` file, Update mode behavior.
- **CTA / next video:** “Next, we’ll customize the Markdown template.”

## Implementation notes

- `HealthData.toMarkdown(...)` renders Markdown from `ExportDataSnapshot`.
- Frontmatter is included when `AdvancedExportSettings.includeMetadata` is true.
- Markdown sections are rendered only for categories with data or enabled category data.
- `VaultManager.writeOneFormat(...)` writes the file and applies write mode.
- `.update` uses `MarkdownMerger.merge(existing:new:)` only for Markdown files.
