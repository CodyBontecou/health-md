# Metric Selection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics
- **Source files:** `HealthMd/iOS/Views/MetricSelectionView.swift`, `HealthMd/Shared/Models/HealthMetrics.swift`, `HealthMd/Shared/Managers/HealthKitRecordCatalog.swift`

## What it does

Metric Selection controls which Apple Health concepts appear in summaries and which source-record queries run when **Lossless Health Records** is on. When Connected Apps is enabled, it also controls which WHOOP API data groups are fetched and exported. Authorization and export selection are separate: Apple/WHOOP control what Health.md may read; Health.md controls what it requests/exports.

The current catalog contains 225+ definitions across 21 categories, including ordinary quantities/categories, reproductive/pregnancy data, specialized records, clinical documents, vision, medications, workouts, and WorkoutKit plans. Runtime OS/API availability still applies. The exact source-generated list is published in the [export reference metric catalog](../reference/data-dictionary-and-rollups.md#metric-catalog).

## Setup

1. Open **Export → Health Metrics**.
2. Enable standard metrics broadly or expand/search for individual metrics.
3. Explicitly opt into categories with separate access flows.
4. Preview/export and inspect `raw_capture_status` plus the query manifest.

## Categories

Sleep, Activity, Heart, Respiratory, Vitals, Body Measurements, Mobility, Cycling, Nutrition, Vitamins, Minerals, Hearing, Mindfulness, Reproductive Health, Symptoms, Clinical Records, Clinical Documents, Vision, Medications, Other, and Workouts.

Some definitions are **archive-only**: they produce exact canonical JSON/CSV records and diagnostics but may not add a daily summary field. Markdown/Bases can therefore show counts/status without displaying each selected source object.

## WHOOP selection

The WHOOP section has independent switches for **Cycles & Strain**, **Recovery**, **Sleep**, **Workouts**, and **Body Measurements**, plus **All WHOOP Data**. Search matches group names and descriptions, including HRV, naps, and heart rate zones. Connect the account in **Settings → Connected Apps**; selecting data does not grant provider permission.

These are whole API-resource selections, not individual-field switches. For example, Recovery includes its score, HRV RMSSD, resting heart rate, blood oxygen, and skin temperature. This preserves native response fidelity without pretending that a native sidecar was field-redacted. IDs relating a selected record to an unselected cycle/sleep remain in that record; the unselected resource's measurements are not fetched.

- Choices are independent of Apple Health category/bulk actions and protected by **Prevent Accidental Changes**.
- Selections persist per export profile and are frozen in scheduled, API, Connected Mac, and generated-file/recovery settings. Export preview uses the same selection.
- Shared Setup does not carry WHOOP resource-selection authority. Imports retain local preferences; v2 Add/Replace seeds imported profiles from the receiver's active profile, so an all-off preference is not silently re-enabled.
- Disabled groups are neither queried nor included in typed daily output or provider-native sidecars. All off skips WHOOP reads and token refresh without disconnecting the account.
- New and older configurations default to all groups enabled, preserving prior connected-account behavior. An explicitly saved empty selection remains empty after restart/recovery.
- Body Measurements remains a current-day profile snapshot, never historical measurements. Existing files are not deleted by changing selection.
- Apple Health counts and standard-metric bulk actions remain Apple-only; WHOOP has its own group count and master switch.

The controls currently ship on iPhone when the WHOOP rollout is enabled. Android Play resource-selection parity is **planned**: expose these five resource IDs in Health Metrics, freeze them per profile/job, and apply them before compatibility reads and Raw API Snapshot endpoint planning without changing the frozen Android daily profiles. Android's existing metric-to-endpoint raw-snapshot selection is not claimed as the same control.

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
- Schema-v8 micronutrient units retain the v7 corrections come from production catalogs: summary/dictionary fields use `µg` versus `mg`, while canonical HealthKit quantity payloads preserve reviewed source units such as `mcg`.

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
- Data Detail is independent from metric selection. Durable settings use `compatibilityDetail` and `healthKitSourceArchivePolicy`; `includeGranularData` remains only a legacy migration bridge.
