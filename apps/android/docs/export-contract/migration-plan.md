# Migration + Backward Compatibility Plan
## Android Export Schema Parity (v1.2.x → v1.3.0)

**Created:** 2026-04-21  
**Updated:** 2026-06-05 (Phase 4 release-readiness pass)  
**Target release:** v1.3.0 (versionCode 11)  
**Scope:** JSON, Markdown/Obsidian Bases, CSV export schema  
**Reference:** `docs/export-contract/android-ios-gap-matrix.md`

---

## 1) Change inventory

### 1a) Breaking changes (old key/label removed)

These are renames where the old name was never valid for the obsidian-health-md plugin.
Existing custom Obsidian dashboards that referenced these Android-specific keys will break.

| Format | Old (≤v1.2.x) | New (v1.3.0+) | Why renamed |
|---|---|---|---|
| JSON | `sleep.stages[]` | `sleep.sleepStages[]` | iOS canonical array name; plugin reads `sleepStages` |
| JSON | `sleep.sleepStages[].startTime` | `sleep.sleepStages[].startDate` | iOS canonical; plugin time-slicer requires `startDate` |
| JSON | `sleep.sleepStages[].endTime` | `sleep.sleepStages[].endDate` | iOS canonical; plugin requires `endDate` |
| JSON | `sleep.sleepStages[]` → *(missing)* | `sleep.sleepStages[].durationSeconds` | iOS requires `durationSeconds` for stage rendering |
| JSON | all sample `time` keys | `timestamp` (ISO 8601) | Plugin `Date.parse()` requires ISO 8601; `"06:00"` → `NaN` |
| JSON | `heart.heartRateSamples[].bpm` | `heart.heartRateSamples[].value` | iOS canonical `.value` key |
| JSON | `heart.hrvSamples[].ms` | `heart.hrvSamples[].value` | iOS canonical `.value` key |
| JSON | `vitals.bloodOxygenSamples[].percent` | `vitals.bloodOxygenSamples[].value` | iOS canonical `.value` key |
| JSON | `vitals.bloodGlucoseSamples[].mgPerDl` | `vitals.bloodGlucoseSamples[].value` | iOS canonical `.value` key |
| JSON | `vitals.respiratoryRateSamples[].breathsPerMin` | `vitals.respiratoryRateSamples[].value` | iOS canonical `.value` key |
| JSON | `mindfulness.mindfulnessMinutes` | `mindfulness.mindfulMinutes` | iOS canonical key name |
| CSV | `Heart,HRV (RMSSD)` | `Heart,HRV` | iOS canonical label; plugin reads "HRV" |
| CSV | `Vitals,SpO2 Sample` | `Vitals,Blood Oxygen Sample` | iOS canonical label |
| CSV | `Activity,Floors Climbed` | `Activity,Flights Climbed` | iOS canonical label; plugin reads "Flights Climbed" |
| CSV | 5-column header | 6-column header (+ `Timestamp`) | iOS standard; aggregate rows emit empty Timestamp |

**Impact:** Custom Obsidian `dataviewjs` scripts, Templater templates, or community plugins
that used these Android-specific keys will need to be updated by users.

### 1b) Dual-write aliases (both old + new keys present; backward-compatible)

These are cases where we emit **both** the old Android key and the new iOS-canonical key.
Existing consumers using the old key continue to work; new consumers use the canonical key.

