# Shared-core M6 rollout baseline

Status: local rollout infrastructure implemented; production promotion gates remain open

This baseline records the implementation boundary for profile-scoped legacy/shadow/Rust export authority. It does not claim TestFlight or Play internal evidence and does not change Apple `healthmd.health_data` v7, Android frozen v4, Android analytical v5, or direct protocol v1/v2.

Operational controls and rollback procedure are defined in the [M6 rollout runbook](shared-core-m6-rollout-runbook.md).

## Engine authority and pins

Apple and Android now model the three closed modes:

- `legacy`: native plan is authoritative;
- `shadow`: native and Rust plan from the same frozen input; only native is returned;
- `rust`: Rust plan is authoritative only for an explicitly admitted operation that requires no native rendering.

Mode is profile-scoped. Committed release defaults remain legacy. Unknown, conflicting, unavailable, or incompatible configuration for **new** work fails closed to legacy before capture. Durable settings snapshots separately record that authority was resolved: a nil pin plus the frozen-authority marker is explicitly legacy and cannot inherit a later rollout default. A durable nonlegacy pin takes precedence over current defaults and cannot silently downgrade during resume.

Durable pins contain the public profile/schema, core API, semantic input, canonical model, render input, artifact-plan, registry version/hash, semantic/render profile revisions, source revision provenance, and explicit IANA calendar timezone. Source revision is provenance rather than an equality gate; versioned contracts govern compatible resume across rollback builds.

Apple build controls:

- `HEALTHMD_APPLE_EXPORT_ENGINE_SHADOW`
- `HEALTHMD_APPLE_EXPORT_ENGINE_RUST`

Android build controls:

- `EXPORT_ENGINE_ANDROID_FROZEN_V4`
- `EXPORT_ENGINE_ANDROID_ANALYTICAL_V5`
- `EXPORT_ENGINE_API_V1_FROZEN_V4`

Release builds ignore runtime overrides. Debug/internal tests may inject profile-scoped overrides.

## Exact artifact plans

Both native layers use immutable destination-neutral plans matching `healthmd.artifact_plan` v1:

- ordered artifact identity;
- validated relative path;
- media type;
- write mode;
- exact bytes;
- byte count;
- SHA-256;
- total byte count.

Plan constructors revalidate identity, digest, bounds, traversal, control characters, and portable Unicode/case collisions. Generated UniFFI records are copied into handwritten native models before use.

Comparators check count, order/identity, path, media type, write mode, length, SHA-256, and exact bytes without parsing or normalization. Production diagnostics expose only fixed profile/revision, mismatch dimension, ordinal, counts, lengths, hashes, and stable error codes. Payloads, health values, dates, IDs, user paths, URLs, credentials, filenames, and arbitrary exception descriptions are absent. First differing byte offsets are debug/internal-only.

Production composition now records a second, narrower evidence shape for rollout accounting. Apple and Android persist bounded aggregate counters for completed comparisons, exact matches, mismatch operations/reported counts and fixed dimensions, plus fixed Rust-failure codes. Apple emits one explicit comparison-completed denominator event even when plans match. Android already emits one comparison result per completed dual render. Stores cannot represent payload-derived lengths/hashes, operation/date/device IDs, paths, endpoints, or arbitrary errors; corrupt evidence resets observability and never affects authority. Apple uses its app defaults domain and `SharedCoreShadow` unified-log category. Android uses `noBackupFilesDir/shared-core-shadow-evidence-v1.json` and log tag `HealthMdSharedCore`; persistence is dispatched to IO and never blocks export callers.

## Side-effect barrier

Native executors use the one-way state sequence:

`planned -> materialized -> committing -> completed|failed`

Authority and bytes are locked before the first directory creation, atomic file mutation, HTTP request, or direct-transfer side effect. Once committing begins, no engine switch, rerender, alternate commit, or regenerated retry body is allowed.

## Implemented production seams

### Apple

