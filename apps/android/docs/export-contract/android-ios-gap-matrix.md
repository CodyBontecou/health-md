# Android ↔ iOS Exporter Gap Matrix

**Status:** canonical gap analysis for Android export-parity work  
**Generated:** 2026-04-21  
**Reference:** `docs/export-contract/ios-export-contract.md`

## Priority Legend

| Priority | Meaning |
|---|---|
| **P0** | Breaks `obsidian-health-md` plugin visualization or changes value semantics (scale, units). Fix before shipping any parity claim. |
| **P1** | Key/label mismatch that causes a field to silently not appear in the plugin, or a rename that makes an existing field invisible. Fix in same release as P0s, using dual-write during transition. |
| **P2** | iOS has the field, Android doesn't — plugin doesn't currently depend on it. Fill incrementally. |
| **P3** | Apple-exclusive concept (HealthKit-only); no Health Connect equivalent. Accept as N/A. |
| **Android+** | Android emits this; iOS doesn't. Document as Android extension (keep). |

---

## 1) JSON format gaps

### 1.1 Sleep category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| Granular array key | `sleep.sleepStages` | `sleep.stages` | **P0** | `sleep-architecture.ts`, `sleep-polar.ts`, `sleep-schedule.ts` all read `sleep.sleepStages` |
| Stage item timestamp key | `startDate` (ISO 8601) | `startTime` (TimeFormatPreference string) | **P0** | Plugin slices stages by ISO 8601; wrong key name + non-ISO format |
| Stage item end timestamp key | `endDate` (ISO 8601) | `endTime` (TimeFormatPreference string) | **P0** | Same as above |
| Stage item duration | `durationSeconds` (number) | ❌ missing | **P0** | Plugin uses `durationSeconds` to reconstruct durations |
| Core vs Light sleep terminology | `coreSleep`, `coreSleepFormatted` | `lightSleep`, `lightSleepFormatted` | **P1** | Semantic mismatch; Health Connect "light" sleep = iOS/Apple Watch "core" sleep for visualization purposes |
| Bedtime / wake time | `bedtime`, `bedtimeISO`, `wakeTime`, `wakeTimeISO` | ❌ missing | **P1** | Used by `sleep-schedule.ts` to plot sleep window |
| iOS sample timestamps | All arrays use ISO 8601 | All arrays use `TimeFormatPreference` string | **P0** | Plugin's time-window slicer in `renderer.ts` parses timestamps as ISO 8601 |

### 1.2 Activity category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| `vo2Max` placement | `activity.vo2Max` | `mobility.vo2Max` | **P0** | `trend-tile.ts` and `summary-card.ts` read `d.activity?.vo2Max` |
| `standHours` | `activity.standHours` | ❌ missing (Health Connect has no stand-hours aggregation) | **P2** | No current plugin dependency |
| `swimmingDistance` | `activity.swimmingDistance` | ❌ missing | **P2** | No current plugin dependency |
| `swimmingStrokes` | `activity.swimmingStrokes` | ❌ missing | **P2** | — |
| Wheelchair push count key | `activity.pushCount` | `activity.wheelchairPushes` | **P1** | Key name mismatch; field invisible to consumers expecting `pushCount` |
| `wheelchairDistanceKm` | ✅ | ❌ missing | **P2** | — |
| `downhillSnowSportsDistanceKm` | ✅ | ❌ missing | **P2** | — |
| `moveMinutes` | ✅ | ❌ missing | **P2** | — |
| `physicalEffort` | ✅ | ❌ missing | **P2** | — |
| **Android+**: `totalCalories` | ❌ | ✅ (Android extra) | — | No iOS equivalent |
| **Android+**: `elevationGained` | ❌ | ✅ (Android extra) | — | No iOS equivalent |

