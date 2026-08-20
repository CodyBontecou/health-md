# `healthmd.rollup_summary` v9

Status: public canonical contract
Source daily schema: `healthmd.health_data` v8
Roll-up rules version: 8

Version 9 replaces the window grammar for newly generated Apple roll-ups without changing daily v8 records or metric aggregation rules.

## Window authority

A v9 artifact has `rollup_period: range`. `start_date`, `end_date`, `period_id`, and `days_expected` come from the immutable requested civil range in the configured IANA timezone, never from successful captures. `period_id` is `<start_date>_to_<end_date>` and the inclusive range may contain at most 400 days.

`source_dates` lists distinct successfully captured owner dates, including successful empty snapshots. Query failures are absent. `days_counted` is the count of those source dates and `coverage_percent` is `days_counted / days_expected * 100`. Failed first or last days do not change the artifact identity. At least one summarized metric is required to emit an artifact.

## Versions

Every JSON, Markdown, Bases, and CSV artifact identifies:

- `schema: healthmd.rollup_summary`
- `schema_version: 9`
- `source_schema: healthmd.health_data`
- `source_schema_version: 8`
- `rollup_rules_version: 8`
- `rollup_period: range`

CSV carries these values as stable leading columns on every row.

## Metrics

Metric reduction rules are unchanged from daily dictionary/rules version 8. Entries whose roll-up rule is `none` or whose period list is empty are excluded. Provider-native WHOOP values therefore remain available in daily v8 records but never appear in v9 range summaries.

Historical weekly/monthly/yearly `healthmd.rollup_summary` v8 artifacts remain valid and are not relabeled.