- Foreground local/vault ranges freeze one renderer authority decision and one explicit calendar timezone before their first HealthKit read, capture the complete successful range, materialize one bounded semantic/render plan under one request/session identity, and cross one commit barrier for all selected daily artifacts.
- Weekly, monthly, and yearly foreground roll-ups expand and capture their frozen source windows, share that range plan and barrier, and filter unselected source-day daily artifacts before exact shadow comparison and commit. Non-archive summary-only operations use the same plan with an empty selected-daily set, preserving roll-up-only and terminal no-data result semantics. This summary-only overwrite subset is the first Apple pure-Rust admission: Rust derives and validates every expected period/format path from the completed semantic result, commits only Rust bytes, and does not call the native daily/roll-up renderers or profile-document adapters. Legacy and unsupported work retain the established path.
- Matching side-effect-free single-day preview.
- API v1 and provider/external-record v2 shadow preparation, exact byte/day batching, and native upload commit. The production API preview reuses its already-captured sample records and exact destination/timezone/provider inputs through the same destination-free preparation seam; authoritative prepared body bytes drive payload sizing without any upload. Apple API Rust authority is not admitted because exact v7 daily records still require native profile documents; a new Rust request resolves before capture/core work and a persisted Rust pin fails closed.
- Generated direct-file daily summaries in shadow mode and non-archive weekly/monthly/yearly ranges when no native-only provider sidecar is present. Compatible pinned jobs decode their immutable capture spool once, separate requested daily owners from roll-up source days, and stage all artifacts through one range plan before persisting the transfer manifest. Summary-only roll-up ranges may use pure Rust authority; daily-output ranges remain shadow/legacy until generic Apple v7 bytes are independent. Missing roll-up source captures and provider sidecars discovered after pinning fail closed. New jobs that can emit provider sidecars freeze explicit legacy before renderer-pin capture.
- iOS local scheduled/recovery work captures a range-capable pin and routes the frozen operation through the same one-plan daily/roll-up barrier as foreground work. macOS local scheduling loads selected and roll-up source records from its native synced cache, preserves selected cache misses as retryable, and commits compatible pinned output through the same range barrier.
- Durable connected-Mac corpus protocol v3 advertises received-range authority without changing partition bytes. V3 peers may pin compatible non-archive roll-up and summary-only jobs. Before each partition ACK, Mac binds the app-private session directory by device/inode, uses descriptor-relative no-follow source/journal operations, rejects rebound or symlinked source directories and linked files, synchronizes every protected source file/directory entry, and binds completed items or partial prefixes to byte counts and SHA-256. It performs no per-partition range destination writes, rejects more than 400 semantic owner dates, and incrementally enforces the 100,000-record, 64 KiB-record, 32 MiB-record-total, 4,096-record-batch, and 1 MiB-batch contracts without imposing those limits on segmented transport-wrapper bytes. It materializes one stable-identity selected plan, explicitly preserves daily-versus-roll-up roles, then protects the exact data-dictionary/artifact bytes and immutable digest before the first destination mutation. A bounded v4 receiver journal binds the selected-root path plus device/inode and checkpoints the dictionary plus ordered artifact frontier. Production commit uses descriptor-relative `O_NOFOLLOW` traversal, canonical descriptor paths with `RENAME_NOFOLLOW_ANY`, live root/parent namespace revalidation, raw-byte inspection, same-directory atomic replacement, and file/ancestor-directory synchronization; its non-cancellable one-file transaction reinspects before adoption and covers write, exact readback, and durable frontier advancement. Relaunch adopts only an exact durable unacknowledged write, skips verified acknowledged writes, and resumes without either renderer; source/finalization corruption, symlink/hard-link traversal, acknowledged byte drift, path collisions, or same/different-path folder rebinding fail closed. The structurally validated terminal result/ACK is persisted before descriptor-relative cleanup; terminal persistence failures preserve resumable state, strict-raw partition replay reconciles only exact protected spools, and strict-raw terminal bytes remain in a hash-bound protected spool across process death and lost final acknowledgements for the fixed recovery window, allowing the durable control-response store to be revalidated or repaired on every replay. Cleanup is replay-safe, strict-raw retained counts survive restart, and duplicate finalization must match the complete partition frontier. Ambiguous old `.finalizing` range journals are rejected, while old `.open` work is integrity-bound and durably migrated. Negotiated v1/v2 peers keep roll-up jobs legacy for old/new compatibility, and the older non-corpus stream/whole-job paths remain legacy for roll-ups.

