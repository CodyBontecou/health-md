//
//  HealthMetricsDictionary.swift
//  Health.md
//
//  Provides a flat [originalKey: value] dictionary for all available health metrics.
//  Used by DailyNoteInjector to pick specific metrics without re-implementing
//  the conversion logic that lives in ObsidianBasesExporter.
//

import Foundation

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
        }
        if let spo2 = vitals.bloodOxygenAvg {
            m["blood_oxygen"] = "\(Int(spo2 * 100))"
        }
        if let temp = vitals.bodyTemperatureAvg {
            m["body_temperature"] = String(format: "%.1f", converter.convertTemperature(temp))
        }
        if let sys = vitals.bloodPressureSystolicAvg {
            m["blood_pressure_systolic"] = "\(Int(sys))"
        }
        if let dia = vitals.bloodPressureDiastolicAvg {
            m["blood_pressure_diastolic"] = "\(Int(dia))"
        }
        if let gluc = vitals.bloodGlucoseAvg {
            m["blood_glucose"] = String(format: "%.1f", gluc)
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
        if let avg = mindfulness.averageValence {
            m["average_mood_valence"] = String(format: "%.2f", avg)
            let pct = Int(((avg + 1.0) / 2.0) * 100)
            m["average_mood_percent"] = "\(pct)"
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
