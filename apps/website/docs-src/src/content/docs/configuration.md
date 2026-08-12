---
title: Configure your agent
description: Choose the Health.md MCP or CLI interface, configure Codex, Claude, or another local client, and connect a paired iPhone without routing HealthKit through a cloud service.
---

The released Mac app includes two signed local helpers: `healthmd-mcp` for typed agent tools and `healthmd` for explicit CLI workflows. A separate cross-platform CLI with direct iPhone MCP is documented as a preview until its first public package completes physical-device release QA.

<div class="callout">
<strong>HealthKit stays on iPhone.</strong>
<p style="margin-top:6px;">Configuration gives a local client access to Health.md's bounded interfaces. It does not give the computer or agent direct HealthKit access, and it does not upload your source library to a Health.md cloud.</p>
</div>

## Choose an interface

| Goal | Start with | Continue to |
|---|---|---|
| Let Codex or Claude query and chart health data on Mac | Bundled `healthmd-mcp` over stdio | [MCP server & tools](/docs/mcp/) |
| Export canonical JSON or generated files in a Mac script | Bundled `healthmd` CLI | [CLI](/docs/cli/) |
| Connect directly to an open iPhone without the Mac app | Portable direct CLI (**preview**) | [Direct iPhone access](/docs/cli-direct/) |
| Build against exact request and response envelopes | Loopback API or public contracts | [Loopback API](/docs/agent-api/) |
| Parse schemas, records, evidence, or generated fixtures | Versioned reference | [Data contracts](/docs/reference/) |

Backend and transport choices are explicit; Health.md does not silently fall back from direct iPhone access to the Mac app.

## Codex with the Mac app

<div class="availability available">
<strong>Available now · signed Mac helper</strong>
<p>Install Health.md for Mac, open its <strong>CLI</strong> screen, and copy the displayed bundled MCP path if the app is not in <code>/Applications</code>.</p>
</div>

Add the separate signed `healthmd-mcp` helper to `~/.codex/config.toml`:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"
```

Restart Codex, call `healthmd_doctor`, resolve IDs with `healthmd_metrics`, explicitly acquire a small scope with the refresh tool, then query that scope with a typed tool such as `healthmd_metric_chart`. The bundled server exposes 21 tools, including Mac readiness, encrypted-context refresh jobs, evidence, and visualizations.

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

Restart the client after changing its configuration. Project-scoped configurations still require workspace trust and explicit server approval. Keep the Mac and iPhone apps open when a tool needs fresh HealthKit data.

## Any stdio MCP client on Mac

Configure one local process:

```text
command: /Applications/Health.md.app/Contents/Helpers/healthmd-mcp
arguments: none
transport: stdio
```

The host owns stdin and the process lifecycle. Do not launch the helper as an ordinary interactive command or wrap it in a shell that changes JSON-RPC output. Use MCP `tools/list` to discover the exact schemas exposed by the installed app.

## Portable direct setup

<div class="availability preview">
<strong>Preview · not yet publicly packaged</strong>
<p>The cross-platform Rust CLI, <code>healthmd setup codex</code>, same-binary <code>healthmd mcp serve</code>, and Linux/Windows direct pairing are implemented but await their first qualified public release.</p>
</div>

After publication, `healthmd setup codex` will configure Codex idempotently and start direct iPhone pairing. Until then, do not rely on unpublished Homebrew, crates.io, installer, or GitHub release URLs. The [Direct iPhone CLI](/docs/cli-direct/) page documents the staged transport and protocol behavior.

## Explicit CLI workflows

For canonical extraction or file-oriented automation, invoke `healthmd` directly instead of asking an MCP host to carry a large source body:

```bash
healthmd status
healthmd extract --category Sleep --last 7 --output sleep.json
healthmd export --last 7 --destination "$HOME/Documents/HealthVault"
```

Availability and grammar differ between the bundled Mac helper and the standalone cross-platform CLI. Review [Health.md CLI](/docs/cli/) before copying commands into unattended automation.

## Portable pairing and readiness

<div class="availability preview">
<strong>Preview · portable direct workflows</strong>
<p>These steps describe the forthcoming cross-platform package. The released bundled Mac MCP path uses the Mac app's existing iPhone connection instead.</p>
</div>

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
  <a href="/docs/mcp/"><span>Tool interface</span>Review the 21 available Mac tools, portable 19-tool preview, MCP Apps, schemas, paging, exports, and sandbox boundaries.</a>
  <a href="/docs/agent-queries/"><span>First questions</span>Run typed metric, sleep, workout, comparison, coverage, and evidence workflows.</a>
  <a href="/docs/cli-extract/"><span>Canonical data</span>Extract selected schema-v7 documents and source records without placing large bodies in chat.</a>
  <a href="/docs/reference/"><span>Contracts</span>Browse versioned data structures, field inventories, generated fixtures, and integration recipes.</a>
</div>
