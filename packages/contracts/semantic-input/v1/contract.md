# `healthmd.semantic_input` v1

Status: internal canonical contract
Public export schemas affected: none

This contract is the bounded native-to-Rust handoff after HealthKit or Health Connect capture and before public rendering. It is independently versioned from Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5, and direct protocol v1/v2.

## Ownership boundary

Native code continues to own SDK queries and provider aggregation, permissions, runtime feature checks, source selection and deduplication, calendar offset resolution, localization, persistence, lifecycle, destinations, networking, and rendering. Rust owns deterministic validation, selection filtering, dependency retention, internal unit normalization, shared derivation, daily reduction, and Apple period roll-ups.

An OS aggregate is represented as `kind: "sdk_aggregate"`; Rust must not reconstruct it from samples. A semantic shadow run consumes the same captured model as the legacy run and never repeats capture.

## Session configuration

`healthmd.semantic_session_config` selects exactly one profile:

- `apple_health_data_v8`
- `android_frozen_v4`
- `android_analytical_v5`

The caller supplies exact registry/version and profile-revision pins, an IANA calendar timezone, native persisted selection IDs, disabled profile output keys, an explicit platform-extension retention policy, and optional Apple roll-up periods. Profiles are never inferred. Android period requests fail with `unsupported_semantic_operation`.

Limits are core-owned: 256 KiB configuration, 1 MiB per batch, 4,096 records per batch, 64 KiB per record, 512 selected IDs, 100,000 records/32 MiB per session, 400 owner dates, 32 extension references per record, and 128 UTF-8 bytes per retention token.

## Exact time

An exact timestamp contains:

- `epoch_seconds`: canonical signed decimal string;
- `nanoseconds`: `0...999999999`;
- nullable `source_utc_offset_seconds`, which is never inferred;
- required `calendar_utc_offset_seconds`, resolved natively for the configured IANA timezone at that instant.

Ordering uses epoch seconds, nanoseconds, then source ordinal. Every record has an explicit ISO civil `owner_date`; Rust never derives ownership from the source offset. This preserves Apple sleep ownership and Android provider behavior.

## Exact numbers and units

Numbers are tagged as raw finite IEEE-754 binary64 bits (`16` lowercase hex digits), canonical signed decimal integers, or canonical unsigned decimal integers. NaN and infinity are rejected. Negative zero and integers above JavaScript's safe range survive the FFI handoff.

Units use allowlisted internal IDs such as `meter`, `ratio_0_1`, `percent_0_100`, `microgram`, and `degree_celsius`. Public labels (`kg/m²`, `µg`, `mcg`, and localized temperature labels) are renderer metadata and are not accepted as semantic unit IDs.

Missing is the absence of a fact. It is never encoded as zero. Rust performs only reviewed conversions, including ratio-to-percent, meter-to-kilometer/mile, and seconds-to-minutes/hours.

## Records and filtering

Each batch declares ordered `owner_dates`, including captured days with no facts, so period coverage is not inferred from metric presence. Each record carries a stable opaque ID, canonical source ordinal, owner date, registry semantic ID, unchanged native selection IDs, direct/dependency attribution, typed kind/value, output projection key, reducer, optional interval/weight/attributes, and extension references. Record IDs and extension retention tokens derive from owner date plus stable native source identity, never a batch index or in-batch position. Native bounded-batch builders enforce the core limits, thread batch indexes and source ordinals, and preserve identity when the same captured model is rechunked.

The semantic ID must be backed by the selected profile and the matching native selection ID must be present. The output key and selection attribution must match that profile's registry projection. Disabled output keys are filtered in Rust even when native capture supplied their facts, and extension references are returned only when the session explicitly enables platform-extension retention. Blood-pressure pair records are retained only when both selectors are enabled. When BMI is selected without a direct BMI fact, weight and height are retained as calculation-only dependencies; their own outputs remain suppressed unless independently selected. A record is reduced only after Rust selection filtering.

`source_ordinal` is strictly ascending across batches. Owner dates are ascending within each batch and nondecreasing across batches; a boundary date may repeat when one captured day is split by a native bounded-batch builder. Record IDs cannot repeat. Latest uses exact timestamp followed by ordinal as a deterministic tie-break.

## Extensions

Platform structures that cannot safely be generalized stay native. The semantic envelope carries only a namespaced/versioned retention token and its selection attribution. Examples include:

- `apple.healthkit_archive`
- `apple.source_provenance`
- `android.health_connect_context`
- `android.phr_resource`
- `android.workout_route`

Unknown extension namespaces are retained in deterministic order but cannot affect shared calculations. Tokens and payload values never appear in health-free diagnostics.

## Results and cancellation

Each batch returns canonical compact JSON. Non-final batches return `processing` with no deliverable days. The final batch returns the core API and profile revision, typed daily values, Apple period values, and retained extension tokens. Native callers stage all results until `completed`.

Cancellation is idempotent and observed before parsing, every 64 records, and before reductions. The next processing call returns a terminal `cancelled` result with no days and clears retained records. Calls after completion/cancellation fail with `semantic_session_terminal`.

## Reduction rules

The closed daily rules are pass-through, sum, average, minimum, maximum, latest, count, duration sum, weighted average, union, histogram, and linear time-of-day average. SDK aggregate facts are singular; duplicate/conflicting SDK facts for one day/output fail closed.

Shared derivation includes BMI from enabled weight and height facts when no direct BMI fact exists. Workouts preserve source record IDs and use explicit duration weights. State-of-Mind source records may attribute to multiple independent views so disabling one view does not alter another view's population.

Apple roll-ups use supplied civil owner dates for ISO weeks, calendar months, and years. Missing days are ignored, zero remains a value, lower later VO2 is still latest, workout averages use daily workout-minute weights, and `days_counted` counts only days containing that key. The configured IANA label is returned unchanged; timezone offsets do not redefine owner dates.

## Canonicalization and diagnostics

Canonical result JSON is UTF-8, compact, and recursively key-sorted. Arrays retain contract order. Cross-language tests compare exact result bytes and SHA-256.

Production diagnostics may include only versions/profile, counts, hashes, and JSON-pointer-style mismatch paths. They must never include record IDs, retention tokens, dates, values, source identities, payloads, or parser details.
