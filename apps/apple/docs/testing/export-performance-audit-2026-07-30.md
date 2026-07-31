# Export performance audit — 2026-07-30

## Scope and invariants

This audit covers Apple local files, ZIP packaging, API Endpoint, connected Mac corpus, and direct CLI export paths, with emphasis on schema-v7 lossless capture. Optimizations must preserve:

- summary calculations and calendar ownership;
- every canonical HealthKit record, relationship, diagnostic, attachment byte, and query status;
- deterministic JSON/CSV values and ordering;
- cancellation, atomic destination writes, durable journals, and resume behavior;
- the public export schema and direct protocol versions.

The changes below are byte-compatible internal optimizations. They do not require an export-schema bump.

## Baseline evidence

Physical-device measurements already recorded in [Local export performance instrumentation](./export-performance.md) show that HealthKit dominates a one-day lossless export. The latest listed run completed 2,314 HealthKit queries in 3.431 seconds, followed by a 225 ms daily write and 3.706 seconds total wall time. Attachment metadata accounted for 1,702 queries and 1.941 seconds of cumulative query time.

The existing measurements also show that higher/dynamic attachment concurrency can make performance much worse because HealthKit throttles. Concurrency changes therefore require physical-device validation, not simulator-only timing.

A new opt-in dense lossless benchmark exercises real canonical archive serialization. An initial local macOS Debug run with 1,792 canonical records and 6,055,161 JSON/CSV output bytes measured 420.22 ms when re-filtering an already-selected archive and 403.29 ms when reusing capture-applied selection. The latest hosted Debug run after the streaming cutover measured 1,609.82 ms, 1,574.27 ms, and 1,587.04 ms for regular buffered compatibility, already-selected buffered compatibility, and already-selected file artifacts respectively. Absolute Debug timing varies substantially; the stable result is that the file-first path no longer adds a whole-document materialization penalty.

A separate file-backed test rendered a 32 MiB attachment into 89,483,839 exact JSON/CSV bytes. Per-format peak resident deltas were 1,867,776 bytes for JSON and 1,015,808 bytes for CSV, with 1.306 seconds total rendering time. This is synthetic macOS evidence, not a substitute for a 256 MiB physical-iPhone run.

## Implemented optimizations

### 1. Combine average/minimum/maximum HealthKit statistics

Heart rate and six vital types previously issued separate `HKStatisticsQueryDescriptor` requests for average, minimum, and maximum values. The adapter now requests the selected discrete statistics together and reads the same `HKStatistics` quantities from one result. A fully selected day reduces these 21 summary queries to seven without deriving values from raw samples or changing units. Each operation still requests only the statistics needed by the selected metrics. If a combined descriptor fails for a nonterminal reason, the code falls back to the prior ordered queries so already-available partial values and diagnostics are preserved; cancellation, timeout, and device-lock failures do not retry.

### 2. Sliding bounded canonical-query window

`HealthKitManager.fetchHealthKitRecordArchive` previously submitted ordinary canonical queries in fixed batches of four. If one request was slow, the next batch waited even while up to three query slots were idle.

The scheduler now replenishes one request whenever one finishes. It still creates at most four child tasks and remains under the operation-wide four-query controller. Query results are still consumed later in deterministic selection-plan order, so completion order cannot affect archive bytes.

### 3. Reuse selection-filtered render preparation

`HealthKitManager` already applies the exact metric selection before returning a day, but local and API paths filtered the complete `HealthData` again before serialization. Re-filtering traverses the canonical dependency graph and rebuilds archive projections.

The capture-aware paths now:

- build one `PreparedHealthDataExport` from the already-selected day;
- reuse it for local loose-file writes and ZIP staging;
- use an already-selected API encoder after `HealthKitDailyCapture` applies selection;
- retain the filtering encoder for callers that do not have this proof.

