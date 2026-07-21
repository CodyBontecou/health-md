# API and CLI

Health.md exposes two automation boundaries:

1. **API Endpoint export** sends daily records from iPhone to a configured HTTP(S) service.
2. **Mac CLI/local control API** asks an open connected iPhone to export files or return strict canonical JSON.

Both reuse the daily `healthmd.health_data` contract. Their envelopes and transport status are versioned independently.

## API Endpoint export

The iPhone sends an HTTP POST with `Content-Type: application/json`. When configured, its access token is sent as an Authorization value. Plain values become `Bearer <token>`; values already beginning with `Bearer ` or `Basic ` are sent as entered.

### Envelope

| Field | Type | Meaning |
|---|---|---|
| `schema` | string | `healthmd.api_export`. |
| `schema_version` | integer | API envelope version. |
| `daily_record_schema` | string | `healthmd.health_data`. |
| `daily_record_schema_version` | integer | Current daily version, `7`. |
| `exported_at` | timestamp | Envelope creation time. |
| `source` | string | Exporting platform/source, normally `ios`. |
| `date_range.start` | date | Requested first date. |
| `date_range.end` | date | Requested last date. |
| `record_count` | integer | Number of retained daily documents. |
| `records` | array | Complete daily schema-v7 objects. |
| `failed_date_details` | array | Dates that failed before a daily document could be retained. |
| Provider sidecars | conditional | Independent v2 external/provider records when an integration is enabled. |

A complete-empty lossless daily record is retained because its query manifest is evidence. A date that cannot produce a daily record is represented in `failed_date_details` rather than as a fabricated empty day.

Complete generated envelopes:

- [`generated/automation/api-export-v1.json`](./generated/automation/api-export-v1.json)
- [`generated/automation/api-export-v2-provider-sidecar.json`](./generated/automation/api-export-v2-provider-sidecar.json)

### Endpoint acceptance

A receiver should:

1. Validate Authorization and `Content-Type`.
2. Branch on API, daily, archive, and provider schema versions independently.
3. Accept idempotent repeats for the same date range.
4. Treat each repeated `records[].date` as a complete replacement snapshot and atomically upsert the newest revision rather than appending duplicate daily documents.
5. Validate every retained daily record and capture status.
6. Deduplicate UUID-backed records by UUID and external records by documented external identity.
7. Return `2xx` only after safely accepting the payload.

Health.md treats HTTP 200 through 299 as success. Other statuses fail the action and can expose a bounded response preview to the user. Every run re-queries HealthKit and rebuilds the selected daily records. Manual same-day exports and scheduled Today Refresh therefore send the latest complete snapshot, not a delta from the prior request; `exported_at` identifies the envelope revision.

### API size and privacy

The API envelope can contain exact routes, clinical documents, medication/mood data, ECG measurements, provenance, and base64 binary content. Use HTTPS, minimize selected metrics, and apply health-data retention/security controls.

Health.md uploads batches sequentially with default limits of 7 calendar days and an 8 MiB encoded-body target. The exact measured JSON bytes are sent. A single daily record is indivisible and may exceed the byte target; after HTTP 413, select fewer metrics, disable Lossless Health Records, or raise the receiver's request limit.

## Local Mac control API

The standalone CLI calls a localhost HTTP server owned by the running Health.md Mac app.

```text
GET  /v1/status
POST /v1/exports
```

The server enforces IPv4/IPv6 loopback peers, 16 KiB headers, a 256 KiB request body, explicit content length for POST, JSON content, and a bounded receive deadline. There is no bearer token in this version; loopback is the authorization boundary.

### Status

The status response reports:

- Mac app state;
- iPhone connection, display name, and trigger capability;
- destination selection, writability, path, and display name;
- current active export, if any.

Complete generated object: [`generated/automation/control-status.json`](./generated/automation/control-status.json).

### Export request

```json
{
  "source": "connected_iphone",
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-03-15",
    "end": "2026-03-15"
  },
  "settings_policy": "requested_dates_only",
  "response_mode": "write_files",
  "wait_timeout_seconds": 120
}
```

Request fields:

