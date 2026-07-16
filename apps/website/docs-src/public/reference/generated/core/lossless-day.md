---
schema: healthmd.health_data
schema_version: 7
time_context:
  calendar_timezone: UTC
  timestamp_timezone: UTC
date: 2026-03-15
type: health-data
raw_capture_status: partial
raw_record_count: 20
raw_query_failure_count: 2
raw_integrity_warning_count: 2
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
active_calories: 520
active_medication_count: 1
afib_burden_percent: 1.2
alcoholic_beverages: 1
archived_medication_count: 1
average_heart_rate: 72
average_mood_percent: 56
average_mood_valence: 0.13
basal_body_temperature: 36.5
basal_calories: 1650
biotin_ug: 30.0
blood_alcohol_percent: 0.001
blood_glucose: 102.0
blood_glucose_avg: 102.0
blood_glucose_max: 138.0
blood_glucose_min: 82.0
blood_oxygen: 97
blood_oxygen_avg: 97
blood_oxygen_max: 99
blood_oxygen_min: 94
blood_pressure_diastolic: 79
blood_pressure_diastolic_avg: 79
blood_pressure_diastolic_max: 84
blood_pressure_diastolic_min: 74
blood_pressure_systolic: 121
blood_pressure_systolic_avg: 121
blood_pressure_systolic_max: 127
blood_pressure_systolic_min: 116
bmi: 23.7
body_fat_percent: 18.0
body_temperature: 36.7
body_temperature_avg: 36.7
body_temperature_max: 37.1
body_temperature_min: 36.3
caffeine_mg: 200.0
calcium_mg: 1000.0
carbohydrates_g: 250.0
cervical_mucus: egg_white
chloride_mg: 2300.0
cholesterol_mg: 180.0
chromium_ug: 35.0
copper_mg: 0.900
cycling_cadence_rpm: 88
cycling_ftp_w: 260
cycling_km: 3.20
cycling_mi: 1.99
cycling_power_w: 215
cycling_speed: 8.20
daily_mood_count: 1
daily_mood_percent: 82
dietary_calories: 2100
double_support_percent: 27.0
downhill_snow_km: 2.30
downhill_snow_mi: 1.43
electrodermal_activity: 1.75
environmental_sound_db: 54.2
exercise_minutes: 45
fat_g: 70.0
fev1_l: 3.90
fiber_g: 25.0
flights_climbed: 8
folate_ug: 400.0
forced_vital_capacity_l: 4.80
handwashing: 8
headphone_audio_db: 71.5
heart_rate_max: 155
heart_rate_min: 52
heart_rate_recovery: 24
height_m: 1.78
hrv_ms: 42.0
inhaler_usage: 2
insulin_delivery_iu: 3.5
intermenstrual_bleeding: 1
iodine_ug: 150.0
iron_mg: 18.00
lean_body_mass_kg: 61.5
magnesium_mg: 420.0
manganese_mg: 2.30
medication_count: 2
medication_details:
  - name: "Thyroid"
    concept_identifier: "rxnorm:617314"
    display_name: "Levothyroxine Sodium 50 MCG Oral Tablet"
    general_form: "tablet"
    is_archived: false
    has_schedule: true
    nickname: "Thyroid"
    related_codings:
      - system: "http://www.nlm.nih.gov/research/umls/rxnorm"
        version: "2026AA"
        code: "617314"
    rxnorm_codes:
      - "617314"
  - name: "Vitamin D"
    concept_identifier: "custom:vitamin-d"
    display_name: "Vitamin D"
    general_form: "capsule"
    is_archived: true
    has_schedule: false
medication_dose_count: 2
medication_dose_events:
  - name: "Thyroid"
    status: taken
    status_display: "Taken"
    id: "00000000-0000-0000-0000-000000000730"
    medication_concept_identifier: "rxnorm:617314"
    start_date: "2026-03-15T08:00:00Z"
    end_date: "2026-03-15T08:00:30Z"
    schedule_type: scheduled
    scheduled_date: "2026-03-15T08:00:00Z"
    dose_quantity: 1
    scheduled_dose_quantity: 1
    unit: "tablet"
    metadata:
      "with_food": "false"
  - name: "custom:vitamin-d"
    status: skipped
    status_display: "Skipped"
    id: "00000000-0000-0000-0000-000000000731"
    medication_concept_identifier: "custom:vitamin-d"
    start_date: "2026-03-15T18:00:00Z"
    end_date: "2026-03-15T18:00:00Z"
    schedule_type: as_needed
    dose_quantity: 2
    unit: "capsule"
    metadata:
      "reason": "not available"
