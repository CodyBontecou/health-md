# Obsidian Bases Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Export Formats; Export → Format Customization → Frontmatter Fields
- **Source files:** `HealthMd/Shared/Export/ObsidianBasesExporter.swift`, `HealthMd/Shared/Export/ExportHelpers.swift`, `HealthMd/iOS/Views/FormatCustomizationView.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Obsidian Bases export writes schema-v6 Apple Health summaries as frontmatter-only Markdown. The body stays empty so each date behaves like a clean database row. Workout presentation fields can include zones, laps, splits, sample/route counts, and metadata.

When **Lossless Health Records** is on, Bases also includes capture status, archive schema, source-record count, query-failure count, and warning count. It intentionally does not add external-record or medication-inventory count properties and does not embed canonical records, route points, clinical payloads, or binary data. Use Markdown for expanded human-readable diagnostics, or JSON/CSV for the authoritative source archive. See [Export formats](../reference/export-formats.md#obsidian-bases) for the complete generated frontmatter and exact reserved-field list.

## Who it is for

- Obsidian users building dashboards with Bases.
- Quantified-self users who want health metrics as properties.
- Users who prefer structured data without Markdown sections.

If you want a readable daily health note, use **Markdown** export. If you want both, select both Markdown and Obsidian Bases in the same export run.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. In **Export Formats**, enable **Obsidian Bases**.
4. Optional: tap **Format Customization → Frontmatter Fields** to choose field names and which properties appear.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- At least one health metric enabled under **Health Metrics**.
- Obsidian Bases available in your Obsidian setup.

## Setup

1. In **Export → Export Formats**, enable **Obsidian Bases**.
2. Optionally keep **Markdown** enabled too. Health.md can write both formats in one export action.
3. Open **Format Customization**.
4. Tap **Frontmatter Fields**.
5. Choose a key style, such as `snake_case` or `camelCase`.
6. Enable/disable individual metric fields.
7. Add any static fields or placeholder fields you want on every export.
8. Export a date range.
9. In Obsidian, create a Base over the exported files and add columns for the health properties you care about.

## File naming behavior

Obsidian Bases files use the `.md` extension because Obsidian reads properties from Markdown frontmatter.

If only **Obsidian Bases** is selected:

```text
Health/2026-05-12.md
```

If **Markdown** and **Obsidian Bases** are both selected, Health.md adds `-bases` to the Bases file to avoid overwriting the human-readable Markdown file:

```text
Health/2026-05-12.md
Health/2026-05-12-bases.md
```

## Example output (abridged)

The complete production-generated frontmatter is [`docs/reference/generated/core/lossless-day-bases.md`](../reference/generated/core/lossless-day-bases.md).

```markdown
---
schema: healthmd.health_data
schema_version: 6
date: 2026-05-12
type: health-data
raw_capture_status: complete
raw_record_count: 842
raw_query_failure_count: 0
raw_integrity_warning_count: 0
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
active_calories: 420
average_heart_rate: 72
exercise_minutes: 45
hrv_ms: 52.3
resting_heart_rate: 58
sleep_total_hours: 7.50
steps: 8432
weight_kg: 72.4
workout_count: 1
workouts: [running]
workout_details:
  - index: 1
    date: 2026-05-12
    time: "07:04"
    datetime: 2026-05-12T07:04:00Z
    type: workout
    source: Health.md
    activity_type: "Running"
    sport: running
    healthkit_activity_type: running
    healthkit_activity_type_raw_value: 37
    duration_sec: 1934
    duration: "32:14"
    distance_km: 5.02
    pace_per_km: "6:25 /km"
    hr_avg: 148
    hr_max: 176
    route_points: 1842
    sample_counts:
      heart_rate: 1840
      cadence: 1799
    splits:
      - split: 1
        distance_km: 1.00
        duration: "6:18"
        pace_per_km: "6:18 /km"
        hr_avg: 141
