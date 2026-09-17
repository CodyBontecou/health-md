---
title: "healthmd query"
description: "Discover and run Health.md's fixed typed query operations from the command line."
---

Run a fixed typed operation through the same registry and canonical evaluator used by the Health.md MCP server.

Typed queries currently require a paired iPhone with query protocol v3. They are not available from an Android source.

## Synopsis

```text
healthmd query [OPERATION] [--arguments <JSON>] [OPTIONS]
```

## Discovery

List all operations without contacting the phone:

```bash
healthmd query
```

Describe one operation, its required fields, defaults, and examples:

```bash
healthmd query healthmd_sleep_sessions
```

Add `--json` for the complete input schema:

```bash
healthmd --json query healthmd_sleep_sessions
```

Discovery does not open credentials or contact the phone.

## Options

| Argument or option | Description | Default |
|---|---|---|
| `[OPERATION]` | Fixed operation name. Omit to list the operation catalog. | — |
| `--arguments <JSON>` | Exact JSON object accepted by the selected operation. Omit to inspect its schema. | — |
| `--timeout <SECONDS>` | Wait for the foreground iPhone query. Range: 1–3,600. | `1200` |
| `--wake-timeout <SECONDS>` | Wait for an unavailable paired phone before starting. | `120` |
| `--no-wake` | Skip the best-effort notification nudge. | Off |

This command also accepts all [global options](/docs/cli-reference/#global-options).

## Examples

All available sleep sessions:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

A chart for an exact inclusive range:

```bash
healthmd query healthmd_metric_chart \
  --arguments '{"dates":{"type":"exact","range":{"start_date":"2026-07-01","end_date":"2026-07-07"}},"metrics":{"type":"explicit","metric_ids":["sleep_total"]}}'
```

Dates in documentation examples only demonstrate the input shape. Supply the dates required by your request.

## Query or extract

Use `query` for a typed result with explicit evidence, coverage, missingness, and limitations. Use [`healthmd extract`](/docs/cli-reference/extract/) for source-shaped canonical data.

Do not use extraction output as a substitute for the `healthmd_sleep_sessions` operation. Inspect the operation first and pass its exact input schema.

## MCP equivalent

The CLI and MCP adapters use the same operation registry. Inspect the MCP form with:

```bash
healthmd mcp schema healthmd_sleep_sessions
healthmd mcp schema healthmd_metric_chart
healthmd mcp schema
```
