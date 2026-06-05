{
  "id": "cd6a3c4d",
  "title": "P2: Add rich workout detail parity",
  "tags": [
    "android",
    "parity",
    "p2",
    "workouts",
    "health-connect"
  ],
  "status": "closed",
  "created_at": "2026-06-05T14:39:14.469Z"
}

## Goal
Upgrade Android workouts from basic sessions to richer iOS-style workout exports.

## Current gap
Android `WorkoutData` only stores type/start/duration, with calories and distance currently `null` in `HealthConnectManager.fetchWorkouts()`. iOS exports workout-level HR, pace/speed, cadence, power, laps, splits, routes, and time series where available.

## Key files
- `app/src/main/java/com/healthmd/domain/model/HealthData.kt` (`WorkoutData`)
- `app/src/main/java/com/healthmd/data/health/HealthConnectManager.kt` (`fetchWorkouts`)
- `app/src/main/java/com/healthmd/data/export/IndividualEntryExporter.kt`
- `MarkdownExporter.kt`, `JsonExporter.kt`, `CsvExporter.kt`
- iOS docs: `docs/features/workout-details.md`

## Acceptance criteria
- Populate workout distance/calories where Health Connect supports per-session correlation.
- Add optional workout time-series samples: HR, speed/pace, cadence, power, elevation if available.
- Export details in JSON/CSV/Markdown and individual entry files.
- Preserve simple exports for devices without rich workout data.
- Document Health Connect limitations vs HealthKit.

Implemented rich workout detail parity:
- WorkoutData now includes calories, distance, elevation, HR, speed/pace, cadence, power, laps, segments, and optional granular samples.
- HealthConnectManager correlates exercise sessions with overlapping Health Connect records.
- JSON/CSV/Markdown and individual workout entry exports include rich details when available.
- Documented Health Connect limitations in `docs/features/workout-details.md`.

Validation: `./gradlew testDebugUnitTest` passes.
