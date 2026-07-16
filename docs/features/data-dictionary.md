# Data Dictionary and Roll-up Rules

## Status

- **Docs status:** draft
- **Video priority:** low
- **Primary output:** `_healthmd_data_dictionary.json`
- **Source files:** `HealthMd/Shared/Export/HealthMetricsDictionary.swift`, `HealthMd/Shared/Export/ExportHelpers.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Health.md writes a data dictionary beside exports so people, scripts, Obsidian plugins, and AI tools can interpret summary/frontmatter fields without guessing. In current `schema_version: 6`, it documents canonical keys, units, HealthKit identifiers, daily aggregation, and weekly/monthly/yearly roll-up rules.

The dictionary describes **summary projections**, including v6 lossless diagnostics. It is not a schema for every nested canonical source payload. Source-record consumers should also parse `healthkit_record_archive` (`healthmd.healthkit_records` v1) and its tagged metadata.

## Location

```text
Health/
  _healthmd_data_dictionary.json
  2026-07-15.md
  2026-07-15.json
  2026-07-15.csv
```

With format folders enabled, the dictionary remains at the shared Health root.

## Entry shape

```json
{
  "key": "active_calories",
  "canonicalKey": "active_calories",
  "metricId": "active_energy",
  "displayName": "Active Energy",
  "category": "Activity",
  "unit": "kcal",
  "healthKitIdentifier": "HKQuantityTypeIdentifierActiveEnergyBurned",
  "metricType": "quantity",
  "aggregation": "sum",
  "dailyAggregation": "sum",
  "healthKitAggregation": "cumulative",
  "rollup": {
    "primary": "sum",
    "statistics": ["sum", "daily_average", "minimum_daily_value", "maximum_daily_value", "days_counted"],
    "periods": ["weekly", "monthly", "yearly"],
    "preferredSource": "daily_frontmatter",
    "nullHandling": "ignore_missing_days_and_report_days_counted",
    "weightedBy": null,
    "notes": "Sum daily values and report days counted."
  },
  "schemaVersion": 6
}
```

## Fields

| Field | Meaning |
|---|---|
| `key` | Actual exported frontmatter/Bases key after style and user renames. |
| `canonicalKey` | Stable Health.md summary key. |
| `metricId` | Health.md metric selection identifier. |
| `displayName` | Human-readable label. |
| `category` | Health.md category. |
| `unit` | Canonical summary unit; empty means categorical/list-like. |
| `healthKitIdentifier` | Source identifier when one exists. |
| `metricType` | `quantity`, `category`, or `workout`. |
| `aggregation` | Backward-compatible alias for `dailyAggregation`. |
| `dailyAggregation` | How the daily summary value was calculated. |
| `healthKitAggregation` | Broader source aggregation definition. |
| `rollup` | Period aggregation guidance. |
| `schemaVersion` | Daily export schema version for this dictionary entry. |

## Daily aggregation values

| Value | Meaning | Examples |
|---|---|---|
| `sum` | Daily total. | steps, active calories, nutrients |
| `duration_sum` | Total duration. | sleep, mindful minutes, workout minutes |
| `count` | Event/record count. | symptoms, mood entries, workouts, raw record count |
| `average` | Daily average. | heart rate, oxygen, respiratory rate |
| `minimum` / `maximum` | Daily extrema. | heart-rate/blood-oxygen min/max |
| `latest` | Latest value/provenance for the day. | weight, VO2 Max, capture status |
| `weighted_average` | Weighted, usually by workout duration. | workout average heart rate/power |
| `first_time` / `last_time` | First/last clock time. | sleep bedtime/wake |
| `list` | List/set-like data. | medications, dose events, workouts |
| `category_latest` | Latest categorical state. | menstrual flow, pregnancy tests |

Missing is not zero. Tools must follow `nullHandling` and report `days_counted`.

## Lossless diagnostic fields

Schema v6 frontmatter/Bases includes compact archive fields such as:

- `raw_capture_status`;
- `raw_record_count` and external-record count;
- query failure/warning counts;
- `raw_record_schema` and `raw_record_schema_version`.

These fields tell a summary consumer whether canonical capture was complete. They do not replace the archive query manifest. `partial`, `not_requested`, and `legacy_unavailable` must remain distinguishable.

## Correctness notes

- `stand_time_minutes` is summed Apple Stand Time duration. `stand_hours` counts distinct stood-hour category records.
- VO2 Max may be carried forward from the latest historical source measurement; its source UUID/start/end, carry-forward flag, and age fields must travel with the value.
- Vitamin/mineral units follow the reviewed HealthKit unit contract. Microgram nutrients such as vitamins A/B12/D/K, folate, biotin, selenium, chromium, and molybdenum use `mcg`; milligram nutrients remain `mg`.
- Blood-pressure summary averages/min/max remain projections. Actual paired correlations and component identity live in the canonical archive.
- `raw_record_count` can roll up as a count for diagnostics, but a roll-up is not a substitute for source records.

## Roll-up examples

### Totals

```yaml
steps_sum: 74231
steps_daily_average: 10604
steps_days_counted: 7
```

### Minimum

For `blood_oxygen_min`, period minimum is the minimum of daily minima, not their average.

### Latest and provenance

Inventory-like values use the latest daily value. VO2 provenance fields should be carried with the selected latest measurement; do not attach an export date to a historical measurement.

### Workout weighted averages

Workout averages prefer duration-weighted details. If only daily summaries are available, tools may use the documented fallback and must preserve `days_counted`.

### Lists/categories

Lists use union/value counts. Categories use latest plus histograms rather than invented numeric averages.

## Custom keys

If `active_calories` is renamed to `activeEnergyKcal`, the entry keeps both:

```json
{
  "key": "activeEnergyKcal",
  "canonicalKey": "active_calories",
  "unit": "kcal"
}
```

Use `key` to match the file and `canonicalKey` for cross-user logic.

## Guidance for parsers and AI tools

- Branch on schema v5/v6 during migration; do not relabel v5 files.
- Read the data dictionary before interpreting summary fields.
- Use `unit`, `dailyAggregation`, and `rollup` instead of guessing.
- Treat missing keys as missing, not zero.
- Read lossless diagnostics before asserting completeness.
- For exact source values/identity, use JSON archive or CSV canonical rows, not frontmatter.
- Preserve unknown canonical metadata tags and raw enum values.

## Limitations

- Roll-ups query daily summary snapshots for complete touched periods; they do not read existing vault files.
- Markdown/Bases and their dictionary intentionally do not expose every raw record.
- Current source archives are snapshots and contain no deletion tombstone history.
- Apple Health may backfill or recalculate data; re-export affected dates.

## Implementation notes

- `HealthMetricExportMapping.metricIdToFrontmatterKeys` maps metrics to summary keys.
- `HealthMetricDataDictionary.entries(using:)` resolves actual keys and schema v6 rules.
- `HealthMetricDataDictionary.unit(for:converter:)` provides canonical structured units.
- `HealthMetricRollupRule` encodes period semantics.
- `VaultManager.writeDataDictionary(...)` writes the shared dictionary.
- `ExportSchemaSignatureTests` fingerprints dictionary/output contracts; the historical v5 fixture remains preserved.