- Connected-corpus protocol v4 leaves v3 range authority and bounded partition framing unchanged while replacing only the private application-item wrapper with deterministic `HMDCITEM` tokens. Strict-raw canonical documents are copied between protected disk spools and selectively decoded on Mac, avoiding a second whole-item `Data`/JSON object; negotiated v1-v3 application bytes remain exact.

Apple shared-core work runs off MainActor. Native code retains HealthKit/provider capture, security-scoped destinations, data-dictionary writes, atomic writes, ZIP, URLSession/authentication, progress, billing, history, and lifecycle.

### Android

- Simple daily aggregate folder output and matching preview.
- API v1 frozen-v4 preparation, failure-only batches, exact UTF-8 byte/day batching, preview, and native OkHttp upload. One selected-envelope validator now gates preview, durable journal creation, and foreground commit before the first POST: it checks canonical UTF-8/JSON, fixed schemas/profile/source/export clock/timezone, contiguous complete requested-date partitions, record/failure owner coverage and counts, and configured day/byte bounds. No path guesses or ordinal-only ownership are accepted.
- Scheduled occurrence/retry and direct-job pin persistence. Scheduled API operations write exact prepared bodies to an app-private no-backup journal before the first POST, persist a contiguous acknowledged-batch frontier after each response, and resume only unresolved bytes without Health Connect recapture or rerender. Pending dates retain the operation ID; acknowledged failure-only dates are detached so a later capture retry becomes a new operation.
- Compatible nonlegacy scheduled folder operations now freeze the exact SAF tree URI, canonical settings hash, engine pin, ordered owner dates, capture outcomes, every selected overwrite artifact, and a whole-plan digest before binding the first destination document. App-private no-backup journals advance each artifact through prepared, binding-intent, document-bound, and exact-byte-acknowledged states. Restart verifies document identity and SHA-256, skips acknowledged files, resumes every unresolved immutable artifact without Health Connect or either renderer, and retains the journal until history/pending-date reconciliation. A known pending operation cannot recreate a missing journal. Missing final documents are materialized through a deterministic journal-owned hidden staging name, exact-byte readback, and strict same-folder rename so a create-before-checkpoint crash can resume without adopting an unrelated final document. Cancellation before commit writes nothing; after the active precommit checkpoint, exact commit/frontier advancement finishes non-cancellably. Corruption, path/media/order mutation, path collision, duplicate/renamed/ambiguous documents, changed folder binding, or byte drift fails closed. Durable scheduled history uses a Room-unique reconciliation key derived from target, operation ID, and attempted owner-date set so a crash between history insertion and pending-state update replaces rather than duplicates that attempt. Legacy, append/update, Daily Note, individual-entry, and raw-snapshot folder operations remain on their existing native paths.
- Generated direct-file daily summaries for supported simple operations. Direct staging validates canonical UTF-8 and writes authoritative artifact-plan bytes without replacing them with decoded String bytes.

Android semantic/render work runs on `Dispatchers.Default`; provider reads and SAF/OkHttp remain native. API v1 is permanently frozen-v4 even when local output selects analytical-v5.

## Whole-operation legacy gates

A new operation remains wholly legacy when the selected Rust seam cannot yet preserve every requested artifact or side effect. There is no per-format engine mixing.

Current explicit gates include combinations involving:

- Apple daily-output and API Rust authority while exact Apple v7 records still require native profile documents (shadow remains supported);
- append/update destination materialization outside the implemented overwrite seam;
- Daily Note destination reads/merge and individual-entry output;
- Apple archive/ZIP and lossless attachment packaging;
- Apple weekly/monthly/yearly roll-ups inside ZIP archive and older non-corpus connected surfaces that do not yet use an equivalent range planner;
- native provider sidecars in generated-file operations;
- sparse non-contiguous API scopes that cannot be represented safely as one closed render-input range;
- operation size beyond bounded inline/stream contracts.

A persisted nonlegacy pin that encounters an unsupported or incompatible seam fails safely; it is not delivered through legacy under a Rust identity.

## Durable migration

Apple:

