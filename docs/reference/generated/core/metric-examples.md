# Metric examples

Exactly one entry is emitted for every definition in `HealthMetrics.all`.

## sleep_total

- Name: Total Sleep
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_total_hours,7.75,hours,duration_sum
```

## sleep_bedtime

- Name: Bedtime
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_bedtime,06:00,time,first_time
```

## sleep_wake

- Name: Wake Time
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_wake,13:45,time,last_time
```

## sleep_deep

- Name: Deep Sleep
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_deep_hours,1.50,hours,duration_sum
```

## sleep_rem

- Name: REM Sleep
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_rem_hours,2.25,hours,duration_sum
```

## sleep_core

- Name: Core Sleep
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_core_hours,4.00,hours,duration_sum
```

## sleep_awake

- Name: Awake During Sleep
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_awake_hours,0.25,hours,duration_sum
```

## sleep_in_bed

- Name: Time in Bed
- Category: Sleep
- HealthKit identifier: `HKCategoryTypeIdentifierSleepAnalysis`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sleep_in_bed_hours,8.00,hours,duration_sum
```

## steps

- Name: Steps
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierStepCount`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
steps,12500,steps,sum
```

## distance_walking_running

- Name: Walking + Running Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceWalkingRunning`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
walking_running_km,9.50,km,sum
walking_running_mi,5.90,mi,sum
```

## distance_swimming

- Name: Swimming Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceSwimming`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
swimming_m,750,m,sum
```

## distance_wheelchair

- Name: Wheelchair Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceWheelchair`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
wheelchair_km,1.25,km,sum
wheelchair_mi,0.78,mi,sum
```

## distance_downhill_snow

- Name: Downhill Snow Sports Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceDownhillSnowSports`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
downhill_snow_km,2.30,km,sum
downhill_snow_mi,1.43,mi,sum
```

## active_energy

- Name: Active Energy
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierActiveEnergyBurned`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
active_calories,520,kcal,sum
```

## basal_energy

- Name: Resting Energy
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierBasalEnergyBurned`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
basal_calories,1650,kcal,sum
```

## exercise_time

- Name: Exercise Time
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierAppleExerciseTime`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
exercise_minutes,45,min,sum
```

## stand_time

- Name: Stand Time
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierAppleStandTime`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
stand_time_minutes,37.5,min,sum
```

## stand_hours

- Name: Stand Hours
- Category: Activity
- HealthKit identifier: `HKCategoryTypeIdentifierAppleStandHour`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
stand_hours,11,hours,count
```

## move_time

- Name: Move Time
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierAppleMoveTime`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
move_minutes,61,min,sum
```

## flights_climbed

- Name: Flights Climbed
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierFlightsClimbed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
flights_climbed,8,floors,sum
```

## swimming_strokes

- Name: Swimming Strokes
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierSwimmingStrokeCount`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
swimming_strokes,420,strokes,sum
```

## push_count

- Name: Wheelchair Pushes
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierPushCount`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
wheelchair_pushes,88,pushes,sum
```

## vo2_max

- Name: Cardio Fitness
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierVO2Max`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vo2_max,42.5,mL/kg/min,maximum
vo2_max_source_uuid,00000000-0000-0000-0000-000000000700,uuid,latest
vo2_max_source_start,2026-03-14T00:00:00.000000000Z,datetime,latest
vo2_max_source_end,2026-03-14T00:01:00.000000000Z,datetime,latest
vo2_max_carried_forward,true,boolean,latest
vo2_max_age_seconds,86400,seconds,latest
```

## physical_effort

- Name: Physical Effort
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierPhysicalEffort`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
physical_effort,4.8,kcal/hr/kg,average
```

## activity_summary

- Name: Activity Summary Rings and Goals
- Category: Activity
- HealthKit identifier: `HKActivitySummaryTypeIdentifier`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKActivitySummaryTypeIdentifier` | `activity_summary` | direct |

## activity_move_mode

- Name: Activity Move Mode
- Category: Activity
- HealthKit identifier: `HKCharacteristicTypeIdentifierActivityMoveMode`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCharacteristicTypeIdentifierActivityMoveMode` | `characteristic` | direct |

## cross_country_skiing_speed

- Name: Cross-Country Skiing Speed
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierCrossCountrySkiingSpeed`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierCrossCountrySkiingSpeed` | `quantity` | direct |

## distance_cross_country_skiing

- Name: Cross-Country Skiing Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceCrossCountrySkiing`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierDistanceCrossCountrySkiing` | `quantity` | direct |

## paddle_sports_speed

- Name: Paddle Sports Speed
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierPaddleSportsSpeed`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierPaddleSportsSpeed` | `quantity` | direct |

## distance_paddle_sports

- Name: Paddle Sports Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistancePaddleSports`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierDistancePaddleSports` | `quantity` | direct |

## rowing_speed

- Name: Rowing Speed
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierRowingSpeed`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierRowingSpeed` | `quantity` | direct |

## distance_rowing

- Name: Rowing Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceRowing`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierDistanceRowing` | `quantity` | direct |

