# Receiver coverage v1

Refs https://github.com/CodyBontecou/health-md/issues/170

**Source status: native opt-in configuration, bounded authenticated HTTP, strict
parsers, atomic recovery-plan v2 journals and scheduler call sites are implemented
for personal compatibility API exports on Apple and Android, including profile and
supported legacy schedules.** Existing schedules remain full lookback by default;
legacy pending work is not migrated or filtered. Native integration compilation
and device/backend acceptance are qualification gates, recorded explicitly below.
An arbitrary API endpoint is not assumed to support this contract.

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

## Configuration and opt-in

In a personal API schedule's settings, open **Receiver-aware scheduling**. The
same editor is available for a profile schedule and the legacy app-wide API
schedule. Turning it on requires an explicit preflight URL, scope and correction
window choice. Turning it off or editing it affects new occurrences only. Managed
clinic destinations are currently rejected on both platforms: their upload
credentials rotate independently, so this version cannot prove they equal the
credential pinned by selection. Manual, raw, gateway and non-API exports are not
changed.

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

## Durable plan and recovery

Atomically persist a versioned plan **before capture or upload**: occurrence/profile
identity, original candidates, chosen dates, exact residual dates, intended fire
boundary, frozen calendar, original Today Refresh owner date/slot, frozen output
settings, policy/correction window, opaque scope/request IDs, destination binding,
safe coverage status, and bounded validated coverage evidence. Link it to existing
durable operation IDs/batch journals. The reference `Plan` JSON specifies the date-selection/recovery subset. Native
admission metadata and frozen settings remain in their owning versioned private
queues; the native selector journal stores the exact v2 plan.

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
checksum of restored/mutated fields supplies that authority. Native atomic storage, authenticated preflight and secure destination binding
supply those separate authorities; historical evidence still is not a server-signed
receipt or protection against wholesale local journal replacement.
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

## Native implementation and private recovery boundaries

Apple's [`ReceiverCoveragePreflight.swift`](../../../../apps/apple/HealthMd/Shared/ReceiverCoverage/ReceiverCoveragePreflight.swift)
and Android's [`ReceiverCoveragePreflight.kt`](../../../../apps/android/app/src/main/java/com/healthmd/data/receivercoverage/ReceiverCoveragePreflight.kt)
implement the same preparatory boundary. Native scheduler call sites now consume
it through dedicated runtime adapters and atomic journals as described below. `prepare` defaults to full lookback and returns no preflight in that mode,
even with invalid/missing preflight configuration. Explicit missing-days validates
same-origin URLs, scope, timezone, correction window, headers and a supplied
32-byte installation key. It constructs a keyed destination binding and headers;
request construction separately validates the frozen occurrence ID and completed
civil dates, deriving today's owner day from execution time in the frozen zone.
Native journals save original request context, selection evidence and dates and
restore those values rather than reconstructing selection on retry. `requireOriginalDestination` rejects a changed binding; it is a comparison
gate, not an atomic storage or secure-key adapter.

The native boundary currently accepts a conservative URL subset: ASCII DNS/IPv4
hosts, HTTPS, no percent escapes, dot segments, userinfo, query, fragment, trailing
host dot or IPv6 literal. Scheme/host case and default port 443 normalize; an empty
path becomes `/`. Unsupported new opt-ins are rejected, not rewritten. Existing
full-lookback HTTP/other endpoint settings are not passed through this validator.
Supporting more URL spellings requires paired normalization vectors first.

The shared HMAC transcript is a concatenation of fields, each framed as ASCII
UTF-8 byte count, `:`, then the exact field bytes (no separator after the field).
Field order is:

1. `receiver-coverage-destination-v1`, then `compatibility_api`;
2. normalized upload URL, normalized explicit preflight URL;
3. scope ID, exact calendar timezone identifier, exact frozen output-settings bytes;
4. decimal credential/routing header count;
5. each lowercase header name and exact value, sorted by lowercase name.

