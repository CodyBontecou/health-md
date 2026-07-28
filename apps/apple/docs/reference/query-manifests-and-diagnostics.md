# Query manifests and diagnostics

A non-empty archive does not prove complete capture. Health.md records what it planned, what ran, what returned, and what failed.

Consumers should evaluate three layers:

1. Daily `raw_capture_status`.
2. Archive `capture_status` and every `query_manifest.results` entry.
3. Integrity warnings and daily exporter partial failures.

## Capture status

| Value | Meaning | Archive expected? |
|---|---|---:|
| `complete` | Every planned supported branch completed without failure, cancellation, skip, or unsupported result. | Yes when requested; it may be empty. |
| `partial` | At least one requested branch failed, was cancelled, skipped, unsupported, or otherwise incomplete. | Usually; successful siblings are retained. |
| `not_requested` | Lossless Health Records was explicitly off. | No. |
| `legacy_unavailable` | Older persisted/connected data cannot supply the canonical archive. | No. |

The archive's own status is authoritative when the archive is present.

## Query result fields

| Field | Type | Meaning |
|---|---|---|
| `identifier` | string | Deterministic planned-query identifier. |
| `object_type_identifier` | optional string | HealthKit/WorkoutKit type when applicable. |
| `operation` | string | Query/selector/series/attachment operation. |
| `metric_ids` | string array | Selected metrics associated with the branch. |
| `metric_attribution` | optional object | Direct and dependency metric IDs. |
| `interval.start_date` | timestamp | Requested lower bound. |
| `interval.end_date` | timestamp | Requested upper bound. |
| `status` | enum string | Query outcome. |
| `record_count` | integer | Direct records reported for this branch. Dependency enrichment does not inflate it. |
| `error` | optional object | Safe structured domain/code/description/recoverability. |
| `status_description` | optional string | Additional non-sensitive context. |

## Query statuses

| Status | Interpretation |
|---|---|
| `success` | Query completed. `record_count: 0` is a successful empty result. |
| `failure` | Query failed; inspect the structured error. |
| `unsupported` | API/type/capability is unavailable on this runtime. |
| `skipped` | Health.md intentionally did not query, commonly because separate access was not granted. |
| `cancelled` | User or request cancelled the branch. |

Unsupported and skipped branches make a requested capture partial. They must not be treated as successful empty results.

## HealthKit privacy behavior

Apple protects read privacy. For many data types, denied read access can be indistinguishable from a successful query returning no samples. Health.md reports the public API outcome; it cannot prove authorization from an empty result.

## Error isolation

Health.md retains successful siblings wherever possible. Examples:

- one ECG waveform failure does not delete other ECG records;
- one workout route failure does not delete the workout;
- one attachment-byte failure does not delete attachment metadata;
- medication inventory failure does not delete captured dose events;
- one specialized workout association failure does not delete ordinary associations;
- one scheduled-plan failure marks capture partial instead of hiding other workout data.

## Integrity warnings

Each warning contains:

| Field | Meaning |
|---|---|
| `code` | Stable machine-readable warning code. |
| `message` | Safe human-readable explanation. |
| `metric_ids` | Affected metrics. |
| `record_uuids` | Affected UUID-backed records. |

Warnings can coexist with retained records. A warning-only archive can still have useful data, but automation should inspect warning codes before claiming an ideal capture.

## Daily partial failures

Exporter/fetch failures outside an individual canonical query appear at `diagnostics.partial_failures`. Each object contains:

- exact diagnostic date;
- `data_type`;
- `date_range_description`;
- `error_description`.

CSV writes each as a `Diagnostics,Partial Failure` canonical JSON row.

## CSV diagnostic rows

| Metric | Value |
|---|---|
| `Raw Capture Status` | Capture status string. |
| `Archive Manifest` | Archive envelope excluding record arrays; includes manifest, warnings, and inventory. |
| `Query Failure` | Canonical failed/cancelled query result. |
| `Integrity Warning` | Canonical warning. |
| `Partial Failure` | Canonical daily partial-failure object. |

## Acceptance algorithm

A strict downstream importer can use this sequence:

1. Validate top-level daily schema/version.
2. Read `raw_capture_status`.
3. If `complete` or `partial`, require and validate the canonical archive.
4. Confirm archive `capture_status` matches the evidence in query results.
5. Verify the requested date/owner interval.
6. Record every non-success query and warning.
7. Import retained records using UUID/external identity.
8. Mark the day complete only when every required branch is complete under the consumer's policy.

Complete-empty is valid. Missing archive under `not_requested` or `legacy_unavailable` is expected, not corruption.

## Complete examples

The generated lossless fixture includes successful-empty, failed, unsupported, skipped, and cancelled query branches, integrity warnings, external records, inventory, and partial failures:

- [`generated/core/lossless-day.json`](./generated/core/lossless-day.json)
- [`generated/core/canonical-archive.json`](./generated/core/canonical-archive.json)
- [`generated/core/lossless-day.csv`](./generated/core/lossless-day.csv)