## distance_skating_sports

- Name: Skating Sports Distance
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceSkatingSports`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierDistanceSkatingSports` | `quantity` | direct |

## workout_effort_score

- Name: Workout Effort Score
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierWorkoutEffortScore`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierWorkoutEffortScore` | `quantity` | direct |

## estimated_workout_effort_score

- Name: Estimated Workout Effort Score
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierEstimatedWorkoutEffortScore`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierEstimatedWorkoutEffortScore` | `quantity` | direct |

## nike_fuel

- Name: Nike Fuel
- Category: Activity
- HealthKit identifier: `HKQuantityTypeIdentifierNikeFuel`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierNikeFuel` | `quantity` | direct |

## heart_rate_avg

- Name: Average Heart Rate
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierHeartRate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
average_heart_rate,72,bpm,average
```

## heart_rate_min

- Name: Minimum Heart Rate
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierHeartRate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
heart_rate_min,52,bpm,minimum
```

## heart_rate_max

- Name: Maximum Heart Rate
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierHeartRate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
heart_rate_max,155,bpm,maximum
```

## resting_heart_rate

- Name: Resting Heart Rate
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierRestingHeartRate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
resting_heart_rate,58,bpm,latest
```

## walking_heart_rate

- Name: Walking Heart Rate Average
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierWalkingHeartRateAverage`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
walking_heart_rate,105,bpm,latest
```

## hrv

- Name: Heart Rate Variability
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierHeartRateVariabilitySDNN`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
hrv_ms,42.0,ms,average
```

## heart_rate_recovery

- Name: Heart Rate Recovery
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierHeartRateRecoveryOneMinute`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
heart_rate_recovery,24,bpm,latest
```

## afib_burden

- Name: Atrial Fibrillation Burden
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierAtrialFibrillationBurden`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
afib_burden_percent,1.2,percent,latest
```

## peripheral_perfusion_index

- Name: Peripheral Perfusion Index
- Category: Heart
- HealthKit identifier: `HKQuantityTypeIdentifierPeripheralPerfusionIndex`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierPeripheralPerfusionIndex` | `quantity` | direct |

## high_heart_rate_event

- Name: High Heart Rate Event
- Category: Heart
- HealthKit identifier: `HKCategoryTypeIdentifierHighHeartRateEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierHighHeartRateEvent` | `category` | direct |

## low_heart_rate_event

- Name: Low Heart Rate Event
- Category: Heart
- HealthKit identifier: `HKCategoryTypeIdentifierLowHeartRateEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierLowHeartRateEvent` | `category` | direct |

## irregular_heart_rhythm_event

- Name: Irregular Heart Rhythm Event
- Category: Heart
- HealthKit identifier: `HKCategoryTypeIdentifierIrregularHeartRhythmEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierIrregularHeartRhythmEvent` | `category` | direct |

## low_cardio_fitness_event

- Name: Low Cardio Fitness Event
- Category: Heart
- HealthKit identifier: `HKCategoryTypeIdentifierLowCardioFitnessEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierLowCardioFitnessEvent` | `category` | direct |

## hypertension_event

- Name: Hypertension Event
- Category: Heart
- HealthKit identifier: `HKCategoryTypeIdentifierHypertensionEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierHypertensionEvent` | `category` | direct |

## electrocardiograms

- Name: Electrocardiograms
- Category: Heart
- HealthKit identifier: `HKDataTypeIdentifierElectrocardiogram`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKDataTypeIdentifierElectrocardiogram` | `electrocardiogram` | direct |

## heartbeat_series

- Name: Heartbeat Series
- Category: Heart
- HealthKit identifier: `HKDataTypeIdentifierHeartbeatSeries`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKDataTypeIdentifierHeartbeatSeries` | `heartbeat_series` | direct |

## respiratory_rate

- Name: Respiratory Rate
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierRespiratoryRate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
respiratory_rate,15.2,breaths/min,average
respiratory_rate_avg,15.2,breaths/min,average
respiratory_rate_min,11.8,breaths/min,minimum
respiratory_rate_max,19.4,breaths/min,maximum
```

## blood_oxygen

- Name: Blood Oxygen
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierOxygenSaturation`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
blood_oxygen,97,percent,average
blood_oxygen_avg,97,percent,average
blood_oxygen_min,94,percent,minimum
blood_oxygen_max,99,percent,maximum
```

## forced_vital_capacity

- Name: Forced Vital Capacity
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierForcedVitalCapacity`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
forced_vital_capacity_l,4.80,L,latest
```

## fev1

- Name: Forced Expiratory Volume (FEV1)
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierForcedExpiratoryVolume1`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
fev1_l,3.90,L,latest
```

## peak_expiratory_flow

- Name: Peak Expiratory Flow Rate
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierPeakExpiratoryFlowRate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
peak_expiratory_flow,510.0,L/min,latest
```

## inhaler_usage

- Name: Inhaler Usage
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierInhalerUsage`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
inhaler_usage,2,uses,sum
```

## sleeping_breathing_disturbances

