# Local export performance instrumentation

See the [2026-07-30 export performance audit](./export-performance-audit-2026-07-30.md) for current bottlenecks and the [Physical export performance lab](./physical-export-lab.md) for supervised iPhone/Mac profiling across direct CLI, local, API Endpoint, and connected-Mac targets.

Health.md includes compile-time-gated export measurements for local development. The recorder and phase call sites use `#if DEBUG`; the shared query executor compiles directly to its supplied HealthKit operation outside Debug. Release/App Store builds do not contain the recorder, logger category, or measurement strings.

## Viewing measurements

Run a Debug build, start an export, and inspect Xcode's console or stream the unified log on the development Mac:

```bash
log stream --level debug \
  --predicate 'subsystem == "com.healthexporter" AND category == "ExportPerformance"'
```

For a USB-connected physical iPhone, capture the Debug app process with `idevicesyslog`, then filter the saved file by the `kind` field:

```bash
NO_COLOR=1 TERM=dumb timeout 300 \
  idevicesyslog --process HealthMd --no-colors \
  > /tmp/healthmd-export-performance-raw.log 2>&1 </dev/null

grep -E 'kind=(phase|healthkit_query)' \
  /tmp/healthmd-export-performance-raw.log
```

Do not use `idevicesyslog --match ExportPerformance`: its rendered lines do not include the unified-log category, so that filter discards the measurement messages.

Phase records have this shape:

```text
kind=phase pipeline=healthkit phase=daily-capture-granular elapsed_ms=... items=... bytes=... queries_total=... queries_elapsed_ms=... queries_max_concurrent=... queries_active=0
```

The HealthKit capture record is followed by deterministic per-operation/type totals:

```text
kind=healthkit_query operation=queryAverage type=HKQuantityTypeIdentifierHeartRate count=... elapsed_ms=... max_elapsed_ms=... max_concurrent=...
```

`queries_elapsed_ms` sums individual query durations and can exceed phase wall-clock time when queries overlap. `queries_max_concurrent` is the whole-session maximum; each query row's `max_concurrent` is the maximum for that exact operation/type pair. Both are observational and do not change production limits. For API and external-provider phases, `items` is the number of outbound request attempts, including failed attempts.

Instrumented phases include:

- HealthKit daily summary/lossless capture and canonical archive construction
- Local foreground/background export and daily writes
- ZIP creation
- API capture/batching/upload
- External-provider daily fetches
- Connected transfer
- Connected Mac partition application and corpus finalization

## Physical-device findings

A Debug build was measured on an iPhone 17 Pro using one-day foreground exports. Three runs used the same retained attachment-parent workload; the final responsiveness run contained fewer attachment parents and is not a direct wall-time comparison.

| Variant | Queries | Attachment queries / cumulative time | HealthKit wall time | Total wall time | Daily write | HangTracer |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Original fixed four-parent attachment batches | 3,638 | 3,003 / 3.306s | 4.185s | 4.502s | 262ms | 0.31s |
| Dynamic metadata window of 16 | 3,638 | 3,003 / 31.311s | 5.212s | 5.567s | 293ms | 0.35s |
| Dynamic metadata window of four | 3,638 | 3,003 / 6.178s | 4.765s | 5.114s | 282ms | 0.34s |
| Fixed batches restored; aggregate durability off MainActor | 2,314 | 1,702 / 1.941s | 3.431s | 3.706s | 225ms | none |

The dynamic attachment schedulers were rejected: both increased physical-device latency, apparently through HealthKit throttling. The fixed four-parent scheduler remains in place. The aggregate/data-dictionary writer now performs its read/modify/atomic-write transaction on a shared serial utility queue. In the validation run, the 225ms durable write completed without a HangTracer event; previous synchronous writes consistently produced a 0.31–0.35s foreground hang. Daily-note injection and individual-entry files still use their existing synchronous paths and require separate profiling when those optional modes are enabled.

The structured physical lab later isolated the long direct generated-file path:

| Direct-file measurement | Before bounded CITEM nodes | After scalar/composite nodes | Latest result |
| --- | ---: | ---: | ---: |
| One-day `spool-encode` | 317.455s / 2.31 GB peak | 82.923s / 818.8 MB peak | 0.203s / 46.2 MB peak |
| One-day complete job | timeout plus resume | 101.98s / 820.3 MB peak | 3.73s / 48.0 MB median |
| Seven-day partition peak | 301.3 MB | 292.5 MB | 164.3 MB |
| Seven-day whole-job peak | above limit | 292.5 MB | 164.3 MB |