- `ExportSettingsSnapshot` freezes settings, pin, and source calendar timezone. Codable engine values are strict inside a present pin: unknown or explicit `legacy` values and malformed bounded fields make restoration fail closed, while a genuinely absent pin remains the only durable legacy representation. Tolerant parsing is reserved for mutable rollout configuration.
- `PendingExportRequest` optionally carries that snapshot; missing means the old legacy/current-settings behavior.
- Retry/residual requests preserve the original snapshot.
- Connected corpus manifests/jobs carry the pin.
- Generated-file direct journal v2 carries the pin and accepts v1 as legacy.
- iOS local scheduled background execution resolves the range surface before persistence and routes a pinned frozen snapshot through one operation-level async plan instead of per-day planner calls. macOS local scheduling resolves the same surface and builds one range from immutable cache snapshots. Old or explicit nil-pin work keeps the legacy path.
- Export history can retain health-free pin provenance.

Android:

- Scheduled occurrences and pending retries carry canonical bounded engine-pin metadata; old payloads preserve their exact legacy signatures. Folder retries may additionally carry a bounded exact-plan operation ID; old requests decode with no folder journal and retain legacy behavior.
- Corrupt present nonlegacy metadata fails instead of disappearing during WorkManager resume.
- Direct pending state persists the pin before provider capture.
- Direct job journal v2 validates pending-to-final pin continuity; missing version/pin is v1 legacy.
- Execution-only pins are not mutable DataStore preferences and override current rollout defaults during resume. Scheduled/direct execution also carries a transient frozen-authority marker so old or explicitly legacy nil-pin work cannot inherit a new default.
- Export-history database v5 adds a nullable unique reconciliation key. Existing rows migrate with `NULL`; durable scheduled attempts derive a stable key from target, operation ID, and attempted owner dates so only crash replays of the same reconciliation replace one row.

[M7](shared-core-m7-protocol-baseline.md) subsequently upgrades Apple and Android direct journals to
version 3 to add an independent direct-protocol pin. Version 2 retains its M6 export-engine pin but
decodes as legacy protocol work.

Rollback releases continue packaging Rust and both engine adapters so pinned work can resume.

## Compatibility evidence

M6 builds on immutable M5 revision-1 render evidence:

- render differential SHA-256 `59fee27e488f76da193d8013fba4ff82d76887fe12df45439ea7de286feb4bc3`;
- Android native request replay SHA-256 `e989e50d2fc81cec95d938a19c40a6ce39428cfc83e45eb23b69703b656037bf`.

The revision-2 managed-Markdown safety repin changes only the internal configuration revision field. Its current hashes are `1181e644cd224c8c0e4126133890830f5af9ec8c39995db6e90a471fae608c7d` for the render differential and `0f6f8ce69bf0babddff87e4e4d1990b96633a754a10043a37475dc3d29b9bfef` for the Android native request replay.

Focused native tests cover mode/policy failure, pin compatibility and legacy decoding, artifact validation, every comparator dimension, shadow native authority, pure Rust summary-only roll-up authority, whole-range identity and byte comparison, planning-before-write/upload, immutable retries, no post-side-effect fallback, API failures/external records, scheduled/direct migration, and diagnostic privacy. The Apple pure-Rust suite fault-injects the native-renderer preflight, disables native profile documents at the adapter boundary, compares customized all-metric weekly/monthly/yearly bytes, checks every nonempty format subset including Bases-only paths, covers a non-UTC IANA timezone, and rejects incomplete Rust plans. New unsupported Apple Rust work becomes explicit legacy without loading the core; persisted unsupported Rust pins fail closed. API-35 instrumentation also runs the concrete daily semantic/render production adapter through the packaged library for both Android profiles and compares all four planned artifact bytes and paths to the Kotlin oracle. On both platforms, only shadow renders native and Rust candidates; admitted Rust authority never invokes a native renderer.

Historical exporter schema/signature fixtures remain unchanged.

## Gates that cannot be inferred from local tests

Production authority is not promoted by this baseline. The following require recorded real-world evidence:

- TestFlight and Play internal shadow runs with zero unexplained differences;
- physical Pixel 7 folder/API/schedule/direct/process-restart testing;
- physical iPhone local/API/connected/direct/interruption/resume/protected-data testing;
- approved wall-time, peak RSS, main-thread, binary-size, ABI/slice, and symbolication budgets;
- actual pinned Obsidian/plugin and website visualization consumer approval;
- PHI review of beta logs, crashes, and diagnostic artifacts;
- profile-owner and release-owner approval.

Legacy remains compiled through M6 and for at least two stable releases after any later Rust-default promotion. M8, not M6, owns deletion.
