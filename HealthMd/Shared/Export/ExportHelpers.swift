import Foundation

// MARK: - Shared Export Formatting Helpers

extension ExportDataSnapshot {
    /// Builds the shared YAML frontmatter lines used by Markdown and Obsidian Bases exports.
    /// Metric fields are included only when the snapshot has a value and the user's
    /// Frontmatter Fields configuration has that canonical field enabled.
    func frontmatterLines(
        using config: FrontmatterConfiguration,
        includeWorkoutDetails: Bool = false
    ) -> [String] {
        var lines: [String] = ["---"]

        if config.includeDate {
            appendFrontmatterField(key: config.customDateKey, value: dateString, to: &lines)
        }
        if config.includeType {
            appendFrontmatterField(key: config.customTypeKey, value: config.customTypeValue, to: &lines)
        }

        // Custom static fields (with fixed values)
        for (key, value) in config.customFields.sorted(by: { $0.key < $1.key }) {
            appendFrontmatterField(key: key, value: value, to: &lines)
        }

        // Placeholder fields (empty values for manual entry)
        for key in config.placeholderFields.sorted() {
            appendFrontmatterField(key: key, value: "", to: &lines)
        }

        // Health metric fields selected in Format Customization > Frontmatter Fields.
        for key in frontmatterMetrics.keys.sorted() {
            guard config.isFieldEnabled(key), let value = frontmatterMetrics[key] else { continue }
            let outputKey = config.outputKey(for: key) ?? config.keyStyle.apply(to: key)
            appendFrontmatterField(key: outputKey, value: value, to: &lines)
        }

        if includeWorkoutDetails,
           !workouts.isEmpty,
           config.isFieldEnabled("workout_details") {
            let outputKey = config.outputKey(for: "workout_details") ?? config.keyStyle.apply(to: "workout_details")
            lines.append("\(outputKey):")
            lines.append(contentsOf: WorkoutFrontmatterDetailBuilder.lines(for: workouts, converter: converter))
        }

        lines.append("---")
        lines.append("")  // Trailing newline when joined with \n
        return lines
    }

    private func appendFrontmatterField(key: String, value: String, to lines: inout [String]) {
        if value.contains("\n") {
            lines.append("\(key):")
            lines.append(contentsOf: value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        } else {
            lines.append(value.isEmpty ? "\(key): " : "\(key): \(value)")
        }
    }
}

private enum WorkoutFrontmatterDetailBuilder {
    static func lines(for workouts: [WorkoutData], converter: UnitConverter) -> [String] {
        workouts.enumerated().flatMap { index, workout in
            lines(for: workout, index: index + 1, converter: converter)
        }
    }

