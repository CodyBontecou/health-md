# Apple Watch respiratory rate guide claim verification

Verified: 2026-11-27 by Claude (agent), method: traced.

No device run or screenshot was performed. Apple pages were read live on 2026-11-27 (some through a summarising fetch; the HealthKit page text could not be retrieved, see below). Health.md claims trace to generated references in the repository.

## Claims

- [x] Respiratory rate is an overnight metric; Sleep must be set up with Track Sleep with Apple Watch and Sleep Focus; latest iOS and watchOS; 7 days wearing the watch to bed to establish typical range; "Vitals app measurements are not intended for medical use"; Browse then Vitals; "If your watch is too loose, the sensors might not capture accurate readings": https://support.apple.com/en-us/120142
- [x] Wear watch at least 1 hour each night; Track Sleep with Apple Watch; Respiratory Rate not available under 13; Sleep Comparisons shows Heart Rate and Respiratory Rate: https://support.apple.com/en-us/108906
- [x] Vitals app on watch, Digital Crown to a metric; Health, Browse, Vitals on iPhone; "Not all features are available in all areas and on all models"; overnight metrics list; heart rate variability replaces sleep duration on some newer models; daytime vitals described as heart rate and HRV on those models; typical range wording: https://support.apple.com/guide/watch/apd15aa7ed96. That page does not state the number of nights, so the 7 comes only from 120142.
- [x] Respiratory Rate switch in Privacy settings on watch and Apple Watch app (My Watch, Privacy): https://support.apple.com/guide/watch/track-your-sleep-crpxel1lvun9/watchos
- [x] Regional/version wording differences: stated generally; the guide does not give a fixed Respiratory menu path, and tells readers to follow their device. Browse then Respiratory was not confirmed on a live page, so it is omitted.
- [x] Export All Health Data steps: https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios (as used in the walking asymmetry guide). Identifier `HKQuantityTypeIdentifierRespiratoryRate`: `apps/apple/HealthMd/Shared/Models/HealthMetrics.swift` and the metric catalog. The HealthKit page https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/respiratoryrate could not be text-read, so the guide states only that it documents the type and the unit as breaths/min from the Health.md catalog, and asks readers to check the unit string in their own file.
- [x] Catalog row `respiratory_rate`: breaths/min, Default yes, keys `respiratory_rate`, `respiratory_rate_avg` (daily average), `respiratory_rate_min`, `respiratory_rate_max`; "A listed key ... does not guarantee a summary value ... require qualifying data": `docs-src/src/content/docs/reference/generated/core/metric-catalog.md` line 72 and line 16.
- [x] JSON fields `vitals.respiratoryRate`, `respiratoryRateAvg`, `respiratoryRateMin`, `respiratoryRateMax`, `respiratoryRateSamples`: `.../generated/core/daily-json-fields.md` lines 555-559. CSV rows Vitals Respiratory Rate Avg/Min/Max/Sample: `.../generated/core/csv-row-contracts.md` lines 540-543.
- [x] The YAML excerpt is labelled fictional and uses catalog keys only; values are invented and not claimed from a fixture.
- [x] Sleep day: the noon-to-noon journal window comes from `content/blog/why-sleep-is-in-yesterdays-note.md` and the catalog note; no respiratory-specific rule is claimed.
- [x] No normal range, no medical advice, no blood oxygen availability claims. Privacy wording follows site rules (local folder workflow; Cloud pilot opt-in, single-owner, not generally available).
- [x] Incoming links added to export-apple-health-sleep-data.md and export-apple-health-hrv.md; their existing ledgers cover their other claims, and the added sentences only link here.
