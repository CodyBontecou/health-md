# iOS Export Contract (Canonical Source of Truth)

**Status:** canonical iOS contract for Android parity work  
**Last verified:** 2026-04-21  
**Source repo:** `/Users/codybontecou/projects/health-md/app`

## Source files (authoritative)

1. JSON exporter
   - `HealthMd/Shared/Export/JSONExporter.swift`
2. CSV exporter
   - `HealthMd/Shared/Export/CSVExporter.swift`
3. Obsidian Bases / frontmatter exporter
   - `HealthMd/Shared/Export/ObsidianBasesExporter.swift`
4. Canonical flat key builder + mapping
   - `HealthMd/Shared/Export/HealthMetricsDictionary.swift`
5. Shared snapshot/hasData behavior
   - `HealthMd/Shared/Export/ExportDataSnapshot.swift`
6. Contract fixtures/tests used for examples
   - `HealthMdTests/Fixtures/Export/ExportFixtures.swift`
   - `HealthMdTests/Export/JSONExporterContractTests.swift`
   - `HealthMdTests/Export/CSVExporterContractTests.swift`
   - `HealthMdTests/Export/ObsidianBasesContractTests.swift`

---

## 1) JSON contract

### 1.1 Top-level schema

```yaml
required_top_level:
  date: string   # DateFormatPreference (default yyyy-MM-dd)
  type: string   # always "health-data"
  units: string  # "metric" or "imperial" (lowercase)

optional_top_level_categories:
  - sleep
  - activity
  - heart
  - vitals
  - body
  - nutrition
  - mindfulness
  - mobility
  - hearing
  - workouts
  - reproductiveHealth
  - cyclingPerformance
  - vitamins
  - minerals
  - symptoms
  - other

presence_rule:
  - categories are omitted when no data exists for that category
  - inside included categories, fields are conditionally present (no fixed required set)
```

### 1.2 Category field graph (machine-readable key inventory)

