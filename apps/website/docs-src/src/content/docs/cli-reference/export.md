---
title: "healthmd export"
description: "Export a platform-native raw artifact or production-generated Health.md files."
---

Export either validated platform-native raw data or files produced by the Health.md mobile app.

## Synopsis

```text
healthmd export DATE (--raw [--output <PATH>] | --destination <ABSOLUTE_DIRECTORY>) [OPTIONS]
```

Choose exactly one [date selection](/docs/cli-reference/#date-selection) and one mode. Running `healthmd export` without a complete request returns local guidance and does not contact a phone.

## Modes

### Raw artifact

```bash
healthmd export --last 7 --raw --output week.json
```

`--raw` returns the source platform's validated native artifact. Omit `--output` to stream it to stdout. iPhone uses canonical Apple Health JSON. Android preserves provider-native Health Connect JSON or NDJSON.

### Generated files

```bash
healthmd export --yesterday --destination /absolute/path/to/vault
```

The mobile app's production exporters create the files. The destination must already exist, be absolute, and not be a symbolic link. The CLI validates and binds it before transfer.

## Options

| Option | Description | Default |
|---|---|---|
| `--raw` | Select raw-artifact mode. | Off |
| `--output <PATH>` | Atomically write a raw artifact. Valid only with `--raw`; omit to use stdout. | stdout |
| `--destination <DIRECTORY>` | Select generated-file mode and write under this existing absolute directory. | — |
| `--use-device-settings` | Use saved export settings from the paired phone. Alias: `--use-iphone-settings`. | Off |
| `--profile <PROFILE_ID>` | Resolve a saved export profile on the phone. Conflicts with device settings and selectors. | — |
| `--provider <PROVIDER>` | Select the Android raw provider. | `health_connect` |
| `--raw-format <json\|ndjson>` | Select the physical Android raw format. | `ndjson` |
| `--metric <METRIC_ID>` | Select one canonical metric. Repeatable. | — |
| `--category <CATEGORY>` | Select one canonical category. Repeatable. | — |
| `--all-metrics` | Select every supported metric. Conflicts with metric and category selectors. | Off |
| `--detail <summary\|lossless>` | Select summary values or source-record detail. | `summary` |
| `--object <ALIAS>` | Select a canonical object alias. Repeatable. | — |
| `--field <JSON_POINTER>` | Retain an RFC 6901 JSON Pointer. Repeatable. | — |
| `--source <SOURCE_ID>` | Select a canonical source. Repeatable. | — |
| `--allow-partial` | Accept a validated partial result with a successful exit status. | Off |
| `--timeout <SECONDS>` | Wait for preparation and transfer. Range: 5–900. | `300` |
| `--wake-timeout <SECONDS>` | Wait for an unavailable paired phone before starting. | `120` |
| `--no-wake` | Skip the best-effort notification nudge. | Off |

This command also accepts all [date and global options](/docs/cli-reference/).

## Examples

```bash
# One complete local-calendar day
healthmd export --yesterday --raw --output yesterday.json

# Exact inclusive range streamed to stdout
healthmd export --from 2026-07-01 --to 2026-07-07 --raw

# Large Android export as NDJSON
healthmd export --all --raw --provider health_connect \
  --raw-format ndjson --output health-connect.ndjson

# Files produced with a saved mobile profile
healthmd export --last 7 \
  --profile 11111111-2222-4333-8444-555555555555 \
  --destination /absolute/path/to/vault
```

## Platform behavior

| Source | Raw artifact | Generated files |
|---|---|---|
| iPhone | Canonical Apple Health artifact | Supported |
| Android | Provider-native Health Connect artifact | Supported, up to 4,096 files per job |

Use [`healthmd extract`](/docs/cli-reference/extract/) for a selected canonical iPhone projection. Android raw data is not converted into Apple Health-shaped output.

## Interruption and partial results

Timeout, Ctrl-C, process exit, network loss, or exhausted mobile background time does not cancel a durable job. Preserve the returned job UUID, inspect it with `healthmd status --job`, and use [`healthmd resume`](/docs/cli-reference/resume/).

A validated partial result exits nonzero unless `--allow-partial` is present.