This also prevents ZIP mode from rebuilding the same export snapshot in `VaultManager` and `LocalArchiveSpool`. Compact API records now use `toJSONDataThrowing` directly instead of creating a complete UTF-8 `String` and converting it back to `Data`.

### 4. Remove redundant dense-record sorting in CSV

`HealthKitRecordArchive` sorts UUID-backed records in every initializer, including decode and filter paths. CSV now consumes that normalized array directly instead of sorting the full record set a second time, and it reuses one configured canonical `JSONEncoder` across all UUID-backed record rows.

### 5. Make repeated-view relationship merging linear

Canonical record and external-record merges previously used repeated array `contains` scans while adding relationship edges. Relationships are now hashable internally, and merges use a membership set while preserving the exact first-seen array order. This removes a quadratic hotspot in dense workout/correlation graphs without changing canonical sorting or bytes.

### 6. Reduce temporary ZIP I/O and copies

Local ZIP staging files use unique private temporary paths and are not visible to a consumer until their write completes. They now use one direct write instead of an unnecessary atomic temporary-copy/rename.

`ZipArchiveWriter` file producers already read at the configured chunk size. The writer now accepts that bounded `Data` directly instead of creating a second `subdata` copy for every file-read chunk. A defensive split remains for future oversized producers.

### 7. Add a true lossless serializer benchmark

`ExportPipelineBenchmarkTests` previously measured compatibility time series but did not include `healthkit_record_archive`. It now reports dense lossless JSON/CSV preparation through `HEALTHMD_LOSSLESS_EXPORT_BENCHMARK` and file-backed attachment RSS through `HEALTHMD_FILE_BACKED_ATTACHMENT_BENCHMARK`.

### 8. Add exact bounded artifact sinks and serializers

`ExportArtifactIO` provides memory, file, and output-stream sinks with incremental SHA-256, exact byte counts, cancellation, private permissions, cleanup leases, and producer-based atomic destination commits. POSIX file iteration uses one reusable 128 KiB buffer so `FileHandle` autorelease behavior cannot grow with the source file.

`CanonicalJSONStreamEncoder` preserves Foundation and canonical key ordering, pretty-print spacing, scalar formatting, slash behavior, and base64 bytes. Daily JSON lazily injects canonical archives without a second archive object graph. CSV emits rows directly and quote-escapes canonical JSON incrementally while preserving the previous control-character sanitization. Existing `String` and `Data` entry points are memory-sink compatibility wrappers.

### 9. Cut production consumers over to immutable files

Vault aggregate writes, local ZIP staging, ZIP producers, native artifact plans, plan comparison, API envelopes, and API commit now consume file artifacts. API uploads use `URLSessionUploadTask` from a stable file and bound response bodies separately. Preview/test compatibility accessors still materialize bytes explicitly.

### 10. Make attachment ownership file-backed and durable

HealthKit attachment capture writes protected restricted files and hashes incrementally instead of accumulating `Data`. The internal metadata case serializes under the existing public `data` tag, so schema-v7 JSON/CSV bytes do not change. Connected-corpus token streams and direct captured-day journals preserve blob files across durable spool boundaries; the direct journal is version 4 and still reads versions 1–3. Ephemeral capture files are released only after all copied models and durable consumers release their leases.

### 11. Remove CITEM temp-file and partition-read amplification

The disk-backed Codable token encoder previously created a temporary file for every scalar and repeatedly copied nested composites. Exact bytes were bounded, but the one-day physical run exposed 317 seconds of file amplification and 2.31 GB of attributed file-cache footprint. Individual scalar and composite nodes remain capped at 256 KiB, while the complete live encoder graph has a fixed 16 MiB inline budget. Child containers release their budget when ownership transfers to a parent, preventing both gigabyte keyed graphs and the cascading temp-file regression caused by a non-reclaiming global budget. Arrays spill to restricted files after the budget is exhausted. The token grammar, key order, lengths, and durable CITEM header are unchanged.

