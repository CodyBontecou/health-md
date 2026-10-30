# Apple Health weight export claim verification

Verified 2026-10-30 by Codex (agent), method: traced. No account, device, export, spreadsheet or product visual QA. No native behavior, schema or generated fixture changed.

## Claims

- [x] HealthKitManager.fetchBodyData queries Weight/bodyMass using the selected day's compatibility predicate. SystemHealthStoreAdapter.queryMostRecent sorts endDate descending with limit one. Described as latest available within the day query, not a mean, carry-forward, all weigh-ins, source filter or guaranteed Apple Health chart match.
- [x] HealthMetrics labels the category Body Measurements and metric Weight. BodyData contains an optional daily weight, no weight sample array. Detailed Time-Series is not claimed to add individual weigh-ins. Original-record routes are separate; coverage/capture warnings retained.
- [x] Exact fictional CSV header and weight row come from docs-src/public/reference/generated/core/summary-day.csv, including its omitted sixth Timestamp field. JSON excerpt matches body.weight and units.weight_kg in summary-day.json. Consumer test ties both to those existing generated publications; no fixture bytes changed.
- [x] Maintained format and first-export documentation establish daily files, Summary, Metric/Imperial weight units, folder access and preview. Exact Body/Weight/kg filter prevents mixed Value and unit errors; no summed weights, invented timestamps, missing-as-zero or raw/daily duplication.
- [x] Official Apple bodyMass documentation identifies discrete mass measurements. Apple's Health data guide supports native Export All Health Data. Native XML/import distinction and canonical archive limits follow maintained XML/format/canonical guides. No restore or universal completeness promise.
- [x] Privacy wording follows maintained local/default and optional single-owner retained-export pilot boundaries. No Health.md price/quota, clinical interpretation or unsupported platform claim. Withings guide provides qualified upstream-sharing context.
- [x] Three existing related guides, incoming Withings recommendation and Apple export contextual link aid discovery. Withings body and Apple export metadata/CTA remain unchanged; the added parent link is separately logged and prevents isolating older CTA effects from later outcomes.
