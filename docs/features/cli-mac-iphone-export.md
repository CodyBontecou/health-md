# Mac CLI iPhone Export Trigger

## Status

- **Docs status:** draft
- **Primary surfaces:** Health.md macOS app, `healthmd` CLI, open Health.md iOS app
- **Source files:** `HealthMdCLI/Sources/healthmd/main.swift`, `HealthMd/Shared/Sync/CanonicalRawCLIModels.swift`, `HealthMd/Shared/Sync/ConnectedTransfer.swift`, `HealthMd/iOS/IPhoneExportRequestHandler.swift`, `HealthMd/macOS/Managers/HealthMdControlServer.swift`

## What it does

The Mac CLI asks an already-open, connected iPhone to read HealthKit. It can send a file-writing job, return the complete strict archival transport, or push a metric/object/detail selection down to iPhone and emit ordinary `healthmd.health_data` documents with the transport envelope removed. `healthmd.health_data` remains the single public health-data source of truth; jobs, paging, receipts, and raw-result wrappers are protocol metadata. HealthKit remains on iPhone and file writes remain in the Mac app. See [API and CLI](../reference/api-and-cli.md) and [Connected Mac–iPhone protocol](../reference/connected-mac-iphone-protocol.md) for exhaustive generated request, response, transfer, and error objects.

## Requirements

- Health.md running on Mac.
- Health.md open/connected on an unlocked-enough iPhone.
- HealthKit access and export quota available.
- Current peer capabilities for strict raw, lossless file jobs, or Daily Notes Only. Older Macs are rejected for Daily Notes Only so they cannot ignore the setting and create aggregate files.
- A selected writable Mac folder for file mode; strict raw mode does not require one.

## Commands

```bash
healthmd status
healthmd status --job 00000000-0000-4000-8000-000000000101
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --from 2026-07-21 --to 2026-07-22
healthmd extract --metric resting_heart_rate --last 30 --object heart --format jsonl --output heart.jsonl
healthmd extract --metric workouts --last 14 --object records --detail lossless
healthmd query --category Sleep --from 2026-07-21 --to 2026-07-22 --all-pages
healthmd query --metric resting_heart_rate --last 30 --reuse-covered --progress-json --format table
healthmd sleep sessions --last-nights 14 --window first:4h --physiology-metric heart_rate
healthmd training align --last 14 --workout running --sleep-window first:4h
healthmd workouts --last 14
healthmd coverage --category Sleep --last 14
healthmd compare --metric steps:sum --first-from 2026-07-01 --first-to 2026-07-07 --second-from 2026-07-08 --second-to 2026-07-14
healthmd evidence training --category Sleep --workout-detail distance --last 14
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --last 7 --category Sleep --detail summary
healthmd export --iphone --last 30 --metric workouts --detail lossless
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --all
healthmd export --iphone --all --raw --output complete-health-corpus.json
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
healthmd export --iphone --last 3650 --raw --output health-corpus.json
healthmd export --iphone --yesterday --use-iphone-settings
healthmd resume 00000000-0000-4000-8000-000000000101 --timeout 300
healthmd resume 00000000-0000-4000-8000-000000000101 --output health-corpus.json --allow-partial
healthmd cancel 00000000-0000-4000-8000-000000000101
```

Executed commands print machine-readable JSON, including control-server and strict-validation failures. `healthmd extract` is the source-schema happy path. JSON contains canonical v7 daily documents under `health_data`, or exact pointer results under `projections`, plus a non-health `healthmd.extract_receipt` protocol object. JSONL writes one data item per line and puts the receipt on stderr or beside `--output` as `.receipt.json`. Fresh acquisition preserves its corpus-wide `status`/`corpus_status` while also returning `healthmd.requested_scope_completion` v1, top-level `requested_scope_status`, and aggregated `unrelated_skips`. Completion examines only owner-day blobs replaced after that refresh began and verifies every requested metric × source/provider × day cell, so stale cache or another provider cannot mask a fresh failure. A requested Sleep or workout scope can therefore be `success` even when an unrelated captured branch made the complete corpus `partial_success`; requested metric/day failures still remain partial or failed. No credential setup is required. `healthmd doctor` combines public Mac/iPhone status with encrypted-cache and fresh-acquisition checks and reports `action_required` when neither cached owner days nor fresh iPhone acquisition is available. High-level queries send their metric, source, date, and detail scope directly, use a cloned non-persisted iPhone selection, and then query the encrypted Mac context store; `--cached` skips acquisition. `--help` is plain text, and pre-request argument/usage errors are plain text on stderr with exit code 2. Multi-year ranges are supported with no calendar-day cap. `--all` is a first-class dynamic selection: the iPhone walks the complete selected `HealthKitRecordCatalog`, queries each ordinary source type plus dedicated activity-summary and medication APIs for its earliest readable date, pins every source-calendar day through today, and returns that exact range before corpus transfer. Static characteristics/inventories are captured as current snapshots and do not fabricate an earlier daily timeline. If any selected historical type cannot be resolved or queried, the request fails rather than claiming a later start is complete. `--all` is mutually exclusive with bounded date flags. `--timeout` must be 5...900 seconds and is reset by validated progress.

