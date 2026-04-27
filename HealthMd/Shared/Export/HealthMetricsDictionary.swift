//
//  HealthMetricsDictionary.swift
//  Health.md
//
//  Canonical source of truth for all flat health metric key-value pairs.
//  Used by ObsidianBasesExporter and DailyNoteInjector — adding a metric here
//  automatically surfaces it in every format that consumes this dictionary.
//

import Foundation

// MARK: - Shared Metric Export Mapping

/// Canonical mapping from HealthMetrics metric IDs to exported frontmatter keys.
///
/// This is shared by both DailyNoteInjector and HealthData metric filtering so
/// export behavior stays consistent across features and platforms.
enum HealthMetricExportMapping {
    static let metricIdToFrontmatterKeys: [String: [String]] = [
        // Sleep
        "sleep_total":    ["sleep_total_hours"],
        "sleep_bedtime":  ["sleep_bedtime"],
        "sleep_wake":     ["sleep_wake"],
        "sleep_deep":     ["sleep_deep_hours"],
        "sleep_rem":      ["sleep_rem_hours"],
        "sleep_core":     ["sleep_core_hours"],
        "sleep_awake":    ["sleep_awake_hours"],
        "sleep_in_bed":   ["sleep_in_bed_hours"],

        // Activity
        "steps":                    ["steps"],
        "active_energy":            ["active_calories"],
        "basal_energy":             ["basal_calories"],
        "exercise_time":            ["exercise_minutes"],
        "stand_time":               ["stand_hours"],
        "flights_climbed":          ["flights_climbed"],
        "distance_walking_running": ["walking_running_km"],
        "distance_swimming":        ["swimming_m"],
        "swimming_strokes":         ["swimming_strokes"],
        "push_count":               ["wheelchair_pushes"],
        "vo2_max":                  ["vo2_max"],

        // Cycling
        "cycling_distance": ["cycling_km"],

        // Heart
        "resting_heart_rate": ["resting_heart_rate"],
        "walking_heart_rate": ["walking_heart_rate"],
        "heart_rate_avg":     ["average_heart_rate"],
        "heart_rate_min":     ["heart_rate_min"],
        "heart_rate_max":     ["heart_rate_max"],
        "hrv":                ["hrv_ms"],

        // Respiratory
        "respiratory_rate": ["respiratory_rate", "respiratory_rate_avg", "respiratory_rate_min", "respiratory_rate_max"],
        "blood_oxygen":     ["blood_oxygen", "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max"],

        // Vitals
        "body_temperature": ["body_temperature", "body_temperature_avg", "body_temperature_min", "body_temperature_max"],
        "blood_pressure_systolic": ["blood_pressure_systolic", "blood_pressure_systolic_avg", "blood_pressure_systolic_min", "blood_pressure_systolic_max"],
        "blood_pressure_diastolic": ["blood_pressure_diastolic", "blood_pressure_diastolic_avg", "blood_pressure_diastolic_min", "blood_pressure_diastolic_max"],
        "blood_glucose": ["blood_glucose", "blood_glucose_avg", "blood_glucose_min", "blood_glucose_max"],

        // Body Measurements
        "weight":              ["weight_kg"],
        "height":              ["height_m"],
        "bmi":                 ["bmi"],
        "body_fat":            ["body_fat_percent"],
        "lean_body_mass":      ["lean_body_mass_kg"],
        "waist_circumference": ["waist_circumference_cm"],

        // Nutrition
        "dietary_energy":        ["dietary_calories"],
        "dietary_protein":       ["protein_g"],
        "dietary_carbs":         ["carbohydrates_g"],
        "dietary_fat":           ["fat_g"],
        "dietary_fat_saturated": ["saturated_fat_g"],
        "dietary_fiber":         ["fiber_g"],
        "dietary_sugar":         ["sugar_g"],
        "dietary_sodium":        ["sodium_mg"],
        "dietary_cholesterol":   ["cholesterol_mg"],
        "dietary_water":         ["water_l"],
        "dietary_caffeine":      ["caffeine_mg"],

        // Mindfulness
        "mindful_minutes":    ["mindful_minutes"],
        "mindful_sessions":   ["mindful_sessions"],
        "daily_mood":         ["daily_mood_count", "daily_mood_percent"],
        "momentary_emotions": ["momentary_emotion_count"],
        "average_valence":    ["average_mood_valence", "average_mood_percent"],

        // Mobility
        "walking_speed":          ["walking_speed"],
        "walking_step_length":    ["step_length_cm"],
        "walking_double_support": ["double_support_percent"],
        "walking_asymmetry":      ["walking_asymmetry_percent"],
        "stair_ascent_speed":     ["stair_ascent_speed"],
        "stair_descent_speed":    ["stair_descent_speed"],
        "six_minute_walk":        ["six_min_walk_m"],

        // Hearing
        "headphone_audio":    ["headphone_audio_db"],
        "environmental_audio": ["environmental_sound_db"],

        // Reproductive Health
        "menstrual_flow":          ["menstrual_flow"],
        "sexual_activity":         ["sexual_activity"],
        "ovulation_test":          ["ovulation_test"],
        "cervical_mucus":          ["cervical_mucus"],
        "intermenstrual_bleeding": ["intermenstrual_bleeding"],

        // Additional Activity
        "distance_wheelchair":      ["wheelchair_km"],
        "distance_downhill_snow":   ["downhill_snow_km"],
        "move_time":                ["move_minutes"],
        "physical_effort":          ["physical_effort"],

        // Additional Heart
        "heart_rate_recovery": ["heart_rate_recovery"],
        "afib_burden":         ["afib_burden_percent"],

        // Additional Vitals / Respiratory
        "basal_body_temperature":  ["basal_body_temperature"],
        "wrist_temperature":       ["wrist_temperature"],
        "electrodermal_activity":  ["electrodermal_activity"],
        "forced_vital_capacity":   ["forced_vital_capacity_l"],
        "fev1":                    ["fev1_l"],
        "peak_expiratory_flow":    ["peak_expiratory_flow"],
        "inhaler_usage":           ["inhaler_usage"],

        // Additional Nutrition
        "dietary_fat_mono": ["monounsaturated_fat_g"],
        "dietary_fat_poly": ["polyunsaturated_fat_g"],

        // Additional Mobility
        "walking_steadiness":            ["walking_steadiness_percent"],
        "running_speed":                 ["running_speed"],
        "running_stride_length":         ["running_stride_length_m"],
        "running_ground_contact":        ["running_ground_contact_ms"],
        "running_vertical_oscillation":  ["running_vertical_oscillation_cm"],
        "running_power":                 ["running_power_w"],

        // Cycling Performance
        "cycling_speed":    ["cycling_speed"],
        "cycling_power":    ["cycling_power_w"],
        "cycling_cadence":  ["cycling_cadence_rpm"],
        "cycling_ftp":      ["cycling_ftp_w"],

        // Vitamins
        "vitamin_a":        ["vitamin_a_ug"],
        "vitamin_b6":       ["vitamin_b6_mg"],
        "vitamin_b12":      ["vitamin_b12_ug"],
        "vitamin_c":        ["vitamin_c_mg"],
        "vitamin_d":        ["vitamin_d_ug"],
        "vitamin_e":        ["vitamin_e_mg"],
        "vitamin_k":        ["vitamin_k_ug"],
        "thiamin":          ["thiamin_mg"],
        "riboflavin":       ["riboflavin_mg"],
        "niacin":           ["niacin_mg"],
        "folate":           ["folate_ug"],
        "biotin":           ["biotin_ug"],
        "pantothenic_acid": ["pantothenic_acid_mg"],

        // Minerals
        "calcium":    ["calcium_mg"],
        "iron":       ["iron_mg"],
        "potassium":  ["potassium_mg"],
        "magnesium":  ["magnesium_mg"],
        "phosphorus": ["phosphorus_mg"],
        "zinc":       ["zinc_mg"],
        "selenium":   ["selenium_ug"],
        "copper":     ["copper_mg"],
        "manganese":  ["manganese_mg"],
        "chromium":   ["chromium_ug"],
        "molybdenum": ["molybdenum_ug"],
        "chloride":   ["chloride_mg"],
        "iodine":     ["iodine_ug"],

        // Symptoms (each maps to its own key)
        "symptom_headache":             ["symptom_headache"],
        "symptom_fatigue":              ["symptom_fatigue"],
        "symptom_nausea":               ["symptom_nausea"],
        "symptom_dizziness":            ["symptom_dizziness"],
        "symptom_mood_changes":         ["symptom_mood_changes"],
        "symptom_sleep_changes":        ["symptom_sleep_changes"],
        "symptom_appetite_changes":     ["symptom_appetite_changes"],
        "symptom_hot_flashes":          ["symptom_hot_flashes"],
        "symptom_chills":               ["symptom_chills"],
        "symptom_fever":                ["symptom_fever"],
        "symptom_lower_back_pain":      ["symptom_lower_back_pain"],
        "symptom_bloating":             ["symptom_bloating"],
        "symptom_constipation":         ["symptom_constipation"],
        "symptom_diarrhea":             ["symptom_diarrhea"],
        "symptom_heartburn":            ["symptom_heartburn"],
        "symptom_coughing":             ["symptom_coughing"],
        "symptom_sore_throat":          ["symptom_sore_throat"],
        "symptom_runny_nose":           ["symptom_runny_nose"],
        "symptom_shortness_of_breath":  ["symptom_shortness_of_breath"],
        "symptom_chest_pain":           ["symptom_chest_pain"],
        "symptom_skipped_heartbeat":    ["symptom_skipped_heartbeat"],
        "symptom_rapid_heartbeat":      ["symptom_rapid_heartbeat"],
        "symptom_acne":                 ["symptom_acne"],
        "symptom_dry_skin":             ["symptom_dry_skin"],
        "symptom_hair_loss":            ["symptom_hair_loss"],
        "symptom_memory_lapse":         ["symptom_memory_lapse"],
        "symptom_night_sweats":         ["symptom_night_sweats"],
        "symptom_vomiting":             ["symptom_vomiting"],
        "symptom_abdominal_cramps":     ["symptom_abdominal_cramps"],
        "symptom_breast_pain":          ["symptom_breast_pain"],
        "symptom_pelvic_pain":          ["symptom_pelvic_pain"],
        "symptom_body_ache":            ["symptom_body_ache"],
        "symptom_fainting":             ["symptom_fainting"],
        "symptom_loss_of_smell":        ["symptom_loss_of_smell"],
        "symptom_loss_of_taste":        ["symptom_loss_of_taste"],
        "symptom_wheezing":             ["symptom_wheezing"],
        "symptom_sinus_congestion":     ["symptom_sinus_congestion"],
        "symptom_bladder_incontinence": ["symptom_bladder_incontinence"],
        "symptom_vaginal_dryness":      ["symptom_vaginal_dryness"],

        // Other
        "uv_exposure":          ["uv_exposure"],
        "time_in_daylight":     ["time_in_daylight_min"],
        "number_of_falls":      ["number_of_falls"],
        "blood_alcohol":        ["blood_alcohol_percent"],
        "alcoholic_beverages":  ["alcoholic_beverages"],
        "insulin_delivery":     ["insulin_delivery_iu"],
        "toothbrushing":        ["toothbrushing"],
        "handwashing":          ["handwashing"],
        "water_temperature":    ["water_temperature"],
        "underwater_depth":     ["underwater_depth_m"],

        // Workouts
        "workouts": [
            "workout_count", "workout_minutes", "workout_calories", "workout_distance_km", "workouts",
            "workout_avg_heart_rate", "workout_max_heart_rate", "workout_min_heart_rate",
            "workout_running_cadence", "workout_running_stride_length",
            "workout_running_ground_contact", "workout_running_vertical_oscillation",
            "workout_cycling_cadence",
            "workout_avg_power", "workout_max_power"
        ],
    ]

