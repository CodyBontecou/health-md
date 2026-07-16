---
schema: healthmd.rollup_summary
schema_version: 7
type: health_rollup
rollup_period: weekly
period_id: 2026-W28
start_date: 2026-07-06
end_date: 2026-07-12
days_expected: 7
days_counted: 3
coverage_percent: 42.86
source_schema: healthmd.health_data
source_schema_version: 7
rollup_rules_version: 7
generated_at: 2026-07-13T12:00:00Z
source_dates:
  - 2026-07-06
  - 2026-07-08
  - 2026-07-11
units:
  average_heart_rate: bpm
  heart_rate_max: bpm
  heart_rate_min: bpm
  sleep_bedtime: time
  sleep_total_hours: hours
  sleep_wake: time
  steps: steps
  vo2_max: mL/kg/min
  vo2_max_age_seconds: seconds
  vo2_max_carried_forward: boolean
  vo2_max_source_end: datetime
  vo2_max_source_start: datetime
  vo2_max_source_uuid: uuid
  weight_kg: kg
  workout_avg_heart_rate: bpm
  workout_calories: kcal
  workout_count: count
  workout_distance_km: km
  workout_distance_mi: mi
  workout_max_heart_rate: bpm
  workout_min_heart_rate: bpm
  workout_minutes: min
---

# Weekly Health Summary — 2026-W28

Generated from 3 HealthKit daily aggregate snapshots in this weekly period.

## Coverage

- **Period:** 2026-07-06 → 2026-07-12
- **Days counted:** 3 / 7 (42.86%)
- **Missing days:** 4
- **Rule source:** `_healthmd_data_dictionary.json` schema v7
- **Source dates:** 2026-07-06, 2026-07-08, 2026-07-11

## Activity

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Cardio Fitness | `vo2_max` | 40.2 | mL/kg/min | 2/7 | latest |
| Cardio Fitness | `vo2_max_age_seconds` | 172,800 | seconds | 2/7 | latest |
| Cardio Fitness | `vo2_max_carried_forward` | true | boolean | 2/7 | latest |
| Cardio Fitness | `vo2_max_source_end` | 2026-07-11T11:01:00.000000000Z | datetime | 2/7 | latest |
| Cardio Fitness | `vo2_max_source_start` | 2026-07-11T11:00:00.000000000Z | datetime | 2/7 | latest |
| Cardio Fitness | `vo2_max_source_uuid` | 00000000-0000-0000-0000-000000000011 | uuid | 2/7 | latest |
| Steps | `steps` | 17,500 | steps | 3/7 | sum |

<details>
<summary>Activity statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `vo2_max` | latest | 40.2 |
| `vo2_max` | minimum_daily_value | 40.2 |
| `vo2_max` | maximum_daily_value | 42.1 |
| `vo2_max` | average_of_daily_values | 41.15 |
| `vo2_max` | days_counted | 2 |
| `vo2_max_age_seconds` | latest | 172,800 |
| `vo2_max_age_seconds` | minimum_daily_value | 0 |
| `vo2_max_age_seconds` | maximum_daily_value | 172,800 |
| `vo2_max_age_seconds` | average_of_daily_values | 86,400 |
| `vo2_max_age_seconds` | days_counted | 2 |
| `vo2_max_carried_forward` | latest | true |
| `vo2_max_carried_forward` | days_counted | 2 |
| `vo2_max_source_end` | latest | 2026-07-11T11:01:00.000000000Z |
| `vo2_max_source_end` | days_counted | 2 |
| `vo2_max_source_start` | latest | 2026-07-11T11:00:00.000000000Z |
| `vo2_max_source_start` | days_counted | 2 |
| `vo2_max_source_uuid` | latest | 00000000-0000-0000-0000-000000000011 |
| `vo2_max_source_uuid` | days_counted | 2 |
| `steps` | sum | 17,500 |
| `steps` | daily_average | 5,833.33 |
| `steps` | minimum_daily_value | 4,000 |
| `steps` | maximum_daily_value | 7,500 |
| `steps` | days_counted | 3 |

</details>

## Body Measurements

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Weight | `weight_kg` | 69.8 | kg | 2/7 | latest |

<details>
<summary>Body Measurements statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `weight_kg` | latest | 69.8 |
| `weight_kg` | minimum_daily_value | 69.8 |
| `weight_kg` | maximum_daily_value | 70.4 |
| `weight_kg` | average_of_daily_values | 70.1 |
| `weight_kg` | days_counted | 2 |

</details>

## Heart

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Average Heart Rate | `average_heart_rate` | 73 | bpm | 2/7 | average |
| Maximum Heart Rate | `heart_rate_max` | 175 | bpm | 3/7 | maximum |
| Minimum Heart Rate | `heart_rate_min` | 48 | bpm | 3/7 | minimum |

<details>
<summary>Heart statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `average_heart_rate` | average_of_daily_values | 73 |
| `average_heart_rate` | minimum_daily_value | 70 |
| `average_heart_rate` | maximum_daily_value | 76 |
| `average_heart_rate` | latest | 76 |
| `average_heart_rate` | days_counted | 2 |
| `heart_rate_max` | maximum | 175 |
| `heart_rate_max` | average_of_daily_values | 166.67 |
| `heart_rate_max` | minimum_daily_value | 160 |
| `heart_rate_max` | days_counted | 3 |
| `heart_rate_min` | minimum | 48 |
| `heart_rate_min` | average_of_daily_values | 50 |
| `heart_rate_min` | maximum_daily_value | 52 |
| `heart_rate_min` | days_counted | 3 |

