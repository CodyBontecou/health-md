---
title: "Health.md MCP server and App"
description: "Use Codex or Claude to run scoped Apple Health analysis, render native charts, and start durable Health.md exports through a local sandboxed MCP App."
---

Health.md for Mac ships a signed `healthmd-mcp` stdio helper. It lets Codex, Claude, and other MCP hosts query factual Apple Health data, render visualizations, refresh encrypted local context, and run approved durable exports through the open Mac app.

```text
Codex / Claude / another local MCP host
  <-> MCP JSON-RPC over stdio
  <-> signed healthmd-mcp helper
  <-> Health.md Mac loopback API on 127.0.0.1:17645
  <-> connected iPhone for fresh HealthKit reads and exports
```

<div class="availability available">
<strong>Available now · Health.md for Mac</strong>
<p>The bundled server exposes 21 fixed tools. It does not read HealthKit, export folders, security-scoped bookmarks, or arbitrary files itself.</p>
</div>

<div class="availability preview">
<strong>Preview · portable direct MCP</strong>
<p>The separate 19-tool <code>healthmd mcp serve</code> topology for macOS, Linux, and Windows is implemented but not publicly packaged yet. Its cloud-free <code>serve-read-only</code> entry exposes only the 13 readiness/query tools after local pairing. Portable-only commands on this page are marked as preview.</p>
</div>

## Requirements

- Health.md for Mac installed and open.
- Health.md open on the paired iPhone when a tool starts a fresh read or export.
- A local MCP host with stdio support.
- The signed helper path shown under **Health.md for Mac → CLI**.

The normal helper path is `/Applications/Health.md.app/Contents/Helpers/healthmd-mcp`. Supported core MCP protocol versions are `2024-11-05`, `2025-03-26`, `2025-06-18`, and `2025-11-25`. Do not launch `healthmd-mcp` as an ordinary interactive command; the MCP host owns stdin and the process lifecycle.

## Codex setup

Add the bundled helper to `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Restart Codex, call `healthmd_doctor`, list metrics with `healthmd_metrics`, then request a small `healthmd_metric_chart`. Hosts without interactive MCP Apps still receive exact JSON plus a standard PNG chart.

## Claude setup

Use this local stdio entry in Claude Desktop's MCP configuration or a trusted Claude Code `.mcp.json`:

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

Restart Claude Desktop after editing its configuration. Claude project configurations require workspace trust and explicit server approval.

Claude Desktop versions that advertise the stable MCP Apps extension render Health.md's interactive view inline. Claude Code and other text-first clients preserve the JSON and image fallbacks.

## Portable direct MCP preview

After the standalone release, `healthmd setup codex` will pair a foreground iPhone and safely create a same-binary `healthmd mcp serve` entry. That topology uses authenticated encrypted Manual IP or Tailscale transport on port `17647`, native credential storage, and explicit per-request iPhone reads. Linux additionally requires an unlocked Secret Service provider; Windows uses Credential Manager.

Until a `healthmd-cli/v<version>` release exists, do not rely on unpublished package or installer URLs. See [Direct iPhone CLI](/docs/cli-direct/) for the staged pairing and transport contract.

## Native MCP App visualizations

Health.md implements stable `io.modelcontextprotocol/ui` negotiation with `text/html;profile=mcp-app`.

After a host advertises that MIME type, the server exposes:

- `ui://healthmd/query-visualization-v1`;
- standard `resources/list` and `resources/read` methods;
- `_meta.ui.resourceUri` on analysis and export-receipt tools;
- validated `structuredContent` alongside exact JSON text.

The view is a self-contained HTML5 resource with no network, remote scripts, remote fonts, storage, or nested frames. Its declared CSP contains empty connect/resource/frame/base domain lists. It follows the standard initialize, tool-result, theme, resize, cancellation, and teardown lifecycle.

It can render:

- metric line charts with units and explicit missing-data gaps;
- period comparisons with caller-selected aggregation;
- sleep sessions and stage-duration summaries;
- workouts and factual workout/sleep timing;
- coverage, missing intervals, evidence, and limitations;
- all-pages traversal receipts;
- durable export progress, destinations, and job receipts.

If the host does not support MCP Apps, the tools still work. `healthmd_metric_chart` adds `image/png` content for image-capable hosts while preserving complete JSON as text.