    static let allKnownFrontmatterKeys: Set<String> = Set(
        metricIdToFrontmatterKeys.values.flatMap { $0 }
    )

    static func frontmatterKeys(for metricId: String) -> [String] {
        metricIdToFrontmatterKeys[metricId] ?? []
    }

    static func frontmatterKeys(enabledIn metricSelection: MetricSelectionState) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()

        var orderedMetricIds = HealthMetrics.all.map(\.id)
        let extraEnabledMetricIds = metricSelection.enabledMetrics
            .subtracting(Set(orderedMetricIds))
            .sorted()
        orderedMetricIds.append(contentsOf: extraEnabledMetricIds)

        for metricId in orderedMetricIds {
            guard metricSelection.isMetricEnabled(metricId) else { continue }
            for key in frontmatterKeys(for: metricId) where !seen.contains(key) {
                keys.append(key)
                seen.insert(key)
            }
        }

        return keys
    }

    static func enabledFrontmatterKeySet(in metricSelection: MetricSelectionState) -> Set<String> {
        Set(frontmatterKeys(enabledIn: metricSelection))
    }
}

struct ExportMindfulnessDerivation {
    let entries: [StateOfMindEntry]
    let dailyMoods: [StateOfMindEntry]
    let momentaryEmotions: [StateOfMindEntry]
    let averageValence: Double?
    let averageValencePercent: Int?
    let averageDailyMoodValence: Double?
    let labels: [String]
    let associations: [String]
}

