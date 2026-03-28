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
        "basal_body_temperature": ["body_temperature", "body_temperature_avg", "body_temperature_min", "body_temperature_max"],
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

        // Workouts
        "workouts": ["workout_count", "workout_minutes", "workout_calories", "workout_distance_km", "workouts"],
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

extension HealthData {

    /// Returns every available health metric as a flat dictionary.
    ///
    /// - Keys:   original snake_case keys matching FrontmatterConfiguration.defaultFields
    /// - Values: formatted strings ready for YAML frontmatter
    /// - Parameter converter: unit converter respecting the user's metric/imperial preference
    /// - Parameter timeFormat: format used for timestamp fields such as sleep_bedtime / sleep_wake
    func allMetricsDictionary(using converter: UnitConverter, timeFormat: TimeFormatPreference = .hour24) -> [String: String] {
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

        // MARK: Mindfulness
        if let minutes = mindfulness.mindfulMinutes {
            m["mindful_minutes"] = "\(Int(minutes))"
        }
        if let sessions = mindfulness.mindfulSessions {
            m["mindful_sessions"] = "\(sessions)"
        }
        if !mindfulness.stateOfMind.isEmpty {
            m["mood_entries"] = "\(mindfulness.stateOfMind.count)"

            if let avg = mindfulness.averageValence {
                m["average_mood_valence"] = String(format: "%.2f", avg)
                let pct = Int(((avg + 1.0) / 2.0) * 100)
                m["average_mood_percent"] = "\(pct)"
            }

            if !mindfulness.dailyMoods.isEmpty {
                m["daily_mood_count"] = "\(mindfulness.dailyMoods.count)"
                if let avgDaily = mindfulness.averageDailyMoodValence {
                    let dailyPct = Int(((avgDaily + 1.0) / 2.0) * 100)
                    m["daily_mood_percent"] = "\(dailyPct)"
                }
            }

            if !mindfulness.momentaryEmotions.isEmpty {
                m["momentary_emotion_count"] = "\(mindfulness.momentaryEmotions.count)"
            }

            if !mindfulness.allLabels.isEmpty {
                let tags = mindfulness.allLabels.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
                m["mood_labels"] = "[\(tags.joined(separator: ", "))]"
            }

            if !mindfulness.allAssociations.isEmpty {
                let tags = mindfulness.allAssociations.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
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

        // MARK: Hearing
        if let hp = hearing.headphoneAudioLevel {
            m["headphone_audio_db"] = String(format: "%.1f", hp)
        }
        if let env = hearing.environmentalSoundLevel {
            m["environmental_sound_db"] = String(format: "%.1f", env)
        }

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
        }

        return m
    }
}