```yaml
json_category_keys:
  sleep:
    - totalDuration
    - totalDurationFormatted
    - bedtime
    - bedtimeISO
    - wakeTime
    - wakeTimeISO
    - deepSleep
    - deepSleepFormatted
    - remSleep
    - remSleepFormatted
    - coreSleep
    - coreSleepFormatted
    - awakeTime
    - awakeTimeFormatted
    - inBedTime
    - inBedTimeFormatted
    - sleepStages
  activity:
    - steps
    - activeCalories
    - basalEnergyBurned
    - exerciseMinutes
    - standHours
    - flightsClimbed
    - walkingRunningDistance
    - walkingRunningDistanceKm
    - cyclingDistance
    - cyclingDistanceKm
    - swimmingDistance
    - swimmingStrokes
    - pushCount
    - vo2Max
    - wheelchairDistanceKm
    - downhillSnowSportsDistanceKm
    - moveMinutes
    - physicalEffort
  heart:
    - restingHeartRate
    - walkingHeartRateAverage
    - averageHeartRate
    - heartRateMin
    - heartRateMax
    - hrv
    - heartRateRecovery
    - atrialFibrillationBurdenPercent
    - heartRateSamples
    - hrvSamples
  vitals:
    - respiratoryRateAvg
    - respiratoryRate              # backward-compat alias
    - respiratoryRateMin
    - respiratoryRateMax
    - bloodOxygenAvg
    - bloodOxygen                  # backward-compat alias
    - bloodOxygenPercent
    - bloodOxygenMin
    - bloodOxygenMinPercent
    - bloodOxygenMax
    - bloodOxygenMaxPercent
    - bodyTemperatureAvg
    - bodyTemperature              # backward-compat alias
    - bodyTemperatureMin
    - bodyTemperatureMax
    - bloodPressureSystolicAvg
    - bloodPressureSystolic        # backward-compat alias
    - bloodPressureSystolicMin
    - bloodPressureSystolicMax
    - bloodPressureDiastolicAvg
    - bloodPressureDiastolic       # backward-compat alias
    - bloodPressureDiastolicMin
    - bloodPressureDiastolicMax
    - bloodGlucoseAvg
    - bloodGlucose                 # backward-compat alias
    - bloodGlucoseMin
    - bloodGlucoseMax
    - basalBodyTemperature
    - wristTemperature
    - electrodermalActivity
    - forcedVitalCapacityL
    - fev1L
    - peakExpiratoryFlow
    - inhalerUsage
    - bloodOxygenSamples
    - bloodGlucoseSamples
    - respiratoryRateSamples
  body:
    - weight
    - height
    - bmi
    - bodyFatPercentage
    - bodyFatPercent
    - leanBodyMass
    - waistCircumference
  nutrition:
    - dietaryEnergy
    - protein
    - carbohydrates
    - fat
    - saturatedFat
    - fiber
    - sugar
    - sodium
    - cholesterol
    - water
    - caffeine
    - monounsaturatedFat
    - polyunsaturatedFat
  mindfulness:
    - mindfulMinutes
    - mindfulSessions
    - stateOfMindCount
    - averageValence
    - averageValencePercent
    - dailyMoodCount
    - averageDailyMoodValence
    - momentaryEmotionCount
    - emotionLabels
    - associations
    - stateOfMindEntries
  mobility:
    - walkingSpeed
    - walkingStepLength
    - walkingDoubleSupportPercentage
    - walkingAsymmetryPercentage
    - stairAscentSpeed
    - stairDescentSpeed
    - sixMinuteWalkDistance
    - walkingSteadinessPercent
    - runningSpeed
    - runningStrideLengthM
    - runningGroundContactMs
    - runningVerticalOscillationCm
    - runningPowerW
  hearing:
    - headphoneAudioLevel
    - environmentalSoundLevel
  workouts:
    item_keys:
      - type
      - startTime
      - duration
      - durationFormatted
      - distance
      - distanceFormatted
      - calories
  reproductiveHealth:
    dynamic_keys_from_metricsForCategory_reproductiveHealth: true
    key_style: snake_case
  cyclingPerformance:
    dynamic_keys_from_metricsForCategory_cycling: true
    key_style: snake_case
  vitamins:
    dynamic_keys_from_metricsForCategory_vitamins: true
    key_style: snake_case
  minerals:
    dynamic_keys_from_metricsForCategory_minerals: true
    key_style: snake_case
  symptoms:
    dynamic_keys: symptom_* -> integer_count
  other:
    dynamic_keys_from_metricsForCategory_other: true
    key_style: snake_case_or_numeric
```

### 1.3 Array item shapes

```yaml
array_item_shapes:
  sleep.sleepStages[]:
    stage: string
    startDate: string   # ISO8601
    endDate: string     # ISO8601
    durationSeconds: number

  heart.heartRateSamples[]:
    timestamp: string   # ISO8601
    value: number

  heart.hrvSamples[]:
    timestamp: string   # ISO8601
    value: number

  vitals.bloodOxygenSamples[]:
    timestamp: string   # ISO8601
    value: number       # fraction (0-1)

  vitals.bloodGlucoseSamples[]:
    timestamp: string   # ISO8601
    value: number

  vitals.respiratoryRateSamples[]:
    timestamp: string   # ISO8601
    value: number

  mindfulness.stateOfMindEntries[]:
    timestamp: string   # formatted by TimeFormatPreference, not ISO8601
    kind: string
    valence: number
    valencePercent: number
    valenceDescription: string
    labels: [string]           # optional
    associations: [string]     # optional
```

### 1.4 Fully populated day example (from `ExportFixtures.fullDayGranular`)