medication_skipped_count: 1
medication_taken_count: 1
medications: [thyroid, vitamin-d]
menstrual_flow: medium
mindful_minutes: 18
mindful_sessions: 3
molybdenum_ug: 45.0
momentary_emotion_count: 1
monounsaturated_fat_g: 24.0
mood_associations: [family, work]
mood_entries: 3
mood_labels: [calm, content, neutral, worried]
move_minutes: 61
niacin_mg: 16.0
number_of_falls: 1
ovulation_test: positive
pantothenic_acid_mg: 5.00
peak_expiratory_flow: 510.0
phosphorus_mg: 700.0
physical_effort: 4.8
polyunsaturated_fat_g: 15.0
potassium_mg: 3400.0
protein_g: 120.0
respiratory_rate: 15.2
respiratory_rate_avg: 15.2
respiratory_rate_max: 19.4
respiratory_rate_min: 11.8
resting_heart_rate: 58
riboflavin_mg: 1.30
running_ground_contact_ms: 245
running_power_w: 278
running_speed: 3.40
running_stride_length_m: 1.15
running_vertical_oscillation_cm: 8.4
saturated_fat_g: 20.0
selenium_ug: 55.0
sexual_activity: 1
six_min_walk_m: 590
sleep_awake_hours: 0.25
sleep_bedtime: 06:00
sleep_core_hours: 4.00
sleep_deep_hours: 1.50
sleep_in_bed_hours: 8.00
sleep_rem_hours: 2.25
sleep_total_hours: 7.75
sleep_wake: 13:45
sodium_mg: 2100
stair_ascent_speed: 0.62
stair_descent_speed: 0.71
stand_hours: 11
stand_time_minutes: 37.5
step_length_cm: 73.0
steps: 12500
sugar_g: 45.0
swimming_m: 750
swimming_strokes: 420
symptom_abdominal_cramps: 29
symptom_acne: 23
symptom_appetite_changes: 7
symptom_bladder_incontinence: 38
symptom_bloating: 12
symptom_body_ache: 32
symptom_breast_pain: 30
symptom_chest_pain: 20
symptom_chills: 9
symptom_constipation: 13
symptom_coughing: 16
symptom_diarrhea: 14
symptom_dizziness: 4
symptom_dry_skin: 24
symptom_fainting: 33
symptom_fatigue: 2
symptom_fever: 10
symptom_hair_loss: 25
symptom_headache: 1
symptom_heartburn: 15
symptom_hot_flashes: 8
symptom_loss_of_smell: 34
symptom_loss_of_taste: 35
symptom_lower_back_pain: 11
symptom_memory_lapse: 26
symptom_mood_changes: 5
symptom_nausea: 3
symptom_night_sweats: 27
symptom_pelvic_pain: 31
symptom_rapid_heartbeat: 22
symptom_runny_nose: 18
symptom_shortness_of_breath: 19
symptom_sinus_congestion: 37
symptom_skipped_heartbeat: 21
symptom_sleep_changes: 6
symptom_sore_throat: 17
symptom_vaginal_dryness: 39
symptom_vomiting: 28
symptom_wheezing: 36
thiamin_mg: 1.20
time_in_daylight_min: 92
toothbrushing: 2
underwater_depth_m: 4.2
uv_exposure: 4.0
vitamin_a_ug: 800.0
vitamin_b12_ug: 2.40
vitamin_b6_mg: 1.70
vitamin_c_mg: 95.0
vitamin_d_ug: 20.0
vitamin_e_mg: 15.00
vitamin_k_ug: 120.0
vo2_max: 42.5
vo2_max_age_seconds: 86400
vo2_max_carried_forward: true
vo2_max_source_end: 2026-03-14T00:01:00.000000000Z
vo2_max_source_start: 2026-03-14T00:00:00.000000000Z
vo2_max_source_uuid: 00000000-0000-0000-0000-000000000700
waist_circumference_cm: 84.0
walking_asymmetry_percent: 1.5
walking_heart_rate: 105
walking_running_km: 9.50
walking_running_mi: 5.90
walking_speed: 1.42
walking_steadiness_percent: 92.0
water_l: 2.50
water_temperature: 19.5
weight_kg: 75.0
wheelchair_km: 1.25
wheelchair_mi: 0.78
wheelchair_pushes: 88
workout_avg_heart_rate: 143
workout_avg_power: 258
workout_calories: 1230
workout_count: 3
workout_cycling_cadence: 86
workout_distance_km: 31.50
workout_distance_mi: 19.57
workout_max_heart_rate: 172
workout_max_power: 430
workout_min_heart_rate: 88
workout_minutes: 135
workout_running_cadence: 176
workout_running_ground_contact: 238
workout_running_stride_length: 1.18
workout_running_vertical_oscillation: 8.1
workouts: [cycling, running, swimming]
wrist_temperature: 36.45
zinc_mg: 11.00
units:
  active_calories: kcal
  active_medication_count: count
  afib_burden_percent: percent
  alcoholic_beverages: drinks
  archived_medication_count: count
  average_heart_rate: bpm
  average_mood_percent: percent
  basal_body_temperature: °C
  basal_calories: kcal
  biotin_ug: µg
  blood_alcohol_percent: percent
  blood_glucose: mg/dL
  blood_glucose_avg: mg/dL
  blood_glucose_max: mg/dL
  blood_glucose_min: mg/dL
  blood_oxygen: percent
  blood_oxygen_avg: percent
  blood_oxygen_max: percent
  blood_oxygen_min: percent
  blood_pressure_diastolic: mmHg
  blood_pressure_diastolic_avg: mmHg
  blood_pressure_diastolic_max: mmHg
  blood_pressure_diastolic_min: mmHg
  blood_pressure_systolic: mmHg
  blood_pressure_systolic_avg: mmHg
  blood_pressure_systolic_max: mmHg
  blood_pressure_systolic_min: mmHg
  bmi: kg/m²
  body_fat_percent: percent
  body_temperature: °C
  body_temperature_avg: °C
  body_temperature_max: °C
  body_temperature_min: °C
  caffeine_mg: mg
  calcium_mg: mg
  carbohydrates_g: g
  chloride_mg: mg
  cholesterol_mg: mg
  chromium_ug: µg
  copper_mg: mg
  cycling_cadence_rpm: rpm
  cycling_ftp_w: W
  cycling_km: km
  cycling_mi: mi
  cycling_power_w: W
  cycling_speed: m/s
  daily_mood_count: count
  daily_mood_percent: percent
  dietary_calories: kcal
  double_support_percent: percent
  downhill_snow_km: km
  downhill_snow_mi: mi
  electrodermal_activity: µS
  environmental_sound_db: dB
  exercise_minutes: min
  fat_g: g
  fev1_l: L
  fiber_g: g
  flights_climbed: floors
  folate_ug: µg
  forced_vital_capacity_l: L
  handwashing: events
  headphone_audio_db: dB
  heart_rate_max: bpm
  heart_rate_min: bpm
  heart_rate_recovery: bpm
  height_m: m
  hrv_ms: ms
  inhaler_usage: uses
  insulin_delivery_iu: IU
  iodine_ug: µg
  iron_mg: mg
  lean_body_mass_kg: kg
  magnesium_mg: mg
  manganese_mg: mg
  medication_count: count
  medication_dose_count: count
  medication_skipped_count: count
  medication_taken_count: count
  mindful_minutes: min
  mindful_sessions: sessions
  molybdenum_ug: µg
  momentary_emotion_count: count
  monounsaturated_fat_g: g
  mood_entries: entries
  move_minutes: min
  niacin_mg: mg
  number_of_falls: falls
  pantothenic_acid_mg: mg
  peak_expiratory_flow: L/min
  phosphorus_mg: mg
  physical_effort: kcal/hr/kg
  polyunsaturated_fat_g: g
  potassium_mg: mg
  protein_g: g
  raw_integrity_warning_count: warnings
  raw_query_failure_count: queries
  raw_record_count: records
  respiratory_rate: breaths/min
  respiratory_rate_avg: breaths/min
  respiratory_rate_max: breaths/min
  respiratory_rate_min: breaths/min
  resting_heart_rate: bpm
  riboflavin_mg: mg
  running_ground_contact_ms: ms
  running_power_w: W
  running_speed: m/s
  running_stride_length_m: m
  running_vertical_oscillation_cm: cm
  saturated_fat_g: g
  selenium_ug: µg
  six_min_walk_m: m
  sleep_awake_hours: hours
  sleep_bedtime: time
  sleep_core_hours: hours
  sleep_deep_hours: hours
  sleep_in_bed_hours: hours
  sleep_rem_hours: hours
  sleep_total_hours: hours
  sleep_wake: time
  sodium_mg: mg
  stair_ascent_speed: m/s
  stair_descent_speed: m/s
  stand_hours: hours
  stand_time_minutes: min
  step_length_cm: cm
  steps: steps
  sugar_g: g
  swimming_m: m
  swimming_strokes: strokes
  thiamin_mg: mg
  time_in_daylight_min: min
  toothbrushing: events
  underwater_depth_m: m
  vitamin_a_ug: µg
  vitamin_b12_ug: µg
  vitamin_b6_mg: mg
  vitamin_c_mg: mg
  vitamin_d_ug: µg
  vitamin_e_mg: mg
  vitamin_k_ug: µg
  vo2_max: mL/kg/min
  vo2_max_age_seconds: seconds
  vo2_max_carried_forward: boolean
  vo2_max_source_end: datetime
  vo2_max_source_start: datetime
  vo2_max_source_uuid: uuid
  waist_circumference_cm: cm
  walking_asymmetry_percent: percent
  walking_heart_rate: bpm
  walking_running_km: km
  walking_running_mi: mi
  walking_speed: m/s
  walking_steadiness_percent: percent
  water_l: L
  water_temperature: °C
  weight_kg: kg
  wheelchair_km: km
  wheelchair_mi: mi
  wheelchair_pushes: pushes
  workout_avg_heart_rate: bpm
  workout_avg_power: W
  workout_calories: kcal
  workout_count: count
  workout_cycling_cadence: rpm
  workout_distance_km: km
  workout_distance_mi: mi
  workout_max_heart_rate: bpm
  workout_max_power: W
  workout_min_heart_rate: bpm
  workout_minutes: min
  workout_running_cadence: spm
  workout_running_ground_contact: ms
  workout_running_stride_length: m
  workout_running_vertical_oscillation: cm
  wrist_temperature: °C
  zinc_mg: mg
