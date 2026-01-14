import Foundation
import HealthKit

// MARK: - Sleep Data

struct SleepData {
    var totalDuration: TimeInterval = 0
    var deepSleep: TimeInterval = 0
    var remSleep: TimeInterval = 0
    var coreSleep: TimeInterval = 0

    var hasData: Bool {
        totalDuration > 0 || deepSleep > 0 || remSleep > 0 || coreSleep > 0
    }
}

// MARK: - Activity Data

struct ActivityData {
    var steps: Int?
    var activeCalories: Double?
    var exerciseMinutes: Double?
    var flightsClimbed: Int?
    var walkingRunningDistance: Double? // in meters

    var hasData: Bool {
        steps != nil || activeCalories != nil || exerciseMinutes != nil ||
        flightsClimbed != nil || walkingRunningDistance != nil
    }
}

// MARK: - Vitals Data

struct VitalsData {
    var restingHeartRate: Double?
    var hrv: Double? // in milliseconds
    var respiratoryRate: Double?
    var bloodOxygen: Double? // as percentage

    var hasData: Bool {
        restingHeartRate != nil || hrv != nil || respiratoryRate != nil || bloodOxygen != nil
    }
}

// MARK: - Body Data

struct BodyData {
    var weight: Double? // in kg
    var bodyFatPercentage: Double?

