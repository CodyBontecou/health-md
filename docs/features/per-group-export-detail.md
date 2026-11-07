# Per-category export detail

## Outcome

A user chooses a default detail level for compatibility exports and may override it for individual categories. For example, they can export individual sleep sessions while keeping heart rate, steps, and vitals summarized. Detail choices never change:

- which metrics are selected (metric selection);
- daily summary values, units, or day ownership;
- how files are organized (filenames, folders, formats);
- raw or canonical archives (Android raw snapshots, Apple `healthmd.healthkit_records`).

Capability classifications live in [`product-capabilities.json`](../../packages/contracts/product-capabilities.json) under `export.per-group-detail-selection`, `export.sleep-session-detail`, and `export.compatibility-detail-expansion`. This page records the rationale, the native inventory, and the compatibility decisions behind them.

## Model

| Concept | Android | Apple |
|---|---|---|
| Default level | `ExportSettings.includeGranularData` | `compatibilityDetail` (`summary` / `selected_time_series`) |
| Per-category overrides | `ExportSettings.detailOverrides` | `compatibilityDetailOverrides` |
| Resolved selection | `ExportDetailSelection` | `AppleExportDetailPolicy.includesSelectedTimeSeries(for:)` |

The category IDs are shared wire values: `sleep`, `activity`, `heart`, `vitals`, `nutrition`, `mobility`, `reproductive_health`, `mindfulness`, `workouts`, `body`. The choice IDs are `summary`, `sessions`, and `detailed`.

- **Summary:** daily aggregates only.
- **Sessions:** individual source sessions without nested samples. Sleep only, and Android only.
- **Detailed:** every detail section the category supports, including nested samples such as sleep stages.

Each platform offers only the choices it can honor. Missing overrides reproduce the previous global setting exactly.

### Successor profiles

Some records have no place in the shipped grammars. An explicit **Detailed** override for such a category selects an additive successor profile (`export.compatibility-detail-expansion`):

| Platform | Selected by an explicit Detailed override for | Profile | Adds |
|---|---|---|---|
| Apple | sleep, activity, nutrition, mobility, reproductive_health, mindfulness, body, vitals | `apple-v12` (`schema_version: 12`, `schema_profile: apple-v12`) | `<category>.detailSamples`; for sleep, per-stage `sourceUUID`/`source`/`sourceName` on `sleepStages` |
| Android | activity, nutrition, body (analytical profile only) | `android-analytical-v7` (`schemaVersion: 7`, `schemaProfile: android-analytical-v7`) | per-record interval arrays |

- The uniform default (Detailed Time-Series / Lossless on Apple, `includeGranularData` on Android) never selects a successor, so those exports keep apple-v8 / analytical v5 bytes exactly. Heart and workout overrides also keep the shipped profile. A Sleep override selects apple-v12 only to attribute each stage to its source; sleep has no `detailSamples`.
- Frozen v4 never upgrades. Morning ends keeps apple-v11 / android-sleep-v6 and neither captures nor writes the successor arrays.
- Daily notes, scoped direct notes, rollups, the Apple data dictionary, and Android Obsidian Bases keep the shipped identity because they carry no sample arrays. Apple Markdown and Bases frontmatter of a v12 day carry the v12 header.
- Both successors are written only by the native writers. The Rust engine never renders detailed daily records (Apple refuses detail in the Rust planner; Android v7 resolves to the Kotlin writers and refuses Rust pins), so no shared-core registry, UniFFI, CLI, or direct-protocol profile changed.
- Each entry is one source record: source start (and end, for intervals), unit, and identity are kept. Nothing is interpolated, resampled, or deduplicated.
- **Sample sums are not daily totals.** Summing a day's entries can give more or less than its summary value, and both are correct:
  - *More:* overlapping sources (for example a phone and a watch) each keep their records, while the summary is deduplicated across sources.
  - *Less:* a record belongs only to the day it starts, while the summary counts the part of every record that overlaps the day. A long record that starts before local midnight, such as a provider's hourly or daily step block, appears in the previous day's array but still contributes to this day's total.
  - Use the summary value for totals. Use the entries for timing, source, and record identity; to reproduce a total, read the neighbouring days' entries and clip each interval to the day.
- Connected Macs must advertise `supportsAppleV12DetailExpansion` before receiving a v12 job (including a Detailed sleep override) or an override outside sleep/heart/vitals/workouts.
- Once any override selects apple-v12, every expansion category that resolves to Detailed, including through the default level, writes `detailSamples`. A user who wants only attributed sleep stages should keep the default at Summary.

## Native capability inventory

The four detail columns are:

- **Summary:** daily aggregates.
- **Records:** individual events or sessions.
- **Samples:** timestamped points or intervals.
- **Nested:** detail inside a record.

In the tables:

- **"Exported"** means the compatibility writer can emit that detail today, gated by its category.
- **"Source only"** means the native API exposes it but no compatibility projection exists yet. Whether that is "not implemented" or "not exposed by the source" is stated explicitly.

### Android (Health Connect)

Health Connect reads are paged (`pageToken`, 1,000 per page), run in 7-day chunks when any category requests detail and 30-day chunks otherwise, and rethrow cancellation. Timestamps keep source instants and zone offsets (`ExactSourceTimestamp`). Synthetic child IDs are marked as synthetic.

| Category | Health Connect types | Summary | Records | Samples / intervals | Nested | Notes |
|---|---|---|---|---|---|---|
| sleep | `SleepSessionRecord` | total, stages, bedtime/wake envelope | **Exported**: `sleepSessions` (JSON); Markdown session table | — | **Exported**: `sleepStages` (stage intervals) | Sessions are always read, because summaries need them. Stages are emitted only for `detailed`. The Markdown table appears only for an explicit sleep override. |
| activity | `StepsRecord`, `ActivityIntensityRecord`, calories, distance, floors, elevation, wheelchair pushes | daily aggregates | — | **Exported**: `stepSamples` (intervals; `exactEndTime` kept), `activityIntensity`; v7 adds `activeCaloriesSamples`, `totalCaloriesSamples`, `distanceSamples`, `floorsSamples`, `elevationSamples` | — | The v7 arrays are written only by `android-analytical-v7`. Wheelchair pushes remain source-only. |
| heart | `HeartRateRecord`, `HeartRateVariabilityRmssdRecord`, `RestingHeartRateRecord` | avg/min/max, RMSSD, resting | — | **Exported**: `heartRateSamples` (series children), `hrvSamples` | — | Resting heart rate records are summarized only (latest). RMSSD stays distinct from Apple SDNN. |
| vitals | blood pressure, SpO₂, glucose, respiratory rate, body/basal/skin temperature | avg/min/max | — | **Exported**: one sample array per type, plus `skinTemperatureDeltas` (native fields) | — | Blood-pressure records are read only when detail is requested or summaries need them. |
| nutrition | `NutritionRecord`, `HydrationRecord` | daily totals | **Exported**: `meals` | v7: **Exported** `hydrationSamples` (liters) | — | CSV meal rows always exist; detail switches to exact machine timestamps. |
| mobility | speed, cadence, power, `Vo2MaxRecord` | averages | — | — | **Exported**: `vo2MaxMeasurementMethod` | Mobility series are exported only as workout detail. |
| reproductive_health | menstruation period/flow, cervical mucus, ovulation, intermenstrual bleeding, sexual activity | daily values | **Exported**: `menstruationPeriods` | — | — | |
| mindfulness | `MindfulnessSessionRecord` | minutes, count | **Exported**: `sessions` | — | — | |
| workouts | `ExerciseSessionRecord`, `ExerciseRoute`, correlated series | per-workout totals | always (laps/segments/splits) | **Exported**: `route`, `timeSeries` (HR, speed, cadence, power, elevation) | exact intervals (v5) | Route reads require per-session consent. Consent is requested only when workouts are selected. |
| body | weight, height, fat, lean/bone/water mass | latest/avg | — | v7: **Exported** `weightSamples`, `heightSamples`, `bodyFatSamples` (fraction 0–1), `leanBodyMassSamples`, `boneMassSamples`, `bodyWaterMassSamples` (instants, no end) | — | Governed by the `body` group. |
| planned workouts / medical resources | `PlannedExerciseSessionRecord`, PHR | records always | — | — | — | Not governed by detail. Plan exact intervals follow `workouts`. |

### Apple (HealthKit)

HealthKit queries use `HKSampleQueryDescriptor` with no limit and `CancellationError` propagation. Per-category failures become `partialFailures`. Compatibility samples are owned by their start date; sleep is window-clipped (noon to noon, or wake date). The canonical archive (Lossless) independently preserves every selected source record, with its UUID, provenance and metadata.