---

# Health Data — 2026-03-15

7h 45m sleep · 12,500 steps · 3 workouts · 2 medication doses · mood 56%

## Sleep

- **Total:** 7h 45m
- **Bedtime:** 06:00
- **Wake:** 13:45
- **In Bed:** 8h 0m
- **Deep:** 1h 30m
- **REM:** 2h 15m
- **Core:** 4h 0m
- **Awake:** 15m

<details>
<summary>Sleep Stages Timeline (6 intervals)</summary>

| Time | Stage | Duration |
|------|-------|----------|
| 06:00 | deep | 1h 0m |
| 07:00 | rem | 1h 0m |
| 08:00 | core | 1h 0m |
| 09:00 | awake | 5m |
| 06:00 | inBed | 7h 45m |
| 09:05 | unspecified | 5m |

</details>

## Activity

- **Steps:** 12,500
- **Active Calories:** 520 kcal
- **Basal Energy:** 1,650 kcal
- **Exercise:** 45 min
- **Stand Time:** 37.5 min
- **Stand Hours:** 11
- **Flights Climbed:** 8
- **Walking/Running Distance:** 9.50 km
- **Cycling Distance:** 3.20 km
- **Swimming Distance:** 750 m
- **Swimming Strokes:** 420
- **Wheelchair Pushes:** 88
- **Cardio Fitness (VO2 Max):** 42.5 mL/kg/min
  - Source measurement: 2026-03-14T00:00:00.000000000Z (carried forward)
  - Source end: 2026-03-14T00:01:00.000000000Z
  - Source UUID: 00000000-0000-0000-0000-000000000700
  - Age at day start: 86400 seconds
