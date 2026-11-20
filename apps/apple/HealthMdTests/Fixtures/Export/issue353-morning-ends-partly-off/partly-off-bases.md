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
native_quantity_details:
  - {"metric":"heart_rate","sample":{"metadata":{"synthetic":"golden-heart"},"timestamp":"2026-03-14T23:55:00.000000000Z","value":61.5},"unit":"bpm"}

sleep_stage_details:
  - {"durationSeconds":600,"endDate":"2026-03-14T23:50:00.000000000Z","stage":"deep","startDate":"2026-03-14T23:40:00.000000000Z"}
  - {"durationSeconds":600,"endDate":"2026-03-15T00:00:00.000000000Z","stage":"rem","startDate":"2026-03-14T23:50:00.000000000Z"}

native_correlation_details:
  - {"metric":"blood_pressure","sample":{"diastolic":76,"endDate":"2026-03-14T23:56:40.000000000Z","systolic":118,"timestamp":"2026-03-14T23:56:40.000000000Z","unit":"mmHg"},"unit":"mmHg"}

native_workout_details:
  - {"metric":"workout","sample":{"avgHeartRate":150,"avgPaceFormatted":"6:00 \/km","avgPacePerKmFormatted":"6:00 \/km","avgPacePerMiFormatted":"9:39 \/mi","calories":300,"distance":5000,"distanceFormatted":"5.00 km","distanceKm":5,"distanceMi":3.1068559611866697,"duration":1800,"durationFormatted":"30m","elapsedDuration":1800,"endTimeISO":"2026-03-14T23:30:00.000000000Z","id":"00000000-0000-4000-8000-000000000354","speedKmh":10,"speedMph":6.2137119223733395,"sport":"running","startTime":"23:00","startTimeISO":"2026-03-14T23:00:00.000000000Z","type":"Running"}}

native_mindfulness_details:
  - {"metric":"state_of_mind","sample":{"associations":["Health"],"displayTime":"23:58","endDate":"2026-03-14T23:58:20.000000000Z","id":"00000000-0000-4000-8000-000000000353","kind":"Daily Mood","labels":["Calm"],"timestamp":"2026-03-14T23:58:20.000000000Z","valence":0.5,"valenceDescription":"Pleasant","valencePercent":75}}

---
