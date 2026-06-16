# Data Dictionary and Roll-up Rules

## Status

- **Docs status:** draft
- **Video priority:** low
- **Primary output:** `_healthmd_data_dictionary.json`
- **Source files:** `HealthMd/Shared/Export/HealthMetricsDictionary.swift`, `HealthMd/Shared/Export/ExportHelpers.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Health.md writes a data dictionary alongside your exports so people, scripts, Obsidian plugins, and AI assistants can understand every exported health field without guessing from the key name.

Starting with the current schema, `schema_version: 1`, the dictionary also documents how each field should be rolled up into weekly, monthly, or yearly summary files. This makes exported data self-describing: a tool can tell that `active_calories` should be summed, `blood_oxygen_min` should use the period minimum, `medication_count` should use the latest value, and `workout_avg_heart_rate` should be duration-weighted when workout details are available.

## Who it is for

- Obsidian users who want long-lived, queryable Apple Health archives.
- Users asking AI assistants to read Health.md exports years later.
- Developers building charts, roll-up summaries, importers, or validators on top of Health.md files.
- Anyone who customizes frontmatter field names but still wants a stable canonical mapping.

## Where to find it

After a successful export, Health.md writes the dictionary at the root of the Health.md export folder:

```text
Health/
  _healthmd_data_dictionary.json
  2026-06-14.md
  2026-06-14.json
  2026-06-14.csv
```

If format folders are enabled, it still lives at the shared Health.md folder root:

```text
Health/
  _healthmd_data_dictionary.json
  Markdown/
  Bases/
  JSON/
  CSV/