- **Wheelchair Distance:** 1.25 km
- **Downhill Snow Distance:** 2.30 km
- **Move Minutes:** 61 min
- **Physical Effort:** 4.8

## Heart

- **Resting HR:** 58 bpm
- **Walking HR Average:** 105 bpm
- **Average HR:** 72 bpm
- **Min HR:** 52 bpm
- **Max HR:** 155 bpm
- **HRV:** 42.0 ms

<details>
<summary>Heart Rate Samples (2 readings)</summary>

| Time | BPM |
|------|-----|
| 00:30 | 61 |
| 01:00 | 92 |

</details>

<details>
<summary>HRV Samples (1 readings)</summary>

| Time | ms |
|------|----|
| 00:31 | 43.0 |

</details>
- **Heart Rate Recovery:** 24 bpm
- **AFib Burden:** 1.2%

## Vitals

- **Respiratory Rate:** 15.2 breaths/min (range: 11.8–19.4)
- **SpO2:** 97% (range: 94%–99%)
- **Body Temperature:** 36.7°C (range: 36.3°C–37.1°C)
- **Blood Pressure:** 121/79 mmHg (range: 116/74–127/84)
- **Blood Glucose:** 102.0 mg/dL (range: 82.0–138.0)

<details>
<summary>Blood Pressure Samples (1 readings)</summary>

