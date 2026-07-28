---
title: "Local MCP server"
description: "Configure the sandboxed healthmd-mcp stdio helper, review its 16 typed tools, and understand loopback, paging, evidence, and privacy boundaries."
---

`healthmd-mcp` is a local stdio Model Context Protocol helper bundled with Health.md for Mac. It translates typed MCP tool calls into fixed loopback requests to the running Mac app.

```text
MCP client <-> newline-delimited JSON-RPC <-> healthmd-mcp
  -> http://127.0.0.1:17645
  -> Health.md Mac app and encrypted context
  -> connected iPhone when a tool needs fresh data
```

The helper does not read HealthKit, export folders, security-scoped bookmarks, or arbitrary files.

## Requirements

- Health.md for Mac installed and open.
- The bundled `healthmd-mcp` helper present.
- A current Health.md iPhone app connected for fresh acquisition.
- An MCP client that supports stdio servers and one of the supported protocol versions.

Supported protocol versions are `2024-11-05`, `2025-03-26`, `2025-06-18`, and `2025-11-25`.

## Install the helper path

Open Health.md on Mac and select **CLI**. The app shows the actual path and can copy an agent-assisted setup prompt.

The normal path is:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

You can point an MCP client at that file directly or create a symlink:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" \
  ~/.local/bin/healthmd-mcp
```

Do not run `healthmd-mcp` as an ordinary interactive command. It waits for newline-delimited JSON-RPC on stdin. Your MCP client should own the process.

## Generic client configuration

MCP clients use different config filenames, but the server entry is usually equivalent to:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

If you installed the symlink and your client inherits `PATH`:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "healthmd-mcp",
      "args": []
    }
  }
}
```

Restart the MCP client after changing its configuration. Then call `healthmd_doctor` before requesting data.

## Optional loopback URL

The helper defaults to:

```text
http://127.0.0.1:17645
```

`HEALTHMD_MCP_BASE_URL` can select another canonical loopback spelling or port:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": [],
      "env": {
        "HEALTHMD_MCP_BASE_URL": "http://localhost:17645"
      }
    }
  }
}
```

Configuration rejects HTTPS, credentials in the URL, paths, queries, fragments, and non-loopback hosts. Accepted hosts are `127.0.0.1`, `::1`, and `localhost` over HTTP.

## Available tools

The server advertises tools only.

### Readiness and discovery

| Tool | Purpose |
|---|---|
| `healthmd_status` | Check the running Mac app and connected iPhone export readiness |
| `healthmd_doctor` | Diagnose encrypted context and fresh-iPhone readiness with next actions |
| `healthmd_capabilities` | List query, evidence, refresh, schema, and pagination capabilities |
| `healthmd_metrics` | List canonical metric IDs, categories, units, and availability requirements |

### Typed health queries

| Tool | Purpose |
|---|---|
| `healthmd_sleep_sessions` | List stable sleep sessions with an optional fixed window and physiology coverage |
| `healthmd_training_alignment` | Align workouts with nearest preceding and following sleep using factual timing |
| `healthmd_workouts` | List workouts through the typed workout operation |
| `healthmd_coverage` | Inspect metric and date coverage with explicit missingness |
| `healthmd_compare_periods` | Compare two exact periods with supplied aggregation rules |
| `healthmd_training_evidence` | Create a factual training evidence packet with selected workout details |

### Low-level contracts and jobs

| Tool | Purpose |
|---|---|
| `healthmd_query` | Send an exact `healthmd.query_request` and optionally traverse all pages |
| `healthmd_evidence_packet` | Send an exact evidence request and optionally traverse all pages |
| `healthmd_refresh` | Acquire an explicit metric, source, date, and detail scope from iPhone |
| `healthmd_job_status` | Inspect a durable local acquisition job |
| `healthmd_job_resume` | Resume that exact acquisition job |
| `healthmd_job_cancel` | Request explicit cancellation |

Use the separate `healthmd extract` CLI for original `healthmd.health_data` documents and canonical source records. MCP tools return typed derived views and evidence, not source-document replacements.

## Example tool flow

A safe client sequence is:

1. Call `healthmd_doctor`.
2. Call `healthmd_metrics` and resolve canonical metric IDs.
3. Choose exact dates, metrics, sources, and detail.
4. If fresh data is required, call `healthmd_refresh` and wait for or resume that acquisition.
5. Call a typed query tool against the encrypted context.
6. Inspect requested-scope status, corpus status, missingness, evidence, and traversal receipt.
7. Report only the fields the user requested.

Example arguments for `healthmd_sleep_sessions`:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "window": {
    "start_offset_seconds": 0,
    "duration_seconds": 14400
  },
  "include_naps": false,
  "all_pages": true
}
```

