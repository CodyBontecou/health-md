---
schema: healthmd.health_data
schema_version: 11
schema_profile: apple-v11
time_context:
  calendar_timezone: GMT
  timestamp_timezone: UTC
  sleep_day_attribution: morning_ends
  sleep_owner_day_rule: session_end_date
  sleep_interval_clipping: none
date: 2026-03-15
type: health-data
raw_capture_status: not_requested
raw_record_count: 0
raw_query_failure_count: 0
raw_integrity_warning_count: 0
average_heart_rate: 61.5
blood_pressure_diastolic: 76
blood_pressure_diastolic_avg: 76
blood_pressure_systolic: 118
blood_pressure_systolic_avg: 118
mood_associations: [health]
mood_entries: 1
sleep_deep_hours: 0.1666666666666667
sleep_rem_hours: 0.1666666666666667
workout_avg_heart_rate: 150
workout_count: 1
workout_distance_km: 5
workout_distance_mi: 3.10685596118667
workout_minutes: 30
workouts: [running]
units:
  average_heart_rate: bpm
  blood_pressure_diastolic: mmHg
  blood_pressure_diastolic_avg: mmHg
  blood_pressure_systolic: mmHg
  blood_pressure_systolic_avg: mmHg
  mood_entries: entries
  raw_integrity_warning_count: warnings
  raw_query_failure_count: queries
  raw_record_count: records
  sleep_deep_hours: hours
  sleep_rem_hours: hours
  workout_avg_heart_rate: bpm
  workout_count: count
  workout_distance_km: km
  workout_distance_mi: mi
  workout_minutes: min
---

# Health Data — 2026-03-15

15 metrics recorded.

## Sleep
- **Deep Sleep:** 0.17 hours
- **REM Sleep:** 0.17 hours

## Heart
- **Average Heart Rate:** 61 bpm

## Vitals
- **Blood Pressure (Systolic):** 118 mmHg
- **Blood Pressure (Systolic):** 118 mmHg
- **Blood Pressure (Diastolic):** 76 mmHg
- **Blood Pressure (Diastolic):** 76 mmHg

## Mindfulness
- **Mood Entries:** 1 entries
- **Mood Entries:** [health]

## Workouts
- **Workout Count:** 1 count
- **Workout Minutes:** 30 min
- **Workout Distance Km:** 5.00 km
- **Workout Distance Mi:** 3.11 mi
- **Workouts:** [running]
- **Workout Avg Heart Rate:** 150 bpm

## Heart Rate Sample Details

| Timestamp (UTC) | Value | Unit |
|---|---|---|
| 2026-03-14T23:55:00.000000000Z | 61.5 | bpm |

## Sleep Stage Details

| Start (UTC) | End (UTC) | Stage | Native Record (JSON) |
|---|---|---|---|
| 2026-03-14T23:40:00.000000000Z | 2026-03-14T23:50:00.000000000Z | deep | `{"durationSeconds":600,"endDate":"2026-03-14T23:50:00.000000000Z","stage":"deep","startDate":"2026-03-14T23:40:00.000000000Z"}` |
| 2026-03-14T23:50:00.000000000Z | 2026-03-15T00:00:00.000000000Z | rem | `{"durationSeconds":600,"endDate":"2026-03-15T00:00:00.000000000Z","stage":"rem","startDate":"2026-03-14T23:50:00.000000000Z"}` |

## Blood Pressure Correlation Details

| Timestamp (UTC) | End (UTC) | Systolic | Diastolic | Unit |
|---|---|---|---|---|
| 2026-03-14T23:56:40.000000000Z | 2026-03-14T23:56:40.000000000Z | 118.0 | 76.0 | mmHg |

## Workout Details

| Native Record (JSON) |
|---|
| `{"metric":"workout","sample":{"avgHeartRate":150,"avgPaceFormatted":"6:00 \/km","avgPacePerKmFormatted":"6:00 \/km","avgPacePerMiFormatted":"9:39 \/mi","calories":300,"distance":5000,"distanceFormatted":"5.00 km","distanceKm":5,"distanceMi":3.1068559611866697,"duration":1800,"durationFormatted":"30m","elapsedDuration":1800,"endTimeISO":"2026-03-14T23:30:00.000000000Z","id":"00000000-0000-4000-8000-000000000354","speedKmh":10,"speedMph":6.2137119223733395,"sport":"running","startTime":"23:00","startTimeISO":"2026-03-14T23:00:00.000000000Z","type":"Running"}}` |

## State of Mind Details

| Native Record (JSON) |
|---|
| `{"metric":"state_of_mind","sample":{"associations":["Health"],"displayTime":"23:58","endDate":"2026-03-14T23:58:20.000000000Z","id":"00000000-0000-4000-8000-000000000353","kind":"Daily Mood","labels":["Calm"],"timestamp":"2026-03-14T23:58:20.000000000Z","valence":0.5,"valenceDescription":"Pleasant","valencePercent":75}}` |
