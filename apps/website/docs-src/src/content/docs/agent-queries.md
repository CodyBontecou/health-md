---
title: "Typed query cookbook"
description: "Run fresh or cached Health.md metric, sleep, training, workout, coverage, period-comparison, and evidence queries with explicit paging and missingness."
---

The high-level CLI commands turn common health-data questions into fixed, typed query operations. They acquire the requested iPhone data by default, query the encrypted Mac context, and return versioned JSON with evidence and coverage.

Use [canonical extraction](/docs/cli-extract/) instead when you need full `healthmd.health_data` days or source records.

## Check readiness and discover metrics

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

The metric catalog returns canonical IDs, display names, categories, units, and availability requirements. It does not claim that HealthKit authorization was granted for a metric.

Copy IDs from the catalog rather than guessing them.

## Query metric series

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

Categories expand through the current catalog:

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Multiple metric and category flags are combined. Fresh acquisition carries the expanded selection to iPhone without changing saved export settings.

The response uses a `healthmd.cli_metric_query` v1 envelope. It keeps acquisition diagnostics alongside the nested typed query response.

## Fresh, cached, and reuse-covered

Fresh is the default:

```bash
healthmd query --metric resting_heart_rate --last 30
```

This requests the exact scope from the connected iPhone, commits updated encrypted owner days, and then queries them.

Cached mode does not contact iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Use cached mode for offline analysis only when the stored capture time and coverage are acceptable.

`--reuse-covered` checks encrypted summary coverage first:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md skips acquisition only when every requested metric and day has complete compatible summary coverage. Lossless requests and newly projected sleep-session operations do not use this shortcut.

## Understand completion fields

Fresh query responses separate three concepts:

| Field | Question answered |
|---|---|
| `requested_scope_status` | Did every requested metric, source, provider, and owner day complete for this acquisition? |
| `corpus_status` | Did other branches in the captured corpus report warnings, skips, or failures? |
| `unrelated_skips` | Which skipped or unsupported branches were outside the requested scope? |

A complete requested scope can coexist with unrelated corpus skips. Health.md keeps both facts instead of falsely downgrading the requested result or hiding corpus diagnostics.

For fresh work, completion counts only blobs replaced after that refresh started. Stale cached values cannot satisfy a failed request.

## Page through results

Without `--all-pages`, the command returns one bounded page. Inspect `next_cursor`:

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

A non-null cursor means more results exist. The outer high-level status remains `partial_success` until traversal is complete.

Automatic traversal follows opaque cursors with repeat checks:

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

The response keeps the first `healthmd.query_response` under `query`, later versioned responses under `pages`, and a `healthmd.cli_query_receipt` v1 containing page, item, fact, and evidence counts plus terminal traversal status.

Automatic traversal has an aggregate page and byte ceiling. If reached, narrow the date or metric selection or use the [low-level API](/docs/agent-api/) to page manually.

## Progress and table output

Write health-free phase and page progress as JSONL to stderr:

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON is the complete output. Table mode is an opt-in lossy TSV view for a person at a terminal:

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

The table footer retains coverage, source, limitation, completion, and unrelated-skip notes. Do not use table output when a script needs exact typed values or evidence.

## Sleep sessions

Apple Health sleep stages cross midnight and can overlap by source. The sleep command builds stable sessions instead of treating each owner day as one numeric total.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Exact dates and all-history selection are also available:

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Each session can report:

- stable session identity;
- owner date and local timezone;
- exact local and UTC start and end timestamps;
- overnight or nap classification;
- selected stage totals;
- observed and untracked duration;
- completeness and exclusions;
- fixed session-relative window;
- adjacent-day physiology coverage;
- source evidence.

Session acquisition requests lossless canonical sleep-stage intervals and the complete canonical stage metric set. Health.md reads at most one technical adjacent owner day for boundaries, then excludes unrelated dates from the result.

Overlapping stage sources are deduplicated for total asleep duration. Aggregate-only cached context is labeled `aggregated`; it does not claim interval observation coverage. A fixed `first:4h` window never apportions a daily aggregate across four hours.

## Workout and sleep alignment

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

For each selected workout, Health.md finds the nearest eligible preceding and following sleep sessions within 36 hours. It reports:

- stable workout and session IDs;
- exact timing gaps;
- requested sleep windows;
- physiology sample counts;
- stage and session coverage;
- evidence and exclusions.

The operation is deterministic temporal alignment. It does not claim that a workout caused a sleep result or that sleep caused workout performance. It reads no more than two technical adjacent owner days and does not return unrelated data.

## Workout listing

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

Workout listing preserves stable identity, exact timestamps, typed details, evidence, and missingness. Results are ordered by start timestamp and stable workout identity. There is no fixed total workout cap; page controls bound each response.

## Coverage

Use coverage when the question is "What do I have?" rather than "What is the value?"

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

Coverage returns requested and available ranges, days considered, days with values, and status-bearing missing intervals. Adjacent intervals with the same status and reason may be compressed without losing meaning.

A day with no matching observations can be `complete_empty`. A day that was never synchronized has a different status. Neither becomes zero.

## Compare exact periods

The CLI never guesses whether a metric should be summed, averaged, minimized, maximized, counted, or selected by latest value. Put the aggregation next to each metric ID:

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

Supported aggregations are:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Unit or type mismatches fail instead of being combined silently. A missing period has no aggregate value. A zero first-period baseline has an absolute change but no percent change and includes `zero_baseline` as a limitation.

Direction is factual: `increased`, `decreased`, `unchanged`, or `not_comparable`. It never means better or worse.

## Training evidence packets

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Request specific workout details only when needed:

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

Selecting workout details requests the required lossless scope for that request. The packet contains factual values, coverage, source descriptors, evidence locators, and limitations.

Packet IDs are deterministic SHA-256 digests of semantic content. Regenerating the same packet at another time keeps the semantic ID even though generation metadata can change.

Evidence packet kinds in contract v1 include `daily_wellness`, `training`, and `doctor_visit`. The high-level convenience command currently exposes the training packet. Use the low-level API for exact request bodies.

## Date ownership and timezone

Query dates are compact-context `owner_date` values. Each day also preserves the exact half-open UTC interval and captured IANA calendar timezone used to form it.

Sleep sessions keep local timestamps and cross-midnight dates. Technical adjacent reads exist so a session can cross an owner-day boundary without moving data according to the Mac's current timezone.

When asking an agent a date-sensitive question, include the intended owner dates and inspect the returned timezone instead of assuming the computer's timezone.

## Do not hide missingness in an agent answer

A safe summary should retain:

- metric ID and canonical unit;
- date range and timezone;
- fresh, cached, or reuse-covered mode;
- requested-scope and corpus status;
- page traversal completion;
- evidence references or source digest;
- complete-empty and missing intervals;
- warnings, limitations, and unrelated skips.

Do not average away failed days, treat absence as zero, or describe temporal alignment as a cause.

## Related

<div class="related">
  <a href="/docs/agents/"><span>Architecture</span>Local agents and health context: setup, encryption, request scope, evidence, and retention.</a>
  <a href="/docs/mcp/"><span>MCP</span>Local MCP helper: typed equivalents for query, sleep, alignment, workouts, coverage, comparison, and evidence.</a>
  <a href="/docs/agent-api/"><span>Raw contracts</span>Loopback query API: exact requests, one-page responses, refresh, and job routes.</a>
  <a href="/docs/reference/evidence-packets/"><span>Reference</span>Compact queries and evidence packets: typed values, cursors, operations, coverage, and IDs.</a>
</div>