### 1.3 Heart category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| Heart rate sample timestamp key | `heartRateSamples[].timestamp` (ISO 8601) | `heartRateSamples[].time` (TimeFormatPreference string) | **P0** | `heart-terrain.ts`, `renderer.ts` parse `timestamp` as ISO 8601 |
| Heart rate sample value key | `heartRateSamples[].value` | `heartRateSamples[].bpm` | **P0** | Plugin reads `.value` from each sample |
| HRV sample timestamp key | `hrvSamples[].timestamp` (ISO 8601) | `hrvSamples[].time` (TimeFormatPreference string) | **P0** | `hrv-trend.ts`, `weekday-average.ts` parse `timestamp` |
| HRV sample value key | `hrvSamples[].value` | `hrvSamples[].ms` | **P0** | Plugin reads `.value` |
| `walkingHeartRateAverage` | ✅ | ❌ missing | **P2** | — |
| `heartRateRecovery` | ✅ | ❌ missing | **P2** | — |
| `atrialFibrillationBurdenPercent` | ✅ | ❌ missing | **P2** | — |

### 1.4 Vitals category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| Blood oxygen sample timestamp key | `bloodOxygenSamples[].timestamp` (ISO 8601) | `bloodOxygenSamples[].time` (TimeFormatPreference string) | **P0** | `oxygen-river.ts`, `renderer.ts` slice by ISO 8601 timestamps |
| Blood oxygen sample value key | `bloodOxygenSamples[].value` (fraction 0–1) | `bloodOxygenSamples[].percent` | **P0** | Key name mismatch; iOS stores fraction (0.97), Android stores percent-named value; scale needs auditing |
| Blood glucose sample timestamp key | `bloodGlucoseSamples[].timestamp` (ISO 8601) | `bloodGlucoseSamples[].time` | **P0** | Same slicing issue |
| Blood glucose sample value key | `bloodGlucoseSamples[].value` | `bloodGlucoseSamples[].mgPerDl` | **P0** | Key mismatch |
| Respiratory rate sample timestamp key | `respiratoryRateSamples[].timestamp` (ISO 8601) | `respiratoryRateSamples[].time` | **P0** | `breathing-wave.ts`, `renderer.ts` |
| Respiratory rate sample value key | `respiratoryRateSamples[].value` | `respiratoryRateSamples[].breathsPerMin` | **P0** | Key mismatch |
| Backward-compat aliases | `respiratoryRate`, `bloodOxygen`, `bodyTemperature`, `bloodPressureSystolic`, `bloodPressureDiastolic`, `bloodGlucose` | ❌ missing | **P1** | `summary-card.ts` reads `respiratoryRate` and `bloodOxygenPercent`/`bloodOxygenAvg` as fallbacks |
| `bloodOxygenMinPercent`, `bloodOxygenMaxPercent` | ✅ | ❌ missing | **P2** | — |
| `wristTemperature` | ✅ (Apple Watch) | `skinTemperatureDelta` (different field) | **P3** | Apple-exclusive hardware |
| `electrodermalActivity` | ✅ (Apple Watch) | ❌ | **P3** | Apple-exclusive hardware |
| `forcedVitalCapacityL`, `fev1L`, `peakExpiratoryFlow`, `inhalerUsage` | ✅ | ❌ missing | **P2** | — |
| **Android+**: `skinTemperatureDelta` | ❌ | ✅ | — | Android/Wear OS extra |
| **Android+**: `bloodPressureSamples[]` | ❌ | ✅ (granular BP) | — | Android extra |
| **Android+**: `bodyTemperatureSamples[]` | ❌ | ✅ | — | Android extra |

### 1.5 Body category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| `waistCircumference` | ✅ | ❌ missing | **P2** | — |
| **Android+**: `bodyWaterMass` | ❌ | ✅ | — | Android extra |
| **Android+**: `boneMass` | ❌ | ✅ | — | Android extra |

### 1.6 Mindfulness category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| Key name mismatch | `mindfulness.mindfulMinutes` | `mindfulness.mindfulnessMinutes` | **P1** | Consumers expecting `mindfulMinutes` miss the field |
| `mindfulSessions` | ✅ | ❌ missing | **P2** | — |
| State of mind fields (`stateOfMindEntries`, `averageValence`, `averageValencePercent`, etc.) | ✅ (Apple exclusive) | ❌ | **P3** | Apple Watch / iOS 17+ exclusive |

### 1.7 Hearing category

| Gap | iOS | Android | Priority | Plugin Impact |
|---|---|---|---|---|
| Entire `hearing` category | ✅ | ❌ missing | **P2** | No current plugin dependency on CSV/JSON hearing |

