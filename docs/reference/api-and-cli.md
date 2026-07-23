# API and CLI

Health.md exposes three independent automation boundaries:

1. **API Endpoint export** sends daily records from iPhone to a configured HTTP(S) service.
2. **Mac export CLI/local control API** asks an open connected iPhone to export files or return strict canonical JSON.
3. **Local query API/CLI/MCP** navigates canonical health data, uses a disposable encrypted index for derived compatibility views, and starts directly scoped acquisition.

`healthmd.health_data` v7 is the single public health-data source of truth. Export/API/job/query wrappers may have protocol versions for compatibility, paging, receipts, and failures, but they are not alternative health schemas. Direct CLI extraction emits canonical daily documents or selected canonical subtrees; typed sleep/alignment/comparison results are explicitly derived protocol views with source evidence.

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

The server enforces IPv4/IPv6 loopback peers, 16 KiB headers, a 256 KiB request body, explicit content length for POST, JSON content, and a bounded receive deadline. All routes are intentionally unattributed: loopback reachability is the boundary, never caller identity. Do not expose or proxy port `17645` to another machine.

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
| `raw_profile` | Optional for legacy requests; required for validated raw transport. | `canonical_source_records_v1` for full archival capture or `health_data_projection` for canonical scoped extraction; valid only with `raw_json`. |
| `canonical_selection` | Required only with `health_data_projection`. | Request-scoped metrics/categories, source, summary/lossless detail, object paths, and field pointers. Selection narrows acquisition; it never changes saved iPhone settings. |
| `wait_timeout_seconds` | Optional; defaults to 300 seconds. | Finite 5 through 900 seconds. |

The localhost server also accepts legacy top-level `from`/`to` dates and camelCase enum aliases: `explicitRange`, `allAvailable`, `requestedDatesOnly`, `currentIPhoneSettings`, `writeFiles`, and `rawJSON`. New clients should send the canonical nested date range and snake_case values shown above. Unknown values fail with structured `4xx` JSON rather than silently falling back.

Complete generated requests:

- [`generated/automation/control-write-files-request.json`](./generated/automation/control-write-files-request.json)
- [`generated/cli/scoped-write-files-export-request.json`](./generated/cli/scoped-write-files-export-request.json)
- [`generated/automation/control-strict-raw-request.json`](./generated/automation/control-strict-raw-request.json)
- [`generated/cli/canonical-health-data-extraction-request.json`](./generated/cli/canonical-health-data-extraction-request.json)

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

`requested_dates_only` uses the iPhone's formats, paths, write mode, Daily Note Injection, and Daily Notes Only for the requested dates, while disabling roll-ups and summary-files-only behavior. It normally keeps saved metrics/lossless preference; an optional `canonical_selection` replaces metric/detail scope for that request before HealthKit reads. This works for ordinary file jobs as well as `health_data_projection` output.

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

## Local query API

`/v1/agent/*` uses the same strictly loopback-only listener as the export routes. There are no bearer credentials, registrations, grants, or access profiles. Any local process that can connect while Health.md is running can issue requests, so port `17645` must not be exposed or proxied to another machine.

| Method and route | Meaning |
|---|---|
| `GET /v1/agent/capabilities` | Supported contracts, direct-scope behavior, and bounded page controls. |
| `GET /v1/agent/metrics` | Canonical queryable metric IDs, names, categories, units, and availability requirements. It does not claim HealthKit read authorization. |
| `GET /v1/agent/readiness` | Encrypted-store and fresh-iPhone readiness with structured next actions and no health values. |
| `POST /v1/agent/query` | Execute a directly scoped typed cached query. |
| `POST /v1/agent/evidence` | Execute a directly scoped `derive_packet` request. |
| `POST /v1/agent/refresh` | Acquire explicit metrics, sources, dates, and detail on the connected open iPhone. |
| `/v1/agent/jobs/{id}` | Local status; `/resume` and `/cancel` are POST actions. |

The former profiles and activity endpoints return `410 removed_endpoint`.

Query responses are bounded by `max_items` and `max_bytes`. A nonterminal response returns an opaque `next_cursor`; complete traversal has no total date, metric, provider, or result cap. Missing/unsupported/failed data stays explicit and is never converted to zero. Evidence packets are factual and do not diagnose, recommend treatment, infer causation, or label results better/worse.

