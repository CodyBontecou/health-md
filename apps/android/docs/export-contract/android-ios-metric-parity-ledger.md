# Android ↔ Apple metric registry

**Generated:** do not edit by hand. Source: `packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json`.

This inventory records an explicit Android decision for every current Apple metric. Hidden unavailable rows are contract accounting and are not fabricated as empty export fields.

## iOS metric parity table

| iOS metric id | iOS category | Android status | Android metric id(s) | Notes |
|---|---|---|---|---|
| sleep_total | Sleep | supported | sleep_total | Exact persisted id. |
| sleep_bedtime | Sleep | mapped/alias | sleep_total,sleep_in_bed | Explicit shared-registry mapping; native selectors remain platform-owned. |
| sleep_wake | Sleep | mapped/alias | sleep_total,sleep_in_bed | Explicit shared-registry mapping; native selectors remain platform-owned. |
| sleep_deep | Sleep | supported | sleep_deep | Exact persisted id. |
| sleep_rem | Sleep | supported | sleep_rem | Exact persisted id. |
| sleep_core | Sleep | mapped/alias | sleep_light | Explicit shared-registry mapping; native selectors remain platform-owned. |
| sleep_awake | Sleep | supported | sleep_awake | Exact persisted id. |
| sleep_in_bed | Sleep | supported | sleep_in_bed | Exact persisted id. |
| steps | Activity | supported | steps | Exact persisted id. |
| distance_walking_running | Activity | mapped/alias | distance | Explicit shared-registry mapping; native selectors remain platform-owned. |
| distance_swimming | Activity | mapped/alias | swimming_distance | Explicit shared-registry mapping; native selectors remain platform-owned. |
| distance_wheelchair | Activity | mapped/alias | wheelchair_distance | Explicit shared-registry mapping; native selectors remain platform-owned. |
| distance_downhill_snow | Activity | mapped/alias | downhill_snow_distance | Explicit shared-registry mapping; native selectors remain platform-owned. |
| active_energy | Activity | mapped/alias | active_calories | Explicit shared-registry mapping; native selectors remain platform-owned. |
| basal_energy | Activity | mapped/alias | basal_calories | Explicit shared-registry mapping; native selectors remain platform-owned. |
| exercise_time | Activity | mapped/alias | exercise_minutes | Explicit shared-registry mapping; native selectors remain platform-owned. |
| stand_time | Activity | health-connect-unavailable | stand_time | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| stand_hours | Activity | health-connect-unavailable | stand_hours | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| move_time | Activity | health-connect-unavailable | move_time | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| flights_climbed | Activity | supported | flights_climbed | Exact persisted id. |
| swimming_strokes | Activity | supported | swimming_strokes | Exact persisted id. |
| push_count | Activity | mapped/alias | wheelchair_pushes | Explicit shared-registry mapping; native selectors remain platform-owned. |
| vo2_max | Activity | supported | vo2_max | Exact persisted id. |
| physical_effort | Activity | health-connect-unavailable | physical_effort | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| activity_summary | Activity | health-connect-unavailable | activity_summary | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| activity_move_mode | Activity | health-connect-unavailable | activity_move_mode | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| cross_country_skiing_speed | Activity | health-connect-unavailable | cross_country_skiing_speed | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| distance_cross_country_skiing | Activity | health-connect-unavailable | distance_cross_country_skiing | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| paddle_sports_speed | Activity | health-connect-unavailable | paddle_sports_speed | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| distance_paddle_sports | Activity | health-connect-unavailable | distance_paddle_sports | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| rowing_speed | Activity | health-connect-unavailable | rowing_speed | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| distance_rowing | Activity | health-connect-unavailable | distance_rowing | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| distance_skating_sports | Activity | health-connect-unavailable | distance_skating_sports | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| workout_effort_score | Activity | health-connect-unavailable | workout_effort_score | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| estimated_workout_effort_score | Activity | health-connect-unavailable | estimated_workout_effort_score | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| nike_fuel | Activity | health-connect-unavailable | nike_fuel | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| heart_rate_avg | Heart | mapped/alias | avg_hr | Explicit shared-registry mapping; native selectors remain platform-owned. |
| heart_rate_min | Heart | mapped/alias | min_hr | Explicit shared-registry mapping; native selectors remain platform-owned. |
| heart_rate_max | Heart | mapped/alias | max_hr | Explicit shared-registry mapping; native selectors remain platform-owned. |
| resting_heart_rate | Heart | mapped/alias | resting_hr | Explicit shared-registry mapping; native selectors remain platform-owned. |
| walking_heart_rate | Heart | mapped/alias | walking_hr | Explicit shared-registry mapping; native selectors remain platform-owned. |
| hrv | Heart | health-connect-unavailable | hrv | Explicit unavailable decision (hidden); Android does not fabricate a parity value. Related but non-equivalent Android selector(s): hrv. |
| heart_rate_recovery | Heart | health-connect-unavailable | heart_rate_recovery | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| afib_burden | Heart | health-connect-unavailable | afib_burden | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| peripheral_perfusion_index | Heart | health-connect-unavailable | peripheral_perfusion_index | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| high_heart_rate_event | Heart | health-connect-unavailable | high_heart_rate_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| low_heart_rate_event | Heart | health-connect-unavailable | low_heart_rate_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| irregular_heart_rhythm_event | Heart | health-connect-unavailable | irregular_heart_rhythm_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| low_cardio_fitness_event | Heart | health-connect-unavailable | low_cardio_fitness_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| hypertension_event | Heart | health-connect-unavailable | hypertension_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| electrocardiograms | Heart | health-connect-unavailable | electrocardiograms | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| heartbeat_series | Heart | health-connect-unavailable | heartbeat_series | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| respiratory_rate | Respiratory | supported | respiratory_rate | Exact persisted id. |
| blood_oxygen | Respiratory | supported | blood_oxygen | Exact persisted id. |
| forced_vital_capacity | Respiratory | health-connect-unavailable | forced_vital_capacity | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| fev1 | Respiratory | health-connect-unavailable | fev1 | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| peak_expiratory_flow | Respiratory | health-connect-unavailable | peak_expiratory_flow | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| inhaler_usage | Respiratory | health-connect-unavailable | inhaler_usage | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| sleeping_breathing_disturbances | Respiratory | health-connect-unavailable | sleeping_breathing_disturbances | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| sleep_apnea_event | Respiratory | health-connect-unavailable | sleep_apnea_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| body_temperature | Vitals | mapped/alias | body_temp | Explicit shared-registry mapping; native selectors remain platform-owned. |
| basal_body_temperature | Vitals | mapped/alias | basal_body_temp | Explicit shared-registry mapping; native selectors remain platform-owned. |
| wrist_temperature | Vitals | health-connect-unavailable | wrist_temperature | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| blood_pressure_systolic | Vitals | mapped/alias | bp_systolic | Explicit shared-registry mapping; native selectors remain platform-owned. |
| blood_pressure_diastolic | Vitals | mapped/alias | bp_diastolic | Explicit shared-registry mapping; native selectors remain platform-owned. |
| blood_glucose | Vitals | supported | blood_glucose | Exact persisted id. |
| electrodermal_activity | Vitals | health-connect-unavailable | electrodermal_activity | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| weight | Body Measurements | supported | weight | Exact persisted id. |
| height | Body Measurements | supported | height | Exact persisted id. |
| bmi | Body Measurements | supported | bmi | Exact persisted id. |
| body_fat | Body Measurements | supported | body_fat | Exact persisted id. |
| lean_body_mass | Body Measurements | mapped/alias | lean_mass | Explicit shared-registry mapping; native selectors remain platform-owned. |
| waist_circumference | Body Measurements | health-connect-unavailable | waist_circumference | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| date_of_birth | Body Measurements | health-connect-unavailable | date_of_birth | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| biological_sex | Body Measurements | health-connect-unavailable | biological_sex | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| blood_type | Body Measurements | health-connect-unavailable | blood_type | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| fitzpatrick_skin_type | Body Measurements | health-connect-unavailable | fitzpatrick_skin_type | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| wheelchair_use | Body Measurements | health-connect-unavailable | wheelchair_use | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| walking_speed | Mobility | supported | walking_speed | Exact persisted id. |
| walking_step_length | Mobility | health-connect-unavailable | walking_step_length | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| walking_double_support | Mobility | health-connect-unavailable | walking_double_support | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| walking_asymmetry | Mobility | health-connect-unavailable | walking_asymmetry | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| walking_steadiness | Mobility | health-connect-unavailable | walking_steadiness | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| stair_ascent_speed | Mobility | health-connect-unavailable | stair_ascent_speed | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| stair_descent_speed | Mobility | health-connect-unavailable | stair_descent_speed | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| six_minute_walk | Mobility | health-connect-unavailable | six_minute_walk | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| running_speed | Mobility | supported | running_speed | Exact persisted id. |
| running_stride_length | Mobility | health-connect-unavailable | running_stride_length | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| running_ground_contact | Mobility | health-connect-unavailable | running_ground_contact | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| running_vertical_oscillation | Mobility | health-connect-unavailable | running_vertical_oscillation | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| running_power | Mobility | supported | running_power | Exact persisted id. |
| walking_steadiness_event | Mobility | health-connect-unavailable | walking_steadiness_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| cycling_distance | Cycling | supported | cycling_distance | Exact persisted id. |
| cycling_speed | Cycling | mapped/alias | workouts | Explicit shared-registry mapping; native selectors remain platform-owned. |
| cycling_power | Cycling | mapped/alias | power_avg | Explicit shared-registry mapping; native selectors remain platform-owned. |
| cycling_cadence | Cycling | supported | cycling_cadence | Exact persisted id. |
| cycling_ftp | Cycling | health-connect-unavailable | cycling_ftp | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| dietary_energy | Nutrition | supported | dietary_energy | Exact persisted id. |
| dietary_protein | Nutrition | mapped/alias | protein | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_carbs | Nutrition | mapped/alias | carbs | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_fat | Nutrition | mapped/alias | fat | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_fat_saturated | Nutrition | mapped/alias | saturated_fat | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_fat_mono | Nutrition | mapped/alias | monounsaturated_fat | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_fat_poly | Nutrition | mapped/alias | polyunsaturated_fat | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_cholesterol | Nutrition | mapped/alias | cholesterol | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_fiber | Nutrition | mapped/alias | fiber | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_sugar | Nutrition | mapped/alias | sugar | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_sodium | Nutrition | mapped/alias | sodium | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_water | Nutrition | mapped/alias | water | Explicit shared-registry mapping; native selectors remain platform-owned. |
| dietary_caffeine | Nutrition | mapped/alias | caffeine | Explicit shared-registry mapping; native selectors remain platform-owned. |
| vitamin_a | Vitamins | supported | vitamin_a | Exact persisted id. |
| vitamin_b6 | Vitamins | supported | vitamin_b6 | Exact persisted id. |
| vitamin_b12 | Vitamins | supported | vitamin_b12 | Exact persisted id. |
| vitamin_c | Vitamins | supported | vitamin_c | Exact persisted id. |
| vitamin_d | Vitamins | supported | vitamin_d | Exact persisted id. |
| vitamin_e | Vitamins | supported | vitamin_e | Exact persisted id. |
| vitamin_k | Vitamins | supported | vitamin_k | Exact persisted id. |
| thiamin | Vitamins | supported | thiamin | Exact persisted id. |
| riboflavin | Vitamins | supported | riboflavin | Exact persisted id. |
| niacin | Vitamins | supported | niacin | Exact persisted id. |
| folate | Vitamins | supported | folate | Exact persisted id. |
| biotin | Vitamins | supported | biotin | Exact persisted id. |
| pantothenic_acid | Vitamins | supported | pantothenic_acid | Exact persisted id. |
| calcium | Minerals | supported | calcium | Exact persisted id. |
| iron | Minerals | supported | iron | Exact persisted id. |
| potassium | Minerals | supported | potassium | Exact persisted id. |
| magnesium | Minerals | supported | magnesium | Exact persisted id. |
| phosphorus | Minerals | supported | phosphorus | Exact persisted id. |
| zinc | Minerals | supported | zinc | Exact persisted id. |
| selenium | Minerals | supported | selenium | Exact persisted id. |
| copper | Minerals | supported | copper | Exact persisted id. |
| manganese | Minerals | supported | manganese | Exact persisted id. |
| chromium | Minerals | supported | chromium | Exact persisted id. |
| molybdenum | Minerals | supported | molybdenum | Exact persisted id. |
| chloride | Minerals | supported | chloride | Exact persisted id. |
| iodine | Minerals | supported | iodine | Exact persisted id. |
| headphone_audio | Hearing | health-connect-unavailable | headphone_audio | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| environmental_audio | Hearing | health-connect-unavailable | environmental_audio | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| environmental_sound_reduction | Hearing | health-connect-unavailable | environmental_sound_reduction | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| environmental_audio_exposure_event | Hearing | health-connect-unavailable | environmental_audio_exposure_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| headphone_audio_exposure_event | Hearing | health-connect-unavailable | headphone_audio_exposure_event | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| audiograms | Hearing | health-connect-unavailable | audiograms | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| mindful_minutes | Mindfulness | supported | mindful_minutes | Exact persisted id. |
| mindful_sessions | Mindfulness | supported | mindful_sessions | Exact persisted id. |
| state_of_mind_entries | Mindfulness | health-connect-unavailable | state_of_mind_entries | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| daily_mood | Mindfulness | health-connect-unavailable | daily_mood | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| average_valence | Mindfulness | health-connect-unavailable | average_valence | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| momentary_emotions | Mindfulness | health-connect-unavailable | momentary_emotions | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| gad7_assessments | Mindfulness | health-connect-unavailable | gad7_assessments | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| phq9_assessments | Mindfulness | health-connect-unavailable | phq9_assessments | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| menstrual_flow | Reproductive Health | supported | menstrual_flow | Exact persisted id. |
| sexual_activity | Reproductive Health | supported | sexual_activity | Exact persisted id. |
| ovulation_test | Reproductive Health | supported | ovulation_test | Exact persisted id. |
| cervical_mucus | Reproductive Health | supported | cervical_mucus | Exact persisted id. |
| intermenstrual_bleeding | Reproductive Health | supported | intermenstrual_bleeding | Exact persisted id. |
| bleeding_after_pregnancy | Reproductive Health | health-connect-unavailable | bleeding_after_pregnancy | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| bleeding_during_pregnancy | Reproductive Health | health-connect-unavailable | bleeding_during_pregnancy | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| contraceptive | Reproductive Health | health-connect-unavailable | contraceptive | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| infrequent_menstrual_cycles | Reproductive Health | health-connect-unavailable | infrequent_menstrual_cycles | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| irregular_menstrual_cycles | Reproductive Health | health-connect-unavailable | irregular_menstrual_cycles | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| lactation | Reproductive Health | health-connect-unavailable | lactation | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| persistent_intermenstrual_bleeding | Reproductive Health | health-connect-unavailable | persistent_intermenstrual_bleeding | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| pregnancy | Reproductive Health | health-connect-unavailable | pregnancy | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| pregnancy_test_result | Reproductive Health | health-connect-unavailable | pregnancy_test_result | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| progesterone_test_result | Reproductive Health | health-connect-unavailable | progesterone_test_result | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| prolonged_menstrual_periods | Reproductive Health | health-connect-unavailable | prolonged_menstrual_periods | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| symptom_headache | Symptoms | health-connect-unavailable | symptom_headache | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_fatigue | Symptoms | health-connect-unavailable | symptom_fatigue | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_nausea | Symptoms | health-connect-unavailable | symptom_nausea | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_dizziness | Symptoms | health-connect-unavailable | symptom_dizziness | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_mood_changes | Symptoms | health-connect-unavailable | symptom_mood_changes | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_sleep_changes | Symptoms | health-connect-unavailable | symptom_sleep_changes | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_appetite_changes | Symptoms | health-connect-unavailable | symptom_appetite_changes | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_hot_flashes | Symptoms | health-connect-unavailable | symptom_hot_flashes | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_chills | Symptoms | health-connect-unavailable | symptom_chills | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_fever | Symptoms | health-connect-unavailable | symptom_fever | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_lower_back_pain | Symptoms | health-connect-unavailable | symptom_lower_back_pain | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_bloating | Symptoms | health-connect-unavailable | symptom_bloating | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_constipation | Symptoms | health-connect-unavailable | symptom_constipation | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_diarrhea | Symptoms | health-connect-unavailable | symptom_diarrhea | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_heartburn | Symptoms | health-connect-unavailable | symptom_heartburn | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_coughing | Symptoms | health-connect-unavailable | symptom_coughing | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_sore_throat | Symptoms | health-connect-unavailable | symptom_sore_throat | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_runny_nose | Symptoms | health-connect-unavailable | symptom_runny_nose | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_shortness_of_breath | Symptoms | health-connect-unavailable | symptom_shortness_of_breath | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_chest_pain | Symptoms | health-connect-unavailable | symptom_chest_pain | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_skipped_heartbeat | Symptoms | health-connect-unavailable | symptom_skipped_heartbeat | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_rapid_heartbeat | Symptoms | health-connect-unavailable | symptom_rapid_heartbeat | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_acne | Symptoms | health-connect-unavailable | symptom_acne | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_dry_skin | Symptoms | health-connect-unavailable | symptom_dry_skin | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_hair_loss | Symptoms | health-connect-unavailable | symptom_hair_loss | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_memory_lapse | Symptoms | health-connect-unavailable | symptom_memory_lapse | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_night_sweats | Symptoms | health-connect-unavailable | symptom_night_sweats | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_vomiting | Symptoms | health-connect-unavailable | symptom_vomiting | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_abdominal_cramps | Symptoms | health-connect-unavailable | symptom_abdominal_cramps | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_breast_pain | Symptoms | health-connect-unavailable | symptom_breast_pain | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_pelvic_pain | Symptoms | health-connect-unavailable | symptom_pelvic_pain | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_body_ache | Symptoms | health-connect-unavailable | symptom_body_ache | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_fainting | Symptoms | health-connect-unavailable | symptom_fainting | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_loss_of_smell | Symptoms | health-connect-unavailable | symptom_loss_of_smell | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_loss_of_taste | Symptoms | health-connect-unavailable | symptom_loss_of_taste | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_wheezing | Symptoms | health-connect-unavailable | symptom_wheezing | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_sinus_congestion | Symptoms | health-connect-unavailable | symptom_sinus_congestion | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_bladder_incontinence | Symptoms | health-connect-unavailable | symptom_bladder_incontinence | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| symptom_vaginal_dryness | Symptoms | health-connect-unavailable | symptom_vaginal_dryness | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| clinical_allergy_records | Clinical Records | health-connect-unavailable | clinical_allergy_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_note_records | Clinical Records | health-connect-unavailable | clinical_note_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_condition_records | Clinical Records | health-connect-unavailable | clinical_condition_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_coverage_records | Clinical Records | health-connect-unavailable | clinical_coverage_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_immunization_records | Clinical Records | health-connect-unavailable | clinical_immunization_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_lab_result_records | Clinical Records | health-connect-unavailable | clinical_lab_result_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_medication_records | Clinical Records | health-connect-unavailable | clinical_medication_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_procedure_records | Clinical Records | health-connect-unavailable | clinical_procedure_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| clinical_vital_sign_records | Clinical Records | health-connect-unavailable | clinical_vital_sign_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| cda_documents | Clinical Documents | health-connect-unavailable | cda_documents | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| verifiable_clinical_records | Clinical Documents | health-connect-unavailable | verifiable_clinical_records | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| vision_prescriptions | Vision | health-connect-unavailable | vision_prescriptions | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |
| medications | Medications | health-connect-unavailable | medications | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| uv_exposure | Other | health-connect-unavailable | uv_exposure | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| time_in_daylight | Other | health-connect-unavailable | time_in_daylight | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| number_of_falls | Other | health-connect-unavailable | number_of_falls | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| blood_alcohol | Other | health-connect-unavailable | blood_alcohol | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| alcoholic_beverages | Other | health-connect-unavailable | alcoholic_beverages | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| insulin_delivery | Other | health-connect-unavailable | insulin_delivery | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| toothbrushing | Other | health-connect-unavailable | toothbrushing | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| handwashing | Other | health-connect-unavailable | handwashing | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| water_temperature | Other | health-connect-unavailable | water_temperature | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| underwater_depth | Other | health-connect-unavailable | underwater_depth | Explicit unavailable decision (listed); Android does not fabricate a parity value. |
| workouts | Workouts | supported | workouts | Exact persisted id. |
| scheduled_workout_plans | Workouts | health-connect-unavailable | scheduled_workout_plans | Explicit unavailable decision (hidden); Android does not fabricate a parity value. |

