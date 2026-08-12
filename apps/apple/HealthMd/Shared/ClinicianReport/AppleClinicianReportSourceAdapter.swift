import Foundation

/// Converts already-captured canonical HealthKit records into bounded report observations.
/// It never pairs blood pressure components by timestamp or value.
nonisolated struct AppleClinicianReportSourceAdapter {
    private static let identifiers: [String: ReportMetric] = [
        "HKQuantityTypeIdentifierHeartRate": .heartRate,
        "HKQuantityTypeIdentifierRestingHeartRate": .restingHeartRate,
        "HKQuantityTypeIdentifierBodyMass": .weight,
        "HKQuantityTypeIdentifierBloodGlucose": .bloodGlucose,
        "HKQuantityTypeIdentifierOxygenSaturation": .oxygenSaturation,
        "HKQuantityTypeIdentifierRespiratoryRate": .respiratoryRate,
        "HKQuantityTypeIdentifierBodyTemperature": .bodyTemperature
    ]
    private static let systolicIdentifier = "HKQuantityTypeIdentifierBloodPressureSystolic"
    private static let diastolicIdentifier = "HKQuantityTypeIdentifierBloodPressureDiastolic"
    private static let bloodPressureCorrelationIdentifier = "HKCorrelationTypeIdentifierBloodPressure"

    struct DayValues {
        var scalars: [ScalarReportObservation] = []
        var bloodPressure: [BloodPressureReportObservation] = []
        var daily: [DailyReportValue] = []
        var sleep: [SleepReportObservation] = []
        var workouts: [WorkoutReportObservation] = []
        var canonicalMetrics: Set<ReportMetric> = []
        var warnings: [String] = []
    }

    func adapt(
        _ healthData: HealthData,
        configuration: ReportConfiguration,
        calendar: Calendar,
        copy: ClinicianReportCopy = ClinicianReportCopy()
    ) -> DayValues {
        var values = DayValues()
        let day = calendar.startOfDay(for: healthData.date)
        let archive = healthData.healthKitRecordArchive

        if let archive {
            if archive.captureStatus == .partial {
                values.warnings.append(copy.format(.warning_apple_source_failure_date, isoDate(day, calendar: calendar)))
            }
            values.warnings.append(contentsOf: archive.integrityWarnings.map { _ in
                copy.format(.warning_apple_integrity_date, isoDate(day, calendar: calendar))
            })
            adaptCanonical(archive.records, selected: configuration.selectedMetrics, calendar: calendar, copy: copy, into: &values)
        } else {
            values.warnings.append(copy.string(.warning_apple_summary_fallback))
        }

        if !healthData.partialFailures.isEmpty {
            values.warnings.append(copy.format(.warning_apple_read_failure_date, isoDate(day, calendar: calendar)))
        }

        var canonicalMetrics = values.canonicalMetrics
        addCompatibilitySamples(healthData, configuration: configuration, copy: copy, canonicalMetrics: &canonicalMetrics, into: &values)
        values.canonicalMetrics = canonicalMetrics
        addFallbacks(healthData, day: day, configuration: configuration, canonicalMetrics: values.canonicalMetrics, into: &values)

        if configuration.selectedMetrics.contains(.sleepDuration), healthData.sleep.totalDuration > 0 {
            // The compatibility aggregate uses Health.md's noon-to-noon sleep window,
            // while the canonical archive is owned by a midnight-to-midnight day. Do not
            // attribute the aggregate to archive sources without proven window membership.
            values.sleep.append(SleepReportObservation(
                date: day,
                durationMinutes: healthData.sleep.totalDuration / 60,
                stableID: nil,
                source: nil
            ))
        }

        if configuration.selectedMetrics.contains(.steps), let steps = healthData.activity.steps {
            values.daily.append(DailyReportValue(metric: .steps, date: day, value: Double(steps)))
        }

        if configuration.selectedMetrics.contains(.workouts) {
            values.workouts.append(contentsOf: healthData.workouts.map { workout in
                WorkoutReportObservation(
                    timestamp: workout.startTime,
                    type: workout.workoutType,
                    durationMinutes: workout.duration / 60,
                    stableID: workout.sourceUUID.map { "healthkit:\($0.uuidString)" },
                    source: source(workout.sourceRevision, device: workout.device, metadata: stringMetadata(workout.metadata), copy: copy)
                )
            })
        }
        return values
    }

    private func adaptCanonical(
        _ records: [HealthKitRecord],
        selected: Set<ReportMetric>,
        calendar: Calendar,
        copy: ClinicianReportCopy,
        into values: inout DayValues
    ) {
        var recordsByID: [UUID: HealthKitRecord] = [:]
        for record in records where !recordsByID.keys.contains(record.originalUUID) {
            recordsByID[record.originalUUID] = record
        }
        var seen = Set<UUID>()

        for record in records where seen.insert(record.originalUUID).inserted {
            guard case .quantity(let payload) = record.payload,
                  let metric = Self.identifiers[record.objectTypeIdentifier],
                  selected.contains(metric) else { continue }
            values.canonicalMetrics.insert(metric)
            let provenance = source(record, copy: copy)
            let normalizedValue = normalizedValue(payload.value, for: metric)
            if metric == .weight || metric == .restingHeartRate {
                let candidate = DailyReportValue(
                    metric: metric,
                    date: calendar.startOfDay(for: record.startDate),
                    value: normalizedValue,
                    timestamp: record.startDate,
                    stableID: "healthkit:\(record.originalUUID.uuidString)",
                    source: provenance
                )
                // These report sections are daily series. HealthKit can contain several
                // same-day records, so retain the deterministic most-recent value rather
                // than presenting each one as a separate "daily" value.
                if let index = values.daily.firstIndex(where: { $0.metric == metric }) {
                    let existing = values.daily[index]
                    if (existing.timestamp ?? existing.date) < record.startDate {
                        values.daily[index] = candidate
                    }
                } else {
                    values.daily.append(candidate)
                }
            } else {
                values.scalars.append(ScalarReportObservation(
                    metric: metric,
                    timestamp: record.startDate,
                    value: normalizedValue,
                    stableID: "healthkit:\(record.originalUUID.uuidString)",
                    source: provenance
                ))
            }
        }

        guard selected.contains(.bloodPressure) else { return }
        for correlation in records where correlation.objectTypeIdentifier == Self.bloodPressureCorrelationIdentifier {
            guard case .correlation(let componentUUIDs) = correlation.payload else { continue }
            let components = componentUUIDs.compactMap { recordsByID[$0] }
            let systolic = components.filter { $0.objectTypeIdentifier == Self.systolicIdentifier }
            let diastolic = components.filter { $0.objectTypeIdentifier == Self.diastolicIdentifier }
            guard systolic.count == 1, diastolic.count == 1,
                  case .quantity(let systolicPayload) = systolic[0].payload,
                  case .quantity(let diastolicPayload) = diastolic[0].payload else { continue }
            values.canonicalMetrics.insert(.bloodPressure)
            values.bloodPressure.append(BloodPressureReportObservation(
                timestamp: correlation.startDate,
                systolic: systolicPayload.value,
                diastolic: diastolicPayload.value,
                stableID: "healthkit:\(correlation.originalUUID.uuidString)",
                source: source(correlation, copy: copy)
            ))
        }
    }

    /// HealthKit's percent unit stores oxygen saturation as a fraction (`0.96` = 96%).
    /// Older compatibility fixtures may contain whole-percent values, so normalize only
    /// values above 1 instead of dividing every canonical `%` payload a second time.
    private func normalizedValue(_ value: Double, for metric: ReportMetric) -> Double {
        guard metric == .oxygenSaturation, value > 1 else { return value }
        return value / 100
    }

    private func addCompatibilitySamples(
        _ data: HealthData,
        configuration: ReportConfiguration,
        copy: ClinicianReportCopy,
        canonicalMetrics: inout Set<ReportMetric>,
        into values: inout DayValues
    ) {
        func add(_ metric: ReportMetric, _ samples: [TimeSample]) {
            guard configuration.selectedMetrics.contains(metric), !canonicalMetrics.contains(metric), !samples.isEmpty else { return }
            canonicalMetrics.insert(metric)
            values.scalars.append(contentsOf: samples.map { sample in
                let metadata = stringMetadata(sample.metadata)
                let manual = metadata["HKWasUserEntered"]?.isTrue == true || metadata["HKMetadataKeyWasUserEntered"]?.isTrue == true
                return ScalarReportObservation(
                    metric: metric,
                    timestamp: sample.timestamp,
                    value: sample.value,
                    source: manual ? ReportSource(label: copy.string(.manual_entry), isManualEntry: true) : nil
                )
            })
        }
        add(.heartRate, data.heart.heartRateSamples)
        add(.bloodGlucose, data.vitals.bloodGlucoseSamples)
        add(.oxygenSaturation, data.vitals.bloodOxygenSamples)
        add(.respiratoryRate, data.vitals.respiratoryRateSamples)
    }

    private func addFallbacks(
        _ data: HealthData,
        day: Date,
        configuration: ReportConfiguration,
        canonicalMetrics: Set<ReportMetric>,
        into values: inout DayValues
    ) {
        func add(_ metric: ReportMetric, _ value: Double?) {
            guard configuration.selectedMetrics.contains(metric), !canonicalMetrics.contains(metric), let value else { return }
            values.daily.append(DailyReportValue(metric: metric, date: day, value: value))
        }
        add(.restingHeartRate, data.heart.restingHeartRate)
        add(.heartRate, data.heart.averageHeartRate)
        add(.weight, data.body.weight)
        add(.bloodGlucose, data.vitals.bloodGlucoseAvg)
        add(.oxygenSaturation, data.vitals.bloodOxygenAvg)
        add(.respiratoryRate, data.vitals.respiratoryRateAvg)
        add(.bodyTemperature, data.vitals.bodyTemperatureAvg)
        // Blood pressure daily averages are not report readings and cannot establish a trusted pair.
    }

    private func source(_ record: HealthKitRecord, copy: ClinicianReportCopy) -> ReportSource? {
        source(record.sourceRevision, device: record.device, metadata: record.metadata, copy: copy)
    }

    private func source(
        _ revision: HealthKitSourceRevision?,
        device: HealthKitDeviceProvenance?,
        metadata: [String: HealthKitMetadataValue],
        copy: ClinicianReportCopy
    ) -> ReportSource? {
        let manual = metadata["HKWasUserEntered"]?.isTrue == true || metadata["HKMetadataKeyWasUserEntered"]?.isTrue == true || metadata["user_entered"]?.isTrue == true
        let sourceName = revision?.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let deviceName = [device?.manufacturer, device?.model, device?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .uniqued()
            .joined(separator: " ")
            .nilIfEmpty
        let label: String?
        if let sourceName, let deviceName, !deviceName.localizedCaseInsensitiveContains(sourceName) {
            label = "\(sourceName) — \(deviceName)"
        } else {
            label = sourceName ?? deviceName ?? (manual ? copy.string(.manual_entry) : nil)
        }
        return label.map { ReportSource(label: $0, isManualEntry: manual) }
    }

    private func stringMetadata(_ metadata: [String: String]) -> [String: HealthKitMetadataValue] {
        metadata.mapValues { value in
            if ["1", "true", "yes"].contains(value.lowercased()) { return .bool(true) }
            return .string(value)
        }
    }

    private func isoDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

nonisolated private extension HealthKitMetadataValue {
    var isTrue: Bool {
        switch self {
        case .bool(let value): return value
        case .signedInteger(let value): return value != 0
        case .unsignedInteger(let value): return value != 0
        case .floatingPoint(let value): return value != 0
        case .string(let value): return ["1", "true", "yes"].contains(value.lowercased())
        default: return false
        }
    }
}

nonisolated private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