Refresh uses a dedicated partitioned `encrypted_context` mode. It writes no export files and does not inherit saved iPhone metrics, formats, or folders. The request supplies the complete metric, source, date, and detail selection. That immutable `CanonicalHealthDataSelection` is persisted in Mac and iPhone recovery records. When Apple Health is selected, the iPhone checks only the selected ordinary read types. All-history uses complete catalog-backed Apple Health discovery plus complete provider-native history cursors, and provider-only requests skip HealthKit entirely. Provider fetch diagnostics verify each requested provider/day without translating provider-native sidecars into synthetic Apple-style values. The Mac commits each deterministic compact day to its Keychain-encrypted store before acknowledging the partition.

See [Local query API](../features/agent-local-api.md), [Evidence packets](./evidence-packets.md), and [Local MCP](../features/local-mcp.md).

## Canonical `health_data` extraction

The preferred direct-data command is selection-pushed canonical extraction:

```bash
healthmd extract --category Sleep --last 7
healthmd extract --metric workouts --last 30 --object workouts --format jsonl
healthmd extract --metric workouts --last 30 --object records --detail lossless --output workout-records.json
healthmd extract --all-metrics --yesterday --detail summary
```

The CLI sends `raw_profile: health_data_projection` only as a bounded durable transport choice. `canonical_selection` is resolved and validated on Mac, persisted in the request fingerprint, and applied on iPhone before HealthKit reads. Summary requests do not capture `healthkit_record_archive`; lossless requests query only HealthKit types backing the selected metrics. Object and field pointers reduce emitted JSON, while metric/category/detail selection reduces actual iPhone acquisition and transfer.

After checksum/range/profile validation, the CLI strips the raw-result transport wrapper. JSON output uses a protocol result with ordinary v7 documents under `health_data`, or exact JSON Pointer/value/status entries under `projections`, plus `healthmd.extract_receipt` containing selection, per-day outcomes, capture counts, and missing dates. Projection objects reference their source v7 document but do not carry `schema: healthmd.health_data`, so a selected subtree cannot masquerade as a complete daily export. JSONL emits one data item per line and writes the receipt to stderr or `OUTPUT.receipt.json`. Unselected data is not fabricated as zero; absent selected paths report complete-empty or the day’s incomplete status. `raw_capture_status: not_requested` means lossless records were not requested. Whole canonical documents stream by byte range; pointer projection decodes at most one bounded day at a time. A partial run emits no data unless `--allow-partial` is explicit. Current canonical extraction supports Apple Health only and rejects other sources instead of translating provider sidecars into a competing shape.

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

Executed `status`, `export`, `extract`, `metrics`, and `query` requests write machine-readable JSON to stdout or the explicit protected output file, including HTTP/control failures and strict-validation errors. `--help` is intentionally plain text, and argument/usage failures that occur before a request are plain text on stderr with exit code 2. Automation should validate arguments up front and parse stdout as JSON only for an executed command.

```bash
healthmd status
healthmd status --job 00000000-0000-4000-8000-000000000101
healthmd doctor --json
healthmd export --iphone --yesterday
healthmd export --iphone --last 7
healthmd export --iphone --from 2026-03-01 --to 2026-03-15
healthmd export --iphone --all
healthmd extract --category Sleep --last 7
healthmd extract --metric resting_heart_rate --last 30 --object heart --format jsonl --output heart.jsonl
healthmd export --iphone --last 7 --category Sleep --detail summary
healthmd export --iphone --last 30 --metric workouts --detail lossless
healthmd export --iphone --all --raw --output complete-health-corpus.json
healthmd export --iphone --yesterday --raw
healthmd export --iphone --last 7 --raw --allow-partial
healthmd export --iphone --last 3650 --raw --output health-corpus.json
healthmd resume 00000000-0000-4000-8000-000000000101 --timeout 300
healthmd resume 00000000-0000-4000-8000-000000000101 --output health-corpus.json --allow-partial
healthmd cancel 00000000-0000-4000-8000-000000000101

healthmd metrics list
healthmd metrics list --category Sleep
healthmd query --metric sleep_total --metric sleep_deep --from 2026-07-21 --to 2026-07-22 --all-pages
healthmd query --category Sleep --yesterday --cached
healthmd query --metric resting_heart_rate --last 30 --reuse-covered --progress-json --format table
healthmd sleep sessions --last-nights 14 --window first:4h --physiology-metric heart_rate
healthmd training align --last 14 --workout running --sleep-window first:4h
healthmd workouts --last 14
healthmd coverage --category Sleep --last 14
healthmd compare --metric steps:sum --first-from 2026-07-01 --first-to 2026-07-07 --second-from 2026-07-08 --second-to 2026-07-14
healthmd evidence training --category Sleep --workout-detail distance --last 14
healthmd agent capabilities
# MCP clients can call healthmd_doctor for local readiness.
healthmd agent query --input query.json
healthmd agent query --input - < query-with-next-cursor.json
healthmd agent evidence --input evidence-query.json
healthmd agent refresh --input refresh.json
healthmd agent job status 00000000-0000-4000-8000-000000000102
healthmd agent job resume 00000000-0000-4000-8000-000000000102 --timeout 300
healthmd agent job cancel 00000000-0000-4000-8000-000000000102
```