```json
{
  "date": "2026-03-15",
  "type": "health-data",
  "units": "metric",
  "sleep": {
    "totalDuration": 27900,
    "totalDurationFormatted": "7h 45m",
    "deepSleep": 5400,
    "deepSleepFormatted": "1h 30m",
    "remSleep": 8100,
    "remSleepFormatted": "2h 15m",
    "coreSleep": 14400,
    "coreSleepFormatted": "4h 0m",
    "awakeTime": 900,
    "awakeTimeFormatted": "15m",
    "inBedTime": 28800,
    "inBedTimeFormatted": "8h 0m",
    "sleepStages": [
      { "stage": "deep",  "startDate": "2026-03-14T22:00:00Z", "endDate": "2026-03-14T23:30:00Z", "durationSeconds": 5400 },
      { "stage": "rem",   "startDate": "2026-03-14T23:30:00Z", "endDate": "2026-03-15T01:30:00Z", "durationSeconds": 7200 },
      { "stage": "core",  "startDate": "2026-03-15T01:30:00Z", "endDate": "2026-03-15T04:30:00Z", "durationSeconds": 10800 },
      { "stage": "awake", "startDate": "2026-03-15T04:30:00Z", "endDate": "2026-03-15T04:45:00Z", "durationSeconds": 900 }
    ]
  },
  "activity": {
    "steps": 12500,
    "activeCalories": 520,
    "basalEnergyBurned": 1650,
    "exerciseMinutes": 45,
    "standHours": 11,
    "flightsClimbed": 8,
    "walkingRunningDistance": 9500,
    "walkingRunningDistanceKm": 9.5,
    "cyclingDistance": 3200,
    "cyclingDistanceKm": 3.2,
    "vo2Max": 42.5
  },
  "heart": {
    "restingHeartRate": 58,
    "walkingHeartRateAverage": 105,
    "averageHeartRate": 72,
    "heartRateMin": 52,
    "heartRateMax": 155,
    "hrv": 42,
    "heartRateSamples": [
      { "timestamp": "2026-03-15T06:00:00Z", "value": 55 },
      { "timestamp": "2026-03-15T09:00:00Z", "value": 72 }
    ],
    "hrvSamples": [
      { "timestamp": "2026-03-15T06:00:00Z", "value": 45 },
      { "timestamp": "2026-03-15T20:00:00Z", "value": 38 }
    ]
  },
  "vitals": {
    "respiratoryRateAvg": 15,
    "respiratoryRate": 15,
    "respiratoryRateMin": 12,
    "respiratoryRateMax": 18,
    "bloodOxygenAvg": 0.97,
    "bloodOxygen": 0.97,
    "bloodOxygenPercent": 97,
    "bloodOxygenMin": 0.94,
    "bloodOxygenMinPercent": 94,
    "bloodOxygenMax": 0.99,
    "bloodOxygenMaxPercent": 99,
    "bloodOxygenSamples": [
      { "timestamp": "2026-03-15T06:00:00Z", "value": 0.96 },
      { "timestamp": "2026-03-15T12:00:00Z", "value": 0.98 }
    ],
    "bloodGlucoseSamples": [
      { "timestamp": "2026-03-15T09:00:00Z", "value": 90 },
      { "timestamp": "2026-03-15T15:00:00Z", "value": 110 }
    ],
    "respiratoryRateSamples": [
      { "timestamp": "2026-03-15T06:00:00Z", "value": 14 },
      { "timestamp": "2026-03-15T12:00:00Z", "value": 16 }
    ]
  },
  "body": {
    "weight": 75,
    "height": 1.78,
    "bmi": 23.7,
    "bodyFatPercentage": 0.18,
    "bodyFatPercent": 18
  },
  "nutrition": {
    "dietaryEnergy": 2100,
    "protein": 120,
    "carbohydrates": 250,
    "fat": 70,
    "fiber": 25,
    "sugar": 45,
    "water": 2.5,
    "caffeine": 200
  },
  "mindfulness": {
    "mindfulMinutes": 15,
    "mindfulSessions": 2
  },
  "mobility": {
    "walkingSpeed": 1.4,
    "walkingStepLength": 0.72,
    "walkingDoubleSupportPercentage": 0.28
  },
  "hearing": {
    "headphoneAudioLevel": 72,
    "environmentalSoundLevel": 55
  },
  "workouts": [
    {
      "type": "Running",
      "startTime": "00:00",
      "duration": 1800,
      "durationFormatted": "30m",
      "distance": 5000,
      "distanceFormatted": "5.00 km",
      "calories": 300
    }
  ]
}
```

### 1.5 Sparse day example (from `ExportFixtures.partialDay`)

