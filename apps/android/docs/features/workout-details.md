# Android Workout Detail Exports

Android now enriches `WorkoutData` from Health Connect exercise sessions instead of exporting only type/start/duration.

## Exported when Health Connect provides matching data

- Session type, start time, duration.
- Calories from `ActiveCaloriesBurnedRecord` records overlapping the workout window.
- Distance from overlapping `DistanceRecord` records.
- Elevation from overlapping `ElevationGainedRecord` records.
- Average/min/max heart rate from `HeartRateRecord` samples inside the session.
- Average/max speed and pace from `SpeedRecord` samples.
- Cycling cadence, steps cadence, average/max power from overlapping sample records.
- Laps from `ExerciseSessionRecord.laps`.
- Segments/repetitions from `ExerciseSessionRecord.segments`.
- Granular workout samples in JSON/CSV/individual workout Markdown when granular export is enabled.

## Health Connect limitations vs HealthKit

Health Connect 1.1.0-beta02 does not provide all iOS HealthKit workout details as first-class, session-linked fields. Android correlates separate records by time window, so values are best-effort when multiple sessions overlap or when source apps write distance/calorie data outside the session interval.

Not currently exported on Android:

- Workout routes (route result metadata exists, but route payload access is not wired here).
- Apple running dynamics such as ground contact time, vertical oscillation, and stride length.
- Apple Watch heart-rate recovery / AFib burden.

The export contract keeps missing values optional so devices and source apps with sparse workout data still produce simple workout entries.