Header names must be unique ignoring case, values printable ASCII, at most 64
headers and 16 KiB of name/value bytes. Accept, Content-Type, Content-Length,
Content-Encoding, Transfer-Encoding, Host, Connection, Trailer, TE, Upgrade,
Expect, Proxy-Authorization and Proxy-Connection are reserved. The preflight adds
its own JSON Accept and Content-Type after validation. The binding is lowercase
hex HMAC-SHA256; no URLs, credentials or settings are serialized by this boundary.
The native adapters supply an installation key from Keychain or encrypted Android
preferences, bind effective personal upload headers after native authorization,
and retain frozen output settings. Missing/unreadable recovery keys block work;
initial setup never replaces a key while saved plans exist. A separate keyed
scope-to-settings ledger rejects reusing a scope after changing its output profile,
provider grants or capture calendar; choose a new receiver scope for that change.
Known set-valued Swift fields are sorted for stable identity; ordered arrays retain
their order. URLs, credentials and keys are not stored in identity digests. This transcript adds no authority to legacy journals.

`ReceiverCoverageRequest` freezes the validated body, original destination binding,
URL, effective headers, execution-zone today and echoed context in memory. It is
not itself durable storage and provides no authority to overwrite an existing
pending plan. Native admission and selector journals supply durability. Both native clients accept only this prepared context, never an arbitrary
URL or replacement credential.

Apple's [`ReceiverCoverageHTTPClient.swift`](../../../../apps/apple/HealthMd/Shared/ReceiverCoverage/ReceiverCoverageHTTPClient.swift)
uses a fresh ephemeral URLSession with no shared credential/cookie/cache storage.
It sends one authenticated POST with the frozen upload headers, refuses redirects
and account/proxy/client-credential challenges, and retains platform TLS trust
validation. A monotonic total budget plus an independent deadline timer bounds
headers and streaming body; cancellation and deadline cancel/invalidate the exact
task/session. A locked completion transition handles cancellation/EOF/deadline
races once, without retaining native private errors.

Android's [`ReceiverCoverageHTTPClient.kt`](../../../../apps/android/app/src/main/java/com/healthmd/data/receivercoverage/ReceiverCoverageHTTPClient.kt)
uses a dedicated OkHttp client with redirects, connection retries, authenticators,
cookies, cache and shared interceptors disabled. Call timeout, a total coroutine
budget and a monotonic elapsed check enforce the deadline; coroutine cancellation
cancels the exact call even while its callback reads the body. Every response body
is closed. Test-only protocol/call-factory seams can shorten, never extend, the
10-second budget. Neither client loops/retries or queries another origin.

`ReceiverCoverageResponseBuffer` rejects non-200/non-JSON metadata before body
retention and caps accepted streaming chunks at 64 KiB. Both HTTP adapters read
streamed platform-decoded bytes through this buffer, reject declared oversized
bodies early, and stop reads on overflow. Exceeding the cap poisons the buffer.
Its output remains **unvalidated bytes** until the strict parser succeeds.

The paired [`Swift parser`](../../../../apps/apple/HealthMd/Shared/ReceiverCoverage/ReceiverCoverageResponse.swift)
and [`Kotlin parser`](../../../../apps/android/app/src/main/java/com/healthmd/data/receivercoverage/ReceiverCoverageResponse.kt)
use flat, nonrecursive schema readers that reject duplicate keys (including escaped
spellings), extra/missing fields, invalid UTF-8/escapes, noninteger/unsupported
versions, unsorted/duplicate/invalid dates, more than 30 dates, future/out-of-window
dates and every mismatched frozen context field. Only an explicit sorted retained
date list and normalized validated response become `ReceiverCoverageEvidence`.
Empty valid coverage remains distinct from failure. Neither parser infers a
contiguous prefix or treats HTTP/batch success as coverage.

The new-occurrence `query` outcome is validated evidence or `fallbackFull` for
unavailable, non-200, wrong-media, malformed, oversized, mismatched or timed-out
preflight. External cancellation throws native cancellation instead; it never
returns fallback and must never trigger capture/upload. Direct parser errors
remain errors, so future restore code can preserve bad pending state rather than
calling the network or constructing a replacement plan.

Host diagnostics compile the actual production source in isolation; they do not
build native apps or use SDK health stores. They use an independent Python HMAC
oracle, synthetic destinations/credentials, date-window vectors and streamed cap
checks. Transport diagnostics also compare parser/evidence results to the Python
reference and exercise the real native clients with synthetic URLProtocol/OkHttp
Call implementations: POST/auth/body fidelity, unavailable/status/media errors,
stream bounds, redirects, total deadline and cancellation before headers and
during body reads. They do not contact a receiver or qualify platform TLS/proxy/
compression behavior. Run with Swift and Kotlin compilers installed:

