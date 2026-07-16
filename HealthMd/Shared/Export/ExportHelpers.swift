import Foundation

// MARK: - Shared Export Formatting Helpers

enum ExportDateFormatting {
    static func utcISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func utcTimestamp(_ date: Date) -> String {
        utcISO8601Formatter().string(from: date)
    }
}

extension ExportDataSnapshot {
    /// Builds the shared YAML frontmatter lines used by Markdown and Obsidian Bases exports.
    /// Metric fields are included only when the snapshot has a value and the user's
    /// Frontmatter Fields configuration has that canonical field enabled.
    func frontmatterLines(
        using config: FrontmatterConfiguration,
        includeWorkoutDetails: Bool = false
    ) -> [String] {
        var lines: [String] = ["---"]
        appendFrontmatterField(key: "schema", value: HealthMdExportSchema.identifier, to: &lines)
        appendFrontmatterField(key: "schema_version", value: "\(HealthMdExportSchema.version)", to: &lines)
        lines.append("time_context:")
        lines.append("  calendar_timezone: \(timeContext.calendarTimeZoneIdentifier)")
        lines.append("  timestamp_timezone: \(ExportTimeContext.timestampTimeZoneIdentifier)")

        if config.includeDate {
            appendFrontmatterField(key: config.customDateKey, value: dateString, to: &lines)
        }
        if config.includeType {
            appendFrontmatterField(key: config.customTypeKey, value: config.customTypeValue, to: &lines)
        }

        let losslessReservedKeys: Set<String> = [
            "raw_capture_status", "raw_record_count", "raw_query_failure_count",
            "raw_integrity_warning_count", "raw_record_schema", "raw_record_schema_version"
        ]

        // Custom fields cannot shadow stable canonical archive diagnostics.
        for (key, value) in config.customFields.sorted(by: { $0.key < $1.key })
            where !losslessReservedKeys.contains(key) {
            appendFrontmatterField(key: key, value: value, to: &lines)
        }

        // Placeholder fields (empty values for manual entry)
        for key in config.placeholderFields.sorted() where !losslessReservedKeys.contains(key) {
            appendFrontmatterField(key: key, value: "", to: &lines)
        }

        let rawDiagnostics = losslessArchiveDiagnostics
        appendFrontmatterField(key: "raw_capture_status", value: rawDiagnostics.captureStatus, to: &lines)
        appendFrontmatterField(key: "raw_record_count", value: "\(rawDiagnostics.recordCount)", to: &lines)
        appendFrontmatterField(key: "raw_query_failure_count", value: "\(rawDiagnostics.queryFailureCount)", to: &lines)
        appendFrontmatterField(key: "raw_integrity_warning_count", value: "\(rawDiagnostics.integrityWarningCount)", to: &lines)
        if let archive = healthKitRecordArchive {
            appendFrontmatterField(key: "raw_record_schema", value: archive.schemaIdentifier, to: &lines)
            appendFrontmatterField(key: "raw_record_schema_version", value: "\(archive.recordSchemaVersion)", to: &lines)
        }

        // Health metric fields selected in Format Customization > Frontmatter Fields.
        var exportedMetricUnits: [(key: String, unit: String)] = [
            (key: "raw_record_count", unit: "records"),
            (key: "raw_query_failure_count", unit: "queries"),
            (key: "raw_integrity_warning_count", unit: "warnings")
        ]
        for key in frontmatterMetrics.keys.sorted() {
            guard config.isFieldEnabled(key), let value = frontmatterMetrics[key] else { continue }
            let outputKey = config.outputKey(for: key) ?? config.keyStyle.apply(to: key)
            appendFrontmatterField(key: outputKey, value: value, to: &lines)
            if let unit = HealthMetricDataDictionary.unit(for: key, converter: converter), !unit.isEmpty {
                exportedMetricUnits.append((key: outputKey, unit: unit))
            }
        }

        if !exportedMetricUnits.isEmpty {
            lines.append("units:")
            for item in exportedMetricUnits.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(item.key): \(item.unit)")
            }
        }

