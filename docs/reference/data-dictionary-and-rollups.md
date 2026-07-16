# Data dictionary and roll-ups

Health.md writes `_healthmd_data_dictionary.json` beside daily exports. It tells people and software how to interpret flat summary/frontmatter keys without guessing units or aggregation behavior.

The dictionary describes summary projections and compact lossless diagnostics. It does not replace the canonical archive schema.

## Dictionary entry

| Field | Type | Meaning |
|---|---|---|
| `key` | string | Actual output key after user key style/rename. |
| `canonicalKey` | string | Stable Health.md flat summary key. |
| `metricId` | string | Metric-selection identifier. |
| `displayName` | string | User-facing metric name. |
| `category` | string | Health.md metric category. |
| `unit` | string | Canonical structured summary unit; empty for list/category-like values. |
| `healthKitIdentifier` | optional string | Primary source identifier where one exists. |
| `metricType` | string | `quantity`, `category`, `workout`, or diagnostic. |
| `aggregation` | string | Compatibility alias for `dailyAggregation`. |
| `dailyAggregation` | string | Rule used to produce the daily value. |
| `healthKitAggregation` | string | Source-definition aggregation behavior. |
| `rollup` | object | Period aggregation guidance. |
| `schemaVersion` | integer | Daily schema version represented. |

Complete generated dictionary: [`generated/core/data-dictionary.json`](./generated/core/data-dictionary.json).

## Metric catalog

The generated catalog joins these production sources:

- `HealthMetrics.all`
- `HealthMetricExportMapping.metricIdToFrontmatterKeys`
- `reviewedArchiveOnlyMetricIDs`
- `HealthMetricDataDictionary.entries`
- reviewed HealthKit catalog identifiers and units where available

It provides exhaustive selection coverage, including metrics with no daily summary key.

Open [`generated/core/metric-catalog.md`](./generated/core/metric-catalog.md) for the contract matrix and [`generated/core/metric-examples.md`](./generated/core/metric-examples.md) for one generated synthetic reference entry per metric ID.

## Daily aggregation values

| Value | Daily meaning |
|---|---|
| `sum` | Total over the selected daily window. |
| `duration_sum` | Total duration. |
| `count` | Number of retained events/items. |
| `average` | Average daily projection. |
| `minimum` | Daily minimum. |
| `maximum` | Daily maximum. |
| `latest` | Latest value or identity/provenance. |
| `weighted_average` | Average weighted by a documented measure such as workout duration. |
| `first_time` | First clock value. |
| `last_time` | Last clock value. |
| `list` | List/set-like projection. |
| `category_latest` | Latest categorical state. |

Missing is not zero. Every roll-up rule also states how missing days are handled.

## Roll-up rule object

| Field | Meaning |
|---|---|
| `primary` | Headline period calculation. |
| `statistics` | Additional statistics emitted. |
| `periods` | Supported `weekly`, `monthly`, and `yearly` periods. |
| `preferredSource` | Preferred daily/detail source for recomputation. |
| `nullHandling` | Explicit missing-day behavior. |
| `weightedBy` | Optional weighting field. |
| `notes` | Human-readable calculation guidance. |

The generated behavior matrix is at [`generated/rollups/aggregation-behavior.md`](./generated/rollups/aggregation-behavior.md).

## Roll-up schema

Roll-up files identify themselves as `healthmd.rollup_summary`. They are derived from daily summary snapshots and do not embed source archives.

Common metadata includes:

- `schema` and `schema_version`;
- period type and period ID;
- start/end dates;
- expected and counted days;
- coverage percent;
- source dates;
- summarized metrics/categories;
- units and per-metric statistics.

## Period behavior

### Sums, durations, and counts

The period headline is the sum of daily values. Additional statistics can include daily average, daily minimum/maximum, and days counted.

### Average

The period averages exported daily aggregate values. It does not silently reconstruct unavailable source samples.

### Weighted average

Workout-derived averages prefer workout detail and duration weighting. When only daily values are available, the documented fallback applies.

### Minimum and maximum

A period minimum is the minimum of daily minima. A period maximum is the maximum of daily maxima.

### Latest

Identity/inventory-like values keep the latest observed daily value and can include value counts. Numeric latest metrics can also expose trend context.

### Lists

Lists are unioned and occurrence counts are preserved.

### Categories

Categorical values retain the latest value plus a histogram/value counts. Health.md does not invent numeric averages for categories.

### Clock times

First/last-time metrics retain earliest, latest, and average time-of-day statistics without conflating clock values with calendar dates.

## Coverage

- `days_expected` is the size of the full period.
- `days_counted` is the number of daily snapshots retained for the roll-up.
- Per-metric days counted can be smaller when a snapshot has no value for that metric.
- Future dates in a current period remain expected but are not queried.
- A failed daily fetch reduces coverage; an absent metric value does not become zero.

## Format-specific roll-ups

| Format | Representation |
|---|---|
| JSON | Structured metadata, metrics, categories, and statistics. |
| CSV | Primary and statistic rows per metric. |
| Markdown | Frontmatter, category tables, and detailed statistics. |
| Obsidian Bases | Frontmatter-focused `rollup_metrics` properties. |

Complete synthetic weekly examples:

- [`generated/rollups/weekly.json`](./generated/rollups/weekly.json)
- [`generated/rollups/weekly.csv`](./generated/rollups/weekly.csv)
- [`generated/rollups/weekly.md`](./generated/rollups/weekly.md)
- [`generated/rollups/weekly-bases.md`](./generated/rollups/weekly-bases.md)

## Consumer guidance

1. Validate the roll-up schema separately from daily records.
2. Read the dictionary rule for every metric.
3. Preserve `days_counted` and coverage with every derived statistic.
4. Do not use raw-record count roll-ups as proof of query completeness.
5. Use daily JSON/CSV archives when source-event identity is required.
6. Regenerate historical periods after re-exporting changed daily source data.
