# ADR-0001: Shared Rust export core through UniFFI

- **Status:** Accepted
- **Date:** 2026-07-25
- **Decision owners:** Apple, Android, and shared-core maintainers
- **Scope:** Post-capture export modeling, projection, and serialization

## Context

Health.md has two deployed native exporters with intentionally different public contracts. Apple emits `healthmd.health_data` v7. Android must preserve its frozen compatibility v4 output while also supporting the additive Android analytical v5 profile. The native implementations contain overlapping normalization, aggregation, projection, and serialization logic, but HealthKit and Health Connect expose different APIs and data models.

A shared implementation must reduce duplicated domain logic without pretending that the platforms have identical capabilities. It must also preserve files consumed by Obsidian, scripts, spreadsheets, archives, the website reference, and the external Obsidian plugin. A refactor is not permission to change a public schema or direct-device protocol.

Milestone 0 records the contract only. It does not move implementation code, change fixture bytes, or change any public export schema.

## Decision

Health.md will introduce a Rust shared core and expose its coarse-grained API to Swift and Kotlin with UniFFI. Migration happens independently for each output profile and platform. Native code remains available during comparison and rollback.

### Ownership boundary

Native Swift and Kotlin own:

- HealthKit and Health Connect authorization, queries, cursors, provider selection, and runtime capability checks;
- platform SDK objects and their conversion into explicit, versioned input DTOs;
- app lifecycle, background work, scheduling, UI, persisted user settings, secrets, and telemetry consent;
- destination selection, sandbox/security-scoped access, atomic file commits, sharing, and platform error presentation;
- platform-only capture behavior and the decision to omit data that the platform cannot provide.

The Rust core owns, after receiving owned DTO values:

- validation of the language-neutral input boundary;
- shared units, deterministic ordering, calculations, aggregation, and normalization where semantics truly match;
- profile-specific projections, compatibility aliases, exact number/date rendering, CSV quoting, JSON ordering, Markdown/frontmatter rendering, and output byte assembly;
- explicit Apple-only and Android-only model variants instead of fake cross-platform placeholders;
- deterministic diagnostics returned as typed values rather than platform exceptions.

Rust returns an output plan containing logical paths, media types, bytes, and non-sensitive diagnostics. Native code validates the plan against its destination policy and performs writes. Rust does not call HealthKit, Health Connect, filesystem, keychain/keystore, network, UI, or direct-device transport APIs.

The UniFFI surface is a narrow request/result boundary. It must not expose HealthKit or Health Connect objects, retain native references, depend on callbacks for record-by-record streaming, or make one FFI call per sample. Inputs and outputs use owned, bounded batches and explicit cancellation/checkpoint values. Panics may not cross the FFI boundary.

### Output profiles

The shared core treats these as separate named profiles:

| Profile | Platform | Public contract | Migration requirement |
|---|---|---|---|
| `apple-v7` | Apple | `healthmd.health_data` v7 | Preserve every currently shipped format byte-for-byte for equivalent controlled input. |
| `android-frozen-v4` | Android | Frozen compatibility `healthmd.health_data` v4, including API/plugin behavior and historical aliases | Remains frozen. Rust may reproduce quirks but may not “correct” them. |
| `android-analytical-v5` | Android | Additive local analytical v5 | Preserve its exact existing output while retaining Android-native fields, exact source values, and provenance. |

A profile is selected explicitly; it is never inferred from app version, platform, or available fields. Android analytical v5 does not upgrade API v1 or plugin-facing frozen v4 output. Apple v7 does not become the implicit Android contract. New profiles require a contract review and must not reuse a shipped profile identifier.

### Metric registry authority

`packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json` is the canonical source for stable semantic IDs, unchanged native selection IDs, category/order metadata, source units and aggregation labels, archive-only/default flags, output keys and compatibility aliases, and explicit platform-backed/unavailable decisions. Its exact canonical bytes are hashed into core build diagnostics and pinned by `packages/contracts/manifest.json`.

