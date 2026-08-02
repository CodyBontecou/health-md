# Local Health.md MCP server and App

Health.md ships two compatible `healthmd-mcp` implementations:

- the signed Swift helper bundled with Health.md for Mac, documented below; and
- portable `healthmd mcp serve`, installed with `healthmd-cli`, which communicates directly with the foreground iPhone app on macOS, Linux, and Windows.

The portable mode does not require Health.md for Mac. `healthmd setup codex` safely configures Codex and opens iPhone pairing when needed. Pairing and MCP run through the same installed `healthmd` executable identity so native credential access does not depend on a second Keychain ACL. The compatibility `healthmd-mcp` executable execs its sibling `healthmd` on Unix. On Windows it serves in-process and supervises its own same-file helper against the same fixed Credential Manager service/account. Keep Direct CLI Access foreground on iPhone. Portable mode exposes the same nine analysis tools, readiness/catalog discovery, MCP App resource, PNG fallback, and four durable generated-file export tools. It omits Mac encrypted-context refresh jobs because every typed query is an explicit fresh iPhone request. Approved exports require an explicit existing desktop destination.

```text
Codex / Claude <-> healthmd mcp serve <-> authenticated encrypted port 17647 <-> foreground iPhone
```

The portable source and operator documentation live under `apps/cli`, and its public query contract is `packages/contracts/direct-protocol/v3/protocol.md`.

Portable Codex onboarding is:

```bash
healthmd setup codex
```

When pairing is needed, the command displays an ephemeral QR. Scanning it with the iPhone Camera opens the existing `healthmd` URL scheme, validates an exact local IPv4 endpoint/port/six-digit code, switches Health.md to Sync, and asks the user to approve **Pair with healthmd** without persisting the code. Manual entry remains the fallback. The generated MCP entry points to the absolute `healthmd` path with arguments `mcp serve`, pins an explicit iPhone when needed, preserves unrelated Codex configuration, applies bounded timeouts, and prompts for export/resume/cancel. Use `--skip-pairing` only when configuration and pairing must be separated.

## Bundled Mac topology

The bundled `healthmd-mcp` is a signed, sandboxed stdio Model Context Protocol helper. It adapts fixed MCP tools to the running Mac app's loopback APIs.

```text
Codex / Claude / another local MCP host
  <-> newline-delimited JSON-RPC over stdio
  <-> healthmd-mcp
  <-> http://127.0.0.1:17645
  <-> Health.md Mac app
  <-> connected iPhone for fresh reads and exports
```

The helper does not read HealthKit, export folders, security-scoped bookmarks, or arbitrary files. HealthKit reads remain on iPhone. The Mac app owns its selected destination bookmark and encrypted query context.

Supported core MCP protocol versions are `2024-11-05`, `2025-03-26`, `2025-06-18`, and `2025-11-25`.

## MCP App negotiation

Health.md implements the stable MCP Apps extension `io.modelcontextprotocol/ui` (2026-01-26).

A host must advertise this MIME type in `initialize`:

```json
{
  "capabilities": {
    "extensions": {
      "io.modelcontextprotocol/ui": {
        "mimeTypes": ["text/html;profile=mcp-app"]
      }
    }
  }
}
```

Only after that exact negotiation does the server advertise:

- the standard resources capability;
- `ui://healthmd/query-visualization-v1`;
- `resources/list` and `resources/read`;
- `_meta.ui.resourceUri` on visual tools;
- validated `structuredContent` for the view.

The bundled view is a self-contained HTML5 document. Its declared CSP allows no network, remote resources, nested frames, or external base URI. It uses the standard `ui/initialize`, tool input/result, host-context, size-change, and teardown lifecycle. It renders factual metric charts, comparisons, sleep, workouts, workout/sleep timing, coverage, evidence, limitations, traversal receipts, and export-job receipts.

If the host does not negotiate MCP Apps, every tool retains a normal text result. `healthmd_metric_chart` also returns a standard `image/png` content block, allowing image-capable Codex and Claude surfaces to show a native static chart. The complete typed JSON remains the first content block and source of truth.

## Configure Codex for the bundled Mac topology

The following alternative is only for the bundled Swift/Mac-app topology. Codex local clients and the desktop host share `~/.codex/config.toml`:

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

Restart Codex after changing configuration. Call `healthmd_doctor`, then request a small `healthmd_metric_chart`. Codex hosts that do not yet negotiate MCP Apps receive the PNG fallback and exact JSON.

## Configure Claude

Claude Desktop's local server entry is:

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

Use that entry in Claude Desktop's MCP configuration, or in a trusted Claude Code `.mcp.json`. Restart Claude Desktop after editing its configuration. Project-scoped Claude configurations require explicit workspace trust and server approval.

Claude Desktop versions that advertise `io.modelcontextprotocol/ui` render the interactive Health.md view inline. Claude Code and other text-oriented surfaces retain text and image fallbacks.

The helper can also be symlinked after the user opts in:

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp" \
  ~/.local/bin/healthmd-mcp