## Typed analytical commands

The high-level `sleep sessions`, `training align`, `workouts`, `coverage`, `compare`, and `evidence training` commands are derived/compatibility views. They use the same direct request scope, fresh acquisition, encrypted internal index, bounded page, evidence, coverage, and missingness contracts as `healthmd query`. That index is disposable implementation state, not a second public health-data source; direct source objects come from `healthmd extract`. Every successful envelope includes a compact `healthmd.cli_query_receipt` v1. `--all-pages` follows opaque cursors with cycle checks and bounded aggregate byte/page ceilings, returning traversed original responses under `pages` while preserving the first page under `query` for compatibility. When the ceiling is reached, narrow scope or page manually. `--progress-json` writes `healthmd.cli_progress` v1 JSONL to stderr so stdout remains one final JSON document. `--format table` is an explicit lossy human-only TSV view with coverage, source, limitation, completion, and unrelated-skip diagnostics retained in its comment footer. They do not read export files or mutate saved iPhone settings. `--reuse-covered` first traverses metric-aware coverage and skips iPhone acquisition only when every requested summary metric/day is available or complete-empty. It never reuses coverage for lossless detail or operations that require newly projected sleep-session context. Comparison aggregation is always explicit (`sum`, `average`, `minimum`, `maximum`, `latest`, `count`, or `duration_sum`); the CLI never guesses from a metric name or labels direction as better or worse. Workout details selected for a training packet request lossless detail directly.

`healthmd sleep sessions` returns stable session IDs, UTC and local timestamps, the captured timezone, owner date and crossed calendar dates, overnight/nap classification, completeness/truncation, observed and untracked duration, selected stage totals, evidence, explicit exclusions, and optional physiology sample coverage. Session requests include `sleep_total` and the complete canonical sleep-stage metric set because boundaries and stage structure are broader than one narrow stage metric. Naps are excluded from `--last-nights` output unless `--include-naps` is set. Session and alignment commands always request lossless capture; aggregate-only cache remains explicitly limited, and fixed windows never guess or proportionally assign daily totals. Overlapping sources are unioned for asleep duration. The query engine may inspect at most one adjacent owner day for sessions and two for alignment, without returning unrelated data.

`healthmd training align` deterministically pairs each selected workout with the nearest eligible preceding and following sleep session within 36 hours. Optional activity filtering is exact and case-insensitive. Each result carries stable workout/session/alignment IDs, timing gaps, the requested sleep window, physiology sample counts, evidence, completeness, and explicit activity/source/missing-session exclusions. The output says only that times were aligned; it never claims a workout caused a sleep change or assigns better/worse meaning.

## Durable jobs

Every Mac-initiated request is written under Health.md's Application Support directory before it is sent. The record contains the exact `IPhoneExportRequest`, progress, pause/session metadata, bound iPhone/Mac installation IDs, terminal ordinary response, and a fixed `expires_at` exactly seven days after creation. For `--all`, the Mac also persists the iPhone-resolved start/end and exact date identifiers before admitting corpus bytes; retries must present the same pinned range and cannot drift when older records later appear. App relaunch does not change that deadline. `healthmd status --job UUID` inspects the record, while `healthmd resume UUID` resends the exact stored request only to the same iPhone installation after reconnecting.

The iPhone also keeps a protected, backup-excluded outbound journal containing the stable session/fingerprint, acknowledged digest frontier, next HealthKit date, any partially committed daily item, and the one current unacknowledged partition. It advances offsets and deletes bytes only after the Mac's durable acknowledgement. Therefore a terminated/relaunched iPhone does not retain or retransmit the completed gigabytes: it resumes from the Mac frontier and retransmits at most the current 64 MiB partition. The iPhone spool remains bounded to the current item and partition rather than aggregate export size.

The initial export POST and a resume POST are only waiters. When a resumed spool carries `health_data_projection`, the CLI recovers the persisted object/field selection and again emits canonical documents rather than exposing the transport wrapper. Their timeout, Ctrl-C, a closed pipe, or another broken loopback client detaches the waiter and returns `timed_out` or `accepted` when possible; it does not cancel iPhone work, corpus work, or delete the job. Peer disconnect marks the job paused and retains both journals. `healthmd cancel UUID` is the only user control operation that sends cancellation. If the bound iPhone is absent, the cancelled Mac record acts as a tombstone and redelivers cleanup only to that installation on its next hello. Cancellation and expiry may remove internal journals/spools, but never remove files already written to the selected destination.

