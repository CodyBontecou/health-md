# Health Connect Raw Record Ledger

Status: v1 closed inventory for `androidx.health.connect:connect-client:1.2.0-alpha02` and `HealthConnectRecordCatalog`. The record and snapshot contracts are [raw-record-v1.md](raw-record-v1.md) and [raw-snapshot-v1.md](raw-snapshot-v1.md).

## 1. Reading the ledger

For ordinary records, the permission is the exact value returned by `HealthPermission.getReadPermission(<Record>::class)`; the symbolic suffix is shown to make review practical. `none` in Feature means no extra gate beyond Health Connect availability. Feature names correspond to `HealthConnectFeatures` constants. Metric IDs are selection aliases, not output field names.

Range `instant [s,e)` and `overlap [s,e)` use the normative half-open rules. `unbounded_non_temporal` means the PHR API offers no record instant and the request range cannot filter it. Mapper `explicit` means a no-reflection pinned mapper exists. `incomplete` is a known implementation defect and MUST become `read_error`, never silent omission. Nested risk calls out high-cardinality, free-text, precise location, nullable, ordering, and exact-payload concerns. `getChanges=yes` is the descriptor’s current `changeEligible=true`; v1 still performs full reads and stores no change token.

## 2. HealthConnectRecordCatalog descriptors

