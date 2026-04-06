import Foundation

// MARK: - CSV Export

extension HealthData {
    func toCSV(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let snapshot = exportSnapshot(customization: config)

        let distanceUnit = snapshot.converter.distanceUnit()
        let weightUnit = snapshot.converter.weightUnit()
        let tempUnit = snapshot.converter.temperatureUnit()

        var csv = "Date,Category,Metric,Value,Unit,Timestamp\n"

        // Sleep
        if snapshot.sleep.hasData {
            if snapshot.sleep.totalDurationSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,Total Duration,\(snapshot.sleep.totalDurationSeconds),seconds\n"
            }
            if let bedtime = snapshot.sleep.bedtime {
                csv += "\(snapshot.dateString),Sleep,Bedtime,\(snapshot.timeFormat.format(date: bedtime)),time\n"
            }
            if let wake = snapshot.sleep.wakeTime {
                csv += "\(snapshot.dateString),Sleep,Wake Time,\(snapshot.timeFormat.format(date: wake)),time\n"
            }
            if snapshot.sleep.deepSleepSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,Deep Sleep,\(snapshot.sleep.deepSleepSeconds),seconds\n"
            }
            if snapshot.sleep.remSleepSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,REM Sleep,\(snapshot.sleep.remSleepSeconds),seconds\n"
            }
            if snapshot.sleep.coreSleepSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,Core Sleep,\(snapshot.sleep.coreSleepSeconds),seconds\n"
            }
            if snapshot.sleep.awakeSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,Awake Time,\(snapshot.sleep.awakeSeconds),seconds\n"
            }
            if snapshot.sleep.inBedSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,In Bed Time,\(snapshot.sleep.inBedSeconds),seconds\n"
            }
            if !snapshot.sleep.stages.isEmpty {
                let isoFormatter = ISO8601DateFormatter()
                for stage in snapshot.sleep.stages {
                    let duration = stage.endDate.timeIntervalSince(stage.startDate)
                    csv += "\(snapshot.dateString),Sleep,Sleep Stage,\(stage.stage) (\(Int(duration))s),seconds,\(isoFormatter.string(from: stage.startDate))\n"
                }
            }
        }

        // Activity
        if snapshot.activity.hasData {
            if let steps = snapshot.activity.steps {
                csv += "\(snapshot.dateString),Activity,Steps,\(steps),count\n"
            }
            if let calories = snapshot.activity.activeCalories {
                csv += "\(snapshot.dateString),Activity,Active Calories,\(calories),kcal\n"
            }
            if let basal = snapshot.activity.basalEnergyBurned {
                csv += "\(snapshot.dateString),Activity,Basal Energy,\(basal),kcal\n"
            }
            if let exercise = snapshot.activity.exerciseMinutes {
                csv += "\(snapshot.dateString),Activity,Exercise Minutes,\(exercise),minutes\n"
            }
            if let standHours = snapshot.activity.standHours {
                csv += "\(snapshot.dateString),Activity,Stand Hours,\(standHours),hours\n"
            }
            if let flights = snapshot.activity.flightsClimbed {
                csv += "\(snapshot.dateString),Activity,Flights Climbed,\(flights),count\n"
            }
            if let distance = snapshot.activity.walkingRunningDistanceMeters {
                csv += "\(snapshot.dateString),Activity,Walking Running Distance,\(distance),meters\n"
            }
            if let cycling = snapshot.activity.cyclingDistanceMeters {
                csv += "\(snapshot.dateString),Activity,Cycling Distance,\(cycling),meters\n"
            }
            if let swimming = snapshot.activity.swimmingDistanceMeters {
                csv += "\(snapshot.dateString),Activity,Swimming Distance,\(swimming),meters\n"
            }
            if let strokes = snapshot.activity.swimmingStrokes {
                csv += "\(snapshot.dateString),Activity,Swimming Strokes,\(strokes),count\n"
            }
            if let pushes = snapshot.activity.wheelchairPushes {
                csv += "\(snapshot.dateString),Activity,Wheelchair Pushes,\(pushes),count\n"
            }
            if let vo2 = snapshot.activity.vo2Max {
                csv += "\(snapshot.dateString),Activity,Cardio Fitness (VO2 Max),\(String(format: "%.1f", vo2)),mL/kg/min\n"
            }
        }

        // Heart
        if snapshot.heart.hasData {
            if let hr = snapshot.heart.restingHeartRate {
                csv += "\(snapshot.dateString),Heart,Resting Heart Rate,\(hr),bpm\n"
            }
            if let walkingHR = snapshot.heart.walkingHeartRateAverage {
                csv += "\(snapshot.dateString),Heart,Walking Heart Rate Average,\(walkingHR),bpm\n"
            }
            if let avgHR = snapshot.heart.averageHeartRate {
                csv += "\(snapshot.dateString),Heart,Average Heart Rate,\(avgHR),bpm\n"
            }
            if let minHR = snapshot.heart.minHeartRate {
                csv += "\(snapshot.dateString),Heart,Min Heart Rate,\(minHR),bpm\n"
            }
            if let maxHR = snapshot.heart.maxHeartRate {
                csv += "\(snapshot.dateString),Heart,Max Heart Rate,\(maxHR),bpm\n"
            }
            if let hrv = snapshot.heart.hrvMilliseconds {
                csv += "\(snapshot.dateString),Heart,HRV,\(hrv),ms\n"
            }
            if !snapshot.heart.heartRateSamples.isEmpty {
                let isoFormatter = ISO8601DateFormatter()
                for sample in snapshot.heart.heartRateSamples {
                    csv += "\(snapshot.dateString),Heart,Heart Rate Sample,\(sample.value),bpm,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
            if !snapshot.heart.hrvSamples.isEmpty {
                let isoFormatter = ISO8601DateFormatter()
                for sample in snapshot.heart.hrvSamples {
                    csv += "\(snapshot.dateString),Heart,HRV Sample,\(sample.value),ms,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
        }

        // Vitals (daily aggregates)
        if snapshot.vitals.hasData {
            if let rrAvg = snapshot.vitals.respiratoryRateAvg {
                csv += "\(snapshot.dateString),Vitals,Respiratory Rate Avg,\(rrAvg),breaths/min\n"
            }
            if let rrMin = snapshot.vitals.respiratoryRateMin {
                csv += "\(snapshot.dateString),Vitals,Respiratory Rate Min,\(rrMin),breaths/min\n"
            }
            if let rrMax = snapshot.vitals.respiratoryRateMax {
                csv += "\(snapshot.dateString),Vitals,Respiratory Rate Max,\(rrMax),breaths/min\n"
            }

            if let spo2Avg = snapshot.vitals.bloodOxygenAvg {
                csv += "\(snapshot.dateString),Vitals,Blood Oxygen Avg,\(spo2Avg * 100),percent\n"
            }
            if let spo2Min = snapshot.vitals.bloodOxygenMin {
                csv += "\(snapshot.dateString),Vitals,Blood Oxygen Min,\(spo2Min * 100),percent\n"
            }
            if let spo2Max = snapshot.vitals.bloodOxygenMax {
                csv += "\(snapshot.dateString),Vitals,Blood Oxygen Max,\(spo2Max * 100),percent\n"
            }

            if let tempAvg = snapshot.vitals.bodyTemperatureAvgCelsius {
                let convertedTemp = snapshot.converter.convertTemperature(tempAvg)
                csv += "\(snapshot.dateString),Vitals,Body Temperature Avg,\(String(format: "%.1f", convertedTemp)),\(tempUnit)\n"
            }
            if let tempMin = snapshot.vitals.bodyTemperatureMinCelsius {
                let convertedTemp = snapshot.converter.convertTemperature(tempMin)
                csv += "\(snapshot.dateString),Vitals,Body Temperature Min,\(String(format: "%.1f", convertedTemp)),\(tempUnit)\n"
            }
            if let tempMax = snapshot.vitals.bodyTemperatureMaxCelsius {
                let convertedTemp = snapshot.converter.convertTemperature(tempMax)
                csv += "\(snapshot.dateString),Vitals,Body Temperature Max,\(String(format: "%.1f", convertedTemp)),\(tempUnit)\n"
            }

            if let systolicAvg = snapshot.vitals.bloodPressureSystolicAvg {
                csv += "\(snapshot.dateString),Vitals,Blood Pressure Systolic Avg,\(systolicAvg),mmHg\n"
            }
            if let systolicMin = snapshot.vitals.bloodPressureSystolicMin {
                csv += "\(snapshot.dateString),Vitals,Blood Pressure Systolic Min,\(systolicMin),mmHg\n"
            }
            if let systolicMax = snapshot.vitals.bloodPressureSystolicMax {
                csv += "\(snapshot.dateString),Vitals,Blood Pressure Systolic Max,\(systolicMax),mmHg\n"
            }

            if let diastolicAvg = snapshot.vitals.bloodPressureDiastolicAvg {
                csv += "\(snapshot.dateString),Vitals,Blood Pressure Diastolic Avg,\(diastolicAvg),mmHg\n"
            }
            if let diastolicMin = snapshot.vitals.bloodPressureDiastolicMin {
                csv += "\(snapshot.dateString),Vitals,Blood Pressure Diastolic Min,\(diastolicMin),mmHg\n"
            }
            if let diastolicMax = snapshot.vitals.bloodPressureDiastolicMax {
                csv += "\(snapshot.dateString),Vitals,Blood Pressure Diastolic Max,\(diastolicMax),mmHg\n"
            }

            if let glucoseAvg = snapshot.vitals.bloodGlucoseAvg {
                csv += "\(snapshot.dateString),Vitals,Blood Glucose Avg,\(glucoseAvg),mg/dL\n"
            }
            if let glucoseMin = snapshot.vitals.bloodGlucoseMin {
                csv += "\(snapshot.dateString),Vitals,Blood Glucose Min,\(glucoseMin),mg/dL\n"
            }
            if let glucoseMax = snapshot.vitals.bloodGlucoseMax {
                csv += "\(snapshot.dateString),Vitals,Blood Glucose Max,\(glucoseMax),mg/dL\n"
            }
            let isoFormatter = ISO8601DateFormatter()
            if !snapshot.vitals.bloodOxygenSamples.isEmpty {
                for sample in snapshot.vitals.bloodOxygenSamples {
                    csv += "\(snapshot.dateString),Vitals,Blood Oxygen Sample,\(sample.value * 100),percent,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
            if !snapshot.vitals.bloodGlucoseSamples.isEmpty {
                for sample in snapshot.vitals.bloodGlucoseSamples {
                    csv += "\(snapshot.dateString),Vitals,Blood Glucose Sample,\(sample.value),mg/dL,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
            if !snapshot.vitals.respiratoryRateSamples.isEmpty {
                for sample in snapshot.vitals.respiratoryRateSamples {
                    csv += "\(snapshot.dateString),Vitals,Respiratory Rate Sample,\(sample.value),breaths/min,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
        }

        // Body
        if snapshot.body.hasData {
            if let weight = snapshot.body.weightKg {
                let convertedWeight = snapshot.converter.convertWeight(weight)
                csv += "\(snapshot.dateString),Body,Weight,\(String(format: "%.1f", convertedWeight)),\(weightUnit)\n"
            }
            if let height = snapshot.body.heightMeters {
                let convertedHeight = snapshot.converter.convertHeight(height)
                csv += "\(snapshot.dateString),Body,Height,\(String(format: "%.1f", convertedHeight)),\(snapshot.converter.heightUnit())\n"
            }
            if let bmi = snapshot.body.bmi {
                csv += "\(snapshot.dateString),Body,BMI,\(bmi),\n"
            }
            if let bodyFat = snapshot.body.bodyFatRatio {
                csv += "\(snapshot.dateString),Body,Body Fat Percentage,\(bodyFat * 100),percent\n"
            }
            if let lean = snapshot.body.leanBodyMassKg {
                let convertedLean = snapshot.converter.convertWeight(lean)
                csv += "\(snapshot.dateString),Body,Lean Body Mass,\(String(format: "%.1f", convertedLean)),\(weightUnit)\n"
            }
            if let waist = snapshot.body.waistCircumferenceMeters {
                csv += "\(snapshot.dateString),Body,Waist Circumference,\(snapshot.converter.formatLength(waist)),\(snapshot.converter.lengthUnit())\n"
            }
        }

        // Nutrition
        if snapshot.nutrition.hasData {
            if let energy = snapshot.nutrition.dietaryEnergyKcal {
                csv += "\(snapshot.dateString),Nutrition,Dietary Energy,\(energy),kcal\n"
            }
            if let protein = snapshot.nutrition.proteinGrams {
                csv += "\(snapshot.dateString),Nutrition,Protein,\(protein),g\n"
            }
            if let carbs = snapshot.nutrition.carbohydratesGrams {
                csv += "\(snapshot.dateString),Nutrition,Carbohydrates,\(carbs),g\n"
            }
            if let fat = snapshot.nutrition.fatGrams {
                csv += "\(snapshot.dateString),Nutrition,Fat,\(fat),g\n"
            }
            if let saturatedFat = snapshot.nutrition.saturatedFatGrams {
                csv += "\(snapshot.dateString),Nutrition,Saturated Fat,\(saturatedFat),g\n"
            }
            if let fiber = snapshot.nutrition.fiberGrams {
                csv += "\(snapshot.dateString),Nutrition,Fiber,\(fiber),g\n"
            }
            if let sugar = snapshot.nutrition.sugarGrams {
                csv += "\(snapshot.dateString),Nutrition,Sugar,\(sugar),g\n"
            }
            if let sodium = snapshot.nutrition.sodiumMg {
                csv += "\(snapshot.dateString),Nutrition,Sodium,\(sodium),mg\n"
            }
            if let cholesterol = snapshot.nutrition.cholesterolMg {
                csv += "\(snapshot.dateString),Nutrition,Cholesterol,\(cholesterol),mg\n"
            }
            if let water = snapshot.nutrition.waterLiters {
                csv += "\(snapshot.dateString),Nutrition,Water,\(water),L\n"
            }
            if let caffeine = snapshot.nutrition.caffeineMg {
                csv += "\(snapshot.dateString),Nutrition,Caffeine,\(caffeine),mg\n"
            }
        }

        // Mindfulness
        if snapshot.mindfulness.hasData {
            if let minutes = snapshot.mindfulness.mindfulMinutes {
                csv += "\(snapshot.dateString),Mindfulness,Mindful Minutes,\(minutes),minutes\n"
            }
            if let sessions = snapshot.mindfulness.mindfulSessions {
                csv += "\(snapshot.dateString),Mindfulness,Mindful Sessions,\(sessions),count\n"
            }

            if !snapshot.mindfulness.stateOfMindEntries.isEmpty {
                csv += "\(snapshot.dateString),Mindfulness,State of Mind Entries,\(snapshot.mindfulness.stateOfMindEntries.count),count\n"

                if let avgValence = snapshot.mindfulness.averageValence,
                   let valencePercent = snapshot.mindfulness.averageValencePercent {
                    csv += "\(snapshot.dateString),Mindfulness,Average Mood Valence,\(String(format: "%.2f", avgValence)),scale(-1 to 1)\n"
                    csv += "\(snapshot.dateString),Mindfulness,Average Mood Percent,\(valencePercent),percent\n"
                }

                if !snapshot.mindfulness.dailyMoods.isEmpty {
                    csv += "\(snapshot.dateString),Mindfulness,Daily Mood Count,\(snapshot.mindfulness.dailyMoods.count),count\n"
                }

                if !snapshot.mindfulness.momentaryEmotions.isEmpty {
                    csv += "\(snapshot.dateString),Mindfulness,Momentary Emotion Count,\(snapshot.mindfulness.momentaryEmotions.count),count\n"
                }

                for entry in snapshot.mindfulness.stateOfMindEntries {
                    let timeStr = snapshot.timeFormat.format(date: entry.timestamp)
                    let labelsStr = entry.labels.joined(separator: "; ").replacingOccurrences(of: ",", with: ";")
                    let associationsStr = entry.associations.joined(separator: "; ").replacingOccurrences(of: ",", with: ";")

                    csv += "\(snapshot.dateString),State of Mind,\(entry.kind.rawValue) at \(timeStr),\(String(format: "%.2f", entry.valence)),valence\n"
                    if !labelsStr.isEmpty {
                        csv += "\(snapshot.dateString),State of Mind,\(entry.kind.rawValue) Labels at \(timeStr),\"\(labelsStr)\",labels\n"
                    }
                    if !associationsStr.isEmpty {
                        csv += "\(snapshot.dateString),State of Mind,\(entry.kind.rawValue) Associations at \(timeStr),\"\(associationsStr)\",associations\n"
                    }
                }
            }
        }

        // Mobility
        if snapshot.mobility.hasData {
            if let speed = snapshot.mobility.walkingSpeedMps {
                csv += "\(snapshot.dateString),Mobility,Walking Speed,\(speed),m/s\n"
            }
            if let stepLength = snapshot.mobility.walkingStepLengthMeters {
                csv += "\(snapshot.dateString),Mobility,Walking Step Length,\(stepLength),meters\n"
            }
            if let doubleSupport = snapshot.mobility.walkingDoubleSupportRatio {
                csv += "\(snapshot.dateString),Mobility,Double Support Percentage,\(doubleSupport * 100),percent\n"
            }
            if let asymmetry = snapshot.mobility.walkingAsymmetryRatio {
                csv += "\(snapshot.dateString),Mobility,Walking Asymmetry,\(asymmetry * 100),percent\n"
            }
            if let ascent = snapshot.mobility.stairAscentSpeedMps {
                csv += "\(snapshot.dateString),Mobility,Stair Ascent Speed,\(ascent),m/s\n"
            }
            if let descent = snapshot.mobility.stairDescentSpeedMps {
                csv += "\(snapshot.dateString),Mobility,Stair Descent Speed,\(descent),m/s\n"
            }
            if let sixMin = snapshot.mobility.sixMinuteWalkDistanceMeters {
                csv += "\(snapshot.dateString),Mobility,Six Minute Walk Distance,\(sixMin),meters\n"
            }
        }

        // Hearing
        if snapshot.hearing.hasData {
            if let headphone = snapshot.hearing.headphoneAudioLevelDb {
                csv += "\(snapshot.dateString),Hearing,Headphone Audio Level,\(headphone),dB\n"
            }
            if let environmental = snapshot.hearing.environmentalSoundLevelDb {
                csv += "\(snapshot.dateString),Hearing,Environmental Sound Level,\(environmental),dB\n"
            }
        }

        // Workouts
        if !snapshot.workouts.isEmpty {
            for workout in snapshot.workouts {
                let startTimeString = snapshot.timeFormat.format(date: workout.startTime)
                csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Start Time,\(startTimeString),time\n"
                csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Duration,\(workout.duration),seconds\n"
                if let distance = workout.distance, distance > 0 {
                    let convertedDistance = snapshot.converter.convertDistance(distance)
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Distance,\(String(format: "%.2f", convertedDistance)),\(distanceUnit)\n"
                }
                if let calories = workout.calories, calories > 0 {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Calories,\(calories),kcal\n"
                }
            }
        }

        return csv
    }
}