## File mode

Default `settings_policy: requested_dates_only` uses iPhone formats, paths, write mode, Daily Note Injection, and Daily Notes Only, but disables roll-ups and summary-only mode for this request. Without selectors it uses saved metrics and Lossless Health Records. Repeatable `--metric`/`--category` (or explicit `--all-metrics`) plus `--detail summary|lossless` replace those two saved choices only for this file job, before HealthKit reads; selected files still use the production exporters and v7 schema. Date selection always comes from the CLI.

`--use-iphone-settings` uses saved settings exactly, including roll-ups, summary-only mode, and Daily Notes Only. Effective granular capture is enabled only for standard file mode: summary-only and Daily Notes Only jobs neither fetch nor transfer a lossless archive even if the saved Lossless Health Records toggle is on.

Current peers negotiate partitioned corpus transfer plus the current `healthmd.healthkit_records` archive version. All-available-history requests require the additive all-history capability and partitioned transfer on both peers; they fail closed instead of turning into a one-day placeholder request. Older peers keep the single-payload path and its 2 GiB ceiling; they are rejected rather than accepting a lossless job that could drop the archive. Summary-only and non-granular jobs retain their legacy compatibility path.

The Mac destination is the root; the iPhone's Health subfolder/templates are appended. When Daily Notes Only is active, the daily-note folder remains root-relative and all aggregate/ZIP/roll-up/individual/provider/data-dictionary outputs are suppressed. File-mode control responses report `daily_notes_updated` and `daily_notes_skipped` when non-zero; `files_written` remains `0` because no additional export file was generated. A successful action records history and consumes one iPhone export action.

## Canonical scoped extraction

`healthmd extract` accepts repeatable `--metric`, `--category`, and `--object` selectors (or explicit `--all-metrics`), a date selection, `--detail summary|lossless`, Apple Health source selection, optional canonical JSON Pointers with `--field`, and `--format json|jsonl`. Summary is the default. The exact resolved metric set is placed in the durable request fingerprint and applied to a cloned, non-persisted iPhone settings snapshot before HealthKit authorization descriptors and queries are built. Unselected HealthKit types are not read. Lossless archive capture occurs only when requested; archive object selectors imply lossless detail.

The iPhone still serializes each retained day through the production v7 JSON exporter. The Mac validates the bounded partition stream and temporary transport envelope. Whole documents are copied by byte range without materializing the corpus. `--field`/`--object` outputs do not pretend to be complete v7 documents: each projection names its source v7 document and returns exact JSON Pointer/value/status entries, including explicit `complete_empty` or partial status for absent paths. Projection decoding is bounded to one 64 MiB day; callers should narrow metrics further when a selected day exceeds that bound. The receipt retains every requested day status, failure code, missing date, capture count, and resolved selection. By default a partial extraction emits only a structured failure plus receipt; `--allow-partial` is required before retained data is emitted. Summary source documents report `raw_capture_status: not_requested` because no lossless archive was requested.

This path currently exposes canonical Apple Health data. Provider sidecars are not silently translated into `healthmd.health_data`; `--source` therefore accepts only `apple_health` until provider objects become part of the main export contract.

## Strict raw profile

`--raw` requests `canonical_source_records_v1` and writes no files. It temporarily forces Lossless Health Records for the request without changing the saved `includeGranularData` preference.

The response is `healthmd.raw_result` v1. Each retained day contains the public schema-v7 `healthmd.health_data` object, including `time_context`, summaries, diagnostics, and `healthkit_record_archive` (`healthmd.healthkit_records` v1). This strict profile currently contains canonical Apple Health data only; it does not fetch or embed connected-provider sidecars.

Strict raw behavior:

- retains complete-empty and warning-only days;
- reports per-day `complete`, `complete_empty`, `complete_with_warnings`, `partial`, `failed`, `cancelled`, or `missing`;
- reports aggregate query counts for `success`, `failure`, `unsupported`, `skipped`, and `cancelled`;
- includes integrity-warning counts/codes, partial-failure types, and missing dates;
- rejects peers that do not advertise the required raw-result, archive, strict-streaming, and size-bounded-transfer versions;
- never downgrades to the legacy internal-Codable `raw_data` shape.

Legacy callers that omit `raw_profile` remain decodable on their old path, but strict clients must not accept that path as equivalent.

## Exit behavior

A complete empty capture is success. A failed, cancelled, missing, unsupported/skipped, or otherwise incomplete requested day/type produces overall `status: partial_success`.

