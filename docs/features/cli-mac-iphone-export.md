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
- Current peer capabilities for strict raw or lossless file jobs; older peers remain eligible only for negotiated summary/non-granular file exports.
- A selected writable Mac folder for file mode; strict raw mode does not require one.

## Commands

```bash
healthmd status
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-07-01 --to 2026-07-07
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
healthmd export --iphone --yesterday --use-iphone-settings
```

Executed `status` and `export` requests print machine-readable JSON, including control-server and strict-validation failures. `--help` is plain text, and pre-request argument/usage errors are plain text on stderr with exit code 2. Multi-year ranges are supported with no calendar-day cap; `--timeout` must be 5...900 seconds and is reset by validated progress.

## File mode

Default `settings_policy: requested_dates_only` uses iPhone formats, metrics, paths, write mode, Lossless Health Records, and side effects, but disables roll-ups and summary-only mode for this request. Date selection always comes from the CLI.

`--use-iphone-settings` uses saved settings exactly, including roll-ups and summary-only mode. Effective granular capture is `includeGranularData && !summaryOnlyModeEnabled`: a true summary-only job neither fetches nor transfers a lossless archive even if the saved Lossless Health Records toggle is on.

Lossless file jobs require both size-bounded transfer support and the current `healthmd.healthkit_records` archive version on the peer. Older peers are rejected instead of accepting a job that could drop the archive. Summary-only and non-granular jobs retain their legacy compatibility path.

The Mac destination is the root; the iPhone's Health subfolder/templates are appended. A successful action records history and consumes one iPhone export action.

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
- before exiting zero for any HTTP-200 strict response, the CLI independently verifies the exact requested date set, raw-result/profile versions, schema-v7 daily documents, and current canonical archive version. A malformed or legacy success becomes machine-readable `invalid_strict_raw_success` diagnostics and exits non-zero.

Automation should inspect response `status`, each day, `capture_summary`, `missing_dates`, and every nested daily `raw_capture_status` before accepting a run.

## Bounded transfer and output size

Lossless file jobs and strict raw results travel iPhone → Mac through the checksum-validated bounded connected-transfer protocol (512 KiB maximum chunks, 8,192 chunks, 2 GiB declared size). The day-count limit is removed, but this byte ceiling still rejects an unusually large prepared payload rather than exhausting either device. Strict raw refuses an unbounded whole-payload fallback. Summary-only and non-granular file jobs remain compatible with older negotiated file transports.

The localhost control response is still final JSON and can be large. Capturing/serializing dense HealthKit data and constructing the final CLI response may use substantial memory. Request smaller date ranges for ECGs, routes, clinical documents, or attachments, and avoid logging raw health payloads.

## Local control boundary

The Mac HTTP control server:

- listens only on `127.0.0.1` and `::1` and rejects non-loopback accepted peers;
- limits headers to 16 KiB and request bodies to 256 KiB;
- has a 10-second receive deadline;
- requires JSON and explicit content length for `POST /v1/exports`;
- validates finite 5...900-second waits.

There is no bearer token in this version; loopback is the authorization boundary. Disconnect/timeouts cancel the iPhone request when possible, and late results are ignored.

## Limitations

This is not fully headless cron. A suspended/locked iPhone, protected HealthKit store, closed app, or disconnected peer returns structured failure. HealthKit read privacy can also make denied access appear successfully empty.

Raw export uses public APIs and current snapshots only. It does not infer unavailable fields or provide deletion tombstone history.

## Implementation notes

- `CanonicalRawCLIModels` preserves canonical daily JSON as strings across sync so exact integer/public serialization is not changed before local-control injection.
- `IPhoneExportRequestSettingsResolver` forces request-scoped lossless capture for strict raw without persisting the setting.
- `ConnectedTransfer` bounds/checksums strict raw and current file jobs.
- `HealthMdControlServer` validates loopback HTTP and returns the raw-result object.
- `healthmd` exits non-zero on partial raw results unless `--allow-partial` is explicit.
