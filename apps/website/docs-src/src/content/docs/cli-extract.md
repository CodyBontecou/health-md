---
title: "Canonical health data extraction"
description: "Use healthmd extract to acquire selected Apple Health metrics and emit canonical schema-v7 documents, source records, JSON Pointer projections, or JSONL with explicit receipts."
---

`healthmd extract` is the source-data command for scripts and agents. It asks iPhone to acquire only the selected metrics and detail, validates the durable transfer, removes the transport envelope, and emits canonical `healthmd.health_data` v7 documents or clearly labeled projections.

Use extraction when you need original Health.md data. Use [typed queries](/docs/agent-queries/) when you need sessions, comparisons, workout alignment, coverage, or evidence packets.

## Basic shape

An extraction needs:

1. at least one metric, category, object, or `--all-metrics` selector;
2. one date selector;
3. optional detail, object, field, format, output, timeout, and partial-result choices.

```bash
healthmd extract \
  (--metric ID | --category NAME | --object NAME | --all-metrics) ... \
  (--from DATE --to DATE | --last N | --yesterday | --all) \
  [--detail summary|lossless] \
  [--source apple_health] \
  [--field /JSON/POINTER] ... \
  [--format json|jsonl] \
  [--timeout 5...900] \
  [--allow-partial] \
  [--output PATH]
```

The current canonical extraction source is `apple_health`. Provider-native sidecars stay in their own contracts and are not translated into synthetic Apple Health values.

## Start with a narrow request

```bash
# One category, one day, summary detail
healthmd extract --category Sleep --yesterday --output sleep.json

# One metric for the last 30 complete days
healthmd extract --metric resting_heart_rate --last 30 \
  --output resting-heart-rate.json

# Every selected source object for one exact range
healthmd extract --all-metrics \
  --from 2026-07-01 --to 2026-07-07 \
  --detail lossless --output health-week.json
```

Metric and category names are validated against the current catalog before iPhone work begins. Repeat selectors to combine them.

```bash
healthmd extract \
  --metric sleep_total \
  --metric resting_heart_rate \
  --category Workouts \
  --last 14 --output recovery-context.json
```

## Selection happens before HealthKit reads

Extraction does not fetch a saved all-metrics export and trim it afterward. The CLI resolves your selector into an immutable `CanonicalHealthDataSelection` and sends it to iPhone. Health.md checks and reads only the ordinary HealthKit types that back the selected metrics.

This distinction matters for privacy, performance, and completeness:

- unselected metrics are not acquired;
- saved iPhone metric preferences do not change;
- summary requests do not create a hidden source archive;
- lossless requests fetch only source types needed by the selection;
- the selection becomes part of the durable request fingerprint.

Object and JSON Pointer selectors narrow emitted data after capture. Metric, category, source, and detail selectors narrow the iPhone acquisition itself.

## Summary and lossless detail

Summary is the default:

```bash
healthmd extract --category Activity --last 7 --detail summary
```

Summary output can include typed daily summaries, query diagnostics, and `raw_capture_status: not_requested`. That status is honest: the command did not fetch canonical source records.

Request lossless detail when source objects, UUIDs, exact timestamps, provenance, or archive diagnostics matter:

```bash
healthmd extract --metric workouts --last 14 \
  --detail lossless --output workouts-lossless.json
```

Archive-oriented objects such as `records` imply lossless detail even if `--detail` is omitted.

## Object selectors

Use `--object` to keep a known portion of each selected day. Current names include:

| Object | Typical contents |
|---|---|
| `sleep` | Daily sleep summary fields |
| `activity` | Steps, energy, distance, exercise, and related activity summaries |
| `heart` | Heart rate, resting heart rate, HRV, and related summaries |
| `vitals` | Blood pressure, glucose, temperature, oxygen, and other vital summaries |
| `body` | Weight, composition, height, and body measurements |
| `nutrition` | Nutrient and hydration summaries |
| `mindfulness` | Mindful sessions and mental-wellbeing summaries |
| `mobility` | Walking, gait, and mobility fields |
| `hearing` | Audio exposure and hearing fields |
| `reproductive-health` | Reproductive, pregnancy, and cycle fields |
| `cycling` | Cycling summaries |
| `vitamins` / `minerals` | Nutrient-specific summaries |
| `symptoms` | Symptom data |
| `medications` | Medication data when available and authorized |
| `workouts` | Canonical workout summary objects |
| `archive` | Canonical HealthKit archive envelope |
| `records` | Canonical source records; implies lossless detail |
| `external-records` | External records already present in the public day |
| `query-results` | Per-query capture outcomes |
| `warnings` | Integrity warnings |

Examples:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --output workout-summaries.json

healthmd extract --metric workouts --last 30 \
  --object records --detail lossless --output workout-records.json

