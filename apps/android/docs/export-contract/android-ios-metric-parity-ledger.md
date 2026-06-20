# Android ↔ iOS Metric Parity Ledger

**Status:** maintained parity source for the Android metric picker/catalog
**Last updated:** 2026-06-20
**iOS source:** `/Users/codybontecou/projects/health-md/app/HealthMd/Shared/Models/HealthMetrics.swift`
**Android source:** `app/src/main/java/com/healthmd/domain/model/MetricSelection.kt`

This ledger explains every iOS HealthMetrics.swift metric id against the Android catalog. Android uses Health Connect `androidx.health.connect:connect-client:1.2.0-alpha02`; metrics that Health Connect does not expose are intentionally non-selectable and are listed in `HealthMetrics.unavailableMetrics` with user-facing reasons.

## Product stance for unavailable metrics

- Android does not fabricate empty export fields for HealthKit-only or Health Connect-unavailable records. Exporters omit those fields unless real Android data exists.
- The metric picker may mention representative unavailable metrics, but unavailable rows are not toggleable and stale persisted ids are ignored by `MetricSelectionState`.
- When Health Connect adds a missing record, move the row from `health-connect-unavailable` to `supported` or `mapped/alias`, add fetch/export support, and update this ledger plus `android-phase3-apple-exclusive.md`.

## Status values

- `supported` — Android has a selectable metric with the same id.
- `mapped/alias` — Android has equivalent data under a different selector id or within workout details.
- `health-connect-unavailable` — the audited Health Connect API does not expose an equivalent record.
- `apple-exclusive` — The metric depends on Apple Watch, HealthKit State of Mind, or Apple-specific HealthKit derivation.
- `android-only` — Android supports the metric but there is no matching iOS HealthMetrics.swift picker id.

## iOS metric parity table

