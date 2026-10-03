# History authorization investigation — issue 172

Refs https://github.com/CodyBontecou/health-md/issues/172

## Status and limits

This is a **partial investigation**, not implementation or device qualification.
No limited-history assessment, reachable authorization warning, or history-state
consumer field is shipped by this change. No physical reproduction was performed.
The Linux source-only lane cannot validate Apple SDKs or HealthKit behavior; only
GitHub-hosted Apple CI runs the tests and SDK probe. Retain run URLs and exact head
SHA in the PR/report before claiming any check passed.

## Verified public API semantics

Apple's public [earliestAuthorizedSampleDate(for:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestauthorizedsampledate(for:))
DocC data endpoint returned HTTP 200 during this investigation. Its declaration is:

```swift
func earliestAuthorizedSampleDate(for types: Set<HKObjectType>) async throws
    -> [HKObjectType: Date]
```

The documentation lists introduction at **27.0** on iOS, iPadOS, Mac Catalyst,
macOS, visionOS, and watchOS. Availability in documentation does not establish
availability in the CI SDK or certify a physical device.

The documented semantics are materially narrower than the issue's requested
`full_history` state:

- Call after requesting authorization. Returned entries identify limited access
  with a known earliest readable date, independently for each requested type.
- The method derives dates from store availability and the chosen authorization
  time frame. Do not substitute the oldest query result for this API result.
- **No entry is ambiguous:** full read access, denied read access, or limited
  access with no specific earliest readable date. An empty dictionary cannot
  prove full access, even with nonempty sample-query results.
- Boundaries are evaluated against a sample's **end date**. A readable sample can
  start before the boundary; keep its original timestamps. Data before the
  boundary is **unknown**, not absent or zero.
- A failed API request throws. Failure is not a successful empty assessment.
- `earliestPermittedSampleDate()` is a framework-wide limit, not the person's
  authorization boundary. `authorizationStatus(for:)` describes **sharing/write**
  authorization; it cannot repair the read-privacy ambiguity.

Consequently an assessment using only this API may report limited, unknown, or
API-unavailable history. It must **not manufacture full access** from omitted
entries, empty data, a successful authorization request, or a successful query.
The acceptance criterion for proven full access needs clarification or a separate
verified public source of that evidence. A future explicit user assertion would
need its own provenance, not masquerade as OS-verified authorization.

## Deterministic source findings and partial changes

`SystemHealthStoreAdapter.queryEarliestSampleDate` issues an ascending one-sample
query. `HealthKitManager.discoverEarliestHealthDataDate` takes the minimum readable
date and tracks query/catalog failures. Neither calls the boundary API.

The internal `isQueryComplete` name now expresses that limited guarantee.
`isComplete` remains a source-compatible alias. The Connected Mac, portable typed
query, portable raw export, and portable file producer check `isQueryComplete`;
request handling, dates, serialized bytes, journal/resume semantics, and empty
query behavior are unchanged. This does **not** fix authorization coverage.

Focused behavior tests in `HealthKitManagerTests` characterize:

- successful empty readable data is query-complete, with no earliest date;
- a readable type plus an empty sibling retains the readable date and is
  query-complete;
- a failed sibling preserves readable data but is not query-complete.

Existing catalog-gap, specialized-type, and activity-summary tests remain in the
same suite. These are injected discovery tests, **not** boundary-assessment tests.
The filesystem-synchronized test target includes them; Apple CI `test-ios` runs
`make test-ios`, and `test-macos` runs `make coverage`. The SDK diagnostic in
`prepare-shared-core` typechecks the public call against the selected iPhone
Simulator and macOS SDKs without executing it. A failed probe is reported as a
failed typecheck with compiler diagnostics, not concealed as runtime verification.

Shortcuts documentation no longer promises an OS-27 `full_history` gate or
nonexistent limited/unverified error messages. The separate release-status
correction is owned by [PR 177](https://github.com/CodyBontecou/health-md/pull/177)
for issue 175; avoid duplicating its response-field correction here. That draft
PR is not proof the claims are corrected on main yet.

## Platform outcome and version impact

The neutral outcome is: know when requested historical coverage is constrained,
retain readable data, and never label unobservable earlier data as absent.

Android already feature-gates `PERMISSION_READ_HEALTH_DATA_HISTORY` in
`HealthConnectPermissionPolicy` and inspects granted permissions in
`HealthConnectRawDataProvider.capabilities`. The raw record ledger maps missing
history permission to `history_permission_missing`. See
[Android permission documentation](https://github.com/CodyBontecou/health-md/blob/main/apps/android/docs/features/health-connect-permissions.md)
and [Health Connect historical-read documentation](https://developer.android.com/health-and-fitness/guides/health-connect/develop/read-data#read-older-data).
Android permission state is not equivalent to Apple's intentionally ambiguous
per-type omitted entries; do not alias it to Apple full-history evidence.

No capability is staged by this investigation, so no inventory availability is
changed. No daily schema, archive, API envelope, direct protocol, shared-core
version, fixture, or persistent data changes are made. Future implementation
must record Apple as planned with a concrete SDK/device target and represent OS
semantics explicitly in `packages/contracts/product-capabilities.json`.

Affected future producers/consumers: Apple local exports and Shortcuts, Connected
Mac context acquisition and bundled MCP, portable raw/file/query paths, shared
Rust protocol/core and CLI/MCP, Android, website, and the external Obsidian reader.
Decide a separately versioned platform coverage extension or negotiated protocol
capability before exposing new fields. Do not rewrite shipped Apple v8/Android
v4/v5 meanings or reinterpret capture `complete` as full-history permission.

## Remaining implementation and verification plan

1. Retain SDK probe evidence. Integrate the public API only with a verified SDK
   declaration and runtime availability checks, without dynamic/private selectors
   or guessing SDK support from Swift compiler version.
2. Build a type-scoped assessment independent of oldest-readable discovery.
   Test mixed boundaries, omitted entries (including known full/denied fixtures
   both projecting to unknown), empty data, API errors, unsupported runtimes,
   unassessed dependencies, and changes in selected metric scope.
3. Show an actionable, accessible warning on the reachable Export/All Time path
   and context refresh. Explain partial history and how to review Health access;
   do not claim granting full access can be verified from an empty dictionary.
4. Propagate truthful type/date limitations to local export, Mac context, and
   portable consumers without changing explicit requested bounds or dropping
   successful siblings. Preserve overlapping sample timestamps, immutable pending
   jobs and old peer/runtime behavior; negotiate any new wire capability.
5. On a supporting iPhone seed synthetic older/newer samples for at least two
   types. Compare limited/full/denied access, no-data types, and an overlapping
   sample whose start precedes but end follows the boundary. Exercise All Time
   and an explicit pre-boundary range through local export, Mac context refresh,
   portable typed queries, raw export, and file export. Repeat on an older runtime
   and with an older peer. Retain health-free OS/build, settings, warning,
   coverage, reconnect/resume, and accessibility receipts; no secret/health logs.

Stop at a partial draft until SDK integration, the full-state semantic decision,
consumer versioning, and physical-device evidence are available. The issue stays
open; passing discovery tests or an SDK probe cannot satisfy those requirements.
