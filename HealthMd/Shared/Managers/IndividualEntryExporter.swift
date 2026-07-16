//
//  IndividualEntryExporter.swift
//  Health.md
//
//  Handles exporting individual timestamped health entries as separate files.
//

import Foundation
import HealthKit

// MARK: - Individual Health Sample

/// Represents a single health data sample with timestamp for individual export
struct IndividualHealthSample {
    let metricId: String
    let metricName: String
    let category: HealthMetricCategory
    let timestamp: Date
    let value: Any
    let unit: String
    let source: String?
    let additionalFields: [String: Any]
    /// Original HealthKit identity when this sample came from the canonical archive.
    let originalUUID: UUID?
    /// Optional rich workout payload used to render HealthFit-style workout
    /// notes while keeping the generic sample model lightweight for other metrics.
    let workout: WorkoutData?

    init(
        metricId: String,
        metricName: String,
        category: HealthMetricCategory,
        timestamp: Date,
        value: Any,
        unit: String,
        source: String? = nil,
        additionalFields: [String: Any] = [:],
        originalUUID: UUID? = nil,
        workout: WorkoutData? = nil
    ) {
        self.metricId = metricId
        self.metricName = metricName
        self.category = category
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.source = source
        self.additionalFields = additionalFields
        self.originalUUID = originalUUID
        self.workout = workout
    }
}

// MARK: - Individual Entry Exporter

@MainActor
final class IndividualEntryExporter {

    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let filenameCollisionFormatter: DateFormatter
    private let datetimeFormatter: ISO8601DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        filenameCollisionFormatter = DateFormatter()
        filenameCollisionFormatter.dateFormat = "ssSSS"

