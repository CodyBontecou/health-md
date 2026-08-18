# Migration + Backward Compatibility Plan
## Android Export Schema Parity (v1.2.x → v1.3.0)

**Created:** 2026-04-21  
**Updated:** 2026-07-25 (shipped-profile signature guardrail)
**Target release:** v1.3.0 (versionCode 11)  
**Scope:** JSON, Markdown/Obsidian Bases, CSV export schema  
**Reference:** `docs/export-contract/android-ios-gap-matrix.md`

---

## Ongoing cross-platform policy

This migration aligned historical Android projections with Apple-facing consumers, but future parity work must not assume that an Apple key is automatically the shared semantic authority. The repository [Apple and Android unification policy](../../../../docs/architecture/cross-platform-unification-policy.md) now governs new work:

- define one platform-neutral user and consumer outcome;
- compare HealthKit and Health Connect meaning, units, statistics, time ownership, provenance, and failure behavior;
- use common IDs/contracts only for proven equivalence;
- retain OS-specific data in explicit Apple/Android sections or capability states;
- mark temporary gaps `planned` with a concrete target;
- never relabel related-but-distinct data merely to satisfy a parity table.

The shipped Android frozen-v4 and analytical-v5 bytes remain immutable. New common semantics should target the proposed unified successor rather than extending those profiles in place.

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

### 1b) Android compatibility aliases (opt-in)

By default, Android now emits the iOS-canonical key/label only. Users with existing Android-specific
scripts can enable **Include Android compatibility keys** in format settings to also emit the old
Android key/label alongside the canonical key.

| Format | Android compatibility key (opt-in) | iOS-canonical key (default) | Plan |
|---|---|---|---|
| JSON | `sleep.lightSleep`, `sleep.lightSleepFormatted` | `sleep.coreSleep`, `sleep.coreSleepFormatted` | Keep behind compatibility toggle |
| JSON | `activity.wheelchairPushes` | `activity.pushCount` | Keep behind compatibility toggle |
| JSON | `mobility.vo2Max` | `activity.vo2Max` | Keep behind compatibility toggle |
| JSON vitals | *(all avg fields)* | `respiratoryRate`, `bloodOxygen`, `bodyTemperature`, `bloodPressureSystolic`, `bloodPressureDiastolic`, `bloodGlucose` backward-compat aliases | Aliases are iOS canonical too; keep indefinitely |
| FM | `sleep_light_hours` | `sleep_core_hours` | Keep behind compatibility toggle |
| CSV | `Sleep,Light Sleep` | `Sleep,Core Sleep` | Keep behind compatibility toggle |
| CSV | `Mobility,VO2 Max` | `Activity,Cardio Fitness (VO2 Max)` | Keep behind compatibility toggle |

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
| `sleep_light_hours` | `sleep_core_hours` (or enable Android compatibility keys) |
| `mobility.vo2Max` | `activity.vo2Max` (or enable Android compatibility keys) |

### Type C — users syncing iOS + Android data

**Before parity:** iOS and Android exports had different schema. Plugin dashboards built on
iOS data would not correctly read Android exports, and vice versa.

**After the historical compatibility migration:** Android v4/v5 adopted the field names and format projections required by the then-current Apple-facing Obsidian consumer. This made supported dashboards interoperable, but it did not make the full Apple and Android public schemas or all metric semantics identical. Mixed-device tools must still dispatch on the explicit profile/version and handle platform-only data.

**Note on `sleep_core_hours` vs `sleep_light_hours`:**  
iOS Apple Watch exposes "Core" sleep while Health Connect exposes "Light/NREM2." The historical Android compatibility profile projects the Health Connect value through `sleep_core_hours` for plugin compatibility and may also emit `sleep_light_hours` when compatibility keys are enabled. The proposed unified contract treats this as `mapped_alias`/`alias-review`; future common writers must not claim semantic equivalence until stage definitions, overlap behavior, and owner-day rules are reviewed.

---

## 3) Deprecation timeline

| Phase | Version | When | Action |
|---|---|---|---|
| **Parity release** | v1.3.0 | Now | All P0-P3 parity fixes, iOS-canonical defaults, optional Android compatibility aliases, expanded Health Connect metrics, and explicit Android N/A handling ship |
| **Compatibility toggle** | v1.3.0+ | Ongoing | Users who need pre-parity Android keys can enable them in format settings |
| **Notice** | v1.4.0 | 3 months | In-app message / release notes documenting the iOS-default export contract |

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

• JSON, Markdown, Obsidian Bases, and CSV compatibility projections now use the field names expected by Apple-facing Obsidian tools.
• Obsidian Health.md plugin charts read Android sleep, heart, HRV, oxygen, breathing, and VO2 Max correctly.
• Richer metrics, preview, retry, schedule lookback, daily notes, and individual entries are ready.
• Unsupported Health Connect metrics are omitted from Android exports.

