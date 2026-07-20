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
