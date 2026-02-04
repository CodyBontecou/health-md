import Foundation
import HealthKit

// MARK: - Sleep Data

struct SleepData {
    var totalDuration: TimeInterval = 0
    var deepSleep: TimeInterval = 0
    var remSleep: TimeInterval = 0
    var coreSleep: TimeInterval = 0
    var awakeTime: TimeInterval = 0
    var inBedTime: TimeInterval = 0

    var hasData: Bool {
        totalDuration > 0 || deepSleep > 0 || remSleep > 0 || coreSleep > 0 || awakeTime > 0 || inBedTime > 0
    }
}

// MARK: - Activity Data

struct ActivityData {
    var steps: Int?
    var activeCalories: Double?
    var exerciseMinutes: Double?
    var flightsClimbed: Int?
    var walkingRunningDistance: Double? // in meters
    var standHours: Int?
    var basalEnergyBurned: Double?
    var cyclingDistance: Double? // in meters
    var swimmingDistance: Double? // in meters
    var swimmingStrokes: Int?
    var pushCount: Int? // wheelchair users

    var hasData: Bool {
        steps != nil || activeCalories != nil || exerciseMinutes != nil ||
        flightsClimbed != nil || walkingRunningDistance != nil ||
        standHours != nil || basalEnergyBurned != nil ||
        cyclingDistance != nil || swimmingDistance != nil ||
        swimmingStrokes != nil || pushCount != nil
    }
}

// MARK: - Heart Data

struct HeartData {
    var restingHeartRate: Double?
    var walkingHeartRateAverage: Double?
    var averageHeartRate: Double?
    var hrv: Double? // in milliseconds
    var heartRateMin: Double?
    var heartRateMax: Double?

    var hasData: Bool {
        restingHeartRate != nil || walkingHeartRateAverage != nil ||
        averageHeartRate != nil || hrv != nil ||
        heartRateMin != nil || heartRateMax != nil
    }
}

// MARK: - Vitals Data

struct VitalsData {
    var respiratoryRate: Double?
    var bloodOxygen: Double? // as percentage
    var bodyTemperature: Double? // in Celsius
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var bloodGlucose: Double? // mg/dL

    var hasData: Bool {
        respiratoryRate != nil || bloodOxygen != nil ||
        bodyTemperature != nil || bloodPressureSystolic != nil ||
        bloodPressureDiastolic != nil || bloodGlucose != nil
    }
}

// MARK: - Body Data

struct BodyData {
    var weight: Double? // in kg
    var bodyFatPercentage: Double?
    var height: Double? // in meters
    var bmi: Double?
    var leanBodyMass: Double? // in kg
    var waistCircumference: Double? // in meters

    var hasData: Bool {
        weight != nil || bodyFatPercentage != nil || height != nil ||
        bmi != nil || leanBodyMass != nil || waistCircumference != nil
    }
}

// MARK: - Nutrition Data

struct NutritionData {
    var dietaryEnergy: Double? // kcal
    var protein: Double? // grams
    var carbohydrates: Double? // grams
    var fat: Double? // grams
    var fiber: Double? // grams
    var sugar: Double? // grams
    var sodium: Double? // mg
    var water: Double? // liters
    var caffeine: Double? // mg
    var cholesterol: Double? // mg
    var saturatedFat: Double? // grams

    var hasData: Bool {
        dietaryEnergy != nil || protein != nil || carbohydrates != nil ||
        fat != nil || fiber != nil || sugar != nil || sodium != nil ||
        water != nil || caffeine != nil || cholesterol != nil || saturatedFat != nil
    }
}

// MARK: - Mindfulness Data

struct MindfulnessData {
    var mindfulMinutes: Double?
    var mindfulSessions: Int?

    var hasData: Bool {
        mindfulMinutes != nil || mindfulSessions != nil
    }
}

// MARK: - Mobility Data

struct MobilityData {
    var walkingSpeed: Double? // m/s
    var walkingStepLength: Double? // meters
    var walkingDoubleSupportPercentage: Double?
    var walkingAsymmetryPercentage: Double?
    var stairAscentSpeed: Double? // m/s
    var stairDescentSpeed: Double? // m/s
    var sixMinuteWalkDistance: Double? // meters