        datetimeFormatter = ISO8601DateFormatter()
        datetimeFormatter.formatOptions = [.withInternetDateTime]
    }

    // MARK: - Export Individual Entries

    /// Export individual samples as separate files
    /// Returns the number of files written
    func exportIndividualEntries(
        samples: [IndividualHealthSample],
        to baseURL: URL,
        settings: IndividualTrackingSettings,
        formatSettings: FormatCustomization
    ) throws -> Int {
        var filesWritten = 0
        var reservedFilePaths = Set<String>()
        let fileManager = FileManager.default

        for sample in samples {
            // Skip if this metric isn't configured for individual tracking
            guard settings.shouldTrackIndividually(sample.metricId) else {
                continue
            }

            // Build the metric definition for folder/filename generation
            let metricDef = HealthMetricDefinition(
                id: sample.metricId,
                name: sample.metricName,
                category: sample.category,
                unit: sample.unit,
                healthKitIdentifier: nil,
                metricType: .quantity,
                aggregation: .mostRecent
            )

            // Build folder path
            let folderPath = settings.folderPath(for: metricDef)
            let folderURL = baseURL.appendingPathComponent(folderPath, isDirectory: true)

            // Create directory if needed
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }

            // Canonical records always include their source UUID in the path. This
            // makes same-minute collisions stable across partial reruns and exports
            // where a single object is intentionally tracked under multiple metrics.
            let filename = filename(for: sample, settings: settings)
            let baseFileURL = folderURL.appendingPathComponent(filename)
            let fileURL: URL
            if sample.originalUUID != nil {
                reservedFilePaths.insert(baseFileURL.path)
                fileURL = baseFileURL
            } else {
                fileURL = collisionResolvedFileURL(
                    baseFileURL,
                    timestamp: sample.timestamp,
                    reservedPaths: &reservedFilePaths
                )
            }

            // Generate content
            let content = generateEntryContent(for: sample, formatSettings: formatSettings)

            // Write file via a same-directory temp file so sync providers never see partial content.
            try AtomicFileWriter.writeString(content, to: fileURL)
            filesWritten += 1
        }

        return filesWritten
    }

    func filename(for sample: IndividualHealthSample, settings: IndividualTrackingSettings) -> String {
        let metric = HealthMetrics.all.first(where: { $0.id == sample.metricId }) ?? HealthMetricDefinition(
            id: sample.metricId,
            name: sample.metricName,
            category: sample.category,
            unit: sample.unit,
            healthKitIdentifier: nil,
            metricType: .quantity,
            aggregation: .mostRecent
        )
        let base = settings.filename(for: metric, date: sample.timestamp, time: sample.timestamp)
        guard let originalUUID = sample.originalUUID else { return base }

        let fileExtension = (base as NSString).pathExtension
        let basename = (base as NSString).deletingPathExtension
        let metricComponent = sample.metricId
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "_", options: .regularExpression)
        return "\(basename)_\(metricComponent)_\(originalUUID.uuidString.lowercased()).\(fileExtension)"
    }

    /// The default filename template has minute precision. Multiple readings can
    /// occur within that minute (especially a blood-pressure triple measurement),
    /// so reserve a deterministic seconds/milliseconds suffix rather than letting
    /// a later sample overwrite an earlier one in the same export run.
    private func collisionResolvedFileURL(
        _ baseURL: URL,
        timestamp: Date,
        reservedPaths: inout Set<String>
    ) -> URL {
        guard reservedPaths.contains(baseURL.path) else {
            reservedPaths.insert(baseURL.path)
            return baseURL
        }

        let fileExtension = baseURL.pathExtension
        let basename = baseURL.deletingPathExtension().lastPathComponent
        let directory = baseURL.deletingLastPathComponent()
        let timestampSuffix = filenameCollisionFormatter.string(from: timestamp)
        var collisionIndex = 1

        while true {
            let indexSuffix = collisionIndex == 1 ? "" : "_\(collisionIndex)"
            let candidateName = "\(basename)_\(timestampSuffix)\(indexSuffix)"
            let candidate = directory
                .appendingPathComponent(candidateName)
                .appendingPathExtension(fileExtension)
            if !reservedPaths.contains(candidate.path) {
                reservedPaths.insert(candidate.path)
                return candidate
            }
            collisionIndex += 1
        }
    }

    // MARK: - Content Generation

    /// Generate markdown content for an individual entry preview without writing it.
    func previewEntryContent(for sample: IndividualHealthSample, formatSettings: FormatCustomization) -> String {
        generateEntryContent(for: sample, formatSettings: formatSettings)
    }

    /// Generate markdown content for an individual entry
    private func generateEntryContent(for sample: IndividualHealthSample, formatSettings: FormatCustomization) -> String {
        if sample.metricId == "workouts", let workout = sample.workout {
            return generateWorkoutEntryContent(
                for: workout,
                canonicalFields: sample.additionalFields,
                formatSettings: formatSettings
            )
        }

        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("date: \(dateFormatter.string(from: sample.timestamp))")
        lines.append("time: \"\(timeFormatter.string(from: sample.timestamp))\"")
        let timestamp = sample.originalUUID == nil
            ? datetimeFormatter.string(from: sample.timestamp)
            : CanonicalRFC3339UTC.string(from: sample.timestamp)
        lines.append("datetime: \(timestamp)")
        lines.append("type: \(sample.category.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
        lines.append("metric: \(sample.metricId)")

        // Primary value
        if let doubleValue = sample.value as? Double {
            let rendered = sample.originalUUID == nil ? formatValue(doubleValue) : String(doubleValue)
            lines.append("value: \(rendered)")
        } else if let intValue = sample.value as? Int {
            lines.append("value: \(intValue)")
        } else if let intValue = sample.value as? Int64 {
            lines.append("value: \(intValue)")
        } else if let stringValue = sample.value as? String {
            lines.append("value: \(yamlQuoted(stringValue))")
        }

        // Unit
        if !sample.unit.isEmpty {
            lines.append("unit: \(formatYAMLStringScalar(sample.unit))")
        }

        // Source
        if let source = sample.source {
            lines.append("source: \(yamlQuoted(source))")
        }

        // Additional fields
        for (key, value) in sample.additionalFields.sorted(by: { $0.key < $1.key }) {
            lines.append(formatYAMLField(key: key, value: value))
        }

        lines.append("---")

        return lines.joined(separator: "\n")
    }

    /// Render a standalone workout note with Dataview-friendly frontmatter and
    /// human-readable sections for zones, laps/splits, and available time-series
    /// metrics. This intentionally derives detail from HealthKit data instead of
    /// requiring a raw `.fit` file.
    private func generateWorkoutEntryContent(
        for workout: WorkoutData,
        canonicalFields: [String: Any],
        formatSettings: FormatCustomization
    ) -> String {
        let converter = UnitConverter(preference: formatSettings.unitPreference)
        let dateString = dateFormatter.string(from: workout.startTime)
        let timeString = timeFormatter.string(from: workout.startTime)
        let zones = workout.heartRateZones()

        var lines: [String] = []
        lines.append("---")
        lines.append("date: \(dateString)")
        lines.append("time: \"\(timeString)\"")
        lines.append("datetime: \(datetimeFormatter.string(from: workout.startTime))")
        lines.append("type: workout")
        lines.append("metric: workouts")
        lines.append("source: Health.md")
        lines.append("activity_type: \(yamlQuoted(workout.workoutTypeName))")
        lines.append("sport: \(workout.workoutSportName)")
        if let healthKitActivityType = workout.healthKitActivityType {
            lines.append("healthkit_activity_type: \(healthKitActivityType)")
        }
        if let rawValue = workout.healthKitActivityTypeRawValue {
            lines.append("healthkit_activity_type_raw_value: \(rawValue)")
        }
        lines.append("tags:")
        lines.append("  - workout")
        lines.append("  - healthmd")
        lines.append("duration_sec: \(Int(workout.duration.rounded()))")
        lines.append("duration: \(yamlQuoted(formatDurationClock(workout.duration)))")

        if let isIndoor = workout.isIndoor {
            lines.append("is_indoor: \(isIndoor)")
            lines.append("location_type: \(isIndoor ? "indoor" : "outdoor")")
        }
        if let distance = workout.distance, distance > 0 {
            lines.append("distance_m: \(Int(distance.rounded()))")
            lines.append("distance_km: \(String(format: "%.2f", distance / 1000.0))")
            lines.append("distance_mi: \(String(format: "%.2f", distance / 1609.344))")
            appendStableRateFields(
                for: workout.workoutType,
                meters: distance,
                duration: workout.duration,
                indentation: "",
                lines: &lines
            )
            lines.append("speed_kmh: \(String(format: "%.1f", speedKmh(meters: distance, duration: workout.duration)))")
            lines.append("speed_mph: \(String(format: "%.1f", speedMph(meters: distance, duration: workout.duration)))")
        }
        if let calories = workout.calories, calories > 0 {
            lines.append("calories: \(Int(calories.rounded()))")
        }
        if let avgHR = workout.avgHeartRate {
            lines.append("hr_avg: \(Int(avgHR.rounded()))")
        }
        if let maxHR = workout.maxHeartRate {
            lines.append("hr_max: \(Int(maxHR.rounded()))")
        }
        if let minHR = workout.minHeartRate {
            lines.append("hr_min: \(Int(minHR.rounded()))")
        }
        if let cadence = workout.avgRunningCadence {
            lines.append("cadence_avg_spm: \(Int(cadence.rounded()))")
        }
        if let cadence = workout.avgCyclingCadence {
            lines.append("cadence_avg_rpm: \(Int(cadence.rounded()))")
        }
        if let avgPower = workout.avgPower {
            lines.append("power_avg_w: \(Int(avgPower.rounded()))")
        }
        if let maxPower = workout.maxPower {
            lines.append("power_max_w: \(Int(maxPower.rounded()))")
        }
        if let elevation = workout.elevationGainMeters {
            lines.append("ascent_m: \(Int(elevation.rounded()))")
        }
        if let elevationLoss = workout.elevationLossMeters {
            lines.append("descent_m: \(Int(elevationLoss.rounded()))")
        }
        if !workout.laps.isEmpty {
            lines.append("laps_count: \(workout.laps.count)")
        }
        if !workout.splits.isEmpty {
            lines.append("splits_count: \(workout.splits.count)")
        }
        if !workout.route.isEmpty {
            lines.append("route_points: \(workout.route.count)")
        }
        appendSampleCountsFrontmatter(for: workout, lines: &lines)
        if !zones.isEmpty {
            lines.append("heart_rate_zones:")
            for zone in zones {
                lines.append("  zone\(zone.index):")
                lines.append("    label: \(zone.label)")
                lines.append("    range: \(yamlQuoted(zone.rangeDescription))")
                lines.append("    seconds: \(Int(zone.seconds.rounded()))")
                lines.append("    duration: \(zone.seconds > 0 ? yamlQuoted(zone.durationClock) : "null")")
            }
        }
        appendIntervalFrontmatter(
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
        appendIntervalFrontmatter(
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
        if canonicalFields["canonical_record_json"] != nil {
            let presentationOwnedKeys: Set<String> = [
                "workout_type", "sport", "duration_seconds", "duration_minutes",
                "is_indoor", "location_type", "healthkit_activity_type_raw_value"
            ]
            for (key, value) in canonicalFields.sorted(by: { $0.key < $1.key })
                where !presentationOwnedKeys.contains(key) {
                lines.append(formatYAMLField(key: key, value: value))
            }
        }
        lines.append("---")
        lines.append("")

        lines.append("# \(workout.workoutTypeName) — \(dateString)")
        lines.append("")
        let headline = workoutHeadline(for: workout, converter: converter)
        if !headline.isEmpty {
            lines.append("**\(headline)**")
            lines.append("")
        }
        let nonZeroZones = zones.filter { $0.seconds > 0 }
        if !nonZeroZones.isEmpty {
            let zoneSummary = nonZeroZones
                .map { "\($0.label) \($0.durationClock)" }
                .joined(separator: " · ")
            lines.append("**Zones:** \(zoneSummary)")
            lines.append("")
        }

        lines.append("## Summary")
        lines.append("")
        lines.append("- **Time:** \(timeString)")
        lines.append("- **Duration:** \(formatDurationClock(workout.duration))")
        if let distance = workout.distance, distance > 0 {
            lines.append("- **Distance:** \(converter.formatDistance(distance))")
            if let rate = formattedRate(for: workout.workoutType, meters: distance, duration: workout.duration, converter: converter) {
                lines.append("- **\(rate.label):** \(rate.value)")
            }
        }
        if let calories = workout.calories, calories > 0 {
            lines.append("- **Calories:** \(Int(calories.rounded())) kcal")
        }
        if let avgHR = workout.avgHeartRate {
            lines.append("- **Avg Heart Rate:** \(Int(avgHR.rounded())) bpm")
        }
        if let maxHR = workout.maxHeartRate {
            lines.append("- **Max Heart Rate:** \(Int(maxHR.rounded())) bpm")
        }
        if let minHR = workout.minHeartRate {
            lines.append("- **Min Heart Rate:** \(Int(minHR.rounded())) bpm")
        }
        if let avgPower = workout.avgPower {
            lines.append("- **Avg Power:** \(Int(avgPower.rounded())) W")
        }
        if let maxPower = workout.maxPower {
            lines.append("- **Max Power:** \(Int(maxPower.rounded())) W")
        }
        if let cadence = workout.avgRunningCadence {
            lines.append("- **Avg Cadence:** \(Int(cadence.rounded())) spm")
        }
        if let cadence = workout.avgCyclingCadence {
            lines.append("- **Avg Cadence:** \(Int(cadence.rounded())) rpm")
        }
        if let elevation = workout.elevationGainMeters {
            lines.append("- **Elevation Gain:** \(formatElevation(elevation, converter: converter))")
        }
        if !workout.route.isEmpty {
            lines.append("- **GPS Route:** \(workout.route.count) points")
        }

        if !zones.isEmpty {
            lines.append("")
            lines.append("## Heart Rate Zones")
            lines.append("")
            lines.append("| Zone | Label | Range | Time |")
            lines.append("|---|---|---|---|")
            for zone in zones {
                let time = zone.seconds > 0 ? zone.durationClock : "—"
                lines.append("| Zone \(zone.index) | \(zone.label) | \(zone.rangeDescription) bpm | \(time) |")
            }
        }

        if !workout.laps.isEmpty {
            lines.append("")
            lines.append("## Laps")
            lines.append("")
            lines.append(intervalTableHeader(for: workout.workoutType))
            for (idx, lap) in workout.laps.enumerated() {
                let stats = intervalStats(for: workout, start: lap.startDate, end: lap.endDate)
                lines.append(intervalTableRow(
                    index: idx + 1,
                    distanceMeters: lap.distanceMeters,
                    duration: lap.duration,
                    stats: stats,
                    fallbackAvgHeartRate: nil,
                    workoutType: workout.workoutType,
                    converter: converter
                ))
            }
        }

        if !workout.splits.isEmpty {
            lines.append("")
            lines.append("## Splits")
            lines.append("")
            lines.append(intervalTableHeader(for: workout.workoutType))
            for split in workout.splits {
                let start = split.startDate
                let end = split.startDate.addingTimeInterval(split.duration)
                let stats = intervalStats(for: workout, start: start, end: end)
                lines.append(intervalTableRow(
                    index: split.index,
                    distanceMeters: split.distanceMeters,
                    duration: split.duration,
                    stats: stats,
                    fallbackAvgHeartRate: split.avgHeartRate,
                    workoutType: workout.workoutType,
                    converter: converter
                ))
            }
        }

        if !workout.timeSeries.isEmpty {
            let seriesRows: [(String, Int)] = [
                ("Heart Rate", workout.timeSeries.heartRate.count),
                ("Speed", workout.timeSeries.speed.count),
                ("Power", workout.timeSeries.power.count),
                ("Cadence", workout.timeSeries.cadence.count),
                ("Stride Length", workout.timeSeries.strideLength.count),
                ("Ground Contact", workout.timeSeries.groundContactTime.count),
                ("Vertical Oscillation", workout.timeSeries.verticalOscillation.count),
                ("Altitude", workout.timeSeries.altitude.count)
            ].filter { $0.1 > 0 }

            if !seriesRows.isEmpty {
                lines.append("")
                lines.append("## Samples")
                lines.append("")
                lines.append("| Metric | Samples |")
                lines.append("|---|---:|")
                for (label, count) in seriesRows {
                    lines.append("| \(label) | \(count) |")
                }
            }
        }

        if !workout.metadata.isEmpty {
            lines.append("")
            lines.append("<details>")
            lines.append("<summary>Workout Metadata</summary>")
            lines.append("")
            for (key, value) in workout.metadata.sorted(by: { $0.key < $1.key }) {
                lines.append("- **\(key):** \(value)")
            }
            lines.append("")
            lines.append("</details>")
        }

        return lines.joined(separator: "\n")
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }

    private func formatYAMLField(key: String, value: Any) -> String {
        let renderedKey = yamlKey(key)

        switch value {
        case let array as [String]:
            if array.isEmpty {
                return "\(renderedKey): []"
            }
            var result = "\(renderedKey):"
            for item in array {
                result += "\n  - \(formatYAMLStringScalar(item))"
            }
            return result

        case let dicts as [[String: Any]]:
            if dicts.isEmpty {
                return "\(renderedKey): []"
            }
            var result = "\(renderedKey):"
            for dict in dicts {
                result += "\n  -"
                for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                    result += "\n    \(yamlKey(k)): \(formatYAMLScalar(v))"
                }
            }
            return result

        case let dict as [String: Any]:
            var result = "\(renderedKey):"
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                result += "\n  \(yamlKey(k)): \(formatYAMLScalar(v))"
            }
            return result

        case let doubleVal as Double:
            return "\(renderedKey): \(formatValue(doubleVal))"

        case let intVal as Int:
            return "\(renderedKey): \(intVal)"

        case let intVal as Int64:
            return "\(renderedKey): \(intVal)"

        case let intVal as UInt64:
            return "\(renderedKey): \(intVal)"

        case let boolVal as Bool:
            return "\(renderedKey): \(boolVal)"

        case let stringVal as String:
            return "\(renderedKey): \(formatYAMLStringScalar(stringVal))"

        default:
            return "\(renderedKey): \(formatYAMLStringScalar(String(describing: value)))"
        }
    }

    private func formatYAMLScalar(_ value: Any) -> String {
        switch value {
        case let doubleVal as Double:
            return formatValue(doubleVal)
        case let intVal as Int:
            return "\(intVal)"
        case let intVal as Int64:
            return "\(intVal)"
        case let intVal as UInt64:
            return "\(intVal)"
        case let boolVal as Bool:
            return "\(boolVal)"
        case let stringVal as String:
            return formatYAMLStringScalar(stringVal)
        default:
            return formatYAMLStringScalar(String(describing: value))
        }
    }

    private func formatYAMLStringScalar(_ value: String) -> String {
        shouldQuoteYAMLString(value) ? yamlQuoted(value) : value
    }

    private func yamlKey(_ key: String) -> String {
        shouldQuoteYAMLString(key) ? yamlQuoted(key) : key
    }

    private func shouldQuoteYAMLString(_ value: String) -> Bool {
        if value.isEmpty || value.hasPrefix(" ") || value.hasSuffix(" ") {
            return true
        }
        if let first = value.first, "-?:,[]{}#&*!|>'\"%@`".contains(first) {
            return true
        }
        if value.contains(":") || value.contains("#") || value.contains("\n") ||
            value.contains("\r") || value.contains("\"") || value.contains("\\") {
            return true
        }

        let lowercased = value.lowercased()
        if ["true", "false", "null", "~", "yes", "no", "on", "off"].contains(lowercased) {
            return true
        }

        return value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029:
                return true
            default:
                return false
            }
        }
    }

    private struct WorkoutIntervalStats {
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let avgPower: Double?
        let avgCadence: Double?
    }

    private struct WorkoutIntervalFrontmatter {
        let index: Int
        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let distanceMeters: Double?
        let fallbackAvgHeartRate: Double?
    }

    private func yamlQuoted(_ value: String) -> String {
        "\"\(yamlDoubleQuotedEscaped(value))\""
    }

    private func yamlDoubleQuotedEscaped(_ value: String) -> String {
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

    private func formatDurationClock(_ seconds: TimeInterval) -> String {
        WorkoutHeartRateZone.clockDuration(seconds)
    }

    private func formattedRate(
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

    private func appendStableRateFields(
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

    private func speedKmh(meters: Double, duration: TimeInterval) -> Double {
        guard meters > 0, duration > 0 else { return 0 }
        return (meters / 1000.0) / (duration / 3600.0)
    }

    private func speedMph(meters: Double, duration: TimeInterval) -> Double {
        guard meters > 0, duration > 0 else { return 0 }
        return (meters / 1609.344) / (duration / 3600.0)
    }

    private func workoutHeadline(for workout: WorkoutData, converter: UnitConverter) -> String {
        var parts: [String] = [formatDurationClock(workout.duration)]
        if let distance = workout.distance, distance > 0 {
            parts.append(converter.formatDistance(distance))
        }
        if let avgHR = workout.avgHeartRate {
            parts.append("HR \(Int(avgHR.rounded())) bpm")
        }
        if let calories = workout.calories, calories > 0 {
            parts.append("\(Int(calories.rounded())) cal")
        }
        return parts.joined(separator: " | ")
    }

    private func formatElevation(_ meters: Double, converter: UnitConverter) -> String {
        switch converter.preference {
        case .metric:
            return "\(Int(meters.rounded())) m"
        case .imperial:
            return "\(Int((meters * 3.28084).rounded())) ft"
        }
    }

    private func cadenceUnit(for workoutType: WorkoutType) -> String {
        workoutType == .cycling ? "rpm" : "spm"
    }

    private func appendSampleCountsFrontmatter(for workout: WorkoutData, lines: inout [String]) {
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
        lines.append("sample_counts:")
        for (key, count) in rows {
            lines.append("  \(key): \(count)")
        }
    }

    private func appendIntervalFrontmatter(
        key: String,
        indexKey: String,
        intervals: [WorkoutIntervalFrontmatter],
        workout: WorkoutData,
        converter _: UnitConverter,
        lines: inout [String]
    ) {
        guard !intervals.isEmpty else { return }
        lines.append("\(key):")
        for interval in intervals {
            let stats = intervalStats(for: workout, start: interval.startDate, end: interval.endDate)
            lines.append("  - \(indexKey): \(interval.index)")
            lines.append("    start: \(datetimeFormatter.string(from: interval.startDate))")
            lines.append("    end: \(datetimeFormatter.string(from: interval.endDate))")
            lines.append("    time_sec: \(Int(interval.duration.rounded()))")
            lines.append("    duration: \(yamlQuoted(formatDurationClock(interval.duration)))")

            if let distance = interval.distanceMeters, distance > 0 {
                lines.append("    distance_m: \(Int(distance.rounded()))")
                lines.append("    distance_km: \(String(format: "%.2f", distance / 1000.0))")
                lines.append("    distance_mi: \(String(format: "%.2f", distance / 1609.344))")
                appendStableRateFields(
                    for: workout.workoutType,
                    meters: distance,
                    duration: interval.duration,
                    indentation: "    ",
                    lines: &lines
                )
                if let rate = formattedRate(for: workout.workoutType, meters: distance, duration: interval.duration, converter: UnitConverter(preference: .metric)) {
                    lines.append("    rate_label: \(yamlQuoted(rate.label))")
                    lines.append("    rate: \(yamlQuoted(rate.value))")
                }
                lines.append("    speed_kmh: \(String(format: "%.1f", speedKmh(meters: distance, duration: interval.duration)))")
                lines.append("    speed_mph: \(String(format: "%.1f", speedMph(meters: distance, duration: interval.duration)))")
            }

            let avgHR = interval.fallbackAvgHeartRate ?? stats.avgHeartRate
            if let avgHR {
                lines.append("    hr_avg: \(Int(avgHR.rounded()))")
            }
            if let maxHR = stats.maxHeartRate {
                lines.append("    hr_max: \(Int(maxHR.rounded()))")
            }
            if let avgPower = stats.avgPower {
                lines.append("    power_avg_w: \(Int(avgPower.rounded()))")
            }
            if let avgCadence = stats.avgCadence {
                lines.append("    cadence_avg_\(cadenceUnit(for: workout.workoutType)): \(Int(avgCadence.rounded()))")
            }
        }
    }

    private func intervalTableHeader(for workoutType: WorkoutType) -> String {
        let rateLabel: String
        switch workoutType {
        case .cycling, .skatingSports, .snowSports, .waterSports:
            rateLabel = "Speed"
        default:
            rateLabel = "Pace"
        }
        return "| # | Distance | Time | \(rateLabel) | Avg HR | Max HR | Avg Power | Avg Cadence |\n|---|---|---|---|---|---|---|---|"
    }

    private func intervalTableRow(
        index: Int,
        distanceMeters: Double?,
        duration: TimeInterval,
        stats: WorkoutIntervalStats,
        fallbackAvgHeartRate: Double?,
        workoutType: WorkoutType,
        converter: UnitConverter
    ) -> String {
        let distance = distanceMeters.map { converter.formatDistance($0) } ?? "—"
        let rate: String
        if let meters = distanceMeters,
           let formatted = formattedRate(for: workoutType, meters: meters, duration: duration, converter: converter) {
            rate = formatted.value
        } else {
            rate = "—"
        }

        let avgHR = (fallbackAvgHeartRate ?? stats.avgHeartRate).map { "\(Int($0.rounded())) bpm" } ?? "—"
        let maxHR = stats.maxHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—"
        let power = stats.avgPower.map { "\(Int($0.rounded())) W" } ?? "—"
        let cadence = stats.avgCadence.map { "\(Int($0.rounded())) \(cadenceUnit(for: workoutType))" } ?? "—"

        return "| \(index) | \(distance) | \(formatDurationClock(duration)) | \(rate) | \(avgHR) | \(maxHR) | \(power) | \(cadence) |"
    }

    private func intervalStats(for workout: WorkoutData, start: Date, end: Date) -> WorkoutIntervalStats {
        WorkoutIntervalStats(
            avgHeartRate: averageSampleValue(workout.timeSeries.heartRate, start: start, end: end),
            maxHeartRate: maxSampleValue(workout.timeSeries.heartRate, start: start, end: end),
            avgPower: averageSampleValue(workout.timeSeries.power, start: start, end: end),
            avgCadence: averageSampleValue(workout.timeSeries.cadence, start: start, end: end)
        )
    }

    private func averageSampleValue(_ samples: [TimeSeriesSample], start: Date, end: Date) -> Double? {
        let values = samples
            .filter { $0.timestamp >= start && $0.timestamp < end }
            .map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func maxSampleValue(_ samples: [TimeSeriesSample], start: Date, end: Date) -> Double? {
        samples
            .filter { $0.timestamp >= start && $0.timestamp < end }
            .map(\.value)
            .max()
    }

    // MARK: - Sample Extraction from HealthData

    /// Extract individual samples from HealthData that should be tracked individually.
    /// A canonical archive is authoritative: daily aggregates are never substituted
    /// for an empty, failed, unsupported, or skipped source-record query.
    func extractIndividualSamples(from healthData: HealthData, settings: IndividualTrackingSettings) -> [IndividualHealthSample] {
        guard settings.globalEnabled else { return [] }

        if let archive = healthData.healthKitRecordArchive {
            // Once present, the archive is the sole source of individual-entry
            // identity and payloads. Compatibility arrays may be empty because
            // their query failed, or may contain duplicate projections of the
            // same UUID; neither condition may replace canonical source truth.
            // UUID-matched workout projections are passed only to preserve the
            // established human-readable graph presentation.
            return extractCanonicalRecordSamples(
                from: archive,
                workoutPresentations: healthData.workouts,
                settings: settings
            )
        }

        let allowsAggregateFallback = healthData.healthKitRecordCaptureStatus == .notRequested ||
            healthData.healthKitRecordCaptureStatus == .legacyUnavailable
        var samples: [IndividualHealthSample] = []

        // Compatibility event arrays remain useful for records created before the
        // canonical archive existed or while an older connected app is in use.
        if settings.shouldTrackIndividually("state_of_mind_entries") ||
           settings.shouldTrackIndividually("daily_mood") ||
           settings.shouldTrackIndividually("momentary_emotions") ||
           settings.shouldTrackIndividually("average_valence") {
            samples.append(contentsOf: extractStateOfMindSamples(
                from: healthData.mindfulness,
                settings: settings
            ))
        }
        if settings.shouldTrackIndividually("workouts") {
            samples.append(contentsOf: extractWorkoutSamples(from: healthData.workouts))
        }
        if settings.shouldTrackIndividually("medications"), let medications = healthData.medications {
            samples.append(contentsOf: extractMedicationDoseSamples(from: medications))
        }
        if settings.shouldTrackIndividually("blood_pressure_systolic") ||
           settings.shouldTrackIndividually("blood_pressure_diastolic") {
            samples.append(contentsOf: extractBloodPressureSamples(
                from: healthData,
                allowAggregateFallback: allowsAggregateFallback
            ))
        }
        if settings.shouldTrackIndividually("blood_glucose") {
            samples.append(contentsOf: extractBloodGlucoseSamples(
                from: healthData,
                allowAggregateFallback: allowsAggregateFallback
            ))
        }
        if allowsAggregateFallback,
           settings.shouldTrackIndividually("weight"),
           let weight = healthData.body.weight {
            samples.append(IndividualHealthSample(
                metricId: "weight",
                metricName: "Weight",
                category: .bodyMeasurements,
                timestamp: healthData.date,
                value: weight,
                unit: "kg",
                additionalFields: [
                    "aggregation": "daily_latest",
                    "entry_kind": "daily_aggregate"
                ]
            ))
        }
        samples.append(contentsOf: extractSymptomSamples(
            from: healthData,
            settings: settings,
            allowAggregateFallback: allowsAggregateFallback
        ))

        // Aggregate notes are a compatibility behavior only for explicitly
        // not-requested or legacy archives. Requested capture never silently
        // turns a daily summary into an apparent source event.
        if allowsAggregateFallback {
            var eventLevelMetricIds = Set(samples.map(\.metricId))
            if eventLevelMetricIds.contains("blood_pressure") {
                eventLevelMetricIds.insert("blood_pressure_systolic")
                eventLevelMetricIds.insert("blood_pressure_diastolic")
            }
            samples.append(contentsOf: extractAggregateMetricSamples(
                from: healthData,
                settings: settings,
                excluding: eventLevelMetricIds
            ))
        }

        return samples
    }

    // MARK: - Specific Extractors

    private func extractCanonicalRecordSamples(
        from archive: HealthKitRecordArchive,
        workoutPresentations: [WorkoutData],
        settings: IndividualTrackingSettings
    ) -> [IndividualHealthSample] {
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })
        var emittedIdentities = Set<String>()
        var samples: [IndividualHealthSample] = []

        for record in archive.records {
            let directMetricIDs: [String]
            if let attribution = record.metricAttribution {
                directMetricIDs = attribution.directMetricIDs
            } else if record.includedBecause == .selectedMetric {
                directMetricIDs = record.selectedMetricIDs
            } else {
                directMetricIDs = []
            }

            let specializedMetricIDs: Set<String> = [
                "state_of_mind_entries", "daily_mood", "average_valence", "momentary_emotions",
                "workouts", "medications", "blood_pressure_systolic", "blood_pressure_diastolic"
            ]

            if let specialized = canonicalSpecializedSample(
                for: record,
                directMetricIDs: directMetricIDs,
                archive: archive,
                workoutPresentations: workoutPresentations,
                settings: settings
            ) {
                let emissionIdentity = "\(record.originalUUID.uuidString)|specialized"
                if emittedIdentities.insert(emissionIdentity).inserted {
                    samples.append(specialized)
                }
            }

            for metricID in directMetricIDs
                .filter(settings.shouldTrackIndividually)
                .filter({ !specializedMetricIDs.contains($0) })
                .sorted() {
                let emissionIdentity = "\(record.originalUUID.uuidString)|\(metricID)"
                guard emittedIdentities.insert(emissionIdentity).inserted else { continue }

                let definition = definitions[metricID] ?? fallbackMetricDefinition(
                    metricID: metricID,
                    record: record
                )
                let primary = canonicalPrimaryValue(for: record.payload, fallbackUnit: definition.unit)
                var fields = canonicalFields(for: record, archive: archive)
                fields["canonical_metric_id"] = metricID
                for (key, value) in primary.additionalFields {
                    fields[key] = value
                }

                samples.append(IndividualHealthSample(
                    metricId: metricID,
                    metricName: definition.name,
                    category: definition.category,
                    timestamp: record.startDate,
                    value: primary.value,
                    unit: primary.unit,
                    source: record.sourceRevision.name,
                    additionalFields: fields,
                    originalUUID: record.originalUUID
                ))
            }
        }

        return samples
    }

    private func canonicalSpecializedSample(
        for record: HealthKitRecord,
        directMetricIDs: [String],
        archive: HealthKitRecordArchive,
        workoutPresentations: [WorkoutData],
        settings: IndividualTrackingSettings
    ) -> IndividualHealthSample? {
        var selected = Set(directMetricIDs.filter(settings.shouldTrackIndividually))
        if record.recordKind == .correlation,
           directMetricIDs.contains("blood_pressure"),
           settings.shouldTrackIndividually("blood_pressure_systolic") ||
            settings.shouldTrackIndividually("blood_pressure_diastolic") {
            // Compatibility for early canonical archives that attributed the
            // correlation to one umbrella ID.
            selected.insert("blood_pressure_systolic")
        }
        guard !selected.isEmpty else { return nil }

        switch record.recordKind {
        case .stateOfMind:
            return canonicalStateOfMindSample(
                record,
                selectedMetricIDs: selected,
                archive: archive
            )
        case .workout where selected.contains("workouts"):
            return canonicalWorkoutSample(
                record,
                archive: archive,
                presentation: workoutPresentations.first { $0.sourceUUID == record.originalUUID }
            )
        case .medicationDoseEvent where selected.contains("medications"):
            return canonicalMedicationSample(record, archive: archive)
        case .correlation where !selected.isDisjoint(with: [
            "blood_pressure_systolic", "blood_pressure_diastolic"
        ]):
            return canonicalBloodPressureSample(record, archive: archive)
        default:
            return nil
        }
    }

    private func canonicalStateOfMindSample(
        _ record: HealthKitRecord,
        selectedMetricIDs: Set<String>,
        archive: HealthKitRecordArchive
    ) -> IndividualHealthSample? {
        guard case .structured(_, let payloadFields) = record.payload else { return nil }
        let kind = metadataEnumSymbol(payloadFields["kind"])
        let normalizedKind = kind?.lowercased() ?? ""

        let metricID: String
        let metricName: String
        if normalizedKind.contains("daily"), selectedMetricIDs.contains("daily_mood") {
            metricID = "daily_mood"
            metricName = "Daily Mood"
        } else if normalizedKind.contains("momentary"), selectedMetricIDs.contains("momentary_emotions") {
            metricID = "momentary_emotions"
            metricName = "Momentary Emotion"
        } else if selectedMetricIDs.contains("state_of_mind_entries") {
            metricID = "state_of_mind_entries"
            metricName = "State of Mind Entry"
        } else if selectedMetricIDs.contains("average_valence") {
            // Average valence individual tracking intentionally exposes each
            // source member, never a fabricated daily-average event.
            metricID = "average_valence"
            metricName = "Mood Valence Source Entry"
        } else {
            // A daily-only view must not emit a momentary source record, and
            // vice versa.
            return nil
        }

        let valence = metadataDouble(payloadFields["valence"]) ?? 0
        let labels = metadataEnumSymbols(payloadFields["labels"])
        let associations = metadataEnumSymbols(payloadFields["associations"])
        var fields = canonicalFields(for: record, archive: archive)
        fields["valence"] = valence
        fields["feeling"] = stateOfMindValenceDescription(valence)
        fields["state_of_mind_kind"] = kind ?? "Unknown"
        fields["end_datetime"] = CanonicalRFC3339UTC.string(from: record.endDate)
        if let classification = metadataEnumSymbol(payloadFields["valenceClassification"]) {
            fields["valence_classification"] = classification
        }
        if !labels.isEmpty { fields["labels"] = labels }
        if !associations.isEmpty { fields["associations"] = associations }

        return IndividualHealthSample(
            metricId: metricID,
            metricName: metricName,
            category: .mindfulness,
            timestamp: record.startDate,
            value: valence,
            unit: "",
            source: record.sourceRevision.name,
            additionalFields: fields,
            originalUUID: record.originalUUID
        )
    }

    private func canonicalWorkoutSample(
        _ record: HealthKitRecord,
        archive: HealthKitRecordArchive,
        presentation: WorkoutData?
    ) -> IndividualHealthSample {
        let payloadFields: [String: HealthKitMetadataValue]
        if case .structured(_, let fields) = record.payload {
            payloadFields = fields
        } else {
            payloadFields = [:]
        }

        let activityName = metadataString(payloadFields["activityTypeSymbolicValue"])
            ?? metadataIntegerString(payloadFields["activityTypeRawValue"])
            ?? "Workout"
        var fields = canonicalFields(for: record, archive: archive)
        fields["workout_type"] = activityName
        fields["start_datetime"] = CanonicalRFC3339UTC.string(from: record.startDate)
        fields["end_datetime"] = CanonicalRFC3339UTC.string(from: record.endDate)
        if let duration = metadataDouble(payloadFields["durationSeconds"]) {
            fields["duration_seconds"] = duration
            fields["duration_minutes"] = duration / 60
        }
        if let isIndoor = metadataBool(payloadFields["isIndoor"]) {
            fields["is_indoor"] = isIndoor
            fields["location_type"] = isIndoor ? "indoor" : "outdoor"
        }
        if let rawValue = metadataIntegerString(payloadFields["activityTypeRawValue"]) {
            fields["healthkit_activity_type_raw_value"] = rawValue
        }

        return IndividualHealthSample(
            metricId: "workouts",
            metricName: "Workout",
            category: .workouts,
            timestamp: record.startDate,
            value: activityName,
            unit: "",
            source: record.sourceRevision.name,
            additionalFields: fields,
            originalUUID: record.originalUUID,
            // The canonical record above remains identity/payload authority.
            // A UUID-matched compatibility projection is presentation-only so
            // existing lap/split/route charts remain unchanged when available;
            // canonical-only exports still produce a complete source note.
            workout: presentation
        )
    }

    private func canonicalMedicationSample(
        _ record: HealthKitRecord,
        archive: HealthKitRecordArchive
    ) -> IndividualHealthSample {
        let payloadFields: [String: HealthKitMetadataValue]
        if case .structured(_, let fields) = record.payload {
            payloadFields = fields
        } else {
            payloadFields = [:]
        }

        let medicationName = metadataString(payloadFields["medicationName"])
            ?? metadataString(payloadFields["medicationConceptIdentifier"])
            ?? "Medication"
        let doseQuantity = metadataDouble(payloadFields["doseQuantity"])
        let doseUnit = metadataString(payloadFields["unit"]) ?? ""
        var fields = canonicalFields(for: record, archive: archive)
        fields["event_id"] = record.originalUUID.uuidString
        fields["medication"] = medicationName
        fields["medication_name"] = medicationName
        fields["start_datetime"] = CanonicalRFC3339UTC.string(from: record.startDate)
        fields["end_datetime"] = CanonicalRFC3339UTC.string(from: record.endDate)
        if let concept = metadataString(payloadFields["medicationConceptIdentifier"]) {
            fields["medication_concept_identifier"] = concept
        }
        if let status = metadataEnumSymbol(payloadFields["logStatus"]) {
            fields["status"] = status
            fields["status_display"] = status
        }
        if let schedule = metadataEnumSymbol(payloadFields["scheduleType"]) {
            fields["schedule_type"] = schedule
        }
        if let scheduledDate = metadataDate(payloadFields["scheduledDate"]) {
            fields["scheduled_datetime"] = CanonicalRFC3339UTC.string(from: scheduledDate)
        }
        if let doseQuantity { fields["dose_quantity"] = doseQuantity }
        if let scheduledDose = metadataDouble(payloadFields["scheduledDoseQuantity"]) {
            fields["scheduled_dose_quantity"] = scheduledDose
        }
        if !doseUnit.isEmpty { fields["dose_unit"] = doseUnit }

        return IndividualHealthSample(
            metricId: "medications",
            metricName: "Medication Dose",
            category: .medications,
            timestamp: record.startDate,
            value: doseQuantity ?? 1,
            unit: doseUnit,
            source: record.sourceRevision.name,
            additionalFields: fields,
            originalUUID: record.originalUUID
        )
    }

    private func canonicalBloodPressureSample(
        _ record: HealthKitRecord,
        archive: HealthKitRecordArchive
    ) -> IndividualHealthSample {
        let componentUUIDs: [UUID]
        if case .correlation(let uuids) = record.payload {
            componentUUIDs = uuids
        } else {
            componentUUIDs = record.relationships.compactMap(\.targetUUID)
        }
        let components = archive.records.filter { componentUUIDs.contains($0.originalUUID) }
        func quantity(containing identifierFragment: String) -> Double? {
            components.first {
                $0.objectTypeIdentifier.localizedCaseInsensitiveContains(identifierFragment)
            }.flatMap {
                guard case .quantity(let quantity) = $0.payload else { return nil }
                return quantity.value
            }
        }
        let systolic = quantity(containing: "BloodPressureSystolic")
        let diastolic = quantity(containing: "BloodPressureDiastolic")
        let displayValue: String
        if let systolic, let diastolic {
            displayValue = "\(formatValue(systolic))/\(formatValue(diastolic))"
        } else {
            displayValue = "Blood Pressure"
        }

        var fields = canonicalFields(for: record, archive: archive)
        fields["end_datetime"] = CanonicalRFC3339UTC.string(from: record.endDate)
        fields["component_uuids"] = componentUUIDs.map(\.uuidString).sorted()
        if let systolic { fields["systolic"] = systolic }
        if let diastolic { fields["diastolic"] = diastolic }

        return IndividualHealthSample(
            metricId: "blood_pressure",
            metricName: "Blood Pressure",
            category: .vitals,
            timestamp: record.startDate,
            value: displayValue,
            unit: "mmHg",
            source: record.sourceRevision.name,
            additionalFields: fields,
            originalUUID: record.originalUUID
        )
    }

    private func metadataString(_ value: HealthKitMetadataValue?) -> String? {
        guard let value else { return nil }
        if case .string(let string) = value { return string }
        return nil
    }

    private func metadataDouble(_ value: HealthKitMetadataValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .floatingPoint(let number): return number
        case .signedInteger(let number): return Double(number)
        case .unsignedInteger(let number): return Double(number)
        case .quantity(let quantity): return quantity.value
        default: return nil
        }
    }

    private func metadataBool(_ value: HealthKitMetadataValue?) -> Bool? {
        guard let value, case .bool(let bool) = value else { return nil }
        return bool
    }

    private func metadataDate(_ value: HealthKitMetadataValue?) -> Date? {
        guard let value, case .date(let date) = value else { return nil }
        return date
    }

    private func metadataIntegerString(_ value: HealthKitMetadataValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .signedInteger(let number): return String(number)
        case .unsignedInteger(let number): return String(number)
        default: return nil
        }
    }

    private func metadataEnumSymbol(_ value: HealthKitMetadataValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let symbol):
            return symbol
        case .dictionary(let fields):
            if case .string(let symbol)? = fields["symbolicValue"] { return symbol }
            return nil
        default:
            return nil
        }
    }

    private func metadataEnumSymbols(_ value: HealthKitMetadataValue?) -> [String] {
        guard let value, case .array(let values) = value else { return [] }
        return values.compactMap(metadataEnumSymbol)
    }

    private func stateOfMindValenceDescription(_ valence: Double) -> String {
        switch valence {
        case ..<(-0.6): return "Very Unpleasant"
        case -0.6 ..< -0.2: return "Unpleasant"
        case -0.2 ..< 0.2: return "Neutral"
        case 0.2 ..< 0.6: return "Pleasant"
        default: return "Very Pleasant"
        }
    }

    private func fallbackMetricDefinition(
        metricID: String,
        record: HealthKitRecord
    ) -> HealthMetricDefinition {
        let category: HealthMetricCategory
        switch record.recordKind {
        case .workout, .workoutRoute:
            category = .workouts
        case .stateOfMind:
            category = .mindfulness
        case .medicationDoseEvent:
            category = .medications
        default:
            category = .other
        }
        return HealthMetricDefinition(
            id: metricID,
            name: metricID.replacingOccurrences(of: "_", with: " ").capitalized,
            category: category,
            unit: "",
            healthKitIdentifier: record.objectTypeIdentifier,
            metricType: .quantity,
            aggregation: .mostRecent
        )
    }

    private func canonicalPrimaryValue(
        for payload: HealthKitRecordPayload,
        fallbackUnit: String
    ) -> (value: Any, unit: String, additionalFields: [String: Any]) {
        switch payload {
        case .quantity(let quantity):
            return (quantity.value, quantity.unit, ["quantity_value": quantity.value])
        case .category(let category):
            var fields: [String: Any] = ["category_raw_value": category.rawValue]
            if let symbolicValue = category.symbolicValue {
                fields["category_symbolic_value"] = symbolicValue
                return (symbolicValue, fallbackUnit, fields)
            }
            return (category.rawValue, fallbackUnit, fields)
        case .correlation(let componentUUIDs):
            return (
                "correlation",
                fallbackUnit,
                ["component_uuids": componentUUIDs.map(\.uuidString).sorted()]
            )
        case .structured(let kind, _):
            return (kind, fallbackUnit, ["structured_kind": kind])
        case .binaryArtifactReference(let artifact):
            return (artifact.identifier, fallbackUnit, ["artifact_identifier": artifact.identifier])
        case .unknown(let kind, _):
            return (kind, fallbackUnit, ["payload_kind": kind])
        }
    }

    private func canonicalFields(
        for record: HealthKitRecord,
        archive: HealthKitRecordArchive
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "entry_kind": "healthkit_record",
            "original_uuid": record.originalUUID.uuidString,
            "object_type_identifier": record.objectTypeIdentifier,
            "record_kind": record.recordKind.rawValue,
            "start_datetime": CanonicalRFC3339UTC.string(from: record.startDate),
            "end_datetime": CanonicalRFC3339UTC.string(from: record.endDate),
            "has_undetermined_duration": record.hasUndeterminedDuration,
            "selected_metric_ids": record.selectedMetricIDs.sorted(),
            "included_because": record.includedBecause.rawValue,
            "raw_record_schema": archive.schemaIdentifier,
            "raw_record_schema_version": archive.recordSchemaVersion
        ]

        guard let canonicalRecord = try? HealthKitRecordArchiveSerializer.recordString(for: record) else {
            return fields
        }
        fields["canonical_record_json"] = canonicalRecord

        guard let data = canonicalRecord.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fields
        }
        let nestedFields = [
            "source_revision": "source_revision_json",
            "device": "device_json",
            "metadata": "metadata_json",
            "payload": "payload_json",
            "relationships": "relationships_json",
            "metric_attribution": "metric_attribution_json"
        ]
        for (canonicalKey, fieldKey) in nestedFields {
            guard let value = object[canonicalKey], !(value is NSNull),
                  let json = stableJSONString(value) else { continue }
            fields[fieldKey] = json
        }
        if let canonicalKind = object["record_kind"] as? String {
            fields["record_kind"] = canonicalKind
        }
        if let canonicalReason = object["included_because"] as? String {
            fields["included_because"] = canonicalReason
        }
        return fields
    }

    private func stableJSONString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func extractStateOfMindSamples(
        from mindfulness: MindfulnessData,
        settings: IndividualTrackingSettings
    ) -> [IndividualHealthSample] {
        mindfulness.stateOfMind.compactMap { entry in
            let metricId: String
            let metricName: String
            if entry.kind == .dailyMood, settings.shouldTrackIndividually("daily_mood") {
                metricId = "daily_mood"
                metricName = "Daily Mood"
            } else if entry.kind == .momentaryEmotion,
                      settings.shouldTrackIndividually("momentary_emotions") {
                metricId = "momentary_emotions"
                metricName = "Momentary Emotion"
            } else if settings.shouldTrackIndividually("state_of_mind_entries") {
                metricId = "state_of_mind_entries"
                metricName = "State of Mind Entry"
            } else if settings.shouldTrackIndividually("average_valence") {
                metricId = "average_valence"
                metricName = "Mood Valence Source Entry"
            } else {
                return nil
            }

            var additionalFields: [String: Any] = [
                "entry_kind": "granular_compatibility",
                "valence": entry.valence,
                "feeling": entry.valenceDescription
            ]

            if !entry.labels.isEmpty {
                additionalFields["labels"] = entry.labels
            }

            if !entry.associations.isEmpty {
                additionalFields["associations"] = entry.associations
            }

            return IndividualHealthSample(
                metricId: metricId,
                metricName: metricName,
                category: .mindfulness,
                timestamp: entry.timestamp,
                value: entry.valence,
                unit: "",
                source: entry.sourceRevision?.name,
                additionalFields: additionalFields,
                originalUUID: entry.id
            )
        }
    }

    private func extractWorkoutSamples(from workouts: [WorkoutData]) -> [IndividualHealthSample] {
        return workouts.map { workout in
            var additionalFields: [String: Any] = [
                "workout_type": workout.workoutTypeName,
                "sport": workout.workoutSportName,
                "duration_minutes": Int(workout.duration / 60)
            ]

            if let healthKitActivityType = workout.healthKitActivityType {
                additionalFields["healthkit_activity_type"] = healthKitActivityType
            }
            if let rawValue = workout.healthKitActivityTypeRawValue {
                additionalFields["healthkit_activity_type_raw_value"] = rawValue
            }
            if let calories = workout.calories {
                additionalFields["calories"] = Int(calories)
            }
            if let isIndoor = workout.isIndoor {
                additionalFields["is_indoor"] = isIndoor
                additionalFields["location_type"] = isIndoor ? "indoor" : "outdoor"
            }

            if let distance = workout.distance {
                additionalFields["distance_meters"] = Int(distance)
            }
            if let avgHR = workout.avgHeartRate {
                additionalFields["avg_heart_rate"] = Int(avgHR.rounded())
            }
            if let maxHR = workout.maxHeartRate {
                additionalFields["max_heart_rate"] = Int(maxHR.rounded())
            }
            if let minHR = workout.minHeartRate {
                additionalFields["min_heart_rate"] = Int(minHR.rounded())
            }
            if let cadence = workout.avgRunningCadence {
                additionalFields["avg_running_cadence"] = Int(cadence.rounded())
            }
            if let stride = workout.avgStrideLength {
                additionalFields["avg_stride_length_m"] = stride
            }
            if let gct = workout.avgGroundContactTime {
                additionalFields["avg_ground_contact_ms"] = Int(gct.rounded())
            }
            if let vertOsc = workout.avgVerticalOscillation {
                additionalFields["avg_vertical_oscillation_cm"] = vertOsc
            }
            if let cyclingCadence = workout.avgCyclingCadence {
                additionalFields["avg_cycling_cadence"] = Int(cyclingCadence.rounded())
            }
            if let avgPow = workout.avgPower {
                additionalFields["avg_power_w"] = Int(avgPow.rounded())
            }
            if let maxPow = workout.maxPower {
                additionalFields["max_power_w"] = Int(maxPow.rounded())
            }
            if let elevation = workout.elevationGainMeters {
                additionalFields["elevation_gain_m"] = Int(elevation.rounded())
            }
            if !workout.laps.isEmpty {
                additionalFields["laps_count"] = workout.laps.count
            }
            if !workout.splits.isEmpty {
                additionalFields["splits_count"] = workout.splits.count
            }
            if !workout.route.isEmpty {
                additionalFields["route_points"] = workout.route.count
            }
            if !workout.timeSeries.isEmpty {
                additionalFields["heart_rate_samples"] = workout.timeSeries.heartRate.count
                additionalFields["power_samples"] = workout.timeSeries.power.count
                additionalFields["cadence_samples"] = workout.timeSeries.cadence.count
            }

            return IndividualHealthSample(
                metricId: "workouts",
                metricName: "Workout",
                category: .workouts,
                timestamp: workout.startTime,
                value: workout.workoutTypeName,
                unit: "",
                source: workout.sourceRevision?.name,
                additionalFields: additionalFields,
                originalUUID: workout.sourceUUID ?? workout.id,
                workout: workout
            )
        }
    }

    private func extractMedicationDoseSamples(from medications: MedicationsData) -> [IndividualHealthSample] {
        medications.doseEvents.map { event in
            var additionalFields: [String: Any] = [
                "entry_kind": "granular_compatibility",
                "event_id": event.id.uuidString,
                "medication": event.displayMedicationName,
                "medication_name": event.displayMedicationName,
                "status": event.logStatus.rawValue,
                "status_display": event.logStatus.displayName,
                "schedule_type": event.scheduleType.rawValue,
                "medication_concept_identifier": event.medicationConceptIdentifier,
                "start_datetime": datetimeFormatter.string(from: event.startDate),
                "end_datetime": datetimeFormatter.string(from: event.endDate)
            ]

            if let doseQuantity = event.doseQuantity {
                additionalFields["dose_quantity"] = doseQuantity
            }
            if let scheduledDate = event.scheduledDate {
                additionalFields["scheduled_datetime"] = datetimeFormatter.string(from: scheduledDate)
            }
            if let scheduledDoseQuantity = event.scheduledDoseQuantity {
                additionalFields["scheduled_dose_quantity"] = scheduledDoseQuantity
            }
            if !event.unit.isEmpty {
                additionalFields["dose_unit"] = event.unit
            }
            if !event.metadata.isEmpty {
                additionalFields["metadata"] = event.metadata
            }

            return IndividualHealthSample(
                metricId: "medications",
                metricName: "Medication Dose",
                category: .medications,
                timestamp: event.startDate,
                value: event.doseQuantity ?? 1,
                unit: event.unit,
                additionalFields: additionalFields,
                originalUUID: event.id
            )
        }
    }

    private func extractBloodPressureSamples(
        from healthData: HealthData,
        allowAggregateFallback: Bool
    ) -> [IndividualHealthSample] {
        if !healthData.vitals.bloodPressureSamples.isEmpty {
            return healthData.vitals.bloodPressureSamples.map { reading in
                var additionalFields: [String: Any] = [
                    "entry_kind": "granular_compatibility",
                    "systolic": reading.systolic,
                    "diastolic": reading.diastolic,
                    "end_datetime": datetimeFormatter.string(from: reading.endDate)
                ]
                if !reading.metadata.isEmpty {
                    additionalFields["metadata"] = reading.metadata
                }

                return IndividualHealthSample(
                    metricId: "blood_pressure",
                    metricName: "Blood Pressure",
                    category: .vitals,
                    timestamp: reading.startDate,
                    value: "\(formatValue(reading.systolic))/\(formatValue(reading.diastolic))",
                    unit: "mmHg",
                    source: reading.sourceRevision?.name,
                    additionalFields: additionalFields,
                    originalUUID: reading.correlationUUID
                )
            }
        }

        guard allowAggregateFallback,
              let systolic = healthData.vitals.bloodPressureSystolic,
              let diastolic = healthData.vitals.bloodPressureDiastolic else {
            return []
        }

        return [IndividualHealthSample(
            metricId: "blood_pressure",
            metricName: "Blood Pressure",
            category: .vitals,
            timestamp: healthData.date,
            value: "\(formatValue(systolic))/\(formatValue(diastolic))",
            unit: "mmHg",
            additionalFields: [
                "systolic": systolic,
                "diastolic": diastolic,
                "aggregation": "daily_average",
                "entry_kind": "daily_aggregate"
            ]
        )]
    }

    private func extractBloodGlucoseSamples(
        from healthData: HealthData,
        allowAggregateFallback: Bool
    ) -> [IndividualHealthSample] {
        if !healthData.vitals.bloodGlucoseSamples.isEmpty {
            return healthData.vitals.bloodGlucoseSamples.map { reading in
                var fields: [String: Any] = ["entry_kind": "granular_compatibility"]
                if !reading.metadata.isEmpty {
                    fields["metadata"] = reading.metadata
                }
                return IndividualHealthSample(
                    metricId: "blood_glucose",
                    metricName: "Blood Glucose",
                    category: .vitals,
                    timestamp: reading.timestamp,
                    value: reading.value,
                    unit: "mg/dL",
                    source: reading.metadata["source"],
                    additionalFields: fields
                )
            }
        }

        guard allowAggregateFallback, let glucose = healthData.vitals.bloodGlucose else {
            return []
        }
        return [IndividualHealthSample(
            metricId: "blood_glucose",
            metricName: "Blood Glucose",
            category: .vitals,
            timestamp: healthData.date,
            value: glucose,
            unit: "mg/dL",
            additionalFields: [
                "aggregation": "daily_average",
                "entry_kind": "daily_aggregate"
            ]
        )]
    }

    private func extractSymptomSamples(
        from healthData: HealthData,
        settings: IndividualTrackingSettings,
        allowAggregateFallback: Bool
    ) -> [IndividualHealthSample] {
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.symptoms.map { ($0.id, $0) })
        let granular = healthData.symptoms.samples.compactMap { symptom -> IndividualHealthSample? in
            guard settings.shouldTrackIndividually(symptom.metricId),
                  let definition = definitions[symptom.metricId] else { return nil }
            var fields: [String: Any] = [
                "entry_kind": "granular_compatibility",
                "category_raw_value": symptom.rawValue,
                "end_datetime": CanonicalRFC3339UTC.string(from: symptom.endDate)
            ]
            if let symbolicValue = symptom.symbolicValue {
                fields["category_symbolic_value"] = symbolicValue
            }
            if let originalUUID = symptom.originalUUID {
                fields["original_uuid"] = originalUUID.uuidString
            }
            if !symptom.metadata.isEmpty {
                fields["metadata"] = symptom.metadata
            }
            return IndividualHealthSample(
                metricId: symptom.metricId,
                metricName: definition.name,
                category: .symptoms,
                timestamp: symptom.startDate,
                value: symptom.symbolicValue ?? String(symptom.rawValue),
                unit: definition.unit,
                source: symptom.source,
                additionalFields: fields,
                originalUUID: symptom.originalUUID
            )
        }

        guard allowAggregateFallback else { return granular }
        let granularMetricIDs = Set(granular.map(\.metricId))
        let aggregates = healthData.symptoms.counts.keys.sorted().compactMap { metricID -> IndividualHealthSample? in
            guard !granularMetricIDs.contains(metricID),
                  settings.shouldTrackIndividually(metricID),
                  let count = healthData.symptoms.counts[metricID],
                  let definition = definitions[metricID] else { return nil }
            return IndividualHealthSample(
                metricId: metricID,
                metricName: definition.name,
                category: .symptoms,
                timestamp: healthData.date,
                value: count,
                unit: definition.unit,
                additionalFields: [
                    "aggregation": "daily_count",
                    "entry_kind": "daily_aggregate"
                ]
            )
        }
        return granular + aggregates
    }

    private func extractAggregateMetricSamples(
        from healthData: HealthData,
        settings: IndividualTrackingSettings,
        excluding eventLevelMetricIds: Set<String>
    ) -> [IndividualHealthSample] {
        let values = healthData.allMetricsDictionary(using: UnitConverter(preference: .metric))

        return HealthMetrics.all.compactMap { metric in
            guard settings.shouldTrackIndividually(metric.id),
                  !eventLevelMetricIds.contains(metric.id) else {
                return nil
            }

            let exportedFields = HealthMetricExportMapping.frontmatterKeys(for: metric.id)
                .compactMap { key -> (String, String)? in
                    guard let value = values[key] else { return nil }
                    return (key, value)
                }

            guard let primaryField = exportedFields.first else { return nil }

            let canonicalConverter = UnitConverter(preference: .metric)
            let primaryUnit = HealthMetricDataDictionary.unit(for: primaryField.0, converter: canonicalConverter) ?? metric.unit
            var fieldUnits: [String: Any] = [:]
            var additionalFields: [String: Any] = [
                "aggregation": metric.aggregationDescription,
                "entry_kind": "daily_aggregate"
            ]
            for (key, value) in exportedFields {
                additionalFields[key] = value
                if let unit = HealthMetricDataDictionary.unit(for: key, converter: canonicalConverter), !unit.isEmpty {
                    fieldUnits[key] = unit
                }
            }
            if !fieldUnits.isEmpty {
                additionalFields["field_units"] = fieldUnits
            }

            return IndividualHealthSample(
                metricId: metric.id,
                metricName: metric.name,
                category: metric.category,
                timestamp: healthData.date,
                value: primaryField.1,
                unit: primaryUnit,
                additionalFields: additionalFields
            )
        }
    }
}

private extension HealthMetricDefinition.AggregationType {
    var descriptionForIndividualEntry: String {
        switch self {
        case .cumulative: return "daily_sum"
        case .discreteAvg: return "daily_average"
        case .discreteMin: return "daily_minimum"
        case .discreteMax: return "daily_maximum"
        case .mostRecent: return "daily_latest"
        case .duration: return "daily_duration"
        case .count: return "daily_count"
        }
    }
}

private extension HealthMetricDefinition {
    var aggregationDescription: String {
        aggregation.descriptionForIndividualEntry
    }
}


