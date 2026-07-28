---
title: "Loopback query API"
description: "Call Health.md's versioned local query, evidence, refresh, readiness, metric, and durable job routes through HTTP or the low-level healthmd agent command."
---

Health.md for Mac exposes a versioned local API under `/v1/agent/`. It serves encrypted-context queries, evidence packets, request-scoped iPhone acquisition, readiness, and durable acquisition jobs.

The API binds to loopback on port `17645`. It accepts only validated IPv4 or IPv6 loopback peers.

<div class="callout">
<strong>Do not expose this port.</strong>
<p style="margin-top:6px;">There is no bearer token, caller registration, access profile, or grant database. Loopback reachability is the complete authorization boundary. Any local process can issue requests while Health.md is open.</p>
</div>

## Routes

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | List versioned schemas, scope support, and page bounds |
| `GET` | `/v1/agent/metrics` | Return canonical queryable metric IDs, categories, units, and requirements |
| `GET` | `/v1/agent/readiness` | Return encrypted-context and fresh-iPhone readiness with next actions |
| `POST` | `/v1/agent/query` | Run one bounded typed query page |
| `POST` | `/v1/agent/evidence` | Derive one bounded factual evidence-packet page |
| `POST` | `/v1/agent/refresh` | Acquire an explicit scope from iPhone into encrypted Mac context |
| `GET` | `/v1/agent/jobs/{id}` | Inspect a durable local acquisition job |
| `POST` | `/v1/agent/jobs/{id}/resume` | Resume the immutable acquisition request |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Request explicit cancellation |

Former `/v1/agent/profiles` and `/v1/agent/activity/query` routes return `410 removed_endpoint`.

The direct iPhone backend does not host these routes. It supports canonical extraction and export, but query, evidence, refresh, metrics, doctor, and MCP need the Mac app's encrypted context.

## Prefer the CLI adapter

The low-level CLI keeps request bodies exact and handles loopback transport errors:

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Use `--json JSON` instead of `--input` for a small body. The CLI does not silently widen or narrow the JSON supplied to these commands.

Use high-level commands such as `healthmd query`, `healthmd sleep sessions`, or `healthmd compare` for ordinary workflows. They validate selectors and construct the typed operation for you.

## Query body

`POST /v1/agent/query` accepts only `request` and optional `detail_level` at the top level:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Unknown wrapper fields are rejected. The query request contract defines metrics, sources, dates, operation, and page controls. `detail_level` is `summary` or `lossless`.

The response is `healthmd.query_response` v1. It contains typed items, coverage, evidence, source descriptors, limitations, and optional `next_cursor`.

Inspect a complete synthetic response at [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Continue a cursor

To request the next page, send the same semantic request and place the returned cursor in `page.cursor`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Follow `next_cursor` until it is absent. Cursors are authenticated and bound to the request and encrypted corpus revision. Health.md rejects modified, mismatched, and stale cursors.

Page bounds protect each request without imposing a total history or result cap.

## Evidence body

`POST /v1/agent/evidence` uses the same wrapper. The operation is `derive_packet` with a packet kind and explicitly selected details.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

The response remains a paged query response and contains a `healthmd.evidence_packet` v1 fragment. Facts include typed values and evidence. The packet includes the factual-observations-only limitation.

See [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json) for a complete synthetic response.

## Refresh body

Refresh acquires only an explicit scope. The body accepts dates, metrics, sources, detail level, and a finite wait timeout:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

The Mac validates the scope against current catalogs and turns it into an immutable canonical selection. The iPhone reads only the selected ordinary HealthKit types. Request-scoped settings do not change saved iPhone export preferences.

Refresh uses a dedicated `encrypted_context` transfer mode:

- it writes no export files;
- it does not consume file-export quota;
- it transfers bounded resumable partitions;
- the Mac commits each deterministic compact owner day before acknowledgement;
- the exact request persists with the durable job.

Provider-only scope does not require an Apple Health read. Provider-native history remains provider-native evidence and is not converted into synthetic Apple Health metrics.

## All available selection

Metric and date selectors can use `all_available`:

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

The iPhone resolves the earliest available selected Apple Health record and every source-calendar day through today. Provider acquisition follows provider-native history cursors. The resolved identifiers are pinned before transfer so resume cannot shift the request.

There is no fixed date or result cap. Partitions, pages, one-day decryption, disk space, and finite waits provide resource bounds.

## Durable acquisition jobs

A refresh waiter can time out while the job continues. The response includes a job ID and safe progress.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

The job expires seven days after creation. Resume reuses the same request, Mac, iPhone, source scope, and committed frontier.

Cancel is terminal only after iPhone acknowledgement. An unavailable iPhone can leave the job in cancellation-pending state.

## Direct HTTP calls

The CLI is preferred, but local software can call HTTP directly:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

The listener enforces bounded headers and JSON bodies, explicit method and content type, receive deadlines, and finite request behavior.

Keep direct HTTP clients on the same Mac. Do not add a LAN bind, proxy, tunnel, or remote HTTP MCP wrapper.

## Typed values and missingness

Query results preserve type and unit. Values can be quantities, durations, counts, strings, categories, Booleans, timestamps, calendar dates, nested arrays, or unknown future typed values.

Missing statuses include complete-empty, partial, failed, unsupported, skipped, cancelled, not requested, legacy unavailable, redacted, and not synchronized. Consumers must not coerce them into zero.

Coverage includes requested and available ranges, days considered, days with values, and compressed status-bearing missing intervals.

## Error handling

Errors use `healthmd.query_error` v1 with a stable code, message, retryability, and typed details. Distinct errors cover:

- invalid page controls;
- malformed or tampered cursors;
- cursor and query mismatch;
- stale corpus revision;
- invalid date range;
- metric or source validation;
- unit or aggregation mismatch;
- unsupported operation;
- evidence scope violation;
- iPhone or encrypted-store readiness;
- durable job state.

Do not retry a refresh blindly after an unknown outcome. Inspect its job state first.

## Related

<div class="related">
  <a href="/docs/agents/"><span>Overview</span>Local agents and health context: setup, encrypted storage, scope, and reporting rules.</a>
  <a href="/docs/agent-queries/"><span>High level</span>Typed query cookbook: validated commands for common metric, sleep, workout, and evidence questions.</a>
  <a href="/docs/mcp/"><span>Tools</span>Local MCP server: stdio configuration, typed tools, paging, and sandbox limits.</a>
  <a href="/docs/reference/api-and-cli/"><span>Reference</span>API and CLI contract: export, extraction, query, direct backend, and operational limits.</a>
  <a href="/docs/reference/evidence-packets/"><span>Data contracts</span>Compact queries and evidence packets: types, cursors, operations, and deterministic packet IDs.</a>
</div>
