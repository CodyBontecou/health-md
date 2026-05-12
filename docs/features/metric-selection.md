# Metric Selection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics
- **Source files:** `HealthMd/iOS/Views/MetricSelectionView.swift`, `HealthMd/Shared/Models/HealthMetrics.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`

## What it does

Metric Selection controls which Apple Health metrics Health.md includes in exports. Users can enable or disable entire categories, expand categories to toggle individual metrics, search by metric name, and quickly select or deselect everything.

This is separate from iOS HealthKit permission. A metric must be both allowed by Apple Health permissions and enabled in Health.md to appear in exports.

## Who it is for

- Users who want smaller, cleaner health notes.
- Users building Obsidian Bases dashboards with only key columns.
- Users who want to exclude sensitive categories.
- Users troubleshooting missing or noisy export fields.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Tap **Health Metrics**.
4. Expand categories or use search to find a metric.

## Prerequisites

- HealthKit permission granted for the relevant data types.
- Export formats configured.
- Apple Health data available for the selected metrics and dates.

## Setup

1. Open **Export → Health Metrics**.
2. Review the summary header showing enabled metrics and categories.
3. Use **Enable All Metrics** or the menu’s **Select All** / **Deselect All** for broad changes.
4. Tap a category row to expand it.
5. Use the category toggle to enable or disable all metrics in that category.
6. Use individual toggles for specific metrics.
7. Use search when you know the metric name.
8. Return to Export and run Preview or Export.

## Available categories

Health.md organizes metrics into categories including:

- Sleep
- Activity
- Heart
- Respiratory
- Vitals
- Body Measurements
- Mobility
- Cycling
- Nutrition
- Vitamins
- Minerals
- Hearing
- Mindfulness
- Reproductive Health
- Symptoms
- Other
- Workouts

Medication tracking is shown as pending Apple permission and cannot be enabled yet.

## Example output impact

If you disable all Nutrition metrics, dietary fields are omitted from Markdown, Obsidian Bases, JSON, and CSV exports.

If you enable only steps, sleep total, resting heart rate, HRV, and workouts, a compact frontmatter export might look like:

```markdown
---
date: 2026-05-12
type: health-data
steps: 8432
sleep_total_hours: 7.50
resting_heart_rate: 58
hrv_ms: 52.3
workouts_count: 1
---
```

## Tips

- Start with all metrics enabled, export one day, then remove what you do not need.
- For Obsidian Bases, keep the metric set small so your table stays readable.
- Use search for specific terms like “HRV,” “Water,” “Weight,” or “Sleep.”
- Category toggles are useful for excluding whole domains like Nutrition or Symptoms.
- If a metric is enabled but blank, check Apple Health permissions and whether the data exists for that day.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Metric does not appear in export | Metric disabled in Health Metrics | Enable the metric or its category. |
| Metric is enabled but still missing | HealthKit permission is off or no data exists | Check Apple Health → Apps → Health.md and the Health app data. |
| Medication category is locked | Apple special permission is pending | Wait for support; it cannot be toggled on yet. |
| Too many fields in Obsidian | Too many metrics enabled | Deselect categories or individual metrics you do not query. |
| Category shows partial state | Some but not all metrics in the category are enabled | Expand the category to inspect individual toggles. |

## Video outline

- **Suggested title:** Choose Exactly Which Apple Health Metrics Export to Obsidian
- **Hook:** “You do not need every Apple Health field in your vault.”
- **Demo flow:**
  1. Open Export → Health Metrics.
  2. Show total enabled count.
  3. Search for HRV and toggle it.
  4. Disable an entire category.
  5. Use Select All / Deselect All.
  6. Preview the resulting file.
- **Key screenshot/recording moments:** summary header, search bar, expanded category, partial category toggle, generated frontmatter.
- **CTA / next video:** “Next, we’ll export the same selected metrics in multiple formats.”

## Implementation notes

- `MetricSelectionView` binds to `AdvancedExportSettings.metricSelection`.
- `MetricSelectionState` defaults to all non-pending metrics enabled.
- Saved metric state is persisted through `AdvancedExportSettings`.
- Legacy `DataTypeSelection` is migration-only; runtime export filtering uses `MetricSelectionState`.
- Pending-approval categories and metrics are blocked in both UI and decoded saved state.
