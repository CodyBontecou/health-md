import Foundation

// MARK: - JSON Export

extension HealthData {
    func toJSON(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let dateString = config.dateFormat.format(date: date)
        let converter = config.unitConverter

        var json: [String: Any] = [
            "date": dateString,
            "type": "health-data",
            "units": config.unitPreference.rawValue.lowercased()
        ]

        // Sleep
        if sleep.hasData {
            var sleepDict: [String: Any] = [:]
            if sleep.totalDuration > 0 {
                sleepDict["totalDuration"] = sleep.totalDuration
                sleepDict["totalDurationFormatted"] = formatDuration(sleep.totalDuration)
            }
            if sleep.deepSleep > 0 {
                sleepDict["deepSleep"] = sleep.deepSleep
                sleepDict["deepSleepFormatted"] = formatDuration(sleep.deepSleep)
            }
            if sleep.remSleep > 0 {
                sleepDict["remSleep"] = sleep.remSleep
                sleepDict["remSleepFormatted"] = formatDuration(sleep.remSleep)
            }
            if sleep.coreSleep > 0 {
                sleepDict["coreSleep"] = sleep.coreSleep
                sleepDict["coreSleepFormatted"] = formatDuration(sleep.coreSleep)
            }
            if sleep.awakeTime > 0 {
                sleepDict["awakeTime"] = sleep.awakeTime
                sleepDict["awakeTimeFormatted"] = formatDuration(sleep.awakeTime)
            }
            if sleep.inBedTime > 0 {
                sleepDict["inBedTime"] = sleep.inBedTime
                sleepDict["inBedTimeFormatted"] = formatDuration(sleep.inBedTime)
            }
            json["sleep"] = sleepDict
        }

        // Activity
        if activity.hasData {
            var activityDict: [String: Any] = [:]
            if let steps = activity.steps {
                activityDict["steps"] = steps
            }
            if let calories = activity.activeCalories {
                activityDict["activeCalories"] = calories
            }
            if let basal = activity.basalEnergyBurned {
                activityDict["basalEnergyBurned"] = basal
            }
            if let exercise = activity.exerciseMinutes {
                activityDict["exerciseMinutes"] = exercise
            }
            if let standHours = activity.standHours {
                activityDict["standHours"] = standHours
            }
            if let flights = activity.flightsClimbed {
                activityDict["flightsClimbed"] = flights
            }
            if let distance = activity.walkingRunningDistance {
                activityDict["walkingRunningDistance"] = distance
                activityDict["walkingRunningDistanceKm"] = distance / 1000
            }
            if let cycling = activity.cyclingDistance {
                activityDict["cyclingDistance"] = cycling
                activityDict["cyclingDistanceKm"] = cycling / 1000
            }
            if let swimming = activity.swimmingDistance {
                activityDict["swimmingDistance"] = swimming
            }
            if let strokes = activity.swimmingStrokes {
                activityDict["swimmingStrokes"] = strokes
            }
            if let pushes = activity.pushCount {
                activityDict["pushCount"] = pushes
            }
            json["activity"] = activityDict
        }

        // Heart
        if heart.hasData {
            var heartDict: [String: Any] = [:]
            if let hr = heart.restingHeartRate {
                heartDict["restingHeartRate"] = hr
            }
            if let walkingHR = heart.walkingHeartRateAverage {
                heartDict["walkingHeartRateAverage"] = walkingHR
            }
            if let avgHR = heart.averageHeartRate {
                heartDict["averageHeartRate"] = avgHR
            }
            if let minHR = heart.heartRateMin {
                heartDict["heartRateMin"] = minHR
            }
            if let maxHR = heart.heartRateMax {
                heartDict["heartRateMax"] = maxHR
            }
            if let hrv = heart.hrv {
                heartDict["hrv"] = hrv
            }
            json["heart"] = heartDict
        }

        // Vitals (daily aggregates)
        if vitals.hasData {
            var vitalsDict: [String: Any] = [:]
            
            // Respiratory Rate
            if let rrAvg = vitals.respiratoryRateAvg {
                vitalsDict["respiratoryRateAvg"] = rrAvg
                vitalsDict["respiratoryRate"] = rrAvg // backward compatibility
            }
            if let rrMin = vitals.respiratoryRateMin {
                vitalsDict["respiratoryRateMin"] = rrMin
            }
            if let rrMax = vitals.respiratoryRateMax {
                vitalsDict["respiratoryRateMax"] = rrMax
            }
            
            // Blood Oxygen / SpO2
            if let spo2Avg = vitals.bloodOxygenAvg {
                vitalsDict["bloodOxygenAvg"] = spo2Avg
                vitalsDict["bloodOxygen"] = spo2Avg // backward compatibility
                vitalsDict["bloodOxygenPercent"] = spo2Avg * 100
            }
            if let spo2Min = vitals.bloodOxygenMin {
                vitalsDict["bloodOxygenMin"] = spo2Min
                vitalsDict["bloodOxygenMinPercent"] = spo2Min * 100
            }
            if let spo2Max = vitals.bloodOxygenMax {
                vitalsDict["bloodOxygenMax"] = spo2Max
                vitalsDict["bloodOxygenMaxPercent"] = spo2Max * 100
            }
            
            // Body Temperature
            if let tempAvg = vitals.bodyTemperatureAvg {
                vitalsDict["bodyTemperatureAvg"] = tempAvg
                vitalsDict["bodyTemperature"] = tempAvg // backward compatibility
            }
            if let tempMin = vitals.bodyTemperatureMin {
                vitalsDict["bodyTemperatureMin"] = tempMin
            }
            if let tempMax = vitals.bodyTemperatureMax {
                vitalsDict["bodyTemperatureMax"] = tempMax
            }
            
            // Blood Pressure Systolic
            if let systolicAvg = vitals.bloodPressureSystolicAvg {
                vitalsDict["bloodPressureSystolicAvg"] = systolicAvg
                vitalsDict["bloodPressureSystolic"] = systolicAvg // backward compatibility
            }
            if let systolicMin = vitals.bloodPressureSystolicMin {
                vitalsDict["bloodPressureSystolicMin"] = systolicMin
            }
            if let systolicMax = vitals.bloodPressureSystolicMax {
                vitalsDict["bloodPressureSystolicMax"] = systolicMax
            }
            
            // Blood Pressure Diastolic
            if let diastolicAvg = vitals.bloodPressureDiastolicAvg {
                vitalsDict["bloodPressureDiastolicAvg"] = diastolicAvg
                vitalsDict["bloodPressureDiastolic"] = diastolicAvg // backward compatibility
            }
            if let diastolicMin = vitals.bloodPressureDiastolicMin {
                vitalsDict["bloodPressureDiastolicMin"] = diastolicMin
            }
            if let diastolicMax = vitals.bloodPressureDiastolicMax {
                vitalsDict["bloodPressureDiastolicMax"] = diastolicMax
            }
            
            // Blood Glucose
            if let glucoseAvg = vitals.bloodGlucoseAvg {
                vitalsDict["bloodGlucoseAvg"] = glucoseAvg
                vitalsDict["bloodGlucose"] = glucoseAvg // backward compatibility
            }
            if let glucoseMin = vitals.bloodGlucoseMin {
                vitalsDict["bloodGlucoseMin"] = glucoseMin
            }
            if let glucoseMax = vitals.bloodGlucoseMax {
                vitalsDict["bloodGlucoseMax"] = glucoseMax
            }
            
            json["vitals"] = vitalsDict
        }

        // Body
        if body.hasData {
            var bodyDict: [String: Any] = [:]
            if let weight = body.weight {
                bodyDict["weight"] = weight
            }
            if let height = body.height {
                bodyDict["height"] = height
            }
            if let bmi = body.bmi {
                bodyDict["bmi"] = bmi
            }
            if let bodyFat = body.bodyFatPercentage {
                bodyDict["bodyFatPercentage"] = bodyFat
                bodyDict["bodyFatPercent"] = bodyFat * 100
            }
            if let lean = body.leanBodyMass {
                bodyDict["leanBodyMass"] = lean
            }
            if let waist = body.waistCircumference {
                bodyDict["waistCircumference"] = waist * 100 // Convert to cm
            }
            json["body"] = bodyDict
        }

        // Nutrition
        if nutrition.hasData {
            var nutritionDict: [String: Any] = [:]
            if let energy = nutrition.dietaryEnergy {
                nutritionDict["dietaryEnergy"] = energy
            }
            if let protein = nutrition.protein {
                nutritionDict["protein"] = protein
            }
            if let carbs = nutrition.carbohydrates {
                nutritionDict["carbohydrates"] = carbs
            }
            if let fat = nutrition.fat {
                nutritionDict["fat"] = fat
            }
            if let saturatedFat = nutrition.saturatedFat {
                nutritionDict["saturatedFat"] = saturatedFat
            }
            if let fiber = nutrition.fiber {
                nutritionDict["fiber"] = fiber
            }
            if let sugar = nutrition.sugar {
                nutritionDict["sugar"] = sugar
            }
            if let sodium = nutrition.sodium {
                nutritionDict["sodium"] = sodium
            }
            if let cholesterol = nutrition.cholesterol {
                nutritionDict["cholesterol"] = cholesterol
            }
            if let water = nutrition.water {
                nutritionDict["water"] = water
            }
            if let caffeine = nutrition.caffeine {
                nutritionDict["caffeine"] = caffeine
            }
            json["nutrition"] = nutritionDict
        }

        // Mindfulness
        if mindfulness.hasData {
            var mindfulnessDict: [String: Any] = [:]
            if let minutes = mindfulness.mindfulMinutes {
                mindfulnessDict["mindfulMinutes"] = minutes
            }
            if let sessions = mindfulness.mindfulSessions {
                mindfulnessDict["mindfulSessions"] = sessions
            }
            
            // State of Mind data
            if !mindfulness.stateOfMind.isEmpty {
                mindfulnessDict["stateOfMindCount"] = mindfulness.stateOfMind.count
                
                if let avgValence = mindfulness.averageValence {
                    mindfulnessDict["averageValence"] = avgValence
                    mindfulnessDict["averageValencePercent"] = Int(((avgValence + 1.0) / 2.0) * 100)
                }
                
                if !mindfulness.dailyMoods.isEmpty {
                    mindfulnessDict["dailyMoodCount"] = mindfulness.dailyMoods.count
                    if let avgDailyValence = mindfulness.averageDailyMoodValence {
                        mindfulnessDict["averageDailyMoodValence"] = avgDailyValence
                    }
                }
                
                if !mindfulness.momentaryEmotions.isEmpty {
                    mindfulnessDict["momentaryEmotionCount"] = mindfulness.momentaryEmotions.count
                }
                
                if !mindfulness.allLabels.isEmpty {
                    mindfulnessDict["emotionLabels"] = mindfulness.allLabels
                }
                
                if !mindfulness.allAssociations.isEmpty {
                    mindfulnessDict["associations"] = mindfulness.allAssociations
                }
                
                // Individual entries
                let entriesArray = mindfulness.stateOfMind.map { entry -> [String: Any] in
                    var entryDict: [String: Any] = [
                        "timestamp": config.timeFormat.format(date: entry.timestamp),
                        "kind": entry.kind.rawValue,
                        "valence": entry.valence,
                        "valencePercent": entry.valencePercent,
                        "valenceDescription": entry.valenceDescription
                    ]
                    if !entry.labels.isEmpty {
                        entryDict["labels"] = entry.labels
                    }
                    if !entry.associations.isEmpty {
                        entryDict["associations"] = entry.associations
                    }
                    return entryDict
                }
                mindfulnessDict["stateOfMindEntries"] = entriesArray
            }
            
            json["mindfulness"] = mindfulnessDict
        }

        // Mobility
        if mobility.hasData {
            var mobilityDict: [String: Any] = [:]
            if let speed = mobility.walkingSpeed {
                mobilityDict["walkingSpeed"] = speed
            }
            if let stepLength = mobility.walkingStepLength {
                mobilityDict["walkingStepLength"] = stepLength
            }
            if let doubleSupport = mobility.walkingDoubleSupportPercentage {
                mobilityDict["walkingDoubleSupportPercentage"] = doubleSupport
            }
            if let asymmetry = mobility.walkingAsymmetryPercentage {
                mobilityDict["walkingAsymmetryPercentage"] = asymmetry
            }
            if let ascent = mobility.stairAscentSpeed {
                mobilityDict["stairAscentSpeed"] = ascent
            }
            if let descent = mobility.stairDescentSpeed {
                mobilityDict["stairDescentSpeed"] = descent
            }
            if let sixMin = mobility.sixMinuteWalkDistance {
                mobilityDict["sixMinuteWalkDistance"] = sixMin
            }
            json["mobility"] = mobilityDict
        }

        // Hearing
        if hearing.hasData {
            var hearingDict: [String: Any] = [:]
            if let headphone = hearing.headphoneAudioLevel {
                hearingDict["headphoneAudioLevel"] = headphone
            }
            if let environmental = hearing.environmentalSoundLevel {
                hearingDict["environmentalSoundLevel"] = environmental
            }
            json["hearing"] = hearingDict
        }

        // Workouts
        if !workouts.isEmpty {
            let workoutsArray = workouts.map { workout in
                var workoutDict: [String: Any] = [
                    "type": workout.workoutTypeName,
                    "startTime": config.timeFormat.format(date: workout.startTime),
                    "duration": workout.duration,
                    "durationFormatted": formatDurationShort(workout.duration)
                ]
                if let distance = workout.distance, distance > 0 {
                    workoutDict["distance"] = distance
                    workoutDict["distanceFormatted"] = converter.formatDistance(distance)
                }
                if let calories = workout.calories, calories > 0 {
                    workoutDict["calories"] = calories
                }
                return workoutDict
            }
            json["workouts"] = workoutsArray
        }

        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "{}"
    }
}
