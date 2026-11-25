# Apple Watch Activity rings export claim verification

Verified: 2026-11-25 by Claude (agent), method: traced.

No device export or Fitness-app comparison was performed. Claims trace to the metric catalog, specialized-records reference, product docs and Apple documentation.

## Claims

- [x] Native export path (Health → picture/initials → Export All Health Data, `export.zip`): https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios. That ring history is in `export.xml` is the brief's claim, consistent with the HKActivitySummary type; no XML attribute names are stated because none were checked in a real export.
- [x] `HKActivitySummary` documents Move, Exercise and Stand values and goals: https://developer.apple.com/documentation/healthkit/hkactivitysummary (cited from the brief, not fetched in this job, no network client available).
- [x] Table rows: `docs-src/src/content/docs/reference/generated/core/metric-catalog.md` rows active_energy (`active_calories`, kcal, daily sum), exercise_time (`exercise_minutes`, min), stand_hours (`stand_hours`, daily count), stand_time (`stand_time_minutes`), move_time (`move_minutes`). Type links: Apple HealthKit identifier pages for activeEnergyBurned, appleExerciseTime, appleStandHour.
- [x] activity_summary is "Source archive only"; its observed fields are date and active_energy: metric-catalog row and the Activity summary section of `specialized-records.md`. Hence goals, ring-closed flags and badges are not daily fields; no such field exists in the catalog.
- [x] Steps (Health Metrics → Activity, formats, folder, Preview, one-day check, five-step setup): same workflow as `content/blog/export-apple-health-steps-data.md` and `docs-src/src/content/docs/iphone-first-export.md`. Manual export needs no Mac.
- [x] Totals may differ from the Fitness app (sources, time zones, iPhone-only days, same-day changes): hedged; no match promised. Source-prioritization behavior as in the steps guide ledger.
- [x] One file per day for a range, combine via `/apple-health-to-csv/` and the Excel guide: steps guide and existing pages.
- [x] Pricing: no allowance numbers stated; the page links `/docs/paywall/`, which describes weekly/yearly/Lifetime access and eligible trials. The brief's "5 free export actions" copy was deliberately not used because the current paywall doc says the subscription release has no local free allowance.
- [x] Privacy: local folder workflow; Cloud pilot described as separate, opt-in, single-owner, not generally available, per `privacy-policy.html#retention` and the steps guide ledger.
- [x] FAQ: no documented Fitness export found (hedged as "no Fitness-app export is documented"); iPhone-only Move data hedged; no Apple Support Activity-rings page was cited because its URL could not be verified here.
- [x] Links: workouts, XML export, Excel guides, /apple-health-export/, /docs/iphone-first-export/. Related lists: steps and workouts guides now link here (python and strava keep other incoming links per brief); those posts' `updated` unchanged.
