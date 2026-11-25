# Apple Watch VO2 max guide claim verification

Verified: 2026-11-25 by Claude (agent), method: traced.

No device run or screenshot was performed. Apple claims come from the task brief's summary of the cited Apple page (the page itself was not re-fetched in this job), so the guide stays close to that summary and gives no ranges or interpretation. Health.md claims trace to repository source and generated fixtures.

## Claims

- [x] Cardio Fitness is the estimate of VO2 max from heart rate and motion sensor data; range 14-65 mL/kg/min; classifications for users 20+; inputs age, sex, weight, height, heart-rate medications; overestimate caveat: https://support.apple.com/en-us/108790
- [x] Only Outdoor Walk, Outdoor Run and Hiking workouts count, indoor/gym equipment workouts do not, Apple Watch Series 3 or later, first estimate needs 24 hours of wear plus several qualifying workouts and passive measurements, Update option, Browse > Heart > Cardio Fitness, D/W/M/6M/Y and notifications: https://support.apple.com/en-us/108790 (Update option described only generally).
- [x] Export All Health Data route (Summary, picture, export.zip, export.xml): https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios. Identifier `HKQuantityTypeIdentifierVO2Max`: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max and `apps/apple/HealthMd/Shared/Models/HealthMetrics.swift` (`vo2_max`, "Cardio Fitness", mL/kg/min, mostRecent, isEnabledByDefault: true).
- [x] Latest sample with start before end of day; carried forward = start before start of day; age = start of day minus sample start (0 when measured that day): `apps/apple/HealthMd/Shared/Managers/HealthKitManager.swift` (~3258-3296).
- [x] CSV row names, JSON fields: `apps/apple/docs/reference/generated/core/csv-row-contracts.md`, `daily-json-fields.md`; Markdown line and "carried forward" / "measured in this day" sub-bullet: `MarkdownExporter.swift` (~807-829).
- [x] The CSV excerpt is lines 34-39 of `docs-src/public/reference/generated/core/summary-day.csv` (fictional, day 2026-03-15, 42.5, carried forward true, age 86400), copied exactly.
- [x] No row before the first estimate: the exporter writes the value only when non-nil (HealthKitManager.swift, MarkdownExporter.swift above).
- [x] Android: no claim made. Privacy wording follows site rules: local folder workflow; Cloud pilot separate, opt-in, single-owner, not generally available.
