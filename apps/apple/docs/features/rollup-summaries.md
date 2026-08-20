# Range summary and historical roll-ups

Health.md can generate one range summary covering exactly the requested civil dates. The range grammar is the independently versioned public contract `healthmd.rollup_summary` v9; daily Apple exports remain `healthmd.health_data` v8.

## User promise

When **Range summary** is enabled, Health.md writes one derived file per selected export format:

```text
Health/
  Rollups/
    Range/2026-03-10_to_2026-03-15.md
    Range/2026-03-10_to_2026-03-15.json
    Range/2026-03-10_to_2026-03-15.csv
    Range/2026-03-10_to_2026-03-15-bases.md
```

With **Organize by File Type**, the format folder precedes `Range`. Range files are derived from Apple-v8 daily aggregate facts and do not embed the canonical HealthKit archive.

The requested IANA calendar timezone and inclusive start/end dates are frozen before capture. `period_id`, `start_date`, `end_date`, and `days_expected` never shrink when the first or last query fails. `source_dates` contains distinct successfully captured owner dates, including successful empty days; `days_counted` and coverage therefore expose missing captures rather than changing artifact identity. Missing edge days never suppress the artifact when captured metrics remain. A range is limited to 10,000 cumulative owner dates (about 27 years), while capture and render batches retain their smaller bounded limits.

## Contract identity

Every new JSON, CSV, Markdown, and Obsidian Bases range artifact identifies:

- `schema: healthmd.rollup_summary`
- `schema_version: 9`
- `source_schema: healthmd.health_data`
- `source_schema_version: 8`
- `rollup_rules_version: 8`
- `rollup_period: range`

CSV carries these values in stable leading columns on every row. Daily JSON, CSV, Markdown, and Bases outputs remain Apple v8 and are not altered by enabling a range summary. Provider-native WHOOP facts remain available in daily v8 records but have no roll-up rule and are excluded from range v9.

The normative contract and reviewed synthetic fixtures are under `packages/contracts/rollup-summary/v9`.

## Settings and migration

Range summary is opt-in. **Range summary only** skips daily files and daily side effects while still capturing the requested dates needed for the summary.

On settings migration, a previously enabled weekly, monthly, or yearly preference opts into the new range-summary setting using OR semantics. An explicitly stored new `false` value remains authoritative, and migrated legacy keys are removed. New durable settings snapshots encode only `generateRangeSummary`.

Historical weekly, monthly, and yearly `healthmd.rollup_summary` v8 artifacts remain valid and readable. Their calendar identifiers and bytes are not relabeled or regenerated as range v9. Semantic-input v1 calendar-period fixtures likewise remain byte-compatible revision-1 fixtures; a range operation is explicitly gated to semantic-input v1, Apple-v8 semantic profile revision 2, one `range` period, and immutable `rollup_range` bounds. Apple range planning rejects a packaged core without the range capability.

## Aggregation rules

Range v9 changes only the window grammar. Metric rules stay at Apple roll-up rules version 8:

| Daily rule | Range behavior |
|---|---|
| `sum`, `duration_sum`, `count` | Sum daily values and retain daily statistics. |
| `average` | Average exported daily aggregate values. |
| `weighted_average` | Use workout duration when available, otherwise use daily averages. |
| `minimum` / `maximum` | Reduce daily minima or maxima. |
| `latest` | Select the latest daily value, including a lower later VO2 Max. |
| `list` | Union values and count occurrences. |
| `category_latest` | Retain the latest value and value counts. |
| `first_time` / `last_time` | Reduce civil clock-time values. |

Missing metric values are ignored for that metric and are never converted to zero. Per-metric `days_counted` reports only dates containing that metric.

## Preview and references

Export Preview shows one **Range summary** section per selected format. The generated data-dictionary and roll-up reference includes complete production JSON, CSV, Markdown, and Bases examples and is checked by `make check-export-docs`.
