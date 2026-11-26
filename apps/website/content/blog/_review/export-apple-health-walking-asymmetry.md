# Walking asymmetry guide claim verification

Verified: 2026-11-23 by Claude (agent), method: traced.

No device run or screenshot was performed. Apple claims cite Apple pages read on 2026-11-23 (HealthKit pages via developer.apple.com documentation data); Health.md claims trace to repository source and generated fixtures. The white paper PDF could not be text-extracted, so nothing in the guide relies on it, and the WWDC20 session was not used.

## Claims

- [x] Walking asymmetry definition, iPhone 8 or later, phone near waist, steady on flat ground, wheelchair status, 10 to 30 samples per day: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingasymmetrypercentage. No normal range appears there, so none is stated.
- [x] Walking speed, step length (height up to date), double support (20% to 40% typical, varies with speed/terrain): HealthKit pages walkingspeed, walkingsteplength, walkingdoublesupportpercentage.
- [x] Stair ascent/descent: Apple Watch Series 5 or later, 10-foot (3 m) flight: HealthKit pages stairascentspeed, stairdescentspeed.
- [x] Walking steadiness: custom algorithms for balance, strength and gait; OK/Low/Very Low; notifications; iPhone 8 or later, pocket or holster near waist: https://support.apple.com/en-us/102504 and https://support.apple.com/guide/iphone/monitor-your-walking-steadiness-iphff1bf03ed/ios (Browse, Mobility, Walking Steadiness, Show More Walking Steadiness Data; share notification). Sample every 7 days and height requirement: HealthKit appleWalkingSteadiness page.
- [x] Apple Watch answer: stated only as "documented as iPhone metrics"; no claim a watch cannot record them. Motion & Fitness is explicitly not claimed as an Apple-documented cause; Settings path is a suggestion to check, not a documented cause.
- [x] Export All Health Data route: https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios (as used in apple-health-xml-export). Identifiers: `apps/apple/HealthMd/Shared/Models/HealthMetrics.swift` lines for walking_speed ... stair_descent_speed.
- [x] Field names, aggregation and units: `docs/reference/generated/core/metric-catalog.md` (walking_asymmetry_percent, double_support_percent, step_length_cm, walking_speed m/s, walking_steadiness_percent daily latest, stair speeds m/s). CSV rows and Markdown lines: `CSVExporter.swift` (~692-715), `MarkdownExporter.swift` (~1139-1163); sample values copied from `summary-day.csv` and `summary-day.md` (fictional). JSON mobility fractions (0.015): `summary-day.json`. Walking speed is m/s in CSV/JSON/frontmatter and km/h in Markdown (metric).
- [x] Defaults and omission: all listed metrics `isEnabledByDefault: true`, availability baseline. Missing values are omitted, not zero (exporters write rows only when non-nil).
- [x] Android: not available in Health.md today; `docs-src/.../visualizations-roadmap.md` says Android lacks asymmetry and double support; the page makes no wider Android claim.
- [x] Clinician Report PDF: see export-apple-health-data-pdf ledger. Privacy wording follows site rules: local folder workflow, Cloud pilot separate, opt-in, single-owner, not generally available.