        if includeWorkoutDetails,
           !workouts.isEmpty,
           config.isFieldEnabled("workout_details") {
            let outputKey = config.outputKey(for: "workout_details") ?? config.keyStyle.apply(to: "workout_details")
            lines.append("\(outputKey):")
            lines.append(contentsOf: WorkoutFrontmatterDetailBuilder.lines(
                for: workouts,
                converter: converter,
                timeZone: calendarTimeZone
            ))
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

struct LosslessArchiveDiagnostics {
    let captureStatus: String
    let recordCount: Int
    let querySuccessCount: Int
    let queryEmptyCount: Int
    let queryFailureCount: Int
    let queryUnsupportedCount: Int
    let querySkippedCount: Int
    let integrityWarningCount: Int
    let medicationInventoryCount: Int
    let isCaptureRequestedOrAvailable: Bool
}

extension ExportDataSnapshot {
    var losslessArchiveDiagnostics: LosslessArchiveDiagnostics {
        let results = healthKitRecordArchive?.queryResults ?? []
        let captureStatus = HealthKitRecordArchiveSerializer.captureStatusString(
            healthKitRecordArchive?.captureStatus ?? healthKitRecordCaptureStatus
        )
        return LosslessArchiveDiagnostics(
            captureStatus: captureStatus,
            recordCount: healthKitRecordArchive?.records.count ?? 0,
            querySuccessCount: results.filter { $0.status == .success && $0.recordCount > 0 }.count,
            queryEmptyCount: results.filter { $0.status == .success && $0.recordCount == 0 }.count,
            queryFailureCount: results.filter { $0.status == .failure }.count,
            queryUnsupportedCount: results.filter { $0.status == .unsupported }.count,
            querySkippedCount: results.filter { $0.status == .skipped }.count,
            integrityWarningCount: healthKitRecordArchive?.integrityWarnings.count ?? 0,
            medicationInventoryCount: healthKitRecordArchive?.medicationInventoryRecords.count ?? 0,
            isCaptureRequestedOrAvailable: healthKitRecordArchive != nil ||
                healthKitRecordCaptureStatus == .complete || healthKitRecordCaptureStatus == .partial
        )
    }
}

private enum WorkoutFrontmatterDetailBuilder {
    static func lines(for workouts: [WorkoutData], converter: UnitConverter, timeZone: TimeZone) -> [String] {
        workouts.enumerated().flatMap { index, workout in
            lines(for: workout, index: index + 1, converter: converter, timeZone: timeZone)
        }
    }

    private static func lines(for workout: WorkoutData, index: Int, converter: UnitConverter, timeZone: TimeZone) -> [String] {
        let zones = workout.heartRateZones()
        var lines: [String] = []

        lines.append("  - index: \(index)")
        lines.append("    date: \(formatWorkoutDate(workout.startTime, timeZone: timeZone))")
        lines.append("    time: \(yamlQuoted(formatWorkoutTime(workout.startTime, timeZone: timeZone)))")
        lines.append("    datetime: \(formatWorkoutDateTime(workout.startTime))")
        lines.append("    type: workout")
        lines.append("    metric: workouts")
        lines.append("    source: Health.md")
        lines.append("    activity_type: \(yamlQuoted(workout.workoutTypeName))")
        lines.append("    sport: \(workout.workoutSportName)")
        if let healthKitActivityType = workout.healthKitActivityType {
            lines.append("    healthkit_activity_type: \(healthKitActivityType)")
        }
        if let rawValue = workout.healthKitActivityTypeRawValue {
            lines.append("    healthkit_activity_type_raw_value: \(rawValue)")
        }
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
            appendStableRateFields(
                for: workout.workoutType,
                meters: distance,
                duration: workout.duration,
                indentation: "    ",
                lines: &lines
            )
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
        converter _: UnitConverter,
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
                appendStableRateFields(
                    for: workout.workoutType,
                    meters: distance,
                    duration: interval.duration,
                    indentation: "        ",
                    lines: &lines
                )
                if let rate = formattedRate(for: workout.workoutType, meters: distance, duration: interval.duration, converter: UnitConverter(preference: .metric)) {
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

    private static func appendStableRateFields(
        for workoutType: WorkoutType,
        meters: Double,
        duration: TimeInterval,
        indentation: String,
        lines: inout [String]
    ) {
        switch workoutType {
        case .swimming:
            if let pace100m = UnitConverter(preference: .metric).formatSwimPace(meters: meters, duration: duration) {
                lines.append("\(indentation)pace_per_100m: \(yamlQuoted(pace100m))")
            }
            if let pace100yd = UnitConverter(preference: .imperial).formatSwimPace(meters: meters, duration: duration) {
                lines.append("\(indentation)pace_per_100yd: \(yamlQuoted(pace100yd))")
            }
        case .cycling, .skatingSports, .snowSports, .waterSports:
            if let speedKmh = UnitConverter(preference: .metric).formatSpeed(meters: meters, duration: duration) {
                lines.append("\(indentation)speed_kmh_formatted: \(yamlQuoted(speedKmh))")
            }
            if let speedMph = UnitConverter(preference: .imperial).formatSpeed(meters: meters, duration: duration) {
                lines.append("\(indentation)speed_mph_formatted: \(yamlQuoted(speedMph))")
            }
        default:
            if let paceKm = UnitConverter(preference: .metric).formatPace(meters: meters, duration: duration) {
                lines.append("\(indentation)pace_per_km: \(yamlQuoted(paceKm))")
            }
            if let paceMi = UnitConverter(preference: .imperial).formatPace(meters: meters, duration: duration) {
                lines.append("\(indentation)pace_per_mi: \(yamlQuoted(paceMi))")
            }
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
        "\"\(yamlDoubleQuotedEscaped(value))\""
    }

    private static func yamlDoubleQuotedEscaped(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                escaped += "\\\""
            case 0x5C:
                escaped += "\\\\"
            case 0x08:
                escaped += "\\b"
            case 0x09:
                escaped += "\\t"
            case 0x0A:
                escaped += "\\n"
            case 0x0C:
                escaped += "\\f"
            case 0x0D:
                escaped += "\\r"
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }

    private static func formatWorkoutDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func formatWorkoutTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func formatWorkoutDateTime(_ date: Date) -> String {
        ExportDateFormatting.utcTimestamp(date)
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
    /// need kilometers/meters. Human-readable Markdown prose may use
    /// `UnitConverter.formatDistance(_:)`; structured exports should use explicit
    /// canonical fields such as meters, `_km`, or `_mi`.
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