## Android-only supported metrics

| Android metric id | Android category | Unit | Android status | Notes |
|---|---|---|---|---|
| total_calories | ACTIVITY | kcal | android-only | Explicitly distinct platform semantic. |
| elevation_gained | ACTIVITY | m | android-only | Explicitly distinct platform semantic. |
| activity_intensity_minutes | ACTIVITY | min | android-only | Explicitly distinct platform semantic. |
| hrv | HEART | ms | android-only | Explicitly distinct platform semantic. Related but non-equivalent to: hrv. |
| skin_temperature | VITALS | ° | android-only | Explicitly distinct platform semantic. |
| body_water_mass | BODY | kg | android-only | Explicitly distinct platform semantic. |
| bone_mass | BODY | kg | android-only | Explicitly distinct platform semantic. |
| unsaturated_fat | NUTRITION | g | android-only | Explicitly distinct platform semantic. |
| trans_fat | NUTRITION | g | android-only | Explicitly distinct platform semantic. |
| folic_acid | NUTRITION | mcg | android-only | Explicitly distinct platform semantic. |
| energy_from_fat | NUTRITION | kcal | android-only | Explicitly distinct platform semantic. |
| nutrition_meals | NUTRITION | count | android-only | Explicitly distinct platform semantic. |
| steps_cadence | MOBILITY | steps/min | android-only | Explicitly distinct platform semantic. |
| power_max | MOBILITY | W | android-only | Explicitly distinct platform semantic. Related but non-equivalent to: cycling_power. |
| menstruation_periods | REPRODUCTIVE | count | android-only | Explicitly distinct platform semantic. |
| menstruation_period_days | REPRODUCTIVE | days | android-only | Explicitly distinct platform semantic. |
| planned_workouts | WORKOUTS |  | android-only | Explicitly distinct platform semantic. |
| medical_resources | MEDICATIONS | count | android-only | Explicitly distinct platform semantic. |

## Legacy unavailable aliases

The registry preserves 102 unavailable/stale Android selection identities. Kotlin remains authoritative for their user-facing display/reason strings and shadow-checks every registry id, category, `label_key`, and `reason_key`; these identities remain non-toggleable.
