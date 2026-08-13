# Unified v9 metric mapping ledger

**Status:** proposal evidence; no production mapping is approved by this document alone

**Registry source:** `packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json`

## Rules

A production v9 writer may emit only rows whose status becomes `approved`. Approval requires reviewed source selectors, source reducers, common statistic, canonical unit, owner-day behavior, provenance, missingness, and cross-platform fixtures.

Current statuses:

- `candidate`: both platforms are backed and the registry records exact-or-unavailable equivalence, but the complete v9 mapping has not been approved.
- `alias-review`: both platforms are backed, but at least one side maps through a historical alias. Name similarity is not semantic proof.
- `distinct`: the source facts intentionally use different semantic identities.
- `platform`: retain only under the matching platform section/archive until separately reviewed.

Canonical unit IDs must replace display abbreviations. Where the current registry units differ, this ledger calls out required normalization rather than selecting a value silently.

## Initial exact-or-unavailable candidates

| Unified semantic ID | Proposed statistic | Canonical unit/review note | Status |
|---|---|---|---|
| `sleep_total` | `duration_sum` | `hour`; reconcile Android overlapping-session journal semantics | candidate |
| `sleep_deep` | `duration_sum` | `hour`; reconcile Android overlapping-session journal semantics | candidate |
| `sleep_rem` | `duration_sum` | `hour`; reconcile Android overlapping-session journal semantics | candidate |
| `sleep_awake` | `duration_sum` | `hour`; reconcile Android overlapping-session journal semantics | candidate |
| `sleep_in_bed` | `duration_sum` | `hour`; reconcile Android overlapping-session journal semantics | candidate |
| `steps` | `sum` | `count` | candidate |
| `flights_climbed` | `sum` | `count` | candidate |
| `swimming_strokes` | `sum` | normalize `strokes`/`count` to `count` after selector review | candidate |
| `vo2_max` | `average` | `milliliter_per_kilogram_minute` | candidate |
| `respiratory_rate` | `average` | normalize erroneous/display `bpm` alias to `breath_per_minute` | candidate |
| `blood_oxygen` | `average` | choose explicit `fraction_0_1` or `percent_0_100`; never infer by magnitude | candidate |
| `blood_glucose` | `average` | `milligram_per_deciliter` | candidate |
| `weight` | `latest` | `kilogram` | candidate |
| `height` | `latest` | normalize Apple `centimeter` and Android `meter` to `meter` | candidate |
| `bmi` | `latest` | `kilogram_per_square_meter`; Android empty display unit is not canonical | candidate |
| `body_fat` | `latest` | choose explicit `fraction_0_1` or `percent_0_100` | candidate |
| `walking_speed` | `average` | normalize Apple `kilometer_per_hour` and Android `meter_per_second` to `meter_per_second` | candidate |
| `running_speed` | `average` | normalize to `meter_per_second` | candidate |
| `running_power` | `average` | `watt` | candidate |
| `cycling_distance` | `sum` | `kilometer` or `meter`; choose once for v9 | candidate |
| `cycling_cadence` | `average` | `revolution_per_minute`; never use ambiguous frozen cadence alias | candidate |
| `dietary_energy` | `sum` | `kilocalorie` | candidate |
| `vitamin_a` | `sum` | normalize `µg`/`mcg` to `microgram` | candidate |
| `vitamin_b6` | `sum` | `milligram` | candidate |
| `vitamin_b12` | `sum` | `microgram` | candidate |
| `vitamin_c` | `sum` | `milligram` | candidate |
| `vitamin_d` | `sum` | `microgram` | candidate |
| `vitamin_e` | `sum` | `milligram` | candidate |
| `vitamin_k` | `sum` | `microgram` | candidate |
| `thiamin` | `sum` | `milligram` | candidate |
| `riboflavin` | `sum` | `milligram` | candidate |
| `niacin` | `sum` | `milligram` | candidate |
| `folate` | `sum` | `microgram` | candidate |
| `biotin` | `sum` | `microgram` | candidate |
| `pantothenic_acid` | `sum` | `milligram` | candidate |
| `calcium` | `sum` | `milligram` | candidate |
| `iron` | `sum` | `milligram` | candidate |
| `potassium` | `sum` | `milligram` | candidate |
| `magnesium` | `sum` | `milligram` | candidate |
| `phosphorus` | `sum` | `milligram` | candidate |
| `zinc` | `sum` | `milligram` | candidate |
| `selenium` | `sum` | `microgram` | candidate |
| `copper` | `sum` | `milligram` | candidate |
| `manganese` | `sum` | `milligram` | candidate |
| `chromium` | `sum` | `microgram` | candidate |
| `molybdenum` | `sum` | `microgram` | candidate |
| `chloride` | `sum` | `milligram` | candidate |
| `iodine` | `sum` | `microgram` | candidate |
| `mindful_minutes` | `duration_sum` | `minute` | candidate |
| `mindful_sessions` | `count` | normalize `sessions`/`count` to `count` | candidate |
| `menstrual_flow` | source-defined | categorical mapping and owner-day behavior require review | candidate |
| `sexual_activity` | `count` | categorical/record mapping requires review | candidate |
| `ovulation_test` | `latest` | categorical vocabulary requires review | candidate |
| `cervical_mucus` | `latest` | categorical vocabulary requires review | candidate |
| `intermenstrual_bleeding` | `count` | event mapping requires review | candidate |
| `workouts` | `count` | shared count only; structured workout detail remains platform-specific until separately mapped | candidate |