| Time | Systolic | Diastolic |
|------|----------|-----------|
| 01:23 | 121.0 mmHg | 79.0 mmHg |

</details>

<details>
<summary>Blood Oxygen Samples (1 readings)</summary>

| Time | SpO2 |
|------|------|
| 00:33 | 97.0% |

</details>

<details>
<summary>Blood Glucose Samples (1 readings)</summary>

| Time | mg/dL |
|------|-------|
| 00:50 | 102.0 |

</details>

<details>
<summary>Respiratory Rate Samples (1 readings)</summary>

| Time | breaths/min |
|------|-------------|
| 01:06 | 15.2 |

</details>
- **Basal Body Temperature:** 36.5
- **Wrist Temperature:** 36.45
- **Electrodermal Activity:** 1.75
- **Forced Vital Capacity:** 4.80 L
- **FEV1:** 3.90 L
- **Peak Expiratory Flow:** 510.0
- **Inhaler Usage:** 2

## Body

- **Weight:** 75.0 kg
- **Height:** 178.0 cm
- **BMI:** 23.7
- **Body Fat:** 18.0%
- **Lean Body Mass:** 61.5 kg
- **Waist Circumference:** 84.0 cm

## Nutrition

- **Calories:** 2,100 kcal
- **Protein:** 120.0 g
- **Carbohydrates:** 250.0 g
- **Fat:** 70.0 g
- **Saturated Fat:** 20.0 g
- **Fiber:** 25.0 g
- **Sugar:** 45.0 g
- **Sodium:** 2,100 mg
- **Cholesterol:** 180.0 mg
- **Water:** 2.50 L
- **Caffeine:** 200.0 mg
- **Monounsaturated Fat:** 24.0 g
- **Polyunsaturated Fat:** 15.0 g

## Mindfulness

- **Mindful Minutes:** 18 min
- **Sessions:** 3

- **Average Mood:** 56% (Neutral)
- **Daily Mood Entries:** 1 (82% average)
- **Momentary Emotions:** 1
- **State of Mind Entries:** 3
- **Emotions/Moods:** Calm, Content, Neutral, Worried
- **Associated With:** Family, Work

### Mood Entries

- **08:00** (Daily Mood): 82% — Content, Calm
- **14:00** (Momentary Emotion): 37% — Worried
- **19:00** (Unknown): 50% — Neutral

