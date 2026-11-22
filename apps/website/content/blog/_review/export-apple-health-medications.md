# Apple Health medication log export claim verification

Verified: 2026-11-22 by Claude (agent), method: traced.

No device run, simulator walkthrough or screenshot was performed. Claims about the Health app cite Apple; claims about Health.md trace to repository source.

## Claims

- [x] Native Export PDF path (Browse, Medications, More, Export PDF) and "current medications" description: https://support.apple.com/en-us/105064 and https://support.apple.com/guide/iphone/iph811670c81/ios. Missing doses/times is labeled a user report: https://discussions.apple.com/thread/255966235.
- [x] Per-medication authorization: WWDC25 session 321, https://developer.apple.com/videos/play/wwdc2025/321/. Health.md calls `requestMedicationAuthorization` (`HealthKitManager.swift`, `GlassMetricsScreen.swift`).
- [x] Medications is an opt-in category with a separate permission flow, availability `healthKit26`: `apps/apple/HealthMd/Shared/Models/HealthMetrics.swift` (`requiresSeparateAuthorization`, `isEnabledByDefault`, metric `medications`). Unsupported message "Medication export requires iOS 26 or later. Other Health metrics can still be exported." from `GlassMetricsScreen.swift`. Per-object selectors and opt-in: `apps/apple/docs/features/export-schema.md`.
- [x] Field names: Markdown keys in `HealthMetricsDictionary.swift` (medication_count ... medication_dose_events); JSON keys (medicationCount, doseEventCount, takenDoseCount, skippedDoseCount) in `JSONExporter.swift`. CSV column layout for medications was not traced, so the post names CSV only as a format option.
- [x] Fictional sample: `docs-src/public/reference/generated/individual/medication-dose.md` (status taken, scheduled 09:14 vs start 09:19, dose 1.5, scheduled 2, unit tablet), labeled fixture output. Individual tracking: `/docs/individual-tracking/`.
- [x] Android unavailable: `packages/contracts/product-capabilities.json`, `apple.medication-dose-events`.
- [x] No claim about export.xml medication contents; clinical medication records are a separate type (`clinical_medication_records` in HealthMetrics.swift).
- [x] Privacy wording follows the site rules: local folder workflow, Cloud pilot separate, opt-in, single-owner, not generally available.