| Format | Old key (kept) | New key (added) | Deprecation plan |
|---|---|---|---|
| JSON | `sleep.lightSleep`, `sleep.lightSleepFormatted` | `sleep.coreSleep`, `sleep.coreSleepFormatted` | Remove `lightSleep` in v2.0 |
| JSON | `activity.wheelchairPushes` | `activity.pushCount` | Remove `wheelchairPushes` in v2.0 |
| JSON | `mobility.vo2Max` | `activity.vo2Max` | Remove from `mobility` in v2.0 |
| JSON vitals | *(all avg fields)* | `respiratoryRate`, `bloodOxygen`, `bodyTemperature`, `bloodPressureSystolic`, `bloodPressureDiastolic`, `bloodGlucose` backward-compat aliases | Aliases are iOS canonical too; keep indefinitely |
| FM | `sleep_light_hours` | `sleep_core_hours` | Remove `sleep_light_hours` in v2.0 |
| CSV | `Sleep,Light Sleep` | `Sleep,Core Sleep` | Remove `Light Sleep` row in v2.0 |
| CSV | `Mobility,VO2 Max` | `Activity,Cardio Fitness (VO2 Max)` | Remove `Mobility,VO2 Max` in v2.0 |

### 1c) Additive-only changes (no existing consumer breaks)

New keys added that didn't exist before. No migration needed.

- JSON `sleep.bedtime`, `sleep.bedtimeISO`, `sleep.wakeTime`, `sleep.wakeTimeISO`
- JSON `activity.stepSamples[].timestamp`+`.value`
- JSON vitals `bloodOxygenMinPercent`, `bloodOxygenMaxPercent`, all min/max variants
- FM `sleep_core_hours`, `sleep_bedtime`, `sleep_wake`, all vitals `_avg/_min/_max` keys
- FM `mindful_sessions`
- CSV `Sleep,Core Sleep`, `Sleep,Bedtime`, `Sleep,Wake Time`, `Sleep,Sleep Stage`
- CSV `Activity,Cardio Fitness (VO2 Max)`, `Mindfulness,Mindful Sessions`

---

## 2) Migration strategy by user type

### Type A — obsidian-health-md plugin users (most common)

**Before parity:** Sleep architecture, heart terrain, HRV trend, oxygen river, and time-window
slicing did not work with Android exports. Breaking changes were already broken for these users.

**After parity:** All plugin visualizations work correctly. No action needed.

**Recommendation:** Upgrade Android app. Re-export recent history (last 30–90 days) so the
plugin's JSON files have the new schema. Old files with the broken schema can be deleted or
left in place; the plugin ignores unrecognized fields gracefully.

### Type B — custom Obsidian dashboards using Android-specific keys

Users who wrote their own `dataviewjs` or Templater scripts against the old Android key names
will need to update their scripts. Provide the following migration table in release notes:

| If your script uses | Change it to |
|---|---|
| `page.sleep?.stages` | `page.sleep?.sleepStages` |
| `stage.startTime` | `stage.startDate` |
| `stage.endTime` | `stage.endDate` |
| `sample.bpm` | `sample.value` |
| `sample.ms` | `sample.value` |
| `sample.percent` | `sample.value` |
| `sample.mgPerDl` | `sample.value` |
| `sample.breathsPerMin` | `sample.value` |
| `mindfulness.mindfulnessMinutes` | `mindfulness.mindfulMinutes` |
| CSV: `HRV (RMSSD)` | CSV: `HRV` |
| CSV: `SpO2 Sample` | CSV: `Blood Oxygen Sample` |
| CSV: `Floors Climbed` | CSV: `Flights Climbed` |
| `sleep_light_hours` | `sleep_core_hours` (or keep `sleep_light_hours` — both present in v1.3.0) |
| `mobility.vo2Max` | `activity.vo2Max` (or keep — both present in v1.3.0) |

### Type C — users syncing iOS + Android data

**Before parity:** iOS and Android exports had different schema. Plugin dashboards built on
iOS data would not correctly read Android exports, and vice versa.

**After parity:** Both platforms produce compatible JSON/Bases/CSV. Mixed-device vaults
work without additional configuration. Shared Obsidian dashboards see the same field names
regardless of export source.

**Note on `sleep_core_hours` vs `sleep_light_hours`:**  
iOS Apple Watch uses "Core" sleep as a distinct stage. Health Connect uses "Light/NREM2" for
the same bucket. Both names are now present in Android exports (`sleep_core_hours` =
`sleep_light_hours` = same numeric value). Dashboards that used `sleep_core_hours` from iOS
will now find the same key in Android exports.

