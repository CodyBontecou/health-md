# Direct iPhone query protocol v3

This document specifies the capability-gated Health.md direct-query extension used by a portable
MCP/CLI process to execute bounded factual queries on a foreground iPhone without the Health.md
macOS app. It is an additive application-layer extension to the deployed iOS direct protocol v1.

## Compatibility and transport

Protocol v3 does **not** change pairing or transport bytes:

- the iPhone still uses pairing protocol selector `1`, a six-digit code, and the v1 pairing and
  trusted-reconnect transcripts;
- TCP remains on port `17647` with `u64be(length) || JSON` outer packets;
- the encrypted channel remains `HMDSC001` with independent monotonic direction sequences;
- the maximum outer packet remains 2 MiB;
- existing export, transfer, resume, and cancellation messages remain application v1 and retain
  their exact JSON, fingerprints, and fixtures.

A v3-capable iPhone advertises application versions `[1,3]` and a non-null `query` object in its
existing Swift-shaped `hello`. A portable client may advertise `[1,2,3]`; Android v2 remains
unchanged. Query messages are sent only when both peers advertise version `3` and compatible query
capabilities. Missing query capabilities mean query is unsupported. Old peers therefore never
receive an unknown associated-value enum case.

Application v3 is a query capability, not permission to reinterpret a v1 export request. Export
requests continue to carry `protocolVersion: 1`.

## Query capabilities

The optional `query` member of `DirectPeerCapabilities` is:

```json
{
  "schemaVersions": [1],
  "operations": [
    "coverage",
    "derive_packet",
    "metric_series",
    "period_comparison",
    "sleep_session_listing",
    "source_record_listing",
    "workout_listing",
    "workout_sleep_alignment"
  ],
  "detailLevels": ["lossless", "summary"],
  "maximumPageItems": 1000,
  "maximumPageBytes": 1048576,
  "supportsEvidenceValues": true
}
```

Lists are unique and sorted when produced by Health.md. A client intersects schema versions,
operations, and detail levels and clamps page controls to both peers' advertised maxima. A query
response must remain below both the negotiated page-byte bound and the 2 MiB direct control-packet
ceiling.

## Encoding

Query messages preserve Swift synthesized associated-value encoding, including the `_0` box:

```json
{
  "queryRequest": {
    "_0": {
      "protocolVersion": 3,
      "requestID": "00000000-0000-4000-8000-000000000003",
      "createdAt": "2023-11-14T22:13:20Z",
      "detailLevel": "summary",
      "query": {
        "schema": "healthmd.query_request",
        "schema_version": 1
      }
    }
  }
}
```

Foundation compatibility remains the same as v1: UUIDs are uppercase and hyphenated, dates use
whole-second ISO-8601 UTC, nil optionals are absent, and canonical encoders sort keys without
escaping `/`. Query JSON uses the language-neutral `healthmd.query_request/1` and
`healthmd.query_response/1` contracts. Non-finite numbers are forbidden.

## Messages

### `queryRequest`

Fields:

- `protocolVersion`: exactly `3`;
- `requestID`: caller-generated UUID unique among in-flight requests;
- `createdAt`: whole-second UTC timestamp, no more than five minutes in the future;
- `detailLevel`: `summary` or `lossless`;
- `query`: complete `healthmd.query_request/1` object.

The query request carries exact metric, source, date, operation, and page scope. The iPhone must
reject unknown query fields through the query-contract decoder. `source_record_listing` and source
evidence values require `lossless`; summary requests cannot disclose them.

### `queryResponse`

```json
{
  "queryResponse": {
    "_0": {
      "requestID": "00000000-0000-4000-8000-000000000003",
      "response": {
        "schema": "healthmd.query_response",
        "schema_version": 1,
        "items": [],
        "packet": null,
        "coverage": null,
        "sources": [],
        "evidence": [],
        "next_cursor": null,
        "limitations": []
      }
    }
  }
}
```

The response ID must match the request. Every response preserves explicit units, availability,
coverage, evidence references, limitations, and cursor semantics. Missing values are never encoded
as zero. A bounded page carries at most 64 missing-interval entries and 64 source descriptors;
`missing_interval_count`, `missing_truncated`, and explicit `coverage_intervals_truncated` /
`source_descriptors_truncated` limitations disclose omitted page metadata without claiming complete
lists. Limitation lists are likewise bounded with an explicit `limitations_truncated` receipt. Health judgments, diagnosis, causation, or treatment recommendations are outside this
protocol.

### `queryRejected`

```json
{
  "queryRejected": {
    "_0": {
      "requestID": "00000000-0000-4000-8000-000000000003",
      "code": "query_unavailable",
      "message": "The iPhone could not complete the direct query.",
      "retryable": true
    }
  }
}
```

Codes and messages are stable and health-free. They must not contain metric values, dates, routes,
identities, source payloads, paths, credentials, or underlying parser/HealthKit errors.

## Execution and lifecycle

- Direct CLI Access is opt-in.
- The iPhone must be foreground and protected data must be available before accepting new work.
- HealthKit authorization is checked for the exact resolved metric scope.
- Query capture and evaluation occur on iPhone; only bounded typed response pages cross the wire.
- A query does not write export files and does not consume a generated-file destination.
- At most one direct query/export operation is active at a time.
- App backgrounding cancels the transient query, clears its in-memory paging snapshot, and
  disconnects the query channel; it does not mutate any durable export job. Only an already-active
  durable export may receive finite iOS background continuation. An ordinary authenticated
  transport closure ends only the in-flight request: while Health.md remains foreground, its
  dataset-bound snapshot may survive for the documented paging-inactivity window so the same
  trusted installation can reconnect and continue an opaque cursor.
- Cursors are authenticated by an iPhone-protected key and bound to the exact query and captured
  dataset fingerprint. A paged compact snapshot may remain in iPhone process memory for ten minutes
  of foreground paging inactivity; terminal traversal and app backgrounding clear it. A cursor used after that
  fails closed rather than silently recapturing a changed corpus.
- `all_available` is a logical unbounded scope. Page item/byte bounds protect response allocation
  and wire frames. One foreground request may span at most 366,000 calendar days and retain at most
  64 MiB of encoded compact context; `query_scope_too_large` tells the caller to partition dates or
  metrics and continue across requests.
  This resource guard does not impose a product-level history or aggregate-result cap.

## Security and privacy

The iPhone resolves requested IDs against the production metric registry before HealthKit work.
Unknown, empty, duplicate, unsupported, or unauthorized scopes fail closed. Evidence values are
returned only for explicit lossless scope. Query values, source records, owner dates, and evidence
must never appear in logs, diagnostics, telemetry, notifications, or public error strings.

The portable MCP process must not add shell, SQL, arbitrary URL, arbitrary file-read, prompts,
roots, or sampling capabilities. MCP Apps HTML is a presentation resource; query authority remains
this authenticated iPhone channel.