enum ExportFrontmatterMetricBuilder {
    static func deriveMindfulness(from mindfulness: MindfulnessData) -> ExportMindfulnessDerivation {
        let entries = mindfulness.stateOfMind
        let dailyMoods = entries.filter { $0.kind == .dailyMood }
        let momentaryEmotions = entries.filter { $0.kind == .momentaryEmotion }

        let averageValence: Double?
        if mindfulness.isAverageValenceExportEnabled, !entries.isEmpty {
            averageValence = entries.reduce(0.0) { $0 + $1.valence } / Double(entries.count)
        } else {
            averageValence = nil
        }

        let averageValencePercent = averageValence.map { Int((($0 + 1.0) / 2.0) * 100) }

        let averageDailyMoodValence: Double?
        if !dailyMoods.isEmpty {
            averageDailyMoodValence = dailyMoods.reduce(0.0) { $0 + $1.valence } / Double(dailyMoods.count)
        } else {
            averageDailyMoodValence = nil
        }

        return .init(
            entries: entries,
            dailyMoods: dailyMoods,
            momentaryEmotions: momentaryEmotions,
            averageValence: averageValence,
            averageValencePercent: averageValencePercent,
            averageDailyMoodValence: averageDailyMoodValence,
            labels: Array(Set(entries.flatMap { $0.labels })).sorted(),
            associations: Array(Set(entries.flatMap { $0.associations })).sorted()
        )
    }

