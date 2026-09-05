# Typed queries and evidence packets

## Status

- **Docs status:** Drafted
- **Video priority:** medium
- **Primary surfaces:** Mac app loopback `/v1/agent/query` and `/v1/agent/evidence` routes; `healthmd-mcp` tools (`healthmd_query`, `healthmd_evidence_packet`, `healthmd_training_evidence`); portable `healthmd` CLI/MCP over iPhone direct query protocol v3
- **Source files:** `HealthMd/Shared/Query/*`, `EncryptedHealthContextQueryExecutor.swift`, `IPhoneDirectCLIService.swift`; reference: [Compact queries and evidence packets](../reference/evidence-packets.md)

## What it does

A typed query is a machine request that names exactly which metrics, dates, and operation you want — and gets back structured values with canonical units, explicit missingness, coverage, and **evidence references** that point to the exact source records behind every fact. Instead of an agent guessing from exported prose, the answer arrives as paged, typed JSON where every number can be traced back to a daily summary key, canonical HealthKit UUID, external identity, query-manifest result, integrity warning, or partial failure.

An **evidence packet** bundles stored facts for a factual scope — `daily_wellness`, `training`, or `doctor_visit` — with those evidence references, coverage, limitations, and a deterministic `packet_id`. Packets report stored values; they do not infer a condition, diagnose, recommend treatment, or call a change better or worse.

These query contracts are independent from daily exports: `healthmd.health_data` v8 files keep their exact meaning and bytes. Adding or advancing a query or packet contract never relabels a daily export.

## Who it is for

- Agents (Codex, Claude) connected through the local MCP server that need verifiable answers, not free-text guesses.
- CLI users and automation that want a bounded, typed read of specific metrics without running a full export.
- Not for producing files: use exports or canonical `extract` for documents destined for Obsidian or disk.

## Where to find it

1. **Mac app routes:** with Health.md for Mac open, `POST /v1/agent/query` and `POST /v1/agent/evidence` on the loopback listener (`127.0.0.1`/`::1`, port 17645). Loopback is the complete authorization boundary — see [Agent-local API](./agent-local-api.md).
2. **MCP tools:** through the bundled `healthmd-mcp` helper (or portable `healthmd mcp serve`), call `healthmd_query`, `healthmd_evidence_packet`, or `healthmd_training_evidence` — see [Local MCP server](./local-mcp.md).
3. **Portable CLI/MCP:** `healthmd mcp serve` on macOS, Linux, or Windows runs fresh typed queries directly against a paired, foreground iPhone over direct query protocol v3 — see [Direct iPhone CLI backend](./cli-direct-iphone.md).

There is no in-app iPhone screen for queries; the iPhone's role is serving the typed protocol while Direct CLI Access is enabled.

## Prerequisites

- **Mac surfaces:** Health.md for Mac open. Query routes read the encrypted Mac context; call the refresh route or `healthmd_refresh` with an explicit metric/source/date scope first when fresh data is required — typed analysis tools never contact the iPhone implicitly.
- **Portable mode:** a paired iPhone with Health.md open and foregrounded, Direct CLI Access enabled, protected data available, and HealthKit authorization for the exact resolved metric scope.
- No HealthKit access happens on the Mac; fresh reads always occur on the iPhone.

## Setup

1. Ask for exactly what you need — explicit metric IDs and an exact inclusive date range, or `all_available`:
2. Read the page, then follow `next_cursor` until it is absent. (MCP tools accept `all_pages: true` to follow cursors automatically within bounded traversal ceilings.)
3. For a packet, request one of the factual kinds and inspect facts, coverage, and evidence references.

## Example output

A query request (from the reference contract):

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