Artifact outputs opt out of Darwin file caching, partition SHA-256 uses one reusable 256 KiB POSIX buffer, and transfer reads retain a negotiated maximum of four in-flight 512 KiB chunks with ordered hash acknowledgements. Atomic files, per-partition hashes, acknowledgement frontiers, and resume journals remain unchanged.

### 12. Bound Foundation JSON temporaries and reuse selected snapshots

Dense exact JSON used `JSONSerialization` for each Foundation-compatible numeric fragment. Without inner autorelease scopes, those short-lived objects accumulated until a complete 27.7 MB render retained 383.6 MB on macOS. Lazy Foundation and Codable array elements now drain independently. Safe strings up to 128 KiB bypass byte-by-byte escaping when no escaping is required, and repeated safe object keys use a bounded 1,024-entry encoded-key cache. Direct CITEM rendering now passes the already-selected prepared export instead of filtering the decoded lossless archive again. Exact physical-output SHA-256 checks cover both JSON and CSV.

Rejected experiments remain rejected: concurrent CSV/JSON rendering was slower and added about 60 MB RSS; 8 MiB, 32 MiB, and 1 MiB-node CITEM variants did not beat the selected 16 MiB graph/256 KiB node policy; in-place array-file finalization did not improve dense encoding; floating-point fragment caching added memory for negligible speed; and an eight-chunk transfer preference would have changed a frozen interoperability fixture before proving a gain.

## Physical iPhone-to-CLI validation

The exact dirty worktree was built, installed, and launched on a physical iPhone 17 Pro running iOS 26.5.2. The standalone Rust CLI connected directly over Manual IP with the macOS app bypassed. Protected data, raw export, and generated-file readiness were all available.

A strict raw export for one real day completed in 10.52 seconds. It produced a 10,510,209-byte restricted file containing one complete schema-v1 raw result and one schema-v7 health document: 3,473 records, 3,466 samples, no missing date, partial failure, integrity warning, or failed query. The desktop receiver peaked at 22,282,240 bytes RSS.

A production generated-file export of the same day committed three restricted files atomically: 10,509,056-byte JSON, 6,619,021-byte CSV, and the 222,317-byte data dictionary. The generated schema-v7 JSON was logically identical to the health document received through strict raw transfer. The CLI committed 17,350,394 bytes across three durable partitions and the iPhone acknowledged terminal completion. The desktop receiver peaked at 21,200,896 bytes RSS, and the iPhone produced no crash or jetsam report.

The physical lab reproduced the saved-settings delay and attributed it precisely. Before the CITEM optimization, `spool-encode` took 317.455 seconds and peaked at 2,307,115,560 bytes of physical footprint; HealthKit granular capture itself took 5.901 seconds. Resuming that exact durable job completed render, partition, transfer, and final acknowledgement without starting a replacement. The same one-day schema-v7 output after bounded inline scalar/keyed/unkeyed CITEM nodes completed in 19.89 seconds, with `spool-encode` reduced to 2.144 seconds and 63,521,808 bytes, and the complete iPhone job peaking at 161,088,600 bytes. The three generated files remained exactly 17,350,394 bytes.

A seven-day saved-settings interruption/resume run emitted 124,777,668 bytes across 15 files. Reusable POSIX partition hashing removed a 125 MiB autorelease/cache jump, and four-chunk bounded transfer pipelining reduced total transfer work from 31 seconds to about 13 seconds. The runner killed the host process after the first committed partition, preserved the same job, and resumed it to terminal acknowledgement in 92.48 seconds total. The iPhone peaked at 180,143,528 bytes, remained thermally fair, produced no crash/jetsam report, and stayed below the 256 MiB ceiling.