### 1.8 Cross-cutting: timestamp format on all sample arrays

> **P0 — affects every granular array.**
>
> iOS uses ISO 8601 (`2026-03-15T06:00:00Z`) for all sample timestamps.  
> Android uses the configured `TimeFormatPreference` string (e.g. `"06:00"`).  
>
> The plugin's `renderer.ts` parses these strings as `Date.parse()` and slices arrays by millisecond epoch.
> A short time string like `"06:00"` parses as an invalid date, breaking all sub-day window slicing.
>
> **Fix:** Use ISO 8601 (or epoch ms) for all sample array timestamps regardless of user time format preference.

---

## 2) Frontmatter / Obsidian Bases gaps

### 2.1 Sleep keys

| Gap | iOS key | Android key | Priority | Plugin impact (markdown-parser.ts) |
|---|---|---|---|---|
| Core vs Light sleep | `sleep_core_hours` | `sleep_light_hours` | **P1** | Parser reads `sleep_core_hours`; Android's `sleep_light_hours` is ignored → `coreSleep: 0` in plugin |
| Bedtime / wake time | `sleep_bedtime`, `sleep_wake` | ❌ missing | **P2** | Parser reads `sleep_bedtime`/`sleep_wake` for sleep window display |

### 2.2 Activity keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Stand hours | `stand_hours` | ❌ missing | **P2** |
| Swimming | `swimming_m`, `swimming_strokes` | ❌ missing | **P2** |
| Wheelchair / snow / move / effort | `wheelchair_km`, `downhill_snow_km`, `move_minutes`, `physical_effort` | ❌ missing | **P2** |

### 2.3 Heart keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Walking heart rate | `walking_heart_rate` | ❌ missing | **P2** |
| Recovery / AFib | `heart_rate_recovery`, `afib_burden_percent` | ❌ missing | **P2** |

### 2.4 Vitals keys

| Gap | iOS keys | Android keys | Priority | Plugin impact |
|---|---|---|---|---|
| Min/max variants | `respiratory_rate_avg`, `respiratory_rate_min`, `respiratory_rate_max`; `blood_oxygen_avg`, `_min`, `_max`; `body_temperature_avg`, `_min`, `_max`; `blood_pressure_systolic_avg`, `_min`, `_max`; `blood_pressure_diastolic_avg`, `_min`, `_max`; `blood_glucose_avg`, `_min`, `_max` | Android only emits single keys (`respiratory_rate`, `blood_oxygen`, `body_temperature`, `blood_pressure_systolic`, `blood_pressure_diastolic`, `blood_glucose`) | **P1** | `summary-card.ts` falls back to `blood_oxygen`/`blood_oxygen_avg` and `respiratory_rate`/`respiratory_rate_avg`; single keys work as-is but min/max range display won't function |
| Respiratory aliases | `respiratory_rate` and `respiratory_rate_avg` (both present) | Only `respiratory_rate` | OK | Plugin uses `respiratory_rate` as primary fallback — **Android OK for this one** |
| Wrist temperature | `wrist_temperature` | ❌ (`skin_temperature_delta` instead) | **P3** | Apple Watch exclusive |
| Extended lung/inhaler metrics | `forced_vital_capacity_l`, `fev1_l`, `peak_expiratory_flow`, `inhaler_usage` | ❌ missing | **P2** | — |
| Electrodermal activity | `electrodermal_activity` | ❌ | **P3** | Apple Watch exclusive |

### 2.5 Body keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Waist circumference | `waist_circumference_cm` | ❌ missing | **P2** |

### 2.6 Nutrition keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Mono/polyunsaturated fat | `monounsaturated_fat_g`, `polyunsaturated_fat_g` | ❌ missing | **P2** |

### 2.7 Mindfulness keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Sessions | `mindful_sessions` | ❌ missing | **P2** |
| Mood/valence | `average_mood_valence`, `average_mood_percent`, `daily_mood_count`, etc. | ❌ | **P3** |