healthmd extract --category Sleep --last 7 \
  --object sleep --object query-results --output sleep-with-status.json
```

## JSON Pointer projection

Repeat `--field` with RFC 6901 JSON Pointers to emit exact values or status entries:

```bash
healthmd extract --category Sleep --last 7 \
  --field /sleep/totalDuration \
  --field /sleep/deepSleep \
  --field /raw_capture_status \
  --output selected-sleep-fields.json
```

Pointer results are projections, not complete daily documents. They reference the source schema and day but do not carry `schema: healthmd.health_data` in a way that could make a subtree look like a full export.

An absent selected path is reported with complete-empty or the day's incomplete status. Health.md does not convert absence into zero.

## JSON output

Default JSON output contains one of these data collections:

- `health_data` for complete canonical daily documents; or
- `projections` for object or pointer results.

It also contains `healthmd.extract_receipt`, which records:

- resolved selection and date range;
- source and detail level;
- per-day outcomes;
- retained item and capture counts;
- missing dates;
- partial or failure diagnostics;
- output completion status.

The receipt is protocol metadata. It does not replace the source schema.

## JSONL output

Use JSONL for stream processing:

```bash
healthmd extract --category Sleep --last 30 \
  --format jsonl --output sleep.jsonl
```

Each line is one data item. The receipt is not mixed into the health-data stream:

- with `--output`, it is written to `OUTPUT.receipt.json`;
- without `--output`, it is written to stderr.

This makes pipelines predictable:

```bash
healthmd extract --metric workouts --last 30 \
  --object workouts --format jsonl --output workouts.jsonl

jq -c 'select(.workouts != null)' workouts.jsonl
jq '{status, retained_item_count, missing_dates}' workouts.jsonl.receipt.json
```

Do not pipe stderr into the JSONL parser because stderr carries the receipt and health-free progress.

## Complete, empty, and partial results

Health.md keeps these states distinct:

| State | Meaning |
|---|---|
| `success` | Every requested branch completed, including complete-empty branches |
| `complete_empty` | The requested scope was represented and had no observations |
| `partial_success` | Some requested data is retained, but at least one requested branch is incomplete |
| `failed` | A requested branch failed |
| `unsupported` | The platform or HealthKit does not support the requested branch |
| `skipped` | Health.md intentionally did not query that branch |
| `cancelled` | iPhone acknowledged cancellation |
| `missing` | A requested day or branch was not represented |

A partial extraction emits no retained data by default. Add `--allow-partial` only when your consumer is designed to accept and preserve incomplete scope:

```bash
healthmd extract --category Sleep --last 30 \
  --allow-partial --output sleep-partial.json
```

The flag changes emission and exit behavior. It does not remove diagnostics or turn partial data into complete data.

## Mac app and direct backends

The command works through either backend:

```bash
# Bundled helper default: Mac app loopback and connected iPhone
healthmd extract --category Sleep --last 7 --output sleep.json

# Direct-capable helper: bypass the Mac app
healthmd --backend direct extract \
  --category Sleep --last 7 --output sleep.json
```

Both paths use the same public daily schema and strict validation. The transport, pairing, storage, and job records differ.

## Large history

`--all` has no fixed date cap:

```bash
healthmd extract --metric steps --all --output all-steps.json
```

The iPhone resolves the earliest available selected record, pins every source-calendar day through today, and transfers bounded partitions. The CLI assembles and validates on disk rather than building one unbounded in-memory response.

Use JSONL or a narrower selection when a corpus is large. Available disk space and one unusually dense day remain practical limits.

## Privacy checklist

- Prefer `--output` for any health-bearing result.
- Protect output and receipt files with the same care as the Apple Health source.
- Do not use shell tracing around health commands.
- Keep payloads out of CI logs and agent transcripts.
- Inspect only receipt, count, status, schema, and missingness fields when troubleshooting.
- Delete temporary exports after the intended consumer commits them safely.

## Related

<div class="related">
  <a href="/docs/cli/"><span>CLI</span>Health.md CLI: setup, backend selection, command map, and output rules.</a>
  <a href="/docs/agent-queries/"><span>Derived views</span>Typed query cookbook: metric series, sleep, training, workouts, comparisons, and evidence.</a>
  <a href="/docs/reference/daily-records/"><span>Schema</span>Daily records: the complete schema-v7 daily document contract.</a>
  <a href="/docs/reference/canonical-healthkit-records/"><span>Source archive</span>Canonical Apple Health records: identity, provenance, relationships, and payloads.</a>
  <a href="/docs/reference/api-and-cli/"><span>Protocol</span>API and CLI reference: extraction requests, receipts, strict validation, and exit behavior.</a>
</div>