    private static func lines(for workout: WorkoutData, index: Int, converter: UnitConverter) -> [String] {
        let zones = workout.heartRateZones()
        var lines: [String] = []

        lines.append("  - index: \(index)")
        lines.append("    date: \(formatWorkoutDate(workout.startTime))")
        lines.append("    time: \(yamlQuoted(formatWorkoutTime(workout.startTime)))")
        lines.append("    datetime: \(formatWorkoutDateTime(workout.startTime))")
        lines.append("    type: workout")
        lines.append("    metric: workouts")
        lines.append("    source: Health.md")
        lines.append("    activity_type: \(yamlQuoted(workout.workoutTypeName))")
        lines.append("    sport: \(workout.workoutType.rawValue)")
        lines.append("    tags:")
        lines.append("      - workout")
        lines.append("      - healthmd")
        lines.append("    duration_sec: \(Int(workout.duration.rounded()))")
        lines.append("    duration: \(yamlQuoted(formatDurationClock(workout.duration)))")
        lines.append("    start: \(formatWorkoutDateTime(workout.startTime))")
        lines.append("    end: \(formatWorkoutDateTime(workout.endTime))")

        if let isIndoor = workout.isIndoor {
            lines.append("    is_indoor: \(isIndoor)")
            lines.append("    location_type: \(isIndoor ? "indoor" : "outdoor")")
        }
        if let distance = workout.distance, distance > 0 {
            lines.append("    distance_m: \(Int(distance.rounded()))")
            lines.append("    distance_km: \(String(format: "%.2f", distance / 1000.0))")
            lines.append("    distance_mi: \(String(format: "%.2f", distance / 1609.344))")
            if let rate = formattedRate(for: workout.workoutType, meters: distance, duration: workout.duration, converter: converter) {
                lines.append("    \(frontmatterRateKey(for: workout.workoutType, converter: converter)): \(yamlQuoted(rate.value))")
            }
            lines.append("    speed_kmh: \(String(format: "%.1f", speedKmh(meters: distance, duration: workout.duration)))")
            lines.append("    speed_mph: \(String(format: "%.1f", speedMph(meters: distance, duration: workout.duration)))")
        }
        if let calories = workout.calories, calories > 0 {
            lines.append("    calories: \(Int(calories.rounded()))")
        }
        if let avgHR = workout.avgHeartRate {
            lines.append("    hr_avg: \(Int(avgHR.rounded()))")
        }
        if let maxHR = workout.maxHeartRate {
            lines.append("    hr_max: \(Int(maxHR.rounded()))")
        }
        if let minHR = workout.minHeartRate {
            lines.append("    hr_min: \(Int(minHR.rounded()))")
        }
        if let cadence = workout.avgRunningCadence {
            lines.append("    cadence_avg_spm: \(Int(cadence.rounded()))")
        }
        if let stride = workout.avgStrideLength {
            lines.append("    stride_length_avg_m: \(String(format: "%.2f", stride))")
        }
        if let groundContact = workout.avgGroundContactTime {
            lines.append("    ground_contact_avg_ms: \(Int(groundContact.rounded()))")
        }
        if let verticalOscillation = workout.avgVerticalOscillation {
            lines.append("    vertical_oscillation_avg_cm: \(String(format: "%.1f", verticalOscillation))")
        }
        if let cadence = workout.avgCyclingCadence {
            lines.append("    cadence_avg_rpm: \(Int(cadence.rounded()))")
        }
        if let avgPower = workout.avgPower {
            lines.append("    power_avg_w: \(Int(avgPower.rounded()))")
        }
        if let maxPower = workout.maxPower {
            lines.append("    power_max_w: \(Int(maxPower.rounded()))")
        }
        if let elevation = workout.elevationGainMeters {
            lines.append("    ascent_m: \(Int(elevation.rounded()))")
        }
        if let elevationLoss = workout.elevationLossMeters {
            lines.append("    descent_m: \(Int(elevationLoss.rounded()))")
        }
        if !workout.laps.isEmpty {
            lines.append("    laps_count: \(workout.laps.count)")
        }
        if !workout.splits.isEmpty {
            lines.append("    splits_count: \(workout.splits.count)")
        }
        if !workout.route.isEmpty {
            lines.append("    route_points: \(workout.route.count)")
        }
        appendSampleCounts(for: workout, lines: &lines)

        if !zones.isEmpty {
            lines.append("    heart_rate_zones:")
            for zone in zones {
                lines.append("      zone\(zone.index):")
                lines.append("        label: \(zone.label)")
                lines.append("        range: \(yamlQuoted(zone.rangeDescription))")
                lines.append("        seconds: \(Int(zone.seconds.rounded()))")
                lines.append("        duration: \(zone.seconds > 0 ? yamlQuoted(zone.durationClock) : "null")")
            }
        }

        appendIntervals(
            key: "laps",
            indexKey: "lap",
            intervals: workout.laps.enumerated().map { idx, lap in
                WorkoutIntervalFrontmatter(
                    index: idx + 1,
                    startDate: lap.startDate,
                    endDate: lap.endDate,
                    duration: lap.duration,
                    distanceMeters: lap.distanceMeters,
                    fallbackAvgHeartRate: nil
                )
            },
            workout: workout,
            converter: converter,
            lines: &lines
        )
        appendIntervals(
            key: "splits",
            indexKey: "split",
            intervals: workout.splits.map { split in
                WorkoutIntervalFrontmatter(
                    index: split.index,
                    startDate: split.startDate,
                    endDate: split.startDate.addingTimeInterval(split.duration),
                    duration: split.duration,
                    distanceMeters: split.distanceMeters,
                    fallbackAvgHeartRate: split.avgHeartRate
                )
            },
            workout: workout,
            converter: converter,
            lines: &lines
        )

        if !workout.metadata.isEmpty {
            lines.append("    metadata:")
            for (key, value) in workout.metadata.sorted(by: { $0.key < $1.key }) {
                lines.append("      \(key): \(yamlQuoted(value))")
            }
        }

        return lines
    }