- Name: Sleeping Breathing Disturbances
- Category: Respiratory
- HealthKit identifier: `HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierAppleSleepingBreathingDisturbances` | `quantity` | direct |

## sleep_apnea_event

- Name: Sleep Apnea Event
- Category: Respiratory
- HealthKit identifier: `HKCategoryTypeIdentifierSleepApneaEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierSleepApneaEvent` | `category` | direct |

## body_temperature

- Name: Body Temperature
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierBodyTemperature`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
body_temperature,36.7,°C,average
body_temperature_avg,36.7,°C,average
body_temperature_min,36.3,°C,minimum
body_temperature_max,37.1,°C,maximum
```

## basal_body_temperature

- Name: Basal Body Temperature
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierBasalBodyTemperature`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
basal_body_temperature,36.5,°C,latest
```

## wrist_temperature

- Name: Wrist Temperature
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierAppleSleepingWristTemperature`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
wrist_temperature,36.45,°C,latest
```

## blood_pressure_systolic

- Name: Blood Pressure (Systolic)
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierBloodPressureSystolic`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
blood_pressure_systolic,121,mmHg,average
blood_pressure_systolic_avg,121,mmHg,average
blood_pressure_systolic_min,116,mmHg,minimum
blood_pressure_systolic_max,127,mmHg,maximum
```

## blood_pressure_diastolic

- Name: Blood Pressure (Diastolic)
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierBloodPressureDiastolic`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
blood_pressure_diastolic,79,mmHg,average
blood_pressure_diastolic_avg,79,mmHg,average
blood_pressure_diastolic_min,74,mmHg,minimum
blood_pressure_diastolic_max,84,mmHg,maximum
```

## blood_glucose

- Name: Blood Glucose
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierBloodGlucose`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
blood_glucose,102.0,mg/dL,average
blood_glucose_avg,102.0,mg/dL,average
blood_glucose_min,82.0,mg/dL,minimum
blood_glucose_max,138.0,mg/dL,maximum
```

## electrodermal_activity

- Name: Electrodermal Activity
- Category: Vitals
- HealthKit identifier: `HKQuantityTypeIdentifierElectrodermalActivity`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
electrodermal_activity,1.75,µS,latest
```

## weight

- Name: Weight
- Category: Body Measurements
- HealthKit identifier: `HKQuantityTypeIdentifierBodyMass`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
weight_kg,75.0,kg,latest
```

## height

- Name: Height
- Category: Body Measurements
- HealthKit identifier: `HKQuantityTypeIdentifierHeight`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
height_m,1.78,m,latest
```

## bmi

- Name: Body Mass Index
- Category: Body Measurements
- HealthKit identifier: `HKQuantityTypeIdentifierBodyMassIndex`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
bmi,23.7,kg/m²,latest
```

## body_fat

- Name: Body Fat Percentage
- Category: Body Measurements
- HealthKit identifier: `HKQuantityTypeIdentifierBodyFatPercentage`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
body_fat_percent,18.0,percent,latest
```

## lean_body_mass

- Name: Lean Body Mass
- Category: Body Measurements
- HealthKit identifier: `HKQuantityTypeIdentifierLeanBodyMass`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
lean_body_mass_kg,61.5,kg,latest
```

## waist_circumference

- Name: Waist Circumference
- Category: Body Measurements
- HealthKit identifier: `HKQuantityTypeIdentifierWaistCircumference`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
waist_circumference_cm,84.0,cm,latest
```

## date_of_birth

- Name: Date of Birth
- Category: Body Measurements
- HealthKit identifier: `HKCharacteristicTypeIdentifierDateOfBirth`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCharacteristicTypeIdentifierDateOfBirth` | `characteristic` | direct |

## biological_sex

- Name: Biological Sex
- Category: Body Measurements
- HealthKit identifier: `HKCharacteristicTypeIdentifierBiologicalSex`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCharacteristicTypeIdentifierBiologicalSex` | `characteristic` | direct |

## blood_type

- Name: Blood Type
- Category: Body Measurements
- HealthKit identifier: `HKCharacteristicTypeIdentifierBloodType`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCharacteristicTypeIdentifierBloodType` | `characteristic` | direct |

## fitzpatrick_skin_type

- Name: Fitzpatrick Skin Type
- Category: Body Measurements
- HealthKit identifier: `HKCharacteristicTypeIdentifierFitzpatrickSkinType`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCharacteristicTypeIdentifierFitzpatrickSkinType` | `characteristic` | direct |

## wheelchair_use

- Name: Wheelchair Use
- Category: Body Measurements
- HealthKit identifier: `HKCharacteristicTypeIdentifierWheelchairUse`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCharacteristicTypeIdentifierWheelchairUse` | `characteristic` | direct |

## walking_speed