```

The file is rewritten with the current export settings, including your selected frontmatter key style and any custom field names.

## File shape

`_healthmd_data_dictionary.json` is a JSON array. Each object describes one exported frontmatter-compatible field.

```json
[
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
      "statistics": [
        "sum",
        "daily_average",
        "minimum_daily_value",
        "maximum_daily_value",
        "days_counted"
      ],
      "periods": ["weekly", "monthly", "yearly"],
      "preferredSource": "daily_frontmatter",
      "nullHandling": "ignore_missing_days_and_report_days_counted",
      "weightedBy": null,
      "notes": "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
    },
    "schemaVersion": 1
  }
]
```

## Entry fields

| Field | Meaning |
|---|---|
| `key` | The actual key written to frontmatter/Bases for the current settings. If you use camelCase or rename a field, this reflects that final output key. |
| `canonicalKey` | Health.md's stable snake_case key for the field. Use this when you need a durable identifier across user renames. |
| `metricId` | Internal Health.md metric ID, usually one Apple Health concept such as `active_energy`, `blood_oxygen`, or `workouts`. |
| `displayName` | Human-readable metric name. |
| `category` | Health.md category, such as `Activity`, `Heart`, `Vitals`, `Nutrition`, or `Workouts`. |
| `unit` | Unit for this exported key. Empty string means the value is categorical/text/list-like rather than numeric. |
| `healthKitIdentifier` | Apple HealthKit identifier when one exists. Some derived or workout fields may be `null`. |
| `metricType` | Source metric shape: `quantity`, `category`, or `workout`. |
| `aggregation` | Backward-compatible alias for `dailyAggregation`. |
| `dailyAggregation` | How the daily value is produced for this exact exported key. |
| `healthKitAggregation` | Broader aggregation declared by the source Health.md metric definition. Useful for provenance. |
| `rollup` | Rule object describing how weekly/monthly/yearly summaries should aggregate this key. |
| `schemaVersion` | Export schema version the dictionary entry follows. |

## Daily aggregation values

`dailyAggregation` describes the meaning of the value in a daily export.

| Value | Meaning | Example keys |
|---|---|---|
| `sum` | Daily value is a total for the day. | `steps`, `active_calories`, `protein_g` |
| `duration_sum` | Daily value is a duration total. | `sleep_total_hours`, `mindful_minutes`, `workout_minutes` |
| `count` | Daily value is a count of events or entries. | `symptom_headache`, `mood_entries`, `workout_count` |
| `average` | Daily value is an average. | `average_heart_rate`, `blood_oxygen`, `respiratory_rate_avg` |
| `minimum` | Daily value is a minimum. | `heart_rate_min`, `blood_oxygen_min` |
| `maximum` | Daily value is a maximum. | `heart_rate_max`, `blood_oxygen_max`, `underwater_depth_m` |
| `latest` | Daily value is the latest value for that day. | `weight_kg`, `vo2_max`, `medication_count` |
| `weighted_average` | Daily value is weighted, usually by workout duration. | `workout_avg_heart_rate`, `workout_avg_power` |
| `first_time` | Daily value is the first clock time. | `sleep_bedtime` |
| `last_time` | Daily value is the last clock time. | `sleep_wake` |
| `list` | Daily value is a list/set-like property. | `mood_labels`, `medications`, `workouts` |
| `category_latest` | Daily value is the latest categorical state. | `menstrual_flow`, `ovulation_test`, `cervical_mucus` |

## Roll-up rule object

The `rollup` object tells a summary generator how to combine daily files into weekly, monthly, and yearly summaries.

| Field | Meaning |
|---|---|
| `primary` | Headline operation for the period, such as `sum`, `average`, `minimum`, `maximum`, `latest`, `weighted_average`, `union`, or `histogram`. |
| `statistics` | Extra fields a summary should preserve, such as `days_counted`, `daily_average`, `latest`, or `value_counts`. |
| `periods` | Periods this rule applies to. Currently `weekly`, `monthly`, and `yearly`. |
| `preferredSource` | Best source to use. Most fields use `daily_frontmatter`; workout averages prefer `workout_details_when_available`. |
| `nullHandling` | How to treat missing daily values. Current rule: ignore missing days and report how many days were counted. |
| `weightedBy` | Weighting dimension when applicable, such as `duration`. Otherwise `null`. |
| `notes` | Human-readable caveat for tools and AI assistants. |

## Roll-up examples

### Sum totals

For cumulative fields like `steps`, `active_calories`, and nutrition totals:

```json
{
  "canonicalKey": "steps",
  "dailyAggregation": "sum",
  "rollup": {
    "primary": "sum",
    "statistics": ["sum", "daily_average", "minimum_daily_value", "maximum_daily_value", "days_counted"]
  }
}
```

A weekly summary can safely produce:

```yaml
steps_sum: 74231
steps_daily_average: 10604
steps_days_counted: 7
```

### Min/max fields

For fields that are already daily extrema:

```json
{
  "canonicalKey": "blood_oxygen_min",
  "dailyAggregation": "minimum",
  "rollup": {
    "primary": "minimum",
    "statistics": ["minimum", "average_of_daily_values", "maximum_daily_value", "days_counted"]
  }
}
```

The period minimum should be the minimum of the daily minima, not an average.

### Latest inventory-like fields

Medication inventory counts use the latest value as the headline period value:

```json
{
  "canonicalKey": "medication_count",
  "dailyAggregation": "latest",
  "rollup": {
    "primary": "latest",
    "statistics": ["latest", "minimum_daily_value", "maximum_daily_value", "average_of_daily_values", "days_counted"]
  }
}
```

This answers “how many medications were active at the end of the month?” while still preserving trend context.

### Workout weighted averages

Workout average fields should be duration-weighted when workout details are present:

```json
{
  "canonicalKey": "workout_avg_heart_rate",
  "dailyAggregation": "weighted_average",
  "rollup": {
    "primary": "weighted_average",
    "preferredSource": "workout_details_when_available",
    "weightedBy": "duration",
    "statistics": ["weighted_average", "minimum_daily_value", "maximum_daily_value", "latest", "days_counted"]
  }
}
```

If a future summary generator has workout detail rows, it should recompute from those workout durations. If it only has daily frontmatter, it can fall back to averaging the daily values and should preserve `days_counted`.

### Lists and categories

List-like fields use unions and value counts:

```json
{
  "canonicalKey": "workouts",
  "dailyAggregation": "list",
  "rollup": {
    "primary": "union",
    "statistics": ["union", "value_counts", "days_counted"]
  }
}
```

Categorical fields use histograms:

```json
{
  "canonicalKey": "menstrual_flow",
  "dailyAggregation": "category_latest",
  "rollup": {
    "primary": "histogram",
    "statistics": ["latest", "value_counts", "days_counted"]
  }
}
```

A period summary should preserve counts like “light: 3 days, medium: 2 days” instead of inventing a numeric average.

## Custom field names

If you rename `active_calories` to `activeEnergyKcal`, the dictionary keeps both the final output key and the canonical key:

```json
{
  "key": "activeEnergyKcal",
  "canonicalKey": "active_calories",
  "unit": "kcal"
}
```

Use `key` to match the user's exported frontmatter. Use `canonicalKey` to recognize the field across different users, key styles, or future exports.

## Tips for AI assistants and scripts

- Read `_healthmd_data_dictionary.json` before interpreting exported notes.
- Match daily frontmatter by `key`, but use `canonicalKey` for stable internal logic.
- Treat missing daily keys as missing data, not zero, unless the roll-up rule says otherwise.
- Always report `days_counted` or equivalent provenance in summary files.
- Prefer `rollup.primary` for the headline value and `rollup.statistics` for additional context.
- Use `unit` instead of guessing from the field name.
- Preserve `schemaVersion` in any derived files so future tools know which rules were used.

## Limitations

- When roll-up summaries are enabled, Health.md creates weekly/monthly/yearly files for every selected export format. The selected export dates determine which roll-up windows are refreshed; Health.md then queries daily aggregate snapshots for the full touched week/month/year instead of reading previously generated vault files.
- Some rich statistics require granular samples or workout details. When only daily frontmatter is available, tools should follow the fallback described in `rollup.notes`.
- Apple Health may backfill or recalculate past data. Re-export affected days before regenerating summaries.

## Implementation notes

- `HealthMetricExportMapping.metricIdToFrontmatterKeys` defines which frontmatter keys each metric can produce.
- `HealthMetricDataDictionary.entries(using:)` resolves the user's final output keys and emits dictionary entries.
- `HealthMetricDataDictionary.unit(for:converter:)` provides canonical structured units.
- `HealthMetricRollupRule` encodes the period summary semantics.
- `VaultManager.writeDataDictionary(...)` writes `_healthmd_data_dictionary.json` at the shared Health.md folder root, even when daily exports are organized into Markdown/, Bases/, JSON/, and CSV/ format folders.
- `ExportSchemaSignatureTests` fingerprints the dictionary so schema changes require an intentional `HealthMdExportSchema.version` bump.