    static func build(
        from healthData: HealthData,
        converter: UnitConverter,
        timeFormat: TimeFormatPreference,
        mindfulness: ExportMindfulnessDerivation? = nil
    ) -> [String: String] {
        let sleep = healthData.sleep
        let activity = healthData.activity
        let heart = healthData.heart
        let vitals = healthData.vitals
        let body = healthData.body
        let nutrition = healthData.nutrition
        let rawMindfulness = healthData.mindfulness
        let mobility = healthData.mobility
        let hearing = healthData.hearing
        let workouts = healthData.workouts

        let derivedMindfulness = mindfulness ?? deriveMindfulness(from: rawMindfulness)

        var m: [String: String] = [:]

        // MARK: Sleep
        if sleep.totalDuration > 0 {
            m["sleep_total_hours"] = String(format: "%.2f", sleep.totalDuration / 3600)
        }
        if let bedtime = sleep.sessionStart {
            m["sleep_bedtime"] = timeFormat.format(date: bedtime)
        }
        if let wake = sleep.sessionEnd {
            m["sleep_wake"] = timeFormat.format(date: wake)
        }
        if sleep.deepSleep > 0 {
            m["sleep_deep_hours"] = String(format: "%.2f", sleep.deepSleep / 3600)
        }
        if sleep.remSleep > 0 {
            m["sleep_rem_hours"] = String(format: "%.2f", sleep.remSleep / 3600)
        }
        if sleep.coreSleep > 0 {
            m["sleep_core_hours"] = String(format: "%.2f", sleep.coreSleep / 3600)
        }
        if sleep.awakeTime > 0 {
            m["sleep_awake_hours"] = String(format: "%.2f", sleep.awakeTime / 3600)
        }
        if sleep.inBedTime > 0 {
            m["sleep_in_bed_hours"] = String(format: "%.2f", sleep.inBedTime / 3600)
        }

        // MARK: Activity
        if let steps = activity.steps {
            m["steps"] = "\(steps)"
        }
        if let cal = activity.activeCalories {
            m["active_calories"] = "\(Int(cal))"
        }
        if let basal = activity.basalEnergyBurned {
            m["basal_calories"] = "\(Int(basal))"
        }
        if let ex = activity.exerciseMinutes {
            m["exercise_minutes"] = "\(Int(ex))"
        }
        if let stand = activity.standHours {
            m["stand_hours"] = "\(stand)"
        }
        if let flights = activity.flightsClimbed {
            m["flights_climbed"] = "\(flights)"
        }
        if let dist = activity.walkingRunningDistance {
            m["walking_running_km"] = String(format: "%.2f", converter.convertDistance(dist))
        }
        if let cyc = activity.cyclingDistance {
            m["cycling_km"] = String(format: "%.2f", converter.convertDistance(cyc))
        }
        if let swim = activity.swimmingDistance {
            m["swimming_m"] = "\(Int(swim))"
        }
        if let strokes = activity.swimmingStrokes {
            m["swimming_strokes"] = "\(strokes)"
        }
        if let pushes = activity.pushCount {
            m["wheelchair_pushes"] = "\(pushes)"
        }
        if let vo2 = activity.vo2Max {
            m["vo2_max"] = String(format: "%.1f", vo2)
        }
        if let wc = activity.wheelchairDistance {
            m["wheelchair_km"] = String(format: "%.2f", converter.convertDistance(wc))
        }
        if let snow = activity.downhillSnowSportsDistance {
            m["downhill_snow_km"] = String(format: "%.2f", converter.convertDistance(snow))
        }
        if let mt = activity.moveTime {
            m["move_minutes"] = "\(Int(mt))"
        }
        if let pe = activity.physicalEffort {
            m["physical_effort"] = String(format: "%.1f", pe)
        }

        // MARK: Heart
        if let hr = heart.restingHeartRate {
            m["resting_heart_rate"] = "\(Int(hr))"
        }
        if let whr = heart.walkingHeartRateAverage {
            m["walking_heart_rate"] = "\(Int(whr))"
        }
        if let avg = heart.averageHeartRate {
            m["average_heart_rate"] = "\(Int(avg))"
        }
        if let minHR = heart.heartRateMin {
            m["heart_rate_min"] = "\(Int(minHR))"
        }
        if let maxHR = heart.heartRateMax {
            m["heart_rate_max"] = "\(Int(maxHR))"
        }
        if let hrv = heart.hrv {
            m["hrv_ms"] = String(format: "%.1f", hrv)
        }
        if let hrr = heart.heartRateRecovery {
            m["heart_rate_recovery"] = "\(Int(hrr))"
        }
        if let afib = heart.atrialFibrillationBurden {
            m["afib_burden_percent"] = String(format: "%.1f", afib * 100)
        }

        // MARK: Vitals
        if let rr = vitals.respiratoryRateAvg {
            m["respiratory_rate"] = String(format: "%.1f", rr)
            m["respiratory_rate_avg"] = String(format: "%.1f", rr)
        }
        if let rrMin = vitals.respiratoryRateMin {
            m["respiratory_rate_min"] = String(format: "%.1f", rrMin)
        }
        if let rrMax = vitals.respiratoryRateMax {
            m["respiratory_rate_max"] = String(format: "%.1f", rrMax)
        }
        if let spo2 = vitals.bloodOxygenAvg {
            m["blood_oxygen"] = "\(Int(spo2 * 100))"
            m["blood_oxygen_avg"] = "\(Int(spo2 * 100))"
        }
        if let spo2Min = vitals.bloodOxygenMin {
            m["blood_oxygen_min"] = "\(Int(spo2Min * 100))"
        }
        if let spo2Max = vitals.bloodOxygenMax {
            m["blood_oxygen_max"] = "\(Int(spo2Max * 100))"
        }
        if let temp = vitals.bodyTemperatureAvg {
            let converted = converter.convertTemperature(temp)
            m["body_temperature"] = String(format: "%.1f", converted)
            m["body_temperature_avg"] = String(format: "%.1f", converted)
        }
        if let tempMin = vitals.bodyTemperatureMin {
            m["body_temperature_min"] = String(format: "%.1f", converter.convertTemperature(tempMin))
        }
        if let tempMax = vitals.bodyTemperatureMax {
            m["body_temperature_max"] = String(format: "%.1f", converter.convertTemperature(tempMax))
        }
        if let sys = vitals.bloodPressureSystolicAvg {
            m["blood_pressure_systolic"] = "\(Int(sys))"
            m["blood_pressure_systolic_avg"] = "\(Int(sys))"
        }
        if let sysMin = vitals.bloodPressureSystolicMin {
            m["blood_pressure_systolic_min"] = "\(Int(sysMin))"
        }
        if let sysMax = vitals.bloodPressureSystolicMax {
            m["blood_pressure_systolic_max"] = "\(Int(sysMax))"
        }
        if let dia = vitals.bloodPressureDiastolicAvg {
            m["blood_pressure_diastolic"] = "\(Int(dia))"
            m["blood_pressure_diastolic_avg"] = "\(Int(dia))"
        }
        if let diaMin = vitals.bloodPressureDiastolicMin {
            m["blood_pressure_diastolic_min"] = "\(Int(diaMin))"
        }
        if let diaMax = vitals.bloodPressureDiastolicMax {
            m["blood_pressure_diastolic_max"] = "\(Int(diaMax))"
        }
        if let gluc = vitals.bloodGlucoseAvg {
            m["blood_glucose"] = String(format: "%.1f", gluc)
            m["blood_glucose_avg"] = String(format: "%.1f", gluc)
        }
        if let glucMin = vitals.bloodGlucoseMin {
            m["blood_glucose_min"] = String(format: "%.1f", glucMin)
        }
        if let glucMax = vitals.bloodGlucoseMax {
            m["blood_glucose_max"] = String(format: "%.1f", glucMax)
        }
        if let bbt = vitals.basalBodyTemperature {
            m["basal_body_temperature"] = String(format: "%.1f", converter.convertTemperature(bbt))
        }
        if let wt = vitals.wristTemperature {
            m["wrist_temperature"] = String(format: "%.2f", wt)
        }
        if let eda = vitals.electrodermalActivity {
            m["electrodermal_activity"] = String(format: "%.2f", eda)
        }
        if let fvc = vitals.forcedVitalCapacity {
            m["forced_vital_capacity_l"] = String(format: "%.2f", fvc)
        }
        if let fev1 = vitals.forcedExpiratoryVolume1 {
            m["fev1_l"] = String(format: "%.2f", fev1)
        }
        if let pef = vitals.peakExpiratoryFlowRate {
            m["peak_expiratory_flow"] = String(format: "%.1f", pef)
        }
        if let inhaler = vitals.inhalerUsage {
            m["inhaler_usage"] = "\(Int(inhaler))"
        }

        // MARK: Body
        if let weight = body.weight {
            m["weight_kg"] = String(format: "%.1f", converter.convertWeight(weight))
        }
        if let height = body.height {
            m["height_m"] = String(format: "%.2f", converter.convertHeight(height))
        }
        if let bmi = body.bmi {
            m["bmi"] = String(format: "%.1f", bmi)
        }
        if let fat = body.bodyFatPercentage {
            m["body_fat_percent"] = String(format: "%.1f", fat * 100)
        }
        if let lean = body.leanBodyMass {
            m["lean_body_mass_kg"] = String(format: "%.1f", converter.convertWeight(lean))
        }
        if let waist = body.waistCircumference {
            m["waist_circumference_cm"] = converter.formatLength(waist)
        }

        // MARK: Nutrition
        if let energy = nutrition.dietaryEnergy {
            m["dietary_calories"] = "\(Int(energy))"
        }
        if let protein = nutrition.protein {
            m["protein_g"] = String(format: "%.1f", protein)
        }
        if let carbs = nutrition.carbohydrates {
            m["carbohydrates_g"] = String(format: "%.1f", carbs)
        }
        if let fat = nutrition.fat {
            m["fat_g"] = String(format: "%.1f", fat)
        }
        if let satFat = nutrition.saturatedFat {
            m["saturated_fat_g"] = String(format: "%.1f", satFat)
        }
        if let fiber = nutrition.fiber {
            m["fiber_g"] = String(format: "%.1f", fiber)
        }
        if let sugar = nutrition.sugar {
            m["sugar_g"] = String(format: "%.1f", sugar)
        }
        if let sodium = nutrition.sodium {
            m["sodium_mg"] = "\(Int(sodium))"
        }
        if let chol = nutrition.cholesterol {
            m["cholesterol_mg"] = String(format: "%.1f", chol)
        }
        if let water = nutrition.water {
            m["water_l"] = String(format: "%.2f", converter.convertVolume(water))
        }
        if let caff = nutrition.caffeine {
            m["caffeine_mg"] = String(format: "%.1f", caff)
        }
        if let mono = nutrition.monounsaturatedFat {
            m["monounsaturated_fat_g"] = String(format: "%.1f", mono)
        }
        if let poly = nutrition.polyunsaturatedFat {
            m["polyunsaturated_fat_g"] = String(format: "%.1f", poly)
        }

        // MARK: Mindfulness
        if let minutes = rawMindfulness.mindfulMinutes {
            m["mindful_minutes"] = "\(Int(minutes))"
        }
        if let sessions = rawMindfulness.mindfulSessions {
            m["mindful_sessions"] = "\(sessions)"
        }
        if !derivedMindfulness.entries.isEmpty {
            m["mood_entries"] = "\(derivedMindfulness.entries.count)"

            if let avg = derivedMindfulness.averageValence {
                m["average_mood_valence"] = String(format: "%.2f", avg)
                if let pct = derivedMindfulness.averageValencePercent {
                    m["average_mood_percent"] = "\(pct)"
                }
            }

            if !derivedMindfulness.dailyMoods.isEmpty {
                m["daily_mood_count"] = "\(derivedMindfulness.dailyMoods.count)"
                if let avgDaily = derivedMindfulness.averageDailyMoodValence {
                    let dailyPct = Int(((avgDaily + 1.0) / 2.0) * 100)
                    m["daily_mood_percent"] = "\(dailyPct)"
                }
            }

            if !derivedMindfulness.momentaryEmotions.isEmpty {
                m["momentary_emotion_count"] = "\(derivedMindfulness.momentaryEmotions.count)"
            }

            if !derivedMindfulness.labels.isEmpty {
                let tags = derivedMindfulness.labels.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
                m["mood_labels"] = "[\(tags.joined(separator: ", "))]"
            }

            if !derivedMindfulness.associations.isEmpty {
                let tags = derivedMindfulness.associations.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
                m["mood_associations"] = "[\(tags.joined(separator: ", "))]"
            }
        }

        // MARK: Mobility
        if let speed = mobility.walkingSpeed {
            m["walking_speed"] = String(format: "%.2f", speed)
        }
        if let step = mobility.walkingStepLength {
            m["step_length_cm"] = String(format: "%.1f", step * 100)
        }
        if let ds = mobility.walkingDoubleSupportPercentage {
            m["double_support_percent"] = String(format: "%.1f", ds * 100)
        }
        if let asym = mobility.walkingAsymmetryPercentage {
            m["walking_asymmetry_percent"] = String(format: "%.1f", asym * 100)
        }
        if let asc = mobility.stairAscentSpeed {
            m["stair_ascent_speed"] = String(format: "%.2f", asc)
        }
        if let desc = mobility.stairDescentSpeed {
            m["stair_descent_speed"] = String(format: "%.2f", desc)
        }
        if let sixMin = mobility.sixMinuteWalkDistance {
            m["six_min_walk_m"] = "\(Int(sixMin))"
        }
        if let ws = mobility.walkingSteadiness {
            m["walking_steadiness_percent"] = String(format: "%.1f", ws * 100)
        }
        if let rs = mobility.runningSpeed {
            m["running_speed"] = String(format: "%.2f", rs)
        }
        if let rsl = mobility.runningStrideLength {
            m["running_stride_length_m"] = String(format: "%.2f", rsl)
        }
        if let rgc = mobility.runningGroundContactTime {
            m["running_ground_contact_ms"] = String(format: "%.0f", rgc)
        }
        if let rvo = mobility.runningVerticalOscillation {
            m["running_vertical_oscillation_cm"] = String(format: "%.1f", rvo)
        }
        if let rp = mobility.runningPower {
            m["running_power_w"] = String(format: "%.0f", rp)
        }

        // MARK: Hearing
        if let hp = hearing.headphoneAudioLevel {
            m["headphone_audio_db"] = String(format: "%.1f", hp)
        }
        if let env = hearing.environmentalSoundLevel {
            m["environmental_sound_db"] = String(format: "%.1f", env)
        }

        // MARK: Reproductive Health
        let reproductive = healthData.reproductiveHealth
        if let flow = reproductive.menstrualFlow {
            m["menstrual_flow"] = flow
        }
        if let count = reproductive.sexualActivityCount {
            m["sexual_activity"] = "\(count)"
        }
        if let result = reproductive.ovulationTestResult {
            m["ovulation_test"] = result
        }
        if let quality = reproductive.cervicalMucusQuality {
            m["cervical_mucus"] = quality
        }
        if let count = reproductive.intermenstrualBleedingCount {
            m["intermenstrual_bleeding"] = "\(count)"
        }

        // MARK: Cycling Performance
        let cycling = healthData.cyclingPerformance
        if let cs = cycling.cyclingSpeed {
            m["cycling_speed"] = String(format: "%.2f", cs)
        }
        if let cp = cycling.cyclingPower {
            m["cycling_power_w"] = String(format: "%.0f", cp)
        }
        if let cc = cycling.cyclingCadence {
            m["cycling_cadence_rpm"] = String(format: "%.0f", cc)
        }
        if let ftp = cycling.cyclingFTP {
            m["cycling_ftp_w"] = String(format: "%.0f", ftp)
        }

        // MARK: Vitamins
        let vit = healthData.vitamins
        if let v = vit.vitaminA { m["vitamin_a_ug"] = String(format: "%.1f", v) }
        if let v = vit.vitaminB6 { m["vitamin_b6_mg"] = String(format: "%.2f", v) }
        if let v = vit.vitaminB12 { m["vitamin_b12_ug"] = String(format: "%.2f", v) }
        if let v = vit.vitaminC { m["vitamin_c_mg"] = String(format: "%.1f", v) }
        if let v = vit.vitaminD { m["vitamin_d_ug"] = String(format: "%.1f", v) }
        if let v = vit.vitaminE { m["vitamin_e_mg"] = String(format: "%.2f", v) }
        if let v = vit.vitaminK { m["vitamin_k_ug"] = String(format: "%.1f", v) }
        if let v = vit.thiamin { m["thiamin_mg"] = String(format: "%.2f", v) }
        if let v = vit.riboflavin { m["riboflavin_mg"] = String(format: "%.2f", v) }
        if let v = vit.niacin { m["niacin_mg"] = String(format: "%.1f", v) }
        if let v = vit.folate { m["folate_ug"] = String(format: "%.1f", v) }
        if let v = vit.biotin { m["biotin_ug"] = String(format: "%.1f", v) }
        if let v = vit.pantothenicAcid { m["pantothenic_acid_mg"] = String(format: "%.2f", v) }

        // MARK: Minerals
        let min = healthData.minerals
        if let v = min.calcium { m["calcium_mg"] = String(format: "%.1f", v) }
        if let v = min.iron { m["iron_mg"] = String(format: "%.2f", v) }
        if let v = min.potassium { m["potassium_mg"] = String(format: "%.1f", v) }
        if let v = min.magnesium { m["magnesium_mg"] = String(format: "%.1f", v) }
        if let v = min.phosphorus { m["phosphorus_mg"] = String(format: "%.1f", v) }
        if let v = min.zinc { m["zinc_mg"] = String(format: "%.2f", v) }
        if let v = min.selenium { m["selenium_ug"] = String(format: "%.1f", v) }
        if let v = min.copper { m["copper_mg"] = String(format: "%.3f", v) }
        if let v = min.manganese { m["manganese_mg"] = String(format: "%.2f", v) }
        if let v = min.chromium { m["chromium_ug"] = String(format: "%.1f", v) }
        if let v = min.molybdenum { m["molybdenum_ug"] = String(format: "%.1f", v) }
        if let v = min.chloride { m["chloride_mg"] = String(format: "%.1f", v) }
        if let v = min.iodine { m["iodine_ug"] = String(format: "%.1f", v) }

        // MARK: Symptoms
        for (key, count) in healthData.symptoms.counts {
            m[key] = "\(count)"
        }

        // MARK: Other
        let otherData = healthData.other
        if let v = otherData.uvExposure { m["uv_exposure"] = String(format: "%.1f", v) }
        if let v = otherData.timeInDaylight { m["time_in_daylight_min"] = "\(Int(v))" }
        if let v = otherData.numberOfFalls { m["number_of_falls"] = "\(Int(v))" }
        if let v = otherData.bloodAlcoholContent { m["blood_alcohol_percent"] = String(format: "%.3f", v) }
        if let v = otherData.alcoholicBeverages { m["alcoholic_beverages"] = "\(Int(v))" }
        if let v = otherData.insulinDelivery { m["insulin_delivery_iu"] = String(format: "%.1f", v) }
        if let v = otherData.toothbrushingCount { m["toothbrushing"] = "\(v)" }
        if let v = otherData.handwashingCount { m["handwashing"] = "\(v)" }
        if let v = otherData.waterTemperature { m["water_temperature"] = String(format: "%.1f", converter.convertTemperature(v)) }
        if let v = otherData.underwaterDepth { m["underwater_depth_m"] = String(format: "%.1f", v) }

        // MARK: Workouts (summary)
        if !workouts.isEmpty {
            m["workout_count"] = "\(workouts.count)"
            let totalDuration = workouts.reduce(0.0) { $0 + $1.duration }
            m["workout_minutes"] = "\(Int(totalDuration / 60))"
            let totalCal = workouts.compactMap { $0.calories }.reduce(0.0, +)
            if totalCal > 0 { m["workout_calories"] = "\(Int(totalCal))" }
            let totalDist = workouts.compactMap { $0.distance }.reduce(0.0, +)
            if totalDist > 0 {
                m["workout_distance_km"] = String(format: "%.2f", converter.convertDistance(totalDist))
            }
            let types = workouts
                .map { $0.workoutTypeName.lowercased().replacingOccurrences(of: " ", with: "-") }
            let unique = Array(Set(types)).sorted()
            m["workouts"] = "[\(unique.joined(separator: ", "))]"

            // Heart rate aggregates across all workouts that have HR.
            if let avgHR = weightedAverage(pairs(workouts, value: \.avgHeartRate)) {
                m["workout_avg_heart_rate"] = "\(Int(avgHR.rounded()))"
            }
            if let maxHR = workouts.compactMap({ $0.maxHeartRate }).max() {
                m["workout_max_heart_rate"] = "\(Int(maxHR.rounded()))"
            }
            if let minHR = workouts.compactMap({ $0.minHeartRate }).min() {
                m["workout_min_heart_rate"] = "\(Int(minHR.rounded()))"
            }

            // Running form — aggregate only across running workouts.
            let runs = workouts.filter { $0.workoutType == .running }
            if let cadence = weightedAverage(pairs(runs, value: \.avgRunningCadence)) {
                m["workout_running_cadence"] = "\(Int(cadence.rounded()))"
            }
            if let stride = weightedAverage(pairs(runs, value: \.avgStrideLength)) {
                m["workout_running_stride_length"] = String(format: "%.2f", stride)
            }
            if let gct = weightedAverage(pairs(runs, value: \.avgGroundContactTime)) {
                m["workout_running_ground_contact"] = "\(Int(gct.rounded()))"
            }
            if let vertOsc = weightedAverage(pairs(runs, value: \.avgVerticalOscillation)) {
                m["workout_running_vertical_oscillation"] = String(format: "%.1f", vertOsc)
            }

            // Cycling cadence — aggregate only across cycling workouts.
            let rides = workouts.filter { $0.workoutType == .cycling }
            if let cyclingCadence = weightedAverage(pairs(rides, value: \.avgCyclingCadence)) {
                m["workout_cycling_cadence"] = "\(Int(cyclingCadence.rounded()))"
            }

            // Power — running and cycling both report watts.
            if let avgPow = weightedAverage(pairs(workouts, value: \.avgPower)) {
                m["workout_avg_power"] = "\(Int(avgPow.rounded()))"
            }
            if let maxPow = workouts.compactMap({ $0.maxPower }).max() {
                m["workout_max_power"] = "\(Int(maxPow.rounded()))"
            }
        }

        return m
    }

