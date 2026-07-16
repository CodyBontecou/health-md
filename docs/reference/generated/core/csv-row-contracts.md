# CSV row contracts

The production header has 6 fields: `Date,Category,Metric,Value,Unit,Timestamp`.

Summary rows emitted by legacy direct interpolation intentionally retain five fields. Canonical, diagnostic, and provenance-aware rows emitted through the shared row writer have six fields. Consumers must accept both forms.

| Example | Category | Metric | Fields | Unit | Timestamp field | Populated timestamp | Rows |
|---|---|---|---:|---|---:|---:|---:|
| Lossless | Activity | Active Calories | 5 | kcal | no | no | 1 |
| Lossless | Activity | Basal Energy | 5 | kcal | no | no | 1 |
| Lossless | Activity | Cardio Fitness (VO2 Max) | 6 | mL/kg/min | yes | yes | 1 |
| Lossless | Activity | Cycling Distance | 5 | meters | no | no | 1 |
| Lossless | Activity | Downhill Snow Sports Distance | 5 | meters | no | no | 1 |
| Lossless | Activity | Exercise Minutes | 5 | minutes | no | no | 1 |
| Lossless | Activity | Flights Climbed | 5 | count | no | no | 1 |
| Lossless | Activity | Move Time | 5 | min | no | no | 1 |
| Lossless | Activity | Physical Effort | 5 | kcal/hr/kg | no | no | 1 |
| Lossless | Activity | Stand Hours | 5 | hours | no | no | 1 |
| Lossless | Activity | Stand Time | 5 | minutes | no | no | 1 |
| Lossless | Activity | Steps | 5 | count | no | no | 1 |
| Lossless | Activity | Swimming Distance | 5 | meters | no | no | 1 |
| Lossless | Activity | Swimming Strokes | 5 | count | no | no | 1 |
| Lossless | Activity | VO2 Max Age | 6 | seconds | yes | yes | 1 |
| Lossless | Activity | VO2 Max Carried Forward | 6 | boolean | yes | yes | 1 |
| Lossless | Activity | VO2 Max Source End | 6 | datetime | yes | yes | 1 |
| Lossless | Activity | VO2 Max Source Start | 6 | datetime | yes | yes | 1 |
| Lossless | Activity | VO2 Max Source UUID | 6 | uuid | yes | yes | 1 |
| Lossless | Activity | Walking Running Distance | 5 | meters | no | no | 1 |
| Lossless | Activity | Wheelchair Distance | 5 | meters | no | no | 1 |
| Lossless | Activity | Wheelchair Pushes | 5 | count | no | no | 1 |
| Lossless | Body | BMI | 5 | empty | no | no | 1 |
| Lossless | Body | Body Fat Percentage | 5 | percent | no | no | 1 |
| Lossless | Body | Height | 5 | m | no | no | 1 |
| Lossless | Body | Lean Body Mass | 5 | kg | no | no | 1 |
| Lossless | Body | Waist Circumference | 5 | cm | no | no | 1 |
| Lossless | Body | Weight | 5 | kg | no | no | 1 |
| Lossless | Cycling | Cycling Cadence | 5 | rpm | no | no | 1 |
| Lossless | Cycling | Cycling Distance | 5 | km | no | no | 1 |
| Lossless | Cycling | Cycling Power | 5 | W | no | no | 1 |
| Lossless | Cycling | Cycling Speed | 5 | m/s | no | no | 1 |
| Lossless | Cycling | Functional Threshold Power | 5 | W | no | no | 1 |
| Lossless | Diagnostics | Partial Failure | 6 | json | yes | yes | 2 |
| Lossless | Hearing | Environmental Sound Level | 5 | dB | no | no | 1 |
| Lossless | Hearing | Headphone Audio Level | 5 | dB | no | no | 1 |
| Lossless | Heart | AFib Burden | 5 | % | no | no | 1 |
| Lossless | Heart | Average Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Heart | HRV | 5 | ms | no | no | 1 |
| Lossless | Heart | HRV Sample | 6 | ms | yes | yes | 1 |
| Lossless | Heart | Heart Rate Recovery | 5 | bpm | no | no | 1 |
| Lossless | Heart | Heart Rate Sample | 6 | bpm | yes | yes | 2 |
| Lossless | Heart | Max Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Heart | Min Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Heart | Resting Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Heart | Walking Heart Rate Average | 5 | bpm | no | no | 1 |
| Lossless | Medications | Active Medications | 5 | count | no | no | 1 |
| Lossless | Medications | Archived Medications | 5 | count | no | no | 1 |
| Lossless | Medications | Authorized Medications | 5 | count | no | no | 1 |
| Lossless | Medications | Dose Event | 6 | as_needed | yes | yes | 1 |
| Lossless | Medications | Dose Event | 6 | scheduled | yes | yes | 1 |
| Lossless | Medications | Dose Event Dose Quantity | 6 | capsule | yes | yes | 1 |
| Lossless | Medications | Dose Event Dose Quantity | 6 | tablet | yes | yes | 1 |
| Lossless | Medications | Dose Event End | 6 | datetime | yes | yes | 2 |
| Lossless | Medications | Dose Event ID | 6 | uuid | yes | yes | 2 |
| Lossless | Medications | Dose Event Medication Concept Identifier | 6 | empty | yes | yes | 2 |
| Lossless | Medications | Dose Event Medication Name | 6 | empty | yes | yes | 2 |
| Lossless | Medications | Dose Event Metadata reason | 6 | metadata | yes | yes | 1 |
| Lossless | Medications | Dose Event Metadata with_food | 6 | metadata | yes | yes | 1 |
| Lossless | Medications | Dose Event Schedule Type | 6 | empty | yes | yes | 2 |
| Lossless | Medications | Dose Event Scheduled Date | 6 | datetime | yes | yes | 1 |
| Lossless | Medications | Dose Event Scheduled Dose Quantity | 6 | tablet | yes | yes | 1 |
| Lossless | Medications | Dose Event Start | 6 | datetime | yes | yes | 2 |
| Lossless | Medications | Dose Event Status | 6 | empty | yes | yes | 2 |
| Lossless | Medications | Dose Event Status Display | 6 | empty | yes | yes | 2 |
| Lossless | Medications | Dose Event Unit | 6 | empty | yes | yes | 2 |
| Lossless | Medications | Dose Events | 5 | count | no | no | 1 |
| Lossless | Medications | Medication | 6 | active;scheduled | yes | no | 1 |
| Lossless | Medications | Medication | 6 | archived;as_needed | yes | no | 1 |
| Lossless | Medications | Medication Archived | 6 | boolean | yes | no | 2 |
| Lossless | Medications | Medication Concept Identifier | 6 | empty | yes | no | 2 |
| Lossless | Medications | Medication Display Name | 6 | empty | yes | no | 2 |
| Lossless | Medications | Medication Export Name | 6 | empty | yes | no | 2 |
| Lossless | Medications | Medication General Form | 6 | empty | yes | no | 2 |
| Lossless | Medications | Medication Has Schedule | 6 | boolean | yes | no | 2 |
| Lossless | Medications | Medication Nickname | 6 | empty | yes | no | 1 |
| Lossless | Medications | Medication Related Coding | 6 | coding | yes | no | 1 |
| Lossless | Medications | Medication RxNorm Code | 6 | rxnorm | yes | no | 1 |
| Lossless | Medications | Skipped Doses | 5 | count | no | no | 1 |
| Lossless | Medications | Taken Doses | 5 | count | no | no | 1 |
| Lossless | Metadata | schema | 6 | empty | yes | no | 1 |
| Lossless | Metadata | schema_version | 6 | empty | yes | no | 1 |
| Lossless | Metadata | time_context.calendar_timezone | 6 | empty | yes | no | 1 |
| Lossless | Metadata | time_context.timestamp_timezone | 6 | empty | yes | no | 1 |
| Lossless | Metadata | unit_system | 6 | empty | yes | no | 1 |
| Lossless | Mindfulness | Average Mood Percent | 5 | percent | no | no | 1 |
| Lossless | Mindfulness | Average Mood Valence | 5 | scale(-1 to 1) | no | no | 1 |
| Lossless | Mindfulness | Daily Mood Count | 5 | count | no | no | 1 |
| Lossless | Mindfulness | Daily Mood Percent | 5 | percent | no | no | 1 |
| Lossless | Mindfulness | Mindful Minutes | 5 | minutes | no | no | 1 |
| Lossless | Mindfulness | Mindful Sessions | 5 | count | no | no | 1 |
| Lossless | Mindfulness | Momentary Emotion Count | 5 | count | no | no | 1 |
| Lossless | Mindfulness | State of Mind Entries | 5 | count | no | no | 1 |
| Lossless | Minerals | Calcium | 5 | mg | no | no | 1 |
| Lossless | Minerals | Chloride | 5 | mg | no | no | 1 |
| Lossless | Minerals | Chromium | 5 | µg | no | no | 1 |
| Lossless | Minerals | Copper | 5 | mg | no | no | 1 |
| Lossless | Minerals | Iodine | 5 | µg | no | no | 1 |
| Lossless | Minerals | Iron | 5 | mg | no | no | 1 |
| Lossless | Minerals | Magnesium | 5 | mg | no | no | 1 |
| Lossless | Minerals | Manganese | 5 | mg | no | no | 1 |
| Lossless | Minerals | Molybdenum | 5 | µg | no | no | 1 |
| Lossless | Minerals | Phosphorus | 5 | mg | no | no | 1 |
| Lossless | Minerals | Potassium | 5 | mg | no | no | 1 |
| Lossless | Minerals | Selenium | 5 | µg | no | no | 1 |
| Lossless | Minerals | Zinc | 5 | mg | no | no | 1 |
| Lossless | Mobility | Double Support Percentage | 5 | percent | no | no | 1 |
| Lossless | Mobility | Running Ground Contact Time | 5 | ms | no | no | 1 |
| Lossless | Mobility | Running Power | 5 | W | no | no | 1 |
| Lossless | Mobility | Running Speed | 5 | m/s | no | no | 1 |
| Lossless | Mobility | Running Stride Length | 5 | m | no | no | 1 |
| Lossless | Mobility | Running Vertical Oscillation | 5 | cm | no | no | 1 |
| Lossless | Mobility | Six Minute Walk Distance | 5 | meters | no | no | 1 |
| Lossless | Mobility | Stair Ascent Speed | 5 | m/s | no | no | 1 |
| Lossless | Mobility | Stair Descent Speed | 5 | m/s | no | no | 1 |
| Lossless | Mobility | Walking Asymmetry | 5 | percent | no | no | 1 |
| Lossless | Mobility | Walking Speed | 5 | m/s | no | no | 1 |
| Lossless | Mobility | Walking Steadiness | 5 | % | no | no | 1 |
| Lossless | Mobility | Walking Step Length | 5 | meters | no | no | 1 |
| Lossless | Nutrition | Caffeine | 5 | mg | no | no | 1 |
| Lossless | Nutrition | Carbohydrates | 5 | g | no | no | 1 |
| Lossless | Nutrition | Cholesterol | 5 | mg | no | no | 1 |
| Lossless | Nutrition | Dietary Energy | 5 | kcal | no | no | 1 |
| Lossless | Nutrition | Fat | 5 | g | no | no | 1 |
| Lossless | Nutrition | Fiber | 5 | g | no | no | 1 |
| Lossless | Nutrition | Monounsaturated Fat | 5 | g | no | no | 1 |
| Lossless | Nutrition | Polyunsaturated Fat | 5 | g | no | no | 1 |
| Lossless | Nutrition | Protein | 5 | g | no | no | 1 |
| Lossless | Nutrition | Saturated Fat | 5 | g | no | no | 1 |
| Lossless | Nutrition | Sodium | 5 | mg | no | no | 1 |
| Lossless | Nutrition | Sugar | 5 | g | no | no | 1 |
| Lossless | Nutrition | Water | 5 | L | no | no | 1 |
| Lossless | Other | Alcoholic Beverages | 5 | drinks | no | no | 1 |
| Lossless | Other | Blood Alcohol Content | 5 | percent | no | no | 1 |
| Lossless | Other | Handwashing | 5 | events | no | no | 1 |
| Lossless | Other | Insulin Delivery | 5 | IU | no | no | 1 |
| Lossless | Other | Number of Falls | 5 | falls | no | no | 1 |
| Lossless | Other | Time in Daylight | 5 | min | no | no | 1 |
| Lossless | Other | Toothbrushing | 5 | events | no | no | 1 |
| Lossless | Other | UV Exposure | 5 | empty | no | no | 1 |
| Lossless | Other | Underwater Depth | 5 | m | no | no | 1 |
| Lossless | Other | Water Temperature | 5 | °C | no | no | 1 |
| Lossless | Raw HealthKit | Archive Manifest | 6 | json | yes | yes | 1 |
| Lossless | Raw HealthKit | Integrity Warning | 6 | json | yes | yes | 2 |
| Lossless | Raw HealthKit | Query Failure | 6 | json | yes | yes | 2 |
| Lossless | Raw HealthKit | Raw Capture Status | 6 | status | yes | no | 1 |
| Lossless | Raw HealthKit | Raw HealthKit External Record | 6 | json | yes | yes | 4 |
| Lossless | Raw HealthKit | Raw HealthKit Record | 6 | json | yes | yes | 20 |
| Lossless | Reproductive Health | Cervical Mucus Quality | 5 | empty | no | no | 1 |
| Lossless | Reproductive Health | Menstrual Flow | 5 | empty | no | no | 1 |
| Lossless | Reproductive Health | Ovulation Test Result | 5 | empty | no | no | 1 |
| Lossless | Reproductive Health | Sexual Activity | 5 | empty | no | no | 1 |
| Lossless | Reproductive Health | Spotting | 5 | empty | no | no | 1 |
| Lossless | Sleep | Awake Time | 5 | seconds | no | no | 1 |
| Lossless | Sleep | Bedtime | 5 | time | no | no | 1 |
| Lossless | Sleep | Core Sleep | 5 | seconds | no | no | 1 |
| Lossless | Sleep | Deep Sleep | 5 | seconds | no | no | 1 |
| Lossless | Sleep | In Bed Time | 5 | seconds | no | no | 1 |
| Lossless | Sleep | REM Sleep | 5 | seconds | no | no | 1 |
| Lossless | Sleep | Sleep Stage | 6 | seconds | yes | yes | 6 |
| Lossless | Sleep | Total Duration | 5 | seconds | no | no | 1 |
| Lossless | Sleep | Wake Time | 5 | time | no | no | 1 |
| Lossless | State of Mind | Daily Mood Associations at 08:00 | 6 | associations | yes | no | 1 |
| Lossless | State of Mind | Daily Mood Labels at 08:00 | 6 | labels | yes | no | 1 |
| Lossless | State of Mind | Daily Mood at 08:00 | 6 | valence | yes | no | 1 |
| Lossless | State of Mind | Momentary Emotion Associations at 14:00 | 6 | associations | yes | no | 1 |
| Lossless | State of Mind | Momentary Emotion Labels at 14:00 | 6 | labels | yes | no | 1 |
| Lossless | State of Mind | Momentary Emotion at 14:00 | 6 | valence | yes | no | 1 |
| Lossless | State of Mind | Unknown Labels at 19:00 | 6 | labels | yes | no | 1 |
| Lossless | State of Mind | Unknown at 19:00 | 6 | valence | yes | no | 1 |
| Lossless | Symptoms | Abdominal Cramps | 5 | count | no | no | 1 |
| Lossless | Symptoms | Acne | 5 | count | no | no | 1 |
| Lossless | Symptoms | Appetite Changes | 5 | count | no | no | 1 |
| Lossless | Symptoms | Bladder Incontinence | 5 | count | no | no | 1 |
| Lossless | Symptoms | Bloating | 5 | count | no | no | 1 |
| Lossless | Symptoms | Body Ache | 5 | count | no | no | 1 |
| Lossless | Symptoms | Breast Pain | 5 | count | no | no | 1 |
| Lossless | Symptoms | Chest Pain | 5 | count | no | no | 1 |
| Lossless | Symptoms | Chills | 5 | count | no | no | 1 |
| Lossless | Symptoms | Constipation | 5 | count | no | no | 1 |
| Lossless | Symptoms | Coughing | 5 | count | no | no | 1 |
| Lossless | Symptoms | Diarrhea | 5 | count | no | no | 1 |
| Lossless | Symptoms | Dizziness | 5 | count | no | no | 1 |
| Lossless | Symptoms | Dry Skin | 5 | count | no | no | 1 |
| Lossless | Symptoms | Fainting | 5 | count | no | no | 1 |
| Lossless | Symptoms | Fatigue | 5 | count | no | no | 1 |
| Lossless | Symptoms | Fever | 5 | count | no | no | 1 |
| Lossless | Symptoms | Hair Loss | 5 | count | no | no | 1 |
| Lossless | Symptoms | Headache | 5 | count | no | no | 1 |
| Lossless | Symptoms | Heartburn | 5 | count | no | no | 1 |
| Lossless | Symptoms | Hot Flashes | 5 | count | no | no | 1 |
| Lossless | Symptoms | Loss Of Smell | 5 | count | no | no | 1 |
| Lossless | Symptoms | Loss Of Taste | 5 | count | no | no | 1 |
| Lossless | Symptoms | Lower Back Pain | 5 | count | no | no | 1 |
| Lossless | Symptoms | Memory Lapse | 5 | count | no | no | 1 |
| Lossless | Symptoms | Mood Changes | 5 | count | no | no | 1 |
| Lossless | Symptoms | Nausea | 5 | count | no | no | 1 |
| Lossless | Symptoms | Night Sweats | 5 | count | no | no | 1 |
| Lossless | Symptoms | Pelvic Pain | 5 | count | no | no | 1 |
| Lossless | Symptoms | Rapid Heartbeat | 5 | count | no | no | 1 |
| Lossless | Symptoms | Runny Nose | 5 | count | no | no | 1 |
| Lossless | Symptoms | Shortness Of Breath | 5 | count | no | no | 1 |
| Lossless | Symptoms | Sinus Congestion | 5 | count | no | no | 1 |
| Lossless | Symptoms | Skipped Heartbeat | 5 | count | no | no | 1 |
| Lossless | Symptoms | Sleep Changes | 5 | count | no | no | 1 |
| Lossless | Symptoms | Sore Throat | 5 | count | no | no | 1 |
| Lossless | Symptoms | Vaginal Dryness | 5 | count | no | no | 1 |
| Lossless | Symptoms | Vomiting | 5 | count | no | no | 1 |
| Lossless | Symptoms | Wheezing | 5 | count | no | no | 1 |
| Lossless | Vitals | Basal Body Temperature | 5 | °C | no | no | 1 |
| Lossless | Vitals | Blood Glucose Avg | 5 | mg/dL | no | no | 1 |
| Lossless | Vitals | Blood Glucose Max | 5 | mg/dL | no | no | 1 |
| Lossless | Vitals | Blood Glucose Min | 5 | mg/dL | no | no | 1 |
| Lossless | Vitals | Blood Glucose Sample | 6 | mg/dL | yes | yes | 1 |
| Lossless | Vitals | Blood Oxygen Avg | 5 | percent | no | no | 1 |
| Lossless | Vitals | Blood Oxygen Max | 5 | percent | no | no | 1 |
| Lossless | Vitals | Blood Oxygen Min | 5 | percent | no | no | 1 |
| Lossless | Vitals | Blood Oxygen Sample | 6 | percent | yes | yes | 1 |
| Lossless | Vitals | Blood Pressure Diastolic Avg | 5 | mmHg | no | no | 1 |
| Lossless | Vitals | Blood Pressure Diastolic Max | 5 | mmHg | no | no | 1 |
| Lossless | Vitals | Blood Pressure Diastolic Min | 5 | mmHg | no | no | 1 |
| Lossless | Vitals | Blood Pressure Sample | 6 | mmHg | yes | yes | 1 |
| Lossless | Vitals | Blood Pressure Systolic Avg | 5 | mmHg | no | no | 1 |
| Lossless | Vitals | Blood Pressure Systolic Max | 5 | mmHg | no | no | 1 |
| Lossless | Vitals | Blood Pressure Systolic Min | 5 | mmHg | no | no | 1 |
| Lossless | Vitals | Body Temperature Avg | 5 | °C | no | no | 1 |
| Lossless | Vitals | Body Temperature Max | 5 | °C | no | no | 1 |
| Lossless | Vitals | Body Temperature Min | 5 | °C | no | no | 1 |
| Lossless | Vitals | Electrodermal Activity | 5 | µS | no | no | 1 |
| Lossless | Vitals | FEV1 | 5 | L | no | no | 1 |
| Lossless | Vitals | Forced Vital Capacity | 5 | L | no | no | 1 |
| Lossless | Vitals | Inhaler Usage | 5 | uses | no | no | 1 |
| Lossless | Vitals | Peak Expiratory Flow | 5 | L/min | no | no | 1 |
| Lossless | Vitals | Respiratory Rate Avg | 5 | breaths/min | no | no | 1 |
| Lossless | Vitals | Respiratory Rate Max | 5 | breaths/min | no | no | 1 |
| Lossless | Vitals | Respiratory Rate Min | 5 | breaths/min | no | no | 1 |
| Lossless | Vitals | Respiratory Rate Sample | 6 | breaths/min | yes | yes | 1 |
| Lossless | Vitals | Wrist Temperature | 5 | °C | no | no | 1 |
| Lossless | Vitamins | Biotin | 5 | µg | no | no | 1 |
| Lossless | Vitamins | Folate | 5 | µg | no | no | 1 |
| Lossless | Vitamins | Niacin (B3) | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Pantothenic Acid (B5) | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Riboflavin (B2) | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Thiamin (B1) | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Vitamin A | 5 | µg | no | no | 1 |
| Lossless | Vitamins | Vitamin B12 | 5 | µg | no | no | 1 |
| Lossless | Vitamins | Vitamin B6 | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Vitamin C | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Vitamin D | 5 | µg | no | no | 1 |
| Lossless | Vitamins | Vitamin E | 5 | mg | no | no | 1 |
| Lossless | Vitamins | Vitamin K | 5 | µg | no | no | 1 |
| Lossless | Workouts | Cycling Avg Cadence | 5 | rpm | no | no | 1 |
| Lossless | Workouts | Cycling Avg Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Cycling Avg Power | 5 | W | no | no | 1 |
| Lossless | Workouts | Cycling Avg Speed | 5 | empty | no | no | 1 |
| Lossless | Workouts | Cycling Calories | 5 | kcal | no | no | 1 |
| Lossless | Workouts | Cycling Distance | 5 | meters | no | no | 1 |
| Lossless | Workouts | Cycling Duration | 5 | seconds | no | no | 1 |
| Lossless | Workouts | Cycling Max Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Cycling Max Power | 5 | W | no | no | 1 |
| Lossless | Workouts | Cycling Min Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Cycling Start Time | 5 | time | no | no | 1 |
| Lossless | Workouts | HealthKit Activity Type | 6 | empty | yes | yes | 3 |
| Lossless | Workouts | HealthKit Activity Type Raw Value | 6 | empty | yes | yes | 3 |
| Lossless | Workouts | Running Avg Cadence | 5 | rpm | no | no | 1 |
| Lossless | Workouts | Running Avg Cadence | 5 | spm | no | no | 1 |
| Lossless | Workouts | Running Avg Ground Contact | 5 | ms | no | no | 1 |
| Lossless | Workouts | Running Avg Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Running Avg Pace | 5 | empty | no | no | 1 |
| Lossless | Workouts | Running Avg Power | 5 | W | no | no | 1 |
| Lossless | Workouts | Running Avg Stride Length | 5 | m | no | no | 1 |
| Lossless | Workouts | Running Avg Vertical Oscillation | 5 | cm | no | no | 1 |
| Lossless | Workouts | Running Calories | 5 | kcal | no | no | 1 |
| Lossless | Workouts | Running Distance | 5 | meters | no | no | 1 |
| Lossless | Workouts | Running Duration | 5 | seconds | no | no | 1 |
| Lossless | Workouts | Running Elevation Gain | 5 | m | no | no | 1 |
| Lossless | Workouts | Running Elevation Loss | 5 | m | no | no | 1 |
| Lossless | Workouts | Running Lap 1 Distance | 5 | meters | no | no | 1 |
| Lossless | Workouts | Running Lap 1 Duration | 5 | seconds | no | no | 1 |
| Lossless | Workouts | Running Lap 1 Pace | 5 | empty | no | no | 1 |
| Lossless | Workouts | Running Location | 5 | empty | no | no | 1 |
| Lossless | Workouts | Running Max Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Running Max Power | 5 | W | no | no | 1 |
| Lossless | Workouts | Running Min Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Running Split 1 Avg Heart Rate | 5 | bpm | no | no | 1 |
| Lossless | Workouts | Running Split 1 Pace | 5 | empty | no | no | 1 |
| Lossless | Workouts | Running Start Time | 5 | time | no | no | 1 |
| Lossless | Workouts | Swimming Avg Pace | 5 | empty | no | no | 1 |
| Lossless | Workouts | Swimming Calories | 5 | kcal | no | no | 1 |
| Lossless | Workouts | Swimming Distance | 5 | meters | no | no | 1 |
| Lossless | Workouts | Swimming Duration | 5 | seconds | no | no | 1 |
| Lossless | Workouts | Swimming Location | 5 | empty | no | no | 1 |
| Lossless | Workouts | Swimming Start Time | 5 | time | no | no | 1 |
| Lossless | Workouts | Workout Activity Type | 6 | empty | yes | yes | 3 |
| Lossless | Workouts | Workout Sport | 6 | empty | yes | yes | 3 |
| Summary | Activity | Active Calories | 5 | kcal | no | no | 1 |
| Summary | Activity | Basal Energy | 5 | kcal | no | no | 1 |
| Summary | Activity | Cardio Fitness (VO2 Max) | 6 | mL/kg/min | yes | yes | 1 |
| Summary | Activity | Cycling Distance | 5 | meters | no | no | 1 |
| Summary | Activity | Downhill Snow Sports Distance | 5 | meters | no | no | 1 |
| Summary | Activity | Exercise Minutes | 5 | minutes | no | no | 1 |
| Summary | Activity | Flights Climbed | 5 | count | no | no | 1 |
| Summary | Activity | Move Time | 5 | min | no | no | 1 |
| Summary | Activity | Physical Effort | 5 | kcal/hr/kg | no | no | 1 |
| Summary | Activity | Stand Hours | 5 | hours | no | no | 1 |
| Summary | Activity | Stand Time | 5 | minutes | no | no | 1 |
| Summary | Activity | Steps | 5 | count | no | no | 1 |
| Summary | Activity | Swimming Distance | 5 | meters | no | no | 1 |
| Summary | Activity | Swimming Strokes | 5 | count | no | no | 1 |
| Summary | Activity | VO2 Max Age | 6 | seconds | yes | yes | 1 |
| Summary | Activity | VO2 Max Carried Forward | 6 | boolean | yes | yes | 1 |
| Summary | Activity | VO2 Max Source End | 6 | datetime | yes | yes | 1 |
| Summary | Activity | VO2 Max Source Start | 6 | datetime | yes | yes | 1 |
| Summary | Activity | VO2 Max Source UUID | 6 | uuid | yes | yes | 1 |
| Summary | Activity | Walking Running Distance | 5 | meters | no | no | 1 |
| Summary | Activity | Wheelchair Distance | 5 | meters | no | no | 1 |
| Summary | Activity | Wheelchair Pushes | 5 | count | no | no | 1 |
| Summary | Body | BMI | 5 | empty | no | no | 1 |
| Summary | Body | Body Fat Percentage | 5 | percent | no | no | 1 |
| Summary | Body | Height | 5 | m | no | no | 1 |
| Summary | Body | Lean Body Mass | 5 | kg | no | no | 1 |
| Summary | Body | Waist Circumference | 5 | cm | no | no | 1 |
| Summary | Body | Weight | 5 | kg | no | no | 1 |
| Summary | Cycling | Cycling Cadence | 5 | rpm | no | no | 1 |
| Summary | Cycling | Cycling Distance | 5 | km | no | no | 1 |
| Summary | Cycling | Cycling Power | 5 | W | no | no | 1 |
| Summary | Cycling | Cycling Speed | 5 | m/s | no | no | 1 |
| Summary | Cycling | Functional Threshold Power | 5 | W | no | no | 1 |
| Summary | Hearing | Environmental Sound Level | 5 | dB | no | no | 1 |
| Summary | Hearing | Headphone Audio Level | 5 | dB | no | no | 1 |
| Summary | Heart | AFib Burden | 5 | % | no | no | 1 |
| Summary | Heart | Average Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Heart | HRV | 5 | ms | no | no | 1 |
| Summary | Heart | HRV Sample | 6 | ms | yes | yes | 1 |
| Summary | Heart | Heart Rate Recovery | 5 | bpm | no | no | 1 |
| Summary | Heart | Heart Rate Sample | 6 | bpm | yes | yes | 2 |
| Summary | Heart | Max Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Heart | Min Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Heart | Resting Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Heart | Walking Heart Rate Average | 5 | bpm | no | no | 1 |
| Summary | Medications | Active Medications | 5 | count | no | no | 1 |
| Summary | Medications | Archived Medications | 5 | count | no | no | 1 |
| Summary | Medications | Authorized Medications | 5 | count | no | no | 1 |
| Summary | Medications | Dose Event | 6 | as_needed | yes | yes | 1 |
| Summary | Medications | Dose Event | 6 | scheduled | yes | yes | 1 |
| Summary | Medications | Dose Event Dose Quantity | 6 | capsule | yes | yes | 1 |
| Summary | Medications | Dose Event Dose Quantity | 6 | tablet | yes | yes | 1 |
| Summary | Medications | Dose Event End | 6 | datetime | yes | yes | 2 |
| Summary | Medications | Dose Event ID | 6 | uuid | yes | yes | 2 |
| Summary | Medications | Dose Event Medication Concept Identifier | 6 | empty | yes | yes | 2 |
| Summary | Medications | Dose Event Medication Name | 6 | empty | yes | yes | 2 |
| Summary | Medications | Dose Event Metadata reason | 6 | metadata | yes | yes | 1 |
| Summary | Medications | Dose Event Metadata with_food | 6 | metadata | yes | yes | 1 |
| Summary | Medications | Dose Event Schedule Type | 6 | empty | yes | yes | 2 |
| Summary | Medications | Dose Event Scheduled Date | 6 | datetime | yes | yes | 1 |
| Summary | Medications | Dose Event Scheduled Dose Quantity | 6 | tablet | yes | yes | 1 |
| Summary | Medications | Dose Event Start | 6 | datetime | yes | yes | 2 |
| Summary | Medications | Dose Event Status | 6 | empty | yes | yes | 2 |
| Summary | Medications | Dose Event Status Display | 6 | empty | yes | yes | 2 |
| Summary | Medications | Dose Event Unit | 6 | empty | yes | yes | 2 |
| Summary | Medications | Dose Events | 5 | count | no | no | 1 |
| Summary | Medications | Medication | 6 | active;scheduled | yes | no | 1 |
| Summary | Medications | Medication | 6 | archived;as_needed | yes | no | 1 |
| Summary | Medications | Medication Archived | 6 | boolean | yes | no | 2 |
| Summary | Medications | Medication Concept Identifier | 6 | empty | yes | no | 2 |
| Summary | Medications | Medication Display Name | 6 | empty | yes | no | 2 |
| Summary | Medications | Medication Export Name | 6 | empty | yes | no | 2 |
| Summary | Medications | Medication General Form | 6 | empty | yes | no | 2 |
| Summary | Medications | Medication Has Schedule | 6 | boolean | yes | no | 2 |
| Summary | Medications | Medication Nickname | 6 | empty | yes | no | 1 |
| Summary | Medications | Medication Related Coding | 6 | coding | yes | no | 1 |
| Summary | Medications | Medication RxNorm Code | 6 | rxnorm | yes | no | 1 |
| Summary | Medications | Skipped Doses | 5 | count | no | no | 1 |
| Summary | Medications | Taken Doses | 5 | count | no | no | 1 |
| Summary | Metadata | schema | 6 | empty | yes | no | 1 |
| Summary | Metadata | schema_version | 6 | empty | yes | no | 1 |
| Summary | Metadata | time_context.calendar_timezone | 6 | empty | yes | no | 1 |
| Summary | Metadata | time_context.timestamp_timezone | 6 | empty | yes | no | 1 |
| Summary | Metadata | unit_system | 6 | empty | yes | no | 1 |
| Summary | Mindfulness | Average Mood Percent | 5 | percent | no | no | 1 |
| Summary | Mindfulness | Average Mood Valence | 5 | scale(-1 to 1) | no | no | 1 |
| Summary | Mindfulness | Daily Mood Count | 5 | count | no | no | 1 |
| Summary | Mindfulness | Daily Mood Percent | 5 | percent | no | no | 1 |
| Summary | Mindfulness | Mindful Minutes | 5 | minutes | no | no | 1 |
| Summary | Mindfulness | Mindful Sessions | 5 | count | no | no | 1 |
| Summary | Mindfulness | Momentary Emotion Count | 5 | count | no | no | 1 |
| Summary | Mindfulness | State of Mind Entries | 5 | count | no | no | 1 |
| Summary | Minerals | Calcium | 5 | mg | no | no | 1 |
| Summary | Minerals | Chloride | 5 | mg | no | no | 1 |
| Summary | Minerals | Chromium | 5 | µg | no | no | 1 |
| Summary | Minerals | Copper | 5 | mg | no | no | 1 |
| Summary | Minerals | Iodine | 5 | µg | no | no | 1 |
| Summary | Minerals | Iron | 5 | mg | no | no | 1 |
| Summary | Minerals | Magnesium | 5 | mg | no | no | 1 |
| Summary | Minerals | Manganese | 5 | mg | no | no | 1 |
| Summary | Minerals | Molybdenum | 5 | µg | no | no | 1 |
| Summary | Minerals | Phosphorus | 5 | mg | no | no | 1 |
| Summary | Minerals | Potassium | 5 | mg | no | no | 1 |
| Summary | Minerals | Selenium | 5 | µg | no | no | 1 |
| Summary | Minerals | Zinc | 5 | mg | no | no | 1 |
| Summary | Mobility | Double Support Percentage | 5 | percent | no | no | 1 |
| Summary | Mobility | Running Ground Contact Time | 5 | ms | no | no | 1 |
| Summary | Mobility | Running Power | 5 | W | no | no | 1 |
| Summary | Mobility | Running Speed | 5 | m/s | no | no | 1 |
| Summary | Mobility | Running Stride Length | 5 | m | no | no | 1 |
| Summary | Mobility | Running Vertical Oscillation | 5 | cm | no | no | 1 |
| Summary | Mobility | Six Minute Walk Distance | 5 | meters | no | no | 1 |
| Summary | Mobility | Stair Ascent Speed | 5 | m/s | no | no | 1 |
| Summary | Mobility | Stair Descent Speed | 5 | m/s | no | no | 1 |
| Summary | Mobility | Walking Asymmetry | 5 | percent | no | no | 1 |
| Summary | Mobility | Walking Speed | 5 | m/s | no | no | 1 |
| Summary | Mobility | Walking Steadiness | 5 | % | no | no | 1 |
| Summary | Mobility | Walking Step Length | 5 | meters | no | no | 1 |
| Summary | Nutrition | Caffeine | 5 | mg | no | no | 1 |
| Summary | Nutrition | Carbohydrates | 5 | g | no | no | 1 |
| Summary | Nutrition | Cholesterol | 5 | mg | no | no | 1 |
| Summary | Nutrition | Dietary Energy | 5 | kcal | no | no | 1 |
| Summary | Nutrition | Fat | 5 | g | no | no | 1 |
| Summary | Nutrition | Fiber | 5 | g | no | no | 1 |
| Summary | Nutrition | Monounsaturated Fat | 5 | g | no | no | 1 |
| Summary | Nutrition | Polyunsaturated Fat | 5 | g | no | no | 1 |
| Summary | Nutrition | Protein | 5 | g | no | no | 1 |
| Summary | Nutrition | Saturated Fat | 5 | g | no | no | 1 |
| Summary | Nutrition | Sodium | 5 | mg | no | no | 1 |
| Summary | Nutrition | Sugar | 5 | g | no | no | 1 |
| Summary | Nutrition | Water | 5 | L | no | no | 1 |
| Summary | Other | Alcoholic Beverages | 5 | drinks | no | no | 1 |
| Summary | Other | Blood Alcohol Content | 5 | percent | no | no | 1 |
| Summary | Other | Handwashing | 5 | events | no | no | 1 |
| Summary | Other | Insulin Delivery | 5 | IU | no | no | 1 |
| Summary | Other | Number of Falls | 5 | falls | no | no | 1 |
| Summary | Other | Time in Daylight | 5 | min | no | no | 1 |
| Summary | Other | Toothbrushing | 5 | events | no | no | 1 |
| Summary | Other | UV Exposure | 5 | empty | no | no | 1 |
| Summary | Other | Underwater Depth | 5 | m | no | no | 1 |
| Summary | Other | Water Temperature | 5 | °C | no | no | 1 |
| Summary | Raw HealthKit | Raw Capture Status | 6 | status | yes | no | 1 |
| Summary | Reproductive Health | Cervical Mucus Quality | 5 | empty | no | no | 1 |
| Summary | Reproductive Health | Menstrual Flow | 5 | empty | no | no | 1 |
| Summary | Reproductive Health | Ovulation Test Result | 5 | empty | no | no | 1 |
| Summary | Reproductive Health | Sexual Activity | 5 | empty | no | no | 1 |
| Summary | Reproductive Health | Spotting | 5 | empty | no | no | 1 |
| Summary | Sleep | Awake Time | 5 | seconds | no | no | 1 |
| Summary | Sleep | Bedtime | 5 | time | no | no | 1 |
| Summary | Sleep | Core Sleep | 5 | seconds | no | no | 1 |
| Summary | Sleep | Deep Sleep | 5 | seconds | no | no | 1 |
| Summary | Sleep | In Bed Time | 5 | seconds | no | no | 1 |
| Summary | Sleep | REM Sleep | 5 | seconds | no | no | 1 |
| Summary | Sleep | Sleep Stage | 6 | seconds | yes | yes | 6 |
| Summary | Sleep | Total Duration | 5 | seconds | no | no | 1 |
| Summary | Sleep | Wake Time | 5 | time | no | no | 1 |
| Summary | State of Mind | Daily Mood Associations at 08:00 | 6 | associations | yes | no | 1 |
| Summary | State of Mind | Daily Mood Labels at 08:00 | 6 | labels | yes | no | 1 |
| Summary | State of Mind | Daily Mood at 08:00 | 6 | valence | yes | no | 1 |
| Summary | State of Mind | Momentary Emotion Associations at 14:00 | 6 | associations | yes | no | 1 |
| Summary | State of Mind | Momentary Emotion Labels at 14:00 | 6 | labels | yes | no | 1 |
| Summary | State of Mind | Momentary Emotion at 14:00 | 6 | valence | yes | no | 1 |
| Summary | State of Mind | Unknown Labels at 19:00 | 6 | labels | yes | no | 1 |
| Summary | State of Mind | Unknown at 19:00 | 6 | valence | yes | no | 1 |
| Summary | Symptoms | Abdominal Cramps | 5 | count | no | no | 1 |
| Summary | Symptoms | Acne | 5 | count | no | no | 1 |
| Summary | Symptoms | Appetite Changes | 5 | count | no | no | 1 |
| Summary | Symptoms | Bladder Incontinence | 5 | count | no | no | 1 |
| Summary | Symptoms | Bloating | 5 | count | no | no | 1 |
| Summary | Symptoms | Body Ache | 5 | count | no | no | 1 |
| Summary | Symptoms | Breast Pain | 5 | count | no | no | 1 |
| Summary | Symptoms | Chest Pain | 5 | count | no | no | 1 |
| Summary | Symptoms | Chills | 5 | count | no | no | 1 |
| Summary | Symptoms | Constipation | 5 | count | no | no | 1 |
| Summary | Symptoms | Coughing | 5 | count | no | no | 1 |
| Summary | Symptoms | Diarrhea | 5 | count | no | no | 1 |
| Summary | Symptoms | Dizziness | 5 | count | no | no | 1 |
| Summary | Symptoms | Dry Skin | 5 | count | no | no | 1 |
| Summary | Symptoms | Fainting | 5 | count | no | no | 1 |
| Summary | Symptoms | Fatigue | 5 | count | no | no | 1 |
| Summary | Symptoms | Fever | 5 | count | no | no | 1 |
| Summary | Symptoms | Hair Loss | 5 | count | no | no | 1 |
| Summary | Symptoms | Headache | 5 | count | no | no | 1 |
| Summary | Symptoms | Heartburn | 5 | count | no | no | 1 |
| Summary | Symptoms | Hot Flashes | 5 | count | no | no | 1 |
| Summary | Symptoms | Loss Of Smell | 5 | count | no | no | 1 |
| Summary | Symptoms | Loss Of Taste | 5 | count | no | no | 1 |
| Summary | Symptoms | Lower Back Pain | 5 | count | no | no | 1 |
| Summary | Symptoms | Memory Lapse | 5 | count | no | no | 1 |
| Summary | Symptoms | Mood Changes | 5 | count | no | no | 1 |
| Summary | Symptoms | Nausea | 5 | count | no | no | 1 |
| Summary | Symptoms | Night Sweats | 5 | count | no | no | 1 |
| Summary | Symptoms | Pelvic Pain | 5 | count | no | no | 1 |
| Summary | Symptoms | Rapid Heartbeat | 5 | count | no | no | 1 |
| Summary | Symptoms | Runny Nose | 5 | count | no | no | 1 |
| Summary | Symptoms | Shortness Of Breath | 5 | count | no | no | 1 |
| Summary | Symptoms | Sinus Congestion | 5 | count | no | no | 1 |
| Summary | Symptoms | Skipped Heartbeat | 5 | count | no | no | 1 |
| Summary | Symptoms | Sleep Changes | 5 | count | no | no | 1 |
| Summary | Symptoms | Sore Throat | 5 | count | no | no | 1 |
| Summary | Symptoms | Vaginal Dryness | 5 | count | no | no | 1 |
| Summary | Symptoms | Vomiting | 5 | count | no | no | 1 |
| Summary | Symptoms | Wheezing | 5 | count | no | no | 1 |
| Summary | Vitals | Basal Body Temperature | 5 | °C | no | no | 1 |
| Summary | Vitals | Blood Glucose Avg | 5 | mg/dL | no | no | 1 |
| Summary | Vitals | Blood Glucose Max | 5 | mg/dL | no | no | 1 |
| Summary | Vitals | Blood Glucose Min | 5 | mg/dL | no | no | 1 |
| Summary | Vitals | Blood Glucose Sample | 6 | mg/dL | yes | yes | 1 |
| Summary | Vitals | Blood Oxygen Avg | 5 | percent | no | no | 1 |
| Summary | Vitals | Blood Oxygen Max | 5 | percent | no | no | 1 |
| Summary | Vitals | Blood Oxygen Min | 5 | percent | no | no | 1 |
| Summary | Vitals | Blood Oxygen Sample | 6 | percent | yes | yes | 1 |
| Summary | Vitals | Blood Pressure Diastolic Avg | 5 | mmHg | no | no | 1 |
| Summary | Vitals | Blood Pressure Diastolic Max | 5 | mmHg | no | no | 1 |
| Summary | Vitals | Blood Pressure Diastolic Min | 5 | mmHg | no | no | 1 |
| Summary | Vitals | Blood Pressure Sample | 6 | mmHg | yes | yes | 1 |
| Summary | Vitals | Blood Pressure Systolic Avg | 5 | mmHg | no | no | 1 |
| Summary | Vitals | Blood Pressure Systolic Max | 5 | mmHg | no | no | 1 |
| Summary | Vitals | Blood Pressure Systolic Min | 5 | mmHg | no | no | 1 |
| Summary | Vitals | Body Temperature Avg | 5 | °C | no | no | 1 |
| Summary | Vitals | Body Temperature Max | 5 | °C | no | no | 1 |
| Summary | Vitals | Body Temperature Min | 5 | °C | no | no | 1 |
| Summary | Vitals | Electrodermal Activity | 5 | µS | no | no | 1 |
| Summary | Vitals | FEV1 | 5 | L | no | no | 1 |
| Summary | Vitals | Forced Vital Capacity | 5 | L | no | no | 1 |
| Summary | Vitals | Inhaler Usage | 5 | uses | no | no | 1 |
| Summary | Vitals | Peak Expiratory Flow | 5 | L/min | no | no | 1 |
| Summary | Vitals | Respiratory Rate Avg | 5 | breaths/min | no | no | 1 |
| Summary | Vitals | Respiratory Rate Max | 5 | breaths/min | no | no | 1 |
| Summary | Vitals | Respiratory Rate Min | 5 | breaths/min | no | no | 1 |
| Summary | Vitals | Respiratory Rate Sample | 6 | breaths/min | yes | yes | 1 |
| Summary | Vitals | Wrist Temperature | 5 | °C | no | no | 1 |
| Summary | Vitamins | Biotin | 5 | µg | no | no | 1 |
| Summary | Vitamins | Folate | 5 | µg | no | no | 1 |
| Summary | Vitamins | Niacin (B3) | 5 | mg | no | no | 1 |
| Summary | Vitamins | Pantothenic Acid (B5) | 5 | mg | no | no | 1 |
| Summary | Vitamins | Riboflavin (B2) | 5 | mg | no | no | 1 |
| Summary | Vitamins | Thiamin (B1) | 5 | mg | no | no | 1 |
| Summary | Vitamins | Vitamin A | 5 | µg | no | no | 1 |
| Summary | Vitamins | Vitamin B12 | 5 | µg | no | no | 1 |
| Summary | Vitamins | Vitamin B6 | 5 | mg | no | no | 1 |
| Summary | Vitamins | Vitamin C | 5 | mg | no | no | 1 |
| Summary | Vitamins | Vitamin D | 5 | µg | no | no | 1 |
| Summary | Vitamins | Vitamin E | 5 | mg | no | no | 1 |
| Summary | Vitamins | Vitamin K | 5 | µg | no | no | 1 |
| Summary | Workouts | Cycling Avg Cadence | 5 | rpm | no | no | 1 |
| Summary | Workouts | Cycling Avg Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Cycling Avg Power | 5 | W | no | no | 1 |
| Summary | Workouts | Cycling Avg Speed | 5 | empty | no | no | 1 |
| Summary | Workouts | Cycling Calories | 5 | kcal | no | no | 1 |
| Summary | Workouts | Cycling Distance | 5 | meters | no | no | 1 |
| Summary | Workouts | Cycling Duration | 5 | seconds | no | no | 1 |
| Summary | Workouts | Cycling Max Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Cycling Max Power | 5 | W | no | no | 1 |
| Summary | Workouts | Cycling Min Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Cycling Start Time | 5 | time | no | no | 1 |
| Summary | Workouts | HealthKit Activity Type | 6 | empty | yes | yes | 3 |
| Summary | Workouts | HealthKit Activity Type Raw Value | 6 | empty | yes | yes | 3 |
| Summary | Workouts | Running Avg Cadence | 5 | rpm | no | no | 1 |
| Summary | Workouts | Running Avg Cadence | 5 | spm | no | no | 1 |
| Summary | Workouts | Running Avg Ground Contact | 5 | ms | no | no | 1 |
| Summary | Workouts | Running Avg Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Running Avg Pace | 5 | empty | no | no | 1 |
| Summary | Workouts | Running Avg Power | 5 | W | no | no | 1 |
| Summary | Workouts | Running Avg Stride Length | 5 | m | no | no | 1 |
| Summary | Workouts | Running Avg Vertical Oscillation | 5 | cm | no | no | 1 |
| Summary | Workouts | Running Calories | 5 | kcal | no | no | 1 |
| Summary | Workouts | Running Distance | 5 | meters | no | no | 1 |
| Summary | Workouts | Running Duration | 5 | seconds | no | no | 1 |
| Summary | Workouts | Running Elevation Gain | 5 | m | no | no | 1 |
| Summary | Workouts | Running Elevation Loss | 5 | m | no | no | 1 |
| Summary | Workouts | Running Lap 1 Distance | 5 | meters | no | no | 1 |
| Summary | Workouts | Running Lap 1 Duration | 5 | seconds | no | no | 1 |
| Summary | Workouts | Running Lap 1 Pace | 5 | empty | no | no | 1 |
| Summary | Workouts | Running Location | 5 | empty | no | no | 1 |
| Summary | Workouts | Running Max Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Running Max Power | 5 | W | no | no | 1 |
| Summary | Workouts | Running Min Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Running Split 1 Avg Heart Rate | 5 | bpm | no | no | 1 |
| Summary | Workouts | Running Split 1 Pace | 5 | empty | no | no | 1 |
| Summary | Workouts | Running Start Time | 5 | time | no | no | 1 |
| Summary | Workouts | Swimming Avg Pace | 5 | empty | no | no | 1 |
| Summary | Workouts | Swimming Calories | 5 | kcal | no | no | 1 |
| Summary | Workouts | Swimming Distance | 5 | meters | no | no | 1 |
| Summary | Workouts | Swimming Duration | 5 | seconds | no | no | 1 |
| Summary | Workouts | Swimming Location | 5 | empty | no | no | 1 |
| Summary | Workouts | Swimming Start Time | 5 | time | no | no | 1 |
| Summary | Workouts | Workout Activity Type | 6 | empty | yes | yes | 3 |
| Summary | Workouts | Workout Sport | 6 | empty | yes | yes | 3 |
