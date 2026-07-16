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
4. Validate every retained daily record and capture status.
5. Deduplicate UUID-backed records by UUID and external records by documented external identity.
6. Return `2xx` only after safely accepting the payload.

Health.md treats HTTP 200 through 299 as success. Other statuses fail the action and can expose a bounded response preview to the user.

### API size and privacy

The API envelope can contain exact routes, clinical documents, medication/mood data, ECG measurements, provenance, and base64 binary content. Use HTTPS, minimize selected metrics, and apply health-data retention/security controls. Dense multi-day requests can be large; reduce the range after HTTP 413 or memory pressure.

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
| `source` | Optional; defaults to the only supported source. | `connected_iphone`. HealthKit reads remain on iPhone. |
| `date_range` | Required unless legacy `from` and `to` are supplied. | Inclusive `start` and `end` dates. The CLI limits its range to 366 days. |
| `settings_policy` | Optional; defaults to `requested_dates_only`. | `requested_dates_only` or `current_iphone_settings`. |
| `response_mode` | Optional; defaults to `write_files`. | `write_files` or `raw_json`. |
| `raw_profile` | Optional for legacy requests; required for strict raw. | `canonical_source_records_v1`; valid only with `raw_json`. |
| `wait_timeout_seconds` | Optional; defaults to 300 seconds. | Finite 5 through 900 seconds. |

The localhost server also accepts legacy top-level `from`/`to` dates and camelCase enum aliases: `requestedDatesOnly`, `currentIPhoneSettings`, `writeFiles`, and `rawJSON`. New clients should send the canonical nested date range and snake_case values shown above. Unknown values fail with structured `4xx` JSON rather than silently falling back.

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

`requested_dates_only` uses the iPhone's formats, metrics, paths, write mode, and lossless preference for the requested dates, while disabling roll-ups and summary-files-only behavior for this request.

`current_iphone_settings` mirrors saved settings, including roll-ups and summary-only mode. Effective lossless capture is `includeGranularData && !summaryOnlyModeEnabled`; a true summary-only job does not fetch or transfer a hidden archive.

### Response statuses

The local control response uses these overall statuses:

- `success`
- `partial_success`
- `failure`
- `cancelled`
- `unavailable`
- `timed_out`

Generated examples for every state are indexed in [`generated/automation/`](./generated/automation/).

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
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-03-01 --to 2026-03-15
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
```

Generated CLI requests, responses, errors, and validation examples include:

- [`generated/cli/status-success.json`](./generated/cli/status-success.json)
- [`generated/cli/write-files-export-request.json`](./generated/cli/write-files-export-request.json)
- [`generated/cli/write-files-export-success-response.json`](./generated/cli/write-files-export-success-response.json)
- [`generated/cli/strict-raw-export-request.json`](./generated/cli/strict-raw-export-request.json)
- [`generated/cli/strict-raw-complete-response.json`](./generated/cli/strict-raw-complete-response.json)
- [`generated/cli/strict-raw-partial-response.json`](./generated/cli/strict-raw-partial-response.json)
- [`generated/cli/invalid-strict-raw-success.json`](./generated/cli/invalid-strict-raw-success.json)
- [`generated/cli/cli-structured-errors.json`](./generated/cli/cli-structured-errors.json)

### Strict success validation

Before returning exit zero for an HTTP-200 strict result, the CLI independently verifies:

- exact requested dates;
- expected raw profile/result version;
- each daily schema identifier/version;
- expected canonical archive identifier/version;
- required archives for retained strict days;
- capture status and partial evidence.

A malformed or legacy HTTP-200 success becomes a structured `invalid_strict_raw_success` error and exits non-zero.

### Partial results

A complete-empty day is success. Failed, cancelled, missing, skipped/unsupported, or otherwise incomplete requested branches produce `partial_success`.

- By default strict partial results exit non-zero.
- `--allow-partial` permits exit zero but does not remove diagnostics.
- Automation should still inspect every day and nested archive status.

The generated exit-code matrix is [`generated/cli/exit-codes.md`](./generated/cli/exit-codes.md).

## Operational limits

Strict raw and current lossless file jobs require current peer capabilities and the bounded connected transfer. The final local JSON response can still be large and can expose sensitive data in terminal history or logs. Redirect intentionally, request small ranges, and never place raw output in ordinary diagnostic logging.