---

## 3) Deprecation timeline

| Phase | Version | When | Action |
|---|---|---|---|
| **Parity release** | v1.3.0 | Now | All P0-P3 parity fixes, dual-write aliases, expanded Health Connect metrics, and explicit Android N/A handling ship |
| **Alias cleanup** | v2.0.0 | 6+ months | Remove `sleep.lightSleep` from JSON, `sleep_light_hours` from FM, `Sleep,Light Sleep` from CSV, `Mobility,VO2 Max` from CSV, `activity.wheelchairPushes` from JSON |
| **Notice** | v1.4.0 | 3 months | In-app message / release notes noting upcoming v2.0 alias removal |

### Protected forever (iOS-standard; never removed)
- `sleep.coreSleep`, `sleep_core_hours`, `Sleep,Core Sleep`
- `activity.vo2Max` (under activity)
- `activity.pushCount`
- All vitals backward-compat aliases (`respiratoryRate`, `bloodOxygen`, etc.)
- 6-column CSV header

---

## 4) Re-export guidance for users

Users who want existing vault files to match the new schema should re-export affected date
ranges. Quick steps:

1. Open Health.md → Export Settings → pick date range (last 90 days recommended)
2. Export to same vault folder (Overwrite mode)
3. Open Obsidian — plugin auto-reloads changed files

For users with large date ranges (years), old-schema files harmlessly coexist with new ones.
Visualizations read the fields they need and skip files that don't have them.

---

## 5) Release checklist for v1.3.0

### Phase 4 release-readiness status
- [x] `versionCode = 11`, `versionName = "1.3.0"` in `app/build.gradle.kts`
- [x] Play Console release notes updated at `play-console/listing/en-US/release-notes/en-US/default.txt`
- [x] Compatibility docs updated after completed P0-P3 implementation
- [x] Release-readiness metadata/docs test added

### Automated validation completed
- [x] All parity contract tests pass: `./gradlew :app:testDebugUnitTest`

### Pre-release validation still requiring a device/manual pass
- [ ] Build release APK/AAB and install on Pixel 7 device (per AGENTS.md)
- [ ] Manual smoke test: export 3 days with granular data enabled, load into Obsidian + plugin
- [ ] Verify sleep architecture, heart terrain, oxygen river charts render

### Release notes (user-facing)
Copy into Play Store "What's New" field:

```
v1.3.0 — Android/iOS Export Parity

• JSON, Markdown, Obsidian Bases, and CSV exports now match the iOS schema.
• Obsidian Health.md plugin charts read Android sleep, heart, HRV, oxygen, breathing, and VO2 Max correctly.
• Richer metrics, preview, retry, schedule lookback, daily notes, and individual entries are ready.
• Unavailable Apple/Health Connect-only metrics are marked.

Custom scripts: re-export recent history and switch old Android keys to canonical iOS-compatible names.
```

### Post-release
- [x] Update `docs/export-contract/android-ios-gap-matrix.md` — mark P0-P3 parity phases as implemented
- [ ] File issue in obsidian-health-md plugin repo to align CSV parser labels with iOS standard
  (pre-existing gap: VO2 Max, Basal Energy, Respiratory Rate, Blood Oxygen labels in CSV parser)

---

## 6) Backward compatibility regression test

`app/src/test/java/com/healthmd/export/BackwardCompatibilityTest.kt`

Verifies that all dual-write aliases remain present until explicitly removed in v2.0:
- `sleep.lightSleep` alongside `sleep.coreSleep`
- `activity.wheelchairPushes` alongside `activity.pushCount`
- `mobility.vo2Max` alongside `activity.vo2Max`
- `sleep_light_hours` alongside `sleep_core_hours` in frontmatter
- `Sleep,Light Sleep` alongside `Sleep,Core Sleep` in CSV
- `Mobility,VO2 Max` alongside `Activity,Cardio Fitness (VO2 Max)` in CSV
