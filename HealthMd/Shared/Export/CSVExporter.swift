import Foundation

// MARK: - CSV Export

extension HealthData {
    func toCSV(customization: FormatCustomization? = nil) -> String {
        let config = customization ?? FormatCustomization()
        let dateString = config.dateFormat.format(date: date)
        let converter = config.unitConverter
        
        let distanceUnit = converter.distanceUnit()
        let weightUnit = converter.weightUnit()
        let tempUnit = converter.temperatureUnit()

        var csv = "Date,Category,Metric,Value,Unit\n"

        // Sleep
        if sleep.hasData {
            if sleep.totalDuration > 0 {
                csv += "\(dateString),Sleep,Total Duration,\(sleep.totalDuration),seconds\n"
            }
            if sleep.deepSleep > 0 {
                csv += "\(dateString),Sleep,Deep Sleep,\(sleep.deepSleep),seconds\n"
            }
            if sleep.remSleep > 0 {
                csv += "\(dateString),Sleep,REM Sleep,\(sleep.remSleep),seconds\n"
            }
            if sleep.coreSleep > 0 {
                csv += "\(dateString),Sleep,Core Sleep,\(sleep.coreSleep),seconds\n"
            }
            if sleep.awakeTime > 0 {
                csv += "\(dateString),Sleep,Awake Time,\(sleep.awakeTime),seconds\n"
            }
            if sleep.inBedTime > 0 {
                csv += "\(dateString),Sleep,In Bed Time,\(sleep.inBedTime),seconds\n"
            }
        }

        // Activity
        if activity.hasData {
            if let steps = activity.steps {
                csv += "\(dateString),Activity,Steps,\(steps),count\n"
            }
            if let calories = activity.activeCalories {
                csv += "\(dateString),Activity,Active Calories,\(calories),kcal\n"
            }
            if let basal = activity.basalEnergyBurned {
                csv += "\(dateString),Activity,Basal Energy,\(basal),kcal\n"
            }
            if let exercise = activity.exerciseMinutes {
                csv += "\(dateString),Activity,Exercise Minutes,\(exercise),minutes\n"
            }
            if let standHours = activity.standHours {
                csv += "\(dateString),Activity,Stand Hours,\(standHours),hours\n"
            }
            if let flights = activity.flightsClimbed {
                csv += "\(dateString),Activity,Flights Climbed,\(flights),count\n"
            }
            if let distance = activity.walkingRunningDistance {
                csv += "\(dateString),Activity,Walking Running Distance,\(distance),meters\n"
            }
            if let cycling = activity.cyclingDistance {
                csv += "\(dateString),Activity,Cycling Distance,\(cycling),meters\n"
            }
            if let swimming = activity.swimmingDistance {
                csv += "\(dateString),Activity,Swimming Distance,\(swimming),meters\n"
            }
            if let strokes = activity.swimmingStrokes {
                csv += "\(dateString),Activity,Swimming Strokes,\(strokes),count\n"
            }
            if let pushes = activity.pushCount {
                csv += "\(dateString),Activity,Wheelchair Pushes,\(pushes),count\n"
            }
        }

        // Heart
        if heart.hasData {
            if let hr = heart.restingHeartRate {
                csv += "\(dateString),Heart,Resting Heart Rate,\(hr),bpm\n"
            }
            if let walkingHR = heart.walkingHeartRateAverage {
                csv += "\(dateString),Heart,Walking Heart Rate Average,\(walkingHR),bpm\n"
            }
            if let avgHR = heart.averageHeartRate {
                csv += "\(dateString),Heart,Average Heart Rate,\(avgHR),bpm\n"
            }
            if let minHR = heart.heartRateMin {
                csv += "\(dateString),Heart,Min Heart Rate,\(minHR),bpm\n"
            }
            if let maxHR = heart.heartRateMax {
                csv += "\(dateString),Heart,Max Heart Rate,\(maxHR),bpm\n"
            }
            if let hrv = heart.hrv {
                csv += "\(dateString),Heart,HRV,\(hrv),ms\n"
            }
        }

        // Vitals (daily aggregates)
        if vitals.hasData {
            // Respiratory Rate
            if let rrAvg = vitals.respiratoryRateAvg {
                csv += "\(dateString),Vitals,Respiratory Rate Avg,\(rrAvg),breaths/min\n"
            }
            if let rrMin = vitals.respiratoryRateMin {
                csv += "\(dateString),Vitals,Respiratory Rate Min,\(rrMin),breaths/min\n"
            }
            if let rrMax = vitals.respiratoryRateMax {
                csv += "\(dateString),Vitals,Respiratory Rate Max,\(rrMax),breaths/min\n"
            }
            
            // Blood Oxygen / SpO2
            if let spo2Avg = vitals.bloodOxygenAvg {
                csv += "\(dateString),Vitals,Blood Oxygen Avg,\(spo2Avg * 100),percent\n"
            }
            if let spo2Min = vitals.bloodOxygenMin {
                csv += "\(dateString),Vitals,Blood Oxygen Min,\(spo2Min * 100),percent\n"
            }
            if let spo2Max = vitals.bloodOxygenMax {
                csv += "\(dateString),Vitals,Blood Oxygen Max,\(spo2Max * 100),percent\n"
            }
            
            // Body Temperature
            if let tempAvg = vitals.bodyTemperatureAvg {
                let convertedTemp = converter.convertTemperature(tempAvg)
                csv += "\(dateString),Vitals,Body Temperature Avg,\(String(format: "%.1f", convertedTemp)),\(tempUnit)\n"
            }
            if let tempMin = vitals.bodyTemperatureMin {
                let convertedTemp = converter.convertTemperature(tempMin)
                csv += "\(dateString),Vitals,Body Temperature Min,\(String(format: "%.1f", convertedTemp)),\(tempUnit)\n"
            }
            if let tempMax = vitals.bodyTemperatureMax {
                let convertedTemp = converter.convertTemperature(tempMax)
                csv += "\(dateString),Vitals,Body Temperature Max,\(String(format: "%.1f", convertedTemp)),\(tempUnit)\n"
            }
            
            // Blood Pressure Systolic
            if let systolicAvg = vitals.bloodPressureSystolicAvg {
                csv += "\(dateString),Vitals,Blood Pressure Systolic Avg,\(systolicAvg),mmHg\n"
            }
            if let systolicMin = vitals.bloodPressureSystolicMin {
                csv += "\(dateString),Vitals,Blood Pressure Systolic Min,\(systolicMin),mmHg\n"
            }
            if let systolicMax = vitals.bloodPressureSystolicMax {
                csv += "\(dateString),Vitals,Blood Pressure Systolic Max,\(systolicMax),mmHg\n"
            }
            
            // Blood Pressure Diastolic
            if let diastolicAvg = vitals.bloodPressureDiastolicAvg {
                csv += "\(dateString),Vitals,Blood Pressure Diastolic Avg,\(diastolicAvg),mmHg\n"
            }
            if let diastolicMin = vitals.bloodPressureDiastolicMin {
                csv += "\(dateString),Vitals,Blood Pressure Diastolic Min,\(diastolicMin),mmHg\n"
            }
            if let diastolicMax = vitals.bloodPressureDiastolicMax {
                csv += "\(dateString),Vitals,Blood Pressure Diastolic Max,\(diastolicMax),mmHg\n"
            }
            
            // Blood Glucose
            if let glucoseAvg = vitals.bloodGlucoseAvg {
                csv += "\(dateString),Vitals,Blood Glucose Avg,\(glucoseAvg),mg/dL\n"
            }
            if let glucoseMin = vitals.bloodGlucoseMin {
                csv += "\(dateString),Vitals,Blood Glucose Min,\(glucoseMin),mg/dL\n"
            }
            if let glucoseMax = vitals.bloodGlucoseMax {
                csv += "\(dateString),Vitals,Blood Glucose Max,\(glucoseMax),mg/dL\n"
            }
        }

        // Body
        if body.hasData {
            if let weight = body.weight {
                let convertedWeight = converter.convertWeight(weight)
                csv += "\(dateString),Body,Weight,\(String(format: "%.1f", convertedWeight)),\(weightUnit)\n"
            }
            if let height = body.height {
                let convertedHeight = converter.convertHeight(height)
                csv += "\(dateString),Body,Height,\(String(format: "%.1f", convertedHeight)),\(converter.heightUnit())\n"
            }
            if let bmi = body.bmi {
                csv += "\(dateString),Body,BMI,\(bmi),\n"
            }
            if let bodyFat = body.bodyFatPercentage {
                csv += "\(dateString),Body,Body Fat Percentage,\(bodyFat * 100),percent\n"
            }
            if let lean = body.leanBodyMass {
                let convertedLean = converter.convertWeight(lean)
                csv += "\(dateString),Body,Lean Body Mass,\(String(format: "%.1f", convertedLean)),\(weightUnit)\n"
            }
            if let waist = body.waistCircumference {
                csv += "\(dateString),Body,Waist Circumference,\(converter.formatLength(waist)),\(converter.lengthUnit())\n"
            }
        }

        // Nutrition
        if nutrition.hasData {
            if let energy = nutrition.dietaryEnergy {
                csv += "\(dateString),Nutrition,Dietary Energy,\(energy),kcal\n"
            }
            if let protein = nutrition.protein {
                csv += "\(dateString),Nutrition,Protein,\(protein),g\n"
            }
            if let carbs = nutrition.carbohydrates {
                csv += "\(dateString),Nutrition,Carbohydrates,\(carbs),g\n"
            }
            if let fat = nutrition.fat {
                csv += "\(dateString),Nutrition,Fat,\(fat),g\n"
            }
            if let saturatedFat = nutrition.saturatedFat {
                csv += "\(dateString),Nutrition,Saturated Fat,\(saturatedFat),g\n"
            }
            if let fiber = nutrition.fiber {
                csv += "\(dateString),Nutrition,Fiber,\(fiber),g\n"
            }
            if let sugar = nutrition.sugar {
                csv += "\(dateString),Nutrition,Sugar,\(sugar),g\n"
            }
            if let sodium = nutrition.sodium {
                csv += "\(dateString),Nutrition,Sodium,\(sodium),mg\n"
            }
            if let cholesterol = nutrition.cholesterol {
                csv += "\(dateString),Nutrition,Cholesterol,\(cholesterol),mg\n"
            }
            if let water = nutrition.water {
                csv += "\(dateString),Nutrition,Water,\(water),L\n"
            }
            if let caffeine = nutrition.caffeine {
                csv += "\(dateString),Nutrition,Caffeine,\(caffeine),mg\n"
            }
        }

        // Mindfulness
        if mindfulness.hasData {
            if let minutes = mindfulness.mindfulMinutes {
                csv += "\(dateString),Mindfulness,Mindful Minutes,\(minutes),minutes\n"
            }
            if let sessions = mindfulness.mindfulSessions {
                csv += "\(dateString),Mindfulness,Mindful Sessions,\(sessions),count\n"
            }
            
            // State of Mind data
            if !mindfulness.stateOfMind.isEmpty {
                csv += "\(dateString),Mindfulness,State of Mind Entries,\(mindfulness.stateOfMind.count),count\n"
                
                if let avgValence = mindfulness.averageValence {
                    csv += "\(dateString),Mindfulness,Average Mood Valence,\(String(format: "%.2f", avgValence)),scale(-1 to 1)\n"
                    let valencePercent = Int(((avgValence + 1.0) / 2.0) * 100)
                    csv += "\(dateString),Mindfulness,Average Mood Percent,\(valencePercent),percent\n"
                }
                
                if !mindfulness.dailyMoods.isEmpty {
                    csv += "\(dateString),Mindfulness,Daily Mood Count,\(mindfulness.dailyMoods.count),count\n"
                }
                
                if !mindfulness.momentaryEmotions.isEmpty {
                    csv += "\(dateString),Mindfulness,Momentary Emotion Count,\(mindfulness.momentaryEmotions.count),count\n"
                }
                
                // Individual entries
                for entry in mindfulness.stateOfMind {
                    let timeStr = config.timeFormat.format(date: entry.timestamp)
                    let labelsStr = entry.labels.joined(separator: "; ").replacingOccurrences(of: ",", with: ";")
                    let associationsStr = entry.associations.joined(separator: "; ").replacingOccurrences(of: ",", with: ";")
                    
                    csv += "\(dateString),State of Mind,\(entry.kind.rawValue) at \(timeStr),\(String(format: "%.2f", entry.valence)),valence\n"
                    if !labelsStr.isEmpty {
                        csv += "\(dateString),State of Mind,\(entry.kind.rawValue) Labels at \(timeStr),\"\(labelsStr)\",labels\n"
                    }
                    if !associationsStr.isEmpty {
                        csv += "\(dateString),State of Mind,\(entry.kind.rawValue) Associations at \(timeStr),\"\(associationsStr)\",associations\n"
                    }
                }
            }
        }

        // Mobility
        if mobility.hasData {
            if let speed = mobility.walkingSpeed {
                csv += "\(dateString),Mobility,Walking Speed,\(speed),m/s\n"
            }
            if let stepLength = mobility.walkingStepLength {
                csv += "\(dateString),Mobility,Walking Step Length,\(stepLength),meters\n"
            }
            if let doubleSupport = mobility.walkingDoubleSupportPercentage {
                csv += "\(dateString),Mobility,Double Support Percentage,\(doubleSupport * 100),percent\n"
            }
            if let asymmetry = mobility.walkingAsymmetryPercentage {
                csv += "\(dateString),Mobility,Walking Asymmetry,\(asymmetry * 100),percent\n"
            }
            if let ascent = mobility.stairAscentSpeed {
                csv += "\(dateString),Mobility,Stair Ascent Speed,\(ascent),m/s\n"
            }
            if let descent = mobility.stairDescentSpeed {
                csv += "\(dateString),Mobility,Stair Descent Speed,\(descent),m/s\n"
            }
            if let sixMin = mobility.sixMinuteWalkDistance {
                csv += "\(dateString),Mobility,Six Minute Walk Distance,\(sixMin),meters\n"
            }
        }

        // Hearing
        if hearing.hasData {
            if let headphone = hearing.headphoneAudioLevel {
                csv += "\(dateString),Hearing,Headphone Audio Level,\(headphone),dB\n"
            }
            if let environmental = hearing.environmentalSoundLevel {
                csv += "\(dateString),Hearing,Environmental Sound Level,\(environmental),dB\n"
            }
        }

        // Workouts
        if !workouts.isEmpty {
            for workout in workouts {
                let startTimeString = config.timeFormat.format(date: workout.startTime)
                csv += "\(dateString),Workouts,\(workout.workoutTypeName) Start Time,\(startTimeString),time\n"
                csv += "\(dateString),Workouts,\(workout.workoutTypeName) Duration,\(workout.duration),seconds\n"
                if let distance = workout.distance, distance > 0 {
                    let convertedDistance = converter.convertDistance(distance)
                    csv += "\(dateString),Workouts,\(workout.workoutTypeName) Distance,\(String(format: "%.2f", convertedDistance)),\(distanceUnit)\n"
                }
                if let calories = workout.calories, calories > 0 {
                    csv += "\(dateString),Workouts,\(workout.workoutTypeName) Calories,\(calories),kcal\n"
                }
            }
        }

        return csv
    }
}
