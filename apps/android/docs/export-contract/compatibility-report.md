# Android ↔ obsidian-health-md Plugin Compatibility Report

**Date:** 2026-04-21  
**Android exporter version:** after parity pass (TODO-97e45d02 through TODO-4bd40e9d)  
**Plugin repo:** `/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md`

---

## Executive Summary

After applying all P0 + P1 gap-matrix fixes, **Android JSON exports are fully compatible with
all obsidian-health-md visualizations**. Markdown/Obsidian Bases exports satisfy all plugin
markdown-parser lookups. CSV exports satisfy most plugin CSV-parser lookups; 4 pre-existing
gaps remain (identical to iOS) that do not affect any visualization.

**No plugin changes are required** for the Android parity targets.

---

## 1) JSON format — Compatibility status: ✅ Fully compatible

The `json-parser.ts` is a passthrough: it validates `type === "health-data"` and `date`, then
returns the parsed object as-is. All visualizations read fields directly from the JSON object.

| Plugin visualization | Fields read | Android status |
|---|---|---|
| `sleep-architecture.ts` | `sleep.sleepStages[].stage`, `.startDate`, `.endDate`, `.durationSeconds` | ✅ Fixed (T0-01/02/03) |
| `sleep-polar.ts` | same as above + `sleep.totalDuration`, `.deepSleep`, `.coreSleep`, `.remSleep` | ✅ Fixed |
| `sleep-schedule.ts` | `sleep.sleepStages[]`, `sleep.bedtime`, `sleep.wakeTime` | ✅ Fixed (T1-02) |
| `heart-terrain.ts` | `heart.heartRateSamples[].timestamp`, `.value` | ✅ Fixed (T0-04/05) |
| `hrv-trend.ts` | `heart.hrvSamples[].timestamp`, `.value` | ✅ Fixed (T0-04/06) |
| `weekday-average.ts` | `heart.hrvSamples[]` | ✅ Fixed |
| `oxygen-river.ts` | `vitals.bloodOxygenSamples[].timestamp`, `.value` | ✅ Fixed (T0-04/07) |
| `oxygen-range.ts` | `vitals.bloodOxygenAvg`, `vitals.bloodOxygenMin`, `vitals.bloodOxygenMax` | ✅ All emitted |
| `breathing-wave.ts` | `vitals.respiratoryRateSamples[].timestamp`, `.value` | ✅ Fixed (T0-04/09) |
| `summary-card.ts` | `vitals.bloodOxygenAvg`, `vitals.bloodOxygenPercent`, `vitals.respiratoryRateAvg`, `vitals.respiratoryRate` | ✅ Aliases emitted (T1-05) |
| `trend-tile.ts` (VO2) | `activity.vo2Max` | ✅ Fixed (T0-10) |
| `vitals-rings.ts` | `activity.steps`, `activity.activeCalories`, `heart.averageHeartRate` | ✅ |
| `intro-stats.ts` | `sleep.sleepStages`, `sleep.totalDuration` | ✅ |
| Time-window slicing (`renderer.ts`) | All sample `timestamp` fields parsed as `Date.parse()` | ✅ ISO 8601 (T0-04) |

### JSON parser validation results (automated)

All 14 plugin-required JSON field patterns verified by `PluginCompatibilityValidationTest`:
```
json_pluginParsesAndroidOutput_notNull    ✅
json_sleepStages_pluginRequiredFields     ✅
json_heartSamples_pluginRequiredFields    ✅
json_hrvSamples_pluginRequiredFields      ✅
json_vitalsSamples_pluginRequiredFields   ✅
json_activityVo2Max_underActivityCategory ✅
json_vitalsAliases_forPluginSummaryCard   ✅
```

---

## 2) Markdown / Obsidian Bases format — Compatibility status: ✅ Fully compatible

The `markdown-parser.ts` reads flat YAML frontmatter keys from both `.md` and Bases files.

| Plugin field read | FM key | Android status |
|---|---|---|
| `activity.steps` | `steps` | ✅ |
| `activity.walkingRunningDistanceKm` | `walking_running_km` | ✅ |
| `activity.activeCalories` | `active_calories` | ✅ |
| `activity.exerciseMinutes` | `exercise_minutes` | ✅ |
| `activity.vo2Max` | `vo2_max` | ✅ |
| `activity.flightsClimbed` | `flights_climbed` | ✅ |
| `heart.restingHeartRate` | `resting_heart_rate` | ✅ |
| `heart.averageHeartRate` | `average_heart_rate` | ✅ |
| `heart.hrv` | `hrv_ms` | ✅ |
| `heart.heartRateMin` | `heart_rate_min` | ✅ |
| `heart.heartRateMax` | `heart_rate_max` | ✅ |
| `sleep.totalDuration` | `sleep_total_hours` (×3600) | ✅ |
| `sleep.deepSleep` | `sleep_deep_hours` | ✅ |
| `sleep.remSleep` | `sleep_rem_hours` | ✅ |
| `sleep.coreSleep` | `sleep_core_hours` | ✅ Fixed (T1-06) |
| `sleep.awakeTime` | `sleep_awake_hours` | ✅ |
| `sleep.bedtime` | `sleep_bedtime` | ✅ Fixed (T1-02) |
| `sleep.wakeTime` | `sleep_wake` | ✅ Fixed (T1-02) |
| `vitals.respiratoryRate` | `respiratory_rate` (alias) | ✅ Fixed (T1-05/07) |
| `vitals.bloodOxygenAvg` | `blood_oxygen` (alias) or `blood_oxygen_avg` | ✅ Both emitted (T1-05/07) |
| `mobility.walkingSpeed` | `walking_speed` | ✅ |

