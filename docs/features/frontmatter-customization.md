# Frontmatter Customization

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Format Customization → Frontmatter Fields
- **Source files:** `HealthMd/iOS/Views/FormatCustomizationView.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Export/MarkdownExporter.swift`, `HealthMd/Shared/Export/MarkdownMerger.swift`

## What it does

Frontmatter Customization controls the YAML properties Health.md writes into Markdown and Obsidian Bases files. You can choose key style, rename fields, disable fields, customize `date` and `type`, add static fields, and add empty placeholder fields for manual entry.

This is the main setup screen for Obsidian properties and Bases workflows.

## Who it is for

- Obsidian users building Bases, Dataview, or property-based dashboards.
- Users who want field names like `sleepTotalHours` instead of `sleep_total_hours`.
- Users who want manual fields such as `notes`, `omron_systolic`, or `tags` included on every export.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Tap **Format Customization**.
4. Tap **Frontmatter Fields**.

## Prerequisites

- Markdown or Obsidian Bases export selected.
- Health metrics enabled for fields you expect to appear.
- Obsidian property names chosen before building long-lived Bases views.

## Setup

1. Choose **Key Style**: `snake_case` or `camelCase`.
2. Enable or disable **Include Date Field**.
3. Enable or disable **Include Type Field** and customize its value if needed.
4. Add **Custom Static Fields** for fixed values on every export.
5. Add **Placeholder Fields** for empty values you will fill manually later.
6. Search or expand Health Metric categories.
7. Toggle individual fields and use the pencil button to rename them.
8. Export or re-export files.

## Example output

```markdown
---
date: 2026-05-12
type: health-data
tags: health, daily
notes: 
steps: 8432
active_calories: 420
sleep_total_hours: 7.50
resting_heart_rate: 58
---
```

With camelCase:

```markdown
---
date: 2026-05-12
type: health-data
activeCalories: 420
sleepTotalHours: 7.50
restingHeartRate: 58
---
```

## Tips

- Pick a key style before creating Obsidian Bases columns.
- Disable fields you do not use to keep properties readable.
- Use static fields for tags or source labels.
- Use placeholder fields for manual measurements that Apple Health does not provide.
- Avoid putting units in numeric field values if you want Obsidian to treat them as numbers.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| A frontmatter field is missing | Field disabled or metric has no data | Enable the field and metric, then re-export. |
| Obsidian Base column broke after rename | Property key changed | Update the Base column/filter or rename the field back. |
| Custom field appears on every file | It was added as a static field | Delete it from Custom Static Fields if not desired. |
| Placeholder is blank | Placeholder fields are intentionally empty | Fill it manually in Obsidian after export. |
| Daily note field names changed | Daily Note Injection respects Frontmatter Fields | Keep field names stable for daily-note workflows. |

## Video outline

- **Suggested title:** Customize Health.md Frontmatter for Obsidian Properties
- **Hook:** “Your Apple Health data becomes much more useful when every metric is an Obsidian property.”
- **Demo flow:**
  1. Open Frontmatter Fields.
  2. Switch snake_case to camelCase and back.
  3. Rename a field and disable unused fields.
  4. Add `tags` as a static field and `notes` as a placeholder.
  5. Export and show the YAML in Obsidian.
- **Key screenshot/recording moments:** key style picker, field rename alert, generated frontmatter, Obsidian properties.
- **CTA / next video:** “Next, we’ll use those fields in Obsidian Bases.”

## Implementation notes

- `FrontmatterConfiguration` stores enabled fields, custom keys, static fields, placeholders, core date/type settings, and key style.
- Default fields are grouped by metric category in `FrontmatterCustomizationView`.
- `FrontmatterKeyStyle.apply(to:)` converts snake_case defaults to camelCase.
- Markdown export writes core, static, and placeholder fields when metadata is included.
- `MarkdownMerger.mergeFrontmatter(...)` preserves existing frontmatter order and updates/adds Health.md properties during Update mode.
