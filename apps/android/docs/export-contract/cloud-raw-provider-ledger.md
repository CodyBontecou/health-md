# Cloud provider-native raw snapshot ledger

Production rollout registers only Health Connect and WHOOP. The other provider entries below preserve adapter semantics and synthetic fixture coverage for future enablement; they do not make those integrations available in the app.

This additive ledger governs `recordKind=provider_payload`. Every successful page is captured by the existing OAuth-aware `CloudHealthApiClient` and synchronously streamed through `CloudRawResponseObserver`; adapters do not create a second client. The exact response bytes/base64 and their SHA-256 are authoritative. Parsed JSON is used only for pagination and application-envelope validation. Withings pages are observer-eligible only when the parsed top-level application `status` is `0`; an HTTP-200 Withings error envelope is rejected before every raw observer.

Selected Health.md metrics expand to the whole listed endpoint. `ALL_AUTHORIZED_SUPPORTED_DATA` requests every implemented endpoint. Each adapter also generates explicit `unsupported/<category>` reports for uncovered metric categories. Those entries never trigger normalized `HealthData` serialization.

| Provider / endpoint key | Native request | Pagination | Range behavior | `serverAggregation` |
|---|---|---|---|---|
| Fitbit `fitbit/activity_daily` | `/1/user/-/activities/date/{day}.json` once per captured-zone day | none, explicit | day path for every day intersecting `[start,end)` | true |
| Fitbit `fitbit/sleep_daily` | `/1.2/user/-/sleep/date/{day}.json` | none, explicit | day path | true (response includes server summary) |
| Fitbit `fitbit/heart_intraday` | `/1/user/-/activities/heart/date/{day}/1d/1min.json` | none, explicit | day path | true (daily server summary plus intraday data) |
| Fitbit `fitbit/body_weight` | `/1/user/-/body/log/weight/date/{day}.json` | none, explicit | day path | false |
| Oura `oura/daily_activity` | `/v2/usercollection/daily_activity` | `next_token`, 100-page cap, cycle detection | captured-zone inclusive date parameters derived from `[start,end)` | true |
| Oura `oura/sleep` | `/v2/usercollection/sleep` | same | date parameters | false |
| Oura `oura/heartrate` | `/v2/usercollection/heartrate` | same | exact start/end instants | false |
| Oura `oura/workout` | `/v2/usercollection/workout` | same | date parameters | false |
| WHOOP `whoop/cycle` | `/developer/v2/cycle` | `next_token` → `nextToken`, `limit=25`, 100-page cap, cycle detection | exact start/end instants, fixed across pages | false |
| WHOOP `whoop/recovery` | `/developer/v2/recovery` | same; independent collection, no cycle prerequisite | exact start/end instants, fixed across pages | false |
| WHOOP `whoop/activity/sleep` | `/developer/v2/activity/sleep` | same | exact start/end instants, fixed across pages | false |
| WHOOP `whoop/activity/workout` | `/developer/v2/activity/workout` | same | exact start/end instants, fixed across pages | false |
| WHOOP `whoop/body_measurement` | `/developer/v2/user/measurement/body` | none, explicit | current non-temporal provider response | false |
| Withings `withings/activity_summary` | `/v2/measure?action=getactivity` | `body.more` + `body.offset`, 100-page cap, cycle detection | captured-zone day parameters | true |
| Withings `withings/sleep_summary` | `/v2/sleep?action=getsummary` | same | captured-zone day parameters | true |
| Withings `withings/measures` | `/measure?action=getmeas` | same | epoch-second `[start,end)` parameters | false |

## WHOOP v2 migration boundary

Android now uses the same WHOOP `/developer/v2` API generation as iOS. Recovery selection (`hrv`, `resting_hr`) no longer fetches or emits unselected cycle pages. Cycle selection covers its native energy (`total_calories`) and average/max heart-rate (`avg_hr`, `max_hr`) fields, not recovery statistics; the raw payload retains WHOOP's original kilojoule units. Sleep/workout UUIDs, recovery `sleep_id`/`cycle_id` relationships, `sport_name`, exact millisecond values, and unknown response fields remain in the authoritative native payload. Existing v1 artifacts remain historical and are never rewritten.

This is a provider API/endpoint-plan update, not a change to Android's frozen daily v4, analytical v5, `healthmd.raw-snapshot` v1, `provider_payload`, direct protocol, or Apple's typed WHOOP v1 contract. Raw endpoint keys remain stable and the dynamic per-type report now declares recovery `pagination: next_token` instead of `fan_out`. Consumers must honor each artifact's actual endpoint identifier and pagination report rather than assume WHOOP's native response grammar is fixed by the outer snapshot version. Shared Rust, CLI, website, API, and external Obsidian grammars are unchanged.