    var hasData: Bool {
        walkingSpeed != nil || walkingStepLength != nil ||
        walkingDoubleSupportPercentage != nil || walkingAsymmetryPercentage != nil ||
        stairAscentSpeed != nil || stairDescentSpeed != nil || sixMinuteWalkDistance != nil
    }
}

// MARK: - Hearing Data

struct HearingData {
    var headphoneAudioLevel: Double? // dB
    var environmentalSoundLevel: Double? // dB

    var hasData: Bool {
        headphoneAudioLevel != nil || environmentalSoundLevel != nil
    }
}

// MARK: - Workout Data

struct WorkoutData: Identifiable {
    let id = UUID()
    let workoutType: HKWorkoutActivityType
    let startTime: Date
    let duration: TimeInterval
    let calories: Double?
    let distance: Double? // in meters

    var workoutTypeName: String {
        switch workoutType {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .coreTraining: return "Core Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .mixedCardio: return "Mixed Cardio"
        case .socialDance: return "Social Dance"
        case .pickleball: return "Pickleball"
        case .tennis: return "Tennis"
        case .badminton: return "Badminton"
        case .tableTennis: return "Table Tennis"
        case .golf: return "Golf"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .baseball: return "Baseball"
        case .softball: return "Softball"
        case .volleyball: return "Volleyball"
        case .americanFootball: return "American Football"
        case .rugby: return "Rugby"
        case .hockey: return "Hockey"
        case .lacrosse: return "Lacrosse"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .waterSports: return "Water Sports"
        case .martialArts: return "Martial Arts"
        case .boxing: return "Boxing"
        case .kickboxing: return "Kickboxing"
        case .wrestling: return "Wrestling"
        case .climbing: return "Climbing"
        case .jumpRope: return "Jump Rope"
        case .mindAndBody: return "Mind & Body"
        case .flexibility: return "Flexibility"
        case .other: return "Other"
        default: return "Workout"
        }
    }
}

// MARK: - Complete Health Data

struct HealthData {
    let date: Date
    var sleep: SleepData = SleepData()
    var activity: ActivityData = ActivityData()
    var heart: HeartData = HeartData()
    var vitals: VitalsData = VitalsData()
    var body: BodyData = BodyData()
    var nutrition: NutritionData = NutritionData()
    var mindfulness: MindfulnessData = MindfulnessData()
    var mobility: MobilityData = MobilityData()
    var hearing: HearingData = HearingData()
    var workouts: [WorkoutData] = []

    var hasAnyData: Bool {
        sleep.hasData || activity.hasData || heart.hasData || vitals.hasData ||
        body.hasData || nutrition.hasData || mindfulness.hasData ||
        mobility.hasData || hearing.hasData || !workouts.isEmpty
    }
}

// MARK: - Export Formats

extension HealthData {
    func export(format: ExportFormat, settings: AdvancedExportSettings) -> String {
        let filteredData = self.filtered(by: settings.dataTypes)

        switch format {
        case .markdown:
            return filteredData.toMarkdown(
                includeMetadata: settings.includeMetadata,
                groupByCategory: settings.groupByCategory
            )
        case .obsidianBases:
            return filteredData.toObsidianBases()
        case .json:
            return filteredData.toJSON()
        case .csv:
            return filteredData.toCSV()
        }
    }

    func filtered(by dataTypes: DataTypeSelection) -> HealthData {
        var filtered = self

        if !dataTypes.sleep {
            filtered.sleep = SleepData()
        }
        if !dataTypes.activity {
            filtered.activity = ActivityData()
        }
        if !dataTypes.heart {
            filtered.heart = HeartData()
        }
        if !dataTypes.vitals {
            filtered.vitals = VitalsData()
        }
        if !dataTypes.body {
            filtered.body = BodyData()
        }
        if !dataTypes.nutrition {
            filtered.nutrition = NutritionData()
        }
        if !dataTypes.mindfulness {
            filtered.mindfulness = MindfulnessData()
        }
        if !dataTypes.mobility {
            filtered.mobility = MobilityData()
        }
        if !dataTypes.hearing {
            filtered.hearing = HearingData()
        }
        if !dataTypes.workouts {
            filtered.workouts = []
        }

        return filtered
    }
}

