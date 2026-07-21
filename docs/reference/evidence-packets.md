# Compact queries and evidence packets

Health.md's shared query foundation reads **compact context days** and returns typed, evidence-linked results. It is a portable Swift layer with no HealthKit, filesystem, network, CLI, or MCP dependency. CLI and MCP transports are intentionally not part of this contract yet.

These contracts are independent from daily exports:

| Contract | Schema | Version |
|---|---|---:|
| Query request | `healthmd.query_request` | 1 |
| Query response | `healthmd.query_response` | 1 |
| Query error | `healthmd.query_error` | 1 |
| Compact context day | `healthmd.query_context_day` | 1 |
| Evidence packet | `healthmd.evidence_packet` | 1 |

The daily export remains `healthmd.health_data` schema version **7**. Adding or advancing a query or packet contract does not relabel daily export files and does not alter their bytes.

## Access is unlimited; pages are bounded

A query may select explicit metric IDs or `all_available`. It may select an exact inclusive owner-date range or `all_available`. The evaluator dynamically enumerates metric IDs in stored context; it has no hand-maintained query allowlist.

There is no contract-level limit on:

- number of selected metrics;
- length of a date range;
- number of stored days or workouts; or
- total number of result items.

Safety comes from `page.max_items`, `page.max_bytes`, and an opaque `page.cursor`. Every matching item remains reachable by following `next_cursor` until it is absent. Ordering and page boundaries are deterministic for the same request and corpus. Cursors are authenticated and bound to both the semantic query and corpus digest, so alteration or reuse with a different query/corpus fails. A single indivisible item larger than `max_bytes` is returned alone with a `single_item_exceeds_page_bytes` limitation rather than creating an inaccessible tail.

Changing page controls does not change query meaning. The cursor binds metric selection, date selection, and operation, but not the next page's byte/item preference.

Example request:

```json
{
  "schema": "healthmd.query_request",
  "schema_version": 1,
  "metrics": { "type": "all_available" },
  "dates": { "type": "all_available" },
  "operation": { "type": "metric_series" },
  "page": { "max_items": 250, "max_bytes": 262144 }
}
```

Exact selections use:

```json
{
  "metrics": { "type": "explicit", "metric_ids": ["steps", "resting_heart_rate"] },
  "dates": {
    "type": "exact",
    "range": { "start_date": "2026-01-01", "end_date": "2026-03-31" }
  }
}
```

Dates are compact-day `owner_date` values. Day intervals also preserve their UTC boundary timestamps and captured IANA `calendar_timezone`; this avoids reassigning data when daylight-saving transitions or the reader's current timezone differ.

## Typed values

`HealthMdQueryValue` is a tagged union. Version 1 preserves:

- quantity plus canonical unit;
- duration in seconds;
- signed count;
- string;
- category identifier, optional display label, and optional raw value;
- Boolean;
- UTC timestamp;
- calendar date;
- nested arrays; and
- unknown future tags with a recursively typed JSON-shaped payload.

NaN and positive/negative infinity are rejected. Missing values are absent values with an explicit availability status, never a fabricated numeric zero. A real zero is encoded as a typed quantity/count/duration.

## Missingness and coverage

Availability statuses are:

- `available`
- `complete_empty`
- `partial`
- `failed`
- `unsupported`
- `skipped`
- `cancelled`
- `not_requested`
- `legacy_unavailable`
- `redacted`
- `not_synchronized`

`complete_empty` means a successfully represented scope with no matching observations. It is different from a missing day and from zero. Query responses and packets include structured coverage with requested and available ranges, days considered, days with values, and status-bearing missing intervals. Responses also carry the source schema/version/digest set and the evidence references used by the returned page. Metric and context limitations remain structured `{code, message}` values.

## Compact context days

A `healthmd.query_context_day` v1 contains:

- owner date, exact half-open interval, and calendar timezone;
- source schema, source version, and source digest;
- day availability;
- dynamically named metric observations with typed values or explicit missingness;
- compact workouts with typed details;
- evidence entries; and
- limitations.

Metric `observation_id` and workout `workout_id` provide stable deduplication identities. Repeated views of the same identity are not summed or listed twice. Distinct identities are retained even when values and timestamps happen to match. Each projected summary metric also carries the authoritative v7 data-dictionary `daily_aggregation` (`sum`, `average`, `minimum`, `maximum`, `latest`, `count`, `duration_sum`, `first_time`, `last_time`, `list`, `category_latest`, or `weighted_average`) rather than asking a query consumer to infer semantics from its name.

