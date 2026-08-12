---
title: Connect an agent in 10 minutes
description: Connect the released Health.md Mac MCP helper to Codex or Claude, acquire one explicit iPhone scope, run a bounded query, and verify completeness safely.
---

<div class="availability available">
<strong>Available now · Health.md for Mac</strong>
<p>This path uses the signed <code>healthmd-mcp</code> helper bundled with the released Mac app. It does not use the portable CLI preview, Direct CLI Access, a pairing QR code, or port 17647.</p>
</div>

You will connect a local MCP host, verify readiness without reading health values, explicitly refresh one small scope from iPhone, and query that encrypted Mac context. Allow about ten minutes when both apps are already installed and on the same local network.

## 1. Install and open Health.md

[Download Health.md from the App Store](https://apps.apple.com/us/app/health-md/id6757763969) on both the Mac and iPhone. Open both apps.

HealthKit stays on iPhone. The Mac app hosts the signed MCP helper and an encrypted, disposable query context; it does not read HealthKit directly.

## 2. Connect iPhone and Mac

1. On Mac, leave Health.md open.
2. On iPhone, open **Health.md → Sync** and enable Mac connectivity.
3. Keep both devices on the same reachable local network and keep Health.md foreground on iPhone while starting fresh work.
4. Confirm the Mac app shows the intended iPhone connection. If it does not, reopen both apps and review [Mac Sync readiness](/docs/sync/).

This is the released Mac connection. Do not run `healthmd direct pair`; that command belongs to the separate portable preview.

## 3. Copy the signed helper path

Open **Health.md for Mac → CLI** and copy the displayed MCP helper path. A normal `/Applications` install uses:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Use the displayed path if the app is installed elsewhere. Configure the helper directly—do not wrap it in a shell or launch it as an interactive command.

## 4. Configure Codex or Claude

### Codex

Add this to `~/.codex/config.toml`, substituting the helper path when needed:

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

Restart Codex after saving the file.

### Claude Desktop or Claude Code

Add this local stdio entry to Claude Desktop's MCP configuration or a trusted Claude Code `.mcp.json`:

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

Restart Claude Desktop, or trust the Claude Code workspace and approve the server. Keep approval prompts enabled for refresh, export, resume, and cancel operations.

## 5. Check readiness

Call `healthmd_doctor`. It reads health-free readiness only.

A ready result contains these fields:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

The complete result also includes checks and next actions. Resolve every blocking check before continuing. A connected helper does **not** prove that encrypted context is fresh.

Next, call `healthmd_metrics` and confirm the canonical metric ID and unit you intend to request. This walkthrough uses `steps` only as an example.

## 6. Explicitly refresh one small scope

Resolve the dates you actually want, then call `healthmd_refresh` with an exact inclusive range. The example requests one day of summary data:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Review the arguments, approve the acquisition, and keep both apps open. Refresh writes no export files and does not change saved iPhone export settings. Retain the returned `job_id` until the job reaches a terminal state.

## 7. Run the first bounded query

After refresh completes, call `healthmd_metric_chart` with the same dates, metric, source selection, and detail level:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` traverses opaque cursors only within the helper's aggregate page and byte ceilings. For sleep, call `healthmd_sleep_sessions` instead of substituting canonical extraction.

## 8. Verify completeness before answering

Do not treat tool success as proof of complete health coverage. Check all of the following:

- the refresh reached a terminal successful state for the same exact dates, metrics, sources, and detail level;
- the response schema and version are recognized;
- the requested range and timezone match the question;
- each stated value retains its canonical metric ID and unit;
- coverage status, days considered, days with values, and every missing interval are reported;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped`, and `cancelled` are not converted to zero;
- traversal completed, or any remaining cursor or aggregate ceiling is disclosed;
- evidence/source descriptors and limitations remain attached to the answer;
- factual direction is not turned into diagnosis, treatment advice, causation, or “better/worse” language.

### Read partial results without discarding useful data

A typed query can return a valid `healthmd.query_response` while only part of the requested scope completed. The generated [partial query response fixture](/docs/reference/generated/automation/agent-query-response-partial.json) retains an available Steps item and reports the failed day separately:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

The strings inside `items` and `limitations` above are explanatory abbreviations; use the downloadable generated fixture for exact fields and evidence. Preserve the retained item, failed interval, coverage counts, and limitation together.

Do not add `status: "partial_success"` to `healthmd.query_response`. That status belongs to higher-level CLI and export envelopes when acquisition, traversal, or file generation is incomplete. A timeout is different again: it is an unknown durable-job outcome that must be inspected by job ID.

Structured failures use `healthmd.query_error` v1 rather than a partial response. Inspect [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) for the generated production shape with stable code, message, retryability, and typed details.

## 9. Recover from a timeout safely

A timeout, closed host, or cancelled MCP waiter does not cancel an accepted refresh.

1. Keep the returned `job_id`.
2. Call `healthmd_job_status` with that ID.
3. If the immutable job is resumable, review and approve `healthmd_job_resume` with the same ID and a finite wait timeout.
4. Start a new refresh only after status proves that no accepted job can still complete.
5. Use `healthmd_job_cancel` only when you intend to terminate the job; cancellation is terminal only after iPhone acknowledgement.

Never retry blindly after an unknown outcome. Durable refresh jobs preserve the accepted scope and committed frontier.

## You are connected

The first read-only workflow is complete when doctor is ready, the explicit refresh is terminal, the bounded query has complete traversal, and you have inspected coverage, evidence, units, and limitations.

Generated-file exports are a separate approval-gated workflow. The released Mac tool writes into the folder already selected in Health.md for Mac; it does not accept an arbitrary destination argument.

<div class="related">
  <a href="/docs/mcp/"><span>Tool catalog</span>Review all released Mac tools, exact schemas, MCP Apps, paging, and safety boundaries.</a>
  <a href="/docs/configuration/"><span>Other clients</span>Choose between the released Mac integration and the clearly marked portable preview.</a>
  <a href="/docs/agent-queries/"><span>Next questions</span>Run typed metric, sleep, workout, comparison, coverage, and evidence workflows.</a>
  <a href="/docs/agents/"><span>Trust model</span>Understand encrypted context, request scope, retention, evidence, and reporting rules.</a>
</div>
