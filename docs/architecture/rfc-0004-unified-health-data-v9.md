# RFC-0004: Unified cross-platform `healthmd.health_data` v9 proposal

- Status: **Proposed — contract review only; production writers remain blocked**
- Proposal date: 2026-08-13
- Owners required for acceptance: Apple, Android, CLI, contracts, shared core, website, product/support, security/privacy, and Obsidian integration owners
- Related: [RFC-0002](rfc-0002-unified-health-data-v8.md), [RFC-0003](rfc-0003-apple-health-data-v8-provider-sections.md), [ADR-0001](adr-0001-shared-rust-uniffi-core.md)

## Proposed decision

Adopt a language-neutral **unified cross-platform contract proposal** under `healthmd.health_data` schema version **9**, profile `unified-cross-platform-v1`.

Do not introduce a second `healthmd.health_data` v8 grammar. RFC-0003 already assigns v8 to the Apple daily grammar. Existing consumers may dispatch only on `(schema, schema_version)`, so a new profile discriminator cannot make two v8 grammars safe.

The normative proposal is in [`packages/contracts/proposals/unified-health-data-v9/`](../../packages/contracts/proposals/unified-health-data-v9/). It defines:

- a common owner-date and frozen-calendar envelope;
- exact tagged values and explicit statistic/unit identity;
- mandatory primary-source provenance;
- resource-level capture completeness;
- independently versioned Apple and Android platform sections;
- reuse of typed WHOOP v1 on either platform;
- explicit SDNN/RMSSD separation;
- historical-profile dual-read and migration requirements.

This RFC proposes the contract. It does **not** authorize a production writer, default switch, fixture rewrite, API bump, direct-protocol bump, or release.

## Relationship to earlier RFCs

### RFC-0002

This proposal reopens RFC-0002's deferred design work, but does not claim its rollout prerequisites are complete. RFC-0002 remains authoritative for the required release/rollback evidence, external-consumer validation, dual-read strategy, privacy review, and product/support approval until this RFC is accepted with those receipts.

If RFC-0004 is accepted, it supersedes RFC-0002's candidate **version number and shape**, not its compatibility cautions.

### RFC-0003

RFC-0003 remains intact. Apple v8 and its historical fixtures continue to identify the Apple-specific grammar with typed WHOOP sections. Unified v9 is a new opt-in profile sourced from Apple v8 or Android v4/v5; it does not reinterpret Apple v8.

## Why a typed fact collection

Current public profiles intentionally differ in hierarchy, aliases, aggregation, units, source identity, timestamps, sleep ownership, provenance, and platform-native data. A merged flat object would either:

- claim false equivalence;
- preserve ambiguous historical keys;
- lose source meaning; or
- become a union in which absence cannot be distinguished from unsupported/failed capture.

Unified v9 therefore uses typed shared metric facts with exact value, canonical unit, explicit statistic, and provenance. Facts that cannot be mapped without loss remain in the matching platform section or source-fidelity contract.

## Ongoing product policy

This proposal is one application of the repository [Apple and Android unification policy](cross-platform-unification-policy.md). Future features should converge on the common contract whenever semantic equivalence is proven. A platform extension is an evidence-backed boundary for OS-specific data, not a default escape hatch or a substitute for implementing the other platform. Temporary one-platform gaps must be recorded as planned with a target; permanent differences must identify the OS/API or semantic limitation.

## Required invariants

1. Exactly one primary platform is present and agrees with the source profile and platform section.
2. Owner date, frozen IANA timezone, and exact half-open UTC boundaries are explicit.
3. Platform and typed-provider capture use the same frozen owner-day calendar.
4. Missing values are omitted and never fabricated as zero.
5. Successful empty capture is `complete` with `record_count: 0`.
6. Every shared metric has one semantic ID, statistic, canonical value/unit, and primary-source provenance.
7. HealthKit SDNN and Health Connect/WHOOP RMSSD use distinct semantic identities.
8. Provider data does not populate shared primary metrics in v9 profile revision 1.
9. v9 readers accept only nested platform/provider versions enumerated by the reviewed v9 schema. Future nested versions require explicit compatibility review and either a revised v9 reader policy or a new daily version; round-trip converters retain referenced canonical bytes or fail closed.
10. Historical Apple v5/v6/v7/v8 and Android v4/v5 bytes remain immutable.

## Rollout gates

Production writer approval requires all of the following evidence:

1. Apple and Android Rust export authority has completed its documented rollback window.
2. Two stable product release cycles have no unexplained output-profile differences.
3. Apple, Android, CLI, website tooling, and the pinned external Obsidian consumer can dual-read canonical v9 fixtures.
4. The mapping ledger has an approved initial metric set with unit, statistic, ownership, missingness, and provenance tests.
5. Capture completeness and platform-extension privacy/security reviews are complete.
6. Every durable job persists its selected public profile and safely resumes/retries it.
7. API receivers advertise and accept daily schema v9 without conflating it with envelope versions.
8. Product/support owners approve user-facing opt-in, dual-write, migration, and rollback behavior.
9. Historical readers/writers remain tested for the documented support period.
10. Apple, Android, contracts, CLI, shared-core, website, and external-consumer test receipts are attached to the acceptance change.

If these are not met, the schema remains a proposal and no production writer may emit it.

## Migration policy

- Readers ship before writers.
- Writers remain profile-explicit and opt-in initially.
- Existing defaults remain Apple v8, Android frozen v4 for API/plugin compatibility, and Android analytical v5 for applicable local exports.
- Dual-write uses separate destinations or deterministic filenames.
- API envelope, direct protocol, raw snapshot, HealthKit archive, semantic-input, and render-input versions remain independent.
- Reverse conversion to historical profiles is best-effort only where a reviewed mapping exists; it must not silently discard platform/provider data.

## Open approval work

- Approve or reject every initial mapping-ledger candidate.
- Specify exact Markdown, CSV, and Bases projection contracts and fixtures.
- Decide the compatibility window and user-facing profile selector.
- Decide unknown-extension byte-retention mechanics across Swift, Kotlin, Rust, and CLI.
- Test the external Obsidian plugin against Apple-origin and Android-origin fixtures.
- Determine whether Android API moves directly from v4 to v9 or stays v4 while local v9 is piloted.
- Determine whether Apple strict canonical `--raw` remains Apple-only when v9 is enabled; the proposal currently preserves that boundary.

## Rejection conditions

Reject or revise this proposal if:

- product requires two incompatible grammars under schema version 8;
- a shared metric mapping depends only on similar labels rather than semantic evidence;
- an implementation cannot preserve exact numbers or distinguish missingness/capture states;
- unknown extension handling would silently lose data;
- required dual-read consumers cannot be updated;
- privacy review rejects exposed provenance or platform payloads.