```json
{
  "date": "2026-03-15",
  "type": "health-data",
  "units": "metric",
  "sleep": {
    "totalDuration": 27000,
    "totalDurationFormatted": "7h 30m",
    "deepSleep": 5400,
    "deepSleepFormatted": "1h 30m",
    "remSleep": 7200,
    "remSleepFormatted": "2h 0m",
    "coreSleep": 14400,
    "coreSleepFormatted": "4h 0m"
  },
  "activity": {
    "steps": 8500,
    "activeCalories": 350,
    "exerciseMinutes": 32,
    "flightsClimbed": 5,
    "walkingRunningDistance": 6200,
    "walkingRunningDistanceKm": 6.2
  }
}
```

---

## 2) Markdown frontmatter / Obsidian Bases contract

## 2.1 Format behavior

- **Obsidian Bases export (`toObsidianBases`)** writes only YAML frontmatter.
- **Markdown export (`toMarkdown`)** frontmatter is metadata-oriented (`date`, `type`, custom fields, placeholder fields). Health metric keys are represented in markdown sections, not injected as the full metric flat map.
- **Daily note injection** uses the same canonical flat key mapping as Obsidian Bases (`HealthMetricExportMapping` + `allMetricsDictionary`).

## 2.2 Frontmatter key style

```yaml
default_key_style: snake_case
optional_key_style: camelCase
style_conversion_examples:
  sleep_total_hours: sleepTotalHours
  active_calories: activeCalories
  resting_heart_rate: restingHeartRate
  hrv_ms: hrvMs
```

## 2.3 Canonical frontmatter key list (all known keys)

```yaml
core_metadata_keys:
  - date
  - type

frontmatter_keys_by_domain:
  sleep: [sleep_total_hours, sleep_bedtime, sleep_wake, sleep_deep_hours, sleep_rem_hours, sleep_core_hours, sleep_awake_hours, sleep_in_bed_hours]
  activity: [steps, active_calories, basal_calories, exercise_minutes, stand_hours, flights_climbed, walking_running_km, swimming_m, swimming_strokes, wheelchair_pushes, vo2_max]
  cycling: [cycling_km]
  heart: [resting_heart_rate, walking_heart_rate, average_heart_rate, heart_rate_min, heart_rate_max, hrv_ms]
  respiratory: [respiratory_rate, respiratory_rate_avg, respiratory_rate_min, respiratory_rate_max, blood_oxygen, blood_oxygen_avg, blood_oxygen_min, blood_oxygen_max]
  vitals: [body_temperature, body_temperature_avg, body_temperature_min, body_temperature_max, blood_pressure_systolic, blood_pressure_systolic_avg, blood_pressure_systolic_min, blood_pressure_systolic_max, blood_pressure_diastolic, blood_pressure_diastolic_avg, blood_pressure_diastolic_min, blood_pressure_diastolic_max, blood_glucose, blood_glucose_avg, blood_glucose_min, blood_glucose_max]
  body_measurements: [weight_kg, height_m, bmi, body_fat_percent, lean_body_mass_kg, waist_circumference_cm]
  nutrition: [dietary_calories, protein_g, carbohydrates_g, fat_g, saturated_fat_g, fiber_g, sugar_g, sodium_mg, cholesterol_mg, water_l, caffeine_mg]
  mindfulness: [mindful_minutes, mindful_sessions, daily_mood_count, daily_mood_percent, momentary_emotion_count, average_mood_valence, average_mood_percent]
  mobility: [walking_speed, step_length_cm, double_support_percent, walking_asymmetry_percent, stair_ascent_speed, stair_descent_speed, six_min_walk_m]
  hearing: [headphone_audio_db, environmental_sound_db]
  reproductive_health: [menstrual_flow, sexual_activity, ovulation_test, cervical_mucus, intermenstrual_bleeding]
  additional_activity: [wheelchair_km, downhill_snow_km, move_minutes, physical_effort]
  additional_heart: [heart_rate_recovery, afib_burden_percent]
  additional_vitals_respiratory: [basal_body_temperature, wrist_temperature, electrodermal_activity, forced_vital_capacity_l, fev1_l, peak_expiratory_flow, inhaler_usage]
  additional_nutrition: [monounsaturated_fat_g, polyunsaturated_fat_g]
  additional_mobility: [walking_steadiness_percent, running_speed, running_stride_length_m, running_ground_contact_ms, running_vertical_oscillation_cm, running_power_w]
  cycling_performance: [cycling_speed, cycling_power_w, cycling_cadence_rpm, cycling_ftp_w]
  vitamins: [vitamin_a_ug, vitamin_b6_mg, vitamin_b12_ug, vitamin_c_mg, vitamin_d_ug, vitamin_e_mg, vitamin_k_ug, thiamin_mg, riboflavin_mg, niacin_mg, folate_ug, biotin_ug, pantothenic_acid_mg]
  minerals: [calcium_mg, iron_mg, potassium_mg, magnesium_mg, phosphorus_mg, zinc_mg, selenium_ug, copper_mg, manganese_mg, chromium_ug, molybdenum_ug, chloride_mg, iodine_ug]
  symptoms:
    - symptom_headache
    - symptom_fatigue
    - symptom_nausea
    - symptom_dizziness
    - symptom_mood_changes
    - symptom_sleep_changes
    - symptom_appetite_changes
    - symptom_hot_flashes
    - symptom_chills
    - symptom_fever
    - symptom_lower_back_pain
    - symptom_bloating
    - symptom_constipation
    - symptom_diarrhea
    - symptom_heartburn
    - symptom_coughing
    - symptom_sore_throat
    - symptom_runny_nose
    - symptom_shortness_of_breath
    - symptom_chest_pain
    - symptom_skipped_heartbeat
    - symptom_rapid_heartbeat
    - symptom_acne
    - symptom_dry_skin
    - symptom_hair_loss
    - symptom_memory_lapse
    - symptom_night_sweats
    - symptom_vomiting
    - symptom_abdominal_cramps
    - symptom_breast_pain
    - symptom_pelvic_pain
    - symptom_body_ache
    - symptom_fainting
    - symptom_loss_of_smell
    - symptom_loss_of_taste
    - symptom_wheezing
    - symptom_sinus_congestion
    - symptom_bladder_incontinence
    - symptom_vaginal_dryness
  other: [uv_exposure, time_in_daylight_min, number_of_falls, blood_alcohol_percent, alcoholic_beverages, insulin_delivery_iu, toothbrushing, handwashing, water_temperature, underwater_depth_m]
  workouts: [workout_count, workout_minutes, workout_calories, workout_distance_km, workouts]
```