    private struct WorkoutIntervalFrontmatter {
        let index: Int
        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let distanceMeters: Double?
        let fallbackAvgHeartRate: Double?
    }

    private struct WorkoutIntervalStats {
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let avgPower: Double?
        let avgCadence: Double?
    }

    private static func appendSampleCounts(for workout: WorkoutData, lines: inout [String]) {
        let rows: [(String, Int)] = [
            ("heart_rate", workout.timeSeries.heartRate.count),
            ("speed", workout.timeSeries.speed.count),
            ("power", workout.timeSeries.power.count),
            ("cadence", workout.timeSeries.cadence.count),
            ("stride_length", workout.timeSeries.strideLength.count),
            ("ground_contact", workout.timeSeries.groundContactTime.count),
            ("vertical_oscillation", workout.timeSeries.verticalOscillation.count),
            ("altitude", workout.timeSeries.altitude.count)
        ].filter { $0.1 > 0 }

        guard !rows.isEmpty else { return }
        lines.append("    sample_counts:")
        for (key, count) in rows {
            lines.append("      \(key): \(count)")
        }
    }

    private static func appendIntervals(
        key: String,
        indexKey: String,
        intervals: [WorkoutIntervalFrontmatter],
        workout: WorkoutData,
        converter: UnitConverter,
        lines: inout [String]
    ) {
        guard !intervals.isEmpty else { return }
        lines.append("    \(key):")
        for interval in intervals {
            let stats = intervalStats(for: workout, start: interval.startDate, end: interval.endDate)
            lines.append("      - \(indexKey): \(interval.index)")
            lines.append("        start: \(formatWorkoutDateTime(interval.startDate))")
            lines.append("        end: \(formatWorkoutDateTime(interval.endDate))")
            lines.append("        time_sec: \(Int(interval.duration.rounded()))")
            lines.append("        duration: \(yamlQuoted(formatDurationClock(interval.duration)))")

            if let distance = interval.distanceMeters, distance > 0 {
                lines.append("        distance_m: \(Int(distance.rounded()))")
                lines.append("        distance_km: \(String(format: "%.2f", distance / 1000.0))")
                lines.append("        distance_mi: \(String(format: "%.2f", distance / 1609.344))")
                if let paceKm = UnitConverter(preference: .metric).formatPace(meters: distance, duration: interval.duration) {
                    lines.append("        pace_per_km: \(yamlQuoted(paceKm))")
                }
                if let paceMi = UnitConverter(preference: .imperial).formatPace(meters: distance, duration: interval.duration) {
                    lines.append("        pace_per_mi: \(yamlQuoted(paceMi))")
                }
                if let rate = formattedRate(for: workout.workoutType, meters: distance, duration: interval.duration, converter: converter) {
                    lines.append("        rate_label: \(yamlQuoted(rate.label))")
                    lines.append("        rate: \(yamlQuoted(rate.value))")
                }
                lines.append("        speed_kmh: \(String(format: "%.1f", speedKmh(meters: distance, duration: interval.duration)))")
                lines.append("        speed_mph: \(String(format: "%.1f", speedMph(meters: distance, duration: interval.duration)))")
            }

            let avgHR = interval.fallbackAvgHeartRate ?? stats.avgHeartRate
            if let avgHR {
                lines.append("        hr_avg: \(Int(avgHR.rounded()))")
            }
            if let maxHR = stats.maxHeartRate {
                lines.append("        hr_max: \(Int(maxHR.rounded()))")
            }
            if let avgPower = stats.avgPower {
                lines.append("        power_avg_w: \(Int(avgPower.rounded()))")
            }
            if let avgCadence = stats.avgCadence {
                lines.append("        cadence_avg_\(cadenceUnit(for: workout.workoutType)): \(Int(avgCadence.rounded()))")
            }
        }
    }

