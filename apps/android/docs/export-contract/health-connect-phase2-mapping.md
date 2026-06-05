# Android Phase 2 Health Connect Mapping

This table records the Phase 2 Android parity decision for iOS metrics that were missing from the Android catalog. Health Connect API surface audited: `androidx.health.connect:connect-client:1.1.0-beta02`.

| iOS / contract metric | Health Connect API | Android support | Notes |
|---|---|---:|---|
| `swimmingDistance` / `swimming_m` | `ExerciseSessionRecord` + overlapping `DistanceRecord` | ✅ | Exported as `activity.swimmingDistance`, frontmatter `swimming_m`, CSV `Activity,Swimming Distance`. |
| `swimmingStrokes` / `swimming_strokes` | `ExerciseSessionRecord.segments[].repetitions` | ✅ partial | Health Connect has no dedicated stroke record in beta02; uses swimming segment repetitions when apps provide them. |
| `wheelchairDistanceKm` / `wheelchair_km` | Wheelchair exercise sessions + overlapping `DistanceRecord` | ✅ partial | Distance is correlated by session time. `wheelchairPushes` remains the direct aggregate. |
| `downhillSnowSportsDistanceKm` / `downhill_snow_km` | Skiing/snowboarding/snowshoeing sessions + overlapping `DistanceRecord` | ✅ partial | Distance is correlated by session time. |
| `walkingHeartRateAverage` / `walking_heart_rate` | Walking sessions + overlapping `HeartRateRecord` samples | ✅ partial | Health Connect beta02 has no standalone walking-HR record; Android derives the average from samples during walking workouts. |
| Running speed / `running_speed` | Running sessions + overlapping `SpeedRecord` samples | ✅ partial | Also kept in workout-level details. |
| Running power / `running_power_*` | Running sessions + overlapping `PowerRecord` samples | ✅ partial | Health Connect exposes generic power samples, not all Apple running-dynamics fields. |
| Mono/poly/unsaturated/trans fat | `NutritionRecord.*_FAT_TOTAL` | ✅ | Exported through JSON, CSV, Markdown, frontmatter/Bases, and metric picker. |
| Vitamins/minerals | `NutritionRecord` micronutrient totals | ✅ | Calcium, iron, magnesium, zinc, vitamins A/B6/B12/C/D/E/K, folate, etc. are supported. |
| Workout calories/distance/elevation | `ActiveCaloriesBurnedRecord`, `DistanceRecord`, `ElevationGainedRecord` overlapping `ExerciseSessionRecord` | ✅ partial | Health Connect does not always link records to a session id; Android correlates by time window. |
| Workout HR/speed/cadence/power time series | `HeartRateRecord`, `SpeedRecord`, `CyclingPedalingCadenceRecord`, `StepsCadenceRecord`, `PowerRecord` | ✅ partial | Samples export only when granular data is enabled. |
| Workout laps/segments | `ExerciseSessionRecord.laps`, `.segments` | ✅ | Routes are not exported; beta02 exposes route result metadata but not a simple permissionless route payload here. |
| Stand hours / stand time | — | N/A | No Health Connect beta02 record equivalent. |
| Move minutes / physical effort | — | N/A | No Health Connect beta02 record equivalent. Exercise minutes remain supported. |
| Forced vital capacity, FEV1, peak flow, inhaler usage | — | N/A | Not in Health Connect beta02 records. |
| Waist circumference / body measurements | — | N/A | No waist/body-measurement record in Health Connect beta02. |
| Step length, double support, asymmetry, stair speeds, six-minute walk, walking steadiness | — | N/A | Not in Health Connect beta02 records. |
| Running stride/contact/vertical oscillation | — | N/A | Not in Health Connect beta02 records. Running speed/power are supported. |
| Hearing / environmental audio | — | N/A | No hearing/audio exposure records in Health Connect beta02. |
| Symptoms, UV, falls, insulin, alcohol, toothbrushing, handwashing | — | N/A | No matching Health Connect beta02 records. |
| Mac desktop destination | Storage Access Framework / synced folders | Platform-specific N/A | Android exports locally through SAF. A network desktop bridge is deferred; see `docs/android-desktop-destination.md`. |