A later matched window emitted 107,311,692 schema-v7 bytes across the same 15-file shape. The final selected build completed in 75.94 seconds at a 164,283,504-byte peak; render fell from 23.90 to 21.38 seconds after exact string/key fast paths, and all phases stayed thermally nominal. On the matched one-day 2,295,659-byte workload, median host wall time fell from 17.95 to 7.16 seconds, median iPhone footprint from 161,727,576 to 47,989,776 bytes, median iPhone job time to 3.73 seconds, and `spool-encode` to about 203 ms. Three repeated runs produced identical byte counts and no crash/jetsam reports.

The fixed 30-day direct-files scenario exposed a separate scale-dependent cache peak. Its first complete 30/30 export emitted 450,888,036 bytes in 61 schema-v7 files and finished in 329.88 seconds, but rereading every generated file through `FileHandle` for final manifest SHA-256 charged 498,451,784 bytes of file cache to the iPhone process. `DirectTransferFile.inspect` now opens the final file nonblocking without following symlinks, requires a regular file, hashes exactly the opened descriptor's fixed size through one reusable 256 KiB POSIX buffer, rejects truncation or observed growth, and enables Darwin `F_NOCACHE`; SHA-256 framing is unchanged. Two complete candidate runs produced the same 61 relative paths and identical per-file SHA-256 values. They finished in 354.49 and 333.07 seconds at 108,790,824 and 91,833,432-byte peaks; render peaked at 70,550,568 and 61,752,384 bytes, remained thermally fair, and produced no crash/jetsam report. One intervening terminal attempt captured 30 days but failed staging before any partition commit; it was inspected rather than resumed or blindly classified as success, and the following matched run completed normally.

The immutable dense replay gives the clearest serializer result. The same physical 24,817,153-byte CITEM reproduced exact expected JSON/CSV SHA-256 values. JSON rendering fell from 4.42 to 3.55 seconds while RSS dropped from 383,598,856 to 3,801,088 bytes; CSV fell from 3.75 to 3.17 seconds with about 3 MB RSS.

The deterministic physical 256 MiB file-backed-blob stress rendered 357,914,981 bytes in 1.228 seconds with a 64,554,024-byte iPhone footprint. It validates the serializer and artifact lifecycle target; real HealthKit attachment-provider and lock-transition validation remains separate.

The production-target smoke matrix also passed: direct sleep files completed in 5.70 seconds at 41.4 MB; saved-settings API uploaded 5,961,666 bytes in 6.75 seconds at 54.1 MB; and connected Mac committed the same 17,350,394 generated bytes in 19.05 seconds at 58.4 MB on iPhone and 50.3 MB on Mac. The API sink validated success, delayed read/response, 429, 500, oversized bounded-response cancellation, and mid-upload disconnect receipts. HMAC-authenticated autonomous Debug requests removed per-run tapping without weakening fixed scenarios, destination attestations, unlock/foreground checks, or stop conditions.

The supervised [Physical export performance lab](./physical-export-lab.md) now provides correlated phase spans, physical process-footprint sampling, fixed scenario controls, private baselines, a stable signed CLI path, a streaming HTTPS API sink, and adapters for direct, local iPhone, API Endpoint, and connected-Mac runs. HealthKit operation rows are persisted without type identifiers or predicates. The latest seven-day breakdown attributes 19,955 attachment-metadata queries and 21.69 seconds of cumulative query time to attachment discovery, followed by 720 workout-associated quantity queries and 2.53 seconds. Attachment work already uses the physically selected concurrency of four; cumulative operation time can overlap and is not phase wall time. This is the canonical evidence for refusing attachment omission or unproven concurrency changes.

A bounded four-query workout-association experiment preserved all 107,311,692 schema-v7 bytes and the 15-file shape but was rejected physically. The actor-isolated version spent 6.041 seconds of wall time in the association windows for 5.659 seconds of cumulative queries and completed in 80.10 seconds. Moving only the raw descriptors to a nonisolated ordered window still spent 6.152 seconds in those windows for 3.652 seconds of cumulative queries and completed in 87.93 seconds. Both lost to the selected 75.94-second serial baseline and its approximately 2.53-second association floor. The scheduler, telemetry probe, and tests were removed after the restored path passed focused cancellation and workout regressions.

