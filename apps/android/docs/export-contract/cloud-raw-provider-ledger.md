# Cloud provider-native raw snapshot ledger

This additive ledger governs `recordKind=provider_payload`. Every successful page is captured by the existing OAuth-aware `CloudHealthApiClient` and synchronously streamed through `CloudRawResponseObserver`; adapters do not create a second client. The exact response bytes/base64 and their SHA-256 are authoritative. Parsed JSON is used only for pagination, application-envelope validation, and WHOOP cycle ID fan-out. Withings pages are observer-eligible only when the parsed top-level application `status` is `0`; an HTTP-200 Withings error envelope is rejected before every raw observer.

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
| WHOOP `whoop/cycle` | `/developer/v1/cycle` | `next_token`, 100-page cap, cycle detection | exact start/end instants | false |
| WHOOP `whoop/recovery` | `/developer/v1/recovery?cycleId=…` | bounded fan-out | IDs discovered from the exact captured cycle pages; IDs are never exported as query metadata | false |
| WHOOP `whoop/activity/sleep` | `/developer/v1/activity/sleep` | `next_token`, cap/cycle detection | exact start/end instants | false |
| WHOOP `whoop/activity/workout` | `/developer/v1/activity/workout` | `next_token`, cap/cycle detection | exact start/end instants | false |
| WHOOP `whoop/body_measurement` | `/developer/v1/user/measurement/body` | none, explicit | current non-temporal provider response | false |
| Withings `withings/activity_summary` | `/v2/measure?action=getactivity` | `body.more` + `body.offset`, 100-page cap, cycle detection | captured-zone day parameters | true |
| Withings `withings/sleep_summary` | `/v2/sleep?action=getsummary` | same | captured-zone day parameters | true |
| Withings `withings/measures` | `/measure?action=getmeas` | same | epoch-second `[start,end)` parameters | false |

## Fidelity and unsupported providers

Fitbit, Oura, WHOOP, and Withings declare `native_api_payload`. Their successful response bytes, JSON whitespace/order/unknown fields, native units, content type/charset, allowlisted response headers, and sanitized request metadata are preserved. Endpoint identifiers are provider-scoped hashes, never paths or URLs. Because exact response bytes are authoritative, Oura/WHOOP response bodies can contain provider pagination cursor/token fields; those payload bytes and their decoded/base64 forms are sensitive health-export content. Cursor/token values and WHOOP `cycleId` are excluded from query metadata, endpoint identifiers, logs, structured errors, and exported request/response headers. Data-field lists, OAuth material, cookies, arbitrary error bodies/text, and arbitrary headers are also excluded outside the exact successful provider payload.

Polar is `unsupported` until a transaction-safe AccessLink native adapter exists. Direct Samsung, Huawei, and Garmin are also `unsupported` until native adapters exist. Health Connect declares `health_connect_api_projected`. Any adapter that has only Health.md normalized metrics must declare `normalized_only` or `unsupported` and cannot appear in this endpoint ledger as native.
