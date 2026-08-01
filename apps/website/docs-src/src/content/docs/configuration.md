---
title: Configure your agent
description: Choose the Health.md MCP or CLI interface, configure Codex, Claude, or another local client, and connect a paired iPhone without routing HealthKit through a cloud service.
---

Health.md exposes two local agent interfaces. Use **MCP** when an agent should discover typed health tools and render results in its own interface. Use the **CLI** when a script needs explicit commands, canonical files, or durable automation.

<div class="callout">
<strong>HealthKit stays on iPhone.</strong>
<p style="margin-top:6px;">Configuration gives a local client access to Health.md's bounded interfaces. It does not give the computer or agent direct HealthKit access, and it does not upload your source library to a Health.md cloud.</p>
</div>

## Choose an interface

| Goal | Start with | Continue to |
|---|---|---|
| Let Codex or Claude query and chart health data | Local MCP over stdio | [MCP server & tools](/docs/mcp/) |
| Export canonical JSON or generated files in a script | Health.md CLI | [CLI](/docs/cli/) |
| Connect directly to an open iPhone without the Mac app | Direct CLI transport | [Direct iPhone access](/docs/cli-direct/) |
| Build against exact request and response envelopes | Loopback API or public contracts | [Loopback API](/docs/agent-api/) |
| Parse schemas, records, evidence, or generated fixtures | Versioned reference | [Data contracts](/docs/reference/) |

MCP and CLI can share the same paired direct identity. Backend and transport choices are explicit; Health.md does not silently fall back from direct iPhone access to the Mac app.

## Codex

The supported setup command updates Codex idempotently, preserves unrelated settings, and starts pairing when the local installation has no trusted iPhone:

```bash
healthmd setup codex
```

It creates a scoped MCP entry using the absolute installed executable path:

```toml
[mcp_servers.healthmd]
command = "/absolute/path/to/healthmd"
args = ["mcp", "serve"]
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

When more than one iPhone is trusted, setup can pin the intended device in `args`. Restart Codex when the command reports that configuration changed, then call `healthmd_doctor` before requesting health values.

## Claude Desktop or Claude Code

Add Health.md to Claude Desktop's MCP configuration or to a trusted Claude Code `.mcp.json`:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/absolute/path/to/healthmd",
      "args": ["mcp", "serve"]
    }
  }
}
```

Use `command -v healthmd` on macOS or Linux and `where.exe healthmd` on Windows to resolve the executable. Restart the client after changing its configuration. Project-scoped configurations still require workspace trust and explicit server approval.

## Any stdio MCP client

Configure one local process:

```text
command: /absolute/path/to/healthmd
arguments: mcp serve
transport: stdio
```

The host owns stdin and the process lifecycle. Do not launch serve mode as an ordinary interactive command and do not wrap it in a shell that changes JSON-RPC output.

The server exposes readiness, discovery, typed analysis, visualization, generated-file export, status, resume, and cancellation tools. Use MCP `tools/list` or inspect an exact local schema without contacting iPhone:

```bash
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema healthmd_sleep_sessions
```

## Explicit CLI workflows

For canonical extraction or file-oriented automation, invoke `healthmd` directly instead of asking an MCP host to carry a large source body:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

Availability and grammar differ between the bundled Mac helper and the standalone cross-platform CLI. Review [Health.md CLI](/docs/cli/) before copying commands into unattended automation.

## Pairing and readiness

Direct MCP and CLI workflows require a one-time trusted pairing with Health.md on iPhone. Pairing uses an authenticated encrypted channel and native credential storage on macOS, Linux, or Windows.

1. Enable **Direct CLI Access** in Health.md on iPhone.
2. Start pairing from `healthmd setup codex` or `healthmd direct pair`.
3. Approve the bounded pairing request on iPhone.
4. Keep Health.md foreground while starting a query or export.
5. Call `healthmd_doctor` in MCP or `healthmd status` in the portable CLI before larger work.

See [Direct iPhone access](/docs/cli-direct/) for Manual IP, Tailscale, port, trusted-device, foreground, and recovery details.

## Configuration boundaries

A local agent configuration does **not** grant:

- arbitrary HealthKit reads or writes;
- arbitrary filesystem access;
- arbitrary URLs, shell commands, prompts, roots, or sampling through MCP;
- permission to hide missingness, coverage, units, evidence, or limitations;
- permission to resume, cancel, or overwrite generated files without the applicable approval.

For a complete result, inspect requested scope, coverage, traversal, limitations, and source schema—not only process success.

## Continue

<div class="related">
  <a href="/docs/mcp/"><span>Tool interface</span>Review the 17 portable tools, MCP Apps, schemas, paging, exports, and sandbox boundaries.</a>
  <a href="/docs/agent-queries/"><span>First questions</span>Run typed metric, sleep, workout, comparison, coverage, and evidence workflows.</a>
  <a href="/docs/cli-extract/"><span>Canonical data</span>Extract selected schema-v7 documents and source records without placing large bodies in chat.</a>
  <a href="/docs/reference/"><span>Contracts</span>Browse versioned data structures, field inventories, generated fixtures, and integration recipes.</a>
</div>
