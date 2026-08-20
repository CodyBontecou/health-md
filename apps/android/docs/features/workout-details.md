# Android Workout Detail Exports

Android enriches `WorkoutData` from Health Connect exercise sessions instead of exporting only type/start/duration. The JSON schema remains additive/backward-compatible: older consumers can ignore the newer keys.

## Exported when Health Connect provides matching data

- Session type, title/notes metadata, start time, end time, duration, and inferred indoor/outdoor status where Health Connect uses a distinct session type (treadmill, stationary bike, pool swim, open-water swim).
- Calories from `ActiveCaloriesBurnedRecord` records overlapping the workout window.
- Distance from overlapping `DistanceRecord` records.
- Elevation gain from `ElevationGainedRecord`; route altitude is used as a fallback when route data is available.
- Elevation loss derived from route altitude when Health Connect returns route data.
- Average/min/max heart rate from `HeartRateRecord` samples inside the session.
- Average/max speed and pace from `SpeedRecord` samples.
- Cycling cadence, steps cadence, average/max power from overlapping sample records.
- Laps from `ExerciseSessionRecord.laps`, including duration and distance when available.
- Splits derived from route distance when route points are available; otherwise lap-backed splits are emitted from Health Connect laps.
- Segments/repetitions from `ExerciseSessionRecord.segments`.
- Route access status (`data`, `consent_required`, or `no_data`) for every workout. Route points are exported only with granular data enabled.
- Routes granted through Health Connect's per-session consent flow during an interactive export run: a session reported `ConsentRequired` whose route the user granted is exported with route access `data` and its full route points, splits, and elevation fallbacks exactly like a natively returned route. Denied or skipped sessions keep `consent_required`.
- Stable metadata from `ExerciseSessionRecord.metadata` such as Health Connect id, data-origin package, client record id/version, recording method, device manufacturer/model, title, notes, and planned exercise session id.
- Granular workout samples in JSON/CSV/individual workout Markdown when granular export is enabled.

## Health Connect limitations vs HealthKit

Health Connect does not provide all iOS HealthKit workout details as first-class, session-linked fields. Android correlates separate records by time window, so values are best-effort when multiple sessions overlap or when source apps write distance/calorie data outside the session interval.

Not currently exported on Android:

- Arbitrary HealthKit-style metadata beyond Health Connect's typed metadata/title/notes fields.
- A dedicated indoor/outdoor metadata flag for generic walking/running/cycling sessions; Android only infers this for explicit treadmill/stationary/pool/open-water session types.
- Route points unless Health Connect returns `ExerciseRouteResult.Data` or the user grants the session's route through Health Connect's per-session consent flow. Interactive export runs from the app UI prompt for third-party sessions (bounded per run, most recent first); scheduled, automation, and direct CLI runs have no consent surface and keep reporting `consent_required`. Grants persist inside Health Connect, so a route granted once is returned as `data` by every later export.
- A standalone Health Connect elevation-loss record; descent is derived only when route altitude is accessible.
- Apple running dynamics such as stride length, ground contact time, and vertical oscillation.
- Apple Watch heart-rate recovery / AFib burden.

The export contract keeps missing values optional so devices and source apps with sparse workout data still produce simple workout entries.
