---
title: "healthmd setup"
description: "Configure a supported local AI host to use the installed Health.md MCP server."
---

Configure a supported local AI host and pair an iPhone when needed.

## Synopsis

```text
healthmd setup [codex]
```

Running `healthmd setup` without a subcommand lists supported integrations without changing configuration.

## `healthmd setup codex`

```text
healthmd setup codex [OPTIONS]
```

Creates or updates the Health.md MCP entry for Codex. The entry launches the same installed executable as `healthmd mcp serve`, so pairing credentials stay under one executable identity. Unrelated Codex settings are preserved.

| Option | Description | Default |
|---|---|---|
| `--skip-pairing` | Configure Codex without opening a pairing listener. | Off |
| `--pairing-timeout <SECONDS>` | Wait for iPhone pairing. Range: 30–600. | `180` |

This command also accepts all [global options](/docs/cli-reference/#global-options).

## Examples

Configure Codex and pair when no phone is trusted:

```bash
healthmd setup codex
```

Configure Codex after pairing separately:

```bash
healthmd direct pair
healthmd setup codex --skip-pairing
```

Restart Codex after its MCP configuration changes.

## What it changes

The command changes only the Health.md MCP entry in the supported Codex configuration. It does not install the CLI, grant mobile health permissions, copy health data, reset trust, or remove other MCP servers.

For manual server configuration and the available tools, see [MCP server and tools](/docs/mcp/).
