# Shared core M5 rendering baseline

Date: 2026-07-25
Status: implemented; native production exporters remain authoritative until M6

## Version pins

| Contract | Version |
|---|---:|
| UniFFI/core API | 4 |
| semantic-result embedded API value | 3 (immutable v1 bytes) |
| `healthmd.render_input` | 1 |
| artifact plan | 1 |
| profile renderer revision | 1 |
| canonical model / registry | 1 |

The render contract is under `packages/contracts/render-input/v1/`. It is internal and does not change Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5, direct v1/v2, or API envelope versions.

## Boundary

A bounded render session receives one completed M4 semantic result plus presentation facts and retained extension payloads from the same frozen native capture. Swift/Kotlin do not query HealthKit, Health Connect, or providers again. Profile, revision, registry hash, semantic session ID, owner date, accepted output key, extension token, and selection overlap must all agree before rendering.

For exact profile fidelity, a day may include an attested presentation document snapshot: ordered JSON nodes with lossless numeric lexemes, typed five/six-column CSV rows, and a line-oriented Markdown body. Its `semantic_output_keys` must equal the complete accepted semantic output set for that day. Swift/Kotlin freeze these facts from the already-filtered native capture; Rust owns JSON/CSV/newline serialization and rejects stale or mismatched output-key attestations. This preserves Android granular/native fields and Apple archive structures without allowing Rust semantic IDs to replace public keys.

Rust owns deterministic format assembly, escaping, ordering, path planning, managed Markdown merge behavior, individual-entry/Daily Note mutation content, Apple roll-up rendering, API envelope construction, exact byte batching, and artifact checksums. Native code still owns locale lookup, source-side extension extraction, security-scoped URLs/SAF, destination reads, atomic writes, ZIP containers, HTTP/authentication, durable transport, history, UI, and lifecycle.

`apple_v7.rs`, `android_frozen_v4.rs`, and `android_analytical_v5.rs` are separate profile entry points. Android analytical v5 cannot construct API v1 output; API v1 accepts only a frozen-v4 semantic/render session.

## Artifact plans and paths

Every inline item has a domain-separated deterministic artifact ID, strict POSIX relative path, media type, normalized write mode, exact bytes, byte count, and SHA-256. `update` becomes `markdown_merge` only for Markdown; structured formats overwrite. Paths reject absolute forms, backslashes, NULs, empty/dot/traversal components, duplicate targets, and collisions after Unicode normalization and case folding.

Apple daily formats retain their raw-name order (`csv`, `json`, `markdown`, `obsidian_bases`). Android retains enum order (`markdown`, `obsidian_bases`, `json`, `csv`). Bases receives its configured suffix only when it would collide with selected Markdown.

## Bounds and streaming

| Item | Limit |
|---|---:|
| configuration | 256 KiB |
| completed semantic result | 32 MiB |
| render batch | 2 MiB |
| facts per batch | 4,096 |
| owner dates | 400 |
| artifacts | 4,096 |
| one ordinary inline artifact | 8 MiB |
| one indivisible API envelope | 32 MiB |
| all inline artifact bytes | 32 MiB |
| stream item | 1 MiB |
| stream total | 2 GiB |

Large source archives and attachments use `CoreLosslessArtifactStream`. Raw chunks, JSON-array items, and RFC 4180 rows are returned immediately. Rust retains only framing state, item/byte counts, and incremental SHA-256; it never retains a second complete archive buffer. A planned stream is created with request/session/profile, validated path, media type, and write mode; finalization returns the same domain-separated artifact identity, byte count, and checksum shape as an inline plan item, without retaining content. Native code writes chunks into its existing private spool or ZIP pipeline.

## Evidence

Canonical render differential SHA-256 at the original revision-1 baseline:

`59fee27e488f76da193d8013fba4ff82d76887fe12df45439ea7de286feb4bc3`

The revision-2 managed-Markdown safety repin changes only the internal configuration revision field; its current differential SHA-256 is `1181e644cd224c8c0e4126133890830f5af9ec8c39995db6e90a471fae608c7d`.

It covers every format for all three profiles, exact path/order/content/hash/write-mode plans, Apple formatting, Android v4/v5 discriminators, update behavior, and frozen-v4 API planning. Rust replays the canonical fixture from the publishable crate mirror and compares every output byte.

Independent pre-cutover byte oracles are frozen directly from production native exporters:

- Apple v7: `53e119fd851b794bae5894705ee540b1a845b5b925217c840250d989202e951a`
- Android v4/v5: `f6b738aab833c19ab96900593f838084e029afb86d2c11ee5a84d0310487f7b1`
- Android native request replay at revision 1: `e989e50d2fc81cec95d938a19c40a6ce39428cfc83e45eb23b69703b656037bf`
- Android native request replay repinned to revision 2: `0f6f8ce69bf0babddff87e4e4d1990b96633a754a10043a37475dc3d29b9bfef`

The Apple corpus contains default summary, imperial, custom frontmatter/template, and lossless archive cases in all four formats. Packaged Rust output matches every byte for all three cases. The Android corpus contains frozen default, frozen alias/native granular, analytical granular, and analytical imperial cases in all four formats; a replayable Kotlin presentation-request mirror proves all 16 Rust outputs against independent native bytes on every Rust CI host. Swift/Kotlin tests call only the production legacy renderers to guard oracle bytes; Rust never generates or rewrites those expected outputs. Historical Apple and Android structural signatures remain unchanged.

Apple weekly, monthly, and yearly roll-ups match all four native format bytes and all 12 native paths for the full synthetic day. API evidence covers Apple compact v1, Apple connected-provider v2 (including raw slash behavior), Android frozen-v4 v1 with failed dates, failure-only/scoped batches, and day/encoded-byte partitioning. Profile-specific managed Markdown merge is compared directly with the shipped Swift and Kotlin mergers, including Apple's preamble-preserving Daily Note mode. Planned streams are exercised through packaged UniFFI on both platforms.

Packaged XCFramework and Android instrumentation tests process native adapter output through the full UniFFI render session, verify all four formats and exact plan descriptors, and exercise bounded stream framing and Markdown merge. M6 adds profile-scoped legacy/shadow/Rust engine selection and compares the complete native oracle plan before any authority switch.

## Rollout state

M5 introduces no production renderer call from `VaultManager`, `PreparedHealthDataExport`, `ExportRepositoryImpl`, direct generated-file producers, or API runners. Existing native exporters still deliver user-visible bytes. No fallback or authority policy is added here; M6 owns capture-once shadow execution, profile gates, durable engine pins, cutover, and rollback. Operational controls and evidence requirements are defined in the [M6 rollout/rollback runbook](shared-core-m6-rollout-runbook.md).