Custom scripts: re-export recent history and switch old Android keys to canonical iOS-compatible names.
```

### Post-release
- [x] Update `docs/export-contract/android-ios-gap-matrix.md` — mark P0-P3 parity phases as implemented
- [ ] File issue in obsidian-health-md plugin repo to align CSV parser labels with iOS standard
  (pre-existing gap: VO2 Max, Basal Energy, Respiratory Rate, Blood Oxygen labels in CSV parser)

---

## 6) Backward compatibility regression test

`app/src/test/java/com/healthmd/export/BackwardCompatibilityTest.kt`

Verifies that duplicate Android compatibility aliases are omitted by default but remain available
through `FormatCustomization.includeLegacyAndroidAliases`. Real Android-native values use the
independent `includeAndroidNativeFields` switch. Persisted settings containing the deprecated
`includeAndroidCompatibilityKeys` field are explicitly migrated to both switches under the frozen
`IOS_V4_FROZEN` profile, preserving their prior byte-level behavior. New local settings use the
additive `ANDROID_ANALYTICAL_V5` profile, while API v1 continues embedding frozen daily schema v4:
- `sleep.lightSleep` alongside `sleep.coreSleep`
- `activity.wheelchairPushes` alongside `activity.pushCount`
- `mobility.vo2Max` alongside `activity.vo2Max`
- `sleep_light_hours` alongside `sleep_core_hours` in frontmatter
- `Sleep,Light Sleep` alongside `Sleep,Core Sleep` in CSV
- `Mobility,VO2 Max` alongside `Activity,Cardio Fitness (VO2 Max)` in CSV

## 7) Analytical v5 additive fidelity

`ANDROID_ANALYTICAL_V5` is a local/exporter profile, not a change to API v1 or plugin daily schema
v4. JSON discloses `schemaProfile=android-analytical-v5` and `schemaVersion=5`; Markdown,
Obsidian Bases, and CSV disclose the same profile in their metadata.

Detailed records retain their existing local date-time fields and add exact source timestamps
(epoch second, nanosecond, and nullable original offset) plus stable source identity. A null source
offset remains null. Nested Health Connect objects without native IDs use deterministic IDs marked
`isSynthetic=true`. Machine CSV timestamps prefer these exact offset-aware values.

All-connected normalized exports add merge provenance: attempted, succeeded, and failed providers;
deterministic category preference; workout provider sources; every workout dedupe/precedence
decision; overlapping providers omitted by the source-preferred policy; and the merge policy ID.
Provider-local workout IDs are provider-qualified and never compared globally. Cross-provider
workouts are deduped only when their type, interval, duration, and indoor semantics match. Markdown
and Obsidian Bases include the complete audit only when all-connected provenance is present.
Single-provider output is unchanged. Raw snapshots do not pass through this merger.

Compatibility-domain percentages are canonical fractions: Health Connect `Percentage.value` is
divided by 100 for SpO2 summaries/samples and body fat. Detailed JSON retains fractions, while the
frozen CSV and Markdown percent displays multiply SpO2 samples by 100. Frozen v4 never emits skin
temperature delta/baseline/sample keys merely because detailed data is enabled; those fields require
the Android-native switch or analytical v5. Analytical workout time series use distinct
`cyclingCadence` (rpm) and `stepsCadence` (steps/min) arrays; frozen v4 retains its historical
`timeSeries.cadence` alias.

Derived route splits interpolate every crossed kilometre boundary, including multiple boundaries in
one sparse route segment. Exact timestamps retain nanoseconds and a shared source offset; when exact
interpolation cannot preserve source timestamp semantics, exact boundary fields remain null. Client
record version zero is retained whenever a client record ID exists. Range exports override daily
weight, height, and resting-heart-rate aggregates with the latest same-day record, matching the
single-day fallback behavior.

### Shipped-profile status and signature guardrail

Both `IOS_V4_FROZEN` and `ANDROID_ANALYTICAL_V5` are shipped profiles and are immutable. Analytical
v5 is treated as shipped even though it is a local/exporter profile rather than the API v1/plugin
daily schema. A public key, JSON type, unit, CSV label/header, Markdown label/table heading, or
Markdown/Bases frontmatter change requires an explicit new profile/version; it must not be folded
into either v4 or v5.

`ExporterSchemaSignatureTest` derives deterministic signatures from the existing Android
`ExportFixtures` plus a fully populated synthetic extension and compares them with:

- `app/src/test/resources/export-contract/signatures/exporter_signature_ios_v4_frozen.json`
- `app/src/test/resources/export-contract/signatures/exporter_signature_android_analytical_v5.json`

Ordinary tests are read-only. Candidate generation is explicit and only supports a newly introduced
profile/version with no existing fixture:

```bash
UPDATE_ANDROID_EXPORTER_SIGNATURES=1 ./gradlew :app:testDebugUnitTest \
  --tests com.healthmd.export.ExporterSchemaSignatureTest
```

The generation run writes candidates under
`$TMPDIR/healthmd-android-exporter-signatures/` and intentionally fails until they are reviewed and
copied into the versioned fixture directory. It refuses to rewrite an existing shipped fixture.

## Shared metric registry (M3)

The canonical deterministic inventory is now `packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json`. It preserves all 106 selectable IDs, 102 unavailable/stale IDs, category and field order, units, feature keys, aliases, and the independent frozen-v4/analytical-v5 projections. Generated regions in `MetricSelection.kt` and `HealthDataFields.kt` are thin adapters; Health Connect record classes, feature detection, permissions, localization, persistence, extraction, and rendering remain Kotlin-owned.

`HealthMdCoreRegistryAdapter` loads the same profile through one coarse UniFFI call for health-free shadow comparison. The registry migration does not change exporter bytes, v4/v5 schema versions, or either immutable signature fixture.