- Name: Walking Speed
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierWalkingSpeed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
walking_speed,1.42,m/s,average
```

## walking_step_length

- Name: Walking Step Length
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierWalkingStepLength`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
step_length_cm,73.0,cm,average
```

## walking_double_support

- Name: Double Support Time
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierWalkingDoubleSupportPercentage`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
double_support_percent,27.0,percent,average
```

## walking_asymmetry

- Name: Walking Asymmetry
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierWalkingAsymmetryPercentage`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
walking_asymmetry_percent,1.5,percent,average
```

## walking_steadiness

- Name: Walking Steadiness
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierAppleWalkingSteadiness`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
walking_steadiness_percent,92.0,percent,latest
```

## stair_ascent_speed

- Name: Stair Ascent Speed
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierStairAscentSpeed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
stair_ascent_speed,0.62,m/s,average
```

## stair_descent_speed

- Name: Stair Descent Speed
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierStairDescentSpeed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
stair_descent_speed,0.71,m/s,average
```

## six_minute_walk

- Name: Six-Minute Walk Distance
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierSixMinuteWalkTestDistance`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
six_min_walk_m,590,m,latest
```

## running_speed

- Name: Running Speed
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierRunningSpeed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
running_speed,3.40,m/s,average
```

## running_stride_length

- Name: Running Stride Length
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierRunningStrideLength`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
running_stride_length_m,1.15,m,average
```

## running_ground_contact

- Name: Running Ground Contact Time
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierRunningGroundContactTime`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
running_ground_contact_ms,245,ms,average
```

## running_vertical_oscillation

- Name: Running Vertical Oscillation
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierRunningVerticalOscillation`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
running_vertical_oscillation_cm,8.4,cm,average
```

## running_power

- Name: Running Power
- Category: Mobility
- HealthKit identifier: `HKQuantityTypeIdentifierRunningPower`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
running_power_w,278,W,average
```

## walking_steadiness_event

- Name: Walking Steadiness Event
- Category: Mobility
- HealthKit identifier: `HKCategoryTypeIdentifierAppleWalkingSteadinessEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierAppleWalkingSteadinessEvent` | `category` | direct |

## cycling_distance

- Name: Cycling Distance
- Category: Cycling
- HealthKit identifier: `HKQuantityTypeIdentifierDistanceCycling`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cycling_km,3.20,km,sum
cycling_mi,1.99,mi,sum
```

## cycling_speed

- Name: Cycling Speed
- Category: Cycling
- HealthKit identifier: `HKQuantityTypeIdentifierCyclingSpeed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cycling_speed,8.20,m/s,average
```

## cycling_power

- Name: Cycling Power
- Category: Cycling
- HealthKit identifier: `HKQuantityTypeIdentifierCyclingPower`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cycling_power_w,215,W,average
```

## cycling_cadence

- Name: Cycling Cadence
- Category: Cycling
- HealthKit identifier: `HKQuantityTypeIdentifierCyclingCadence`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cycling_cadence_rpm,88,rpm,average
```

## cycling_ftp