</details>

## Reproductive Health

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Menstrual Flow | `menstrual_flow` | light |  | 3/7 | histogram |

<details>
<summary>Reproductive Health statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `menstrual_flow` | latest | light |
| `menstrual_flow` | value_counts | light: 2, medium: 1 |
| `menstrual_flow` | days_counted | 3 |

</details>

## Sleep

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Bedtime | `sleep_bedtime` | 22:30 | time | 3/7 | time_of_day |
| Total Sleep | `sleep_total_hours` | 24 | hours | 3/7 | sum |
| Wake Time | `sleep_wake` | 06:30 | time | 3/7 | time_of_day |

<details>
<summary>Sleep statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `sleep_bedtime` | earliest_time | 21:45 |
| `sleep_bedtime` | latest_time | 23:15 |
| `sleep_bedtime` | average_time_of_day | 22:30 |
| `sleep_bedtime` | days_counted | 3 |
| `sleep_total_hours` | sum | 24 |
| `sleep_total_hours` | daily_average | 8 |
| `sleep_total_hours` | minimum_daily_value | 7.75 |
| `sleep_total_hours` | maximum_daily_value | 8.25 |
| `sleep_total_hours` | days_counted | 3 |
| `sleep_wake` | earliest_time | 06:00 |
| `sleep_wake` | latest_time | 07:00 |
| `sleep_wake` | average_time_of_day | 06:30 |
| `sleep_wake` | days_counted | 3 |

</details>

## Workouts

| Metric | Key | Value | Unit | Days | Rule |
|---|---:|---:|---|---:|---|
| Workouts | `workout_avg_heart_rate` | 125.71 | bpm | 3/7 | weighted_average |
| Workouts | `workout_calories` | 880 | kcal | 3/7 | sum |
| Workouts | `workout_count` | 3 | count | 3/7 | sum |
| Workouts | `workout_distance_km` | 31.5 | km | 3/7 | sum |
| Workouts | `workout_distance_mi` | 19.57 | mi | 3/7 | sum |
| Workouts | `workout_max_heart_rate` | 500 | bpm | 3/7 | sum |
| Workouts | `workout_min_heart_rate` | 285 | bpm | 3/7 | sum |
| Workouts | `workout_minutes` | 105 | min | 3/7 | sum |
| Workouts | `workouts` | [cycling, running] |  | 3/7 | union |

<details>
<summary>Workouts statistics</summary>

| Key | Statistic | Value |
|---|---:|---:|
| `workout_avg_heart_rate` | weighted_average | 125.71 |
| `workout_avg_heart_rate` | minimum_daily_value | 100 |
| `workout_avg_heart_rate` | maximum_daily_value | 140 |
| `workout_avg_heart_rate` | latest | 120 |
| `workout_avg_heart_rate` | days_counted | 3 |
| `workout_calories` | sum | 880 |
| `workout_calories` | daily_average | 293.33 |
| `workout_calories` | minimum_daily_value | 130 |
| `workout_calories` | maximum_daily_value | 510 |
| `workout_calories` | days_counted | 3 |
| `workout_count` | sum | 3 |
| `workout_count` | daily_average | 1 |
| `workout_count` | minimum_daily_value | 1 |
| `workout_count` | maximum_daily_value | 1 |
| `workout_count` | days_counted | 3 |
| `workout_distance_km` | sum | 31.5 |
| `workout_distance_km` | daily_average | 10.5 |
| `workout_distance_km` | minimum_daily_value | 2.5 |
| `workout_distance_km` | maximum_daily_value | 24 |
| `workout_distance_km` | days_counted | 3 |
| `workout_distance_mi` | sum | 19.57 |
| `workout_distance_mi` | daily_average | 6.52 |
| `workout_distance_mi` | minimum_daily_value | 1.55 |
| `workout_distance_mi` | maximum_daily_value | 14.91 |
| `workout_distance_mi` | days_counted | 3 |
| `workout_max_heart_rate` | sum | 500 |
| `workout_max_heart_rate` | daily_average | 166.67 |
| `workout_max_heart_rate` | minimum_daily_value | 160 |
| `workout_max_heart_rate` | maximum_daily_value | 175 |
| `workout_max_heart_rate` | days_counted | 3 |
| `workout_min_heart_rate` | sum | 285 |
| `workout_min_heart_rate` | daily_average | 95 |
| `workout_min_heart_rate` | minimum_daily_value | 90 |
| `workout_min_heart_rate` | maximum_daily_value | 100 |
| `workout_min_heart_rate` | days_counted | 3 |
| `workout_minutes` | sum | 105 |
| `workout_minutes` | daily_average | 35 |
| `workout_minutes` | minimum_daily_value | 15 |
| `workout_minutes` | maximum_daily_value | 60 |
| `workout_minutes` | days_counted | 3 |
| `workouts` | union | [cycling, running] |
| `workouts` | value_counts | cycling: 1, running: 2 |
| `workouts` | days_counted | 3 |

</details>

## Roll-up notes

- Missing daily values are ignored and reported through the days-counted columns.
- Daily averages divide by days with data, not by calendar days.
- Weighted workout metrics use daily workout duration when available, then fall back to unweighted daily values.
- Summary files are derived artifacts and can be regenerated from HealthKit daily aggregates plus the data dictionary.
