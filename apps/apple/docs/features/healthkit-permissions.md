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

On OS 27 and later, the production adapter uses HealthKit's [`earliestAuthorizedSampleDate(for:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestauthorizedsampledate(for:)) API to assess the exact selected types and their dependencies. Returned dates limit sample **end** dates. Omitted types, an empty response, failures, unavailable APIs and unassessed types remain explicit uncertainty; they never prove unrestricted history or a denied read.

**All Time** means all readable data in the selected scope. Earliest-date discovery must complete for every selected metric; a partial query cannot supply a successful sibling's range. Discovery freezes the export time zone, rejects changed selections and cancellation, and does not turn failed or empty discovery into Today with an All Time label.

The separate capture-time assessment binds historical-access evidence to the exact selection and operation. Known limitations and unknown coverage remain visible in native warnings and the existing query/export history extensions. Interactive exports retain the explicit Continue Unverified/Cancel decision for a slow assessment and revalidate readiness before capture. Portable and paired-Mac operations retain their existing request/peer/scope-bound observations and recovery validation. Date discovery itself makes no full-history completeness claim.

The legacy compatibility assessment reserves `full_history` for affirmative evidence; its boundary-only adapter cannot produce that state. Current native and transport behavior follows the [history assessment implementation](../testing/history-authorization-implementation.md) and [export-history contract](../../../../packages/contracts/export-history/v1/README.md).

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
| History warning reports a limited boundary | OS 27 reports an earliest readable sample-end date for a selected type | Review Health access or export the readable scope with its limitation retained. Earlier data remains unknown. |
| History warning reports unknown or unavailable evidence | The API cannot establish unrestricted history for this selected scope | Review Health access. A slow interactive assessment retains Continue Unverified/Cancel; no result becomes proof of full history. |
| History state is `api_unavailable` | The runtime or app build cannot call the history-boundary API, or the query is local to Mac | Treat full-history completeness as unverified and use explicit ranges. OS 27 alone is insufficient; the iPhone app must also be built with a supported SDK. |
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
- Native iPhone/iPad **All Time** range resolution uses `NativeExportDateRangeResolver` for complete selected-query discovery in the frozen time zone. The existing execution-selection coordinator independently assesses and binds history evidence before capture. Saved dates, Preview, Connected Mac and API exports preserve selection identity, ordinary readiness/quota checks and request-bound historical-access evidence.
- Errors are isolated and safely described without logging clinical content/PHI.
- macOS does not query HealthKit; iPhone prepares local/API/Connected Mac records.
- Production history assessment uses the SDK 27-qualified adapter with runtime availability checks. The older compatibility adapter retains its explicit `HEALTHMD_HAS_HEALTHKIT_HISTORY_AUTHORIZATION` SDK-family gate; an unavailable adapter reports uncertainty. Neither path turns an omitted boundary into unrestricted-history proof. Native qualification must use the supported SDK; do not disable that requirement to make an older local SDK pass.