Swift and Kotlin retain localization resources, SDK type resolution, OS/feature checks, authorization flows, and persisted settings. Deterministic generation projects the Rust registry into thin native catalog constants so watch and JVM host builds do not need to load an FFI library at static initialization. iOS, macOS, and Android instrumentation tests load the same snapshot through one coarse UniFFI call and shadow-compare every native projection. Semantic IDs never replace persisted native IDs or public output keys.

### Semantic input authority

`packages/contracts/semantic-input/v1/` defines the internal post-capture `healthmd.semantic_input` v1 envelope and typed canonical-result v1 model. Native adapters convert one already-captured `HealthData` tree into bounded coarse JSON batches with exact epoch-second/nanosecond timestamps, nullable source offsets, calendar offsets, finite binary64 bit patterns, canonical integers, allowlisted unit IDs, explicit owner dates, and opaque platform-extension retention tokens.

Native SDK aggregates cross as singular `sdk_aggregate` facts; Rust does not replace HealthKit/Health Connect provider statistics with naïve raw-sample sums. Rust validates profile/registry/selection attribution, filters disabled records and coupled blood-pressure dependencies, normalizes reviewed units, reduces deterministic observations, derives shared BMI, and computes Apple civil ISO-week/month/year roll-ups. Rust sessions are ephemeral and cancellation-aware. During M4 they run only in tests or non-authoritative shadow preparation; public renderers remain native and unchanged.

### Render input and artifact-plan authority

`packages/contracts/render-input/v1/` defines the separate internal boundary from one completed semantic result to exact profile bytes. The boundary carries frozen presentation settings, resolved labels, output-key presentation facts, retained native-extension payloads, and destination-neutral path policy. Rust rejects any presentation fact or extension token that was not accepted by the M4 result.

Three separate profile modules render Apple v7, Android frozen v4, and Android analytical v5. Rust also owns strict relative-path/collision validation, normalized write modes, managed Markdown merge content, Apple roll-up files, individual-entry/Daily Note mutation content, and exact byte-aware API envelopes. Android API v1 requires the frozen-v4 profile. Large source layers use bounded stream objects that return each chunk immediately and retain only checksum/sequence state.

Rust returns deterministic artifact IDs, paths, media types, write modes, bytes, lengths, and hashes. Native code still performs destination reads/commits, ZIP, HTTP, authentication, and durable transport. M5 keeps native exporters authoritative; M6 compares complete plans in shadow before any profile-specific authority change.

### Independent internal versioning

The following versions advance independently:

1. native-to-core input DTO version;
2. Rust canonical model version;
3. UniFFI API/ABI version;
4. output profile implementation revision;
5. Rust crate/package version;
6. public export schema versions;
7. direct-device protocol versions.

Every request declares its input DTO version and output profile. Every result declares the core/model and profile implementation revisions used to create it. Unsupported versions fail before output is written.

An internal version bump does not imply a public schema bump. A public key, type, meaning, unit, aggregation, ordering guarantee, or serialized representation change follows that profile's public schema policy. Conversely, a crate release or UniFFI regeneration must not alter output bytes. This ADR does not change Apple v7, Android v4/v5, or direct protocol v1/v2.

### Generated artifact policy

Rust source, UniFFI interface/configuration, lockfiles, generation scripts, contract fixtures, and generator version pins are canonical inputs.

Generated Swift/Kotlin binding source and required C headers/module maps may be checked in only as component-scoped, lockstep snapshots when a native build needs them. They are never edited by hand. CI regenerates them with the pinned toolchain and fails on a diff. Generated files carry their generator/version notice and remain under the consuming component, not `packages/contracts`.

Compiled libraries, XCFrameworks, AARs, target directories, and other platform binaries are build or release artifacts and are not committed. Release automation must build them from the tagged Rust source, publish checksums, and retain enough provenance to reproduce the artifact. A native release may consume only an artifact produced from the same reviewed shared-core revision declared by that component. Changing this source/generated/binary policy requires a follow-up ADR.

### Runtime migration modes