## Available tools

The bundled Mac server exposes 21 fixed tools. The portable preview exposes the same readiness, analysis, and generated-file export tools but omits the four encrypted-context acquisition tools.

### Readiness and discovery

| Tool | Purpose |
|---|---|
| `healthmd_status` | Check Mac app, context, iPhone, and export readiness |
| `healthmd_doctor` | Diagnose the bundled helper and Mac loopback topology |
| `healthmd_capabilities` | List direct query, evidence, export, schema, and paging capabilities |
| `healthmd_metrics` | List canonical metric IDs, categories, units, and requirements |

### Analysis and visualization

| Tool | Purpose |
|---|---|
| `healthmd_metric_chart` | Query metric series and render native charts with coverage and units |
| `healthmd_sleep_sessions` | List and visualize stable sleep sessions and physiology coverage |
| `healthmd_training_alignment` | Show factual workout timing against preceding/following sleep |
| `healthmd_workouts` | List and visualize workouts |
| `healthmd_coverage` | Inspect metric/date coverage and missingness |
| `healthmd_compare_periods` | Compare exact periods with explicit aggregation semantics |
| `healthmd_training_evidence` | Create a factual training evidence packet |
| `healthmd_query` | Send an exact `healthmd.query_request` and optionally traverse pages |
| `healthmd_evidence_packet` | Send an exact evidence request and optionally traverse pages |

### Generated-file exports

| Tool | Purpose |
|---|---|
| `healthmd_export_files` | Run a durable export through the Mac app into its selected folder |
| `healthmd_export_job_status` | Inspect export progress and destination receipt |
| `healthmd_export_job_resume` | Resume the exact immutable durable export job |
| `healthmd_export_job_cancel` | Explicitly cancel the export job |

The export, resume, and cancel tools are marked as potentially destructive writes and require explicit interaction on current Claude hosts, because configured export modes can update or overwrite generated files. Codex configuration above prompts on those tools as an additional safeguard.

### Encrypted-context acquisition jobs · bundled Mac only

| Tool | Purpose |
|---|---|
| `healthmd_refresh` | Acquire an approved scope from iPhone into disposable encrypted Mac context |
| `healthmd_job_status` | Inspect refresh progress without reading health values |
| `healthmd_job_resume` | Resume the exact accepted refresh job |
| `healthmd_job_cancel` | Explicitly cancel an accepted refresh job |

### Discover the complete query shape

MCP `tools/list` includes complete nested JSON Schema for dates, metrics, sources, paging, period
ranges, aggregations, and the advanced `healthmd.query_request`. Typed tools also include concrete
examples. An agent should call the matching typed tool directly rather than inspect generic shell
help. In particular, sleep questions use `healthmd_sleep_sessions`; `healthmd extract` produces a
different canonical source-data projection.

You can inspect the same schema locally without opening a network listener or contacting iPhone:

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
```

A minimal sleep call has this shape (resolve the inclusive dates for the actual request):

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-22",
      "end_date": "2026-07-28"
    }
  },
  "all_pages": true
}
```

Canonical sleep metrics and lossless session detail are supplied automatically by
`healthmd_sleep_sessions`.

## Analyze and chart data

Call `healthmd_doctor` first. Resolve metric IDs with `healthmd_metrics`, then chart a directly scoped series. Each query explicitly requests a fresh bounded iPhone read:

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
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

Pass that object to `healthmd_metric_chart`. The interactive view uses unit-safe small multiples. A missing or partial point breaks the line rather than becoming zero.

Typed query tools contact only the paired foreground iPhone. The iPhone captures the requested days, projects compact typed context, evaluates the request locally, and returns a bounded response page with coverage, missingness, evidence, and limitations.

## Run a generated-file export

Create an existing destination directory on the computer first. After the host shows the full arguments and the user approves, call `healthmd_export_files`:

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "destination": "/absolute/path/to/HealthVault",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Use `date_selection: "all_available"` without `date_range` for complete history. Optional `metric_ids`, `categories`, or `all_metrics` narrow iPhone acquisition without changing saved settings. `detail_level` applies only when one of those selections is present. `all_metrics` cannot be combined with explicit metric/category lists.

Inspect:

