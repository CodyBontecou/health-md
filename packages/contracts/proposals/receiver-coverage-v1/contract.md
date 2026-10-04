# Receiver coverage v1 — deferred proposal

Refs https://github.com/CodyBontecou/health-md/issues/170

**Status: proposal plus executable reference model only. Neither Apple nor Android
implements this feature. No production writer, endpoint, setting, or migration is
enabled by this change.** Review the contract before native adoption. Do not use
this document as evidence that an arbitrary API endpoint supports preflight.

## Outcome and scope

An explicitly opted-in scheduled **compatibility API export** can omit completed
days already retained by its configured receiver while still refreshing selected
recent snapshots and today's partial snapshot. Existing schedules continue to
resend their full lookback. Manual exports, raw snapshots, source-change cursors,
local folders, Connected Mac, and direct CLI/MCP are outside this proposal.
Receiver coverage is neither HealthKit/Health Connect permission completeness nor
a source deletion/correction feed.

The independent `healthmd.receiver_coverage` request/response contract stays v1;
the proposal's recovery-plan JSON is independently versioned at v2. This does
not change `healthmd.api_export`, Apple daily v8, Android frozen v4/analytical
v5, range-summary v9, direct protocols, or shared-core versions. All existing
shipped bytes, settings, pending requests, and acknowledgement journals stay unchanged.
No signature regeneration or historical-fixture rewrite is appropriate.

## Configuration (proposed, not current UI)

Per API schedule/profile:

- `selection_policy`: `full_lookback` by default; `missing_days` requires explicit
  opt-in and the warning below. A missing persisted setting means full lookback.
- `preflight_url`: an explicit final HTTPS URL supplied by the receiver owner.
  There is no discovery, appended path, generic GET, or change to the upload URL.
  HTTPS, same origin as upload, no userinfo/query/fragment, and no redirects are
  required for this new mode. Existing HTTP/full-lookback configurations are not
  migrated or made unusable. Cross-origin preflight is unsupported in v1.
- `scope_id`: opaque non-secret receiver namespace for the exact account/tenant,
  producer platform, daily profile/version, selected metrics, detail/archive and
  provider settings. Changing any of these requires a new scope. Two platforms'
  shipped daily profiles must not imply interchangeable coverage.
- `refresh_recent_days`: explicit integer 0–30, measured backward from the latest
  candidate owner date in **calendar days**, intersected with candidates. Require
  a user choice when enabling missing-days; recommend the full lookback for
  correction-sensitive users. Zero explicitly disables completed-day correction
  refresh; coverage does not prove the source can never change. Manual full
  re-export remains the escape hatch for older corrections/deletions.
- Today Refresh keeps its existing independent setting/cadence. Preflight never
  suppresses today's work and never advances its success marker.

Opt-in warning: “Already retained completed days may be skipped. Late source
updates outside the correction window will not be resent automatically. Use full
lookback or a manual re-export to refresh older snapshots.” This is not incremental
source sync. Receivers must continue replacing/upserting each complete daily
snapshot instead of appending duplicates.

Authentication reuses the frozen upload credential/header configuration only at
the explicitly configured same origin. Native secure credential stores remain
authoritative; no credentials go in URLs, exported settings, journals, logs,
history, or error messages. App-controlled Accept/Content-Type/framing headers
cannot be overridden for preflight. Receivers authenticate before returning state
and must bind the requested scope to that authenticated account. Unknown/foreign
scope is an error, never another account's coverage. This proposal adds no login,
enrollment, account-change, or authentication-challenge API.

## Request and response

POST to the exact configured `preflight_url`, with `Content-Type: application/json`
and `Accept: application/json`. No request health records are sent, but dates and
scope are private metadata: do not log request/response bodies, credentials, URLs,
or identifiers. The receiver implements a read-only query, not an upload.

Synthetic request:

```json
{
  "schema": "healthmd.receiver_coverage.request",
  "schema_version": 1,
  "request_id": "occurrence-1",
  "scope_id": "scope-1",
  "calendar_timezone": "America/Los_Angeles",
  "start": "2026-03-06",
  "end_exclusive": "2026-03-09"
}
```

Synthetic response (HTTP 200 with JSON media type):

```json
{
  "schema": "healthmd.receiver_coverage.response",
  "schema_version": 1,
  "request_id": "occurrence-1",
  "scope_id": "scope-1",
  "calendar_timezone": "America/Los_Angeles",
  "start": "2026-03-06",
  "end_exclusive": "2026-03-09",
  "completed_dates": ["2026-03-06", "2026-03-08"]
}
```

All fields shown are required, with no extra or duplicate fields. Version is an
integer, not a Boolean. IDs contain 1–128 ASCII letters, digits, underscores, or
hyphens; use a fresh random occurrence request ID. The response echoes the entire
request context except schema. Replayed/mismatched context is invalid.