| Field | Presence/default | Values/meaning |
|---|---|---|
| `job_id` | Optional for custom clients; current CLI always sends one. | UUID used to cancel the connected session if the HTTP client disconnects. |
| `source` | Optional; defaults to the only supported source. | `connected_iphone`. HealthKit reads remain on iPhone. |
| `date_selection` | Optional; defaults to `explicit_range`. | `explicit_range` or `all_available`. The latter is dynamically resolved and pinned by the iPhone. |
| `date_range` | Required for `explicit_range` unless legacy `from` and `to` are supplied; forbidden for `all_available`. | Inclusive `start` and `end` dates. Multi-year ranges are supported; there is no calendar-day cap. |
| `settings_policy` | Optional; defaults to `requested_dates_only`. | `requested_dates_only` or `current_iphone_settings`. |
| `response_mode` | Optional; defaults to `write_files`. | `write_files` or `raw_json`. |
| `raw_profile` | Optional for legacy requests; required for strict raw. | `canonical_source_records_v1`; valid only with `raw_json`. |
| `wait_timeout_seconds` | Optional; defaults to 300 seconds. | Finite 5 through 900 seconds. |

The localhost server also accepts legacy top-level `from`/`to` dates and camelCase enum aliases: `explicitRange`, `allAvailable`, `requestedDatesOnly`, `currentIPhoneSettings`, `writeFiles`, and `rawJSON`. New clients should send the canonical nested date range and snake_case values shown above. Unknown values fail with structured `4xx` JSON rather than silently falling back.

Complete generated requests:

- [`generated/automation/control-write-files-request.json`](./generated/automation/control-write-files-request.json)
- [`generated/automation/control-strict-raw-request.json`](./generated/automation/control-strict-raw-request.json)

A direct localhost request looks like:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/status

curl --fail-with-body --max-time 130 \
  -H 'Content-Type: application/json' \
  --data @docs/reference/generated/automation/control-write-files-request.json \
  http://127.0.0.1:17645/v1/exports
