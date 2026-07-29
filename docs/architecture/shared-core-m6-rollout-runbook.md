# Shared-core M6 rollout and rollback runbook

Status: implementation rollout support; production authority remains legacy

This runbook controls the profile-scoped migration from native deterministic exporters to the shared Rust core. It does not change Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5, or direct protocol v1/v2.

## Authority modes

Each output profile resolves exactly one mode before capture:

- `legacy`: native rendering is authoritative. Rust output is not delivered.
- `shadow`: the operation captures once and freezes one settings, timezone, clock, and identifier snapshot. Native and Rust render from that same snapshot. Only the native plan may be committed.
- `rust`: the Rust plan is authoritative only after the operation-specific admission gate proves that no native renderer is needed. Native remains compiled during the rollback window.

Missing, unknown, conflicting, incompatible, or unsupported configuration resolves new work to `legacy` before core loading or capture. Durable settings metadata records that the decision was frozen independently from the optional pin: frozen metadata with no pin is explicitly legacy and never inherits a later default. Codable engine parsing is strict inside a present durable pin; unknown or explicit `legacy` values and malformed bounded pin fields make snapshot/journal/manifest restoration fail closed. Tolerant unknown-to-legacy parsing applies only to mutable rollout configuration. A durable nonlegacy job uses its persisted engine/profile/core pin instead of current defaults; if that persisted Rust promise is outside the current pure-Rust admission, it fails closed rather than silently switching engines. A rollback build must continue packaging Rust so an already-pinned supported Rust job can resume.

## Build controls

Committed defaults remain `legacy` until release evidence is approved.

### Apple

Apple modes are selected per `apple_health_data_v7` profile with mutually exclusive Swift compilation conditions:

- `HEALTHMD_APPLE_EXPORT_ENGINE_SHADOW`
- `HEALTHMD_APPLE_EXPORT_ENGINE_RUST`

Defining both fails closed to `legacy`. Debug/internal builds may use `HEALTHMD_EXPORT_ENGINE_APPLE_HEALTH_DATA_V7` or the profile-scoped debug `UserDefaults` override. Release builds ignore runtime overrides.

### Android

Android modes are compile-time `BuildConfig` values sourced from Gradle properties or environment variables:

- `EXPORT_ENGINE_ANDROID_FROZEN_V4`
- `EXPORT_ENGINE_ANDROID_ANALYTICAL_V5`
- `EXPORT_ENGINE_API_V1_FROZEN_V4`

Allowed values are `legacy`, `shadow`, and `rust`; every other value becomes `legacy` during configuration. API v1 always uses the frozen-v4 profile. Debug/test builds may inject profile-scoped preferences; release builds ignore them.

Apple pure-Rust admission is currently limited to non-archive summary-only overwrite roll-ups on range-capable local, generated-direct, and connected-corpus surfaces without provider sidecars. Apple daily-output, preview, and API operations may run shadow but cannot select Rust authority while exact v7 daily records still require native profile documents. Do not broaden this predicate without independent exact-byte/path evidence and native-renderer fault-injection coverage.

## Promotion sequence

1. Run exact native/Rust contract fixtures and malformed/cancellation tests in CI.
2. Enable Android frozen-v4 shadow on the Play internal track.
3. Review health-free mismatch counts, crashes, latency, RSS, and AAB growth. Resolve every difference.
4. Repeat for Android analytical-v5, then promote each complete profile independently.
5. Enable Apple v7 summary shadow in TestFlight. Lossless archive authority remains gated until bounded-stream physical-device tests pass.
6. Review downstream Obsidian/plugin, website visualization, API, schedule, connected, direct, interruption, and resume evidence.
7. Record profile-owner approval before changing a release default to `rust`.

No operation may mix engines by format. An unsupported feature resolves the entire new operation to `legacy` before capture.

## Comparison and privacy

The comparator is byte-exact and ordered. It compares artifact count, identity, relative path, media type, write mode, byte count, SHA-256, and bytes. It never parses, trims, normalizes, or re-encodes output.

Production diagnostics may contain only:

- profile and fixed revisions;
- mismatch dimension and artifact ordinal;
- counts and byte lengths;
- one-way content SHA-256 values;
- stable health-free error codes.

They must not contain payload bytes, health values, dates, request/session identifiers, user paths, URLs, credentials, filenames, arbitrary exception descriptions, or source identities. First-differing-byte offsets are internal/debug-only.

### Collecting shadow evidence

Each completed dual render records one denominator event. Exact matches, mismatch operations/dimensions, and fixed Rust-failure codes are aggregated with saturating counters. Corrupt evidence may be reset and recollected; it must never change an export result.