- `status` and durable `state`;
- `job_id`;
- processed/total days and progress;
- files or Daily Notes written;
- validated desktop destination;
- committed partitions and bytes;
- pause/failure reason and expiry.

A timeout or closed MCP waiter does not cancel the durable job. Check `healthmd_export_job_status` before resuming after an unknown outcome. Only explicit cancel terminates the job.

Raw and canonical source transport can contain gigabytes of routes, clinical text, attachments, and source records. Health.md deliberately does not put those bodies into an MCP conversation. Use the validated streaming CLI for source-shaped output:

```bash
healthmd extract --metric workouts --last 30 --detail lossless --output workouts.json
healthmd export --iphone --all --raw --output health-corpus.json
```

MCP analysis remains a derived factual view; generated-file exports continue to use the public `healthmd.health_data` contract through the production exporters.

## Paging and completeness

Query/evidence tools expose `all_pages: true` where supported. The helper follows opaque cursors with cycle detection and aggregate byte/page ceilings, preserving each versioned response under `healthmd.mcp_query_pages` v1. If an automatic-traversal ceiling is reached, the successful partial wrapper sets `receipt.traversal_complete` to `false` and returns the exact `receipt.next_cursor` for lossless continuation. iPhone retains a paged compact snapshot for ten minutes of foreground inactivity and clears it on terminal traversal or backgrounding. One request has a 366,000-day and 64 MiB encoded compact-context guard; `query_scope_too_large` means partition dates or metric IDs across calls, not that the logical history is unavailable. Pages bound missing-interval and source-descriptor lists with explicit count/truncation fields and limitations.

Transport success is not completeness. Always inspect:

- requested-scope and corpus status;
- coverage and missing intervals;
- limitations and evidence;
- `next_cursor` or traversal receipt;
- unrelated skips;
- source schema and version.

The MCP App displays these fields instead of hiding them. If automatic traversal reaches its safety ceiling, narrow the scope or continue manually.

## Security and privacy boundaries

The helper has no prompts, roots, sampling, shell, SQL, arbitrary file reads, arbitrary URL fetches, HealthKit writes, loopback HTTP service, or remote MCP endpoint. Its only MCP resource is the bundled App document. Generated-file writes are one fixed approval-gated operation and require an explicit existing destination that is validated and durably bound before transfer.

Direct trust is stored in Keychain, Secret Service, or Windows Credential Manager. Pairing uses the existing authenticated encrypted protocol; the iPhone must be foreground and explicitly connected to the computer's LAN or Tailscale address. Query pages are bounded to the negotiated byte/item limits, and automatic all-pages aggregation has additional byte/page ceilings. Unbounded raw bodies stay on the validated streaming CLI path.

Health.md reports factual observations with units, provenance, coverage, and missingness. It does not diagnose, recommend treatment, infer causation, or call a direction better or worse.

## Troubleshooting

| Symptom | Action |
|---|---|
| Host cannot start the helper | Use the absolute installed `healthmd` or `.exe` path with arguments `mcp serve` |
| Helper waits when run in Terminal | Expected; an MCP host must send JSON-RPC on stdin |
| `healthmd_not_paired` | Run `healthmd direct pair` and finish pairing on iPhone |
| `healthmd_unavailable` | Unlock and foreground Health.md on iPhone, enable Direct CLI Access, and connect to the computer |
| `query_scope_too_large` | Partition dates or metric IDs across calls; the logical corpus remains available across requests |
| No interactive chart | Update the host; the server still returns exact JSON and a PNG metric-chart fallback |
| Export destination unavailable | Create and pass an existing absolute non-symlink desktop directory |
| Export waiter times out | Inspect the durable export job by ID before resuming |
| Result has `next_cursor` | Set `all_pages: true` or continue the cursor manually |

## Related

<div class="related">
  <a href="/docs/agents/"><span>Architecture</span>Local agents, encrypted context, request scope, and evidence.</a>
  <a href="/docs/agent-queries/"><span>Analysis</span>Typed query cookbook for metrics, sleep, workouts, comparison, and coverage.</a>
  <a href="/docs/cli-extract/"><span>Source data</span>Validated canonical extraction for large source-shaped results.</a>
  <a href="/docs/reference/evidence-packets/"><span>Contracts</span>Typed values, missingness, evidence, and packet identities.</a>
</div>
