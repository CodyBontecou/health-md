import Foundation

// MARK: - Markdown Export

extension HealthData {
    func toMarkdown(includeMetadata: Bool = true, groupByCategory: Bool = true, customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let dateString = config.dateFormat.format(date: date)
        let converter = config.unitConverter
        let template = config.markdownTemplate
        let bullet = template.bulletStyle.rawValue
        let headerPrefix = String(repeating: "#", count: template.sectionHeaderLevel)
        
        // Emoji prefixes based on settings
        let sleepEmoji = template.useEmoji ? "😴 " : ""
        let activityEmoji = template.useEmoji ? "🏃 " : ""
        let heartEmoji = template.useEmoji ? "❤️ " : ""
        let vitalsEmoji = template.useEmoji ? "🩺 " : ""
        let bodyEmoji = template.useEmoji ? "📏 " : ""
        let nutritionEmoji = template.useEmoji ? "🍎 " : ""
        let mindfulnessEmoji = template.useEmoji ? "🧘 " : ""
        let mobilityEmoji = template.useEmoji ? "🚶 " : ""
        let hearingEmoji = template.useEmoji ? "👂 " : ""
        let workoutsEmoji = template.useEmoji ? "💪 " : ""

        var markdown = ""

        if includeMetadata {
            let fmConfig = config.frontmatterConfig
            markdown += "---\n"
            if fmConfig.includeDate {
                markdown += "\(fmConfig.customDateKey): \(dateString)\n"
            }
            if fmConfig.includeType {
                markdown += "\(fmConfig.customTypeKey): \(fmConfig.customTypeValue)\n"
            }
            // Add custom static fields
            for (key, value) in fmConfig.customFields.sorted(by: { $0.key < $1.key }) {
                markdown += "\(key): \(value)\n"
            }
            markdown += "---\n\n"
        }

        markdown += "# Health Data — \(dateString)\n"
        
        // Summary section
        if template.includeSummary {
            var summaryParts: [String] = []
            if sleep.totalDuration > 0 {
                summaryParts.append(formatDuration(sleep.totalDuration) + " sleep")
            }
            if let steps = activity.steps {
                summaryParts.append(formatNumber(steps) + " steps")
            }
            if !workouts.isEmpty {
                summaryParts.append("\(workouts.count) workout\(workouts.count > 1 ? "s" : "")")
            }
            if let avgValence = mindfulness.averageValence {
                let valencePercent = Int(((avgValence + 1.0) / 2.0) * 100)
                let moodEmoji = template.useEmoji ? (avgValence >= 0.2 ? "🙂" : avgValence <= -0.2 ? "😔" : "😐") + " " : ""
                summaryParts.append("\(moodEmoji)mood \(valencePercent)%")
            }
            if !summaryParts.isEmpty {
                markdown += "\n" + summaryParts.joined(separator: " · ") + "\n"
            }
        }

        // Sleep Section
        if sleep.hasData {
            markdown += "\n\(headerPrefix) \(sleepEmoji)Sleep\n\n"
            if sleep.totalDuration > 0 {
                markdown += "\(bullet) **Total:** \(formatDuration(sleep.totalDuration))\n"
            }
            if sleep.inBedTime > 0 {
                markdown += "\(bullet) **In Bed:** \(formatDuration(sleep.inBedTime))\n"
            }
            if sleep.deepSleep > 0 {
                markdown += "\(bullet) **Deep:** \(formatDuration(sleep.deepSleep))\n"
            }
            if sleep.remSleep > 0 {
                markdown += "\(bullet) **REM:** \(formatDuration(sleep.remSleep))\n"
            }
            if sleep.coreSleep > 0 {
                markdown += "\(bullet) **Core:** \(formatDuration(sleep.coreSleep))\n"
            }
            if sleep.awakeTime > 0 {
                markdown += "\(bullet) **Awake:** \(formatDuration(sleep.awakeTime))\n"
            }
        }

        // Activity Section
        if activity.hasData {
            markdown += "\n\(headerPrefix) \(activityEmoji)Activity\n\n"
            if let steps = activity.steps {
                markdown += "\(bullet) **Steps:** \(formatNumber(steps))\n"
            }
            if let calories = activity.activeCalories {
                markdown += "\(bullet) **Active Calories:** \(formatNumber(Int(calories))) kcal\n"
            }
            if let basal = activity.basalEnergyBurned {
                markdown += "\(bullet) **Basal Energy:** \(formatNumber(Int(basal))) kcal\n"
            }
            if let exercise = activity.exerciseMinutes {
                markdown += "\(bullet) **Exercise:** \(Int(exercise)) min\n"
            }
            if let standHours = activity.standHours {
                markdown += "\(bullet) **Stand Hours:** \(standHours)\n"
            }
            if let flights = activity.flightsClimbed {
                markdown += "\(bullet) **Flights Climbed:** \(flights)\n"
            }
            if let distance = activity.walkingRunningDistance {
                markdown += "\(bullet) **Walking/Running Distance:** \(converter.formatDistance(distance))\n"
            }
            if let cycling = activity.cyclingDistance {
                markdown += "\(bullet) **Cycling Distance:** \(converter.formatDistance(cycling))\n"
            }
            if let swimming = activity.swimmingDistance {
                markdown += "\(bullet) **Swimming Distance:** \(converter.formatDistance(swimming))\n"
            }
            if let strokes = activity.swimmingStrokes {
                markdown += "\(bullet) **Swimming Strokes:** \(formatNumber(strokes))\n"
            }
            if let pushes = activity.pushCount {
                markdown += "\(bullet) **Wheelchair Pushes:** \(formatNumber(pushes))\n"
            }
        }

        // Heart Section
        if heart.hasData {
            markdown += "\n\(headerPrefix) \(heartEmoji)Heart\n\n"
            if let hr = heart.restingHeartRate {
                markdown += "\(bullet) **Resting HR:** \(Int(hr)) bpm\n"
            }
            if let walkingHR = heart.walkingHeartRateAverage {
                markdown += "\(bullet) **Walking HR Average:** \(Int(walkingHR)) bpm\n"
            }
            if let avgHR = heart.averageHeartRate {
                markdown += "\(bullet) **Average HR:** \(Int(avgHR)) bpm\n"
            }
            if let minHR = heart.heartRateMin {
                markdown += "\(bullet) **Min HR:** \(Int(minHR)) bpm\n"
            }
            if let maxHR = heart.heartRateMax {
                markdown += "\(bullet) **Max HR:** \(Int(maxHR)) bpm\n"
            }
            if let hrv = heart.hrv {
                markdown += "\(bullet) **HRV:** \(String(format: "%.1f", hrv)) ms\n"
            }
        }

        // Vitals Section
        if vitals.hasData {
            markdown += "\n\(headerPrefix) \(vitalsEmoji)Vitals\n\n"
            
            // Respiratory Rate
            if let rrAvg = vitals.respiratoryRateAvg {
                var rrStr = "\(bullet) **Respiratory Rate:** \(String(format: "%.1f", rrAvg)) breaths/min"
                if let rrMin = vitals.respiratoryRateMin, let rrMax = vitals.respiratoryRateMax, rrMin != rrMax {
                    rrStr += " (range: \(String(format: "%.1f", rrMin))–\(String(format: "%.1f", rrMax)))"
                }
                markdown += rrStr + "\n"
            }
            
            // Blood Oxygen / SpO2
            if let spo2Avg = vitals.bloodOxygenAvg {
                var spo2Str = "\(bullet) **SpO2:** \(Int(spo2Avg * 100))%"
                if let spo2Min = vitals.bloodOxygenMin, let spo2Max = vitals.bloodOxygenMax, spo2Min != spo2Max {
                    spo2Str += " (range: \(Int(spo2Min * 100))%–\(Int(spo2Max * 100))%)"
                }
                markdown += spo2Str + "\n"
            }
            
            // Body Temperature
            if let tempAvg = vitals.bodyTemperatureAvg {
                var tempStr = "\(bullet) **Body Temperature:** \(converter.formatTemperature(tempAvg))"
                if let tempMin = vitals.bodyTemperatureMin, let tempMax = vitals.bodyTemperatureMax, tempMin != tempMax {
                    tempStr += " (range: \(converter.formatTemperature(tempMin))–\(converter.formatTemperature(tempMax)))"
                }
                markdown += tempStr + "\n"
            }
            
            // Blood Pressure
            if let systolicAvg = vitals.bloodPressureSystolicAvg, let diastolicAvg = vitals.bloodPressureDiastolicAvg {
                var bpStr = "\(bullet) **Blood Pressure:** \(Int(systolicAvg))/\(Int(diastolicAvg)) mmHg"
                if let sysMin = vitals.bloodPressureSystolicMin, let sysMax = vitals.bloodPressureSystolicMax,
                   let diaMin = vitals.bloodPressureDiastolicMin, let diaMax = vitals.bloodPressureDiastolicMax,
                   (sysMin != sysMax || diaMin != diaMax) {
                    bpStr += " (range: \(Int(sysMin))/\(Int(diaMin))–\(Int(sysMax))/\(Int(diaMax)))"
                }
                markdown += bpStr + "\n"
            }
            
            // Blood Glucose
            if let glucoseAvg = vitals.bloodGlucoseAvg {
                var glucoseStr = "\(bullet) **Blood Glucose:** \(String(format: "%.1f", glucoseAvg)) mg/dL"
                if let glucoseMin = vitals.bloodGlucoseMin, let glucoseMax = vitals.bloodGlucoseMax, glucoseMin != glucoseMax {
                    glucoseStr += " (range: \(String(format: "%.1f", glucoseMin))–\(String(format: "%.1f", glucoseMax)))"
                }
                markdown += glucoseStr + "\n"
            }
        }

        // Body Section
        if body.hasData {
            markdown += "\n\(headerPrefix) \(bodyEmoji)Body\n\n"
            if let weight = body.weight {
                markdown += "\(bullet) **Weight:** \(converter.formatWeight(weight))\n"
            }
            if let height = body.height {
                markdown += "\(bullet) **Height:** \(converter.formatHeight(height))\n"
            }
            if let bmi = body.bmi {
                markdown += "\(bullet) **BMI:** \(String(format: "%.1f", bmi))\n"
            }
            if let bodyFat = body.bodyFatPercentage {
                markdown += "\(bullet) **Body Fat:** \(String(format: "%.1f", bodyFat * 100))%\n"
            }
            if let lean = body.leanBodyMass {
                markdown += "\(bullet) **Lean Body Mass:** \(converter.formatWeight(lean))\n"
            }
            if let waist = body.waistCircumference {
                markdown += "\(bullet) **Waist Circumference:** \(converter.formatLength(waist))\n"
            }
        }

        // Nutrition Section
        if nutrition.hasData {
            markdown += "\n\(headerPrefix) \(nutritionEmoji)Nutrition\n\n"
            if let energy = nutrition.dietaryEnergy {
                markdown += "\(bullet) **Calories:** \(formatNumber(Int(energy))) kcal\n"
            }
            if let protein = nutrition.protein {
                markdown += "\(bullet) **Protein:** \(String(format: "%.1f", protein)) g\n"
            }
            if let carbs = nutrition.carbohydrates {
                markdown += "\(bullet) **Carbohydrates:** \(String(format: "%.1f", carbs)) g\n"
            }
            if let fat = nutrition.fat {
                markdown += "\(bullet) **Fat:** \(String(format: "%.1f", fat)) g\n"
            }
            if let saturatedFat = nutrition.saturatedFat {
                markdown += "\(bullet) **Saturated Fat:** \(String(format: "%.1f", saturatedFat)) g\n"
            }
            if let fiber = nutrition.fiber {
                markdown += "\(bullet) **Fiber:** \(String(format: "%.1f", fiber)) g\n"
            }
            if let sugar = nutrition.sugar {
                markdown += "\(bullet) **Sugar:** \(String(format: "%.1f", sugar)) g\n"
            }
            if let sodium = nutrition.sodium {
                markdown += "\(bullet) **Sodium:** \(formatNumber(Int(sodium))) mg\n"
            }
            if let cholesterol = nutrition.cholesterol {
                markdown += "\(bullet) **Cholesterol:** \(String(format: "%.1f", cholesterol)) mg\n"
            }
            if let water = nutrition.water {
                markdown += "\(bullet) **Water:** \(converter.formatVolume(water))\n"
            }
            if let caffeine = nutrition.caffeine {
                markdown += "\(bullet) **Caffeine:** \(String(format: "%.1f", caffeine)) mg\n"
            }
        }

        // Mindfulness Section
        if mindfulness.hasData {
            markdown += "\n\(headerPrefix) \(mindfulnessEmoji)Mindfulness\n\n"
            if let minutes = mindfulness.mindfulMinutes {
                markdown += "\(bullet) **Mindful Minutes:** \(Int(minutes)) min\n"
            }
            if let sessions = mindfulness.mindfulSessions {
                markdown += "\(bullet) **Sessions:** \(sessions)\n"
            }
            
            // State of Mind data
            if !mindfulness.stateOfMind.isEmpty {
                markdown += "\n"
                
                // Summary stats
                if let avgValence = mindfulness.averageValence {
                    let valencePercent = Int(((avgValence + 1.0) / 2.0) * 100)
                    markdown += "\(bullet) **Average Mood:** \(valencePercent)% (\(valenceDescription(avgValence)))\n"
                }
                
                if !mindfulness.dailyMoods.isEmpty {
                    markdown += "\(bullet) **Daily Mood Entries:** \(mindfulness.dailyMoods.count)\n"
                }
                
                if !mindfulness.momentaryEmotions.isEmpty {
                    markdown += "\(bullet) **Momentary Emotions:** \(mindfulness.momentaryEmotions.count)\n"
                }
                
                // List all unique labels
                if !mindfulness.allLabels.isEmpty {
                    markdown += "\(bullet) **Emotions/Moods:** \(mindfulness.allLabels.joined(separator: ", "))\n"
                }
                
                // List all unique associations
                if !mindfulness.allAssociations.isEmpty {
                    markdown += "\(bullet) **Associated With:** \(mindfulness.allAssociations.joined(separator: ", "))\n"
                }
                
                // Detailed entries (if template allows)
                if template.includeSummary && mindfulness.stateOfMind.count <= 5 {
                    let subHeaderPrefix = String(repeating: "#", count: template.sectionHeaderLevel + 1)
                    markdown += "\n\(subHeaderPrefix) Mood Entries\n\n"
                    
                    for entry in mindfulness.stateOfMind {
                        let timeStr = config.timeFormat.format(date: entry.timestamp)
                        let emoji = template.useEmoji ? entry.valenceEmoji + " " : ""
                        markdown += "\(bullet) **\(timeStr)** \(emoji)(\(entry.kind.rawValue)): \(entry.valencePercent)%"
                        if !entry.labels.isEmpty {
                            markdown += " — \(entry.labels.joined(separator: ", "))"
                        }
                        markdown += "\n"
                    }
                }
            }
        }

        // Mobility Section
        if mobility.hasData {
            markdown += "\n\(headerPrefix) \(mobilityEmoji)Mobility\n\n"
            if let speed = mobility.walkingSpeed {
                markdown += "\(bullet) **Walking Speed:** \(converter.formatSpeed(speed))\n"
            }
            if let stepLength = mobility.walkingStepLength {
                markdown += "\(bullet) **Step Length:** \(converter.formatLength(stepLength))\n"
            }
            if let doubleSupport = mobility.walkingDoubleSupportPercentage {
                markdown += "\(bullet) **Double Support:** \(String(format: "%.1f", doubleSupport * 100))%\n"
            }
            if let asymmetry = mobility.walkingAsymmetryPercentage {
                markdown += "\(bullet) **Walking Asymmetry:** \(String(format: "%.1f", asymmetry * 100))%\n"
            }
            if let ascent = mobility.stairAscentSpeed {
                markdown += "\(bullet) **Stair Ascent Speed:** \(converter.formatSpeed(ascent))\n"
            }
            if let descent = mobility.stairDescentSpeed {
                markdown += "\(bullet) **Stair Descent Speed:** \(converter.formatSpeed(descent))\n"
            }
            if let sixMin = mobility.sixMinuteWalkDistance {
                markdown += "\(bullet) **6-Min Walk Distance:** \(converter.formatDistance(sixMin))\n"
            }
        }

        // Hearing Section
        if hearing.hasData {
            markdown += "\n\(headerPrefix) \(hearingEmoji)Hearing\n\n"
            if let headphone = hearing.headphoneAudioLevel {
                markdown += "\(bullet) **Headphone Audio Level:** \(String(format: "%.1f", headphone)) dB\n"
            }
            if let environmental = hearing.environmentalSoundLevel {
                markdown += "\(bullet) **Environmental Sound Level:** \(String(format: "%.1f", environmental)) dB\n"
            }
        }

        // Workouts Section
        if !workouts.isEmpty {
            markdown += "\n\(headerPrefix) \(workoutsEmoji)Workouts\n"
            
            let subHeaderPrefix = String(repeating: "#", count: template.sectionHeaderLevel + 1)

            for (index, workout) in workouts.enumerated() {
                markdown += "\n\(subHeaderPrefix) \(index + 1). \(workout.workoutTypeName)\n\n"
                markdown += "\(bullet) **Time:** \(config.timeFormat.format(date: workout.startTime))\n"
                markdown += "\(bullet) **Duration:** \(formatDurationShort(workout.duration))\n"
                if let distance = workout.distance, distance > 0 {
                    markdown += "\(bullet) **Distance:** \(converter.formatDistance(distance))\n"
                }
                if let calories = workout.calories, calories > 0 {
                    markdown += "\(bullet) **Calories:** \(Int(calories)) kcal\n"
                }
            }
        }

        return markdown
    }
}