// MARK: - Markdown Export

extension HealthData {
    func toMarkdown(includeMetadata: Bool = true, groupByCategory: Bool = true) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        var markdown = ""

        if includeMetadata {
            markdown += """
            ---
            date: \(dateString)
            type: health-data
            ---

            """
        }

        markdown += "# Health Data — \(dateString)\n\n"

        // Sleep Section
        if sleep.hasData {
            markdown += "\n## Sleep\n\n"
            if sleep.totalDuration > 0 {
                markdown += "- **Total:** \(formatDuration(sleep.totalDuration))\n"
            }
            if sleep.inBedTime > 0 {
                markdown += "- **In Bed:** \(formatDuration(sleep.inBedTime))\n"
            }
            if sleep.deepSleep > 0 {
                markdown += "- **Deep:** \(formatDuration(sleep.deepSleep))\n"
            }
            if sleep.remSleep > 0 {
                markdown += "- **REM:** \(formatDuration(sleep.remSleep))\n"
            }
            if sleep.coreSleep > 0 {
                markdown += "- **Core:** \(formatDuration(sleep.coreSleep))\n"
            }
            if sleep.awakeTime > 0 {
                markdown += "- **Awake:** \(formatDuration(sleep.awakeTime))\n"
            }
        }

        // Activity Section
        if activity.hasData {
            markdown += "\n## Activity\n\n"
            if let steps = activity.steps {
                markdown += "- **Steps:** \(formatNumber(steps))\n"
            }
            if let calories = activity.activeCalories {
                markdown += "- **Active Calories:** \(formatNumber(Int(calories))) kcal\n"
            }
            if let basal = activity.basalEnergyBurned {
                markdown += "- **Basal Energy:** \(formatNumber(Int(basal))) kcal\n"
            }
            if let exercise = activity.exerciseMinutes {
                markdown += "- **Exercise:** \(Int(exercise)) min\n"
            }
            if let standHours = activity.standHours {
                markdown += "- **Stand Hours:** \(standHours)\n"
            }
            if let flights = activity.flightsClimbed {
                markdown += "- **Flights Climbed:** \(flights)\n"
            }
            if let distance = activity.walkingRunningDistance {
                markdown += "- **Walking/Running Distance:** \(formatDistance(distance))\n"
            }
            if let cycling = activity.cyclingDistance {
                markdown += "- **Cycling Distance:** \(formatDistance(cycling))\n"
            }
            if let swimming = activity.swimmingDistance {
                markdown += "- **Swimming Distance:** \(formatDistance(swimming))\n"
            }
            if let strokes = activity.swimmingStrokes {
                markdown += "- **Swimming Strokes:** \(formatNumber(strokes))\n"
            }
            if let pushes = activity.pushCount {
                markdown += "- **Wheelchair Pushes:** \(formatNumber(pushes))\n"
            }
        }

        // Heart Section
        if heart.hasData {
            markdown += "\n## Heart\n\n"
            if let hr = heart.restingHeartRate {
                markdown += "- **Resting HR:** \(Int(hr)) bpm\n"
            }
            if let walkingHR = heart.walkingHeartRateAverage {
                markdown += "- **Walking HR Average:** \(Int(walkingHR)) bpm\n"
            }
            if let avgHR = heart.averageHeartRate {
                markdown += "- **Average HR:** \(Int(avgHR)) bpm\n"
            }
            if let minHR = heart.heartRateMin {
                markdown += "- **Min HR:** \(Int(minHR)) bpm\n"
            }
            if let maxHR = heart.heartRateMax {
                markdown += "- **Max HR:** \(Int(maxHR)) bpm\n"
            }
            if let hrv = heart.hrv {
                markdown += "- **HRV:** \(String(format: "%.1f", hrv)) ms\n"
            }
        }