| Category | HealthKit types | Summary | Records | Samples / intervals | Nested | Notes |
|---|---|---|---|---|---|---|
| sleep | `sleepAnalysis` category samples | union-based totals, stages, bedtime/wake | **Unavailable as sessions**: HealthKit has no session object | **Exported**: `sleepStages` (category intervals, window-clipped); v12 adds `sourceUUID`, `source` (bundle identifier) and `sourceName` per stage | — | Choices are Summary and Detailed. Overlapping sources (for example a watch and a bed sensor) each keep their stages; totals stay deduplicated. A clipped stage keeps the UUID of the sample it was cut from. Wake-date mode merges intervals for ownership internally; that derivation is not exported as source sessions. |
| heart | heart rate, HRV SDNN, resting, walking, recovery, AFib burden | stats / most recent | — | **Exported**: `heartRateSamples`, `hrvSamples` | — | |
| vitals | respiratory rate, SpO₂, BP correlations, glucose, temperatures, spirometry | stats / most recent | — | **Exported**: SpO₂, glucose, respiratory, BP samples; v12 adds temperature and spirometry `detailSamples` | — | Inhaler usage and electrodermal activity remain source-only (canonical archive). |
| workouts | `HKWorkout`, events, route, associated series | per-workout | always | **Exported**: laps, splits, route, `timeSeries` | — | Follows the `workouts` override (Summary or Detailed). Summary keeps per-workout totals and drops laps, splits, route and series. Capture always reads workout detail; the sanitizer removes it. |
| activity, nutrition, mobility, mindfulness, reproductive, body | quantity/category samples | statistics | — | v12: **Exported** `detailSamples` (one entry per sample: `metric`, `healthKitType`, `timestamp`, `endDate`, `value`+`unit` or `categoryValue`, `sourceUUID`, `source`, `sourceName`) | — | Units are the summary units; percentages are fractions 0–1 labelled `%`, as in the canonical archive. Mindful sessions are category intervals. |
| hearing, symptoms, medications, other | quantity/category samples | statistics | source-only (canonical archive) | source-only (canonical archive) | — | No compatibility projection. Lossless exposes the native records. |

## Capture

Capture reads only the detail the export writes, plus detail that individual-entry tracking needs internally:

- Android: `ExportSettings.captureDetailSelection()`.
- Apple: per-category `includesSelectedTimeSeries(for:)` in `HealthKitManager`.

Tracking-only detail is never written to compatibility files.

When a category's summary itself requires source records, those records are still read; the summary does not depend on the detail choice. Examples are sleep sessions, HRV records, and vitals records behind min/max values.

## Formats

| Format | Behavior |
|---|---|
| JSON | Under the shipped profiles, emits a subset of the existing optional detail arrays, per category; frozen Android v4 / analytical v5 and Apple v8 grammars are unchanged. The successor arrays appear only in apple-v12 / android-analytical-v7 records. |
| CSV | Emits a subset of the existing detail rows. Sleep sessions are not added as CSV rows: adding them would change the frozen row grammar and needs a reviewed profile. apple-v12 files add a seventh `Source` header column, filled on sleep-stage and `Detail Sample` rows with the source name (or bundle identifier); other rows leave it empty. |
| Markdown | Existing sample tables follow their category. An explicit sleep override (Sessions or Detailed, Android) adds a session table with full local date, time, source offset, and an elapsed duration that is safe across DST. The previous global setting keeps byte-identical output. |
| Obsidian Bases | Frontmatter only. Unchanged. |
| API / gateway / direct-device generated files | Use the same resolved selection as file exports. |

## Compatibility decisions

- **Settings migration.** None required: absent overrides resolve to the previous global value. New writes keep explicit choices even when they equal the default, so a later default change never moves them.
- **Durable jobs.** Scheduled retries, resumed jobs and profiles persist overrides inside the frozen settings snapshot.
  - Android: `AndroidExportSettingsSnapshot.detailOverrides`. It is nullable, omitted when empty, normalized, and validated.
  - Apple: `ExportSettingsSnapshot.compatibilityDetailOverrides`. It is encoded only when non-empty, and unknown values fail decoding.
  - Existing snapshot bytes and fingerprints are unchanged. Older builds reject Android snapshots that carry overrides (fail closed).
  - Older Macs are refused before transfer by the `supportsPerGroupExportDetail` capability.
- **Shared Setup v2.** This contract is byte-frozen and cannot represent overrides. Setup files carry the default level only. The native fields are classified `prohibited` in the field-coverage inventories. Portable overrides require a reviewed Shared Setup successor.
- **Public schemas.** The shipped profiles and their signature fixtures are unchanged. The successors have their own contracts and fixtures (`healthmd.health_data.apple_detail` v12, `healthmd.health_data.android_analytical_detail` v7 in the [contracts manifest](../../packages/contracts/manifest.json)). No direct-protocol version or CLI option changed; the CLI and direct protocols expose only the separate summary/lossless archive scope.
- **Android sleep aggregates.** The frozen v4/v5 behavior is unchanged: totals use whole-session duration, and the bedtime/wake pair spans disconnected sessions. Correcting either requires a new reviewed profile; see the open follow-up in the capability inventory.

## Remaining work

- Successor detail under Morning ends (a reviewed successor of apple-v11 / android-sleep-v6).
- Folding the successor arrays into the [unified v9 proposal](../../packages/contracts/proposals/unified-health-data-v9/contract.md).
- Shared Setup successor field for portable overrides.
- CSV sleep-session rows and Bases session counts behind a reviewed profile.
- Device verification of the new settings UI on both platforms.
