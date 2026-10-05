# HealthKit Permissions

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding → Health Data Access; Export → Health Metrics
- **Source files:** `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/HealthKitRecordCatalog.swift`, `HealthMd/iOS/Views/MetricSelectionView.swift`

## What it does

HealthKit permission controls which Apple Health values Health.md may read on iPhone. Metric Selection independently controls which summaries and lossless source records Health.md requests/exports.

Health.md uses public HealthKit/WorkoutKit APIs only. Normal local exports do not upload health data to a Health.md server.

> **Current App Store availability:** Clinical Health Records access is temporarily removed. Current builds do not include the `health-records` or `verifiable-health-records` managed entitlements, do not show Apple's clinical-records prompt, and do not offer Clinical Records or Clinical Documents in metric selection. Ordinary Apple Health data remains available.

## Standard setup

1. During onboarding, tap **Grant Access**.
2. Choose readable categories in Apple's Health sheet.
3. Open **Export → Health Metrics** and choose what to export.
4. Leave **Lossless Health Records** on if you need canonical source records.
5. Revisit Apple Health → Apps → Health.md to adjust ordinary read permissions.

## Permission privacy

For many read types, HealthKit intentionally does not tell an app whether access was denied. A denied read can look like a successful query with zero records. Health.md reports the public result and cannot bypass or reliably distinguish that privacy behavior.

The pinned Xcode 26.6 / SDK 26.5 does **not** declare a supported per-type history-authorization boundary API. The native adapter reports `api_unavailable` even on a newer runtime; an OS upgrade alone cannot add an API to this build. Health.md rejects unqualified **All Time** / `all_available` completeness claims and offers explicit date ranges with completeness unverified. It does not substitute the platform's general earliest permitted date, query an earliest sample or treat an empty result as proof of unrestricted access.

The independently versioned history-authorization contract retains these states for compatible sources and synthetic tests; their grammar does not establish native support:

- `limited_history`: a verified source assessment reports a per-type date boundary. Earlier data is unknown, not absent; unqualified completeness is rejected.
- `full_history`: a verified source assessment covers the selected scope without a limited boundary. This still does not prove individual read permissions were granted; privacy-hidden types can be omitted. The current native adapter cannot produce this assessment from HealthKit.
- `unknown`: an assessment failed or did not cover the requested scope. An explicit range remains available without a full-history claim.
- `api_unavailable`: this build/runtime cannot perform the required assessment. This is the current native adapter outcome, not proof of denial or no data.

Retained boundary assessments use sample end dates; a sample can begin before its boundary. Pre-boundary data is never represented as zero or absent-by-proof. Android's independently checked Health Connect historical-read grant is a different permission model, not an equivalent Apple boundary API.

Mac readiness reports `limited_history_detection_supported: false` and authorization `unknown`. Legacy OS-number hints/keys remain for compatibility; they are not feature-support or upgrade instructions. Cached Mac data cannot infer the iPhone's current permissions.

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
| Clinical records and CDA/verifiable documents | Unavailable in current App Store builds; their dormant query paths remain source-gated for a future reviewed release. |
| WorkoutKit schedules | Separate read-only capability path, no ordinary HealthKit prompt. |

Available special categories are opt-in and excluded from broad Select All/default category enablement. Unsupported runtime APIs are reported `unsupported`; ungranted/unprompted special access is `skipped` rather than successful empty.

ECG, audiogram, heartbeat series, scored assessments, State of Mind, quantities, categories, correlations, workouts, routes, Activity summaries, and characteristics use their applicable standard/runtime-aware HealthKit paths.

## Source completeness

With Lossless Health Records on, JSON/CSV includes a query manifest showing exact type, operation, interval, status, count, and safe error detail. One failed child query retains successful siblings and marks the archive `partial`.

When canonical archive capture is off, output says `raw_capture_status: not_requested`. Detailed Time-Series may still retain selected compatibility samples; that status describes only the archive.

## Tips

- When a run reports missing data, the export result sheet explains exactly which requested health types were not authorized (Export Permission Guidance) and names them, so you can fix the gap in Apple Health settings instead of guessing.

- Grant only categories you want Health.md to read.
- Opt into medications and vision prescriptions deliberately.
- Check the manifest instead of inferring permission from a missing field.
- Keep both apps current for Connected Mac capability negotiation.
- Device lock protects HealthKit and can block scheduled/CLI reads until unlocked.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Ordinary metric missing | Permission off, metric off, no data, or read hidden | Check Health app, selection, and manifest. |
| Empty query despite known data | HealthKit may be hiding denied read access | Revisit Apple Health permissions; Health.md cannot distinguish denial. |
| All Time/all-available request rejected as limited | A compatible source assessment reports a limited boundary; current native SDK support is unavailable | Use an explicit range within any verified boundary; do not infer missing earlier data. |
| All Time/all-available request rejected as unverified | The assessment is unavailable, failed or incomplete | Choose an explicit range. An OS upgrade alone does not enable this build's missing boundary API. |
| History state is `api_unavailable` | This build cannot assess per-type authorization boundaries, regardless of runtime version | Use explicit ranges and retain unverified completeness; no permission bypass or inferred full history. |
| Medication/Vision locked | Unsupported OS or selector incomplete | Use supported OS and complete separate selection. |
| Clinical record metric unavailable | Clinical Health Records are omitted from this App Store build | Use an ordinary Apple Health metric; clinical access may return in a future reviewed release. |
| Archive partial | One requested branch failed/skipped/unsupported/cancelled | Inspect manifest and retry recoverable paths. |
| Scheduled export cannot read | Device locked/protected | Unlock and use pending recovery. |

## Video outline

- **Suggested title:** Understand Apple Health Permissions and Empty Results
- **Hook:** “A missing sample can mean no data, no selection, or a privacy-hidden denial.”
- **Demo flow:** ordinary authorization, metric selection, medication/vision/document flows, and manifest outcomes.

## Implementation notes

- `HealthKitRecordCatalog` derives standard authorization from reviewed runtime-available descriptors.
- `HealthKitManager` keeps standard, medication, vision, document, verifiable, and WorkoutKit paths separate; the document/clinical paths are source-gated off in current App Store builds.
- Errors are isolated and safely described without logging clinical content/PHI.
- macOS does not query HealthKit; iPhone prepares local/API/Connected Mac records.