The durable interruption/resume baseline emitted 124,777,668 bytes in 15 files, stayed thermally fair, completed in 92.48 seconds, and preserved the same job after the first committed partition. A later matched seven-day window emitted 107,311,692 bytes in 75.94 seconds at a 164,283,504-byte peak with nominal thermal state. The matching one-day workload improved from 17.95 to 7.16 seconds median host wall time and from 161.7 to 48.0 MB median iPhone footprint. Per-run crash/jetsam indexes reported no new device reports.

A fixed direct-files-only 30-day scenario now requires 30/30 successful requested days, exact receipt file/byte totals, schema v7, and complete target-specific telemetry. The first complete 450,888,036-byte/61-file run peaked at 498.5 MB because final manifest inspection reread every generated file through cached `FileHandle` data. Replacing that pass with a reusable 256 KiB POSIX SHA-256 buffer and `F_NOCACHE` reduced two complete candidate peaks to 108.8 and 91.8 MB; render itself peaked at 70.6 and 61.8 MB. Candidate wall times were 354.49 and 333.07 seconds versus the 329.88-second over-limit baseline. Both candidate runs had identical relative paths and per-file SHA-256 values, stayed thermally fair, and produced no crash/jetsam report.

Exact replay of the dense physical CITEM reduced 27,660,487-byte JSON rendering from 4.42 to 3.55 seconds and from 383.6 to 3.8 MB RSS; 16,217,173-byte CSV fell from 3.75 to 3.17 seconds. JSON, CSV, and re-encoded CITEM SHA-256 values matched the physical artifacts exactly. HealthKit operation telemetry identifies attachment discovery as the remaining floor: 19,955 queries and 21.69 seconds cumulative across seven days, already using the physically selected concurrency of four.

A four-query ordered window for the next-largest operation, 720 workout-associated quantity queries, was slower and was removed. Its two physical variants spent 6.041 and 6.152 seconds of wall time in the measured association windows, compared with the established serial operation floor of about 2.53 seconds; matched whole-job results were 80.10 and 87.93 seconds versus the selected 75.94-second baseline. Both variants preserved 107,311,692 schema-v7 bytes in 15 files, so rejection was based on performance rather than correctness.

The attachment count cannot be reduced with a public bulk query. `HKAttachmentStore` accepts one `HKObject` in `attachments(for:)`; `HKAttachment` cannot be returned by an `HKSampleQuery` and carries no parent UUID from which a flattened response could reconstruct ownership. Retained parent references are already deduplicated by HealthKit UUID before querying. Skipping presumed-ineligible types or caching across owner days would weaken completeness or failure diagnostics, so the expected safe reduction from batching is zero.

## Privacy boundary

Instrumentation records only fixed pipeline/phase names, public HealthKit type identifiers, operation labels, elapsed milliseconds, aggregate counts, bytes, and concurrency. It must not record dates, health values, record/sample counts, UUIDs, predicates, metadata, filenames, paths, endpoint URLs, authorization values, or error descriptions.

## Verification

The debug counter tests are in `HealthMdTests/Performance/ExportPerformanceInstrumentationTests.swift`. Release verification should build both app targets and inspect the binaries:

```bash
strings /path/to/HealthMd | grep -E \
  'ExportPerformance|queries_total|healthkit_query|ExportPerformanceQuerySession'
```

A correct Release binary produces no matches. The physical lab's stronger fixed-string gate builds an unsigned Release simulator app and checks all Debug control/telemetry markers:

```bash
make check-export-lab-release
```

The separate opt-in synthetic serializer benchmarks remain available by setting `HEALTHMD_RUN_EXPORT_BENCHMARKS=1` in the `ExportPipelineBenchmarkTests` test action. They emit:

- `HEALTHMD_EXPORT_BENCHMARK` for 1-, 30-, and 365-day summary/compatibility rendering;
- `HEALTHMD_LOSSLESS_EXPORT_BENCHMARK` for dense canonical-archive JSON/CSV preparation, including the already-selected capture and file-artifact paths;
- `HEALTHMD_FILE_BACKED_ATTACHMENT_BENCHMARK` for per-format peak RSS while rendering a 32 MiB file-backed attachment;
- `HEALTHMD_CITEM_BENCHMARK` for dense connected-application-item encoding and decode parity;
- `HEALTHMD_PHYSICAL_CITEM_ENCODE` and `HEALTHMD_PHYSICAL_CITEM_REPLAY` when `HEALTHMD_PHYSICAL_CITEM_REPLAY_PATH` points to a private captured item. The expected JSON and CSV paths are required and enforce exact SHA checks.

These benchmarks do not measure HealthKit, filesystem durability, real attachment providers, transfer, or UI stalls. The attachment benchmark measures synthetic macOS serialization memory only; physical-device validation remains required.