## Mobility

- **Walking Speed:** 5.1 km/h
- **Step Length:** 73.0 cm
- **Double Support:** 27.0%
- **Walking Asymmetry:** 1.5%
- **Stair Ascent Speed:** 2.2 km/h
- **Stair Descent Speed:** 2.6 km/h
- **6-Min Walk Distance:** 590 m
- **Walking Steadiness:** 92.0%
- **Running Speed:** 3.40
- **Running Stride Length:** 1.15 m
- **Running Ground Contact:** 245 ms
- **Running Vertical Oscillation:** 8.4 cm
- **Running Power:** 278 W

## Hearing

- **Headphone Audio Level:** 71.5 dB
- **Environmental Sound Level:** 54.2 dB

## Workouts

### 1. Running

- **Time:** 10:00
- **Location:** Outdoor
- **Duration:** 1h 0m
- **Distance:** 10.00 km
- **Avg Pace:** 6:00 /km
- **Calories:** 540 kcal
- **Avg Heart Rate:** 148 bpm
- **Max Heart Rate:** 172 bpm
- **Min Heart Rate:** 92 bpm
- **Avg Cadence:** 176 spm
- **Avg Stride Length:** 1.18 m
- **Avg Ground Contact:** 238 ms
- **Avg Vertical Oscillation:** 8.1 cm
- **Avg Cadence:** 84 rpm
- **Avg Power:** 286 W
- **Max Power:** 430 W
- **Elevation Gain:** 125 m
- **Elevation Loss:** 118 m
- **GPS Route:** 1 points

#### Details

| Field | Value |
|---|---|
| Source | Health.md |
| Activity Type | Running |
| Sport | running |
| HealthKit Activity Type | running |
| HealthKit Activity Type Raw Value | 37 |
| Start | 2026-03-15T10:00:00Z |
| End | 2026-03-15T11:05:00Z |
| Duration | 1:00:00 |
| Location | Outdoor |
| Distance | 10.00 km (10.00 km / 6.21 mi) |
| Average Pace | 6:00 /km |
| Speed | 10.0 km/h / 6.2 mph |
| Calories | 540 kcal |
| Avg Heart Rate | 148 bpm |
| Max Heart Rate | 172 bpm |
| Min Heart Rate | 92 bpm |
| Avg Running Cadence | 176 spm |
| Avg Stride Length | 1.18 m |
| Avg Ground Contact | 238 ms |
| Avg Vertical Oscillation | 8.1 cm |
| Avg Cycling Cadence | 84 rpm |
| Avg Power | 286 W |
| Max Power | 430 W |
| Elevation Gain | 125 m |
| Elevation Loss | 118 m |
| GPS Route Points | 1 |
| Laps | 1 |
| Splits | 1 |

- **Heart Rate Zones:** Threshold 1:00:00

- **Heart Rate Zones:**

| Zone | Label | Range | Time |
|---|---|---|---|
| Zone 1 | Recovery | 87-103 bpm | — |
| Zone 2 | Aerobic | 104-121 bpm | — |
| Zone 3 | Tempo | 122-138 bpm | — |
| Zone 4 | Threshold | 139-156 bpm | 1:00:00 |
| Zone 5 | Max | 157-174 bpm | — |

- **Laps:**

| # | Start | End | Distance | Time | Pace | Speed | Avg HR | Max HR | Avg Power | Avg Cadence |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 10:00:00 | 10:30:00 | 5.00 km | 30:00 | 6:00 /km | 10.0 km/h / 6.2 mph | 142 bpm | 142 bpm | 286 W | 176 spm |

- **Splits:**

| # | Start | End | Distance | Time | Pace | Speed | Avg HR | Max HR | Avg Power | Avg Cadence |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 10:00:00 | 10:06:00 | 1.00 km | 6:00 | 6:00 /km | 10.0 km/h / 6.2 mph | 142 bpm | 142 bpm | 286 W | 176 spm |

#### Samples