    private static func intervalStats(for workout: WorkoutData, start: Date, end: Date) -> WorkoutIntervalStats {
        WorkoutIntervalStats(
            avgHeartRate: averageSampleValue(workout.timeSeries.heartRate, start: start, end: end),
            maxHeartRate: maxSampleValue(workout.timeSeries.heartRate, start: start, end: end),
            avgPower: averageSampleValue(workout.timeSeries.power, start: start, end: end),
            avgCadence: averageSampleValue(workout.timeSeries.cadence, start: start, end: end)
        )
    }

    private static func averageSampleValue(_ samples: [TimeSeriesSample], start: Date, end: Date) -> Double? {
        let values = samples
            .filter { $0.timestamp >= start && $0.timestamp < end }
            .map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func maxSampleValue(_ samples: [TimeSeriesSample], start: Date, end: Date) -> Double? {
        samples
            .filter { $0.timestamp >= start && $0.timestamp < end }
            .map(\.value)
            .max()
    }

    private static func formattedRate(
        for workoutType: WorkoutType,
        meters: Double,
        duration: TimeInterval,
        converter: UnitConverter
    ) -> (label: String, value: String)? {
        switch workoutType {
        case .swimming:
            guard let value = converter.formatSwimPace(meters: meters, duration: duration) else { return nil }
            return ("Pace", value)
        case .cycling, .skatingSports, .snowSports, .waterSports:
            guard let value = converter.formatSpeed(meters: meters, duration: duration) else { return nil }
            return ("Speed", value)
        default:
            guard let value = converter.formatPace(meters: meters, duration: duration) else { return nil }
            return ("Pace", value)
        }
    }

    private static func frontmatterRateKey(for workoutType: WorkoutType, converter: UnitConverter) -> String {
        switch workoutType {
        case .swimming:
            return converter.preference == .metric ? "pace_per_100m" : "pace_per_100yd"
        case .cycling, .skatingSports, .snowSports, .waterSports:
            return converter.preference == .metric ? "speed_kmh_formatted" : "speed_mph_formatted"
        default:
            return converter.preference == .metric ? "pace_per_km" : "pace_per_mi"
        }
    }

    private static func cadenceUnit(for workoutType: WorkoutType) -> String {
        workoutType == .cycling ? "rpm" : "spm"
    }

    private static func speedKmh(meters: Double, duration: TimeInterval) -> Double {
        guard meters > 0, duration > 0 else { return 0 }
        return (meters / 1000.0) / (duration / 3600.0)
    }

    private static func speedMph(meters: Double, duration: TimeInterval) -> Double {
        guard meters > 0, duration > 0 else { return 0 }
        return (meters / 1609.344) / (duration / 3600.0)
    }

    private static func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func formatWorkoutDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formatWorkoutTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func formatWorkoutDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func formatDurationClock(_ seconds: TimeInterval) -> String {
        WorkoutHeartRateZone.clockDuration(seconds)
    }
}

extension HealthData {
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func formatDurationShort(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Metric-only distance formatter retained for tests and call sites that explicitly
    /// need kilometers/meters. Export paths should use `UnitConverter.formatDistance(_:)`
    /// so imperial exports render miles/feet correctly.
    func formatDistanceMetric(_ meters: Double) -> String {
        UnitConverter(preference: .metric).formatDistance(meters)
    }
    
    func valenceDescription(_ valence: Double) -> String {
        switch valence {
        case -1.0 ..< -0.6:
            return "Very Unpleasant"
        case -0.6 ..< -0.2:
            return "Unpleasant"
        case -0.2 ..< 0.2:
            return "Neutral"
        case 0.2 ..< 0.6:
            return "Pleasant"
        case 0.6 ... 1.0:
            return "Very Pleasant"
        default:
            return "Unknown"
        }
    }
}