    var hasData: Bool {
        weight != nil || bodyFatPercentage != nil
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
    var vitals: VitalsData = VitalsData()
    var body: BodyData = BodyData()
    var workouts: [WorkoutData] = []

    var hasAnyData: Bool {
        sleep.hasData || activity.hasData || vitals.hasData || body.hasData || !workouts.isEmpty
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
        if !dataTypes.vitals {
            filtered.vitals = VitalsData()
        }
        if !dataTypes.body {
            filtered.body = BodyData()
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
            if sleep.deepSleep > 0 {
                markdown += "- **Deep:** \(formatDuration(sleep.deepSleep))\n"
            }
            if sleep.remSleep > 0 {
                markdown += "- **REM:** \(formatDuration(sleep.remSleep))\n"
            }
            if sleep.coreSleep > 0 {
                markdown += "- **Core:** \(formatDuration(sleep.coreSleep))\n"
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
            if let exercise = activity.exerciseMinutes {
                markdown += "- **Exercise:** \(Int(exercise)) min\n"
            }
            if let flights = activity.flightsClimbed {
                markdown += "- **Flights Climbed:** \(flights)\n"
            }
            if let distance = activity.walkingRunningDistance {
                markdown += "- **Distance:** \(formatDistance(distance))\n"
            }
        }

        // Vitals Section
        if vitals.hasData {
            markdown += "\n## Vitals\n\n"
            if let hr = vitals.restingHeartRate {
                markdown += "- **Resting HR:** \(Int(hr)) bpm\n"
            }
            if let hrv = vitals.hrv {
                markdown += "- **HRV:** \(String(format: "%.1f", hrv)) ms\n"
            }
            if let rr = vitals.respiratoryRate {
                markdown += "- **Respiratory Rate:** \(String(format: "%.1f", rr)) breaths/min\n"
            }
            if let spo2 = vitals.bloodOxygen {
                markdown += "- **SpO2:** \(Int(spo2 * 100))%\n"
            }
        }

        // Body Section
        if body.hasData {
            markdown += "\n## Body\n\n"
            if let weight = body.weight {
                markdown += "- **Weight:** \(String(format: "%.1f", weight)) kg\n"
            }
            if let bodyFat = body.bodyFatPercentage {
                markdown += "- **Body Fat:** \(String(format: "%.1f", bodyFat * 100))%\n"
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
            if let exercise = activity.exerciseMinutes {
                activityDict["exerciseMinutes"] = exercise
            }
            if let flights = activity.flightsClimbed {
                activityDict["flightsClimbed"] = flights
            }
            if let distance = activity.walkingRunningDistance {
                activityDict["walkingRunningDistance"] = distance
                activityDict["walkingRunningDistanceKm"] = distance / 1000
            }
            json["activity"] = activityDict
        }

        // Vitals
        if vitals.hasData {
            var vitalsDict: [String: Any] = [:]
            if let hr = vitals.restingHeartRate {
                vitalsDict["restingHeartRate"] = hr
            }
            if let hrv = vitals.hrv {
                vitalsDict["hrv"] = hrv
            }
            if let rr = vitals.respiratoryRate {
                vitalsDict["respiratoryRate"] = rr
            }
            if let spo2 = vitals.bloodOxygen {
                vitalsDict["bloodOxygen"] = spo2
                vitalsDict["bloodOxygenPercent"] = spo2 * 100
            }
            json["vitals"] = vitalsDict
        }

        // Body
        if body.hasData {
            var bodyDict: [String: Any] = [:]
            if let weight = body.weight {
                bodyDict["weight"] = weight
            }
            if let bodyFat = body.bodyFatPercentage {
                bodyDict["bodyFatPercentage"] = bodyFat
                bodyDict["bodyFatPercent"] = bodyFat * 100
            }
            json["body"] = bodyDict
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
        }

        // Activity
        if activity.hasData {
            if let steps = activity.steps {
                csv += "\(dateString),Activity,Steps,\(steps),count\n"
            }
            if let calories = activity.activeCalories {
                csv += "\(dateString),Activity,Active Calories,\(calories),kcal\n"
            }
            if let exercise = activity.exerciseMinutes {
                csv += "\(dateString),Activity,Exercise Minutes,\(exercise),minutes\n"
            }
            if let flights = activity.flightsClimbed {
                csv += "\(dateString),Activity,Flights Climbed,\(flights),count\n"
            }
            if let distance = activity.walkingRunningDistance {
                csv += "\(dateString),Activity,Walking Running Distance,\(distance),meters\n"
            }
        }

        // Vitals
        if vitals.hasData {
            if let hr = vitals.restingHeartRate {
                csv += "\(dateString),Vitals,Resting Heart Rate,\(hr),bpm\n"
            }
            if let hrv = vitals.hrv {
                csv += "\(dateString),Vitals,HRV,\(hrv),ms\n"
            }
            if let rr = vitals.respiratoryRate {
                csv += "\(dateString),Vitals,Respiratory Rate,\(rr),breaths/min\n"
            }
            if let spo2 = vitals.bloodOxygen {
                csv += "\(dateString),Vitals,Blood Oxygen,\(spo2 * 100),percent\n"
            }
        }

        // Body
        if body.hasData {
            if let weight = body.weight {
                csv += "\(dateString),Body,Weight,\(weight),kg\n"
            }
            if let bodyFat = body.bodyFatPercentage {
                csv += "\(dateString),Body,Body Fat Percentage,\(bodyFat * 100),percent\n"
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
        }

        // Activity metrics
        if activity.hasData {
            if let steps = activity.steps {
                frontmatter.append("steps: \(steps)")
            }
            if let calories = activity.activeCalories {
                frontmatter.append("active_calories: \(Int(calories))")
            }
            if let exercise = activity.exerciseMinutes {
                frontmatter.append("exercise_minutes: \(Int(exercise))")
            }
            if let flights = activity.flightsClimbed {
                frontmatter.append("flights_climbed: \(flights)")
            }
            if let distance = activity.walkingRunningDistance {
                frontmatter.append("distance_km: \(String(format: "%.2f", distance / 1000))")
            }
        }

        // Vitals metrics
        if vitals.hasData {
            if let hr = vitals.restingHeartRate {
                frontmatter.append("resting_heart_rate: \(Int(hr))")
            }
            if let hrv = vitals.hrv {
                frontmatter.append("hrv_ms: \(String(format: "%.1f", hrv))")
            }
            if let rr = vitals.respiratoryRate {
                frontmatter.append("respiratory_rate: \(String(format: "%.1f", rr))")
            }
            if let spo2 = vitals.bloodOxygen {
                frontmatter.append("blood_oxygen: \(Int(spo2 * 100))")
            }
        }

        // Body metrics
        if body.hasData {
            if let weight = body.weight {
                frontmatter.append("weight_kg: \(String(format: "%.1f", weight))")
            }
            if let bodyFat = body.bodyFatPercentage {
                frontmatter.append("body_fat_percent: \(String(format: "%.1f", bodyFat * 100))")
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
        var body = "\n# Health — \(dateString)\n"

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
            body += "\n" + summaryItems.joined(separator: " · ") + "\n"
        }

        body += "\n## Notes\n\n"

        return frontmatter.joined(separator: "\n") + body
    }
}