### 2.8 Mobility keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Extended walk metrics | `step_length_cm`, `double_support_percent`, `walking_asymmetry_percent`, `stair_ascent_speed`, `stair_descent_speed`, `six_min_walk_m` | ❌ missing | **P2** |
| Running metrics | `walking_steadiness_percent`, `running_speed`, `running_stride_length_m`, `running_ground_contact_ms`, `running_vertical_oscillation_cm`, `running_power_w` | ❌ missing | **P2** |

### 2.9 Hearing keys

| Gap | iOS key | Android key | Priority |
|---|---|---|---|
| Headphone audio | `headphone_audio_db` | ❌ missing | **P2** |
| Environmental sound | `environmental_sound_db` | ❌ missing | **P2** |

### 2.10 Android-only frontmatter extras

These are Android additions with no iOS equivalent. Keep them.

| Android key | Source |
|---|---|
| `sleep_light_hours` | Health Connect sleep stage (maps to iOS "core") |
| `total_calories` | Health Connect total calories |
| `elevation_gained_m` | Health Connect elevation data |
| `body_water_mass_kg`, `bone_mass_kg` | Health Connect body composition |
| `cycling_cadence`, `steps_cadence`, `power_avg`, `power_max` | Health Connect workout metrics |
| `cervical_mucus_appearance`, `cervical_mucus_sensation`, `protection_used` | Health Connect reproductive health (finer granularity than iOS) |
| `skin_temperature_delta` | Wear OS |

---

## 3) CSV format gaps

### 3.1 Header schema

| Gap | iOS | Android | Priority | Impact |
|---|---|---|---|---|
| Column count (non-granular) | Always 6 columns: `Date,Category,Metric,Value,Unit,Timestamp` | 5 columns: `Date,Category,Metric,Value,Unit` (no Timestamp column) | **P1** | Plugin CSV parser handles ≥5 columns gracefully, but external tools expecting fixed 6 columns will break |

### 3.2 Sleep rows

| Gap | iOS | Android | Priority |
|---|---|---|---|
| Core vs Light sleep row | `Sleep,Core Sleep,<sec>,seconds` | `Sleep,Light Sleep,<sec>,seconds` | **P1** |
| Stage rows format | `Sleep,Sleep Stage,<name> (<dur>s),seconds,<ISO8601>` | `Sleep,Stage <name>,<start> - <end>,time range` | **P1** (label + structure) |
| Bedtime / wake rows | `Sleep,Bedtime,<time>,time` | ❌ missing | **P2** |

### 3.3 Activity rows

| Gap | iOS | Android | Priority |
|---|---|---|---|
| Flights label | `Activity,Flights Climbed` | `Activity,Floors Climbed` | **P1** |
| VO2 placement + label | `Activity,Cardio Fitness (VO2 Max),<val>,mL/kg/min` | `Mobility,VO2 Max,<val>,mL/kg/min` | **P1** — plugin CSV parser reads `getNum(rows,"Activity","VO2 Max")`, which matches neither. Closest match is Android label |
| Stand Hours | `Activity,Stand Hours` | ❌ missing | **P2** |
| Swimming / wheelchair / extra metrics | various | ❌ missing | **P2** |

### 3.4 Heart rows

| Gap | iOS | Android | Priority |
|---|---|---|---|
| HRV label | `Heart,HRV,<val>,ms` | `Heart,HRV (RMSSD),<val>,ms` | **P1** |
| Granular HR sample timestamp format | `...,bpm,<ISO8601>` | `...,bpm,<TimeFormatPreference string>` | **P0** |
| Walking HR, Recovery, AFib rows | various | ❌ missing | **P2** |

### 3.5 Vitals rows

| Gap | iOS | Android | Priority |
|---|---|---|---|
| SpO2 sample label | `Vitals,Blood Oxygen Sample` | `Vitals,SpO2 Sample` | **P1** |
| All granular sample timestamp format | ISO 8601 | TimeFormatPreference string | **P0** |

### 3.6 Hearing rows

| Gap | iOS | Android | Priority |
|---|---|---|---|
| `Hearing` category | `Hearing,Headphone Audio Level`, `Hearing,Environmental Sound Level` | ❌ missing | **P2** |

### 3.7 Mindfulness rows

| Gap | iOS | Android | Priority |
|---|---|---|---|
| Sessions | `Mindfulness,Mindful Sessions` | ❌ missing | **P2** |
| State of mind rows | `Mindfulness,…` / `State of Mind,…` | ❌ (Apple exclusive) | **P3** |

