# Local query API

## Boundary

Health.md's query routes live under `/v1/agent/` on the existing IPv4/IPv6 loopback listener. The listener accepts only `127.0.0.1`, `::1`, and validated loopback peers. It also enforces bounded headers and JSON bodies, receive deadlines, and finite request timeouts.

There are no registrations, bearer credentials, grants, or stored access profiles. Loopback is the complete authorization boundary: any process on this Mac can call these routes while Health.md is open. Do not expose or proxy port `17645` to another machine.

## Routes

| Route | Purpose |
|---|---|
| `GET /v1/agent/capabilities` | Versioned schemas, direct-scope support, and per-page safety bounds. |
| `GET /v1/agent/metrics` | Canonical queryable metric catalog without HealthKit authorization claims. |
| `GET /v1/agent/readiness` | Encrypted-store and fresh-iPhone readiness with structured next actions. |
| `POST /v1/agent/query` | Run a directly scoped cached query. |
| `POST /v1/agent/evidence` | Build a directly scoped factual evidence packet. |
| `POST /v1/agent/refresh` | Acquire the supplied metric/source/date/detail scope from the connected iPhone. |
| `/v1/agent/jobs/{id}` | Local status, resume, and cancel for durable acquisition jobs. |

The former profiles and activity routes return `410 removed_endpoint` for compatibility.

## Direct request scope

Every query carries its own `healthmd.query_request` v1 containing metrics, sources, dates, operation, and page controls. The wrapper adds only `detail_level: summary | lossless`. Unknown wrapper fields—including former access-control fields—are rejected instead of ignored.

Every refresh carries:

```json
{
  "dates": {"type": "exact", "range": {"start_date": "2026-07-21", "end_date": "2026-07-22"}},
  "metrics": {"type": "explicit", "metric_ids": ["sleep_total"]},
  "sources": {"type": "explicit", "source_ids": ["apple_health"], "provider_ids": []},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Health.md validates that scope against the current metric/provider catalogs, turns it into an immutable `CanonicalHealthDataSelection`, and persists it with the durable job. A context acquisition without an explicit selection is rejected rather than falling back to saved iPhone metric settings.

`healthmd.health_data` remains the only public source-data contract. Use `healthmd extract` for canonical source objects. Typed query and evidence routes are bounded derived views over the disposable encrypted Mac index.

Fresh acquisition remains an iPhone operation. HealthKit reads happen on the open connected iPhone, request-scoped settings are cloned without changing saved preferences, and corpus partitions are committed to the encrypted Mac context store before acknowledgement. Provider-only requests do not require an Apple Health read. Query pages and transfer partitions bound memory and wire usage without imposing a total history/result cap.

Raw export `profile` values such as `canonical_source_records_v1` are transport modes and are unrelated to the removed access-profile feature.
