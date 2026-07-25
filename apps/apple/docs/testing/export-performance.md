# Local export performance instrumentation

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

## Privacy boundary

Instrumentation records only fixed pipeline/phase names, public HealthKit type identifiers, operation labels, elapsed milliseconds, aggregate counts, bytes, and concurrency. It must not record dates, health values, record/sample counts, UUIDs, predicates, metadata, filenames, paths, endpoint URLs, authorization values, or error descriptions.

## Verification

The debug counter tests are in `HealthMdTests/Performance/ExportPerformanceInstrumentationTests.swift`. Release verification should build both app targets and inspect the binaries:

```bash
strings /path/to/HealthMd | grep -E \
  'ExportPerformance|queries_total|healthkit_query|ExportPerformanceQuerySession'
```

A correct Release binary produces no matches.

The separate opt-in synthetic serializer benchmark remains available by setting `HEALTHMD_RUN_EXPORT_BENCHMARKS=1` before running `ExportPipelineBenchmarkTests`. It does not measure HealthKit, filesystem durability, providers, transfer, peak memory, or UI stalls.
