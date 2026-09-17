---
title: "healthmd extract"
description: "Extract selected canonical healthmd.health_data content from a paired iPhone."
---

Request a scoped canonical `healthmd.health_data` projection from a paired iPhone. `extract` is source-data access. It is separate from typed sleep, workout, chart, and evidence queries.

## Synopsis

```text
healthmd extract DATE SCOPE [OPTIONS]
```

Choose exactly one [date selection](/docs/cli-reference/#date-selection) and at least one primary scope selector: `--metric`, `--category`, `--object`, or `--all-metrics`.

Running `healthmd extract` without a complete request returns local guidance and does not contact the phone.

## Options

| Option | Description | Default |
|---|---|---|
| `--metric <METRIC_ID>` | Select one canonical metric. Repeatable. | — |
| `--category <CATEGORY>` | Select one canonical category. Repeatable. | — |
| `--all-metrics` | Select every supported metric. Conflicts with metric and category selectors. | Off |
| `--detail <summary\|lossless>` | Select summary values or lossless source records. | `summary` |
| `--object <ALIAS>` | Select a canonical object alias or absolute JSON Pointer. Repeatable. | — |
| `--field <JSON_POINTER>` | Retain an RFC 6901 JSON Pointer. Repeatable. | — |
| `--source <SOURCE_ID>` | Select a canonical source. Repeatable. | — |
| `--output <PATH>` | Atomically write the result. Omit to stream it to stdout. | stdout |
| `--format <json\|jsonl>` | Select the canonical output encoding. JSONL also emits a health-free receipt. | `json` |
| `--allow-partial` | Accept a validated partial result with a successful exit status. | Off |
| `--timeout <SECONDS>` | Wait for preparation and transfer. Range: 5–900. | `300` |
| `--wake-timeout <SECONDS>` | Wait for an unavailable paired phone before starting. | `120` |
| `--no-wake` | Skip the best-effort notification nudge. | Off |

This command also accepts all [date and global options](/docs/cli-reference/).

## Examples

```bash
# Sleep summaries for the previous seven complete days
healthmd extract --category Sleep --last 7 --output sleep.json

# Lossless workout records
healthmd extract --metric workouts --last 14 \
  --object workouts --detail lossless --output workouts.json

# Stream selected data as JSONL
healthmd extract --category Sleep --last 7 --format jsonl

# Retain an exact field from selected content
healthmd extract --metric resting_heart_rate --last 30 \
  --field /health_data/metrics/resting_heart_rate \
  --output resting-heart-rate.json
```

When JSONL is written to a file, the CLI also writes a health-free receipt beside it as `<OUTPUT>.receipt.json`.

## Platform support

Canonical extraction is currently an iPhone capability. For Android, use [`healthmd export --raw`](/docs/cli-reference/export/) to preserve the provider-native Health Connect artifact.

## Completeness

A complete empty result means Health.md represented the requested scope and found no observations. It is different from zero, missing, failed, skipped, unsupported, or partial.

Without `--allow-partial`, incomplete canonical extraction emits no accepted partial values and exits nonzero. See [canonical extraction](/docs/cli-extract/) for object aliases, projections, and completeness receipts.