```

Do not run `healthmd-mcp` as an ordinary interactive command. It waits for JSON-RPC on stdin; the MCP host owns its process.

## Tools

### Readiness and discovery

- `healthmd_status`
- `healthmd_doctor`
- `healthmd_capabilities`
- `healthmd_metrics`

### Analysis and native visualization

- `healthmd_metric_chart`
- `healthmd_sleep_sessions`
- `healthmd_training_alignment`
- `healthmd_workouts`
- `healthmd_coverage`
- `healthmd_compare_periods`
- `healthmd_training_evidence`
- `healthmd_query`
- `healthmd_evidence_packet`

Visual tools preserve the exact query response as text. Negotiated MCP Apps additionally receive the same validated `healthmd.query_response` v1 or `healthmd.mcp_query_pages` v1 object as `structuredContent`.

Every analysis tool advertises complete nested JSON Schema for date, metric, source, page, period,
aggregation, and advanced request objects. Typed tools include concrete examples and should be called
directly: use `healthmd_sleep_sessions` for sleep rather than inspecting generic shell help or
substituting `healthmd extract`, which returns a different canonical source-data projection. The
portable executable can print the generated discovery shape without credentials or a listener, or
execute the same operation directly through the CLI adapter:

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema # complete fixed catalog
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

A minimal sleep call is
`{"dates":{"type":"exact","range":{"start_date":"2026-07-22","end_date":"2026-07-28"}},"all_pages":true}`;
resolve those inclusive example dates for the user's actual request. The typed tool supplies canonical
sleep metrics and lossless session detail automatically.

### Durable generated-file exports

- `healthmd_export_files`
- `healthmd_export_job_status`
- `healthmd_export_job_resume`
- `healthmd_export_job_cancel`

`healthmd_export_files` writes through the Mac app into the folder already selected in Health.md. It accepts an explicit date range or all available dates. Optional metric IDs, categories, or all-metrics selection narrows iPhone acquisition without changing saved iPhone settings; summary/lossless detail is valid only with one of those selections.

The export, resume, and cancel tools are marked as potentially destructive writes and with `anthropic/requiresUserInteraction`, because configured export modes can update or overwrite generated files. Hosts should show the full arguments and ask for approval. The server never infers approval or silently retries an unknown outcome.

Raw and canonical transport bodies can be gigabytes and contain routes, clinical text, attachments, or source records. MCP deliberately does not place those bodies in conversation context. Use `healthmd extract --output ...` or `healthmd export --raw --output ...` for validated streamed source data. MCP can still run selected generated-file exports and inspect their durable receipts.

### Encrypted-context acquisition jobs

- `healthmd_refresh`
- `healthmd_job_status`
- `healthmd_job_resume`
- `healthmd_job_cancel`

These jobs populate the disposable encrypted query context; they are independent from generated-file export jobs. Refresh, resume, and cancel also require explicit user interaction because they trigger iPhone reads or mutate durable job state.

## Example analysis

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
  "all_pages": true
}
```

Pass those arguments to `healthmd_metric_chart`. The interactive App creates unit-safe small multiples and renders missing values as gaps, never zero. The PNG fallback shows a bounded visual summary while the text block retains every returned page.

Typed analysis tools read encrypted Mac context and do not contact iPhone implicitly. Call `healthmd_refresh` first when fresh data is required.

## Example generated-file export

```json
{
  "date_selection": "explicit_range",
  "date_range": {
    "start": "2026-07-01",
    "end": "2026-07-07"
  },
  "settings_policy": "requested_dates_only",
  "categories": ["Sleep"],
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

After user approval, pass that to `healthmd_export_files`. Inspect the returned status, `job_id`, destination, files written, progress, and expiry. A waiter timeout does not cancel the durable job. Neither does an MCP `notifications/cancelled` message: it detaches only that transient waiter and returns the generated job ID for recovery. Use export job status before deciding whether to resume; only the explicit cancel tool terminates an accepted job.

## Paging and result semantics

Query and evidence tools accept `all_pages: true` where exposed. The helper follows opaque cursors with repeat detection and bounded aggregate byte/page ceilings, then returns `healthmd.mcp_query_pages` v1. If an automatic-traversal ceiling is reached, the successful partial wrapper sets `receipt.traversal_complete` to `false` and returns the exact `receipt.next_cursor` for lossless continuation. A caller can narrow scope or continue that cursor manually. Individual API pages remain bounded; the logical corpus has no date or item cap.

Transport success does not prove data completeness. Inspect coverage, requested-scope status, corpus status, missing intervals, limitations, evidence, `next_cursor`, and traversal receipts. The view displays these fields instead of hiding them.

## Safety boundaries

The helper has no prompts, roots, sampling, shell, SQL, arbitrary filesystem, arbitrary URL-fetch, HealthKit-write, or remote MCP capability. Its only resource is the predeclared bundled App HTML. Configuration accepts HTTP loopback hosts only: `127.0.0.1`, `::1`, or `localhost`, with no credentials, paths, queries, or fragments.

The loopback listener is the complete authorization boundary. Any local process that can reach it while Health.md is open can issue the same requests. Do not expose or proxy port `17645`.

Health.md outputs factual observations with units, provenance, coverage, and missingness. It does not diagnose, recommend treatment, infer causation, or label changes better or worse.
