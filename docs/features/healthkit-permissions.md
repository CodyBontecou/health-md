# HealthKit Permissions

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding → Health Data Access; Export → Health Metrics
- **Source files:** `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/HealthKitRecordCatalog.swift`, `HealthMd/iOS/Views/MetricSelectionView.swift`

## What it does

HealthKit permission controls which Apple Health values Health.md may read on iPhone. Metric Selection independently controls which summaries and lossless source records Health.md requests/exports.

Health.md uses public HealthKit/WorkoutKit APIs only. Normal local exports do not upload health data to a Health.md server.

## Standard setup

1. During onboarding, tap **Grant Access**.
2. Choose readable categories in Apple's Health sheet.
3. Open **Export → Health Metrics** and choose what to export.
4. Leave **Lossless Health Records** on if you need canonical source records.
5. Revisit Apple Health → Apps → Health.md to adjust ordinary read permissions.

## Permission privacy

For many read types, HealthKit intentionally does not tell an app whether access was denied. A denied read can look like a successful query with zero records. Health.md reports the public result and cannot bypass or reliably distinguish that privacy behavior.

Therefore:

- `success` + `record_count: 0` means the query completed empty from the app's perspective;
- it is not proof the user has no Health data;
- `failure`, `unsupported`, `skipped`, and `cancelled` remain distinct diagnostics;
- partial capture is never labeled complete.

## Separate authorization and capabilities

Some selected data is not covered by onboarding's standard read sheet:

| Data | Behavior |
|---|---|
| Medications | Apple's per-medication selector on iOS 26+; only selected medications are read. |
| Vision prescriptions | Apple's per-object selector on supported runtimes. |
| CDA documents | User-selection query; cancellation is recorded. |
| Verifiable clinical records | User-selection query; no ordinary authorization object type. |
| WorkoutKit schedules | Separate read-only capability path, no ordinary HealthKit prompt. |

These categories are opt-in and excluded from broad Select All/default category enablement. Unsupported runtime APIs are reported `unsupported`; ungranted/unprompted special access is `skipped` rather than successful empty.

Ordinary clinical records, ECG, audiogram, heartbeat series, scored assessments, State of Mind, quantities, categories, correlations, workouts, routes, Activity summaries, and characteristics use their applicable standard/runtime-aware HealthKit paths.

## Source completeness

With Lossless Health Records on, JSON/CSV includes a query manifest showing exact type, operation, interval, status, count, and safe error detail. One failed child query retains successful siblings and marks the archive `partial`.

With the setting off, output is summary-only and explicitly says `raw_capture_status: not_requested`.

## Tips

- Grant only categories you want Health.md to read.
- Opt into medications/vision/documents deliberately.
- Check the manifest instead of inferring permission from a missing field.
- Keep both apps current for Connected Mac capability negotiation.
- Device lock protects HealthKit and can block scheduled/CLI reads until unlocked.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Ordinary metric missing | Permission off, metric off, no data, or read hidden | Check Health app, selection, and manifest. |
| Empty query despite known data | HealthKit may be hiding denied read access | Revisit Apple Health permissions; Health.md cannot distinguish denial. |
| Medication/Vision locked | Unsupported OS or selector incomplete | Use supported OS and complete separate selection. |
| CDA/verifiable query cancelled | Selection sheet dismissed | Retry intentionally; cancellation remains diagnostic. |
| Archive partial | One requested branch failed/skipped/unsupported/cancelled | Inspect manifest and retry recoverable paths. |
| Scheduled export cannot read | Device locked/protected | Unlock and use pending recovery. |

## Video outline

- **Suggested title:** Understand Apple Health Permissions and Empty Results
- **Hook:** “A missing sample can mean no data, no selection, or a privacy-hidden denial.”
- **Demo flow:** ordinary authorization, metric selection, medication/vision/document flows, and manifest outcomes.

## Implementation notes

- `HealthKitRecordCatalog` derives standard authorization from reviewed runtime-available descriptors.
- `HealthKitManager` handles standard, medication, vision, document, verifiable, and WorkoutKit capability paths separately.
- Errors are isolated and safely described without logging clinical content/PHI.
- macOS does not query HealthKit; iPhone prepares local/API/Connected Mac records.