## Alias-review candidates

| Unified semantic ID | Risk requiring review | Status |
|---|---|---|
| `sleep_core` | Apple core sleep versus Android light sleep and overlapping-session behavior | alias-review |
| `distance_walking_running` | Android generic distance may include different activity scope | alias-review |
| `distance_swimming` | source selector and aggregation scope | alias-review |
| `distance_wheelchair` | source selector and wheelchair semantics | alias-review |
| `distance_downhill_snow` | activity classification mapping | alias-review |
| `active_energy` | calorie/kilocalorie normalization and provider overlap | alias-review |
| `basal_energy` | calorie/kilocalorie normalization and source aggregation | alias-review |
| `exercise_time` | Apple exercise ring semantics versus Android exercise minutes | alias-review |
| `push_count` | normalize `pushes`/`count`; source semantics | alias-review |
| `heart_rate_avg` | source interval and SDK aggregation | alias-review |
| `heart_rate_min` | source interval and SDK aggregation | alias-review |
| `heart_rate_max` | source interval and SDK aggregation | alias-review |
| `resting_heart_rate` | platform-derived statistic differences | alias-review |
| `walking_heart_rate` | selector/derivation differences | alias-review |
| `body_temperature` | normalize `°C`/`°`; reject unitless interpretation | alias-review |
| `basal_body_temperature` | normalize `°C`/`°`; reject unitless interpretation | alias-review |
| `blood_pressure_systolic` | paired-record identity and source aggregation | alias-review |
| `blood_pressure_diastolic` | paired-record identity and source aggregation | alias-review |
| `lean_body_mass` | source selector and `kilogram` normalization | alias-review |
| `cycling_power` | average versus other workout power statistics | alias-review |
| `dietary_protein` | naming only; verify source aggregation | alias-review |
| `dietary_carbs` | naming only; verify source aggregation | alias-review |
| `dietary_fat` | naming only; verify source aggregation | alias-review |
| `dietary_fat_saturated` | naming only; verify source aggregation | alias-review |
| `dietary_fat_mono` | naming only; verify source aggregation | alias-review |
| `dietary_fat_poly` | naming only; verify source aggregation | alias-review |
| `dietary_cholesterol` | naming only; verify source aggregation | alias-review |
| `dietary_fiber` | naming only; verify source aggregation | alias-review |
| `dietary_sugar` | naming only; verify source aggregation | alias-review |
| `dietary_sodium` | naming only; verify source aggregation | alias-review |
| `dietary_water` | liter/milliliter source normalization | alias-review |
| `dietary_caffeine` | source aggregation | alias-review |

## Explicit distinct identities

| Source/platform identity | Unified handling | Status |
|---|---|---|
| Apple `hrv` / HealthKit SDNN | map only as `heart_rate_variability_sdnn` after approval | distinct |
| Android `android.hrv_rmssd` / Health Connect RMSSD | map only as `heart_rate_variability_rmssd` after approval | distinct |
| WHOOP `hrv_rmssd_ms` | retain under typed WHOOP provider section | distinct |
| Android `android.steps_cadence` | retain distinct from cycling cadence | distinct |
| Android `android.skin_temperature` | retain platform-specific until baseline/delta/absolute semantics are mapped | distinct |
| Android `android.total_calories` | retain platform-specific until active/basal overlap is defined | distinct |
| Android `android.elevation_gained` | retain platform-specific until route/workout scope is defined | distinct |
| Android `android.activity_intensity_minutes` | retain platform-specific | distinct |
| Android `android.body_water_mass` | retain platform-specific | distinct |
| Android `android.bone_mass` | retain platform-specific | distinct |
| Android native nutrition identities | retain platform-specific until exact common identities are approved | distinct |
| Android menstruation period/day identities | retain platform-specific until event/range semantics are approved | distinct |
| Android planned workouts and medical resources | retain under Android platform data | distinct |

## Platform-only data

Apple-only HealthKit types, clinical records/documents, medications, state of mind, assessments, ECG/heartbeat series, hearing, vision, characteristics, attachments, and canonical HealthKit archive remain under `platform.apple`/`healthmd.healthkit_records` v1.

Android-native exact record timestamps and offsets, deterministic synthetic IDs, all-connected merge audit, workout dedupe decisions, route splits, source-specific detailed records, Raw API Snapshots, planned workouts, and medical resources remain under `platform.android` or their separate raw contracts.

Absence from shared metrics is not a statement that the data is unsupported or unimportant. It is a refusal to claim unreviewed semantic equivalence.
