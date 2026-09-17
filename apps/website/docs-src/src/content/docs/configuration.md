---
title: Configure your agent
description: Connect Codex, Claude, or another local client to Health.md without sending HealthKit data through a Health.md cloud service.
---

The Mac app contains two signed helpers. `healthmd-mcp` gives agents typed tools. `healthmd` gives you CLI commands.

The separate portable CLI can connect directly to a phone. This feature is a preview and has not completed stable release tests.

<div class="callout">
<strong>HealthKit stays on iPhone.</strong>
<p style="margin-top:6px;">A local client can use only the Health.md interfaces that you configure. The client cannot read HealthKit directly. Health.md does not upload your source library.</p>
</div>

## Choose an interface

| Goal | Start with | Continue to |
|---|---|---|
| Let Codex or Claude query and chart health data on Mac | Bundled `healthmd-mcp` over stdio | [MCP server & tools](/docs/mcp/) |
| Export canonical JSON or generated files in a Mac script | Bundled `healthmd` CLI | [CLI](/docs/cli/) |
| Connect directly to an open iPhone or Android phone without the Mac app | Portable direct CLI (**preview**) | [Direct phone access](/docs/cli-direct/) |
| Build against exact request and response envelopes | Loopback API or public contracts | [Loopback API](/docs/agent-api/) |
| Parse schemas, records, evidence, or generated fixtures | Versioned reference | [Data contracts](/docs/reference/) |

Health.md does not change from direct phone access to the Mac app without your action.

## Codex with the Mac app

<div class="availability available">
<strong>Available now · signed Mac helper</strong>
<p>Install Health.md for Mac. Open its <strong>CLI</strong> screen. If the app is not in <code>/Applications</code>, copy the displayed MCP path.</p>
</div>

Add the signed `healthmd-mcp` helper to `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Restart Codex. Call `healthmd_doctor` to check setup. Use `healthmd_metrics` to find metric IDs.

Use the refresh tool to get a small data scope. Then query that scope with a typed tool such as `healthmd_metric_chart`.

The bundled server has 21 tools for setup, refresh jobs, evidence, queries, and visualizations.

## Claude Desktop or Claude Code on Mac

Add the bundled helper to Claude Desktop's MCP configuration or to a trusted Claude Code `.mcp.json`:

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

Restart the client after you change its configuration. A project configuration requires workspace trust and server approval.

Keep the Mac and iPhone apps open when a tool requests new HealthKit data.

## Any stdio MCP client on Mac

Configure one local process:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

The host controls stdin and the process. Do not start the helper as an interactive command.

Do not use a shell wrapper that changes JSON-RPC output. Use MCP `tools/list` to get the schemas from the installed app.

## Portable direct setup

<div class="availability preview">
<strong>Public preview · not yet qualified stable</strong>
<p>The portable Rust CLI is a public preview. It includes <code>healthmd setup codex</code>, <code>healthmd mcp serve</code>, and direct pairing on Linux and Windows.</p>
</div>

On macOS or Linux, run <code>brew install CodyBontecou/tap/healthmd</code>. Then run `healthmd setup codex` to configure Codex and pair an iPhone.

You can run the setup command again without making duplicate configuration entries.

Use the mobile build that the release evidence names. A published package does not prove mobile compatibility.

Read [Direct phone access](/docs/cli-direct/) for transport and protocol details.

## Explicit CLI workflows

Use `healthmd` directly for canonical extraction or file automation:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

The bundled Mac helper and portable CLI have different commands and release status. Read [Health.md CLI](/docs/cli/) before you automate a command.

## Portable pairing and readiness

<div class="availability preview">
<strong>Preview · portable direct workflows</strong>
<p>These portable workflows are a preview. The bundled Mac MCP helper uses the Mac app's existing iPhone connection.</p>
</div>

Direct MCP and CLI workflows require one trusted pairing with Health.md on iPhone. Pairing uses authenticated encryption and the operating system credential store.

1. Enable **Direct CLI Access** in Health.md on iPhone.
2. Start pairing from `healthmd setup codex` or `healthmd direct pair`.
3. Approve the bounded pairing request on iPhone.
4. Keep Health.md in the foreground when you start a query or export.
5. Before a large request, call `healthmd_doctor` in MCP. In the portable CLI, run `healthmd status`.

Read [Direct phone access](/docs/cli-direct/) for Manual IP, Tailscale, ports, trusted devices, foreground use, and recovery.

## Configuration boundaries

A local agent configuration does not grant:

- Unrestricted HealthKit access
- Unrestricted file access
- Unrestricted URLs, shell commands, prompts, roots, or MCP sampling
- Permission to hide missing data, coverage, units, evidence, or limits
- Permission to resume, cancel, or overwrite files without the required approval.

For a complete result, inspect the requested scope, coverage, traversal, limits, and source schema. Process success is not sufficient evidence.

## Continue

<div class="related">
  <a href="/docs/mcp/"><span>Tool interface</span>Review tools, MCP Apps, schemas, paging, exports, and sandbox limits.</a>
  <a href="/docs/agent-queries/"><span>First questions</span>Run typed metric, sleep, workout, comparison, coverage, and evidence queries.</a>
  <a href="/docs/cli-extract/"><span>Canonical data</span>Extract schema-v8 documents and source records without putting large data in chat.</a>
  <a href="/docs/reference/"><span>Contracts</span>Browse versioned structures, field lists, fixtures, and integration examples.</a>
</div>