### 2.4 Fully populated Obsidian Bases example (excerpt)

```yaml
---
date: 2026-03-15
type: health-data
sleep_total_hours: 7.75
sleep_deep_hours: 1.50
sleep_rem_hours: 2.25
sleep_core_hours: 4.00
sleep_awake_hours: 0.25
sleep_in_bed_hours: 8.00
steps: 12500
active_calories: 520
basal_calories: 1650
exercise_minutes: 45
stand_hours: 11
flights_climbed: 8
walking_running_km: 9.50
cycling_km: 3.20
vo2_max: 42.5
resting_heart_rate: 58
walking_heart_rate: 105
average_heart_rate: 72
heart_rate_min: 52
heart_rate_max: 155
hrv_ms: 42.0
respiratory_rate: 15.0
respiratory_rate_avg: 15.0
respiratory_rate_min: 12.0
respiratory_rate_max: 18.0
blood_oxygen: 97
blood_oxygen_avg: 97
blood_oxygen_min: 94
blood_oxygen_max: 99
weight_kg: 75.0
height_m: 178.00
bmi: 23.7
body_fat_percent: 18.0
dietary_calories: 2100
protein_g: 120.0
carbohydrates_g: 250.0
fat_g: 70.0
fiber_g: 25.0
sugar_g: 45.0
water_l: 2.50
caffeine_mg: 200.0
mindful_minutes: 15
mindful_sessions: 2
walking_speed: 1.40
step_length_cm: 72.0
double_support_percent: 28.0
headphone_audio_db: 72.0
environmental_sound_db: 55.0
workout_count: 1
workout_minutes: 30
workout_calories: 300
workout_distance_km: 5.00
workouts: [running]
---
```