| iOS metric id | iOS category | Android status | Android metric id(s) | Notes |
|---|---|---|---|---|
| sleep_total | Sleep | supported | sleep_total | Android uses the same metric id. |
| sleep_bedtime | Sleep | mapped/alias | sleep_total,sleep_in_bed | Android exports sleep session start when sleep_total or sleep_in_bed is selected. |
| sleep_wake | Sleep | mapped/alias | sleep_total,sleep_in_bed | Android exports sleep session end when sleep_total or sleep_in_bed is selected. |
| sleep_deep | Sleep | supported | sleep_deep | Android uses the same metric id. |
| sleep_rem | Sleep | supported | sleep_rem | Android uses the same metric id. |
| sleep_core | Sleep | mapped/alias | sleep_light | Health Connect light sleep maps to iOS core sleep semantics. |
| sleep_awake | Sleep | supported | sleep_awake | Android uses the same metric id. |
| sleep_in_bed | Sleep | supported | sleep_in_bed | Android uses the same metric id. |
| steps | Activity | supported | steps | Android uses the same metric id. |
| distance_walking_running | Activity | mapped/alias | distance | Android distance is walking/running distance. |
| distance_swimming | Activity | mapped/alias | swimming_distance | Android uses the swimming_distance selector. |
| distance_wheelchair | Activity | mapped/alias | wheelchair_distance | Android derives wheelchair distance from wheelchair sessions plus overlapping DistanceRecord data. |
| distance_downhill_snow | Activity | mapped/alias | downhill_snow_distance | Android derives snow-sport distance from snow sessions plus overlapping DistanceRecord data. |
| active_energy | Activity | mapped/alias | active_calories | Android uses active_calories. |
| basal_energy | Activity | mapped/alias | basal_calories | Android uses basal_calories. |
| exercise_time | Activity | mapped/alias | exercise_minutes | Android uses exercise_minutes. |
| stand_time | Activity | health-connect-unavailable | stand_time | Apple Stand Time has no Health Connect 1.1.0-beta02 equivalent record. |
| move_time | Activity | health-connect-unavailable | move_time | Apple Move Time has no Health Connect 1.1.0-beta02 equivalent record; Android exports Exercise Minutes instead. |
| flights_climbed | Activity | supported | flights_climbed | Android uses the same metric id. |
| swimming_strokes | Activity | supported | swimming_strokes | Android uses the same metric id. |
| push_count | Activity | mapped/alias | wheelchair_pushes | Android uses wheelchair_pushes. |
| vo2_max | Activity | supported | vo2_max | Android uses the same metric id. |
| physical_effort | Activity | health-connect-unavailable | physical_effort | Health Connect 1.1.0-beta02 does not expose Apple physical-effort records. |
| heart_rate_avg | Heart | mapped/alias | avg_hr | Android uses avg_hr. |
| heart_rate_min | Heart | mapped/alias | min_hr | Android uses min_hr. |
| heart_rate_max | Heart | mapped/alias | max_hr | Android uses max_hr. |
| resting_heart_rate | Heart | mapped/alias | resting_hr | Android uses resting_hr. |
| walking_heart_rate | Heart | mapped/alias | walking_hr | Android derives this from walking workouts and heart-rate samples. |
| hrv | Heart | supported | hrv | Android uses the same metric id. |
| heart_rate_recovery | Heart | apple-exclusive | heart_rate_recovery | Apple Watch-derived recovery metric; Health Connect does not expose a matching daily aggregate. |
| afib_burden | Heart | apple-exclusive | afib_burden | Apple Watch-derived atrial fibrillation burden; Health Connect has no equivalent record. |
| respiratory_rate | Respiratory | supported | respiratory_rate | Android uses the same metric id. |
| blood_oxygen | Respiratory | supported | blood_oxygen | Android uses the same metric id. |
| forced_vital_capacity | Respiratory | health-connect-unavailable | forced_vital_capacity | Health Connect 1.1.0-beta02 has no respiratory volume record equivalent. |
| fev1 | Respiratory | health-connect-unavailable | fev1 | Health Connect 1.1.0-beta02 has no spirometry FEV1 record equivalent. |
| peak_expiratory_flow | Respiratory | health-connect-unavailable | peak_expiratory_flow | Health Connect 1.1.0-beta02 has no peak-flow record equivalent. |
| inhaler_usage | Respiratory | health-connect-unavailable | inhaler_usage | Health Connect 1.1.0-beta02 has no inhaler-use record equivalent. |
| body_temperature | Vitals | mapped/alias | body_temp | Android uses body_temp. |
| basal_body_temperature | Vitals | mapped/alias | basal_body_temp | Android uses basal_body_temp. |
| wrist_temperature | Vitals | apple-exclusive | wrist_temperature | Apple Watch wrist-temperature hardware; Android exports Skin Temperature Delta when Health Connect provides it. |
| blood_pressure_systolic | Vitals | mapped/alias | bp_systolic | Android uses bp_systolic. |
| blood_pressure_diastolic | Vitals | mapped/alias | bp_diastolic | Android uses bp_diastolic. |
| blood_glucose | Vitals | supported | blood_glucose | Android uses the same metric id. |
| electrodermal_activity | Vitals | apple-exclusive | electrodermal_activity | Apple Watch electrodermal-activity hardware; Health Connect has no equivalent record. |
| weight | Body Measurements | supported | weight | Android uses the same metric id. |
| height | Body Measurements | supported | height | Android uses the same metric id. |
| bmi | Body Measurements | supported | bmi | Android uses the same metric id. |
| body_fat | Body Measurements | supported | body_fat | Android uses the same metric id. |
| lean_body_mass | Body Measurements | mapped/alias | lean_mass | Android uses lean_mass. |
| waist_circumference | Body Measurements | health-connect-unavailable | waist_circumference | Health Connect 1.1.0-beta02 has no waist-circumference body-measurement record. |
| walking_speed | Mobility | supported | walking_speed | Android uses the same metric id. |
| walking_step_length | Mobility | health-connect-unavailable | walking_step_length | Health Connect 1.1.0-beta02 does not expose this walking-mobility metric. |
| walking_double_support | Mobility | health-connect-unavailable | walking_double_support | Health Connect 1.1.0-beta02 does not expose this walking-mobility metric. |
| walking_asymmetry | Mobility | health-connect-unavailable | walking_asymmetry | Health Connect 1.1.0-beta02 does not expose this walking-mobility metric. |
| walking_steadiness | Mobility | health-connect-unavailable | walking_steadiness | Health Connect 1.1.0-beta02 does not expose walking steadiness. |
| stair_ascent_speed | Mobility | health-connect-unavailable | stair_ascent_speed | Health Connect 1.1.0-beta02 does not expose stair-speed metrics. |
| stair_descent_speed | Mobility | health-connect-unavailable | stair_descent_speed | Health Connect 1.1.0-beta02 does not expose stair-speed metrics. |
| six_minute_walk | Mobility | health-connect-unavailable | six_minute_walk | Health Connect 1.1.0-beta02 does not expose a six-minute-walk metric. |
| running_speed | Mobility | supported | running_speed | Android uses the same metric id. |
| running_stride_length | Mobility | health-connect-unavailable | running_stride_length | Health Connect 1.1.0-beta02 does not expose this running-dynamics metric. |
| running_ground_contact | Mobility | health-connect-unavailable | running_ground_contact | Health Connect 1.1.0-beta02 does not expose this running-dynamics metric. |
| running_vertical_oscillation | Mobility | health-connect-unavailable | running_vertical_oscillation | Health Connect 1.1.0-beta02 does not expose this running-dynamics metric. |
| running_power | Mobility | supported | running_power | Android uses the same metric id. |
| cycling_distance | Cycling | supported | cycling_distance | Android uses the same metric id. |
| cycling_speed | Cycling | mapped/alias | workouts | Health Connect speed is exported inside workout details; no standalone daily cycling-speed selector yet. |
| cycling_power | Cycling | mapped/alias | power_avg,power_max | Android exposes Health Connect PowerRecord via power_avg and power_max. |
| cycling_cadence | Cycling | supported | cycling_cadence | Android uses the same metric id. |
| cycling_ftp | Cycling | health-connect-unavailable | cycling_ftp | Health Connect 1.1.0-beta02 does not expose functional threshold power. |
| dietary_energy | Nutrition | supported | dietary_energy | Android uses the same metric id. |
| dietary_protein | Nutrition | mapped/alias | protein | Android uses protein. |
| dietary_carbs | Nutrition | mapped/alias | carbs | Android uses carbs. |
| dietary_fat | Nutrition | mapped/alias | fat | Android uses fat. |
| dietary_fat_saturated | Nutrition | mapped/alias | saturated_fat | Android uses saturated_fat. |
| dietary_fat_mono | Nutrition | mapped/alias | monounsaturated_fat | Android uses monounsaturated_fat. |
| dietary_fat_poly | Nutrition | mapped/alias | polyunsaturated_fat | Android uses polyunsaturated_fat. |
| dietary_cholesterol | Nutrition | mapped/alias | cholesterol | Android uses cholesterol. |
| dietary_fiber | Nutrition | mapped/alias | fiber | Android uses fiber. |
| dietary_sugar | Nutrition | mapped/alias | sugar | Android uses sugar. |
| dietary_sodium | Nutrition | mapped/alias | sodium | Android uses sodium. |
| dietary_water | Nutrition | mapped/alias | water | Android uses water. |
| dietary_caffeine | Nutrition | mapped/alias | caffeine | Android uses caffeine. |
| vitamin_a | Vitamins | supported | vitamin_a | Android uses the same metric id. |
| vitamin_b6 | Vitamins | supported | vitamin_b6 | Android uses the same metric id. |
| vitamin_b12 | Vitamins | supported | vitamin_b12 | Android uses the same metric id. |
| vitamin_c | Vitamins | supported | vitamin_c | Android uses the same metric id. |
| vitamin_d | Vitamins | supported | vitamin_d | Android uses the same metric id. |
| vitamin_e | Vitamins | supported | vitamin_e | Android uses the same metric id. |
| vitamin_k | Vitamins | supported | vitamin_k | Android uses the same metric id. |
| thiamin | Vitamins | supported | thiamin | Android uses the same metric id. |
| riboflavin | Vitamins | supported | riboflavin | Android uses the same metric id. |
| niacin | Vitamins | supported | niacin | Android uses the same metric id. |
| folate | Vitamins | supported | folate | Android uses the same metric id. |
| biotin | Vitamins | supported | biotin | Android uses the same metric id. |
| pantothenic_acid | Vitamins | supported | pantothenic_acid | Android uses the same metric id. |
| calcium | Minerals | supported | calcium | Android uses the same metric id. |
| iron | Minerals | supported | iron | Android uses the same metric id. |
| potassium | Minerals | supported | potassium | Android uses the same metric id. |
| magnesium | Minerals | supported | magnesium | Android uses the same metric id. |
| phosphorus | Minerals | supported | phosphorus | Android uses the same metric id. |
| zinc | Minerals | supported | zinc | Android uses the same metric id. |
| selenium | Minerals | supported | selenium | Android uses the same metric id. |
| copper | Minerals | supported | copper | Android uses the same metric id. |
| manganese | Minerals | supported | manganese | Android uses the same metric id. |
| chromium | Minerals | supported | chromium | Android uses the same metric id. |
| molybdenum | Minerals | supported | molybdenum | Android uses the same metric id. |
| chloride | Minerals | supported | chloride | Android uses the same metric id. |
| iodine | Minerals | supported | iodine | Android uses the same metric id. |
| headphone_audio | Hearing | health-connect-unavailable | headphone_audio | Health Connect 1.1.0-beta02 does not expose headphone audio exposure records. |
| environmental_audio | Hearing | health-connect-unavailable | environmental_audio | Health Connect 1.1.0-beta02 does not expose environmental sound exposure records. |
| mindful_minutes | Mindfulness | supported | mindful_minutes | Android uses the same metric id. |
| mindful_sessions | Mindfulness | supported | mindful_sessions | Android uses the same metric id. |
| state_of_mind_entries | Mindfulness | apple-exclusive | state_of_mind_entries | HealthKit State of Mind is iOS 17+/Apple-platform specific and is not exposed by Health Connect. |
| daily_mood | Mindfulness | apple-exclusive | daily_mood | HealthKit State of Mind is iOS 17+/Apple-platform specific and is not exposed by Health Connect. |
| average_valence | Mindfulness | apple-exclusive | average_valence | HealthKit State of Mind mood valence is iOS 17+/Apple-platform specific and is not exposed by Health Connect. |
| momentary_emotions | Mindfulness | apple-exclusive | momentary_emotions | HealthKit State of Mind is iOS 17+/Apple-platform specific and is not exposed by Health Connect. |
| menstrual_flow | Reproductive Health | supported | menstrual_flow | Android uses the same metric id. |
| sexual_activity | Reproductive Health | supported | sexual_activity | Android uses the same metric id. |
| ovulation_test | Reproductive Health | supported | ovulation_test | Android uses the same metric id. |
| cervical_mucus | Reproductive Health | supported | cervical_mucus | Android uses the same metric id. |
| intermenstrual_bleeding | Reproductive Health | supported | intermenstrual_bleeding | Android uses the same metric id. |
| symptom_headache | Symptoms | health-connect-unavailable | symptom_headache | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_fatigue | Symptoms | health-connect-unavailable | symptom_fatigue | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_nausea | Symptoms | health-connect-unavailable | symptom_nausea | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_dizziness | Symptoms | health-connect-unavailable | symptom_dizziness | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_mood_changes | Symptoms | health-connect-unavailable | symptom_mood_changes | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_sleep_changes | Symptoms | health-connect-unavailable | symptom_sleep_changes | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_appetite_changes | Symptoms | health-connect-unavailable | symptom_appetite_changes | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_hot_flashes | Symptoms | health-connect-unavailable | symptom_hot_flashes | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_chills | Symptoms | health-connect-unavailable | symptom_chills | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_fever | Symptoms | health-connect-unavailable | symptom_fever | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_lower_back_pain | Symptoms | health-connect-unavailable | symptom_lower_back_pain | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_bloating | Symptoms | health-connect-unavailable | symptom_bloating | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_constipation | Symptoms | health-connect-unavailable | symptom_constipation | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_diarrhea | Symptoms | health-connect-unavailable | symptom_diarrhea | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_heartburn | Symptoms | health-connect-unavailable | symptom_heartburn | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_coughing | Symptoms | health-connect-unavailable | symptom_coughing | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_sore_throat | Symptoms | health-connect-unavailable | symptom_sore_throat | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_runny_nose | Symptoms | health-connect-unavailable | symptom_runny_nose | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_shortness_of_breath | Symptoms | health-connect-unavailable | symptom_shortness_of_breath | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_chest_pain | Symptoms | health-connect-unavailable | symptom_chest_pain | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_skipped_heartbeat | Symptoms | health-connect-unavailable | symptom_skipped_heartbeat | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_rapid_heartbeat | Symptoms | health-connect-unavailable | symptom_rapid_heartbeat | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_acne | Symptoms | health-connect-unavailable | symptom_acne | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_dry_skin | Symptoms | health-connect-unavailable | symptom_dry_skin | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_hair_loss | Symptoms | health-connect-unavailable | symptom_hair_loss | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_memory_lapse | Symptoms | health-connect-unavailable | symptom_memory_lapse | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_night_sweats | Symptoms | health-connect-unavailable | symptom_night_sweats | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_vomiting | Symptoms | health-connect-unavailable | symptom_vomiting | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_abdominal_cramps | Symptoms | health-connect-unavailable | symptom_abdominal_cramps | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_breast_pain | Symptoms | health-connect-unavailable | symptom_breast_pain | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_pelvic_pain | Symptoms | health-connect-unavailable | symptom_pelvic_pain | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_body_ache | Symptoms | health-connect-unavailable | symptom_body_ache | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_fainting | Symptoms | health-connect-unavailable | symptom_fainting | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_loss_of_smell | Symptoms | health-connect-unavailable | symptom_loss_of_smell | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_loss_of_taste | Symptoms | health-connect-unavailable | symptom_loss_of_taste | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_wheezing | Symptoms | health-connect-unavailable | symptom_wheezing | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_sinus_congestion | Symptoms | health-connect-unavailable | symptom_sinus_congestion | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_bladder_incontinence | Symptoms | health-connect-unavailable | symptom_bladder_incontinence | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| symptom_vaginal_dryness | Symptoms | health-connect-unavailable | symptom_vaginal_dryness | Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms. |
| medications | Medications | health-connect-unavailable | medications | Health Connect 1.1.0-beta02 does not expose a medication dose-event catalog comparable to HealthKit medications. |
| uv_exposure | Other | health-connect-unavailable | uv_exposure | Health Connect 1.1.0-beta02 does not expose UV exposure records. |
| time_in_daylight | Other | health-connect-unavailable | time_in_daylight | Health Connect 1.1.0-beta02 does not expose HealthKit Time in Daylight records. |
| number_of_falls | Other | health-connect-unavailable | number_of_falls | Health Connect 1.1.0-beta02 does not expose fall-count records. |
| blood_alcohol | Other | health-connect-unavailable | blood_alcohol | Health Connect 1.1.0-beta02 does not expose blood-alcohol records. |
| alcoholic_beverages | Other | health-connect-unavailable | alcoholic_beverages | Health Connect 1.1.0-beta02 does not expose alcoholic-beverage count records. |
| insulin_delivery | Other | health-connect-unavailable | insulin_delivery | Health Connect 1.1.0-beta02 does not expose insulin-delivery records. |
| toothbrushing | Other | health-connect-unavailable | toothbrushing | Health Connect 1.1.0-beta02 does not expose toothbrushing event records. |
| handwashing | Other | health-connect-unavailable | handwashing | Health Connect 1.1.0-beta02 does not expose handwashing event records. |
| water_temperature | Other | health-connect-unavailable | water_temperature | Health Connect 1.1.0-beta02 does not expose water-temperature records. |
| underwater_depth | Other | health-connect-unavailable | underwater_depth | Health Connect 1.1.0-beta02 does not expose underwater-depth records. |
| workouts | Workouts | supported | workouts | Android uses the same metric id. |