- default raw CLI exit is non-zero for `partial_success`;
- `--allow-partial` makes that result exit zero but does not remove diagnostics;
- no partial capture may be treated as complete;
- for a partitioned response, the Mac validates every exact source date, raw-result/profile version, schema-v7 daily document, and current canonical archive before setting checksum/date-range validation headers; the CLI verifies those headers, requested range/count, the streamed body SHA-256, and the strict schema/date/archive invariants with a bounded-memory streaming parser before emitting bytes;
- legacy HTTP-200 responses retain whole-response independent CLI validation. A malformed or legacy success becomes machine-readable diagnostics and exits non-zero.

Automation should inspect response `status`, each day, `capture_summary`, `missing_dates`, and every nested daily `raw_capture_status` before accepting a run.

## Partitioned transfer and output size

Current peers use one stable corpus session with a default 48 MiB target (negotiated within 32–64 MiB). Each partition carries exact source dates, byte counts, a SHA-256 digest, a previous-partition digest, and 512 KiB transport frames. A logical day/item may span any number of bounded 64 MiB physical partitions; item and aggregate byte counts use 64-bit counters and have no product-level total cap. Mac acknowledges a partition only after its daily items and durable journal commit. A failed partition is retried with the same identity, and replay does not duplicate daily writes.

The legacy single-payload transport remains capped at 2 GiB for mixed-version peers. Strict raw never falls back to an unbounded whole-payload message.

For current strict raw, Mac composes final JSON on disk and retains that protected response spool as a durable job artifact until explicit cancellation or expiry. Each loopback download reads the artifact without consuming it, so a broken download can be retried with job status/resume. The CLI downloads to a temporary spool, verifies its SHA-256 and requested range, then copies it to stdout in bounded chunks or atomically commits `--output PATH`. It does not parse the complete corpus into a `JSONSerialization` object. One dense HealthKit day still has to be captured/encoded at a time, and available device/Mac storage remains a practical bound. Avoid logging raw health payloads.

## Local control boundary

The Mac HTTP control server:

- listens only on `127.0.0.1` and `::1` and rejects non-loopback accepted peers;
- limits headers to 16 KiB and request bodies to 256 KiB;
- has a 10-second receive deadline;
- requires JSON and explicit content length for `POST /v1/exports`;
- validates finite 5...900-second inactivity waits;
- provides additive `GET /v1/exports/{jobID}`, `POST /v1/exports/{jobID}/resume`, and `POST /v1/exports/{jobID}/cancel` routes;
- uses client-provided job IDs to detach a transient HTTP waiter if the CLI connection closes early, without cancelling durable work.

There is no bearer token; loopback is the complete authorization boundary. Only the explicit cancel route sends iPhone/transfer/corpus cancellation. Late results after a waiter timeout are persisted and remain retrievable.

## Request-scoped metric queries

`healthmd query` accepts repeatable `--metric` and `--category` selectors plus the normal date forms. It validates selections against `GET /v1/agent/metrics` and sends Apple Health, requested metrics, dates, and summary/lossless detail as the complete request scope. The exact selection and owner-date labels are durable and resumable, and the iPhone's saved metric toggles, formats, folders, and roll-ups are never changed. The high-level command returns one bounded typed-query page; a non-null `next_cursor` makes the outer envelope `partial_success` so additional results cannot be mistaken for a complete traversal.

The iPhone verifies standard HealthKit authorization decisions only for the requested metrics. HealthKit read permission is still an operating-system boundary: unresolved permission requires user action on iPhone, and denied read access can remain indistinguishable from an empty result. Special medication, vision, document, and restricted-record domains retain their explicit selector or skipped/partial behavior; automation must preserve those diagnostics.

## Limitations

This is not fully headless cron. iOS may suspend capture while Health.md is closed, and protected HealthKit data still requires the iPhone to be unlocked enough for reads. A disconnect or app termination pauses a durable v2 job rather than failing it; reopening Health.md and reconnecting the same installations resumes automatically until the fixed seven-day expiry. Legacy peers retain their previous failure behavior. HealthKit read privacy can also make denied access appear successfully empty.

Raw export uses public APIs and current snapshots only. It does not infer unavailable fields or provide deletion tombstone history.

## Implementation notes

- `CanonicalRawCLIModels` preserves canonical daily JSON as strings across sync so exact integer/public serialization is not changed before local-control injection.
- `IPhoneExportRequestSettingsResolver` applies scoped extraction metrics/detail or forces request-scoped lossless capture for archival strict raw without persisting either setting.
- `ConnectedCorpusTransfer` and `ConnectedCorpusPartitionFile` negotiate and checksum resumable partitions above the legacy aggregate ceiling.
- `MacCorpusExportSessionManager` applies daily items incrementally and journals committed partitions/exact dates.
- `HealthMdControlServer` validates loopback HTTP and streams protected raw-result spools.
- `healthmd` exits non-zero on partial raw results unless `--allow-partial` is explicit.
