# Metric Selection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics
- **Source files:** `HealthMd/iOS/Views/MetricSelectionView.swift`, `HealthMd/Shared/Models/HealthMetrics.swift`, `HealthMd/Shared/Managers/HealthKitRecordCatalog.swift`

## What it does

Metric Selection controls which Apple Health concepts appear in summaries and which source-record queries run when **Lossless Health Records** is on. Health permission and metric selection are separate: Apple controls what Health.md may read; Health.md controls what it requests/exports.

The current catalog contains 225+ definitions across 21 categories, including ordinary quantities/categories, reproductive/pregnancy data, specialized records, clinical documents, vision, medications, workouts, and WorkoutKit plans. Runtime OS/API availability still applies. The exact source-generated list is published in the [export reference metric catalog](../reference/data-dictionary-and-rollups.md#metric-catalog).

## Setup

1. Open **Export → Health Metrics**.
2. Enable standard metrics broadly or expand/search for individual metrics.
3. Explicitly opt into categories with separate access flows.
4. Preview/export and inspect `raw_capture_status` plus the query manifest.

## Categories

Sleep, Activity, Heart, Respiratory, Vitals, Body Measurements, Mobility, Cycling, Nutrition, Vitamins, Minerals, Hearing, Mindfulness, Reproductive Health, Symptoms, Clinical Records, Clinical Documents, Vision, Medications, Other, and Workouts.

Some definitions are **archive-only**: they produce exact canonical JSON/CSV records and diagnostics but may not add a daily summary field. Markdown/Bases can therefore show counts/status without displaying each selected source object.

## Dependencies and attribution

Some selected metrics require related object types:

- blood pressure includes correlation plus systolic/diastolic components;
- food includes nutrient components;
- Workouts includes routes, associated samples, activities/statistics, effort relationships, and plans;
- Stand Time keeps Apple Stand Hour only as a compatibility dependency, while Stand Hours remains a separate metric.

Canonical records label direct and dependency metric attribution. Selecting one metric does not falsely claim every related object was selected directly, and disabled metrics are removed without using unrelated records as dependency bridges.

## Special access

Standard “select all” excludes separate-access categories:

- Medications use Apple's per-medication selector (iOS 26+).
- Vision prescriptions use Apple's per-object selector on supported runtimes.
- CDA/verifiable clinical records use user-selection queries and may be cancelled.
- WorkoutKit schedules use a separate read-only capability path without ordinary HealthKit authorization.

Unsupported APIs appear `unsupported`; intentionally unavailable/ungranted special flows appear `skipped`. They are not reported as a false successful-empty query.

## Tips

- Start with standard metrics, then opt into sensitive/special categories deliberately.
- Use archive-only metrics with JSON/CSV.
- Keep the metric set small for Bases, while retaining JSON for source-complete history.
- If a selected type returns no records, inspect query status; HealthKit read denial may look successfully empty.
- Corrected schema-v6 micronutrient units come from production catalogs: summary/dictionary fields use `µg` versus `mg`, while canonical HealthKit quantity payloads preserve reviewed source units such as `mcg`.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Metric absent | Disabled/unavailable/no readable data | Enable it, check OS and Health access. |
| Selected metric has no summary key | It is archive-only | Read JSON/CSV canonical records. |
| Medication/Vision cannot enable | Runtime unsupported or selector not completed | Use the category's separate access action. |
| Clinical selection is cancelled | User-selection query was dismissed | Retry intentionally; manifest remains cancelled/partial. |
| Query says skipped/unsupported | Separate access/capability unavailable | Treat as incomplete requested capture, not empty success. |
| Related child appears | It is a required dependency | Inspect `metric_attribution` to distinguish direct/dependency. |

## Video outline

- **Suggested title:** Choose Summary Metrics and Exact HealthKit Records
- **Hook:** “Selection now controls both readable summaries and the complete public record graph.”
- **Demo flow:** choose standard/archive-only/special metrics, inspect attribution and manifest, then compare Markdown with JSON.

## Implementation notes

- `MetricSelectionState` persists selected metric IDs and excludes separate-access categories from broad defaults.
- `HealthKitRecordCatalog` is the reviewed object-type/unit/dependency/authorization graph.
- `HealthKitManager` filters summaries, records, external identities, relationships, warnings, and manifest entries by selection.
- New installs enable Lossless Health Records separately; the internal setting remains `includeGranularData`.