### 2.5 Sparse Obsidian Bases example

```yaml
---
date: 2026-03-15
type: health-data
sleep_total_hours: 7.50
sleep_deep_hours: 1.50
sleep_rem_hours: 2.00
sleep_core_hours: 4.00
steps: 8500
active_calories: 350
exercise_minutes: 32
flights_climbed: 5
walking_running_km: 6.20
---
```

---

## 3) CSV contract

### 3.1 Header and row shape

```yaml
header: [Date, Category, Metric, Value, Unit, Timestamp]
row_rules:
  - aggregate rows are typically 5 columns (Timestamp omitted)
  - sample/timeseries rows include Timestamp (6th column)
  - Date is formatted by DateFormatPreference (default yyyy-MM-dd)
```

### 3.2 Category + metric label taxonomy + units

```yaml
csv_taxonomy:
  Sleep:
    - [Total Duration, seconds]
    - [Bedtime, time]
    - [Wake Time, time]
    - [Deep Sleep, seconds]
    - [REM Sleep, seconds]
    - [Core Sleep, seconds]
    - [Awake Time, seconds]
    - [In Bed Time, seconds]
    - [Sleep Stage, seconds, timestamped]

  Activity:
    - [Steps, count]
    - [Active Calories, kcal]
    - [Basal Energy, kcal]
    - [Exercise Minutes, minutes]
    - [Stand Hours, hours]
    - [Flights Climbed, count]
    - [Walking Running Distance, meters]
    - [Cycling Distance, meters]
    - [Swimming Distance, meters]
    - [Swimming Strokes, count]
    - [Wheelchair Pushes, count]
    - [Cardio Fitness (VO2 Max), mL/kg/min]
    - [Wheelchair Distance, km|mi (depends on units)]
    - [Downhill Snow Sports Distance, km|mi (depends on units)]
    - [Move Time, min]
    - [Physical Effort, kcal/hr/kg]

  Heart:
    - [Resting Heart Rate, bpm]
    - [Walking Heart Rate Average, bpm]
    - [Average Heart Rate, bpm]
    - [Min Heart Rate, bpm]
    - [Max Heart Rate, bpm]
    - [HRV, ms]
    - [Heart Rate Sample, bpm, timestamped]
    - [HRV Sample, ms, timestamped]
    - [Heart Rate Recovery, bpm]
    - [AFib Burden, %]

  Vitals:
    - [Respiratory Rate Avg, breaths/min]
    - [Respiratory Rate Min, breaths/min]
    - [Respiratory Rate Max, breaths/min]
    - [Blood Oxygen Avg, percent]
    - [Blood Oxygen Min, percent]
    - [Blood Oxygen Max, percent]
    - [Body Temperature Avg, °C|°F (depends on units)]
    - [Body Temperature Min, °C|°F (depends on units)]
    - [Body Temperature Max, °C|°F (depends on units)]
    - [Blood Pressure Systolic Avg, mmHg]
    - [Blood Pressure Systolic Min, mmHg]
    - [Blood Pressure Systolic Max, mmHg]
    - [Blood Pressure Diastolic Avg, mmHg]
    - [Blood Pressure Diastolic Min, mmHg]
    - [Blood Pressure Diastolic Max, mmHg]
    - [Blood Glucose Avg, mg/dL]
    - [Blood Glucose Min, mg/dL]
    - [Blood Glucose Max, mg/dL]
    - [Blood Oxygen Sample, percent, timestamped]
    - [Blood Glucose Sample, mg/dL, timestamped]
    - [Respiratory Rate Sample, breaths/min, timestamped]
    - [Basal Body Temperature, °C|°F (depends on units)]
    - [Wrist Temperature, °C]
    - [Electrodermal Activity, µS]
    - [Forced Vital Capacity, L]
    - [FEV1, L]
    - [Peak Expiratory Flow, L/min]
    - [Inhaler Usage, uses]

  Body:
    - [Weight, kg|lbs (depends on units)]
    - [Height, cm|ft/in (depends on units)]
    - [BMI, ""]
    - [Body Fat Percentage, percent]
    - [Lean Body Mass, kg|lbs (depends on units)]
    - [Waist Circumference, cm|in (depends on units)]

  Nutrition:
    - [Dietary Energy, kcal]
    - [Protein, g]
    - [Carbohydrates, g]
    - [Fat, g]
    - [Saturated Fat, g]
    - [Fiber, g]
    - [Sugar, g]
    - [Sodium, mg]
    - [Cholesterol, mg]
    - [Water, L]
    - [Caffeine, mg]
    - [Monounsaturated Fat, g]
    - [Polyunsaturated Fat, g]

  Mindfulness:
    - [Mindful Minutes, minutes]
    - [Mindful Sessions, count]
    - [State of Mind Entries, count]
    - [Average Mood Valence, scale(-1 to 1)]
    - [Average Mood Percent, percent]
    - [Daily Mood Count, count]
    - [Momentary Emotion Count, count]

  State of Mind:
    - ["<kind> at <time>", valence]
    - ["<kind> Labels at <time>", labels]
    - ["<kind> Associations at <time>", associations]

  Mobility:
    - [Walking Speed, m/s]
    - [Walking Step Length, meters]
    - [Double Support Percentage, percent]
    - [Walking Asymmetry, percent]
    - [Stair Ascent Speed, m/s]
    - [Stair Descent Speed, m/s]
    - [Six Minute Walk Distance, meters]
    - [Walking Steadiness, %]
    - [Running Speed, m/s]
    - [Running Stride Length, m]
    - [Running Ground Contact Time, ms]
    - [Running Vertical Oscillation, cm]
    - [Running Power, W]

  Hearing:
    - [Headphone Audio Level, dB]
    - [Environmental Sound Level, dB]

  Workouts:
    - ["<WorkoutType> Start Time", time]
    - ["<WorkoutType> Duration", seconds]
    - ["<WorkoutType> Distance", km|mi (depends on units)]
    - ["<WorkoutType> Calories", kcal]

  Reproductive Health:
    labels_from_health_metrics: [Menstrual Flow, Sexual Activity, Ovulation Test Result, Cervical Mucus Quality, Spotting]
    unit_column: ""   # currently blank in exporter

  Cycling:
    labels_from_health_metrics: [Cycling Distance, Cycling Speed, Cycling Power, Cycling Cadence, Functional Threshold Power]
    unit_column: ""   # currently blank in exporter

  Vitamins:
    labels_from_health_metrics: [Vitamin A, Vitamin B6, Vitamin B12, Vitamin C, Vitamin D, Vitamin E, Vitamin K, Thiamin (B1), Riboflavin (B2), Niacin (B3), Folate, Biotin, Pantothenic Acid (B5)]
    unit_column: ""   # currently blank in exporter

  Minerals:
    labels_from_health_metrics: [Calcium, Iron, Potassium, Magnesium, Phosphorus, Zinc, Selenium, Copper, Manganese, Chromium, Molybdenum, Chloride, Iodine]
    unit_column: ""   # currently blank in exporter

  Symptoms:
    labels_rule: "frontmatter key symptom_* -> title-cased label (e.g., symptom_headache -> Headache)"
    unit_column: count

  Other:
    labels_from_health_metrics: [UV Exposure, Time in Daylight, Number of Falls, Blood Alcohol Content, Alcoholic Beverages, Insulin Delivery, Toothbrushing, Handwashing, Water Temperature, Underwater Depth]
    unit_column: ""   # currently blank in exporter
```