| Metric | Samples |
|---|---:|
| Heart Rate | 1 |
| Speed | 1 |
| Power | 1 |
| Cadence | 1 |
| Stride Length | 1 |
| Ground Contact | 1 |
| Vertical Oscillation | 1 |
| Altitude | 1 |


#### Metadata

| Key | Value |
|---|---|
| weather | clear |


### 2. Swimming

- **Time:** 13:53
- **Location:** Indoor
- **Duration:** 30m
- **Distance:** 1.50 km
- **Avg Pace:** 2:00 /100m
- **Calories:** 280 kcal

#### Details

| Field | Value |
|---|---|
| Source | Health.md |
| Activity Type | Swimming |
| Sport | swimming |
| HealthKit Activity Type | swimming |
| HealthKit Activity Type Raw Value | 46 |
| Start | 2026-03-15T13:53:20Z |
| End | 2026-03-15T14:23:20Z |
| Duration | 30:00 |
| Location | Indoor |
| Distance | 1.50 km (1.50 km / 0.93 mi) |
| Average Pace | 2:00 /100m |
| Speed | 3.0 km/h / 1.9 mph |
| Calories | 280 kcal |


### 3. Cycling

- **Time:** 16:40
- **Duration:** 45m
- **Distance:** 20.00 km
- **Avg Speed:** 26.7 km/h
- **Calories:** 410 kcal
- **Avg Heart Rate:** 136 bpm
- **Max Heart Rate:** 158 bpm
- **Min Heart Rate:** 88 bpm
- **Avg Cadence:** 86 rpm
- **Avg Power:** 220 W
- **Max Power:** 415 W

#### Details

| Field | Value |
|---|---|
| Source | Health.md |
| Activity Type | Cycling |
| Sport | cycling |
| HealthKit Activity Type | cycling |
| HealthKit Activity Type Raw Value | 13 |
| Start | 2026-03-15T16:40:00Z |
| End | 2026-03-15T17:25:00Z |
| Duration | 45:00 |
| Distance | 20.00 km (20.00 km / 12.43 mi) |
| Average Speed | 26.7 km/h |
| Speed | 26.7 km/h / 16.6 mph |
| Calories | 410 kcal |
| Avg Heart Rate | 136 bpm |
| Max Heart Rate | 158 bpm |
| Min Heart Rate | 88 bpm |
| Avg Cycling Cadence | 86 rpm |
| Avg Power | 220 W |
| Max Power | 415 W |


## Reproductive Health

- **Menstrual Flow:** medium
- **Sexual Activity:** 1
- **Ovulation Test Result:** positive
- **Cervical Mucus Quality:** egg_white
- **Spotting:** 1

## Cycling Performance

- **Cycling Distance:** 3.20
- **Cycling Speed:** 8.20
- **Cycling Power:** 215
- **Cycling Cadence:** 88
- **Functional Threshold Power:** 260

## Vitamins

- **Vitamin A:** 800.0
- **Vitamin B6:** 1.70
- **Vitamin B12:** 2.40
- **Vitamin C:** 95.0
- **Vitamin D:** 20.0
- **Vitamin E:** 15.00
- **Vitamin K:** 120.0
- **Thiamin (B1):** 1.20
- **Riboflavin (B2):** 1.30
- **Niacin (B3):** 16.0
- **Folate:** 400.0
- **Biotin:** 30.0
- **Pantothenic Acid (B5):** 5.00

## Minerals

- **Calcium:** 1000.0
- **Iron:** 18.00
- **Potassium:** 3400.0
- **Magnesium:** 420.0
- **Phosphorus:** 700.0
- **Zinc:** 11.00
- **Selenium:** 55.0
- **Copper:** 0.900
- **Manganese:** 2.30
- **Chromium:** 35.0
- **Molybdenum:** 45.0
- **Chloride:** 2300.0
- **Iodine:** 150.0

## Symptoms