Compatibility daily exports also page sleep, workouts, and recovery, preserve UUID identity, map reviewed `sport_name` values to existing workout enums (unknown names remain `OTHER` with native-name metadata), derive elapsed workout duration from its actual instants, and reuse one workout capture for workout/energy projections. Repeated records across pages are deduplicated only in compatibility projections by sleep/workout `id` or recovery `cycle_id`, retaining the first captured view. Records without a usable provider identity are not collapsed together. A malformed compatibility section is omitted without discarding healthy sibling sections; cancellation still propagates. Authoritative raw pages are never deduplicated or rewritten by this normalization. Body profiles appear only on today's compatibility record, matching iOS; raw snapshots retain the explicitly non-temporal singleton. Android does not adopt Apple's typed `providers.whoop` section or provider-sidecar layout in this migration.

## Fidelity and unsupported providers

### WHOOP compatibility sleep journal window

Night begins normalized WHOOP sleep summaries retain the shipped behavior: query noon on the journal date through noon on the following date in the operation's captured export timezone. The adapter also excludes returned records that do not overlap that half-open window, and excludes invalid or zero-length intervals before adding stage totals. Range reads retain the caller's captured timezone. Workouts and recovery keep their calendar-day query bounds; authoritative raw snapshot reads retain the exact requested instant range and unchanged provider payloads.

This corrects daily ownership without changing the shipped additive aggregation or public v4/v5 fields. The synthetic provider-input sleep fixture now describes the night owned by its requested journal date; versioned export fixtures and signatures remain unchanged. WHOOP provides whole-session stage aggregates, not timestamped stage intervals: aggregates and source timestamps are preserved without fabricated proration at noon. A session crossing noon can therefore contribute its full provider aggregate to adjacent journal windows. This limitation differs from Health Connect's timestamped-stage clipping and must not be mistaken for an exact per-window stage reconstruction. Apple retains its independently versioned typed WHOOP records; this correction does not rewrite those records or their collection windows.

### WHOOP Morning ends successor capture

The explicit `android-sleep-v6` Morning ends path assigns each whole WHOOP session to its end date in the frozen export timezone. It queries the local calendar-day interval with a one-second lower guard for an exact-midnight end, then filters by `dayStart <= sourceEnd < nextDayStart`. [WHOOP's sleep collection contract](https://developer.whoop.com/api/) describes intersecting range results; capture keeps those whole returned records rather than applying a finite duration lookback or clipping their reported stage totals. No timestamped stage sequence is fabricated from aggregate scores.

Morning capture populates the existing successor exact timestamps and native IDs for sleep and workout parents. Timestamp offsets come from the source timestamp literals, not inferred device offsets; elapsed workout duration retains nanoseconds in this path. Night begins keeps its historical noon queries, overlap selection, millisecond behavior and v4/v5 output. Raw `provider_payload` pages, request ranges and Apple's typed WHOOP v1 remain unchanged. Host producer tests cover ordinary overnight, 27-hour, exact-midnight and DST-fold sleep ownership through the real API export route. Real-provider range acceptance and production enablement remain unqualified.

For Morning projections, every selected WHOOP endpoint must finish successfully. HTTP/JSON/envelope errors, pagination cycles and the page cap fail the selected provider capture instead of publishing partial collections as complete or empty. Successful empty collections remain valid. Sleep, recovery and body requests follow category selection; the workout collection is shared by workout and activity-energy projections. API exports report the failed owner date with a sanitized error and no daily record. All-connected capture retains the repository's explicit provider-failure provenance. Historical Night tolerance and native raw endpoint results remain unchanged.

Fitbit, Oura, WHOOP, and Withings declare `native_api_payload`. Their successful response bytes, JSON whitespace/order/unknown fields, native units, content type/charset, allowlisted response headers, and sanitized request metadata are preserved. Endpoint identifiers are provider-scoped hashes, never paths or URLs. Because exact response bytes are authoritative, Oura/WHOOP response bodies can contain provider pagination cursor/token fields; those payload bytes and their decoded/base64 forms are sensitive health-export content. Opaque or secret cursor/token values and WHOOP `cycleId` are excluded from query metadata, endpoint identifiers, logs, structured errors, and exported request/response headers. Explicitly allowlisted non-secret numeric paging offsets may appear in query metadata. Data-field lists, OAuth material, cookies, arbitrary error bodies/text, and arbitrary headers are also excluded outside the exact successful provider payload.

Polar is `unsupported` until a transaction-safe AccessLink native adapter exists. Direct Samsung, Huawei, and Garmin are also `unsupported` until native adapters exist. Health Connect declares `health_connect_api_projected`. Any adapter that has only Health.md normalized metrics must declare `normalized_only` or `unsupported` and cannot appear in this endpoint ledger as native.