### 3.3 Fully populated CSV example (excerpt)

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Sleep,Total Duration,27900,seconds
2026-03-15,Sleep,Deep Sleep,5400,seconds
2026-03-15,Sleep,Sleep Stage,deep (5400s),seconds,2026-03-14T22:00:00Z
2026-03-15,Activity,Steps,12500,count
2026-03-15,Activity,Cardio Fitness (VO2 Max),42.5,mL/kg/min
2026-03-15,Heart,Resting Heart Rate,58,bpm
2026-03-15,Heart,Heart Rate Sample,55,bpm,2026-03-15T06:00:00Z
2026-03-15,Vitals,Blood Oxygen Avg,97.0,percent
2026-03-15,Vitals,Blood Oxygen Sample,96.0,percent,2026-03-15T06:00:00Z
2026-03-15,Body,Weight,75.0,kg
2026-03-15,Nutrition,Protein,120.0,g
2026-03-15,Workouts,Running Duration,1800,seconds
```

### 3.4 Sparse CSV example (from `partialDay`)

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Sleep,Total Duration,27000,seconds
2026-03-15,Sleep,Deep Sleep,5400,seconds
2026-03-15,Sleep,REM Sleep,7200,seconds
2026-03-15,Sleep,Core Sleep,14400,seconds
2026-03-15,Activity,Steps,8500,count
2026-03-15,Activity,Active Calories,350.0,kcal
2026-03-15,Activity,Exercise Minutes,32.0,minutes
2026-03-15,Activity,Walking Running Distance,6200.0,meters
```