- Name: Functional Threshold Power
- Category: Cycling
- HealthKit identifier: `HKQuantityTypeIdentifierCyclingFunctionalThresholdPower`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cycling_ftp_w,260,W,latest
```

## dietary_energy

- Name: Dietary Energy
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryEnergyConsumed`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
dietary_calories,2100,kcal,sum
```

## dietary_protein

- Name: Protein
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryProtein`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
protein_g,120.0,g,sum
```

## dietary_carbs

- Name: Carbohydrates
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryCarbohydrates`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
carbohydrates_g,250.0,g,sum
```

## dietary_fat

- Name: Total Fat
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryFatTotal`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
fat_g,70.0,g,sum
```

## dietary_fat_saturated

- Name: Saturated Fat
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryFatSaturated`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
saturated_fat_g,20.0,g,sum
```

## dietary_fat_mono

- Name: Monounsaturated Fat
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryFatMonounsaturated`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
monounsaturated_fat_g,24.0,g,sum
```

## dietary_fat_poly

- Name: Polyunsaturated Fat
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryFatPolyunsaturated`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
polyunsaturated_fat_g,15.0,g,sum
```

## dietary_cholesterol

- Name: Cholesterol
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryCholesterol`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cholesterol_mg,180.0,mg,sum
```

## dietary_fiber

- Name: Fiber
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryFiber`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
fiber_g,25.0,g,sum
```

## dietary_sugar

- Name: Sugar
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietarySugar`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sugar_g,45.0,g,sum
```

## dietary_sodium

- Name: Sodium
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietarySodium`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sodium_mg,2100,mg,sum
```

## dietary_water

- Name: Water
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryWater`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
water_l,2.50,L,sum
```

## dietary_caffeine

- Name: Caffeine
- Category: Nutrition
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryCaffeine`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
caffeine_mg,200.0,mg,sum
```

## vitamin_a

- Name: Vitamin A
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminA`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_a_ug,800.0,µg,sum
```

## vitamin_b6

- Name: Vitamin B6
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminB6`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_b6_mg,1.70,mg,sum
```

## vitamin_b12

- Name: Vitamin B12
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminB12`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_b12_ug,2.40,µg,sum
```

## vitamin_c

- Name: Vitamin C
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminC`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_c_mg,95.0,mg,sum
```

## vitamin_d

- Name: Vitamin D
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminD`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_d_ug,20.0,µg,sum
```

## vitamin_e

- Name: Vitamin E
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminE`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_e_mg,15.00,mg,sum
```

## vitamin_k

- Name: Vitamin K
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryVitaminK`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
vitamin_k_ug,120.0,µg,sum
```

## thiamin

- Name: Thiamin (B1)
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryThiamin`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
thiamin_mg,1.20,mg,sum
```

## riboflavin

- Name: Riboflavin (B2)
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryRiboflavin`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
riboflavin_mg,1.30,mg,sum
```

## niacin

- Name: Niacin (B3)
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryNiacin`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
niacin_mg,16.0,mg,sum
```

## folate

- Name: Folate
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryFolate`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
folate_ug,400.0,µg,sum
```

## biotin

- Name: Biotin
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryBiotin`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
biotin_ug,30.0,µg,sum
```

## pantothenic_acid

- Name: Pantothenic Acid (B5)
- Category: Vitamins
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryPantothenicAcid`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
pantothenic_acid_mg,5.00,mg,sum
```

## calcium

- Name: Calcium
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryCalcium`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
calcium_mg,1000.0,mg,sum
```

## iron

- Name: Iron
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryIron`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
iron_mg,18.00,mg,sum
```

## potassium

- Name: Potassium
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryPotassium`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
potassium_mg,3400.0,mg,sum
```

## magnesium

- Name: Magnesium
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryMagnesium`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
magnesium_mg,420.0,mg,sum
```

## phosphorus

- Name: Phosphorus
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryPhosphorus`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
phosphorus_mg,700.0,mg,sum
```

## zinc

- Name: Zinc
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryZinc`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
zinc_mg,11.00,mg,sum
```

## selenium

- Name: Selenium
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietarySelenium`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
selenium_ug,55.0,µg,sum
```

## copper

- Name: Copper
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryCopper`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
copper_mg,0.900,mg,sum
```

## manganese

- Name: Manganese
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryManganese`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
manganese_mg,2.30,mg,sum
```

## chromium

- Name: Chromium
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryChromium`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
chromium_ug,35.0,µg,sum
```

## molybdenum

- Name: Molybdenum
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryMolybdenum`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
molybdenum_ug,45.0,µg,sum
```

## chloride

- Name: Chloride
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryChloride`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
chloride_mg,2300.0,mg,sum
```

## iodine

- Name: Iodine
- Category: Minerals
- HealthKit identifier: `HKQuantityTypeIdentifierDietaryIodine`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
iodine_ug,150.0,µg,sum
```

## headphone_audio

- Name: Headphone Audio Level
- Category: Hearing
- HealthKit identifier: `HKQuantityTypeIdentifierHeadphoneAudioExposure`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
headphone_audio_db,71.5,dB,average
```

## environmental_audio

- Name: Environmental Sound Level
- Category: Hearing
- HealthKit identifier: `HKQuantityTypeIdentifierEnvironmentalAudioExposure`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
environmental_sound_db,54.2,dB,average
```

## environmental_sound_reduction

- Name: Environmental Sound Reduction
- Category: Hearing
- HealthKit identifier: `HKQuantityTypeIdentifierEnvironmentalSoundReduction`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKQuantityTypeIdentifierEnvironmentalSoundReduction` | `quantity` | direct |

## environmental_audio_exposure_event

- Name: Environmental Audio Exposure Event
- Category: Hearing
- HealthKit identifier: `HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierAudioExposureEvent` | `category` | direct |

## headphone_audio_exposure_event

- Name: Headphone Audio Exposure Event
- Category: Hearing
- HealthKit identifier: `HKCategoryTypeIdentifierHeadphoneAudioExposureEvent`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierHeadphoneAudioExposureEvent` | `category` | direct |

## audiograms

- Name: Audiograms
- Category: Hearing
- HealthKit identifier: `HKDataTypeIdentifierAudiogram`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKDataTypeIdentifierAudiogram` | `audiogram` | direct |

## mindful_minutes

- Name: Mindful Minutes
- Category: Mindfulness
- HealthKit identifier: `HKCategoryTypeIdentifierMindfulSession`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
mindful_minutes,18,min,duration_sum
```

## mindful_sessions

- Name: Mindful Sessions
- Category: Mindfulness
- HealthKit identifier: `HKCategoryTypeIdentifierMindfulSession`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
mindful_sessions,3,sessions,count
```

## state_of_mind_entries

- Name: Mood Entries
- Category: Mindfulness
- HealthKit identifier: `HKStateOfMind`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
mood_entries,3,entries,count
mood_labels,"[calm, content, neutral, worried]",,list
mood_associations,"[family, work]",,list
```

## daily_mood

- Name: Daily Mood
- Category: Mindfulness
- HealthKit identifier: `HKStateOfMind`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
daily_mood_count,1,count,count
daily_mood_percent,82,percent,average
```

## average_valence

- Name: Average Mood Valence
- Category: Mindfulness
- HealthKit identifier: `HKStateOfMind`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
average_mood_valence,0.13,,average
average_mood_percent,56,percent,average
```