`healthmd doctor` (or explicit `healthmd doctor --json`) emits `healthmd.cli_doctor` v1 with Mac/iPhone connectivity, encrypted owner-date coverage, and fresh-iPhone capability. It never prints health values. `healthmd metrics list` returns the canonical catalog. High-level `sleep sessions`, `training align`, `workouts`, `coverage`, `compare`, and `evidence training` commands construct first-class sleep-session/window, deterministic workout-to-preceding/following-sleep alignment, typed workout-listing, coverage, explicit period-comparison, and factual training-packet operations while reusing the same fresh/cached direct-scope flow. Sleep sessions carry stable identity, local timezone semantics, midnight-spanning calendar dates, explicit completeness/untracked duration, selected stage totals, adjacent-day physiology coverage, and exclusions. Session and alignment commands acquire lossless sleep intervals and the complete canonical sleep-stage metric set; aggregate-only cached sessions remain explicitly `aggregated`, never claim interval observation coverage, and fixed windows never apportion daily aggregates. Technical adjacent-owner-day reads are limited to one day for sessions and two for alignment and do not return unrelated data. Overlapping stage sources are de-duplicated for total asleep duration. Training alignment returns timing, coverage, exclusions, and evidence only; it makes no causal or medical claim. Aggregation semantics are caller-selected rather than inferred.

The high-level `healthmd query` command validates and expands metric/category selections, sends the complete source/date/metric/detail scope directly, performs fresh iPhone acquisition by default, and then executes a typed query; `--cached` skips acquisition. Its `healthmd.cli_metric_query` v1 envelope preserves acquisition diagnostics and the nested query response. It reports `requested_scope_status`, `corpus_status`, and `unrelated_skips` separately: unrelated skipped/unsupported capture branches do not downgrade a complete requested metric/date scope, while corpus completeness remains visible. Fresh completion is computed only from owner-day blobs replaced after that refresh began and verifies every requested metric × source/provider × day cell, so stale cached values or another provider cannot mask a partial acquisition. Without `--all-pages`, the first high-level query page preserves `next_cursor`; when another page exists, the outer status is `partial_success` instead of claiming complete traversal. `--all-pages` follows opaque cursors with repeat checks while enforcing bounded aggregate byte/page ceilings in both CLI and MCP; callers must narrow scope or page manually when a ceiling is reached. It keeps the first response under `query`, preserves traversed versioned responses under `pages`, and reports terminal traversal plus page/item/fact/evidence counts in `healthmd.cli_query_receipt` v1. `--progress-json` writes phase/page JSONL to stderr; default stdout remains one compatible JSON envelope. `--format table` opts into a deliberately lossy human TSV projection whose comment footer retains coverage, sources, limitations, completion status, and unrelated-skip diagnostics. `--reuse-covered` skips fresh acquisition only after complete metric-aware summary coverage and is disabled for lossless or newly projected sleep-session operations. Low-level query, evidence, and refresh bodies remain exact JSON objects supplied with `--input PATH|-` or `--json JSON`; the CLI does not silently widen or narrow those bodies. Follow `next_cursor` until null for manual complete results.

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

`all_available` requires current peers. The iPhone resolves its earliest available selected record across the complete runtime HealthKit query catalog (including dedicated non-sample discovery where available) and every source-calendar day through today, then the Mac persists the exact resolved identifiers before transfer. If a selected historical type fails or cannot be resolved, Health.md fails closed instead of reporting a later readable date as complete. Resume uses that immutable set, so the result remains reproducible even if the Health store later gains older records. The full resolved corpus remains reachable; partitioning is a resource boundary, not a history cap.

Current strict raw and lossless file jobs use stable partitioned sessions: 48 MiB default targets negotiated within 32–64 MiB, 64 MiB physical maximum, 512 KiB transport frames, and no 2 GiB aggregate protocol cap. The iPhone journal remains bounded to current uncommitted item/partition bytes and resumes after app relaunch from the Mac's acknowledged frontier, so completed gigabytes are not retransmitted. Durable jobs expire seven days after creation without extending on progress. Mixed-version peers retain the legacy 2 GiB single-payload ceiling and in-process-only retry. Available storage and one-day HealthKit density remain practical limits. Raw JSON can expose sensitive data in terminal history or logs; prefer `--output`, protect the file, and never place raw output in ordinary diagnostic logging.