---
```

There is no Markdown body after the closing `---`.

## Custom fields

In **Format Customization → Frontmatter Fields**, users can configure:

- **Core fields:** date and type field names/values.
- **Key style:** snake_case or camelCase.
- **Metric fields:** enable, disable, or rename individual health properties.
- **Custom static fields:** fixed values included in every export, such as `tags: health`.
- **Placeholder fields:** empty fields for manual entry later, such as `notes:` or `omron_systolic:`.

This makes Bases export useful for hybrid workflows where Health.md fills Apple Health data and the user fills subjective/manual fields afterward.

## Suggested Base views

| Base view | Useful columns | Filter/sort idea |
|---|---|---|
| Daily overview | date, steps, sleep_total_hours, resting_heart_rate, hrv_ms | Sort newest first |
| Sleep log | date, sleep_total_hours, sleep_deep_hours, sleep_rem_hours | Filter where sleep_total_hours exists |
| Activity log | date, steps, active_calories, exercise_minutes, workouts | Sort by steps descending |
| Workout log | date, workout_count, workout_minutes, workout_distance_km, workout_details | Filter where workout_count exists |
| Recovery log | date, hrv_ms, resting_heart_rate, sleep_total_hours | Filter by current month |
| Nutrition log | date, dietary_calories, protein, water, caffeine | Filter where dietary_calories exists |

## Tips

- Use Obsidian Bases export for database views and Markdown export for reading.
- If you select both Markdown and Bases, point your Base at `*-bases.md` files to avoid mixing human-readable notes with database records.
- Keep field names stable once you have built a Base; renaming properties later means updating your Base columns.
- Keep `workout_details` enabled if you want rich per-workout presentation data instead of only aggregate workout summaries.
- Read `raw_capture_status` before treating a date as source-complete.
- Join exact source records from JSON/CSV by UUID; do not expect canonical payloads in Bases.
- Add placeholder fields for metrics that do not come from Apple Health but belong in the same dashboard.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| My Base has no rows | Obsidian is not pointed at the export folder | Check the folder path and Base source/filter. |
| Properties are missing | Metric disabled or field disabled in Frontmatter Fields | Enable the metric and frontmatter field, then re-export. |
| Bases file overwrote Markdown file | Older export or both formats not using suffix logic | Re-export with current Health.md; Bases gets `-bases` when Markdown is also selected. |
| Values look like text, not numbers | Obsidian property inference or custom formatting | Keep numeric fields simple and avoid adding units into renamed numeric fields. |
| Too many columns | Too many metric fields enabled | Disable unused fields in **Frontmatter Fields**. |
| Raw records are missing | Bases intentionally contains summaries and diagnostics only | Export JSON or CSV for canonical records. |
| `raw_capture_status` is `partial` | A selected source query did not complete | Inspect the JSON/CSV manifest before treating the day as complete. |

## Video outline

- **Suggested title:** Use Apple Health Data in Obsidian Bases
- **Hook:** “Obsidian Bases can become a private Apple Health dashboard if your daily metrics are frontmatter properties.”
- **Demo flow:**
  1. Enable Obsidian Bases export in Health.md.
  2. Show Frontmatter Fields and choose a small set: date, steps, sleep, HRV, resting HR.
  3. Export the last 7 days.
  4. Open Obsidian and show the generated `-bases.md` files.
  5. Create a Base table with date, steps, sleep, and HRV.
  6. Sort/filter the Base to show trends.
- **Key screenshot/recording moments:** Export Formats toggles, Frontmatter Fields screen, generated YAML-only file, Obsidian Base table.
- **CTA / next video:** “Next, we’ll customize file names and folder structure so your health vault stays clean.”

## Implementation notes

- `HealthData.toObsidianBases(customization:)` generates frontmatter from `ExportDataSnapshot`.
- The exporter writes schema/date/type fields, enabled summary fields, lossless diagnostic counts, custom fields, and `workout_details` presentation data.
- `VaultManager.writeOneFormat(...)` handles file writing and collision behavior.
- `AdvancedExportSettings.filename(for:format:)` adds the `-bases` suffix only when both `.markdown` and `.obsidianBases` are selected.