---

## 4) Prioritized implementation task list

### Tier 0 — Must fix (breaks plugin)

| # | Format | Change | Affected Android file |
|---|---|---|---|
| T0-01 | JSON | Rename `sleep.stages` → `sleep.sleepStages` | `JsonExporter.kt` |
| T0-02 | JSON | Rename stage item `startTime`/`endTime` → `startDate`/`endDate` (ISO 8601) | `JsonExporter.kt` |
| T0-03 | JSON | Add `durationSeconds` to each sleep stage item | `JsonExporter.kt` |
| T0-04 | JSON | All granular sample timestamps must use ISO 8601 (not TimeFormatPreference) | `JsonExporter.kt` |
| T0-05 | JSON | Rename heart sample key `bpm` → `value` | `JsonExporter.kt` |
| T0-06 | JSON | Rename heart HRV sample key `ms` → `value` | `JsonExporter.kt` |
| T0-07 | JSON | Rename blood oxygen sample key `percent` → `value`; verify value is fraction (0-1), not percent | `JsonExporter.kt` |
| T0-08 | JSON | Rename blood glucose sample key `mgPerDl` → `value` | `JsonExporter.kt` |
| T0-09 | JSON | Rename respiratory rate sample key `breathsPerMin` → `value` | `JsonExporter.kt` |
| T0-10 | JSON | Add `vo2Max` to `activity` dict (keep `mobility.vo2Max` too as Android extra) | `JsonExporter.kt` |
| T0-11 | CSV | All granular sample `Timestamp` column must be ISO 8601 | `CsvExporter.kt` |

### Tier 1 — Fix before marking parity shipped

