---
schema: healthmd.rollup_summary
schema_version: 7
type: health_rollup
rollup_period: weekly
period_id: "2026-W28"
title: "Weekly Health Summary — 2026-W28"
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
  average_heart_rate: "bpm"
  heart_rate_max: "bpm"
  heart_rate_min: "bpm"
  sleep_bedtime: "time"
  sleep_total_hours: "hours"
  sleep_wake: "time"
  steps: "steps"
  vo2_max: "mL/kg/min"
  vo2_max_age_seconds: "seconds"
  vo2_max_carried_forward: "boolean"
  vo2_max_source_end: "datetime"
  vo2_max_source_start: "datetime"
  vo2_max_source_uuid: "uuid"
  weight_kg: "kg"
  workout_avg_heart_rate: "bpm"
  workout_calories: "kcal"
  workout_count: "count"
  workout_distance_km: "km"
  workout_distance_mi: "mi"
  workout_max_heart_rate: "bpm"
  workout_min_heart_rate: "bpm"
  workout_minutes: "min"
rollup_metrics:
  average_heart_rate:
    value: "73"
    unit: "bpm"
    category: "Heart"
    display_name: "Average Heart Rate"
    canonical_key: average_heart_rate
    rule: average
    days_counted: 2
    statistics:
      average_of_daily_values: "73"
      minimum_daily_value: "70"
      maximum_daily_value: "76"
      latest: "76"
      days_counted: "2"
    notes: "Average the exported daily aggregate values; recompute from granular samples in a future roll-up engine when those samples are available."
  heart_rate_max:
    value: "175"
    unit: "bpm"
    category: "Heart"
    display_name: "Maximum Heart Rate"
    canonical_key: heart_rate_max
    rule: maximum
    days_counted: 3
    statistics:
      maximum: "175"
      average_of_daily_values: "166.67"
      minimum_daily_value: "160"
      days_counted: "3"
    notes: "Use the maximum of exported daily maxima for the period maximum."
  heart_rate_min:
    value: "48"
    unit: "bpm"
    category: "Heart"
    display_name: "Minimum Heart Rate"
    canonical_key: heart_rate_min
    rule: minimum
    days_counted: 3
    statistics:
      minimum: "48"
      average_of_daily_values: "50"
      maximum_daily_value: "52"
      days_counted: "3"
    notes: "Use the minimum of exported daily minima for the period minimum."
  menstrual_flow:
    value: "light"
    unit: ""
    category: "Reproductive Health"
    display_name: "Menstrual Flow"
    canonical_key: menstrual_flow
    rule: histogram
    days_counted: 3
    statistics:
      latest: "light"
      value_counts: "light: 2, medium: 1"
      days_counted: "3"
    notes: "Keep the latest category value and counts for every category value seen in the period."
  sleep_bedtime:
    value: "22:30"
    unit: "time"
    category: "Sleep"
    display_name: "Bedtime"
    canonical_key: sleep_bedtime
    rule: time_of_day
    days_counted: 3
    statistics:
      earliest_time: "21:45"
      latest_time: "23:15"
      average_time_of_day: "22:30"
      days_counted: "3"
    notes: "Summarize the time-of-day values across days; keep dates separate from clock-time calculations."
  sleep_total_hours:
    value: "24"
    unit: "hours"
    category: "Sleep"
    display_name: "Total Sleep"
    canonical_key: sleep_total_hours
    rule: sum
    days_counted: 3
    statistics:
      sum: "24"
      daily_average: "8"
      minimum_daily_value: "7.75"
      maximum_daily_value: "8.25"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  sleep_wake:
    value: "06:30"
    unit: "time"
    category: "Sleep"
    display_name: "Wake Time"
    canonical_key: sleep_wake
    rule: time_of_day
    days_counted: 3
    statistics:
      earliest_time: "06:00"
      latest_time: "07:00"
      average_time_of_day: "06:30"
      days_counted: "3"
    notes: "Summarize the time-of-day values across days; keep dates separate from clock-time calculations."
  steps:
    value: "17,500"
    unit: "steps"
    category: "Activity"
    display_name: "Steps"
    canonical_key: steps
    rule: sum
    days_counted: 3
    statistics:
      sum: "17,500"
      daily_average: "5,833.33"
      minimum_daily_value: "4,000"
      maximum_daily_value: "7,500"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  vo2_max:
    value: "40.2"
    unit: "mL/kg/min"
    category: "Activity"
    display_name: "Cardio Fitness"
    canonical_key: vo2_max
    rule: latest
    days_counted: 2
    statistics:
      latest: "40.2"
      minimum_daily_value: "40.2"
      maximum_daily_value: "42.1"
      average_of_daily_values: "41.15"
      days_counted: "2"
    notes: "Use the latest daily value as the headline period value, with min/max/average for trend context."
  vo2_max_age_seconds:
    value: "172,800"
    unit: "seconds"
    category: "Activity"
    display_name: "Cardio Fitness"
    canonical_key: vo2_max_age_seconds
    rule: latest
    days_counted: 2
    statistics:
      latest: "172,800"
      minimum_daily_value: "0"
      maximum_daily_value: "172,800"
      average_of_daily_values: "86,400"
      days_counted: "2"
    notes: "Use the latest daily value as the headline period value, with min/max/average for trend context."
  vo2_max_carried_forward:
    value: "true"
    unit: "boolean"
    category: "Activity"
    display_name: "Cardio Fitness"
    canonical_key: vo2_max_carried_forward
    rule: latest
    days_counted: 2
    statistics:
      latest: "true"
      days_counted: "2"
    notes: "Keep the latest provenance value and report value counts across captured days."
  vo2_max_source_end:
    value: "2026-07-11T11:01:00.000000000Z"
    unit: "datetime"
    category: "Activity"
    display_name: "Cardio Fitness"
    canonical_key: vo2_max_source_end
    rule: latest
    days_counted: 2
    statistics:
      latest: "2026-07-11T11:01:00.000000000Z"
      days_counted: "2"
    notes: "Keep the latest provenance value and report value counts across captured days."
  vo2_max_source_start:
    value: "2026-07-11T11:00:00.000000000Z"
    unit: "datetime"
    category: "Activity"
    display_name: "Cardio Fitness"
    canonical_key: vo2_max_source_start
    rule: latest
    days_counted: 2
    statistics:
      latest: "2026-07-11T11:00:00.000000000Z"
      days_counted: "2"
    notes: "Keep the latest provenance value and report value counts across captured days."
  vo2_max_source_uuid:
    value: "00000000-0000-0000-0000-000000000011"
    unit: "uuid"
    category: "Activity"
    display_name: "Cardio Fitness"
    canonical_key: vo2_max_source_uuid
    rule: latest
    days_counted: 2
    statistics:
      latest: "00000000-0000-0000-0000-000000000011"
      days_counted: "2"
    notes: "Keep the latest provenance value and report value counts across captured days."
  weight_kg:
    value: "69.8"
    unit: "kg"
    category: "Body Measurements"
    display_name: "Weight"
    canonical_key: weight_kg
    rule: latest
    days_counted: 2
    statistics:
      latest: "69.8"
      minimum_daily_value: "69.8"
      maximum_daily_value: "70.4"
      average_of_daily_values: "70.1"
      days_counted: "2"
    notes: "Use the latest daily value as the headline period value, with min/max/average for trend context."
  workout_avg_heart_rate:
    value: "125.71"
    unit: "bpm"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_avg_heart_rate
    rule: weighted_average
    days_counted: 3
    statistics:
      weighted_average: "125.71"
      minimum_daily_value: "100"
      maximum_daily_value: "140"
      latest: "120"
      days_counted: "3"
    notes: "Daily workout values are duration-weighted. Period roll-ups should recompute from workout details when present; otherwise average daily values."
  workout_calories:
    value: "880"
    unit: "kcal"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_calories
    rule: sum
    days_counted: 3
    statistics:
      sum: "880"
      daily_average: "293.33"
      minimum_daily_value: "130"
      maximum_daily_value: "510"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workout_count:
    value: "3"
    unit: "count"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_count
    rule: sum
    days_counted: 3
    statistics:
      sum: "3"
      daily_average: "1"
      minimum_daily_value: "1"
      maximum_daily_value: "1"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workout_distance_km:
    value: "31.5"
    unit: "km"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_distance_km
    rule: sum
    days_counted: 3
    statistics:
      sum: "31.5"
      daily_average: "10.5"
      minimum_daily_value: "2.5"
      maximum_daily_value: "24"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workout_distance_mi:
    value: "19.57"
    unit: "mi"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_distance_mi
    rule: sum
    days_counted: 3
    statistics:
      sum: "19.57"
      daily_average: "6.52"
      minimum_daily_value: "1.55"
      maximum_daily_value: "14.91"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workout_max_heart_rate:
    value: "500"
    unit: "bpm"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_max_heart_rate
    rule: sum
    days_counted: 3
    statistics:
      sum: "500"
      daily_average: "166.67"
      minimum_daily_value: "160"
      maximum_daily_value: "175"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workout_min_heart_rate:
    value: "285"
    unit: "bpm"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_min_heart_rate
    rule: sum
    days_counted: 3
    statistics:
      sum: "285"
      daily_average: "95"
      minimum_daily_value: "90"
      maximum_daily_value: "100"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workout_minutes:
    value: "105"
    unit: "min"
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workout_minutes
    rule: sum
    days_counted: 3
    statistics:
      sum: "105"
      daily_average: "35"
      minimum_daily_value: "15"
      maximum_daily_value: "60"
      days_counted: "3"
    notes: "Sum the daily values in the period. Daily averages divide by days with data, not calendar days."
  workouts:
    value: "[cycling, running]"
    unit: ""
    category: "Workouts"
    display_name: "Workouts"
    canonical_key: workouts
    rule: union
    days_counted: 3
    statistics:
      union: "[cycling, running]"
      value_counts: "cycling: 1, running: 2"
      days_counted: "3"
    notes: "Merge list values across days and keep occurrence counts for each value."
---

# Weekly Health Summary — 2026-W28

Structured roll-up summary for Obsidian Bases. Query `rollup_metrics` and top-level period fields from the YAML frontmatter.
