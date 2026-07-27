# Shared core M4 semantic baseline

Date: 2026-07-25
Status: implemented, legacy public renderers remain authoritative

## Version pins

| Contract | Version |
|---|---:|
| UniFFI/core API | 3 |
| `healthmd.semantic_input` | 1 |
| canonical semantic result | 1 |
| metric registry | 1 |
| profile implementation revision | 1 |
| persisted core state | 1 (unchanged) |

The internal contract is specified under `packages/contracts/semantic-input/v1/`. It does not change Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5, or direct protocol v1/v2.

## Boundary

Swift and Kotlin continue to capture through HealthKit and Health Connect/provider APIs. The native semantic adapters consume one frozen `HealthData` tree and never repeat a query. SDK-produced daily statistics cross as singular `sdk_aggregate` facts. Raw synthetic observations exercise Rust reducers without replacing provider overlap/deduplication behavior.

Rust validates exact epoch-second/nanosecond timestamps, nullable source offsets, calendar offsets, finite binary64 bits/canonical integers, internal units, profile/registry pins, persisted selection attribution, declared owner dates, disabled output keys, explicit extension-retention policy, and bounded sequence state. Rust owns filtering, coupled blood-pressure retention, reviewed unit conversion, BMI derivation, daily reducers, deterministic latest ties, extension-token retention, and Apple ISO-week/month/year roll-ups. Already-captured SDK daily aggregates remain singular pass-through facts, but their types, units, output attribution, and retention policy are still validated in Rust.

Opaque extension side tables retain HealthKit archive records, Android granular/provider/workout/PHR structures, and unknown future namespaces without crossing payload objects over FFI. Their retention tokens and semantic record IDs are derived from owner date plus native source identities rather than batch positions, so automatic rechunking does not change identity and repeated inventory/provenance identities remain session-unique across days. Results and production shadow differences expose only typed internal data or health-free hashes/counts/pointer paths as appropriate.

## Bounds and cancellation

- configuration: 256 KiB
- batch: 1 MiB
- records per batch: 4,096
- one record: 64 KiB
- selected IDs: 512
- session: 100,000 records and 32 MiB
- owner dates: 400
- extensions per record: 32
- retention token: 128 UTF-8 bytes

`CoreSemanticSession.cancel()` is idempotent and lock-independent. Rust probes before parse, every 64 records, between day reductions, and between period reductions. Cancellation returns a terminal canonical `cancelled` result and clears staged records. Native runners execute synchronous FFI away from the main actor/UI dispatcher, translate a Rust `cancelled` result into native cancellation, and stage all output until completion. Swift and Kotlin provide deterministic bounded-batch builders that thread batch indexes/source ordinals, enforce per-record/batch/session limits before FFI, and preserve stable record and extension-token identity across rechunking.

## Differential corpus

`differential-v1.json` is synthetic and covers:

- missing versus explicit zero and negative-zero bits;
- nanoseconds, null source offsets, `+05:45`, explicit `-05:00`/`-04:00` DST transitions, and DST-owned civil dates;
- ISO week/year and leap-month bounds;
- deterministic latest/VO2 behavior;
- blood-pressure coupling and sleep-stage selection;
- Android ratio-to-percent handling and explicit v4/v5 profiles;
- State-of-Mind independent views;
- workout duration weighting and record identity;
- batch-boundary invariance;
- unknown extension retention;
- non-finite, sequence, bounds, cancellation, and terminal-state failures.

The canonical fixture is pinned in `packages/contracts/manifest.json` and mirrored byte-for-byte into the publishable Rust crate. Rust verifies exact result SHA-256 values. Swift executes every case through the packaged XCFramework. Kotlin verifies canonical input encoding, and Android instrumentation processes adapter output through all packaged native layers.

## Rollout state

M4 does not deliver Rust-rendered files. Existing native exporter signatures and bytes remain the compatibility authority. M5 adds renderers/artifact plans; M6 adds explicit `legacy`, `shadow`, and `rust` authority modes.