The tool supplies the complete canonical sleep-stage metric selection and lossless detail to the query operation. It reads encrypted Mac context and does not refresh iPhone data implicitly. Use an explicit refresh first when current stage intervals are required. The high-level `healthmd sleep sessions` CLI command combines fresh acquisition and query in one workflow.

Example arguments for `healthmd_compare_periods`:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps", "resting_heart_rate"]
  },
  "first": {
    "start_date": "2026-07-01",
    "end_date": "2026-07-07"
  },
  "second": {
    "start_date": "2026-07-08",
    "end_date": "2026-07-14"
  },
  "aggregations": [
    {"metric_id": "steps", "aggregation": "sum"},
    {"metric_id": "resting_heart_rate", "aggregation": "average"}
  ],
  "all_pages": true
}
```

The operation reports increased, decreased, unchanged, or not comparable. It does not label direction as better or worse.

## Fresh acquisition and cached queries

Typed MCP query and evidence tools read the encrypted Mac context. They do not contact iPhone implicitly. Call `healthmd_refresh` first when the answer needs current data, then run the typed tool after acquisition completes.

A refresh body includes:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-14"
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

The iPhone must be open and connected. Health.md persists the immutable scope with the durable job, acquires only that scope, and commits encrypted owner days before acknowledgement.

## Page traversal

`healthmd_query`, `healthmd_evidence_packet`, and the typed query tools accept `all_pages: true` where their schemas expose it.

The helper then:

- follows opaque `next_cursor` values;
- rejects cursor repetition;
- keeps original versioned pages;
- applies a maximum aggregate byte ceiling;
- applies a maximum page count;
- returns a `healthmd.mcp_query_pages` v1 receipt.

Each individual API page remains bounded. If automatic traversal reaches its ceiling, narrow the request or continue manually with the last cursor. No matching tail is silently dropped.

## Result and error behavior

Tool results preserve the Mac API JSON as MCP text content. The helper marks non-2xx HTTP responses and local transport failures with `isError: true`.

A valid tool call can still return incomplete health-data status. MCP transport success does not imply complete requested scope. Instruct the client to inspect:

- `requested_scope_status`;
- `corpus_status`;
- `unrelated_skips`;
- missing intervals;
- limitations;
- `next_cursor` or all-pages receipt;
- source schema, version, and evidence.

Unknown top-level properties are rejected by typed tool schemas. This prevents a client typo from widening, narrowing, or changing a request silently.

## Deliberate capability limits

`healthmd-mcp` has no:

- MCP resources;
- prompts;
- roots;
- sampling;
- shell execution;
- SQL execution;
- arbitrary filesystem access;
- arbitrary URL fetch;
- HealthKit write capability;
- direct iPhone backend;
- streamable HTTP MCP endpoint.

The helper is App-Sandboxed with network-client authority for loopback access. Its request size is capped at 2 MiB. Normal responses are capped at 2 MiB per loopback call, with bounded multi-page traversal for supported tools.

## Privacy and medical neutrality

Any local process that can call the Mac app's loopback listener while it is open can request data. There are no MCP credentials or profile grants. Do not expose port `17645` or wrap this stdio server in a remote service.

Tool descriptions and server instructions require factual output with units, provenance, coverage, and missingness. They do not authorize diagnosis or treatment advice. A client should not infer cause from training alignment or treat missing data as zero.

## Troubleshooting

| Symptom | Action |
|---|---|
| Client cannot start the server | Use the absolute helper path and verify the file exists |
| Server waits with no terminal output | Expected when launched manually; an MCP client must send JSON-RPC on stdin |
| `healthmd_unavailable` | Open Health.md for Mac and confirm loopback readiness |
| Doctor says iPhone is unavailable | Unlock and open Health.md on iPhone, then wait for Mac connectivity |
| Config rejects base URL | Use plain HTTP with `127.0.0.1`, `::1`, or `localhost` and no credentials or path |
| Tool returns `isError: true` | Parse the JSON error and follow its next action |
| Result has `next_cursor` | Set `all_pages: true` or continue the cursor manually |
| Fresh job pauses | Reopen the same iPhone and call job status or resume |

## Related

<div class="related">
  <a href="/docs/agents/"><span>Architecture</span>Local agents and health context: setup, encrypted storage, scope, retention, and evidence.</a>
  <a href="/docs/agent-queries/"><span>Semantics</span>Typed query cookbook: sleep, alignment, workouts, coverage, comparison, paging, and completion.</a>
  <a href="/docs/agent-api/"><span>Routes</span>Loopback query API: exact HTTP requests and durable acquisition jobs.</a>
  <a href="/docs/reference/evidence-packets/"><span>Contracts</span>Compact queries and evidence packets: typed values, missingness, cursors, and packet IDs.</a>
</div>