    /// Duration-weighted average of (value, weight) pairs. Returns nil for empty input or zero total weight.
    private static func weightedAverage(_ pairs: [(value: Double, weight: TimeInterval)]) -> Double? {
        guard !pairs.isEmpty else { return nil }
        let totalWeight = pairs.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let weightedSum = pairs.reduce(0.0) { $0 + $1.value * $1.weight }
        return weightedSum / totalWeight
    }

    /// Build (value, duration) pairs for workouts that have the keypath value set.
    private static func pairs(_ workouts: [WorkoutData], value: KeyPath<WorkoutData, Double?>) -> [(value: Double, weight: TimeInterval)] {
        workouts.compactMap { workout in
            guard let v = workout[keyPath: value] else { return nil }
            return (v, workout.duration)
        }
    }
}

extension HealthData {

    /// Returns every available health metric as a flat dictionary.
    ///
    /// - Keys:   original snake_case keys matching FrontmatterConfiguration.defaultFields
    /// - Values: formatted strings ready for YAML frontmatter
    /// - Parameter converter: unit converter respecting the user's metric/imperial preference
    /// - Parameter timeFormat: format used for timestamp fields such as sleep_bedtime / sleep_wake
    func allMetricsDictionary(using converter: UnitConverter, timeFormat: TimeFormatPreference = .hour24) -> [String: String] {
        ExportFrontmatterMetricBuilder.build(
            from: self,
            converter: converter,
            timeFormat: timeFormat
        )
    }
}