## Android-only supported metrics

| Android metric id | Android category | Unit | Android status | Notes |
|---|---|---|---|---|
| total_calories | ACTIVITY | kcal | android-only | Health Connect total calories aggregate; no dedicated iOS picker id in HealthMetrics.swift. |
| elevation_gained | ACTIVITY | m | android-only | Health Connect elevation aggregate and workout detail field. |
| skin_temperature | VITALS | ° | android-only | Health Connect SkinTemperatureRecord delta; kept separate from Apple wrist_temperature. |
| body_water_mass | BODY | kg | android-only | Health Connect body water mass. |
| bone_mass | BODY | kg | android-only | Health Connect bone mass. |
| unsaturated_fat | NUTRITION | g | android-only | Health Connect unsaturated fat total. |
| trans_fat | NUTRITION | g | android-only | Health Connect trans fat total. |
| folic_acid | NUTRITION | mcg | android-only | Health Connect folic acid total, distinct from folate. |
| steps_cadence | MOBILITY | steps/min | android-only | Health Connect StepsCadenceRecord average. |
| activity_intensity_minutes | ACTIVITY | min | android-only | Health Connect ActivityIntensityRecord total intensity minutes. |
| energy_from_fat | NUTRITION | kcal | android-only | Health Connect NutritionRecord energyFromFat total. |
| nutrition_meals | NUTRITION | count | android-only | Health Connect NutritionRecord per-meal entries with name/type/timing context. |
| menstruation_periods | REPRODUCTIVE | count | android-only | Health Connect MenstruationPeriodRecord interval count and entries. |
| menstruation_period_days | REPRODUCTIVE | days | android-only | Health Connect MenstruationPeriodRecord interval duration. |
| planned_workouts | WORKOUTS | count | android-only | Health Connect PlannedExerciseSessionRecord planned training sessions. |
| medical_resources | MEDICATIONS | count | android-only | Feature-gated Health Connect Personal Health Record / FHIR resources, including medication resources when granted. |

## Legacy unavailable aliases

The following Android ids are also kept in `HealthMetrics.unavailableMetrics` so stale persisted settings and old docs remain explainable: `audio_exposure`, `afib_burden_percent`, `state_of_mind_count`, `average_valence_percent`, `daily_mood_count`, `average_daily_mood_valence`, `momentary_emotion_count`, `forced_vital_capacity_l`, `fev1_l`, `headphone_audio_db`, `environmental_sound_db`, `stand_hours`, `move_minutes`, `waist_circumference_cm`, `step_length_cm`, `double_support_percent`, `walking_asymmetry_percent`, `six_min_walk_m`, `walking_steadiness_percent`, `running_stride_length_m`, `running_ground_contact_ms`, `running_vertical_oscillation_cm`, `symptoms`.