| typeKey | SDK record | read permission | feature | metric IDs | range behavior | mapper status | nested fidelity risk | canonical units | getChanges eligible |
|---|---|---|---|---|---|---|---|---|---|
| steps | StepsRecord | getReadPermission; READ_STEPS | none | steps | overlap [s,e) | explicit | high-cardinality pages; count | count | yes |
| heart_rate | HeartRateRecord | getReadPermission; READ_HEART_RATE | none | avg_hr, min_hr, max_hr | overlap [s,e) | explicit | high-cardinality samples ordered by nano instant | bpm integer | yes |
| sleep_session | SleepSessionRecord | getReadPermission; READ_SLEEP | none | sleep_total, sleep_deep, sleep_rem, sleep_light, sleep_awake, sleep_in_bed | overlap [s,e) | explicit | title/notes free text; ordered stages and raw stage enum | duration is temporal; no quantity | yes |
| exercise_session | ExerciseSessionRecord | getReadPermission; READ_EXERCISE | none | exercise_minutes, cycling_distance, swimming_distance, swimming_strokes, wheelchair_distance, downhill_snow_distance, walking_hr, running_speed, running_power, workouts | overlap [s,e) | explicit | free text; segments; nullable laps; precise route and consent state | lap/accuracy/altitude m; lat/lon raw | yes |
| distance | DistanceRecord | getReadPermission; READ_DISTANCE | none | distance, cycling_distance, swimming_distance, wheelchair_distance, downhill_snow_distance | overlap [s,e) | explicit | converted quantity | m | yes |
| active_calories_burned | ActiveCaloriesBurnedRecord | getReadPermission; READ_ACTIVE_CALORIES_BURNED | none | active_calories | overlap [s,e) | explicit | converted quantity | kcal | yes |
| total_calories_burned | TotalCaloriesBurnedRecord | getReadPermission; READ_TOTAL_CALORIES_BURNED | none | total_calories | overlap [s,e) | explicit | converted quantity | kcal | yes |
| basal_metabolic_rate | BasalMetabolicRateRecord | getReadPermission; READ_BASAL_METABOLIC_RATE | none | basal_calories | instant [s,e) | explicit | converted rate quantity | W | yes |
| blood_pressure | BloodPressureRecord | getReadPermission; READ_BLOOD_PRESSURE | none | bp_systolic, bp_diastolic | instant [s,e) | explicit | two raw enums plus quantities | mmHg | yes |
| blood_glucose | BloodGlucoseRecord | getReadPermission; READ_BLOOD_GLUCOSE | none | blood_glucose | instant [s,e) | explicit | specimen/meal/relation raw enums | mmol/L | yes |
| body_fat | BodyFatRecord | getReadPermission; READ_BODY_FAT | none | body_fat | instant [s,e) | explicit | percentage quantity | % | yes |
| body_temperature | BodyTemperatureRecord | getReadPermission; READ_BODY_TEMPERATURE | none | body_temp | instant [s,e) | explicit | location raw enum | degC | yes |
| height | HeightRecord | getReadPermission; READ_HEIGHT | none | height, bmi | instant [s,e) | explicit | BMI selection alias does not synthesize BMI record | m | yes |
| weight | WeightRecord | getReadPermission; READ_WEIGHT | none | weight, bmi | instant [s,e) | explicit | BMI selection alias does not synthesize BMI record | kg | yes |
| oxygen_saturation | OxygenSaturationRecord | getReadPermission; READ_OXYGEN_SATURATION | none | blood_oxygen | instant [s,e) | explicit | percentage quantity | % | yes |
| respiratory_rate | RespiratoryRateRecord | getReadPermission; READ_RESPIRATORY_RATE | none | respiratory_rate | instant [s,e) | explicit | scalar decimal pair | breaths/min | yes |
| heart_rate_variability_rmssd | HeartRateVariabilityRmssdRecord | getReadPermission; READ_HEART_RATE_VARIABILITY | none | hrv | instant [s,e) | explicit | scalar decimal pair | ms | yes |
| nutrition | NutritionRecord | getReadPermission; READ_NUTRITION | none | dietary_energy, protein, carbs, fat, saturated_fat, monounsaturated_fat, polyunsaturated_fat, unsaturated_fat, trans_fat, fiber, sugar, sodium, potassium, calcium, iron, magnesium, zinc, phosphorus, iodine, selenium, copper, manganese, chromium, molybdenum, chloride, vitamin_a, vitamin_b6, vitamin_b12, vitamin_c, vitamin_d, vitamin_e, vitamin_k, thiamin, riboflavin, niacin, folate, folic_acid, pantothenic_acid, biotin, cholesterol, caffeine, energy_from_fat, nutrition_meals | overlap [s,e) | explicit | many nullable nutrients; name free text; meal enum | kcal energy; g nutrients | yes |
| hydration | HydrationRecord | getReadPermission; READ_HYDRATION | none | water | overlap [s,e) | explicit | converted quantity | L | yes |
| floors_climbed | FloorsClimbedRecord | getReadPermission; READ_FLOORS_CLIMBED | none | flights_climbed | overlap [s,e) | explicit | finite raw double | floors | yes |
| lean_body_mass | LeanBodyMassRecord | getReadPermission; READ_LEAN_BODY_MASS | none | lean_mass | instant [s,e) | explicit | converted quantity | kg | yes |
| resting_heart_rate | RestingHeartRateRecord | getReadPermission; READ_RESTING_HEART_RATE | none | resting_hr | instant [s,e) | explicit | integer | bpm integer | yes |
| speed | SpeedRecord | getReadPermission; READ_SPEED | none | walking_speed, running_speed | overlap [s,e) | explicit | high-cardinality ordered samples | m/s | yes |
| vo2_max | Vo2MaxRecord | getReadPermission; READ_VO2_MAX | none | vo2_max | instant [s,e) | explicit | measurement method raw enum | mL/(min*kg) | yes |
| elevation_gained | ElevationGainedRecord | getReadPermission; READ_ELEVATION_GAINED | none | elevation_gained | overlap [s,e) | explicit | converted quantity | m | yes |
| wheelchair_pushes | WheelchairPushesRecord | getReadPermission; READ_WHEELCHAIR_PUSHES | none | wheelchair_pushes | overlap [s,e) | explicit | count | count | yes |
| power | PowerRecord | getReadPermission; READ_POWER | none | power_avg, power_max, running_power | overlap [s,e) | explicit | high-cardinality ordered samples | W | yes |
| basal_body_temperature | BasalBodyTemperatureRecord | getReadPermission; READ_BASAL_BODY_TEMPERATURE | none | basal_body_temp | instant [s,e) | explicit | sensitive reproductive signal; location enum | degC | yes |
| body_water_mass | BodyWaterMassRecord | getReadPermission; READ_BODY_WATER_MASS | none | body_water_mass | instant [s,e) | explicit | converted quantity | kg | yes |
| bone_mass | BoneMassRecord | getReadPermission; READ_BONE_MASS | none | bone_mass | instant [s,e) | explicit | converted quantity | kg | yes |
| skin_temperature | SkinTemperatureRecord | getReadPermission; READ_SKIN_TEMPERATURE | FEATURE_SKIN_TEMPERATURE | skin_temperature | overlap [s,e) | explicit | nullable baseline; high-cardinality deltas; location enum | degC | yes |
| cervical_mucus | CervicalMucusRecord | getReadPermission; READ_CERVICAL_MUCUS | none | cervical_mucus | instant [s,e) | explicit | sensitive reproductive signal; two raw enums | enum only | yes |
| intermenstrual_bleeding | IntermenstrualBleedingRecord | getReadPermission; READ_INTERMENSTRUAL_BLEEDING | none | intermenstrual_bleeding | instant [s,e) | explicit | sensitive marker; empty fields object | marker | yes |
| menstruation_flow | MenstruationFlowRecord | getReadPermission; READ_MENSTRUATION | none | menstrual_flow | instant [s,e) | explicit | sensitive raw flow enum | enum only | yes |
| menstruation_period | MenstruationPeriodRecord | getReadPermission; READ_MENSTRUATION | none | menstruation_periods, menstruation_period_days | overlap [s,e) | explicit | sensitive interval marker; empty fields object | temporal | yes |
| ovulation_test | OvulationTestRecord | getReadPermission; READ_OVULATION_TEST | none | ovulation_test | instant [s,e) | explicit | sensitive raw result enum | enum only | yes |
| sexual_activity | SexualActivityRecord | getReadPermission; READ_SEXUAL_ACTIVITY | none | sexual_activity | instant [s,e) | explicit | highly sensitive protection enum | enum only | yes |
| cycling_pedaling_cadence | CyclingPedalingCadenceRecord | getReadPermission; READ_CYCLING_PEDALING_CADENCE | none | cycling_cadence | overlap [s,e) | explicit | high-cardinality ordered finite doubles | revolutions/min | yes |
| steps_cadence | StepsCadenceRecord | getReadPermission; READ_STEPS_CADENCE | none | steps_cadence | overlap [s,e) | explicit | high-cardinality ordered finite doubles | steps/min | yes |
| mindfulness_session | MindfulnessSessionRecord | getReadPermission; READ_MINDFULNESS | FEATURE_MINDFULNESS_SESSION | mindful_minutes, mindful_sessions | overlap [s,e) | explicit | title/notes free text; raw type enum | temporal | yes |
| planned_exercise_session | PlannedExerciseSessionRecord | getReadPermission; READ_PLANNED_EXERCISE | FEATURE_PLANNED_EXERCISE | planned_workouts | overlap [s,e) | explicit | deeply nested ordered blocks/steps/goals/targets; free text | m, s+nano, kcal, W, m/s, kg, bpm/cadence raw | yes |
| activity_intensity | ActivityIntensityRecord | getReadPermission; READ_ACTIVITY_INTENSITY | FEATURE_ACTIVITY_INTENSITY | activity_intensity_minutes | overlap [s,e) | explicit | raw intensity enum | temporal | yes |

