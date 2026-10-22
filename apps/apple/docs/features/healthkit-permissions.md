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

On OS 27 and later, builds made with a supported OS 27 HealthKit SDK also call HealthKit's [`earliestAuthorizedSampleDate(for:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestauthorizedsampledate(for:)) API after authorization and before resolving an all-available request. An older-SDK binary cannot perform this check merely because it runs on a newer OS. The machine-readable history state is one of:

- `limited_history`: HealthKit returned at least one per-type earliest readable date. Data before each boundary is unknown, not absent. Health.md warns in the export UI and refuses an unqualified **All Time** / `all_available` completeness claim.
- `full_history`: HealthKit returned no limited date boundary for the assessed types. By Apple's privacy design, this still does not prove each read permission was granted; a denied type can also be omitted.
- `unknown`: the boundary check failed or could not cover the requested scope. Health.md rejects `all_available`; an explicit date range remains available.
- `api_unavailable`: the runtime predates OS 27, the app was built without the supported HealthKit SDK API, or the query is local to the Mac companion. Health.md rejects `all_available` because it cannot verify full-history authorization, but continues explicit-range bounded exports with that limitation reported.

The boundary is evaluated against a sample's end date, so a readable sample can begin before its reported boundary. Health.md never interprets the pre-boundary period as zero or missing-by-proof.

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
| All Time/all-available request rejected as limited | OS 27 reports a user-selected earliest readable date for at least one selected type | Grant full history in Apple Health or choose an explicit date range at or after the displayed boundary. |
| All Time/all-available request rejected as unverified | The check failed, did not cover every selected metric, or the API is unavailable | Choose an explicit date range. On supported devices, use OS 27+ and rerun authorization so Health.md can reassess the full selected scope. |
| History state is `api_unavailable` | The runtime or app build cannot call the history-boundary API, or the query is local to Mac | Treat full-history completeness as unverified and use explicit ranges. OS 27 alone is insufficient; the iPhone app must also be built with a supported SDK. |
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
- Native iPhone/iPad **All Time** selection and export admission share `NativeExportDateRangeResolver`. It discovers the earliest date for the selected metrics in the export time zone and requires complete discovery plus a full-history assessment covering that scope. Saved dates, Preview exports, and Connected Mac/API destinations do not bypass the check. Selection changes or cancellation during discovery reject the pending result; explicit ranges do not require this full-history gate. Failed discovery never substitutes Today while retaining the All Time label.
- Errors are isolated and safely described without logging clinical content/PHI.
- macOS does not query HealthKit; iPhone prepares local/API/Connected Mac records.
- The Xcode project's four configurations map the reviewed SDK 27 major family (`SDK_VERSION_MAJOR=270000`) to `HEALTHMD_HAS_HEALTHKIT_HISTORY_AUTHORIZATION`. Both the production adapter and its support flag use that compile-time gate plus OS 27 runtime availability. SDK 26 builds compile without referencing the absent symbol and report `api_unavailable`, never an empty full-history result. Qualify additional SDK families before adding their mapping; do not infer SDK support from the Swift compiler version or override the gate to make an unsupported build pass.
