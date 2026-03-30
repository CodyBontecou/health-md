import Foundation

// MARK: - JSON Export

extension HealthData {
    func toJSON(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let snapshot = exportSnapshot(customization: config)

        var json: [String: Any] = [
            "date": snapshot.dateString,
            "type": "health-data",
            "units": snapshot.unitPreference.rawValue.lowercased()
        ]

        // Sleep
        if snapshot.sleep.hasData {
            var sleepDict: [String: Any] = [:]
            if snapshot.sleep.totalDurationSeconds > 0 {
                sleepDict["totalDuration"] = snapshot.sleep.totalDurationSeconds
                sleepDict["totalDurationFormatted"] = formatDuration(snapshot.sleep.totalDurationSeconds)
            }
            if let bedtime = snapshot.sleep.bedtime {
                sleepDict["bedtime"] = snapshot.timeFormat.format(date: bedtime)
                sleepDict["bedtimeISO"] = ISO8601DateFormatter().string(from: bedtime)
            }
            if let wake = snapshot.sleep.wakeTime {
                sleepDict["wakeTime"] = snapshot.timeFormat.format(date: wake)
                sleepDict["wakeTimeISO"] = ISO8601DateFormatter().string(from: wake)
            }
            if snapshot.sleep.deepSleepSeconds > 0 {
                sleepDict["deepSleep"] = snapshot.sleep.deepSleepSeconds
                sleepDict["deepSleepFormatted"] = formatDuration(snapshot.sleep.deepSleepSeconds)
            }
            if snapshot.sleep.remSleepSeconds > 0 {
                sleepDict["remSleep"] = snapshot.sleep.remSleepSeconds
                sleepDict["remSleepFormatted"] = formatDuration(snapshot.sleep.remSleepSeconds)
            }
            if snapshot.sleep.coreSleepSeconds > 0 {
                sleepDict["coreSleep"] = snapshot.sleep.coreSleepSeconds
                sleepDict["coreSleepFormatted"] = formatDuration(snapshot.sleep.coreSleepSeconds)
            }
            if snapshot.sleep.awakeSeconds > 0 {
                sleepDict["awakeTime"] = snapshot.sleep.awakeSeconds
                sleepDict["awakeTimeFormatted"] = formatDuration(snapshot.sleep.awakeSeconds)
            }
            if snapshot.sleep.inBedSeconds > 0 {
                sleepDict["inBedTime"] = snapshot.sleep.inBedSeconds
                sleepDict["inBedTimeFormatted"] = formatDuration(snapshot.sleep.inBedSeconds)
            }
            json["sleep"] = sleepDict
        }

        // Activity
        if snapshot.activity.hasData {
            var activityDict: [String: Any] = [:]
            if let steps = snapshot.activity.steps {
                activityDict["steps"] = steps
            }
            if let calories = snapshot.activity.activeCalories {
                activityDict["activeCalories"] = calories
            }
            if let basal = snapshot.activity.basalEnergyBurned {
                activityDict["basalEnergyBurned"] = basal
            }
            if let exercise = snapshot.activity.exerciseMinutes {
                activityDict["exerciseMinutes"] = exercise
            }
            if let standHours = snapshot.activity.standHours {
                activityDict["standHours"] = standHours
            }
            if let flights = snapshot.activity.flightsClimbed {
                activityDict["flightsClimbed"] = flights
            }
            if let distance = snapshot.activity.walkingRunningDistanceMeters {
                activityDict["walkingRunningDistance"] = distance
                activityDict["walkingRunningDistanceKm"] = distance / 1000
            }
            if let cycling = snapshot.activity.cyclingDistanceMeters {
                activityDict["cyclingDistance"] = cycling
                activityDict["cyclingDistanceKm"] = cycling / 1000
            }
            if let swimming = snapshot.activity.swimmingDistanceMeters {
                activityDict["swimmingDistance"] = swimming
            }
            if let strokes = snapshot.activity.swimmingStrokes {
                activityDict["swimmingStrokes"] = strokes
            }
            if let pushes = snapshot.activity.wheelchairPushes {
                activityDict["pushCount"] = pushes
            }
            if let vo2 = snapshot.activity.vo2Max {
                activityDict["vo2Max"] = vo2
            }
            json["activity"] = activityDict
        }

        // Heart
        if snapshot.heart.hasData {
            var heartDict: [String: Any] = [:]
            if let hr = snapshot.heart.restingHeartRate {
                heartDict["restingHeartRate"] = hr
            }
            if let walkingHR = snapshot.heart.walkingHeartRateAverage {
                heartDict["walkingHeartRateAverage"] = walkingHR
            }
            if let avgHR = snapshot.heart.averageHeartRate {
                heartDict["averageHeartRate"] = avgHR
            }
            if let minHR = snapshot.heart.minHeartRate {
                heartDict["heartRateMin"] = minHR
            }
            if let maxHR = snapshot.heart.maxHeartRate {
                heartDict["heartRateMax"] = maxHR
            }
            if let hrv = snapshot.heart.hrvMilliseconds {
                heartDict["hrv"] = hrv
            }
            json["heart"] = heartDict
        }

        // Vitals (daily aggregates)
        if snapshot.vitals.hasData {
            var vitalsDict: [String: Any] = [:]

            // Respiratory Rate
            if let rrAvg = snapshot.vitals.respiratoryRateAvg {
                vitalsDict["respiratoryRateAvg"] = rrAvg
                vitalsDict["respiratoryRate"] = rrAvg // backward compatibility
            }
            if let rrMin = snapshot.vitals.respiratoryRateMin {
                vitalsDict["respiratoryRateMin"] = rrMin
            }
            if let rrMax = snapshot.vitals.respiratoryRateMax {
                vitalsDict["respiratoryRateMax"] = rrMax
            }

            // Blood Oxygen / SpO2
            if let spo2Avg = snapshot.vitals.bloodOxygenAvg {
                vitalsDict["bloodOxygenAvg"] = spo2Avg
                vitalsDict["bloodOxygen"] = spo2Avg // backward compatibility
                vitalsDict["bloodOxygenPercent"] = spo2Avg * 100
            }
            if let spo2Min = snapshot.vitals.bloodOxygenMin {
                vitalsDict["bloodOxygenMin"] = spo2Min
                vitalsDict["bloodOxygenMinPercent"] = spo2Min * 100
            }
            if let spo2Max = snapshot.vitals.bloodOxygenMax {
                vitalsDict["bloodOxygenMax"] = spo2Max
                vitalsDict["bloodOxygenMaxPercent"] = spo2Max * 100
            }

            // Body Temperature
            if let tempAvg = snapshot.vitals.bodyTemperatureAvgCelsius {
                vitalsDict["bodyTemperatureAvg"] = tempAvg
                vitalsDict["bodyTemperature"] = tempAvg // backward compatibility
            }
            if let tempMin = snapshot.vitals.bodyTemperatureMinCelsius {
                vitalsDict["bodyTemperatureMin"] = tempMin
            }
            if let tempMax = snapshot.vitals.bodyTemperatureMaxCelsius {
                vitalsDict["bodyTemperatureMax"] = tempMax
            }

            // Blood Pressure Systolic
            if let systolicAvg = snapshot.vitals.bloodPressureSystolicAvg {
                vitalsDict["bloodPressureSystolicAvg"] = systolicAvg
                vitalsDict["bloodPressureSystolic"] = systolicAvg // backward compatibility
            }
            if let systolicMin = snapshot.vitals.bloodPressureSystolicMin {
                vitalsDict["bloodPressureSystolicMin"] = systolicMin
            }
            if let systolicMax = snapshot.vitals.bloodPressureSystolicMax {
                vitalsDict["bloodPressureSystolicMax"] = systolicMax
            }

            // Blood Pressure Diastolic
            if let diastolicAvg = snapshot.vitals.bloodPressureDiastolicAvg {
                vitalsDict["bloodPressureDiastolicAvg"] = diastolicAvg
                vitalsDict["bloodPressureDiastolic"] = diastolicAvg // backward compatibility
            }
            if let diastolicMin = snapshot.vitals.bloodPressureDiastolicMin {
                vitalsDict["bloodPressureDiastolicMin"] = diastolicMin
            }
            if let diastolicMax = snapshot.vitals.bloodPressureDiastolicMax {
                vitalsDict["bloodPressureDiastolicMax"] = diastolicMax
            }

            // Blood Glucose
            if let glucoseAvg = snapshot.vitals.bloodGlucoseAvg {
                vitalsDict["bloodGlucoseAvg"] = glucoseAvg
                vitalsDict["bloodGlucose"] = glucoseAvg // backward compatibility
            }
            if let glucoseMin = snapshot.vitals.bloodGlucoseMin {
                vitalsDict["bloodGlucoseMin"] = glucoseMin
            }
            if let glucoseMax = snapshot.vitals.bloodGlucoseMax {
                vitalsDict["bloodGlucoseMax"] = glucoseMax
            }

            json["vitals"] = vitalsDict
        }

        // Body
        if snapshot.body.hasData {
            var bodyDict: [String: Any] = [:]
            if let weight = snapshot.body.weightKg {
                bodyDict["weight"] = weight
            }
            if let height = snapshot.body.heightMeters {
                bodyDict["height"] = height
            }
            if let bmi = snapshot.body.bmi {
                bodyDict["bmi"] = bmi
            }
            if let bodyFat = snapshot.body.bodyFatRatio {
                bodyDict["bodyFatPercentage"] = bodyFat
                bodyDict["bodyFatPercent"] = bodyFat * 100
            }
            if let lean = snapshot.body.leanBodyMassKg {
                bodyDict["leanBodyMass"] = lean
            }
            if let waist = snapshot.body.waistCircumferenceMeters {
                bodyDict["waistCircumference"] = waist * 100 // Convert to cm
            }
            json["body"] = bodyDict
        }

        // Nutrition
        if snapshot.nutrition.hasData {
            var nutritionDict: [String: Any] = [:]
            if let energy = snapshot.nutrition.dietaryEnergyKcal {
                nutritionDict["dietaryEnergy"] = energy
            }
            if let protein = snapshot.nutrition.proteinGrams {
                nutritionDict["protein"] = protein
            }
            if let carbs = snapshot.nutrition.carbohydratesGrams {
                nutritionDict["carbohydrates"] = carbs
            }
            if let fat = snapshot.nutrition.fatGrams {
                nutritionDict["fat"] = fat
            }
            if let saturatedFat = snapshot.nutrition.saturatedFatGrams {
                nutritionDict["saturatedFat"] = saturatedFat
            }
            if let fiber = snapshot.nutrition.fiberGrams {
                nutritionDict["fiber"] = fiber
            }
            if let sugar = snapshot.nutrition.sugarGrams {
                nutritionDict["sugar"] = sugar
            }
            if let sodium = snapshot.nutrition.sodiumMg {
                nutritionDict["sodium"] = sodium
            }
            if let cholesterol = snapshot.nutrition.cholesterolMg {
                nutritionDict["cholesterol"] = cholesterol
            }
            if let water = snapshot.nutrition.waterLiters {
                nutritionDict["water"] = water
            }
            if let caffeine = snapshot.nutrition.caffeineMg {
                nutritionDict["caffeine"] = caffeine
            }
            json["nutrition"] = nutritionDict
        }

        // Mindfulness
        if snapshot.mindfulness.hasData {
            var mindfulnessDict: [String: Any] = [:]
            if let minutes = snapshot.mindfulness.mindfulMinutes {
                mindfulnessDict["mindfulMinutes"] = minutes
            }
            if let sessions = snapshot.mindfulness.mindfulSessions {
                mindfulnessDict["mindfulSessions"] = sessions
            }

            if !snapshot.mindfulness.stateOfMindEntries.isEmpty {
                mindfulnessDict["stateOfMindCount"] = snapshot.mindfulness.stateOfMindEntries.count

                if let avgValence = snapshot.mindfulness.averageValence {
                    mindfulnessDict["averageValence"] = avgValence
                    mindfulnessDict["averageValencePercent"] = snapshot.mindfulness.averageValencePercent
                }

                if !snapshot.mindfulness.dailyMoods.isEmpty {
                    mindfulnessDict["dailyMoodCount"] = snapshot.mindfulness.dailyMoods.count
                    if let avgDailyValence = snapshot.mindfulness.averageDailyMoodValence {
                        mindfulnessDict["averageDailyMoodValence"] = avgDailyValence
                    }
                }

                if !snapshot.mindfulness.momentaryEmotions.isEmpty {
                    mindfulnessDict["momentaryEmotionCount"] = snapshot.mindfulness.momentaryEmotions.count
                }

                if !snapshot.mindfulness.emotionLabels.isEmpty {
                    mindfulnessDict["emotionLabels"] = snapshot.mindfulness.emotionLabels
                }

                if !snapshot.mindfulness.associations.isEmpty {
                    mindfulnessDict["associations"] = snapshot.mindfulness.associations
                }

                let entriesArray = snapshot.mindfulness.stateOfMindEntries.map { entry -> [String: Any] in
                    var entryDict: [String: Any] = [
                        "timestamp": snapshot.timeFormat.format(date: entry.timestamp),
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
        if snapshot.mobility.hasData {
            var mobilityDict: [String: Any] = [:]
            if let speed = snapshot.mobility.walkingSpeedMps {
                mobilityDict["walkingSpeed"] = speed
            }
            if let stepLength = snapshot.mobility.walkingStepLengthMeters {
                mobilityDict["walkingStepLength"] = stepLength
            }
            if let doubleSupport = snapshot.mobility.walkingDoubleSupportRatio {
                mobilityDict["walkingDoubleSupportPercentage"] = doubleSupport
            }
            if let asymmetry = snapshot.mobility.walkingAsymmetryRatio {
                mobilityDict["walkingAsymmetryPercentage"] = asymmetry
            }
            if let ascent = snapshot.mobility.stairAscentSpeedMps {
                mobilityDict["stairAscentSpeed"] = ascent
            }
            if let descent = snapshot.mobility.stairDescentSpeedMps {
                mobilityDict["stairDescentSpeed"] = descent
            }
            if let sixMin = snapshot.mobility.sixMinuteWalkDistanceMeters {
                mobilityDict["sixMinuteWalkDistance"] = sixMin
            }
            json["mobility"] = mobilityDict
        }

        // Hearing
        if snapshot.hearing.hasData {
            var hearingDict: [String: Any] = [:]
            if let headphone = snapshot.hearing.headphoneAudioLevelDb {
                hearingDict["headphoneAudioLevel"] = headphone
            }
            if let environmental = snapshot.hearing.environmentalSoundLevelDb {
                hearingDict["environmentalSoundLevel"] = environmental
            }
            json["hearing"] = hearingDict
        }

        // Workouts
        if !snapshot.workouts.isEmpty {
            let workoutsArray = snapshot.workouts.map { workout in
                var workoutDict: [String: Any] = [
                    "type": workout.workoutTypeName,
                    "startTime": snapshot.timeFormat.format(date: workout.startTime),
                    "duration": workout.duration,
                    "durationFormatted": formatDurationShort(workout.duration)
                ]
                if let distance = workout.distance, distance > 0 {
                    workoutDict["distance"] = distance
                    workoutDict["distanceFormatted"] = snapshot.converter.formatDistance(distance)
                }
                if let calories = workout.calories, calories > 0 {
                    workoutDict["calories"] = calories
                }
                return workoutDict
            }
            json["workouts"] = workoutsArray
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        return "{}"
    }
}