A bounded response page carries typed items plus the context that makes them trustworthy:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "items": [],
  "packet": null,
  "coverage": {
    "status": "complete_empty",
    "days_considered": 0,
    "days_with_values": 0,
    "missing": []
  },
  "sources": [],
  "evidence": [],
  "next_cursor": null,
  "limitations": []
}
```

## Tips

- Missing values are absent values with an explicit availability status — never a fabricated zero. A real zero is a typed quantity/count/duration.
- Access is unlimited; pages are bounded. There is no contract-level cap on selected metrics, date-range length, or total items — safety comes from `page.max_items`, `page.max_bytes`, and the opaque authenticated cursor. Changing page controls never changes query meaning.
- Cursors are authenticated and bound to both the semantic query and the corpus digest; altering one, or reusing it with a different query or mutated store, fails closed instead of returning wrong data.
- `period_comparison` requires you to supply a typed aggregation descriptor per metric. The evaluator does not guess aggregation semantics from a metric name, and direction is only `increased`, `decreased`, `unchanged`, or `not_comparable` — never better or worse.
- Inspect coverage, missing intervals, limitations, and (for MCP auto-traversal) `receipt.traversal_complete` before treating a result as complete. Transport success does not prove data completeness.
- A single indivisible item larger than `max_bytes` is returned alone with a `single_item_exceeds_page_bytes` limitation rather than becoming an inaccessible tail.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Stale or empty results on Mac | Encrypted context not refreshed | Run `healthmd_refresh` (or `POST /v1/agent/refresh`) with an explicit scope, then re-query |
| `single_item_exceeds_page_bytes` limitation | One indivisible item exceeds `max_bytes` | Raise `max_bytes` (up to the public v1 maximum) and re-request that page |
| `invalidCursor` / `cursorDoesNotMatchQuery` / `staleCursor` | Tampered cursor, different request, or a committed store mutation | Re-issue the query from the first page |
| `traversal_complete: false` in an MCP wrapper | Automatic cursor traversal hit its bounded ceiling | Continue from `receipt.next_cursor` manually or narrow the scope |
| `backend_unsupported` from the bundled Swift helper | Mac-context query/evidence subcommands were run with `--backend direct` | Use the default `mac-app` backend, or use portable `healthmd mcp serve` for direct queries |
| `query_scope_too_large` (direct protocol v3) | One foreground request exceeds the 366,000-day / 64 MiB compact-context guard | Partition dates or metrics across separate requests |
| `query_unavailable` (retryable) | The iPhone could not complete the direct query | Keep Health.md foregrounded with protected data available and retry |

## Video outline

- **Suggested title:** Ask Your Agent a Health Question — Get Evidence, Not Guesses
- **Hook:** "Every number comes with a receipt."
- **Demo flow:** 1. `healthmd_query` for steps + resting heart rate over a month. 2. Walk the paged response: typed units, coverage, missing intervals shown as gaps not zeros. 3. Build a `training` evidence packet and inspect its evidence references and `packet_id`.
- **Key screenshot/recording moments:** the JSON response with evidence references; an MCP Apps/PNG chart rendering missing values as gaps; the traversal receipt.
- **CTA / next video:** [Agent-local API](./agent-local-api.md) and [Local MCP server](./local-mcp.md) setup.

## Implementation notes

The shared query foundation is a portable Swift layer with no HealthKit, filesystem, network, CLI, or MCP dependency. Public contracts: `healthmd.query_request/response/error` v1, `healthmd.query_context_day` v1, and `healthmd.evidence_packet` v1 ([reference](../reference/evidence-packets.md)). `HealthMdQueryContextProjector` converts captured `HealthData` days into compact context days — a disposable indexing/derived-view protocol over canonical `healthmd.health_data`, not an independent health-data source. Mac execution runs through `EncryptedHealthContextQueryExecutor` over the AES-256-GCM per-day encrypted context store ([store](./encrypted-query-context-store.md), [executor](./bounded-encrypted-query-executor.md)) with bounded-memory paging. iPhone execution is capability-gated direct query protocol v3 ([protocol](../../../../packages/contracts/direct-protocol/v3/protocol.md)): evaluation happens on-device, only bounded typed pages cross the encrypted channel, and app backgrounding cancels the transient query. `packet_id` is the SHA-256 of the packet's semantic fields with volatile metadata excluded, so equivalent packets keep their identity across regeneration.
