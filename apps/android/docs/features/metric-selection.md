# Metric Selection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics
- **Source files:** `app/src/main/java/com/healthmd/presentation/metrics/MetricSelectionScreen.kt`, `domain/model/MetricSelection.kt`

## What it does

Metric Selection controls which of Health.md's 106 selectable Health Connect metrics appear in your exports. Search by name, expand categories, toggle individual metrics, or flip a whole category with its tri-state checkbox. Permission and selection are separate: Health Connect controls what Health.md may read; this screen controls what actually gets exported.

## Who it is for

- Users who want a compact daily note with a handful of metrics.
- Power users enabling everything for JSON/CSV analysis pipelines.
- Not for granting data access — that's Health Connect's permission sheet (see ./health-connect-permissions.md).

## Where to find it

1. Open Health.md → **Export** tab.
2. Open the metrics entry (the header shows your current count, e.g. `106/106`).
3. Search, expand categories, and toggle metrics or whole categories.

## Prerequisites

- Health Connect read permission for any category you enable (unpermitted types export as no data, not errors).

## Setup

1. Use **Select all** / **Deselect all** for a quick baseline.
2. Expand a category and fine-tune with individual checkboxes; the category checkbox shows a dash when partially enabled.
3. Watch the header counter and progress bar as you narrow the set.

## Categories

Sleep, Activity, Heart, Respiratory, Vitals, Body, Nutrition, Mobility, Cycling, Hearing, Mindfulness, Reproductive Health, Symptoms, Medications, Other, and Workouts.

Each metric shows its unit under the name where one applies, so you can see at a glance what will land in your files.

## Example output

With only Sleep and Heart enabled, a daily Markdown note contains those sections; JSON omits the other metrics' keys rather than writing zeros.

## Tips

- Start from Deselect all and add the categories you actually journal about — smaller exports are faster and easier to read.
- Newer record types (skin temperature, mindfulness, planned workouts, activity intensity, medical resources) also require provider support, not just a toggle.
- The count `x/106` counts only selectable metrics; Health.md additionally documents which Apple-only or unsupported concepts it deliberately does not fabricate on Android.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Enabled metric exports nothing | Permission not granted, no source data, or provider lacks the type | Check Health Connect grants and source apps |
| A metric you heard about isn't listed | It's an Apple-only concept or unsupported by your provider | Android omits it rather than substituting a lookalike |
| Search finds nothing | Name doesn't match your search text | Clear the search or try the category expansion instead |
| Count looks stuck | Selection persists per settings | Use Select all/Deselect all to reset deliberately |

## Video outline

- **Suggested title:** Choose Exactly Which Health Metrics You Export
- **Hook:** "106 metrics. You decide which ones matter."
- **Demo flow:**
  1. Open metric selection from the Export tab.
  2. Search "sleep", toggle a few heart metrics.
  3. Show the counter dropping, then export a lean day.
- **Key screenshot/recording moments:** search box, tri-state category checkbox, `12/106` counter.
- **CTA / next video:** ./export-preview.md.

## Implementation notes

`MetricSelectionScreen.kt` renders search (`contains` on localized display names), bulk buttons, a `LinearProgressIndicator`, and per-category `GeistCard` rows with tri-state category checkboxes (`isCategoryFullyEnabled`/`isCategoryPartiallyEnabled`) over a `LazyColumn`. The catalog is `HealthMetrics` in `domain/model/MetricSelection.kt`: `ALL_METRICS` (106 `HealthMetricDefinition`s across the 16 `HealthMetricCategory` values) plus `UNAVAILABLE_METRICS`, which document — with reasons — concepts that are not offered on Android (e.g. Apple-only equivalents); unavailable entries are never fabricated as selectable metrics. Selection state (`MetricSelectionState.enabledMetrics`) persists in settings and feeds every exporter. Category and metric display names localize via `presentation/i18n`. Deliberate difference from Apple: the Apple catalog is far larger (225+ definitions including archive-only and special-access flows); Android's list is exactly what Health Connect's pinned API exposes.