        // Vitals Section
        if vitals.hasData {
            markdown += "\n## Vitals\n\n"
            if let rr = vitals.respiratoryRate {
                markdown += "- **Respiratory Rate:** \(String(format: "%.1f", rr)) breaths/min\n"
            }
            if let spo2 = vitals.bloodOxygen {
                markdown += "- **SpO2:** \(Int(spo2 * 100))%\n"
            }
            if let temp = vitals.bodyTemperature {
                markdown += "- **Body Temperature:** \(String(format: "%.1f", temp))°C\n"
            }
            if let systolic = vitals.bloodPressureSystolic, let diastolic = vitals.bloodPressureDiastolic {
                markdown += "- **Blood Pressure:** \(Int(systolic))/\(Int(diastolic)) mmHg\n"
            }
            if let glucose = vitals.bloodGlucose {
                markdown += "- **Blood Glucose:** \(String(format: "%.1f", glucose)) mg/dL\n"
            }
        }

        // Body Section
        if body.hasData {
            markdown += "\n## Body\n\n"
            if let weight = body.weight {
                markdown += "- **Weight:** \(String(format: "%.1f", weight)) kg\n"
            }
            if let height = body.height {
                markdown += "- **Height:** \(String(format: "%.2f", height)) m\n"
            }
            if let bmi = body.bmi {
                markdown += "- **BMI:** \(String(format: "%.1f", bmi))\n"
            }
            if let bodyFat = body.bodyFatPercentage {
                markdown += "- **Body Fat:** \(String(format: "%.1f", bodyFat * 100))%\n"
            }
            if let lean = body.leanBodyMass {
                markdown += "- **Lean Body Mass:** \(String(format: "%.1f", lean)) kg\n"
            }
            if let waist = body.waistCircumference {
                markdown += "- **Waist Circumference:** \(String(format: "%.1f", waist * 100)) cm\n"
            }
        }

        // Nutrition Section
        if nutrition.hasData {
            markdown += "\n## Nutrition\n\n"
            if let energy = nutrition.dietaryEnergy {
                markdown += "- **Calories:** \(formatNumber(Int(energy))) kcal\n"
            }
            if let protein = nutrition.protein {
                markdown += "- **Protein:** \(String(format: "%.1f", protein)) g\n"
            }
            if let carbs = nutrition.carbohydrates {
                markdown += "- **Carbohydrates:** \(String(format: "%.1f", carbs)) g\n"
            }
            if let fat = nutrition.fat {
                markdown += "- **Fat:** \(String(format: "%.1f", fat)) g\n"
            }
            if let saturatedFat = nutrition.saturatedFat {
                markdown += "- **Saturated Fat:** \(String(format: "%.1f", saturatedFat)) g\n"
            }
            if let fiber = nutrition.fiber {
                markdown += "- **Fiber:** \(String(format: "%.1f", fiber)) g\n"
            }
            if let sugar = nutrition.sugar {
                markdown += "- **Sugar:** \(String(format: "%.1f", sugar)) g\n"
            }
            if let sodium = nutrition.sodium {
                markdown += "- **Sodium:** \(formatNumber(Int(sodium))) mg\n"
            }
            if let cholesterol = nutrition.cholesterol {
                markdown += "- **Cholesterol:** \(String(format: "%.1f", cholesterol)) mg\n"
            }
            if let water = nutrition.water {
                markdown += "- **Water:** \(String(format: "%.2f", water)) L\n"
            }
            if let caffeine = nutrition.caffeine {
                markdown += "- **Caffeine:** \(String(format: "%.1f", caffeine)) mg\n"
            }
        }

        // Mindfulness Section
        if mindfulness.hasData {
            markdown += "\n## Mindfulness\n\n"
            if let minutes = mindfulness.mindfulMinutes {
                markdown += "- **Mindful Minutes:** \(Int(minutes)) min\n"
            }
            if let sessions = mindfulness.mindfulSessions {
                markdown += "- **Sessions:** \(sessions)\n"
            }
        }

