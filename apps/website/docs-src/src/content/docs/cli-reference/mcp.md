---
title: "healthmd mcp"
description: "Run the local Health.md MCP server or inspect its fixed tool schemas."
---

Run Health.md's fixed Model Context Protocol surface or inspect tool schemas without starting a server.

## Synopsis

```text
healthmd mcp [serve|serve-read-only|schema]
```

Running `healthmd mcp` without a subcommand returns local discovery. It does not start a listener.

## Subcommands

| Command | Description |
|---|---|
| `healthmd mcp serve` | Serve the complete local MCP surface over stdio. |
| `healthmd mcp serve-read-only` | Serve readiness and typed-query tools over stdio; omit pairing and export tools. |
| `healthmd mcp schema [TOOL]` | Print one tool schema or the complete fixed catalog. |

Default release builds include these local stdio commands. The experimental `serve-http` command is source-build-only. See [Remote MCP architecture](/docs/mcp/#portable-direct-mcp-preview) before enabling it.

All subcommands accept the [global options](/docs/cli-reference/#global-options). After a server starts, stdout is reserved for MCP JSON-RPC. `--json` and `--human` do not change the protocol.

## `healthmd mcp serve`

```text
healthmd mcp serve [--timeout-seconds <SECONDS>]
```

Starts the complete local stdio server, including pairing, readiness, typed queries, visualizations, and approval-annotated export job tools.

| Option | Description | Default |
|---|---|---|
| `--timeout-seconds <SECONDS>` | Default timeout for readiness and query operations. | `1200` |

The server exposes only fixed Health.md operations. It has no shell, SQL, arbitrary URL, or arbitrary file-read tool.

## `healthmd mcp serve-read-only`

```text
healthmd mcp serve-read-only [--timeout-seconds <SECONDS>]
```

Starts a least-privilege local stdio server containing readiness, discovery, and typed-query tools. Pairing and filesystem export tools are absent. Pair the phone separately:

```bash
healthmd direct pair
healthmd mcp serve-read-only
```

## `healthmd mcp schema`

```text
healthmd mcp schema [TOOL]
```

This command is local and health-free. Omit `TOOL` to print the complete fixed catalog.

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema
```

## Wake environment

MCP query and job operations use the same 120-second wake window as the shell commands. Set `HEALTHMD_WAKE_TIMEOUT=<SECONDS>` for the server process. Use `0` to disable waiting. Set `HEALTHMD_NO_WAKE=1` to disable the best-effort notification nudge.

## Experimental Streamable HTTP

Source builds with the `streamable-http` feature add `healthmd mcp serve-http`. It always binds loopback and exposes only the read-only remote-safe tool set. OAuth support requires the separate `oauth-resource-server` feature and exact issuer, audience, JWKS, subject, scope, Host, and Origin validation.

This mode is absent from release archives. Do not expose the loopback socket directly to a network.