Dates are Gregorian zero-padded `YYYY-MM-DD` owner dates. `start` is inclusive;
`end_exclusive` is exclusive. Calendar boundaries use the frozen IANA timezone,
not the UTC date or elapsed multiples of 24 hours; DST days remain civil days.
Candidates come from existing occurrence math, contain only completed days, and
span at most 30 calendar days with at most 30 dates. The interval covers candidates;
it need not assert every candidate will have readable source records.

`completed_dates` is a sorted unique list of **explicit** retained complete days
in that scope/window, before today's date in the frozen zone. The example leaves
March 7 missing, even though March 8 is observed. There is **no high-watermark,
contiguous-prefix inference, pagination, or “latest date means complete” rule**.
Empty list means no completed coverage. A receiver may omit uncertain dates,
causing conservative re-export. It must not label a partial/failed capture or a
mere batch receipt complete, even for HTTP 2xx. A confirmed complete-empty day can
be reported only if the receiver has explicit completeness evidence; current
upload envelopes may not provide that evidence for no-readable-data days.

## Failure policy and deterministic selection

1. Reuse an existing frozen plan first. Do not preflight retries.
2. For a new full-lookback occurrence, do not issue preflight at all.
3. For a new opted-in occurrence, freeze candidates, calendar, configuration,
   request ID, and destination binding before preflight. Derive Today Refresh's
   owner date from actual execution time in the frozen zone, independently of the
   intended completed-day fire boundary.
4. Valid coverage selects `candidates - completed_dates`, then unions candidates
   in the correction window and, if due, today's owner date.
5. Transport failure, timeout, non-200 (including 204, 401, 429, 5xx), invalid media
   type, malformed/unsupported/oversized/mismatched/future state, or unknown scope
   falls back to **full original candidates**, plus due Today Refresh. Do not
   interpret failure as “all retained.” The upload remains bound to its original
   destination; an upload auth failure is still a failure. Native cancellation is
   not receiver unavailability: preserve pending work and stop without upload.
6. Require a 10-second total preflight deadline, no redirects, no automatic
   preflight retries in one occurrence, and a streaming 64 KiB response cap before
   JSON decoding. Persist a fixed safe status (`not_requested`, `valid`, or
   `fallback_full`) and, only for `valid`, the bounded normalized validated response
   as frozen selection evidence. Never retain server error bodies. This evidence
   is for recovery of that occurrence only, not a response cache for newer ones.

An empty selection after valid coverage satisfies only that completed-day
occurrence without capture/upload; it must not clear unrelated residuals or claim
health records were uploaded. Due Today Refresh still captures/uploads normally.
Receiver retention races can cause later re-export; v1 is an optimization, not a
transactional guarantee against receiver deletions after preflight.

## Durable plan and recovery (native work still required)

Atomically persist a versioned plan **before capture or upload**: occurrence/profile
identity, original candidates, chosen dates, exact residual dates, intended fire
boundary, frozen calendar, original Today Refresh owner date/slot, frozen output
settings, policy/correction window, opaque scope/request IDs, destination binding,
safe coverage status, and bounded validated coverage evidence. Link it to existing
durable operation IDs/batch journals. The reference `Plan` JSON tests the
date-selection/recovery subset, not native storage, scheduling markers, or atomic
commits.

`healthmd.receiver_coverage.plan` v2 requires `coverage_response`: immutable JSON
text containing only the validated response for `valid`, or `null` for
`not_requested`/`fallback_full`; `select` normalizes it before persistence.
The same strict response parser enforces the 64 KiB
cap, at most 30 explicit completed dates, and echoed frozen request context on
restore. Recompute the **original selection**, not the residual, from that saved
evidence, original candidates, policy/correction window and Today Refresh owner
date. The persisted `selected` must equal the result exactly. For example, coverage
of March 7 with candidates March 6–8 and a one-day correction window selects March
6 and March 8: dropping March 6 from both `selected` and `residual` must fail, not
become indistinguishable from a receiver that originally retained March 6 too.
Acknowledgements may reduce only `residual`; they preserve all selection evidence.
A bad restore raises an error without returning an empty/fallback replacement;
the caller must retain the pending JSON and abort capture/upload for explicit
recovery. No current receiver query or new execution date may repair a mismatch.

Saved evidence establishes internal snapshot consistency, not authenticated
historical authority or protection against rewriting the entire journal. No
checksum of restored/mutated fields supplies that authority. Native atomic storage,
authenticated preflight and secure destination binding remain adoption gates.
Evidence-less plan v1 is rejected, including valid missing-days plans; there is no
automatic migration because its original selection cannot be proven. Retain that
state for explicit recovery rather than invent coverage or discard pending dates.
This is a proposal-local JSON version change, not a native journal migration.

