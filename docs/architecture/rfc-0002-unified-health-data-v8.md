# RFC-0002: Unified `healthmd.health_data` v8

- Status: **Deferred for a unified cross-platform schema; partially superseded by RFC-0003's Apple-only v8**
- Decision date: 2026-07-26
- Owners: Apple, Android, CLI, contracts, website, and Obsidian integration owners
- Related: [ADR-0001](adr-0001-shared-rust-uniffi-core.md), [RFC-0004](rfc-0004-unified-health-data-v9.md)

## Decision

> **2026-08-12 update:** [RFC-0003](rfc-0003-apple-health-data-v8-provider-sections.md) approves an Apple-only v8 for typed provider sections. It does not unify or relabel Android. This RFC remains authoritative for the deferred unified cross-platform schema described below.
>
> **2026-08-13 update:** [RFC-0004](rfc-0004-unified-health-data-v9.md) and `packages/contracts/proposals/unified-health-data-v9/` reopen the contract design as a v9 proposal. A unified grammar cannot reuse v8 after Apple v8. This RFC's rollout gates remain in force until RFC-0004 is accepted with evidence.

Health.md will **not** introduce a unified public v8 schema as part of the Rust/UniFFI migration or legacy-engine cleanup.

Apple `healthmd.health_data` v7, Android frozen v4, and Android analytical v5 remain independent supported profiles. Moving deterministic semantics and rendering into Rust does not relabel, merge, or version those contracts. Historical fixtures remain immutable.

A future unified successor may proceed only as a separate cross-platform contract project after:

1. Rust export authority has completed its rollback window on Apple and Android;
2. two stable release cycles have passed with no unexplained profile differences;
3. external Obsidian, CLI, website, and automation consumers can dual-read the proposal;
4. capture completeness and platform-extension semantics are reviewed independently of renderer migration; and
5. product and support owners approve a user-visible migration plan.

Deferral is an affirmative compatibility decision, not an unresolved implementation task.

## Why a unified successor is not a cleanup format

The shipped profiles differ intentionally:

- Apple v8 represents HealthKit summaries, Apple-only types, source archives, medications, state of mind, Apple date/roll-up behavior, and typed provider sections.
- Android frozen v4 preserves compatibility with the historical Apple/plugin-facing shape.
- Android analytical v5 adds reviewed Android-native facts and exact source detail.
- HealthKit HRV SDNN and Health Connect RMSSD are related but non-equivalent.
- Platform SDK aggregations, provenance, authorization, capture completeness, and owner-date behavior are not interchangeable.

A single serializer cannot erase those distinctions without changing public meaning. Treating a shared Rust implementation as evidence that the public contracts are already unified would conflate code reuse with semantic equivalence.

## Producers and consumers

Any unified successor proposal must enumerate and test every producer and consumer.

### Producers

- Apple iOS local, API, scheduled, connected-Mac, and direct generated-file exports.
- Apple macOS received/continued exports and roll-ups.
- Android local SAF, API, scheduled, automation, history retry, and direct generated-file exports.
- Shared Rust semantic/render core.
- CLI extraction or conversion commands that produce canonical health data.

### Consumers

- Existing Apple app versions reading historical exports.
- Existing Android app versions and persisted retries/jobs.
- Standalone Health.md CLI on macOS, Linux, and Windows.
- `packages/contracts` validators and interoperability fixtures.
- Health.md website documentation, samples, and generated reference pages.
- `CodyBontecou/health-md-visualizations` and its Obsidian users.
- User-authored Dataview queries, Bases files, scripts, dashboards, API receivers, and archival tools.
- Direct-protocol peers carrying generated files without interpreting their public schema.

External user scripts are not discoverable in full, so backward-compatible dual-read and explicit version markers are mandatory.

## Historical candidate shape before RFC-0004

This section records design constraints, not an approved schema.

This earlier constraint list informed the v9 proposal. A unified contract should contain:

- `schema: "healthmd.health_data"` and a new unambiguous version (`schema_version: 9` in RFC-0004);
- explicit `source_platform` and source-app/profile provenance;
- a shared summary block containing only reviewed semantically equivalent metrics;
- tagged metric values with stable semantic identity, public presentation key, unit, reducer, and capture status;
- an explicit capture-completeness model distinguishing unavailable, unauthorized, unsupported, failed, empty, and not requested;
- a tagged source archive rather than an untyped merged record bag;
- explicit `apple`, `android`, and future provider extension blocks;
- exact source timestamps, offsets, owner date, and calendar timezone where relevant;
- distinct HRV statistic identities rather than a shared ambiguous `hrv` value;
- profile-independent provenance and versioned extension namespaces;
- deterministic ordering/canonicalization rules suitable for Rust, Swift, Kotlin, and CLI consumers.

Platform extensions must be ignorable without being lossy for consumers that understand them. Shared summary fields must not be populated by guessed cross-platform equivalence.

## Migration and dual-read requirements

If a unified successor is approved later:

1. Add a new language-neutral schema and fixtures; never rewrite v4/v5/v6/v7 fixtures.
2. Keep readers for Apple v5/v6/v7 and Android v4/v5 for a documented support period.
3. Ship dual-read before any v8 default writer.
4. Decide whether writers offer explicit old-profile export, dual-write, or a one-time opt-in; do not silently change existing jobs.
5. Persist the selected public profile with every scheduled, connected, and direct generated-file job.
6. Keep API versions explicit. A v8 file schema does not implicitly change API envelope or direct protocol versions.
7. Publish field-by-field mappings, non-equivalences, unit rules, omission behavior, and extension handling.
8. Run the actual pinned Obsidian/visualization and CLI consumers against unified-successor fixtures.
9. Provide user-facing migration guidance for vault queries, Bases, scripts, and receivers.
10. Treat removal of old writers/readers as a later compatibility decision with telemetry-free support evidence.

## Versioning analysis

The current shared-core work changes internal contracts only:

- semantic input/result;
- render input/artifact plan;
- registry/profile metadata;
- engine and durable-job pins.

None changes a public key, type, unit, meaning, order, or serialized representation. Therefore no public schema bump is justified.

A unified successor necessarily changes public modeling and must bump the public schema even if some individual rendered values happen to match historical bytes. Because Apple v8 now exists, the unified successor must use v9 or a distinct schema identity.

## Rejected alternatives

### Rename the Rust canonical result to v8

Rejected. The canonical semantic result is an internal bounded interchange model, not a user-facing export contract.

### Make Android analytical v5 the shared schema

Rejected. It contains Android-specific source structures and does not model Apple-only capture or compatibility obligations.

### Add `source_platform` to existing v7/v5 in place

Rejected. Adding a public field changes immutable contracts and historical signatures.

### Delete old profiles when native code is removed

Rejected. Implementation ownership and public schema support are independent. Rust must continue rendering historical profiles byte-for-byte.

## Acceptance of the reopened proposal

Accepting RFC-0004 requires a reviewed change that supplies:

- recorded M6/M8 release and rollback evidence;
- the proposed unified schema and canonical fixtures;
- complete producer/consumer impact analysis;
- a dual-read/write plan;
- external consumer test results;
- privacy/security review for source archives and provenance;
- explicit owner approvals.

Until then, the authoritative decision is to preserve shipped Apple v8 and Android v4/v5 without a production unified writer. The v9 schema, ledger, and fixtures are review artifacts only.