- Apple internal logs: `log show --predicate 'category == "SharedCoreShadow"' --style compact`. The aggregate is stored under app-defaults key `HealthMd.sharedCore.appleShadowEvidence.v1`; internal diagnostics may call `ShadowExportEvidenceRecorder.snapshot()` or `reset()`. On macOS development installs, reset with `defaults delete com.codybontecou.obsidianhealth HealthMd.sharedCore.appleShadowEvidence.v1`.
- Android internal logs: `adb logcat -s HealthMdSharedCore:I`. On a debuggable internal build, inspect with `adb shell run-as com.healthmd.android cat no_backup/shared-core-shadow-evidence-v1.json` and reset with `adb shell run-as com.healthmd.android rm -f no_backup/shared-core-shadow-evidence-v1.json`. Internal diagnostics may instead call `AndroidShadowExportEvidenceRecorder.snapshot()` or `reset()`.

Collection output must be reviewed as counters only. Do not attach general device logs, user exports, app containers, or unrelated crash payloads to rollout evidence. A local exact-match aggregate is necessary but does not substitute for the TestFlight/Play, PHI, consumer, physical-device, or owner-approval gates.

## Commit barrier

Every destination executor follows `planned -> materialized -> committing -> completed|failed`.

Before `committing`, native code may read existing destinations and materialize append/merge behavior. Immediately before the first directory creation, file mutation, HTTP request, or direct-transfer side effect, transition to `committing`. From that point:

- never select another engine;
- never rerender;
- never retry with newly generated bytes;
- retry only persisted immutable bodies, spools, or artifacts;
- preserve per-artifact receipts/frontiers.

Shadow mismatch or Rust shadow failure never changes native success, retry, history, quota, or user-visible output.

Android API delivery validates every selected body before preview, durable persistence, or a foreground POST. Validation proves canonical UTF-8/JSON, fixed envelope/daily schemas, source/profile clock and timezone, an ordered complete requested-date partition, exact record/failure owner coverage and counts, and configured day/byte bounds. Scheduled delivery then persists every exact body and owner-date scope before the first POST and advances only a contiguous acknowledged-batch frontier. A process restart resumes from that frontier without provider recapture or renderer invocation. Generic HTTP endpoints still provide at-least-once, not exactly-once, delivery: if the server accepts a request and the process dies before the local frontier commit, the same immutable body is retransmitted. Advancing before a response would risk permanent data loss and is forbidden.

For compatible Android scheduled folder work, do not bind or create a SAF document until the complete selected operation plan, fixed capture failures, and immutable whole-plan digest are atomically visible in `noBackupFilesDir/scheduled-folder-export-v1`. Each artifact first persists its binding intent. An existing final document must retain its exact ID; a missing final is written to a deterministic journal-owned hidden staging name, verified by exact hash, and strictly renamed within the same parent before acknowledgement. On restart, an acknowledged artifact is verified and skipped; a bound unresolved artifact may receive only its persisted bytes, and every unresolved owner date must participate in the resume. A known pending ID with no journal, missing/renamed/replaced/duplicate documents, hash or metadata drift, folder-URI changes, corrupt journals, and cross-day path collisions fail closed. Cancellation before the commit checkpoint writes nothing; exact commit and frontier persistence after that checkpoint run non-cancellably. Keep the operation ID on unresolved pending dates and delete the journal only after history and pending-date reconciliation. These app-private journals contain exact export bytes: never collect, log, or attach them as rollout diagnostics, and include their lifecycle/storage treatment in the PHI review.

## Rollback

Rollback changes the profile default for **new** operations to `legacy`. It does not rewrite user files, change schemas, reinterpret settings, or alter already-persisted engine pins.

1. Set the affected profile's next-work default to `legacy`.
2. Keep the Rust library, bindings, Rust engine adapter, and pin validation in the release.
3. Resume persisted Rust jobs with their exact pinned profile and core evidence. If the packaged core cannot satisfy the pin, pause/fail safely; do not deliver legacy bytes under a Rust identity.
4. Verify scheduled retries, API bodies, connected manifests, and direct spools reuse persisted immutable data.
5. If incorrect files were delivered, provide an explicit re-export workflow under the same public schema. Do not silently mutate prior output.

Legacy implementations remain compiled for at least two complete stable release cycles after Rust becomes the default, and are deleted only by the separately reviewed M8 gate.

## Evidence checklist

A profile cannot be promoted on local fixture parity alone. Record:

- exact CI fixture/shadow results;
- TestFlight or Play internal build/version and mode;
- physical Pixel 7 and iPhone folder/API/schedule/direct interruption and resume results;
- wall time, peak RSS, main-thread responsiveness, and binary-size deltas;
- ABI/slice and symbolication checks;
- external Obsidian/plugin and website visualization compatibility;
- diagnostic/crash artifact PHI review;
- profile-owner and release-owner approval;
- rollback exercise for new work and pinned in-flight work.