```sh
HEALTHMD_TEST_NATIVE_BOUNDARY=1 python3 -m unittest discover -s packages/contracts/proposals/receiver-coverage-v1 -p 'test_native_*.py' -v
```

If Kotlin is supplied as cached embeddable compiler jars, set
`HEALTHMD_KOTLIN_COMPILER_CLASSPATH` and `HEALTHMD_KOTLIN_STDLIB`; otherwise the
runner uses `kotlinc`/`kotlin` on PATH. The transport tests additionally require
`HEALTHMD_KOTLIN_TRANSPORT_CLASSPATH` with the app's OkHttp/Okio, coroutines and
kotlinx JSON/core jars (no downloads). Missing compilers/dependencies are reported as skips,
not native verification. Temporary compiler output is removed on completion.
These opt-in diagnostics are not added to the portable CI time budget.

The paired `ReceiverCoveragePlan` and `ReceiverCoverageJournal` implementations
write a flushed, atomically renamed provisional full-window plan before receiver
HTTP, then commit validated chosen dates before capture/upload. If interrupted in
preflight, restart fixes that saved conservative plan without another query. Bad
or unknown native journals and v1 evidence-less plans remain intact and block work.
Acknowledgements reduce only the residual; saved candidates, original selection,
coverage evidence, calendar, Today Refresh owner date and destination stay fixed.
A valid empty selection completes only its occurrence without health capture or
an upload-history claim. Prepared API batch journals retain their original bytes
and acknowledgement authority.

Apple's `PendingExportRequest` freezes local receiver configuration for new API
admissions. Receiver requests live in a separately versioned, flushed atomic
pending file, isolated from historical UserDefaults queues and older binaries.
`SchedulingManager` resolves both legacy and profile API runs through the same
selection path, persists narrowed native dates before capture and checkpoints
selection acknowledgements before clearing the native request. Stable plan IDs
include profile/legacy identity, generation, enabled period, intended fire and
kind; recreating a pending UUID after a completion-marker crash cannot re-preflight.
Cancellation/discard checks run after suspension and before capture/checkpoints.

Android profile admissions freeze settings, receiver configuration, keyed binding,
credential fingerprint and root plan ID before source work. The same root plan
survives separate prepared-batch and fresh-capture residual groups. The legacy
worker freezes its policy per admission and publishes exact native pending recovery
before HTTP, then reduces it to chosen dates before capture. Its per-date requests
retain the receiver plan ID even when the API batch operation ID is detached.
Foreground legacy recovery restores the original plan without querying the receiver.
Native generations, WorkRequest IDs, mutexes and prepared-batch acknowledgement
journals remain authoritative.

Receiver-aware Android pending settings use private
`healthmd.receiver_scheduled_snapshot` schema version 1 with native discriminator
`version: 4`: an opaque original canonical output snapshot plus frozen receiver
configuration, plan ID and destination identities. The ordinary portable/profile
snapshot decoder rejects this wrapper; only explicit local scheduled decoding can
unwrap it. Older codecs reject version 4 instead of treating selection authority
as ignorable optional fields. If an older DataStore writer strips optional model
fields, the new reader restores only the copies present in the unchanged opaque
wrapper and rejects contradictions. This is not Android daily/export schema v4,
a public export change, an FFI change or a rewrite of historical settings snapshots.

Android receiver-aware Night begins admissions use private output-snapshot version
5 to retain the exact selected provider set and connection identities. Version 3
keeps its original Morning ends meaning; version 4 remains the receiver wrapper.
New occurrences capture current source authority, while pending work restores its
saved authority. Account/provider changes therefore change the scope binding and
require a new receiver scope. A receiver admission with a historical unbound output
snapshot is rejected before preflight or capture; it cannot adopt the current
account during retry. Enabling receiver mode on an unbound legacy schedule accepts
a new schedule generation before selection. Existing unbound receiver recovery
must be explicitly discarded/replaced rather than silently recaptured.

Today Refresh never consults receiver state on its own. A merged occurrence adds
its original execution-zone today independently of completed-day coverage and
retains that owner date/slot across retry. Existing unbound residuals finish through
their original path before a new receiver-aware occurrence is admitted.