        // Mobility Section
        if mobility.hasData {
            markdown += "\n## Mobility\n\n"
            if let speed = mobility.walkingSpeed {
                markdown += "- **Walking Speed:** \(String(format: "%.2f", speed)) m/s\n"
            }
            if let stepLength = mobility.walkingStepLength {
                markdown += "- **Step Length:** \(String(format: "%.2f", stepLength * 100)) cm\n"
            }
            if let doubleSupport = mobility.walkingDoubleSupportPercentage {
                markdown += "- **Double Support:** \(String(format: "%.1f", doubleSupport * 100))%\n"
            }
            if let asymmetry = mobility.walkingAsymmetryPercentage {
                markdown += "- **Walking Asymmetry:** \(String(format: "%.1f", asymmetry * 100))%\n"
            }
            if let ascent = mobility.stairAscentSpeed {
                markdown += "- **Stair Ascent Speed:** \(String(format: "%.2f", ascent)) m/s\n"
            }
            if let descent = mobility.stairDescentSpeed {
                markdown += "- **Stair Descent Speed:** \(String(format: "%.2f", descent)) m/s\n"
            }
            if let sixMin = mobility.sixMinuteWalkDistance {
                markdown += "- **6-Min Walk Distance:** \(formatDistance(sixMin))\n"
            }
        }

        // Hearing Section
        if hearing.hasData {
            markdown += "\n## Hearing\n\n"
            if let headphone = hearing.headphoneAudioLevel {
                markdown += "- **Headphone Audio Level:** \(String(format: "%.1f", headphone)) dB\n"
            }
            if let environmental = hearing.environmentalSoundLevel {
                markdown += "- **Environmental Sound Level:** \(String(format: "%.1f", environmental)) dB\n"
            }
        }

        // Workouts Section
        if !workouts.isEmpty {
            markdown += "\n## Workouts\n"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"

            for (index, workout) in workouts.enumerated() {
                markdown += "\n### \(index + 1). \(workout.workoutTypeName)\n\n"
                markdown += "- **Time:** \(timeFormatter.string(from: workout.startTime))\n"
                markdown += "- **Duration:** \(formatDurationShort(workout.duration))\n"
                if let distance = workout.distance, distance > 0 {
                    markdown += "- **Distance:** \(formatDistance(distance))\n"
                }
                if let calories = workout.calories, calories > 0 {
                    markdown += "- **Calories:** \(Int(calories)) kcal\n"
                }
            }
        }