All 42 descriptors currently set `changeEligible=true`. The app does not call `getChanges`; eligibility MUST NOT be read as an incremental-export guarantee. A future incremental contract must define token ownership, expiry, deletion tombstones, reset behavior, dedupe, and transaction limitations.

## 3. Personal Health Record medical categories

Every row maps to output `wireType=medical_resource` and selection metric `medical_resources`. Its report `typeKey` remains category-specific. All require `FEATURE_PERSONAL_HEALTH_RECORD`, are `unbounded_non_temporal`, use `RawMedicalResourceMapper`, have exact FHIR JSON/IDs/source metadata risk, no canonical quantity conversion, and are not eligible for the ordinary Record `getChanges` flow.

| typeKey | SDK medical resource type | read permission constant | feature | metric IDs | range behavior | mapper status | nested fidelity risk | canonical units | getChanges eligible |
|---|---|---|---|---|---|---|---|---|---|
| medical_resource/allergies_intolerances | MEDICAL_RESOURCE_TYPE_ALLERGIES_INTOLERANCES | PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/conditions | MEDICAL_RESOURCE_TYPE_CONDITIONS | PERMISSION_READ_MEDICAL_DATA_CONDITIONS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/laboratory_results | MEDICAL_RESOURCE_TYPE_LABORATORY_RESULTS | PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/medications | MEDICAL_RESOURCE_TYPE_MEDICATIONS | PERMISSION_READ_MEDICAL_DATA_MEDICATIONS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/personal_details | MEDICAL_RESOURCE_TYPE_PERSONAL_DETAILS | PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/practitioner_details | MEDICAL_RESOURCE_TYPE_PRACTITIONER_DETAILS | PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/pregnancy | MEDICAL_RESOURCE_TYPE_PREGNANCY | PERMISSION_READ_MEDICAL_DATA_PREGNANCY | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/procedures | MEDICAL_RESOURCE_TYPE_PROCEDURES | PERMISSION_READ_MEDICAL_DATA_PROCEDURES | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/social_history | MEDICAL_RESOURCE_TYPE_SOCIAL_HISTORY | PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/vaccines | MEDICAL_RESOURCE_TYPE_VACCINES | PERMISSION_READ_MEDICAL_DATA_VACCINES | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/visits | MEDICAL_RESOURCE_TYPE_VISITS | PERMISSION_READ_MEDICAL_DATA_VISITS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |
| medical_resource/vital_signs | MEDICAL_RESOURCE_TYPE_VITAL_SIGNS | PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS | FEATURE_PERSONAL_HEALTH_RECORD | medical_resources | unbounded_non_temporal | explicit | exact FHIR string; IDs; source; version | none | no |

