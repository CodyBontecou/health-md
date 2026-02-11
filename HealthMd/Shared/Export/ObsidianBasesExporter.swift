import Foundation

// MARK: - Obsidian Bases Export

extension HealthData {
    func toObsidianBases(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let dateString = config.dateFormat.format(date: date)
        let fmConfig = config.frontmatterConfig
        let converter = config.unitConverter

        var frontmatter: [String] = []
        frontmatter.append("---")
        
        // Core fields
        if fmConfig.includeDate {
            frontmatter.append("\(fmConfig.customDateKey): \(dateString)")
        }
        if fmConfig.includeType {
            frontmatter.append("\(fmConfig.customTypeKey): \(fmConfig.customTypeValue)")
        }
        
        // Custom static fields
        for (key, value) in fmConfig.customFields.sorted(by: { $0.key < $1.key }) {
            frontmatter.append("\(key): \(value)")
        }
        
        // Helper to add a field with custom key support
        func addField(_ originalKey: String, _ value: String) {
            if let outputKey = fmConfig.outputKey(for: originalKey) {
                frontmatter.append("\(outputKey): \(value)")
            }
        }

        // Sleep metrics
        if sleep.hasData {
            if sleep.totalDuration > 0 {
                addField("sleep_total_hours", String(format: "%.2f", sleep.totalDuration / 3600))
            }
            if sleep.deepSleep > 0 {
                addField("sleep_deep_hours", String(format: "%.2f", sleep.deepSleep / 3600))
            }
            if sleep.remSleep > 0 {
                addField("sleep_rem_hours", String(format: "%.2f", sleep.remSleep / 3600))
            }
            if sleep.coreSleep > 0 {
                addField("sleep_core_hours", String(format: "%.2f", sleep.coreSleep / 3600))
            }
            if sleep.awakeTime > 0 {
                addField("sleep_awake_hours", String(format: "%.2f", sleep.awakeTime / 3600))
            }
            if sleep.inBedTime > 0 {
                addField("sleep_in_bed_hours", String(format: "%.2f", sleep.inBedTime / 3600))
            }
        }

        // Activity metrics
        if activity.hasData {
            if let steps = activity.steps {
                addField("steps", "\(steps)")
            }
            if let calories = activity.activeCalories {
                addField("active_calories", "\(Int(calories))")
            }
            if let basal = activity.basalEnergyBurned {
                addField("basal_calories", "\(Int(basal))")
            }
            if let exercise = activity.exerciseMinutes {
                addField("exercise_minutes", "\(Int(exercise))")
            }
            if let standHours = activity.standHours {
                addField("stand_hours", "\(standHours)")
            }
            if let flights = activity.flightsClimbed {
                addField("flights_climbed", "\(flights)")
            }
            if let distance = activity.walkingRunningDistance {
                let converted = converter.convertDistance(distance)
                addField("walking_running_km", String(format: "%.2f", converted))
            }
            if let cycling = activity.cyclingDistance {
                let converted = converter.convertDistance(cycling)
                addField("cycling_km", String(format: "%.2f", converted))
            }
            if let swimming = activity.swimmingDistance {
                addField("swimming_m", "\(Int(swimming))")
            }
            if let strokes = activity.swimmingStrokes {
                addField("swimming_strokes", "\(strokes)")
            }
            if let pushes = activity.pushCount {
                addField("wheelchair_pushes", "\(pushes)")
            }
        }

        // Heart metrics
        if heart.hasData {
            if let hr = heart.restingHeartRate {
                addField("resting_heart_rate", "\(Int(hr))")
            }
            if let walkingHR = heart.walkingHeartRateAverage {
                addField("walking_heart_rate", "\(Int(walkingHR))")
            }
            if let avgHR = heart.averageHeartRate {
                addField("average_heart_rate", "\(Int(avgHR))")
            }
            if let minHR = heart.heartRateMin {
                addField("heart_rate_min", "\(Int(minHR))")
            }
            if let maxHR = heart.heartRateMax {
                addField("heart_rate_max", "\(Int(maxHR))")
            }
            if let hrv = heart.hrv {
                addField("hrv_ms", String(format: "%.1f", hrv))
            }
        }

        // Vitals metrics (daily aggregates)
        if vitals.hasData {
            // Respiratory Rate
            if let rrAvg = vitals.respiratoryRateAvg {
                addField("respiratory_rate", String(format: "%.1f", rrAvg))
                addField("respiratory_rate_avg", String(format: "%.1f", rrAvg))
            }
            if let rrMin = vitals.respiratoryRateMin {
                addField("respiratory_rate_min", String(format: "%.1f", rrMin))
            }
            if let rrMax = vitals.respiratoryRateMax {
                addField("respiratory_rate_max", String(format: "%.1f", rrMax))
            }
            
            // Blood Oxygen / SpO2
            if let spo2Avg = vitals.bloodOxygenAvg {
                addField("blood_oxygen", "\(Int(spo2Avg * 100))")
                addField("blood_oxygen_avg", "\(Int(spo2Avg * 100))")
            }
            if let spo2Min = vitals.bloodOxygenMin {
                addField("blood_oxygen_min", "\(Int(spo2Min * 100))")
            }
            if let spo2Max = vitals.bloodOxygenMax {
                addField("blood_oxygen_max", "\(Int(spo2Max * 100))")
            }
            
            // Body Temperature
            if let tempAvg = vitals.bodyTemperatureAvg {
                let converted = converter.convertTemperature(tempAvg)
                addField("body_temperature", String(format: "%.1f", converted))
                addField("body_temperature_avg", String(format: "%.1f", converted))
            }
            if let tempMin = vitals.bodyTemperatureMin {
                let converted = converter.convertTemperature(tempMin)
                addField("body_temperature_min", String(format: "%.1f", converted))
            }
            if let tempMax = vitals.bodyTemperatureMax {
                let converted = converter.convertTemperature(tempMax)
                addField("body_temperature_max", String(format: "%.1f", converted))
            }
            
            // Blood Pressure Systolic
            if let systolicAvg = vitals.bloodPressureSystolicAvg {
                addField("blood_pressure_systolic", "\(Int(systolicAvg))")
                addField("blood_pressure_systolic_avg", "\(Int(systolicAvg))")
            }
            if let systolicMin = vitals.bloodPressureSystolicMin {
                addField("blood_pressure_systolic_min", "\(Int(systolicMin))")
            }
            if let systolicMax = vitals.bloodPressureSystolicMax {
                addField("blood_pressure_systolic_max", "\(Int(systolicMax))")
            }
            
            // Blood Pressure Diastolic
            if let diastolicAvg = vitals.bloodPressureDiastolicAvg {
                addField("blood_pressure_diastolic", "\(Int(diastolicAvg))")
                addField("blood_pressure_diastolic_avg", "\(Int(diastolicAvg))")
            }
            if let diastolicMin = vitals.bloodPressureDiastolicMin {
                addField("blood_pressure_diastolic_min", "\(Int(diastolicMin))")
            }
            if let diastolicMax = vitals.bloodPressureDiastolicMax {
                addField("blood_pressure_diastolic_max", "\(Int(diastolicMax))")
            }
            
            // Blood Glucose
            if let glucoseAvg = vitals.bloodGlucoseAvg {
                addField("blood_glucose", String(format: "%.1f", glucoseAvg))
                addField("blood_glucose_avg", String(format: "%.1f", glucoseAvg))
            }
            if let glucoseMin = vitals.bloodGlucoseMin {
                addField("blood_glucose_min", String(format: "%.1f", glucoseMin))
            }
            if let glucoseMax = vitals.bloodGlucoseMax {
                addField("blood_glucose_max", String(format: "%.1f", glucoseMax))
            }
        }

        // Body metrics
        if body.hasData {
            if let weight = body.weight {
                let converted = converter.convertWeight(weight)
                addField("weight_kg", String(format: "%.1f", converted))
            }
            if let height = body.height {
                let converted = converter.convertHeight(height)
                addField("height_m", String(format: "%.2f", converted))
            }
            if let bmi = body.bmi {
                addField("bmi", String(format: "%.1f", bmi))
            }
            if let bodyFat = body.bodyFatPercentage {
                addField("body_fat_percent", String(format: "%.1f", bodyFat * 100))
            }
            if let lean = body.leanBodyMass {
                let converted = converter.convertWeight(lean)
                addField("lean_body_mass_kg", String(format: "%.1f", converted))
            }
            if let waist = body.waistCircumference {
                addField("waist_circumference_cm", converter.formatLength(waist))
            }
        }

        // Nutrition metrics
        if nutrition.hasData {
            if let energy = nutrition.dietaryEnergy {
                addField("dietary_calories", "\(Int(energy))")
            }
            if let protein = nutrition.protein {
                addField("protein_g", String(format: "%.1f", protein))
            }
            if let carbs = nutrition.carbohydrates {
                addField("carbohydrates_g", String(format: "%.1f", carbs))
            }
            if let fat = nutrition.fat {
                addField("fat_g", String(format: "%.1f", fat))
            }
            if let saturatedFat = nutrition.saturatedFat {
                addField("saturated_fat_g", String(format: "%.1f", saturatedFat))
            }
            if let fiber = nutrition.fiber {
                addField("fiber_g", String(format: "%.1f", fiber))
            }
            if let sugar = nutrition.sugar {
                addField("sugar_g", String(format: "%.1f", sugar))
            }
            if let sodium = nutrition.sodium {
                addField("sodium_mg", "\(Int(sodium))")
            }
            if let cholesterol = nutrition.cholesterol {
                addField("cholesterol_mg", String(format: "%.1f", cholesterol))
            }
            if let water = nutrition.water {
                let converted = converter.convertVolume(water)
                addField("water_l", String(format: "%.2f", converted))
            }
            if let caffeine = nutrition.caffeine {
                addField("caffeine_mg", String(format: "%.1f", caffeine))
            }
        }

        // Mindfulness metrics
        if mindfulness.hasData {
            if let minutes = mindfulness.mindfulMinutes {
                addField("mindful_minutes", "\(Int(minutes))")
            }
            if let sessions = mindfulness.mindfulSessions {
                addField("mindful_sessions", "\(sessions)")
            }
            
            // State of Mind metrics
            if !mindfulness.stateOfMind.isEmpty {
                addField("mood_entries", "\(mindfulness.stateOfMind.count)")
                
                if let avgValence = mindfulness.averageValence {
                    addField("average_mood_valence", String(format: "%.2f", avgValence))
                    let valencePercent = Int(((avgValence + 1.0) / 2.0) * 100)
                    addField("average_mood_percent", "\(valencePercent)")
                }
                
                if !mindfulness.dailyMoods.isEmpty {
                    addField("daily_mood_count", "\(mindfulness.dailyMoods.count)")
                    if let avgDailyValence = mindfulness.averageDailyMoodValence {
                        let dailyPercent = Int(((avgDailyValence + 1.0) / 2.0) * 100)
                        addField("daily_mood_percent", "\(dailyPercent)")
                    }
                }
                
                if !mindfulness.momentaryEmotions.isEmpty {
                    addField("momentary_emotion_count", "\(mindfulness.momentaryEmotions.count)")
                }
                
                // Labels as tags
                if !mindfulness.allLabels.isEmpty {
                    let labelTags = mindfulness.allLabels.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
                    addField("mood_labels", "[\(labelTags.joined(separator: ", "))]")
                }
                
                // Associations as tags
                if !mindfulness.allAssociations.isEmpty {
                    let associationTags = mindfulness.allAssociations.map { $0.lowercased().replacingOccurrences(of: " ", with: "-") }
                    addField("mood_associations", "[\(associationTags.joined(separator: ", "))]")
                }
            }
        }

        // Mobility metrics
        if mobility.hasData {
            if let speed = mobility.walkingSpeed {
                addField("walking_speed", String(format: "%.2f", speed))
            }
            if let stepLength = mobility.walkingStepLength {
                addField("step_length_cm", String(format: "%.1f", stepLength * 100))
            }
            if let doubleSupport = mobility.walkingDoubleSupportPercentage {
                addField("double_support_percent", String(format: "%.1f", doubleSupport * 100))
            }
            if let asymmetry = mobility.walkingAsymmetryPercentage {
                addField("walking_asymmetry_percent", String(format: "%.1f", asymmetry * 100))
            }
            if let ascent = mobility.stairAscentSpeed {
                addField("stair_ascent_speed", String(format: "%.2f", ascent))
            }
            if let descent = mobility.stairDescentSpeed {
                addField("stair_descent_speed", String(format: "%.2f", descent))
            }
            if let sixMin = mobility.sixMinuteWalkDistance {
                addField("six_min_walk_m", "\(Int(sixMin))")
            }
        }

        // Hearing metrics
        if hearing.hasData {
            if let headphone = hearing.headphoneAudioLevel {
                addField("headphone_audio_db", String(format: "%.1f", headphone))
            }
            if let environmental = hearing.environmentalSoundLevel {
                addField("environmental_sound_db", String(format: "%.1f", environmental))
            }
        }

        // Workout summary
        if !workouts.isEmpty {
            addField("workout_count", "\(workouts.count)")

            let totalDuration = workouts.reduce(0.0) { $0 + $1.duration }
            addField("workout_minutes", "\(Int(totalDuration / 60))")

            let totalCalories = workouts.compactMap { $0.calories }.reduce(0.0, +)
            if totalCalories > 0 {
                addField("workout_calories", "\(Int(totalCalories))")
            }

            let totalDistance = workouts.compactMap { $0.distance }.reduce(0.0, +)
            if totalDistance > 0 {
                let converted = converter.convertDistance(totalDistance)
                addField("workout_distance_km", String(format: "%.2f", converted))
            }

            // List workout types as tags
            let workoutTypes = workouts.map { $0.workoutTypeName.lowercased().replacingOccurrences(of: " ", with: "-") }
            let uniqueTypes = Array(Set(workoutTypes))
            addField("workouts", "[\(uniqueTypes.joined(separator: ", "))]")
        }

        frontmatter.append("---")

        // Build the markdown body
        var bodyText = "\n# Health — \(dateString)\n"

        // Add a brief summary section
        var summaryItems: [String] = []

        if sleep.totalDuration > 0 {
            let hours = Int(sleep.totalDuration) / 3600
            let minutes = (Int(sleep.totalDuration) % 3600) / 60
            summaryItems.append("\(hours)h \(minutes)m sleep")
        }

        if let steps = activity.steps {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let formatted = formatter.string(from: NSNumber(value: steps)) {
                summaryItems.append("\(formatted) steps")
            }
        }

        if let calories = nutrition.dietaryEnergy {
            summaryItems.append("\(Int(calories)) kcal")
        }

        if let minutes = mindfulness.mindfulMinutes, minutes > 0 {
            summaryItems.append("\(Int(minutes)) mindful min")
        }
        
        if let avgValence = mindfulness.averageValence {
            let valencePercent = Int(((avgValence + 1.0) / 2.0) * 100)
            summaryItems.append("mood: \(valencePercent)%")
        }

        if !workouts.isEmpty {
            let types = workouts.map { $0.workoutTypeName }
            let uniqueTypes = Array(Set(types))
            if uniqueTypes.count == 1 {
                summaryItems.append("\(workouts.count) \(uniqueTypes[0].lowercased()) workout\(workouts.count > 1 ? "s" : "")")
            } else {
                summaryItems.append("\(workouts.count) workout\(workouts.count > 1 ? "s" : "")")
            }
        }

        if !summaryItems.isEmpty {
            bodyText += "\n" + summaryItems.joined(separator: " · ") + "\n"
        }

        bodyText += "\n## Notes\n\n"

        return frontmatter.joined(separator: "\n") + bodyText
    }
}
