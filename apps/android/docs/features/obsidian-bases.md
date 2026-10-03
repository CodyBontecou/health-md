# Obsidian Bases export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export
- **Source files:** `data/export/ObsidianBasesExporter.kt`, `domain/model/HealthDataFields.kt`

## What it does

Writes frontmatter-only `.md` notes — a single YAML block listing every metric as `key: value`, with no body text. Drop them into an Obsidian **Bases** database view and your health data becomes filterable and sortable like a table.

## Who it is for

- Obsidian Bases users who want to query health data ("all days with deep sleep under 1 hour").
- Anyone building dashboards from frontmatter properties instead of parsing Markdown bodies.

## Where to find it

1. Enable **Obsidian Bases** in **Export Format** on the Export tab.
2. Export; one `-bases.md` file appears per day (when Markdown is also enabled; otherwise plain `.md`).

## Prerequisites

- Health Connect permission for the categories you want exported.
- A folder selected through the Android folder picker — ideally inside your Obsidian vault.
- Obsidian Bases enabled in [multi-format export](./multi-format-export.md).

## Setup

1. Enable the Obsidian Bases format card.
2. Point your export folder at a folder inside your Obsidian vault.
3. In Obsidian, create a Bases view over the folder and add the properties you care about.

## Example output

```markdown
---
date: 2026-05-12
sleep_total_hours: 7.2
sleep_deep_hours: 1.4
steps: 8432
resting_heart_rate: 58
---
```

That is the entire file — everything lives in frontmatter.

## Tips

- Metrics with no data for a day are simply omitted; empty properties never appear.
- Rename keys (for example `steps` → `dailySteps`) in [Frontmatter customization](./frontmatter-customization.md); renames apply here too.
- On the analytical v5 profile the first property is `healthmd_schema_profile: android-analytical-v5`, so Bases views can filter by profile.
- When cloud providers merge into a day, `healthmd_all_connected_*` audit properties record which provider supplied each category and how duplicate workouts were deduplicated.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Bases view shows nothing | Files are outside the vault, or the view's folder filter is wrong | Export into a vault folder and check the Bases filter |
| File looks "empty" | Bases notes have no body by design | View properties via the Properties panel or a Bases table |
| Two `.md` files per day | Markdown + Bases both enabled | Expected; the Bases one carries the `-bases` suffix |

## Video outline

- **Suggested title:** Query Your Health Like a Database: Obsidian Bases
- **Hook:** "Every health metric, one YAML block, infinitely filterable."
- **Demo flow:**
  1. Export a week with Bases enabled.
  2. Open Obsidian and create a Bases view over the folder.
  3. Filter days by `sleep_deep_hours` and sort by `steps`.
- **Key screenshot/recording moments:** the raw `-bases.md` file, a Bases table with filters applied.
- **CTA / next video:** [Frontmatter customization](./frontmatter-customization.md).

## Implementation notes

`ObsidianBasesExporter` builds a single frontmatter block from `HealthDataFields.extract` (the same single source of truth Markdown and daily-note injection use), skipping null values and applying `FrontmatterConfiguration.outputKey` renames. Static custom fields emit sorted; placeholder fields emit blank. Analytical v5 adds the profile marker; all-connected merges append the `healthmd_all_connected_*` audit block. The `-bases` suffix is applied by the export path only when Markdown shares the `.md` extension in the same run (see [multi-format export](./multi-format-export.md)).