| # | Format | Change | Affected Android file |
|---|---|---|---|
| T1-01 | JSON + Frontmatter | Add `coreSleep`/`coreSleepFormatted`/`sleep_core_hours` alias for Health Connect "light" sleep (keep `lightSleep`/`sleep_light_hours` as Android extra) | `JsonExporter.kt`, `HealthDataFields.kt` |
| T1-02 | JSON | Add `bedtime` + `bedtimeISO` + `wakeTime` + `wakeTimeISO` to sleep category | `JsonExporter.kt`, `SleepData` (needs sessionStart/sessionEnd) |
| T1-03 | JSON | Rename `mindfulness.mindfulnessMinutes` → `mindfulness.mindfulMinutes` | `JsonExporter.kt` |
| T1-04 | JSON | Rename `activity.wheelchairPushes` → `activity.pushCount` (keep `wheelchairPushes` as alias) | `JsonExporter.kt` |
| T1-05 | JSON vitals | Add backward-compat aliases: `respiratoryRate`, `bloodOxygen`, `bodyTemperature`, `bloodPressureSystolic`, `bloodPressureDiastolic`, `bloodGlucose` | `JsonExporter.kt` |
| T1-06 | Frontmatter | Add `sleep_core_hours` alias (same value as `sleep_light_hours`) | `HealthDataFields.kt` |
| T1-07 | Frontmatter | Expand single vitals keys to min/max variants: `respiratory_rate_avg`/`_min`/`_max`, `blood_oxygen_avg`/`_min`/`_max`, etc. | `HealthDataFields.kt`, `VitalsData` fields already present |
| T1-08 | CSV | Change header to always use 6 columns: add `Timestamp` column (blank for aggregate rows) | `CsvExporter.kt` |
| T1-09 | CSV | Rename `Core Sleep`/`Light Sleep` row to use `Core Sleep` label (alias) | `CsvExporter.kt` |
| T1-10 | CSV | Rename `Floors Climbed` → `Flights Climbed` | `CsvExporter.kt` |
| T1-11 | CSV | Add `Activity,Cardio Fitness (VO2 Max)` row (plugin expects that exact label under Activity) | `CsvExporter.kt` |
| T1-12 | CSV | Rename `HRV (RMSSD)` → `HRV` | `CsvExporter.kt` |
| T1-13 | CSV | Rename `SpO2 Sample` → `Blood Oxygen Sample` | `CsvExporter.kt` |
| T1-14 | Frontmatter | Add `mindful_sessions` (map to null/missing if Health Connect doesn't track sessions) | `HealthDataFields.kt`, `MindfulnessData` |

### Tier 2 — Fill incrementally

| # | Format | Change | Notes |
|---|---|---|---|
| T2-01 | JSON + FM + CSV | Add `standHours` / `stand_hours` | Health Connect has `HKQuantityTypeIdentifierAppleStandTime` equivalent? Check Health Connect API. |
| T2-02 | JSON + FM + CSV | Add `walkingHeartRateAverage` / `walking_heart_rate` | Health Connect `WalkingHeartRateAverage` exists. |
| T2-03 | JSON + FM + CSV | Add bedtime/wake derived from sleep session data | Requires `SleepData.sessionStart`/`sessionEnd` fields. |
| T2-04 | JSON + FM + CSV | Extended mobility: step length, double support, asymmetry, stair speeds, 6MW | Health Connect has these. |
| T2-05 | JSON + FM + CSV | Hearing: headphone + environmental audio | Health Connect `ExposureCategory` / `LoudnessStats`. |
| T2-06 | JSON + FM + CSV | Swimming distance + strokes | Health Connect has these. |
| T2-07 | JSON + FM + CSV | Waist circumference | Health Connect has `BodyMeasurementRecord`. |
| T2-08 | JSON + FM + CSV | Mono/polyunsaturated fat | Health Connect nutrition. |
| T2-09 | JSON + FM | AFib burden | Health Connect `HeartRateVariabilityRmssdRecord` partial analog; AFib = Watch-specific. |

### Tier 3 — Accept as N/A (Apple-exclusive)

| Feature | Reason |
|---|---|
| `wristTemperature` | Apple Watch hardware sensor |
| `electrodermalActivity` | Apple Watch hardware sensor |
| State of mind / mood valence (`stateOfMindEntries`, etc.) | HealthKit `HKStateOfMind` is iOS 17+ / Apple Watch exclusive |
| `heartRateRecovery` (Apple Watch-derived) | No Health Connect equivalent |
| Forced expiratory flow / inhaler usage | Rare; no Health Connect equivalent |

---

## 5) Rollout recommendation

### Strict match vs dual-write strategy

**Recommendation: dual-write for semantically equivalent fields, strict match for key renames.**

1. **New ISO 8601 timestamps (T0-04, T0-11):** Switch immediately. Breaks anything relying on human-readable time strings in arrays, but any such consumer is already broken (plugin fails to parse them). No backward-compat concern.

2. **Sample value key renames (T0-05 through T0-09):** Breaking change. No existing field was named correctly, so there are no existing consumers to protect. Rename directly.

3. **`sleep.stages` → `sleep.sleepStages` (T0-01):** Rename immediately. No Android JSON consumer was using the old key correctly.

4. **`activity.vo2Max` addition (T0-10):** Add to both `activity` and keep in `mobility`. Dual-write allows existing Android-specific tooling to keep reading from `mobility`. Remove from `mobility` in a future version once consumers migrate.

5. **`coreSleep` / `sleep_core_hours` alias (T1-01, T1-06):** Dual-write: emit both `lightSleep` (Android extra) and `coreSleep` (iOS parity alias). The values are from the same Health Connect sleep stage bucket (Light/NREM2). Note this in the contract as an explicit mapping note.

6. **`mindfulMinutes` rename (T1-03):** Switch immediately. Old key `mindfulnessMinutes` was never in the iOS contract.

7. **Vitals backward-compat aliases (T1-05):** Add as dual-write alongside existing `*Avg` keys. iOS has both; Android should too.

8. **CSV header (T1-08):** Add `Timestamp` as 6th column unconditionally. Aggregate rows get empty string. This is backward-compatible for parsers checking `parts.length >= 5`.

---

## 6) Summary counts

| Priority | JSON gaps | Frontmatter gaps | CSV gaps | Total |
|---|---|---|---|---|
| P0 | 11 | 0 | 2 | **13** |
| P1 | 6 | 8 | 6 | **20** |
| P2 | 18 | 24 | 11 | **53** |
| P3 | 6 | 5 | 2 | **13** |
| Android+ | 10 | 10 | — | **20** |