        return markdown
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatDurationShort(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

// MARK: - JSON Export

extension HealthData {
    func toJSON() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var json: [String: Any] = [
            "date": dateString,
            "type": "health-data"
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

        // Vitals
        if vitals.hasData {
            var vitalsDict: [String: Any] = [:]
            if let rr = vitals.respiratoryRate {
                vitalsDict["respiratoryRate"] = rr
            }
            if let spo2 = vitals.bloodOxygen {
                vitalsDict["bloodOxygen"] = spo2
                vitalsDict["bloodOxygenPercent"] = spo2 * 100
            }
            if let temp = vitals.bodyTemperature {
                vitalsDict["bodyTemperature"] = temp
            }
            if let systolic = vitals.bloodPressureSystolic {
                vitalsDict["bloodPressureSystolic"] = systolic
            }
            if let diastolic = vitals.bloodPressureDiastolic {
                vitalsDict["bloodPressureDiastolic"] = diastolic
            }
            if let glucose = vitals.bloodGlucose {
                vitalsDict["bloodGlucose"] = glucose
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
                    "startTime": timeFormatter.string(from: workout.startTime),
                    "duration": workout.duration,
                    "durationFormatted": formatDurationShort(workout.duration)
                ]
                if let distance = workout.distance, distance > 0 {
                    workoutDict["distance"] = distance
                    workoutDict["distanceKm"] = distance / 1000
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

// MARK: - CSV Export

extension HealthData {
    func toCSV() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

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

        // Vitals
        if vitals.hasData {
            if let rr = vitals.respiratoryRate {
                csv += "\(dateString),Vitals,Respiratory Rate,\(rr),breaths/min\n"
            }
            if let spo2 = vitals.bloodOxygen {
                csv += "\(dateString),Vitals,Blood Oxygen,\(spo2 * 100),percent\n"
            }
            if let temp = vitals.bodyTemperature {
                csv += "\(dateString),Vitals,Body Temperature,\(temp),celsius\n"
            }
            if let systolic = vitals.bloodPressureSystolic {
                csv += "\(dateString),Vitals,Blood Pressure Systolic,\(systolic),mmHg\n"
            }
            if let diastolic = vitals.bloodPressureDiastolic {
                csv += "\(dateString),Vitals,Blood Pressure Diastolic,\(diastolic),mmHg\n"
            }
            if let glucose = vitals.bloodGlucose {
                csv += "\(dateString),Vitals,Blood Glucose,\(glucose),mg/dL\n"
            }
        }

        // Body
        if body.hasData {
            if let weight = body.weight {
                csv += "\(dateString),Body,Weight,\(weight),kg\n"
            }
            if let height = body.height {
                csv += "\(dateString),Body,Height,\(height),meters\n"
            }
            if let bmi = body.bmi {
                csv += "\(dateString),Body,BMI,\(bmi),\n"
            }
            if let bodyFat = body.bodyFatPercentage {
                csv += "\(dateString),Body,Body Fat Percentage,\(bodyFat * 100),percent\n"
            }
            if let lean = body.leanBodyMass {
                csv += "\(dateString),Body,Lean Body Mass,\(lean),kg\n"
            }
            if let waist = body.waistCircumference {
                csv += "\(dateString),Body,Waist Circumference,\(waist * 100),cm\n"
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
                let startTimeString = timeFormatter.string(from: workout.startTime)
                csv += "\(dateString),Workouts,\(workout.workoutTypeName) Start Time,\(startTimeString),time\n"
                csv += "\(dateString),Workouts,\(workout.workoutTypeName) Duration,\(workout.duration),seconds\n"
                if let distance = workout.distance, distance > 0 {
                    csv += "\(dateString),Workouts,\(workout.workoutTypeName) Distance,\(distance),meters\n"
                }
                if let calories = workout.calories, calories > 0 {
                    csv += "\(dateString),Workouts,\(workout.workoutTypeName) Calories,\(calories),kcal\n"
                }
            }
        }

        return csv
    }
}

// MARK: - Obsidian Bases Export

extension HealthData {
    func toObsidianBases() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        var frontmatter: [String] = []
        frontmatter.append("---")
        frontmatter.append("date: \(dateString)")
        frontmatter.append("type: health-data")

        // Sleep metrics
        if sleep.hasData {
            if sleep.totalDuration > 0 {
                frontmatter.append("sleep_total_hours: \(String(format: "%.2f", sleep.totalDuration / 3600))")
            }
            if sleep.deepSleep > 0 {
                frontmatter.append("sleep_deep_hours: \(String(format: "%.2f", sleep.deepSleep / 3600))")
            }
            if sleep.remSleep > 0 {
                frontmatter.append("sleep_rem_hours: \(String(format: "%.2f", sleep.remSleep / 3600))")
            }
            if sleep.coreSleep > 0 {
                frontmatter.append("sleep_core_hours: \(String(format: "%.2f", sleep.coreSleep / 3600))")
            }
            if sleep.awakeTime > 0 {
                frontmatter.append("sleep_awake_hours: \(String(format: "%.2f", sleep.awakeTime / 3600))")
            }
            if sleep.inBedTime > 0 {
                frontmatter.append("sleep_in_bed_hours: \(String(format: "%.2f", sleep.inBedTime / 3600))")
            }
        }

        // Activity metrics
        if activity.hasData {
            if let steps = activity.steps {
                frontmatter.append("steps: \(steps)")
            }
            if let calories = activity.activeCalories {
                frontmatter.append("active_calories: \(Int(calories))")
            }
            if let basal = activity.basalEnergyBurned {
                frontmatter.append("basal_calories: \(Int(basal))")
            }
            if let exercise = activity.exerciseMinutes {
                frontmatter.append("exercise_minutes: \(Int(exercise))")
            }
            if let standHours = activity.standHours {
                frontmatter.append("stand_hours: \(standHours)")
            }
            if let flights = activity.flightsClimbed {
                frontmatter.append("flights_climbed: \(flights)")
            }
            if let distance = activity.walkingRunningDistance {
                frontmatter.append("walking_running_km: \(String(format: "%.2f", distance / 1000))")
            }
            if let cycling = activity.cyclingDistance {
                frontmatter.append("cycling_km: \(String(format: "%.2f", cycling / 1000))")
            }
            if let swimming = activity.swimmingDistance {
                frontmatter.append("swimming_m: \(Int(swimming))")
            }
            if let strokes = activity.swimmingStrokes {
                frontmatter.append("swimming_strokes: \(strokes)")
            }
            if let pushes = activity.pushCount {
                frontmatter.append("wheelchair_pushes: \(pushes)")
            }
        }

        // Heart metrics
        if heart.hasData {
            if let hr = heart.restingHeartRate {
                frontmatter.append("resting_heart_rate: \(Int(hr))")
            }
            if let walkingHR = heart.walkingHeartRateAverage {
                frontmatter.append("walking_heart_rate: \(Int(walkingHR))")
            }
            if let avgHR = heart.averageHeartRate {
                frontmatter.append("average_heart_rate: \(Int(avgHR))")
            }
            if let minHR = heart.heartRateMin {
                frontmatter.append("heart_rate_min: \(Int(minHR))")
            }
            if let maxHR = heart.heartRateMax {
                frontmatter.append("heart_rate_max: \(Int(maxHR))")
            }
            if let hrv = heart.hrv {
                frontmatter.append("hrv_ms: \(String(format: "%.1f", hrv))")
            }
        }

        // Vitals metrics
        if vitals.hasData {
            if let rr = vitals.respiratoryRate {
                frontmatter.append("respiratory_rate: \(String(format: "%.1f", rr))")
            }
            if let spo2 = vitals.bloodOxygen {
                frontmatter.append("blood_oxygen: \(Int(spo2 * 100))")
            }
            if let temp = vitals.bodyTemperature {
                frontmatter.append("body_temperature: \(String(format: "%.1f", temp))")
            }
            if let systolic = vitals.bloodPressureSystolic {
                frontmatter.append("blood_pressure_systolic: \(Int(systolic))")
            }
            if let diastolic = vitals.bloodPressureDiastolic {
                frontmatter.append("blood_pressure_diastolic: \(Int(diastolic))")
            }
            if let glucose = vitals.bloodGlucose {
                frontmatter.append("blood_glucose: \(String(format: "%.1f", glucose))")
            }
        }

        // Body metrics
        if body.hasData {
            if let weight = body.weight {
                frontmatter.append("weight_kg: \(String(format: "%.1f", weight))")
            }
            if let height = body.height {
                frontmatter.append("height_m: \(String(format: "%.2f", height))")
            }
            if let bmi = body.bmi {
                frontmatter.append("bmi: \(String(format: "%.1f", bmi))")
            }
            if let bodyFat = body.bodyFatPercentage {
                frontmatter.append("body_fat_percent: \(String(format: "%.1f", bodyFat * 100))")
            }
            if let lean = body.leanBodyMass {
                frontmatter.append("lean_body_mass_kg: \(String(format: "%.1f", lean))")
            }
            if let waist = body.waistCircumference {
                frontmatter.append("waist_circumference_cm: \(String(format: "%.1f", waist * 100))")
            }
        }

        // Nutrition metrics
        if nutrition.hasData {
            if let energy = nutrition.dietaryEnergy {
                frontmatter.append("dietary_calories: \(Int(energy))")
            }
            if let protein = nutrition.protein {
                frontmatter.append("protein_g: \(String(format: "%.1f", protein))")
            }
            if let carbs = nutrition.carbohydrates {
                frontmatter.append("carbohydrates_g: \(String(format: "%.1f", carbs))")
            }
            if let fat = nutrition.fat {
                frontmatter.append("fat_g: \(String(format: "%.1f", fat))")
            }
            if let saturatedFat = nutrition.saturatedFat {
                frontmatter.append("saturated_fat_g: \(String(format: "%.1f", saturatedFat))")
            }
            if let fiber = nutrition.fiber {
                frontmatter.append("fiber_g: \(String(format: "%.1f", fiber))")
            }
            if let sugar = nutrition.sugar {
                frontmatter.append("sugar_g: \(String(format: "%.1f", sugar))")
            }
            if let sodium = nutrition.sodium {
                frontmatter.append("sodium_mg: \(Int(sodium))")
            }
            if let cholesterol = nutrition.cholesterol {
                frontmatter.append("cholesterol_mg: \(String(format: "%.1f", cholesterol))")
            }
            if let water = nutrition.water {
                frontmatter.append("water_l: \(String(format: "%.2f", water))")
            }
            if let caffeine = nutrition.caffeine {
                frontmatter.append("caffeine_mg: \(String(format: "%.1f", caffeine))")
            }
        }

        // Mindfulness metrics
        if mindfulness.hasData {
            if let minutes = mindfulness.mindfulMinutes {
                frontmatter.append("mindful_minutes: \(Int(minutes))")
            }
            if let sessions = mindfulness.mindfulSessions {
                frontmatter.append("mindful_sessions: \(sessions)")
            }
        }

        // Mobility metrics
        if mobility.hasData {
            if let speed = mobility.walkingSpeed {
                frontmatter.append("walking_speed: \(String(format: "%.2f", speed))")
            }
            if let stepLength = mobility.walkingStepLength {
                frontmatter.append("step_length_cm: \(String(format: "%.1f", stepLength * 100))")
            }
            if let doubleSupport = mobility.walkingDoubleSupportPercentage {
                frontmatter.append("double_support_percent: \(String(format: "%.1f", doubleSupport * 100))")
            }
            if let asymmetry = mobility.walkingAsymmetryPercentage {
                frontmatter.append("walking_asymmetry_percent: \(String(format: "%.1f", asymmetry * 100))")
            }
            if let ascent = mobility.stairAscentSpeed {
                frontmatter.append("stair_ascent_speed: \(String(format: "%.2f", ascent))")
            }
            if let descent = mobility.stairDescentSpeed {
                frontmatter.append("stair_descent_speed: \(String(format: "%.2f", descent))")
            }
            if let sixMin = mobility.sixMinuteWalkDistance {
                frontmatter.append("six_min_walk_m: \(Int(sixMin))")
            }
        }

        // Hearing metrics
        if hearing.hasData {
            if let headphone = hearing.headphoneAudioLevel {
                frontmatter.append("headphone_audio_db: \(String(format: "%.1f", headphone))")
            }
            if let environmental = hearing.environmentalSoundLevel {
                frontmatter.append("environmental_sound_db: \(String(format: "%.1f", environmental))")
            }
        }

        // Workout summary
        if !workouts.isEmpty {
            frontmatter.append("workout_count: \(workouts.count)")

            let totalDuration = workouts.reduce(0.0) { $0 + $1.duration }
            frontmatter.append("workout_minutes: \(Int(totalDuration / 60))")

            let totalCalories = workouts.compactMap { $0.calories }.reduce(0.0, +)
            if totalCalories > 0 {
                frontmatter.append("workout_calories: \(Int(totalCalories))")
            }

            let totalDistance = workouts.compactMap { $0.distance }.reduce(0.0, +)
            if totalDistance > 0 {
                frontmatter.append("workout_distance_km: \(String(format: "%.2f", totalDistance / 1000))")
            }

            // List workout types as tags
            let workoutTypes = workouts.map { $0.workoutTypeName.lowercased().replacingOccurrences(of: " ", with: "-") }
            let uniqueTypes = Array(Set(workoutTypes))
            frontmatter.append("workouts: [\(uniqueTypes.joined(separator: ", "))]")
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