Mode is selected per platform and output profile, not globally:

- **`legacy`**: the native exporter is authoritative and Rust output is not delivered. This is the default until shadow prerequisites pass.
- **`shadow`**: native output is delivered. Rust receives the same captured input and settings, but its output is used only for a local comparison. Rust may not write files, alter export success, enqueue retries, or change user-visible output.
- **`rust`**: Rust output is delivered. The legacy path may still run as a non-authoritative comparator during the rollback window.

Production mode controls must fail closed to `legacy` when missing, unknown, or incompatible with an input/profile version. A mode change cannot reinterpret persisted user settings or silently choose a different output profile.

### Byte-for-byte comparison

Migration equivalence means exact bytes, not parsed or semantic equality. For the same controlled input and settings, comparison includes:

- the complete ordered output-plan path list;
- every file's byte length and SHA-256 digest;
- JSON key/order and number rendering;
- CSV headers, row order, quoting, delimiters, and line endings;
- Markdown, frontmatter, whitespace, and trailing newlines;
- deterministic diagnostics that are part of a public file.

Tests and shadow runs inject or capture all nondeterministic inputs, including clock, calendar timezone, locale, identifier source, source ordering, and profile revision. The comparator does not parse and re-encode output, trim whitespace, normalize Unicode/newlines, ignore fields, or apply numeric tolerances. If bytes cannot be made deterministic, the nondeterministic value must be moved into the explicit input contract; it is not allowlisted away.

A mismatch records profile, implementation revisions, lengths, hashes, and the first differing byte offset. It must not log or persist health payload bytes, paths containing user data, credentials, or field values. Test fixtures remain synthetic. Shadow mismatches are visible to engineering diagnostics but do not fail a user's legacy export.

### Promotion, rollback, and deletion

Promotion is profile-specific. `shadow` may become `rust` only when:

1. contract fixtures and representative synthetic edge corpora compare byte-for-byte in CI;
2. native component tests cover success, empty, unsupported, partial, cancellation, and malformed-input behavior;
3. beta shadow evidence has no unexplained mismatch for that profile;
4. performance and memory remain within that component's approved limits; and
5. the profile owner records approval and confirms downstream consumer coverage.

Before legacy deletion, `rust` must be the default for at least one generally available release of that platform, the runtime mode switch and legacy implementation must remain usable for the entire rollback window, and no unresolved correctness, crash, performance, or comparison regression may exist. Apple v7, Android frozen v4, and Android analytical v5 satisfy and lose their gates independently. Success for one profile cannot justify deleting another profile's path.

Rollback before deletion is an immediate profile-scoped switch to `legacy`; it does not rewrite files, migrate schema labels, or require a public version change. If Rust has emitted incorrect files, remediation is an explicit re-export using the same public profile. Rollback after legacy deletion requires shipping a repaired or reverted app build; therefore deletion requires a separate reviewed change with recorded gate evidence and an updated operational runbook.

Deletion removes the corresponding native projection/serializer only. Native capture adapters, platform-only capability handling, destination commits, comparison fixtures, and shipped profile tests remain. No legacy path is deleted on a date alone, to reduce binary size alone, or while unexplained differences are waived.

## Consequences

- Common post-capture behavior can converge while source access remains native and platform-aware.
- Three existing output contracts remain explicit instead of being collapsed into one “cross-platform” schema.
- During migration, apps temporarily carry both implementations and pay CPU/memory cost in shadow mode.
- Exact compatibility requires preserving some historical formatting and profile-specific behavior in Rust.
- Native builds gain a pinned code-generation step and reproducibility checks, but generated binaries do not enter source control.
- Platform parity is maintained as a product inventory, not inferred from equal metric counts.

## Follow-up gates

Implementation milestones must add the Rust crate, versioned DTO/schema definitions, synthetic equivalence corpora, UniFFI generation checks, native adapters, and profile-scoped mode controls in separately reviewed changes. Any change to public outputs or direct protocol bytes is out of scope and follows the existing contract-version workflows.