## momentary_emotions

- Name: Momentary Emotions
- Category: Mindfulness
- HealthKit identifier: `HKStateOfMind`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
momentary_emotion_count,1,count,count
```

## gad7_assessments

- Name: GAD-7 Assessments
- Category: Mindfulness
- HealthKit identifier: `HKScoredAssessmentTypeIdentifierGAD7`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKScoredAssessmentTypeIdentifierGAD7` | `scored_assessment` | direct |

## phq9_assessments

- Name: PHQ-9 Assessments
- Category: Mindfulness
- HealthKit identifier: `HKScoredAssessmentTypeIdentifierPHQ9`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKScoredAssessmentTypeIdentifierPHQ9` | `scored_assessment` | direct |

## menstrual_flow

- Name: Menstrual Flow
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierMenstrualFlow`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
menstrual_flow,medium,,category_latest
```

## sexual_activity

- Name: Sexual Activity
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierSexualActivity`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
sexual_activity,1,,count
```

## ovulation_test

- Name: Ovulation Test Result
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierOvulationTestResult`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
ovulation_test,positive,,category_latest
```

## cervical_mucus

- Name: Cervical Mucus Quality
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierCervicalMucusQuality`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
cervical_mucus,egg_white,,category_latest
```

## intermenstrual_bleeding

- Name: Spotting
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierIntermenstrualBleeding`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
intermenstrual_bleeding,1,,count
```

## bleeding_after_pregnancy

- Name: Bleeding After Pregnancy
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierBleedingAfterPregnancy`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierBleedingAfterPregnancy` | `category` | direct |

## bleeding_during_pregnancy

- Name: Bleeding During Pregnancy
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierBleedingDuringPregnancy`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierBleedingDuringPregnancy` | `category` | direct |

## contraceptive

- Name: Contraceptive
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierContraceptive`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierContraceptive` | `category` | direct |

## infrequent_menstrual_cycles

- Name: Infrequent Menstrual Cycles
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierInfrequentMenstrualCycles`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierInfrequentMenstrualCycles` | `category` | direct |

## irregular_menstrual_cycles

- Name: Irregular Menstrual Cycles
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierIrregularMenstrualCycles`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierIrregularMenstrualCycles` | `category` | direct |

## lactation

- Name: Lactation
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierLactation`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierLactation` | `category` | direct |

## persistent_intermenstrual_bleeding

- Name: Persistent Intermenstrual Bleeding
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierPersistentIntermenstrualBleeding`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierPersistentIntermenstrualBleeding` | `category` | direct |

## pregnancy

- Name: Pregnancy
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierPregnancy`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierPregnancy` | `category` | direct |

## pregnancy_test_result

- Name: Pregnancy Test Result
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierPregnancyTestResult`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierPregnancyTestResult` | `category` | direct |

## progesterone_test_result

- Name: Progesterone Test Result
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierProgesteroneTestResult`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierProgesteroneTestResult` | `category` | direct |

## prolonged_menstrual_periods

- Name: Prolonged Menstrual Periods
- Category: Reproductive Health
- HealthKit identifier: `HKCategoryTypeIdentifierProlongedMenstrualPeriods`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKCategoryTypeIdentifierProlongedMenstrualPeriods` | `category` | direct |

## symptom_headache

- Name: Headache
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierHeadache`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_headache,1,,count
```

## symptom_fatigue

- Name: Fatigue
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierFatigue`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_fatigue,2,,count
```

## symptom_nausea

- Name: Nausea
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierNausea`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_nausea,3,,count
```

## symptom_dizziness

- Name: Dizziness
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierDizziness`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_dizziness,4,,count
```

## symptom_mood_changes

- Name: Mood Changes
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierMoodChanges`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_mood_changes,5,,count
```

## symptom_sleep_changes

- Name: Sleep Changes
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierSleepChanges`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_sleep_changes,6,,count
```

## symptom_appetite_changes

- Name: Appetite Changes
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierAppetiteChanges`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_appetite_changes,7,,count
```

## symptom_hot_flashes

- Name: Hot Flashes
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierHotFlashes`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_hot_flashes,8,,count
```

## symptom_chills

- Name: Chills
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierChills`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_chills,9,,count
```

## symptom_fever

- Name: Fever
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierFever`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_fever,10,,count
```

## symptom_lower_back_pain

- Name: Lower Back Pain
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierLowerBackPain`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_lower_back_pain,11,,count
```

## symptom_bloating

- Name: Bloating
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierBloating`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_bloating,12,,count
```

## symptom_constipation

- Name: Constipation
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierConstipation`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_constipation,13,,count
```

## symptom_diarrhea

- Name: Diarrhea
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierDiarrhea`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_diarrhea,14,,count
```

## symptom_heartburn

- Name: Heartburn
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierHeartburn`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_heartburn,15,,count
```

## symptom_coughing