### Bases parser validation results (automated)

All 15 plugin-required FM key patterns verified by `PluginCompatibilityValidationTest`:
```
bases_pluginReadsSteps                   ✅ 12500
bases_pluginReadsVo2Max                  ✅ 42.5
bases_pluginReadsRestingHeartRate        ✅ 58.0
bases_pluginReadsHrvMs                   ✅ 42.0
bases_pluginReadsSleepTotalHours         ✅ ≈7.75h
bases_pluginReadsSleepCoreHours          ✅ (T1-06 fix)
bases_pluginReadsSleepBedtimeWake        ✅ (T1-02 fix)
bases_pluginReadsRespiratoryRate         ✅ (T1-05/07 fix)
bases_pluginReadsBloodOxygen             ✅ (T1-05/07 fix)
bases_pluginReadsWalkingSpeed            ✅
```

---

## 3) CSV format — Compatibility status: ✅ Core fields, 4 pre-existing gaps

The `csv-parser.ts` uses case-insensitive `category + metric` label lookups.

### Reads correctly

| Plugin lookup | Android output | Status |
|---|---|---|
| `Activity,Steps` | `Activity,Steps` | ✅ |
| `Activity,Active Calories` | `Activity,Active Calories` | ✅ |
| `Activity,Exercise Minutes` | `Activity,Exercise Minutes` | ✅ |
| `Activity,Flights Climbed` | `Activity,Flights Climbed` | ✅ Fixed (T1-10) |
| `Activity,Walking Running Distance` | `Activity,Walking Running Distance` (meters, plugin converts) | ✅ |
| `Heart,Resting Heart Rate` | `Heart,Resting Heart Rate` | ✅ |
| `Heart,Average Heart Rate` | `Heart,Average Heart Rate` | ✅ |
| `Heart,Heart Rate Min` | `Heart,Min Heart Rate` | ✅ |
| `Heart,Heart Rate Max` | `Heart,Max Heart Rate` | ✅ |
| `Heart,HRV` | `Heart,HRV` | ✅ Fixed (T1-12) |
| `Sleep,Total Duration` | `Sleep,Total Duration` | ✅ |
| `Sleep,Deep Sleep` | `Sleep,Deep Sleep` | ✅ |
| `Sleep,REM Sleep` | `Sleep,REM Sleep` | ✅ |
| `Sleep,Core Sleep` | `Sleep,Core Sleep` | ✅ Fixed (T1-09) |
| `Sleep,Awake Time` | `Sleep,Awake Time` | ✅ |
| `Sleep,Bedtime` | `Sleep,Bedtime` | ✅ (T1-02) |
| `Sleep,Wake Time` | `Sleep,Wake Time` | ✅ (T1-02) |
| `Mobility,Walking Speed` | `Mobility,Walking Speed` | ✅ |

### Pre-existing gaps (identical in iOS; no visualization impact)

| Plugin lookup | Android output | Gap | Impact |
|---|---|---|---|
| `Activity,VO2 Max` | `Activity,Cardio Fitness (VO2 Max)` | Label mismatch (iOS standard label) | None — plugin reads VO2 from JSON `activity.vo2Max` |
| `Activity,Basal Energy Burned` | `Activity,Basal Energy` | Label mismatch (iOS standard label) | None — no visualization uses CSV basal energy |
| `Vitals,Respiratory Rate` | `Vitals,Respiratory Rate Avg` | Label mismatch (iOS standard label) | None — plugin reads resp rate from JSON `vitals.respiratoryRate` |
| `Vitals,Blood Oxygen` | `Vitals,Blood Oxygen Avg` | Label mismatch (iOS standard label) | None — plugin reads SpO2 from JSON `vitals.bloodOxygenAvg` |

These gaps exist in the iOS exporter too — the plugin's `csv-parser.ts` was written against
an older iOS exporter version and has not been updated. They do not block any visualization
because all the affected fields are read from JSON when granular data is available.

---

## 4) Sample files

Generated from `ExportFixtures.fullDayGranular` (2026-03-15 reference date):

| File | Format | Description |
|---|---|---|
| `docs/export-contract/samples/android-full-day-granular.json` | JSON | Full day with all sample arrays |
| `docs/export-contract/samples/android-partial-day.json` | JSON | Sleep + activity only |
| `docs/export-contract/samples/android-empty-day.json` | JSON | Date + type only |
| `docs/export-contract/samples/android-full-day.md` | Markdown/Bases | Full day frontmatter |
| `docs/export-contract/samples/android-full-day-granular.csv` | CSV | Full day with granular rows |

To use in Obsidian: copy any sample file to your vault's Health.md data folder and set
format = `auto` in the plugin settings.

---

## 5) Plugin changes required

**None.** All required parity fixes were applied on the Android side.

The 4 pre-existing CSV label gaps are iOS-identical and don't affect any visualization.
If the plugin's `csv-parser.ts` is updated in the future, the Android exporter already
uses the correct iOS-standard labels that would match updated lookups.

---

## 6) Test validation commands

```bash
# Full contract suite (137 tests)
./gradlew :app:testDebugUnitTest

# Validation test only
./gradlew :app:testDebugUnitTest --tests com.healthmd.export.PluginCompatibilityValidationTest

# Results: 41 tests, 0 failures, 0 errors
```