### HealthData projection

`HealthMdQueryContextProjector` converts one captured `HealthData` day into this contract. It uses the current metric catalog, `HealthMetricExportMapping`, `ExportFrontmatterMetricBuilder`, and `HealthMetricDataDictionary`; it does not maintain a competing summary schema. Callers may supply an explicit enabled metric-ID set and explicit unavailable statuses known only by a corpus/synchronization layer.

The projector:

- preserves canonical v7 metric IDs, units, typed values, source timezone boundaries, source schema/version, and a deterministic source-projection SHA-256 digest;
- treats an optional numeric zero as an available value, but never converts default-zero compatibility fields into observations without summary or archive evidence;
- derives `complete_empty`, `failed`, `unsupported`, `skipped`, and `cancelled` from query manifests, and keeps `partial`, `not_requested`, `legacy_unavailable`, and `not_synchronized` distinct;
- emits stable evidence for every represented summary key, canonical UUID, external identity, query result, integrity warning, and partial failure;
- projects workout identity, exact start/end timestamps, and typed factual details;
- keeps archive-only and future metric IDs reachable through typed evidence details; and
- retains provider-native daily sidecars as external evidence instead of silently normalizing them into Apple Health metrics.

Input array order does not affect context ordering, evidence IDs, canonical bytes, or the source digest. The projection contains observations and source limitations only; it does not diagnose, recommend, infer causation, or label a change better or worse.

This projector and compact query contract remain independent of `healthmd.health_data`; the daily export schema stays version **7**.

## Evidence locators

Evidence references include an `evidence_id`, exact source descriptor, and one locator:

- daily summary key;
- canonical HealthKit UUID;
- canonical external identity;
- query-manifest result;
- integrity warning; or
- partial failure.

Resolution requires all three parts to match: evidence ID, locator, and source schema/version/digest. An ID collision cannot redirect a fact to a different source object.

## Operations

### Metric series

Returns every selected stored metric observation in owner-date, metric-ID, and observation-ID order. `all_available` is the union discovered from compact context, not a fixed list.

### Period comparison

The caller supplies a typed aggregation descriptor for each metric: `sum`, `average`, `minimum`, `maximum`, `latest`, `count`, or `duration_sum`, with an optional expected unit. The evaluator does not guess aggregation semantics from a metric name. Missing periods return no aggregate value rather than zero. Unit mismatches fail rather than silently converting or mixing values.

Comparison direction is only `increased`, `decreased`, `unchanged`, or `not_comparable`. Results never label change as better or worse. A zero first-period value produces no percent change and a `zero_baseline` limitation; absolute change remains available when types and units match.

### Workout listing

Returns every distinct workout through the same cursor paging model, ordered by start timestamp and stable workout identity. There is no total workout cap.

### Coverage

Returns structured corpus/date coverage without requiring metric result materialization.

### Evidence packet derivation

Version 1 supports factual packet kinds:

- `daily_wellness`
- `training`
- `doctor_visit`

The caller must inject an `HealthMdEvidenceScope`. Requested metric IDs and detail IDs outside that scope fail closed; training workout details are included only when workout access is explicitly allowed. Packet facts report stored values and evidence. They do not infer a condition, diagnose, recommend treatment, or assign beneficial/harmful direction.

Packet facts are paged when needed. Follow `next_cursor` to reach all facts. Each returned packet fragment states when more factual items remain.

## Determinism and packet IDs

Canonical query JSON uses sorted object keys, unescaped slashes, and fixed nine-digit RFC 3339 UTC timestamps. Semantically unordered packet facts, evidence references, source descriptors, and limitations are normalized before hashing.

`packet_id` is the lowercase SHA-256 digest of the packet's semantic fields:

- packet schema/version and kind;
- date range;
- normalized facts and evidence;
- coverage;
- source descriptors; and
- limitations.

The digest excludes `packet_id` itself and volatile metadata such as `metadata.generated_at` and producer information. Reordering equivalent inputs or regenerating the same packet at another time therefore preserves its semantic ID, while canonical full-packet bytes still retain the actual metadata.

## Errors

Transport adapters should encode failures as `healthmd.query_error` v1 with a stable code, human-readable message, retryability flag, and typed details. Invalid page controls, malformed/tampered cursors, cursor/query mismatch, invalid date ranges, unit/aggregation mismatch, unsupported operations, and evidence-scope violations are distinct failures in the shared evaluator.