- Name: Coughing
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierCoughing`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_coughing,16,,count
```

## symptom_sore_throat

- Name: Sore Throat
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierSoreThroat`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_sore_throat,17,,count
```

## symptom_runny_nose

- Name: Runny Nose
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierRunnyNose`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_runny_nose,18,,count
```

## symptom_shortness_of_breath

- Name: Shortness of Breath
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierShortnessOfBreath`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_shortness_of_breath,19,,count
```

## symptom_chest_pain

- Name: Chest Tightness or Pain
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierChestTightnessOrPain`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_chest_pain,20,,count
```

## symptom_skipped_heartbeat

- Name: Skipped Heartbeat
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierSkippedHeartbeat`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_skipped_heartbeat,21,,count
```

## symptom_rapid_heartbeat

- Name: Rapid/Pounding Heartbeat
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_rapid_heartbeat,22,,count
```

## symptom_acne

- Name: Acne
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierAcne`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_acne,23,,count
```

## symptom_dry_skin

- Name: Dry Skin
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierDrySkin`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_dry_skin,24,,count
```

## symptom_hair_loss

- Name: Hair Loss
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierHairLoss`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_hair_loss,25,,count
```

## symptom_memory_lapse

- Name: Memory Lapse
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierMemoryLapse`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_memory_lapse,26,,count
```

## symptom_night_sweats

- Name: Night Sweats
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierNightSweats`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_night_sweats,27,,count
```

## symptom_vomiting

- Name: Vomiting
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierVomiting`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_vomiting,28,,count
```

## symptom_abdominal_cramps

- Name: Abdominal Cramps
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierAbdominalCramps`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_abdominal_cramps,29,,count
```

## symptom_breast_pain

- Name: Breast Pain
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierBreastPain`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_breast_pain,30,,count
```

## symptom_pelvic_pain

- Name: Pelvic Pain
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierPelvicPain`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_pelvic_pain,31,,count
```

## symptom_body_ache

- Name: Generalized Body Ache
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierGeneralizedBodyAche`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_body_ache,32,,count
```

## symptom_fainting

- Name: Fainting
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierFainting`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_fainting,33,,count
```

## symptom_loss_of_smell

- Name: Loss of Smell
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierLossOfSmell`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_loss_of_smell,34,,count
```

## symptom_loss_of_taste

- Name: Loss of Taste
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierLossOfTaste`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_loss_of_taste,35,,count
```

## symptom_wheezing

- Name: Wheezing
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierWheezing`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_wheezing,36,,count
```

## symptom_sinus_congestion

- Name: Sinus Congestion
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierSinusCongestion`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_sinus_congestion,37,,count
```

## symptom_bladder_incontinence

- Name: Bladder Incontinence
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierBladderIncontinence`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_bladder_incontinence,38,,count
```

## symptom_vaginal_dryness

- Name: Vaginal Dryness
- Category: Symptoms
- HealthKit identifier: `HKCategoryTypeIdentifierVaginalDryness`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
symptom_vaginal_dryness,39,,count
```

## clinical_allergy_records

- Name: Allergy Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierAllergyRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierAllergyRecord` | `clinical` | direct |

## clinical_note_records

- Name: Clinical Notes
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierClinicalNoteRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierClinicalNoteRecord` | `clinical` | direct |

## clinical_condition_records

- Name: Condition Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierConditionRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierConditionRecord` | `clinical` | direct |

## clinical_coverage_records

- Name: Coverage Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierCoverageRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierCoverageRecord` | `clinical` | direct |

## clinical_immunization_records

- Name: Immunization Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierImmunizationRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierImmunizationRecord` | `clinical` | direct |

## clinical_lab_result_records

- Name: Lab Result Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierLabResultRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierLabResultRecord` | `clinical` | direct |

## clinical_medication_records

- Name: Clinical Medication Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierMedicationRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierMedicationRecord` | `clinical` | direct |

## clinical_procedure_records

- Name: Procedure Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierProcedureRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierProcedureRecord` | `clinical` | direct |

## clinical_vital_sign_records

- Name: Clinical Vital-Sign Records
- Category: Clinical Records
- HealthKit identifier: `HKClinicalTypeIdentifierVitalSignRecord`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKClinicalTypeIdentifierVitalSignRecord` | `clinical` | direct |

## cda_documents

- Name: CDA Documents
- Category: Clinical Documents
- HealthKit identifier: `HKDocumentTypeIdentifierCDA`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKDocumentTypeIdentifierCDA` | `document` | direct |

## verifiable_clinical_records