Attachment discovery is a public-API floor rather than an unimplemented batch. Xcode 26.5 exposes only `HKAttachmentStore.attachments(for: HKObject)`, one parent at a time. `HKAttachment` is not an `HKObject` or `HKSample`, general query descriptors cannot return it, and an attachment does not expose its parent UUID. The central sweep already deduplicates retained parents by HealthKit UUID before the adapter issues one metadata request per unique parent. Cross-day caching or assumed attachment-capable type lists would change observation, diagnostics, or completeness. The expected safe query-count reduction from additional batching or pruning is therefore zero.

## Highest-value remaining work

### P0 — Validate real attachment providers and lock/low-disk transitions

The deterministic 256 MiB physical serializer stress is comfortably bounded, but real HealthKit attachment providers must still verify protected-file behavior during lock transitions, provider stream failures, low-disk cleanup, and cancellation.

### P1 — Bound retained model graphs in API shadow/planned mode

Per-day encoded bytes are now files, but the newer API authority path can still retain all `HealthData` outcomes and native/Rust comparison evidence for a requested range. Profile this independently and release model evidence after comparison and durable pin decisions when compatibility allows.

### P1 — Evaluate a one-day capture/write pipeline

Date ranges remain serial. A one-day bounded prefetch could overlap HealthKit with previous-day serialization/I/O while retaining at most two model graphs. This must be opt-in and physically profiled because sustained HealthKit pressure can erase the gain.

### P2 — Profile optional side effects and durability frequency

Daily-note injection, individual-entry tracking, partition hashing, journal replacement, and per-chunk acknowledgements still trade throughput for compatibility or resumability. Measure them independently before batching any operation, and preserve the exact acknowledged frontier after interruption.

### P2 — Converge Rust only after archive-aware parity exists

Swift remains authoritative for this cutover. The current Rust stream renderer still has different item/stream limits and CSV framing and does not render Apple canonical archives or file-backed blobs. Routing schema-v7 Apple exports through it now would violate exact-byte or memory guarantees. A later internal shared-core revision can add archive-aware blob handles and differential fixtures before changing authority; no public schema or direct protocol bump is needed for the Swift file-artifact implementation.

## Explicit non-optimizations

- Do not derive established HealthKit statistics from raw samples; the values are not guaranteed equivalent.
- Do not skip attachment queries based on assumptions about which object types can carry attachments.
- Do not raise HealthKit concurrency without physical-device evidence.
- Do not remove atomic destination writes, checksum validation, durable commit barriers, or resume journals to improve a synthetic benchmark.
- Do not alter canonical ordering, timestamps, precision, units, diagnostics, or schema keys for speed.

## Verification completed

- Exact parity covers pretty/compact daily JSON, standalone canonical archives and records, CSV fields, Foundation and JSONEncoder floating-point modes, control/Unicode escaping, slash behavior, streamed base64 carry boundaries, file-backed attachment bytes, API envelopes, and generated reference documentation.
- Cancellation, injected low-disk failure, sibling lease cleanup, private permissions, atomic destination preservation, upload-from-file, partition resume, legacy journal decoding, and durable sender tests pass.
- The final full macOS run passed: 1,827 tests executed, seven skipped, zero failures. The full iOS simulator suite passed 1,733 tests with 12 skips and zero failures.
- The iOS Simulator app build succeeded; only the pre-existing `IPhoneCorpusExportRecoveryManager` actor-isolation warning was emitted.
- All generated export references are current and 237 local documentation links pass.
- The schema-v7 signature fixture remained unchanged.
- The 32 MiB attachment benchmark emitted 89,483,839 JSON/CSV bytes with a 1.79 MiB maximum per-format RSS delta; the dense 1,792-record benchmark emitted 6,055,161 bytes identically through compatibility and file-artifact paths.
