# Android Phase 3 Apple-Exclusive / N/A Metrics

**Status:** implemented as explicit Android N/A handling  
**Date:** 2026-06-05  
**Reference:** `docs/export-contract/android-ios-gap-matrix.md` Tier 3 and `docs/export-contract/health-connect-phase2-mapping.md`

Phase 3 does not add fabricated export fields. It finalizes parity by making metrics that are Apple-exclusive or absent from Health Connect explicit and non-selectable on Android.

## Implementation decision

- Supported Android metrics remain in `HealthMetrics.allMetrics` and can be toggled in the metric picker.
- Unavailable iOS-only or Health Connect-missing metrics are listed in `HealthMetrics.unavailableMetrics` with a user-facing reason.
- Persisted stale metric IDs, such as the old unsupported `audio_exposure` selector, no longer inflate enabled metric counts.
- Metric picker categories are built only from supported metrics, so unavailable-only categories are not shown as empty `0/0` groups.
- The metric picker shows an Android Phase 3 notice summarizing unavailable Apple-exclusive data.

## Phase 3 Apple-exclusive items

| Metric | Android status | Reason |
|---|---|---|
| Wrist Temperature | N/A | Apple Watch wrist-temperature hardware; Android exports Health Connect Skin Temperature Delta separately when present. |
| Electrodermal Activity | N/A | Apple Watch sensor; no Health Connect equivalent. |
| Heart Rate Recovery | N/A | Apple Watch-derived daily signal; no matching Health Connect aggregate. |
| AFib Burden | N/A | Apple Watch-derived atrial fibrillation burden; no Health Connect equivalent. |
| State of Mind entries/count/valence/mood fields | N/A | HealthKit State of Mind is iOS 17+/Apple-platform specific and is not exposed by Health Connect. |
| Forced Vital Capacity, FEV1, Peak Expiratory Flow, Inhaler Usage | N/A | No Health Connect 1.1.0-beta02 respiratory volume, spirometry, peak-flow, or inhaler-use records. |

## Additional Health Connect-unavailable fields surfaced by the Phase 2 audit

These are not necessarily Apple-hardware-exclusive, but they are unavailable in the audited Health Connect API and are therefore also non-selectable as live Android metrics:

- Hearing/audio exposure: headphone audio level, environmental sound level, legacy `audio_exposure` selector.
- Activity gaps: Stand Hours, Move Minutes, Physical Effort.
- Body gap: Waist Circumference.
- Mobility/running dynamics gaps: walking step length, double support, walking asymmetry, stair speeds, six-minute walk distance, walking steadiness, running stride length, ground contact time, vertical oscillation.
- Symptoms: HealthKit symptom records have no Health Connect 1.1.0-beta02 equivalent.

## Export contract behavior

Android exporters continue to omit categories and fields with no data. They do **not** emit fake `null` fields for Phase 3 N/A metrics, because the iOS contract already treats category fields as optional and plugin parsers gracefully ignore absent fields.

If Health Connect adds any of these records in a future version, move the metric from `HealthMetrics.unavailableMetrics` to `HealthMetrics.allMetrics`, add Health Connect fetch/export support, and update this document plus `health-connect-phase2-mapping.md`.
