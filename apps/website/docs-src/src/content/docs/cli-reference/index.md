---
title: "CLI command reference"
description: "Complete healthmd command hierarchy, global options, output behavior, and exit statuses."
---

## Synopsis

```text
healthmd [GLOBAL OPTIONS] <COMMAND>
```

`healthmd` requests exports and typed queries from an open, paired iPhone or Android device. Source health reads always occur on the phone.

## Commands

| Command | Description |
|---|---|
| [`healthmd status`](/docs/cli-reference/status/) | Check live readiness or inspect one durable job. |
| [`healthmd export`](/docs/cli-reference/export/) | Export native raw data or mobile-generated files. |
| [`healthmd extract`](/docs/cli-reference/extract/) | Extract selected canonical health data from an iPhone. |
| [`healthmd query`](/docs/cli-reference/query/) | Discover or run a fixed typed query operation. |
| [`healthmd resume`](/docs/cli-reference/resume/) | Resume an interrupted durable job. |
| [`healthmd cancel`](/docs/cli-reference/cancel/) | Request cancellation of a durable job. |
| [`healthmd direct`](/docs/cli-reference/direct/) | Pair phones and manage local trust. |
| [`healthmd mcp`](/docs/cli-reference/mcp/) | Inspect or run the local MCP server. |
| [`healthmd setup`](/docs/cli-reference/setup/) | Configure a supported local AI host. |

## Global options

Global options work before or after a subcommand.

| Option | Description | Default |
|---|---|---|
| `--backend <direct\|mac-app>` | Select the execution backend. `direct` is the portable implementation; `mac-app` is reserved and currently unsupported. | `direct` |
| `--transport <manual-ip\|nearby>` | Select the direct transport. Use `manual-ip` for LAN or Tailscale. The portable CLI does not support Nearby. | `manual-ip` |
| `--device <UUID>` | Select a trusted phone. Required when more than one phone is paired. | Automatically selected when unambiguous. |
| `--port <PORT>` | Use the TCP port saved in the phone's Direct CLI settings. | `17647` |
| `--json` | Force stable machine-readable JSON for structured CLI output. | Automatic for pipes and redirects. |
| `--human` | Force readable text, including through a pipe. Conflicts with `--json`. | Automatic for an interactive terminal. |
| `-h`, `--help` | Print text help. | — |
| `-V`, `--version` | Print the CLI version. | — |

## Date selection

`export` and `extract` require exactly one date selection:

| Option | Meaning |
|---|---|
| `--yesterday` | Yesterday in the computer's local calendar. |
| `--last <DAYS>` | The previous complete local-calendar days, ending yesterday. |
| `--from <YYYY-MM-DD> --to <YYYY-MM-DD>` | An inclusive exact range. Both options are required together. |
| `--all` | All dates available from the selected source. This may create a large job. |

## Wake behavior

Export, extract, query, resume, and cancel wait for an unavailable paired phone for up to 120 seconds before failing. The phone must be unlocked and Health.md must be open to begin new work.

| Option | Description | Default |
|---|---|---|
| `--wake-timeout <SECONDS>` | Wait for the paired phone to become active. Use `0` to fail immediately. | `120` |
| `--no-wake` | Do not send the best-effort notification nudge. Waiting still follows `--wake-timeout`. | Off |

The operation-specific `--timeout` starts after the wake window.

## Output rules

| Invocation | Output |
|---|---|
| Interactive terminal | Readable text |
| Pipe or redirect | Pretty-printed JSON |
| `--json` | JSON |
| `--human` | Readable text |
| `healthmd mcp serve*` | MCP JSON-RPC on stdout |
| Raw JSON/NDJSON artifact | Exact validated artifact bytes |

Pairing instructions and health-free progress may use stderr. Do not write raw or lossless health output to logs, issue reports, shell traces, or CI artifacts.

## Exit statuses

| Status | Meaning |
|---:|---|
| `0` | Success, explicit help/version, or safe local guidance. |
| `1` | Validation, source, runtime, job, output, integrity, or unaccepted-partial failure. |
| `2` | Command-line parsing failure, such as an unknown option, invalid UUID, or conflict. |

## Local discovery

An incomplete action command returns guidance without opening credentials or contacting the phone:

```bash
healthmd export
healthmd extract
healthmd query
healthmd query healthmd_sleep_sessions
healthmd resume
healthmd cancel
healthmd direct
healthmd mcp
healthmd setup
```

Add `--json` to receive the stable guidance or schema contract instead of terminal text.