```

The `healthmd` CLI is preferred because it validates arguments, strict response contracts, and exit behavior. Direct control requests remain loopback-only.

### Settings policies

`requested_dates_only` uses the iPhone's formats, metrics, paths, write mode, lossless preference, Daily Note Injection, and Daily Notes Only for the requested dates, while disabling roll-ups and summary-files-only behavior for this request.

`current_iphone_settings` mirrors saved settings, including roll-ups, summary-only mode, and Daily Notes Only. Effective lossless capture is limited to standard file mode; summary-only and Daily Notes Only jobs do not fetch or transfer a hidden archive.

### Response statuses

The local control response uses these overall statuses:

- `success`
- `partial_success`
- `failure`
- `cancelled`
- `unavailable`
- `timed_out`

Generated examples for every state are indexed in [`generated/automation/`](./generated/automation/).

File-mode responses normally report `files_written` and `external_record_count`. When Daily Notes Only is active, `files_written` remains `0` and the response adds `daily_notes_updated` and, when applicable, `daily_notes_skipped`. Daily Notes Only requires a current Mac capability and cannot silently downgrade to aggregate-file output.

## Strict raw profile

Strict raw uses:

```json
{
  "response_mode": "raw_json",
  "raw_profile": "canonical_source_records_v1"
}
```

It temporarily forces Lossless Health Records for the request without changing the saved iPhone preference. It writes no files and returns `healthmd.raw_result` version 1.

This strict profile currently captures canonical Apple Health daily records only. It does not fetch or embed connected-provider sidecars. Provider sidecars remain available through file-writing jobs, legacy raw requests without `raw_profile`, and `healthmd.api_export` v2 under `external_records`.

The result preserves public daily JSON as canonical strings during connected transfer, then injects parsed public objects into the local control response without round-tripping through an internal Codable representation.

A strict result describes:

- the requested profile/version and exact date range;
- retained daily schema-v7 records;
- per-day states such as complete, complete-empty, warning, partial, failed, cancelled, or missing;
- aggregate query status counts;
- integrity warning counts/codes;
- partial-failure types;
- missing dates;
- overall completion status.

Complete examples:

- [`generated/automation/raw-result-complete.json`](./generated/automation/raw-result-complete.json)
- [`generated/automation/raw-result-partial.json`](./generated/automation/raw-result-partial.json)

## CLI

Executed `status` and `export` requests write machine-readable JSON to stdout, including HTTP/control failures and strict-validation errors. `--help` is intentionally plain text, and argument/usage failures that occur before a request are plain text on stderr with exit code 2. Automation should validate arguments up front and parse stdout as JSON only for an executed command.

```bash
healthmd status
healthmd status --job 00000000-0000-4000-8000-000000000101
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-03-01 --to 2026-03-15
healthmd export --iphone --all
healthmd export --iphone --all --raw --output complete-health-corpus.json
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
healthmd export --iphone --last 3650 --raw --output health-corpus.json
healthmd resume 00000000-0000-4000-8000-000000000101 --timeout 300
healthmd resume 00000000-0000-4000-8000-000000000101 --output health-corpus.json --allow-partial
healthmd cancel 00000000-0000-4000-8000-000000000101
```

Current connected exports are durable jobs rather than the lifetime of one HTTP request. Responses and `active_export` may include `durable`, `state`, `session_id`, `paused`, `processed_days`, `total_count`/`total_days`, `committed_partitions`, `committed_bytes`, `fraction_complete`, and the fixed `expires_at`. A waiter timeout or disconnected CLI does not cancel the job. Resume reuses the exact request and same bound iPhone/Mac installations; only the explicit cancel command terminates it.

Generated CLI requests, responses, errors, and validation examples include:

- [`generated/cli/status-success.json`](./generated/cli/status-success.json)
- [`generated/cli/all-history-strict-raw-export-request.json`](./generated/cli/all-history-strict-raw-export-request.json)
- [`generated/cli/write-files-export-request.json`](./generated/cli/write-files-export-request.json)
- [`generated/cli/write-files-export-success-response.json`](./generated/cli/write-files-export-success-response.json)
- [`generated/cli/strict-raw-export-request.json`](./generated/cli/strict-raw-export-request.json)
- [`generated/cli/strict-raw-complete-response.json`](./generated/cli/strict-raw-complete-response.json)
- [`generated/cli/strict-raw-partial-response.json`](./generated/cli/strict-raw-partial-response.json)
- [`generated/cli/invalid-strict-raw-success.json`](./generated/cli/invalid-strict-raw-success.json)
- [`generated/cli/cli-structured-errors.json`](./generated/cli/cli-structured-errors.json)

### Strict success validation

For a current partitioned response, Mac validates every exact source date, raw profile/result version, daily schema/archive, and capture status while composing the result spool. The CLI then verifies Mac's strict-validation headers, requested range/count, and the complete streamed body SHA-256 before writing stdout or `--output PATH`.

Mixed-version whole responses retain the previous independent CLI object validation. A malformed or legacy HTTP-200 success becomes a structured error and exits non-zero.

### Partial results

A complete-empty day is success. Failed, cancelled, missing, skipped/unsupported, or otherwise incomplete requested branches produce `partial_success`.

- By default strict partial results exit non-zero.
- `--allow-partial` permits exit zero but does not remove diagnostics.
- Automation should still inspect every day and nested archive status.

The generated exit-code matrix is [`generated/cli/exit-codes.md`](./generated/cli/exit-codes.md).

## Operational limits

`all_available` requires current peers. The iPhone resolves its earliest available selected record and every source-calendar day through today, then the Mac persists the exact resolved identifiers before transfer. Resume uses that immutable set, so the result remains reproducible even if the Health store later gains older records. The full resolved corpus remains reachable; partitioning is a resource boundary, not a history cap.

Current strict raw and lossless file jobs use stable partitioned sessions: 48 MiB default targets negotiated within 32–64 MiB, 64 MiB physical maximum, 512 KiB transport frames, and no 2 GiB aggregate protocol cap. The iPhone journal remains bounded to current uncommitted item/partition bytes and resumes after app relaunch from the Mac's acknowledged frontier, so completed gigabytes are not retransmitted. Durable jobs expire seven days after creation without extending on progress. Mixed-version peers retain the legacy 2 GiB single-payload ceiling and in-process-only retry. Available storage and one-day HealthKit density remain practical limits. Raw JSON can expose sensitive data in terminal history or logs; prefer `--output`, protect the file, and never place raw output in ordinary diagnostic logging.
