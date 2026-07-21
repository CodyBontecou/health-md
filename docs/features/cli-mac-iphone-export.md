# Mac CLI iPhone Export Trigger

## Status

- **Docs status:** draft
- **Primary surfaces:** Health.md macOS app, `healthmd` CLI, open Health.md iOS app
- **Source files:** `HealthMdCLI/Sources/healthmd/main.swift`, `HealthMd/Shared/Sync/CanonicalRawCLIModels.swift`, `HealthMd/Shared/Sync/ConnectedTransfer.swift`, `HealthMd/iOS/IPhoneExportRequestHandler.swift`, `HealthMd/macOS/Managers/HealthMdControlServer.swift`

## What it does

The Mac CLI asks an already-open, connected iPhone to read HealthKit. It can either send a file-writing job to the selected Mac destination or return a strict canonical raw result. HealthKit remains on iPhone and file writes remain in the Mac app. See [API and CLI](../reference/api-and-cli.md) and [Connected Mac–iPhone protocol](../reference/connected-mac-iphone-protocol.md) for exhaustive generated request, response, transfer, and error objects.

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
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
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

Executed commands print machine-readable JSON, including control-server and strict-validation failures. `--help` is plain text, and pre-request argument/usage errors are plain text on stderr with exit code 2. Multi-year ranges are supported with no calendar-day cap. `--all` is a first-class dynamic selection: the iPhone walks the complete selected `HealthKitRecordCatalog`, queries each ordinary source type plus dedicated activity-summary and medication APIs for its earliest readable date, pins every source-calendar day through today, and returns that exact range before corpus transfer. Static characteristics/inventories are captured as current snapshots and do not fabricate an earlier daily timeline. If any selected historical type cannot be resolved or queried, the request fails rather than claiming a later start is complete. `--all` is mutually exclusive with bounded date flags. `--timeout` must be 5...900 seconds and is reset by validated progress.

## Durable jobs

Every Mac-initiated request is written under Health.md's Application Support directory before it is sent. The record contains the exact `IPhoneExportRequest`, progress, pause/session metadata, bound iPhone/Mac installation IDs, terminal ordinary response, and a fixed `expires_at` exactly seven days after creation. For `--all`, the Mac also persists the iPhone-resolved start/end and exact date identifiers before admitting corpus bytes; retries must present the same pinned range and cannot drift when older records later appear. App relaunch does not change that deadline. `healthmd status --job UUID` inspects the record, while `healthmd resume UUID` resends the exact stored request only to the same iPhone installation after reconnecting.

The iPhone also keeps a protected, backup-excluded outbound journal containing the stable session/fingerprint, acknowledged digest frontier, next HealthKit date, any partially committed daily item, and the one current unacknowledged partition. It advances offsets and deletes bytes only after the Mac's durable acknowledgement. Therefore a terminated/relaunched iPhone does not retain or retransmit the completed gigabytes: it resumes from the Mac frontier and retransmits at most the current 64 MiB partition. The iPhone spool remains bounded to the current item and partition rather than aggregate export size.

The initial export POST and a resume POST are only waiters. Their timeout, Ctrl-C, a closed pipe, or another broken loopback client detaches the waiter and returns `timed_out` or `accepted` when possible; it does not cancel iPhone work, corpus work, or delete the job. Peer disconnect marks the job paused and retains both journals. `healthmd cancel UUID` is the only user control operation that sends cancellation. If the bound iPhone is absent, the cancelled Mac record acts as a tombstone and redelivers cleanup only to that installation on its next hello. Cancellation and expiry may remove internal journals/spools, but never remove files already written to the selected destination.

## File mode

Default `settings_policy: requested_dates_only` uses iPhone formats, metrics, paths, write mode, Lossless Health Records, Daily Note Injection, and Daily Notes Only, but disables roll-ups and summary-only mode for this request. Date selection always comes from the CLI.

`--use-iphone-settings` uses saved settings exactly, including roll-ups, summary-only mode, and Daily Notes Only. Effective granular capture is enabled only for standard file mode: summary-only and Daily Notes Only jobs neither fetch nor transfer a lossless archive even if the saved Lossless Health Records toggle is on.

Current peers negotiate partitioned corpus transfer plus the current `healthmd.healthkit_records` archive version. All-available-history requests require the additive all-history capability and partitioned transfer on both peers; they fail closed instead of turning into a one-day placeholder request. Older peers keep the single-payload path and its 2 GiB ceiling; they are rejected rather than accepting a lossless job that could drop the archive. Summary-only and non-granular jobs retain their legacy compatibility path.

The Mac destination is the root; the iPhone's Health subfolder/templates are appended. When Daily Notes Only is active, the daily-note folder remains root-relative and all aggregate/ZIP/roll-up/individual/provider/data-dictionary outputs are suppressed. File-mode control responses report `daily_notes_updated` and `daily_notes_skipped` when non-zero; `files_written` remains `0` because no additional export file was generated. A successful action records history and consumes one iPhone export action.

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

Current peers use one stable corpus session with a default 48 MiB target (negotiated within 32–64 MiB). Each partition carries exact source dates, byte counts, a SHA-256 digest, a previous-partition digest, and 512 KiB transport frames. Each independently decoded day/item is capped at 64 MiB, while aggregate session bytes use 64-bit counters and are not capped at 2 GiB. Mac acknowledges a partition only after its daily items and durable journal commit. A failed partition is retried with the same identity, and replay does not duplicate daily writes.

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

There is no bearer token in this version; loopback is the authorization boundary. Only the explicit cancel route sends iPhone/transfer/corpus cancellation. Late results after a waiter timeout are persisted and remain retrievable.

## Limitations

This is not fully headless cron. iOS may suspend capture while Health.md is closed, and protected HealthKit data still requires the iPhone to be unlocked enough for reads. A disconnect or app termination pauses a durable v2 job rather than failing it; reopening Health.md and reconnecting the same installations resumes automatically until the fixed seven-day expiry. Legacy peers retain their previous failure behavior. HealthKit read privacy can also make denied access appear successfully empty.

Raw export uses public APIs and current snapshots only. It does not infer unavailable fields or provide deletion tombstone history.

## Implementation notes

- `CanonicalRawCLIModels` preserves canonical daily JSON as strings across sync so exact integer/public serialization is not changed before local-control injection.
- `IPhoneExportRequestSettingsResolver` forces request-scoped lossless capture for strict raw without persisting the setting.
- `ConnectedCorpusTransfer` and `ConnectedCorpusPartitionFile` negotiate and checksum resumable partitions above the legacy aggregate ceiling.
- `MacCorpusExportSessionManager` applies daily items incrementally and journals committed partitions/exact dates.
- `HealthMdControlServer` validates loopback HTTP and streams protected raw-result spools.
- `healthmd` exits non-zero on partial raw results unless `--allow-partial` is explicit.