Health Connect medical resource labels also include `medicalResourceType` raw values `vaccines`, `allergies_intolerances`, `pregnancy`, `social_history`, `vital_signs`, `laboratory_results`, `conditions`, `procedures`, `medications`, `personal_details`, `practitioner_details`, and `visits`. FHIR resource type raw+label supports immunization, allergy intolerance, observation, condition, procedure, medication, medication request, medication statement, patient, practitioner, practitioner role, encounter, location, and organization; unknown integers remain `unknown_<raw>`.

A missing matching `MedicalDataSource` maps the affected resource with `source:null`, marks only that category `read_error`, preserves records and already completed categories, and includes an issue without embedding the FHIR body.

## 4. Permissions, features, and history behavior

A type read requires Health Connect availability, its row permission, its feature gate when present, and—when the request extends beyond the provider’s ordinary historical window—`PERMISSION_READ_HEALTH_DATA_HISTORY`. `FEATURE_READ_HEALTH_DATA_HISTORY` being available is not the same as permission granted. Missing history permission maps affected selected temporal rows to `history_permission_missing`; the exporter MUST NOT present their zero/partial counts as proof that no older data exists.

When several metric aliases select the same descriptor, permission is requested/read once. Menstruation flow and period may resolve to the same platform permission but remain separate type reports. PHR permissions are category-specific: one granted category MUST be read even when another is denied, and denied categories MUST be reported rather than collapsing all PHR into one status.

## 5. Mapper and upgrade policy

The mapper is a closed `when` over pinned SDK classes and sealed nested variants. Reflection, Java/Kotlin `toString`, generic object serialization, and silent catch-and-drop are forbidden fidelity fallbacks. A catalog descriptor with no complete temporal and field mapper is `read_error` until fixed. Temporal dispatch is structurally paired with each catalog descriptor's `instant` or `overlap` range behavior. `SleepSessionRecord` has explicit interval dispatch and mapping coverage.

On every Health Connect dependency upgrade, maintainers MUST compare the SDK record inventory, fields, constants, unit APIs, nested sealed classes, permissions, features, and changes support against this ledger. Additive `fields` are permitted, but changed meaning/unit/nullability or identity requires a versioned contract decision.

## 6. Provider and privacy limitations

Health Connect can already contain data synchronized from apps or clouds. `dataOriginPackageName` identifies the Health Connect writer; it does not prove original sensor, account, or cloud provenance. The exporter MUST preserve exposed origin/device metadata and MUST NOT manufacture deeper lineage. Exact cloud payload fidelity can be claimed only by an adapter that receives and preserves that payload; normalized cloud API values are not equivalent to native Health Connect records.

All rows are health data. Reproductive, sexual, PHR, free-text, device identity, and route rows carry elevated re-identification risk. Permission availability never implies consent to log, analyze, upload, or retain exports outside the user-directed destination.