- Name: Verifiable Clinical Records
- Category: Clinical Documents
- HealthKit identifier: `HKVerifiableClinicalRecordTypeIdentifier`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKVerifiableClinicalRecordTypeIdentifier` | `verifiable_clinical_record` | direct |

## vision_prescriptions

- Name: Vision Prescriptions
- Category: Vision
- HealthKit identifier: `HKVisionPrescriptionTypeIdentifier`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `HKVisionPrescriptionTypeIdentifier` | `vision_prescription` | direct |

## medications

- Name: Medications
- Category: Medications
- HealthKit identifier: `HKMedicationDoseEventTypeIdentifierMedicationDoseEvent`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
medication_count,2,count,latest
active_medication_count,1,count,latest
archived_medication_count,1,count,latest
medication_details,"  - name: ""Thyroid""
    concept_identifier: ""rxnorm:617314""
    display_name: ""Levothyroxine Sodium 50 MCG Oral Tablet""
    general_form: ""tablet""
    is_archived: false
    has_schedule: true
    nickname: ""Thyroid""
    related_codings:
      - system: ""http://www.nlm.nih.gov/research/umls/rxnorm""
        version: ""2026AA""
        code: ""617314""
    rxnorm_codes:
      - ""617314""
  - name: ""Vitamin D""
    concept_identifier: ""custom:vitamin-d""
    display_name: ""Vitamin D""
    general_form: ""capsule""
    is_archived: true
    has_schedule: false",,list
medication_dose_count,2,count,count
medication_dose_events,"  - name: ""Thyroid""
    status: taken
    status_display: ""Taken""
    id: ""00000000-0000-0000-0000-000000000730""
    medication_concept_identifier: ""rxnorm:617314""
    start_date: ""2026-03-15T08:00:00Z""
    end_date: ""2026-03-15T08:00:30Z""
    schedule_type: scheduled
    scheduled_date: ""2026-03-15T08:00:00Z""
    dose_quantity: 1
    scheduled_dose_quantity: 1
    unit: ""tablet""
    metadata:
      ""with_food"": ""false""
  - name: ""custom:vitamin-d""
    status: skipped
    status_display: ""Skipped""
    id: ""00000000-0000-0000-0000-000000000731""
    medication_concept_identifier: ""custom:vitamin-d""
    start_date: ""2026-03-15T18:00:00Z""
    end_date: ""2026-03-15T18:00:00Z""
    schedule_type: as_needed
    dose_quantity: 2
    unit: ""capsule""
    metadata:
      ""reason"": ""not available""",,list
medication_taken_count,1,count,count
medication_skipped_count,1,count,count
medications,"[thyroid, vitamin-d]",,list
```

## uv_exposure

- Name: UV Exposure
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierUVExposure`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
uv_exposure,4.0,,maximum
```

## time_in_daylight

- Name: Time in Daylight
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierTimeInDaylight`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
time_in_daylight_min,92,min,minimum
```

## number_of_falls

- Name: Number of Falls
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierNumberOfTimesFallen`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
number_of_falls,1,falls,sum
```

## blood_alcohol

- Name: Blood Alcohol Content
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierBloodAlcoholContent`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
blood_alcohol_percent,0.001,percent,latest
```

## alcoholic_beverages

- Name: Alcoholic Beverages
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierNumberOfAlcoholicBeverages`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
alcoholic_beverages,1,drinks,sum
```

## insulin_delivery

- Name: Insulin Delivery
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierInsulinDelivery`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
insulin_delivery_iu,3.5,IU,sum
```

## toothbrushing

- Name: Toothbrushing
- Category: Other
- HealthKit identifier: `HKCategoryTypeIdentifierToothbrushingEvent`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
toothbrushing,2,events,count
```

## handwashing

- Name: Handwashing
- Category: Other
- HealthKit identifier: `HKCategoryTypeIdentifierHandwashingEvent`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
handwashing,8,events,count
```

## water_temperature

- Name: Water Temperature
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierWaterTemperature`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
water_temperature,19.5,°C,latest
```

## underwater_depth

- Name: Underwater Depth
- Category: Other
- HealthKit identifier: `HKQuantityTypeIdentifierUnderwaterDepth`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
underwater_depth_m,4.2,m,maximum
```

## workouts

- Name: Workouts
- Category: Workouts
- HealthKit identifier: `None`
- Export mode: `summary`

```csv
key,value,unit,daily_aggregation
workout_count,3,count,count
workout_minutes,135,min,duration_sum
workout_calories,1230,kcal,sum
workout_distance_km,31.50,km,sum
workout_distance_mi,19.57,mi,sum
workouts,"[cycling, running, swimming]",,list
workout_avg_heart_rate,143,bpm,weighted_average
workout_max_heart_rate,172,bpm,count
workout_min_heart_rate,88,bpm,count
workout_running_cadence,176,spm,weighted_average
workout_running_stride_length,1.18,m,weighted_average
workout_running_ground_contact,238,ms,weighted_average
workout_running_vertical_oscillation,8.1,cm,weighted_average
workout_cycling_cadence,86,rpm,weighted_average
workout_avg_power,258,W,weighted_average
workout_max_power,430,W,count
```

## scheduled_workout_plans

- Name: Scheduled Workout Plans
- Category: Workouts
- HealthKit identifier: `WorkoutKitScheduledWorkoutPlan`
- Export mode: `archive-only`

| Reviewed object type | Canonical record kind | Attribution |
|---|---|---|
| `WorkoutKitScheduledWorkoutPlan` | `scheduledWorkoutPlan` | direct |
