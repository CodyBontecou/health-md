---
schema: healthmd.health_data
schema_version: 8
time_context:
  calendar_timezone: UTC
  timestamp_timezone: UTC
date: 2026-03-15
type: health-data
raw_capture_status: not_requested
raw_record_count: 0
raw_query_failure_count: 0
raw_integrity_warning_count: 0
whoop_capture_status: complete
whoop_cycle_strain_score: 12.7
whoop_cycle_energy_kilojoules: 8420.0
whoop_cycle_average_heart_rate_bpm: 68.0
whoop_cycle_max_heart_rate_bpm: 174.0
whoop_recovery_score_percent: 82.0
whoop_resting_heart_rate_bpm: 49.0
whoop_hrv_rmssd_ms: 54.3
whoop_spo2_percent: 97.2
whoop_skin_temperature_celsius: 33.4
whoop_total_sleep_milliseconds: 24300750
whoop_total_in_bed_milliseconds: 27000000
whoop_awake_milliseconds: 2399250
whoop_light_sleep_milliseconds: 12600125
whoop_slow_wave_sleep_milliseconds: 5400250
whoop_rem_sleep_milliseconds: 6300375
whoop_recent_nap_adjustment_milliseconds: -900000
whoop_respiratory_rate_breaths_per_minute: 14.2
whoop_sleep_performance_percent: 91.0
whoop_sleep_consistency_percent: 88.0
whoop_sleep_efficiency_percent: 90.0
whoop_workout_sport_name: running
whoop_workout_strain_score: 10.4
whoop_workout_average_heart_rate_bpm: 146.0
whoop_workout_max_heart_rate_bpm: 174.0
whoop_workout_energy_kilojoules: 2500.0
whoop_workout_distance_meters: 10000.0
whoop_body_height_meters: 1.82
whoop_body_weight_kilograms: 78.4
whoop_body_max_heart_rate_bpm: 190.0
steps: 1
units:
  raw_integrity_warning_count: warnings
  raw_query_failure_count: queries
  raw_record_count: records
  steps: steps
  whoop_awake_milliseconds: ms
  whoop_body_height_meters: m
  whoop_body_max_heart_rate_bpm: bpm
  whoop_body_weight_kilograms: kg
  whoop_capture_status: status
  whoop_cycle_average_heart_rate_bpm: bpm
  whoop_cycle_energy_kilojoules: kJ
  whoop_cycle_max_heart_rate_bpm: bpm
  whoop_cycle_strain_score: score
  whoop_hrv_rmssd_ms: ms
  whoop_light_sleep_milliseconds: ms
  whoop_recent_nap_adjustment_milliseconds: ms
  whoop_recovery_score_percent: percent
  whoop_rem_sleep_milliseconds: ms
  whoop_respiratory_rate_breaths_per_minute: breaths/min
  whoop_resting_heart_rate_bpm: bpm
  whoop_skin_temperature_celsius: °C
  whoop_sleep_consistency_percent: percent
  whoop_sleep_efficiency_percent: percent
  whoop_sleep_performance_percent: percent
  whoop_slow_wave_sleep_milliseconds: ms
  whoop_spo2_percent: percent
  whoop_total_in_bed_milliseconds: ms
  whoop_total_sleep_milliseconds: ms
  whoop_workout_average_heart_rate_bpm: bpm
  whoop_workout_distance_meters: m
  whoop_workout_energy_kilojoules: kJ
  whoop_workout_max_heart_rate_bpm: bpm
  whoop_workout_strain_score: score
---

# Health Data — 2026-03-15

1 steps

## Activity

- **Steps:** 1


## WHOOP

- **Capture:** Complete
- **Recovery score:** 82.0%
- **HRV (RMSSD):** 54.3 ms
- **Resting heart rate:** 49.0 bpm

| Cycle ID | Start | End | Strain | Energy (kJ) | Avg HR | Max HR |
|---|---|---|---:|---:|---:|---:|
| 101 | 2026-03-15T07:00:00.000000000Z | 2026-03-15T17:30:00.000000000Z | 12.7 | 8420.0 | 68.0 | 174.0 |

| Cycle ID | Sleep ID | Recovery | HRV (RMSSD) | Resting HR | SpO₂ | Skin temp (°C) |
|---|---|---:|---:|---:|---:|---:|
| 101 | 202 | 82.0 | 54.3 | 49.0 | 97.2 | 33.4 |

| Sleep ID | Cycle ID | Start | End | Nap | Total sleep (ms) | In bed (ms) | Nap adjustment (ms) |
|---|---|---|---|---|---:|---:|---:|
| 202 | 101 | 2026-03-15T07:30:00.000000000Z | 2026-03-15T15:00:00.000000000Z | No | 24300750 | 27000000 | -900000 |

| Workout ID | Sport | Start | End | Strain | Avg HR | Max HR | Distance (m) |
|---|---|---|---|---:|---:|---:|---:|
| 303 | running | 2026-03-15T16:00:00.000000000Z | 2026-03-15T17:00:00.000000000Z | 10.4 | 146.0 | 174.0 | 10000.0 |

**Current profile snapshot**
- Height: 1.82 m
- Weight: 78.4 kg
- Maximum heart rate: 190.0 bpm

| Resource | Status | Records | Details |
|---|---|---:|---|
| cycles | success | 1 |  |
| recovery | success | 1 |  |
| sleep | success | 1 |  |
| workouts | success | 1 |  |
| body | success | 1 |  |
