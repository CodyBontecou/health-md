---
schema: healthmd.rollup_summary
schema_version: 11
type: health_rollup
rollup_period: range
period_id: "2026-10-31_to_2026-11-03"
title: "Range Health Summary — 2026-10-31_to_2026-11-03"
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
  sleep_total_hours: "hours"
rollup_metrics:
  sleep_total_hours:
    value: "8.25"
    unit: "hours"
    category: "Sleep"
    display_name: "Total Sleep"
    canonical_key: sleep_total_hours
    rule: sum
    days_counted: 1
    statistics:
      daily_average: "8.25"
      minimum: "8.25"
      maximum: "8.25"
---

# Range Health Summary — 2026-10-31_to_2026-11-03

Structured roll-up summary for Obsidian Bases. Query `rollup_metrics` and top-level period fields from the YAML frontmatter.