Native HTTP and journal host tests pass independently of app SDK builds. Full app
integration compilation must use `make verify-native`; runtime/backend and visual
acceptance remain explicit, unrun qualification surfaces until requested. Never
infer device acceptance from these hermetic tests.

## Source investigation and non-duplication

At base `b8fd904f4d299f5af4a22111d2fdccf829705ea7`:

- Apple `ScheduledExportCoordinator.makePendingScheduledExportRequest` computes
  dates locally and reuses an existing same-occurrence pending request. Its
  completion path preserves exact residual dates and frozen calendar; the receiver-aware path now freezes opt-in and resolves its atomic v2 plan
  before capture. `APIExportClient.upload` POSTs snapshots
  and accepts status-based 2xx success; it does not parse receiver coverage.
- Android `ScheduledProfileOccurrenceMath.dueOccurrence` prioritizes exact residual
  groups, otherwise returns the entire trailing completed-day window and separate
  Today Refresh. `APIEndpointExportRunner.exportDates` snapshots credentials and
  checks destination fingerprints and durable-operation identity before capture.
  Those protections must be extended, not replaced by receiver coverage.
- `APIExportClient.kt` is an upload client, not a coverage client. Its existing
  custom headers, response previews, and redirect behavior cannot be assumed safe
  for this new read contract. The new isolated transports above do not change the
  upload client or its legacy recovery behavior.

The initial issue/PR review found no existing receiver-aware selection implementation. Merged
[PR 86](https://github.com/CodyBontecou/health-md/pull/86) implements batching, not
coverage. Open [PR 153](https://github.com/CodyBontecou/health-md/pull/153) implements
a distinct Agent Data Gateway artifact-ingest contract and explicitly defers API
export envelopes. Open [PR 163](https://github.com/CodyBontecou/health-md/pull/163)
adds blocked Cloud foundations; it is not proof that arbitrary endpoints implement
this proposed preflight. Neither branch was modified or imported.

Android legacy receiver plans are isolated by admission, even when source capture
failed before creating an API batch. New occurrences never reuse an older plan
or its Today date; dates owned by older pending work remain in explicit recovery.
A legacy admission can cover several missed runs; all its completed owner dates
remain candidates. Catch-up exceeding the v1 30-day count/span freezes full-lookback
behavior for that admission without truncation or a receiver query.
The journal commits conservative intent before publishing receiver-tagged legacy
pending rows and before registering the cancellable HTTP child. A notification
cancelled during preparation therefore recovers the saved full fallback without
querying the receiver again.

## Parity and consumer impact

| Producer/consumer | State and adoption boundary |
|---|---|
| Apple scheduled compatibility API | Native personal-API opt-in, v2 atomic plans and legacy/profile execution implemented; integration/runtime qualification explicit |
| Android scheduled compatibility API | Same personal-API outcome for profile/legacy workers and legacy recovery; private versioned authority wrapper; integration/runtime qualification explicit |
| Shared Rust core | No change; possible future shared selector after contract review; HTTP and secure stores stay native |
| CLI/direct MCP | No wire/output change, no receiver queries |
| Website | No released availability claim; maintained native setup guides describe source integration and qualification limits |
| External Obsidian plugin | Daily files/keys unchanged; no preflight consumer or fixture change |
| Receiver owners | Must explicitly implement/authenticate this independent v1 query before opt-in is usable |

The product-capability inventory records the implementation and remaining native
qualification gates. Both platforms keep the same personal-API scope and defaults;
managed rotating clinic credentials are unsupported in both. This source status
does not claim released availability or successful device/backend acceptance.

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

No device/backend scenario was run. iPhone/Android receiver QA and visual
acceptance are unrun. Host tests
exercise real native plan/journal/runtime/pending-store code with inert SDK seams,
including restart, partial acknowledgement, configuration changes, valid empty
selection and corruption preservation. Full application compilation remains a
separate queued gate. These tests do not prove native scheduler runtime, TLS/proxy/
compression behavior or background delivery on a device.
Passing the reference suite alone does not complete issue 170. Native opt-in is
implemented in source; issue completion and released availability require queued
application compilation and explicit runtime acceptance of both platforms.
The host tests do not substitute for those gates.
