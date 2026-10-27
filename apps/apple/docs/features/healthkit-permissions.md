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

On OS 27 and later, the supported HealthKit API can report an earliest authorized sample end date for selected types. A reported date describes a boundary; an omitted entry does not prove unrestricted access and can also occur for denied access or limited access without a known date.

The current scoped assessment keeps `limited`, `not_assessed_or_denied`, `api_unavailable`, and `not_completed` distinct. It binds the selected metrics, dates, timezone, profile and request lifetime. Interactive execution rechecks that scope and requires an explicit Continue or Cancel if the assessment does not complete. Query and durable-export paths return their own scoped evidence when negotiated. **All Time** / `all_available` acquires currently readable data; it never certifies that unreadable earlier records do not exist.

The legacy `healthmd.history_authorization` v1 representation remains decodable. Historical `full_history` tags are compatibility data, not authorization proof; newly assessed omitted boundaries report `unknown`. A scope-free status response reports unverified history. Legacy all-data sync without bound history provenance requires an explicit date range or a scoped export path.

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

- When an export reports authorization-not-determined errors, Export Permission Guidance identifies the affected types where possible and offers Request Access. It cannot identify privacy-hidden read denials from successful empty queries.

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
| History disclosure reports a limited boundary | OS 27 reported an earliest readable sample end date | Earlier data remains unknown; review permissions or select an explicit date range. |
| History assessment did not complete | The provider failed, timed out or could not cover the selected scope | Review the current selection, then explicitly Continue without verification or Cancel. No sample is read merely because a logical waiter expired. |
| History state is `api_unavailable` | The runtime or app build cannot call the history-boundary API, or the query is local to Mac | Treat full-history completeness as unverified. Runtime and build support are separate; no omitted boundary proves full read access. |
| Medication/Vision locked | Unsupported OS or selector incomplete | Use supported OS and complete separate selection. |
| Clinical record metric unavailable | Clinical Health Records are omitted from this App Store build | Use an ordinary Apple Health metric; clinical access may return in a future reviewed release. |
| Archive partial | One requested branch failed/skipped/unsupported/cancelled | Inspect manifest and retry recoverable paths. |
| Scheduled export cannot read | Device locked/protected | Unlock and use pending recovery. |

## Video outline

- **Suggested title:** Understand Apple Health Permissions and Empty Results
- **Hook:** “A missing sample can mean no data, no selection, or a privacy-hidden denial.”
- **Demo flow:** ordinary authorization, metric selection, available medication/vision selectors, and manifest outcomes; explain that clinical/document authorization requires a separately qualified clinical build, not the default build.

## Implementation notes

- `HealthKitRecordCatalog` derives standard authorization from reviewed runtime-available descriptors.
- `HealthKitManager` keeps standard, medication, vision, document, verifiable, and WorkoutKit paths separate; the document/clinical paths are source-gated off in current App Store builds.
- Errors are isolated and safely described without logging clinical content/PHI.
- macOS does not query HealthKit; iPhone prepares local/API/Connected Mac records.
- The current scoped adapter requires actual SDK 27 compilation and supported runtime qualification. The older compatibility adapter's SDK-family flag does not prove that every app source compiles against SDK 26. Local SDK 26.5 cannot qualify the current scoped API; do not infer support from the compiler version or override gates to make an unsupported build pass.