Destination binding must be an installation-keyed HMAC over an unambiguous canonical
encoding of target type, exact normalized upload/preflight URLs, credentials/routing
headers, scope, output-affecting settings, and calendar zone. Domain-separate it as
`receiver-coverage-destination-v1`. Store only the digest; protect the key with the
native secure store. Do not use an unkeyed credential hash. The reference uses a
synthetic 64-hex binding supplied by its caller; it does not compute or store keys.
Credential rotation conservatively blocks pending recovery unless an explicit
reviewed user recovery flow confirms the same destination. A changed endpoint,
account/header/scope, calendar, or output settings must never silently reroute work.

Retry only unresolved originally chosen dates, using original bytes/operation
identity for prepared batches and the original settings for fresh capture residuals.
Acknowledged days reduce the residual; they never expand it, re-run preflight, or
recompute against a newer receiver response/day/window. Capture failures remain
unresolved even when siblings' batch upload succeeds. Persist acknowledgement before
clearing completion; reconcile existing batch frontiers after crash. A failed plan
write must abort before capture/upload. Unknown/corrupt plan versions preserve local
state for explicit recovery, not “no pending work.”

Legacy pending requests are not rewritten, filtered, dropped, or re-bound. New
configuration applies only to new occurrences after exact legacy residuals resolve.
No destination-discard, migration, or local-data deletion is implemented here.

## Source investigation and non-duplication

At base `b8fd904f4d299f5af4a22111d2fdccf829705ea7`:

- Apple `ScheduledExportCoordinator.makePendingScheduledExportRequest` computes
  dates locally and reuses an existing same-occurrence pending request. Its
  completion path preserves exact residual dates and frozen calendar; it has no
  receiver query or selection-plan field. `APIExportClient.upload` POSTs snapshots
  and accepts status-based 2xx success; it does not parse receiver coverage.
- Android `ScheduledProfileOccurrenceMath.dueOccurrence` prioritizes exact residual
  groups, otherwise returns the entire trailing completed-day window and separate
  Today Refresh. `APIEndpointExportRunner.exportDates` snapshots credentials and
  checks destination fingerprints and durable-operation identity before capture.
  Those protections must be extended, not replaced by receiver coverage.
- `APIExportClient.kt` is an upload client, not a coverage client. Its existing
  custom headers, response previews, and redirect behavior cannot be assumed safe
  for this new read contract. New bounded/no-redirect transports need native
  tests; this PR makes no SDK-call or transport implementation claim.

Live issue/PR review found no receiver-aware selection implementation. Merged
[PR 86](https://github.com/CodyBontecou/health-md/pull/86) implements batching, not
coverage. Open [PR 153](https://github.com/CodyBontecou/health-md/pull/153) implements
a distinct Agent Data Gateway artifact-ingest contract and explicitly defers API
export envelopes. Open [PR 163](https://github.com/CodyBontecou/health-md/pull/163)
adds blocked Cloud foundations; it is not proof that arbitrary endpoints implement
this proposed preflight. Neither branch was modified or imported.

## Parity and consumer impact

| Producer/consumer | State and adoption boundary |
|---|---|
| Apple scheduled compatibility API | **planned**: add per-profile/schedule opt-in configuration, bounded same-origin preflight, atomic plan persistence and exact retry/destination gates; adopt the same reference cases before enabling |
| Android scheduled compatibility API | **planned**: same target and semantics, covering both profile and legacy single schedules; preserve WorkManager cancellation and durable journals |
| Shared Rust core | No change; possible future shared selector after contract review; HTTP and secure stores stay native |
| CLI/direct MCP | No wire/output change, no receiver queries |
| Website | No availability claim or generated public guide change; publish setup instructions only at native adoption |
| External Obsidian plugin | Daily files/keys unchanged; no preflight consumer or fixture change |
| Receiver owners | Must explicitly implement/authenticate this independent v1 query before opt-in is usable |

Neither platform is staged as available. The shipped product-capability inventory
remains unchanged; add `export.scheduled-receiver-coverage` as `planned` with both
native targets when adoption begins, and mark `shared` only after both platforms'
source/device gates. This proposal's parity table is not a shipped parity claim.

## Verification surface and limits

`reference.py` is standard-library executable contract logic, **not app code**.
`test_reference.py` executes selection, strict receiver parsing, correction/Today
Refresh policy, v2 JSON plan round trips, saved-evidence/context validation, coupled
March 6 omission rejection, acknowledgement-only residual reduction, destination
rejection and fail-closed v1 recovery. Core Rust CI registers these tests in a
separate Ubuntu-hosted bounded job that participates in its final gate. Run the
standard-library tests from the repository root:

```sh
python3 -m unittest discover -s packages/contracts/proposals/receiver-coverage-v1 -p 'test_*.py' -v
```

Reproduction remains code-derived: no device/backend scenario was run. Native
UI/persistence migration, atomic fault injection, bounded transport/redirect/auth
mock tests, cross-language fixture consumers, cancellation, schedule success markers,
relaunch recovery, and actual iPhone/Android plus receiver QA are outstanding.
Passing the reference suite alone does not complete issue 170. Keep the PR draft
and issue open; do not enable this feature on the strength of proposal tests.