---

## 4) Compatibility-critical fields for `obsidian-health-md` visualizations

Source plugin repo: `/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md`

### 4.1 Must-preserve JSON fields

- `type == "health-data"`, `date` (loader gate)
  - `src/parsers/json-parser.ts`
- **Sleep architecture / schedule / polar charts**
  - `sleep.sleepStages[]` with `stage`, `startDate`, `endDate`, `durationSeconds`
  - fallback aggregate fields: `sleep.totalDuration`, `sleep.deepSleep`, `sleep.remSleep`, `sleep.coreSleep`
  - `src/visualizations/sleep-architecture.ts`, `sleep-polar.ts`, `sleep-schedule.ts`
- **Heart terrain / HRV trend / window recomputation**
  - `heart.heartRateSamples[]`, `heart.hrvSamples[]`
  - aggregate fallback: `heart.averageHeartRate`, `heart.heartRateMin`, `heart.heartRateMax`, `heart.hrv`, `heart.restingHeartRate`
  - `src/visualizations/heart-terrain.ts`, `hrv-trend.ts`, `renderer.ts`
- **Oxygen and breathing charts**
  - `vitals.bloodOxygenSamples[]`, `vitals.respiratoryRateSamples[]`
  - fallback aggregate aliases: `bloodOxygenAvg|bloodOxygenPercent|bloodOxygenMin|bloodOxygenMax`, `respiratoryRateAvg|respiratoryRate|respiratoryRateMin|respiratoryRateMax`
  - `src/visualizations/oxygen-river.ts`, `oxygen-range.ts`, `breathing-wave.ts`, `summary-card.ts`
- **VO2 trend tile placement**
  - `activity.vo2Max` (must remain under `activity`, not moved)
  - `src/visualizations/trend-tile.ts`

### 4.2 Must-preserve frontmatter/Bases keys (markdown parser)

Parser expects/normalizes these canonical keys:

- Sleep: `sleep_total_hours`, `sleep_deep_hours`, `sleep_rem_hours`, `sleep_core_hours`, `sleep_bedtime`, `sleep_wake`
- Activity: `steps`, `active_calories`, `exercise_minutes`, `walking_running_km`, `vo2_max`
- Heart: `resting_heart_rate`, `average_heart_rate`, `heart_rate_min`, `heart_rate_max`, `hrv_ms`
- Vitals: `respiratory_rate`, `blood_oxygen` (or `blood_oxygen_avg`)

Source: `src/parsers/markdown-parser.ts`

### 4.3 CSV parser sensitivity

Current plugin CSV parser matches exact labels in `Category` + `Metric` columns (case-insensitive) and only a subset of fields.

Source: `src/parsers/csv-parser.ts`

---

## 5) Contract semantics summary

1. **Top-level JSON required keys** are always: `date`, `type`, `units`.
2. **All category objects are optional** and omitted when empty.
3. **Granular arrays are optional** and present only when granular data exists.
4. **Obsidian/Bases flat keys are canonicalized in snake_case** and can be style-transformed (camelCase) by config.
5. **CSV taxonomy is label-based** and currently includes mixed static and dynamic label generation.
6. **Plugin compatibility depends on exact field placement** for sleep stages, heart/vitals sample arrays, and `activity.vo2Max`.
