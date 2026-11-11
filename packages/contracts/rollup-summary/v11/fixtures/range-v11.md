---
schema: healthmd.rollup_summary
schema_version: 11
type: health_rollup
rollup_period: range
period_id: 2026-10-31_to_2026-11-03
start_date: 2026-10-31
end_date: 2026-11-03
calendar_timezone: America/New_York
days_expected: 4
days_counted: 2
coverage_percent: 50
source_schema: healthmd.health_data
source_schema_version: 11
rollup_rules_version: 11
generated_at: 2026-11-04T12:00:00Z
schema_profile: apple-rollup-v11
source_schema_profile: apple-v11
time_context:
  calendar_timezone: America/New_York
  timestamp_timezone: UTC
  sleep_day_attribution: morning_ends
  sleep_owner_day_rule: session_end_date
  sleep_interval_clipping: none
source_dates:
  - 2026-11-01
  - 2026-11-02
units:
  sleep_total_hours: hours
---

# Range Health Summary — 2026-10-31_to_2026-11-03

Generated from 2 HealthKit daily aggregate snapshots in this range period.

## Coverage

- **Period:** 2026-10-31 → 2026-11-03
- **Days counted:** 2 / 4 (50%)
- **Missing days:** 2
- **Rule source:** `_healthmd_data_dictionary.json` schema v8
- **Source dates:** 2026-11-01, 2026-11-02

## Sleep

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Total Sleep | `sleep_total_hours` | 8.25 | hours | 1/4 | sum |

<details>
<summary>Sleep statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `sleep_total_hours` | daily_average | 8.25 |
| `sleep_total_hours` | minimum | 8.25 |
| `sleep_total_hours` | maximum | 8.25 |

</details>

## Roll-up notes

- Missing daily values are ignored and reported through the days-counted columns.
- Daily averages divide by days with data, not by calendar days.
- Weighted workout metrics use daily workout duration when available, then fall back to unweighted daily values.
- Summary files are derived artifacts and can be regenerated from HealthKit daily aggregates plus the data dictionary.