- **Abdominal Cramps:** 29
- **Acne:** 23
- **Appetite Changes:** 7
- **Bladder Incontinence:** 38
- **Bloating:** 12
- **Body Ache:** 32
- **Breast Pain:** 30
- **Chest Pain:** 20
- **Chills:** 9
- **Constipation:** 13
- **Coughing:** 16
- **Diarrhea:** 14
- **Dizziness:** 4
- **Dry Skin:** 24
- **Fainting:** 33
- **Fatigue:** 2
- **Fever:** 10
- **Hair Loss:** 25
- **Headache:** 1
- **Heartburn:** 15
- **Hot Flashes:** 8
- **Loss Of Smell:** 34
- **Loss Of Taste:** 35
- **Lower Back Pain:** 11
- **Memory Lapse:** 26
- **Mood Changes:** 5
- **Nausea:** 3
- **Night Sweats:** 27
- **Pelvic Pain:** 31
- **Rapid Heartbeat:** 22
- **Runny Nose:** 18
- **Shortness Of Breath:** 19
- **Sinus Congestion:** 37
- **Skipped Heartbeat:** 21
- **Sleep Changes:** 6
- **Sore Throat:** 17
- **Vaginal Dryness:** 39
- **Vomiting:** 28
- **Wheezing:** 36

## Medications

- **Authorized medications:** 2 (1 active, 1 archived)
- **Active:** Thyroid
- **Archived:** Vitamin D

<details>
<summary>Medication Details (2 medications)</summary>

| Name | Display Name | Nickname | Concept ID | Form | Archived | Has Schedule | Related Codings | RxNorm Codes |
|------|--------------|----------|------------|------|----------|--------------|-----------------|--------------|
| Thyroid | Levothyroxine Sodium 50 MCG Oral Tablet | Thyroid | rxnorm:617314 | tablet | false | true | http://www.nlm.nih.gov/research/umls/rxnorm:617314@2026AA | 617314 |
| Vitamin D | Vitamin D |  | custom:vitamin-d | capsule | true | false |  |  |

</details>
- **Dose events:** 2 (1 taken, 1 skipped)
- 08:00 **Thyroid:** Taken; 1 tablet; scheduled 08:00
- 18:00 **custom:vitamin-d:** Skipped; 2 capsule

<details>
<summary>Dose Event Details (2 events)</summary>

| Time | Name | Status | Dose | Scheduled Dose | Scheduled Time | Start | End | Schedule Type | ID | Concept ID | Metadata |
|------|------|--------|------|----------------|----------------|-------|-----|---------------|----|------------|----------|
| 08:00 | Thyroid | taken | 1 tablet | 1 tablet | 08:00 | 2026-03-15T08:00:00Z | 2026-03-15T08:00:30Z | scheduled | 00000000-0000-0000-0000-000000000730 | rxnorm:617314 | with_food=false |
| 18:00 | custom:vitamin-d | skipped | 2 capsule |  |  | 2026-03-15T18:00:00Z | 2026-03-15T18:00:00Z | as_needed | 00000000-0000-0000-0000-000000000731 | custom:vitamin-d | reason=not available |

</details>

## Other

- **UV Exposure:** 4.0
- **Time in Daylight:** 92
- **Number of Falls:** 1
- **Blood Alcohol Content:** 0.001
- **Alcoholic Beverages:** 1
- **Insulin Delivery:** 3.5
- **Toothbrushing:** 2
- **Handwashing:** 8
- **Water Temperature:** 19.5
- **Underwater Depth:** 4.2


## Lossless Health Records

- **Capture status:** partial
- **Source records:** 20
- **External records:** 4
- **Queries:** 1 succeeded · 1 empty · 2 failed · 1 unsupported · 1 skipped
- **Medication inventory:** 2
- **Integrity warnings:** 2

| Type | Identifier | Details |
|---|---|---|
| Query failure | HKFixtureTypeIdentifier | NSCocoaErrorDomain 3072: The user cancelled the selection |
| Query failure | HKFixtureTypeIdentifier | HKErrorDomain 5: Authorization or source data error |
| Integrity warning | cross_day_relationship | A relationship target belongs to another owner date; metrics: workouts; records: 00000000-0000-0000-0000-000000000001, 00000000-0000-0000-0000-000000000002 |
| Integrity warning | partial_binary_availability | One binary reference has metadata but no inline bytes; metrics: electrocardiograms; records: 00000000-0000-0000-0000-000000000005 |
