import CryptoKit
import Foundation

nonisolated private final class CSVStreamAccumulator {
    private let writer: BufferedExportByteWriter
    private var deferredError: Error?

    init(sink: ExportByteSink) throws {
        self.writer = try BufferedExportByteWriter(sink: sink)
    }

    static func += (lhs: inout CSVStreamAccumulator, rhs: String) {
        guard lhs.deferredError == nil else { return }
        do {
            try lhs.writer.append(rhs)
        } catch {
            lhs.deferredError = error
        }
    }

    func append(_ value: String) {
        guard deferredError == nil else { return }
        do {
            try writer.append(value)
        } catch {
            deferredError = error
        }
    }

    func appendThrowing(_ value: String) throws {
        if let deferredError { throw deferredError }
        try writer.append(value)
    }

    func appendThrowing(_ value: Data) throws {
        if let deferredError { throw deferredError }
        try writer.append(value)
    }

    func finish() throws {
        if let deferredError { throw deferredError }
        try writer.flush()
    }
}

/// Escapes a canonical JSON value directly into an already-quoted CSV field.
/// Canonical JSON chunks are complete UTF-8 fragments, so arbitrary record and
/// attachment payloads never need to become one intermediate String.
nonisolated private final class CSVQuotedJSONFieldSink: ExportByteSink {
    private let csv: CSVStreamAccumulator
    private var hasher = SHA256()
    private var count: UInt64 = 0
    private var pendingUTF8 = Data()
    private var completedDescriptor: ExportArtifactDescriptor?

    init(csv: CSVStreamAccumulator) {
        self.csv = csv
    }

    var byteCount: UInt64 { count }

    func write(_ data: Data) throws {
        guard completedDescriptor == nil else {
            throw ExportArtifactIOError.alreadyFinished
        }
        let output: Data
        if pendingUTF8.isEmpty {
            output = escape(data, isFinal: false)
        } else {
            var input = Data()
            input.reserveCapacity(pendingUTF8.count + data.count)
            input.append(pendingUTF8)
            input.append(data)
            pendingUTF8.removeAll(keepingCapacity: true)
            output = escape(input, isFinal: false)
        }
        try appendOutput(output)
    }

    func finish() throws -> ExportArtifactDescriptor {
        if let completedDescriptor { return completedDescriptor }
        if !pendingUTF8.isEmpty {
            try appendOutput(escape(pendingUTF8, isFinal: true))
            pendingUTF8.removeAll(keepingCapacity: true)
        }
        let descriptor = ExportArtifactDescriptor(
            byteCount: count,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            mediaType: "application/json"
        )
        completedDescriptor = descriptor
        return descriptor
    }

    private func appendOutput(_ output: Data) throws {
        let total = count.addingReportingOverflow(UInt64(output.count))
        guard !total.overflow else { throw ExportArtifactIOError.byteCountOverflow }
        try csv.appendThrowing(output)
        hasher.update(data: output)
        count = total.partialValue
    }

    private func escape(_ input: Data, isFinal: Bool) -> Data {
        var output = Data()
        output.reserveCapacity(input.count + input.count / 32)
        input.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            guard let base = bytes.baseAddress else { return }
            var index = 0
            var runStart = 0

            func appendRun(endingAt end: Int) {
                if end > runStart {
                    output.append(base.advanced(by: runStart), count: end - runStart)
                }
            }

            while index < bytes.count {
                let byte = bytes[index]
                let remaining = bytes.count - index
                if !isFinal,
                   (byte == 0xc2 && remaining < 2 || byte == 0xe2 && remaining < 3) {
                    appendRun(endingAt: index)
                    pendingUTF8.append(base.advanced(by: index), count: remaining)
                    return
                }

                var consumed = 0
                var unicodeEscape: UInt32?
                if byte == 0x22 {
                    appendRun(endingAt: index)
                    output.append(contentsOf: [0x22, 0x22])
                    consumed = 1
                } else if byte <= 0x08 || byte == 0x0b || byte == 0x0c ||
                            (byte >= 0x0e && byte <= 0x1f) || byte == 0x7f {
                    unicodeEscape = UInt32(byte)
                    consumed = 1
                } else if byte == 0xc2, remaining >= 2,
                          bytes[index + 1] >= 0x80, bytes[index + 1] <= 0x9f {
                    unicodeEscape = UInt32(bytes[index + 1])
                    consumed = 2
                } else if byte == 0xe2, remaining >= 3, bytes[index + 1] == 0x80,
                          bytes[index + 2] == 0xa8 || bytes[index + 2] == 0xa9 {
                    unicodeEscape = bytes[index + 2] == 0xa8 ? 0x2028 : 0x2029
                    consumed = 3
                }

                if let unicodeEscape {
                    appendRun(endingAt: index)
                    appendUnicodeEscape(unicodeEscape, to: &output)
                }
                if consumed > 0 {
                    index += consumed
                    runStart = index
                } else {
                    index += 1
                }
            }
            appendRun(endingAt: bytes.count)
        }
        return output
    }

    private func appendUnicodeEscape(_ scalar: UInt32, to output: inout Data) {
        let digits = Array("0123456789ABCDEF".utf8)
        output.append(contentsOf: [
            0x5c, 0x75,
            digits[Int((scalar >> 12) & 0x0f)],
            digits[Int((scalar >> 8) & 0x0f)],
            digits[Int((scalar >> 4) & 0x0f)],
            digits[Int(scalar & 0x0f)]
        ])
    }
}

// MARK: - CSV Export

extension HealthData {
    /// Compatibility convenience for previews and older callers. Production
    /// writers use `toCSVThrowing` and fail the date instead of silently
    /// omitting an unencodable raw record.
    func toCSV(customization: FormatCustomization? = nil) -> String {
        do {
            return try toCSVThrowing(customization: customization)
        } catch {
            return "Date,Category,Metric,Value,Unit,Timestamp\n" +
                ",Diagnostics,Serialization Error,canonical_export_encoding_failed,incomplete,\n"
        }
    }

    func toCSVThrowing(customization: FormatCustomization? = nil) throws -> String {
        let config = customization ?? FormatCustomization()
        return try toCSVThrowing(
            snapshot: exportSnapshot(customization: config),
            config: config
        )
    }

    func toCSVThrowing(
        snapshot: ExportDataSnapshot,
        config: FormatCustomization
    ) throws -> String {
        let sink = MemoryExportByteSink(mediaType: "text/csv")
        try writeCSVThrowing(to: sink, snapshot: snapshot, config: config)
        _ = try sink.finish()
        guard let value = String(data: sink.data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return value
    }

    func writeCSVThrowing(
        to sink: ExportByteSink,
        snapshot: ExportDataSnapshot,
        config: FormatCustomization
    ) throws {
        let canonicalRateConverter = UnitConverter(preference: .metric)
        var structuredUnitsByKey: [String: String] = [:]
        for entry in HealthMetricDataDictionary.entries(using: config) {
            structuredUnitsByKey[entry.key] = entry.unit
            structuredUnitsByKey[entry.canonicalKey] = entry.unit
        }

        func csvSafe(_ value: String) -> String {
            CSVFieldEscaper.escape(value)
        }

        func csvBool(_ value: Bool) -> String {
            value ? "true" : "false"
        }

        func csvNumber(_ value: Double) -> String {
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", value)
            }
            return String(describing: value)
        }

        func appendCSVRow(category: String, metric: String, value: String, unit: String = "", timestamp: String = "", to csv: inout CSVStreamAccumulator) {
            let fields = [snapshot.dateString, category, metric, value, unit, timestamp]
            csv += fields.map(csvSafe).joined(separator: ",") + "\n"
        }

        func appendCanonicalJSONRow(
            category: String,
            metric: String,
            unit: String,
            timestamp: String,
            to csv: inout CSVStreamAccumulator,
            render: (ExportByteSink) throws -> Void
        ) throws {
            let prefix = [snapshot.dateString, category, metric]
                .map(csvSafe)
                .joined(separator: ",")
            try csv.appendThrowing(prefix + ",\"")
            let jsonSink = CSVQuotedJSONFieldSink(csv: csv)
            try render(jsonSink)
            _ = try jsonSink.finish()
            try csv.appendThrowing("\",\(csvSafe(unit)),\(csvSafe(timestamp))\n")
        }

        var csv = try CSVStreamAccumulator(sink: sink)
        csv += "Date,Category,Metric,Value,Unit,Timestamp\n"
        csv += "\(snapshot.dateString),Metadata,schema,\(HealthMdExportSchema.identifier),,\n"
        csv += "\(snapshot.dateString),Metadata,schema_version,\(HealthMdExportSchema.version),,\n"
        csv += "\(snapshot.dateString),Metadata,unit_system,metric,,\n"
        csv += "\(snapshot.dateString),Metadata,time_context.calendar_timezone,\(csvSafe(snapshot.timeContext.calendarTimeZoneIdentifier)),,\n"
        csv += "\(snapshot.dateString),Metadata,time_context.timestamp_timezone,\(ExportTimeContext.timestampTimeZoneIdentifier),,\n"

        appendCSVRow(
            category: "Raw HealthKit",
            metric: "Raw Capture Status",
            value: HealthKitRecordArchiveSerializer.captureStatusString(snapshot.healthKitRecordCaptureStatus),
            unit: "status",
            to: &csv
        )

        if let archive = snapshot.healthKitRecordArchive {
            let manifestTimestamp = CanonicalRFC3339UTC.string(from: archive.dailyOwnership.intervalStart)
            try appendCanonicalJSONRow(
                category: "Raw HealthKit",
                metric: "Archive Manifest",
                unit: "json",
                timestamp: manifestTimestamp,
                to: &csv
            ) { try HealthKitRecordArchiveSerializer.writeManifest(archive, to: $0) }

            // HealthKitRecordArchive normalizes records in every initializer.
            // Stream each canonical JSON field through CSV quote escaping rather
            // than retaining a second full JSON String per dense record.
            for record in archive.records {
                try appendCanonicalJSONRow(
                    category: "Raw HealthKit",
                    metric: "Raw HealthKit Record",
                    unit: "json",
                    timestamp: CanonicalRFC3339UTC.string(from: record.startDate),
                    to: &csv
                ) { try HealthKitRecordArchiveSerializer.writeRecord(record, to: $0) }
            }

            for record in HealthKitRecordArchiveSerializer.sortedExternalRecords(archive.externalRecords) {
                try appendCanonicalJSONRow(
                    category: "Raw HealthKit",
                    metric: "Raw HealthKit External Record",
                    unit: "json",
                    timestamp: manifestTimestamp,
                    to: &csv
                ) { try HealthKitRecordArchiveSerializer.writeExternalRecord(record, to: $0) }
            }

            for result in HealthKitRecordArchiveSerializer.sortedQueryResults(archive.queryResults)
                where result.status == .failure || result.status == .cancelled {
                try appendCanonicalJSONRow(
                    category: "Raw HealthKit",
                    metric: "Query Failure",
                    unit: "json",
                    timestamp: CanonicalRFC3339UTC.string(from: result.interval.startDate),
                    to: &csv
                ) { try HealthKitRecordArchiveSerializer.writeQueryResult(result, to: $0) }
            }

            for warning in HealthKitRecordArchiveSerializer.sortedWarnings(archive.integrityWarnings) {
                try appendCanonicalJSONRow(
                    category: "Raw HealthKit",
                    metric: "Integrity Warning",
                    unit: "json",
                    timestamp: manifestTimestamp,
                    to: &csv
                ) { try HealthKitRecordArchiveSerializer.writeIntegrityWarning(warning, to: $0) }
            }
        }

        for failure in ExportDiagnosticSerializer.sorted(snapshot.partialFailures) {
            let failureJSON = try ExportDiagnosticSerializer.string(for: failure)
            appendCSVRow(
                category: "Diagnostics",
                metric: "Partial Failure",
                value: failureJSON,
                unit: "json",
                timestamp: CanonicalRFC3339UTC.string(from: failure.date),
                to: &csv
            )
        }

        // Sleep
        if snapshot.sleep.hasData {
            if snapshot.sleep.totalDurationSeconds > 0 {
                csv += "\(snapshot.dateString),Sleep,Total Duration,\(snapshot.sleep.totalDurationSeconds),seconds\n"
            }
            if let bedtime = snapshot.sleep.bedtime {
                csv += "\(snapshot.dateString),Sleep,Bedtime,\(snapshot.formatCalendarTime(bedtime)),time\n"
            }
            if let wake = snapshot.sleep.wakeTime {
                csv += "\(snapshot.dateString),Sleep,Wake Time,\(snapshot.formatCalendarTime(wake)),time\n"
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
                let isoFormatter = ExportDateFormatting.utcISO8601Formatter()
                for stage in snapshot.sleep.stages {
                    let duration = stage.endDate.timeIntervalSince(stage.startDate)
                    csv += "\(snapshot.dateString),Sleep,Sleep Stage,\(stage.stage) (\(Int(duration))s),seconds,\(isoFormatter.string(from: stage.startDate))\n"
                }
            }
        }

        // Activity
        if snapshot.activity.hasData || snapshot.hasCategoryData(.activity) {
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
            if let standTimeMinutes = snapshot.activity.standTimeMinutes {
                csv += "\(snapshot.dateString),Activity,Stand Time,\(standTimeMinutes),minutes\n"
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
                let sourceTimestamp = snapshot.activity.vo2MaxSourceStartDate.map(CanonicalRFC3339UTC.string) ?? ""
                appendCSVRow(category: "Activity", metric: "Cardio Fitness (VO2 Max)", value: String(format: "%.1f", vo2), unit: "mL/kg/min", timestamp: sourceTimestamp, to: &csv)
                if let sourceUUID = snapshot.activity.vo2MaxSourceUUID {
                    appendCSVRow(category: "Activity", metric: "VO2 Max Source UUID", value: sourceUUID.uuidString, unit: "uuid", timestamp: sourceTimestamp, to: &csv)
                }
                if let startDate = snapshot.activity.vo2MaxSourceStartDate {
                    appendCSVRow(category: "Activity", metric: "VO2 Max Source Start", value: CanonicalRFC3339UTC.string(from: startDate), unit: "datetime", timestamp: sourceTimestamp, to: &csv)
                }
                if let endDate = snapshot.activity.vo2MaxSourceEndDate {
                    appendCSVRow(category: "Activity", metric: "VO2 Max Source End", value: CanonicalRFC3339UTC.string(from: endDate), unit: "datetime", timestamp: sourceTimestamp, to: &csv)
                }
                if let carriedForward = snapshot.activity.vo2MaxCarriedForward {
                    appendCSVRow(category: "Activity", metric: "VO2 Max Carried Forward", value: csvBool(carriedForward), unit: "boolean", timestamp: sourceTimestamp, to: &csv)
                }
                if let ageSeconds = snapshot.activity.vo2MaxAgeSeconds {
                    appendCSVRow(category: "Activity", metric: "VO2 Max Age", value: csvNumber(ageSeconds), unit: "seconds", timestamp: sourceTimestamp, to: &csv)
                }
            }
            if let wheelchair = snapshot.activity.wheelchairDistanceMeters {
                csv += "\(snapshot.dateString),Activity,Wheelchair Distance,\(wheelchair),meters\n"
            }
            if let snow = snapshot.activity.downhillSnowSportsDistanceMeters {
                csv += "\(snapshot.dateString),Activity,Downhill Snow Sports Distance,\(snow),meters\n"
            }
            if let v = snapshot.frontmatterMetrics["move_minutes"] {
                csv += "\(snapshot.dateString),Activity,Move Time,\(v),min\n"
            }
            if let v = snapshot.frontmatterMetrics["physical_effort"] {
                csv += "\(snapshot.dateString),Activity,Physical Effort,\(v),kcal/hr/kg\n"
            }
        }

        // Heart
        if snapshot.heart.hasData || snapshot.hasCategoryData(.heart) {
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
                let isoFormatter = ExportDateFormatting.utcISO8601Formatter()
                for sample in snapshot.heart.heartRateSamples {
                    csv += "\(snapshot.dateString),Heart,Heart Rate Sample,\(sample.value),bpm,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
            if !snapshot.heart.hrvSamples.isEmpty {
                let isoFormatter = ExportDateFormatting.utcISO8601Formatter()
                for sample in snapshot.heart.hrvSamples {
                    csv += "\(snapshot.dateString),Heart,HRV Sample,\(sample.value),ms,\(isoFormatter.string(from: sample.timestamp))\n"
                }
            }
            if let v = snapshot.frontmatterMetrics["heart_rate_recovery"] {
                csv += "\(snapshot.dateString),Heart,Heart Rate Recovery,\(v),bpm\n"
            }
            if let v = snapshot.frontmatterMetrics["afib_burden_percent"] {
                csv += "\(snapshot.dateString),Heart,AFib Burden,\(v),%\n"
            }
        }

        // Vitals (daily aggregates)
        if snapshot.vitals.hasData || snapshot.hasCategoryData(.vitals) || snapshot.hasCategoryData(.respiratory) {
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
                csv += "\(snapshot.dateString),Vitals,Body Temperature Avg,\(String(format: "%.1f", tempAvg)),°C\n"
            }
            if let tempMin = snapshot.vitals.bodyTemperatureMinCelsius {
                csv += "\(snapshot.dateString),Vitals,Body Temperature Min,\(String(format: "%.1f", tempMin)),°C\n"
            }
            if let tempMax = snapshot.vitals.bodyTemperatureMaxCelsius {
                csv += "\(snapshot.dateString),Vitals,Body Temperature Max,\(String(format: "%.1f", tempMax)),°C\n"
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
            let isoFormatter = ExportDateFormatting.utcISO8601Formatter()
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
            if !snapshot.vitals.bloodPressureSamples.isEmpty {
                for sample in snapshot.vitals.bloodPressureSamples {
                    appendCSVRow(
                        category: "Vitals",
                        metric: "Blood Pressure Sample",
                        value: "\(csvNumber(sample.systolic))/\(csvNumber(sample.diastolic))",
                        unit: "mmHg",
                        timestamp: isoFormatter.string(from: sample.startDate),
                        to: &csv
                    )
                }
            }
            if let v = snapshot.frontmatterMetrics["basal_body_temperature"] {
                csv += "\(snapshot.dateString),Vitals,Basal Body Temperature,\(v),°C\n"
            }
            if let v = snapshot.frontmatterMetrics["wrist_temperature"] {
                csv += "\(snapshot.dateString),Vitals,Wrist Temperature,\(v),°C\n"
            }
            if let v = snapshot.frontmatterMetrics["electrodermal_activity"] {
                csv += "\(snapshot.dateString),Vitals,Electrodermal Activity,\(v),µS\n"
            }
            if let v = snapshot.frontmatterMetrics["forced_vital_capacity_l"] {
                csv += "\(snapshot.dateString),Vitals,Forced Vital Capacity,\(v),L\n"
            }
            if let v = snapshot.frontmatterMetrics["fev1_l"] {
                csv += "\(snapshot.dateString),Vitals,FEV1,\(v),L\n"
            }
            if let v = snapshot.frontmatterMetrics["peak_expiratory_flow"] {
                csv += "\(snapshot.dateString),Vitals,Peak Expiratory Flow,\(v),L/min\n"
            }
            if let v = snapshot.frontmatterMetrics["inhaler_usage"] {
                csv += "\(snapshot.dateString),Vitals,Inhaler Usage,\(v),uses\n"
            }
        }

        // Body
        if snapshot.body.hasData {
            if let weight = snapshot.body.weightKg {
                csv += "\(snapshot.dateString),Body,Weight,\(String(format: "%.1f", weight)),kg\n"
            }
            if let height = snapshot.body.heightMeters {
                csv += "\(snapshot.dateString),Body,Height,\(String(format: "%.2f", height)),m\n"
            }
            if let bmi = snapshot.body.bmi {
                csv += "\(snapshot.dateString),Body,BMI,\(bmi),\n"
            }
            if let bodyFat = snapshot.body.bodyFatRatio {
                csv += "\(snapshot.dateString),Body,Body Fat Percentage,\(bodyFat * 100),percent\n"
            }
            if let lean = snapshot.body.leanBodyMassKg {
                csv += "\(snapshot.dateString),Body,Lean Body Mass,\(String(format: "%.1f", lean)),kg\n"
            }
            if let waist = snapshot.body.waistCircumferenceMeters {
                csv += "\(snapshot.dateString),Body,Waist Circumference,\(String(format: "%.1f", waist * 100)),cm\n"
            }
        }

        // Nutrition
        if snapshot.nutrition.hasData || snapshot.hasCategoryData(.nutrition) {
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
            if let v = snapshot.frontmatterMetrics["monounsaturated_fat_g"] {
                csv += "\(snapshot.dateString),Nutrition,Monounsaturated Fat,\(v),g\n"
            }
            if let v = snapshot.frontmatterMetrics["polyunsaturated_fat_g"] {
                csv += "\(snapshot.dateString),Nutrition,Polyunsaturated Fat,\(v),g\n"
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

            if let avgValence = snapshot.mindfulness.averageValence,
               let valencePercent = snapshot.mindfulness.averageValencePercent {
                csv += "\(snapshot.dateString),Mindfulness,Average Mood Valence,\(String(format: "%.2f", avgValence)),scale(-1 to 1)\n"
                csv += "\(snapshot.dateString),Mindfulness,Average Mood Percent,\(valencePercent),percent\n"
            }

            if !snapshot.mindfulness.dailyMoods.isEmpty {
                csv += "\(snapshot.dateString),Mindfulness,Daily Mood Count,\(snapshot.mindfulness.dailyMoods.count),count\n"
                if let dailyAverage = snapshot.mindfulness.averageDailyMoodValence {
                    let dailyPercent = Int(((dailyAverage + 1.0) / 2.0) * 100)
                    csv += "\(snapshot.dateString),Mindfulness,Daily Mood Percent,\(dailyPercent),percent\n"
                }
            }

            if !snapshot.mindfulness.momentaryEmotions.isEmpty {
                csv += "\(snapshot.dateString),Mindfulness,Momentary Emotion Count,\(snapshot.mindfulness.momentaryEmotions.count),count\n"
            }

            if !snapshot.mindfulness.stateOfMindEntries.isEmpty {
                csv += "\(snapshot.dateString),Mindfulness,State of Mind Entries,\(snapshot.mindfulness.stateOfMindEntries.count),count\n"
                for entry in snapshot.mindfulness.stateOfMindEntries {
                    let timeStr = snapshot.formatCalendarTime(entry.timestamp)
                    let labelsStr = entry.labels.joined(separator: ", ")
                    let associationsStr = entry.associations.joined(separator: ", ")

                    appendCSVRow(
                        category: "State of Mind",
                        metric: "\(entry.kind.rawValue) at \(timeStr)",
                        value: String(format: "%.2f", entry.valence),
                        unit: "valence",
                        to: &csv
                    )
                    if !labelsStr.isEmpty {
                        appendCSVRow(
                            category: "State of Mind",
                            metric: "\(entry.kind.rawValue) Labels at \(timeStr)",
                            value: labelsStr,
                            unit: "labels",
                            to: &csv
                        )
                    }
                    if !associationsStr.isEmpty {
                        appendCSVRow(
                            category: "State of Mind",
                            metric: "\(entry.kind.rawValue) Associations at \(timeStr)",
                            value: associationsStr,
                            unit: "associations",
                            to: &csv
                        )
                    }
                }
            }
        }

        // Mobility
        if snapshot.mobility.hasData || snapshot.hasCategoryData(.mobility) {
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
            if let v = snapshot.frontmatterMetrics["walking_steadiness_percent"] {
                csv += "\(snapshot.dateString),Mobility,Walking Steadiness,\(v),%\n"
            }
            if let v = snapshot.frontmatterMetrics["running_speed"] {
                csv += "\(snapshot.dateString),Mobility,Running Speed,\(v),m/s\n"
            }
            if let v = snapshot.frontmatterMetrics["running_stride_length_m"] {
                csv += "\(snapshot.dateString),Mobility,Running Stride Length,\(v),m\n"
            }
            if let v = snapshot.frontmatterMetrics["running_ground_contact_ms"] {
                csv += "\(snapshot.dateString),Mobility,Running Ground Contact Time,\(v),ms\n"
            }
            if let v = snapshot.frontmatterMetrics["running_vertical_oscillation_cm"] {
                csv += "\(snapshot.dateString),Mobility,Running Vertical Oscillation,\(v),cm\n"
            }
            if let v = snapshot.frontmatterMetrics["running_power_w"] {
                csv += "\(snapshot.dateString),Mobility,Running Power,\(v),W\n"
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
                let startTimeString = snapshot.formatCalendarTime(workout.startTime)
                let startTimestamp = ExportDateFormatting.utcTimestamp(workout.startTime)
                csv += "\(snapshot.dateString),Workouts,Workout Activity Type,\(workout.workoutTypeName),,\(startTimestamp)\n"
                csv += "\(snapshot.dateString),Workouts,Workout Sport,\(workout.workoutSportName),,\(startTimestamp)\n"
                if let healthKitActivityType = workout.healthKitActivityType {
                    csv += "\(snapshot.dateString),Workouts,HealthKit Activity Type,\(healthKitActivityType),,\(startTimestamp)\n"
                }
                if let rawValue = workout.healthKitActivityTypeRawValue {
                    csv += "\(snapshot.dateString),Workouts,HealthKit Activity Type Raw Value,\(rawValue),,\(startTimestamp)\n"
                }
                csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Start Time,\(startTimeString),time\n"
                if let isIndoor = workout.isIndoor {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Location,\(isIndoor ? "Indoor" : "Outdoor"),\n"
                }
                csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Duration,\(workout.duration),seconds\n"
                if let distance = workout.distance, distance > 0 {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Distance,\(String(format: "%.0f", distance)),meters\n"
                    if let rate = workout.paceOrSpeed(using: canonicalRateConverter) {
                        csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) \(rate.label),\(rate.value),\n"
                    }
                }
                if let calories = workout.calories, calories > 0 {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Calories,\(calories),kcal\n"
                }
                if let avgHR = workout.avgHeartRate {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Heart Rate,\(Int(avgHR.rounded())),bpm\n"
                }
                if let maxHR = workout.maxHeartRate {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Max Heart Rate,\(Int(maxHR.rounded())),bpm\n"
                }
                if let minHR = workout.minHeartRate {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Min Heart Rate,\(Int(minHR.rounded())),bpm\n"
                }
                if let cadence = workout.avgRunningCadence {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Cadence,\(Int(cadence.rounded())),spm\n"
                }
                if let stride = workout.avgStrideLength {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Stride Length,\(String(format: "%.2f", stride)),m\n"
                }
                if let gct = workout.avgGroundContactTime {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Ground Contact,\(Int(gct.rounded())),ms\n"
                }
                if let vertOsc = workout.avgVerticalOscillation {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Vertical Oscillation,\(String(format: "%.1f", vertOsc)),cm\n"
                }
                if let cyclingCadence = workout.avgCyclingCadence {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Cadence,\(Int(cyclingCadence.rounded())),rpm\n"
                }
                if let avgPow = workout.avgPower {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Avg Power,\(Int(avgPow.rounded())),W\n"
                }
                if let maxPow = workout.maxPower {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Max Power,\(Int(maxPow.rounded())),W\n"
                }
                if let elevation = workout.elevationGainMeters {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Elevation Gain,\(Int(elevation.rounded())),m\n"
                }
                if let elevationLoss = workout.elevationLossMeters {
                    csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Elevation Loss,\(Int(elevationLoss.rounded())),m\n"
                }
                if !workout.laps.isEmpty {
                    for (i, lap) in workout.laps.enumerated() {
                        let n = i + 1
                        if let d = lap.distanceMeters {
                            csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Lap \(n) Distance,\(String(format: "%.0f", d)),meters\n"
                        }
                        csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Lap \(n) Duration,\(Int(lap.duration.rounded())),seconds\n"
                        if let d = lap.distanceMeters, d > 0,
                           let pace = canonicalRateConverter.formatPace(meters: d, duration: lap.duration) {
                            csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Lap \(n) Pace,\(pace),\n"
                        }
                    }
                }
                if !workout.splits.isEmpty {
                    for split in workout.splits {
                        if let pace = canonicalRateConverter.formatPace(meters: split.distanceMeters, duration: split.duration) {
                            csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Split \(split.index) Pace,\(pace),\n"
                        }
                        if let hr = split.avgHeartRate {
                            csv += "\(snapshot.dateString),Workouts,\(workout.workoutTypeName) Split \(split.index) Avg Heart Rate,\(Int(hr.rounded())),bpm\n"
                        }
                    }
                }
            }
        }

        // Reproductive Health
        if snapshot.reproductiveHealth.hasData {
            for m in snapshot.metricsForCategory(.reproductiveHealth) {
                csv += "\(snapshot.dateString),Reproductive Health,\(m.label),\(m.value),\(structuredUnitsByKey[m.key] ?? "")\n"
            }
        }

        // Cycling Performance
        if snapshot.cyclingPerformance.hasData {
            for m in snapshot.metricsForCategory(.cycling) {
                csv += "\(snapshot.dateString),Cycling,\(m.label),\(m.value),\(structuredUnitsByKey[m.key] ?? "")\n"
            }
        }

        // Vitamins
        if snapshot.vitamins.hasData {
            for m in snapshot.metricsForCategory(.vitamins) {
                csv += "\(snapshot.dateString),Vitamins,\(m.label),\(m.value),\(structuredUnitsByKey[m.key] ?? "")\n"
            }
        }

        // Minerals
        if snapshot.minerals.hasData {
            for m in snapshot.metricsForCategory(.minerals) {
                csv += "\(snapshot.dateString),Minerals,\(m.label),\(m.value),\(structuredUnitsByKey[m.key] ?? "")\n"
            }
        }

        // Symptoms
        if snapshot.symptoms.hasData {
            for (key, count) in snapshot.symptoms.counts.sorted(by: { $0.key < $1.key }) {
                let label = key.replacingOccurrences(of: "symptom_", with: "").replacingOccurrences(of: "_", with: " ").capitalized
                csv += "\(snapshot.dateString),Symptoms,\(label),\(count),count\n"
            }
        }

        // Medications
        if snapshot.medications.hasData {
            let medications = snapshot.medications
            csv += "\(snapshot.dateString),Medications,Authorized Medications,\(medications.medications.count),count\n"
            csv += "\(snapshot.dateString),Medications,Active Medications,\(medications.activeMedications.count),count\n"
            csv += "\(snapshot.dateString),Medications,Archived Medications,\(medications.archivedMedications.count),count\n"
            csv += "\(snapshot.dateString),Medications,Dose Events,\(medications.doseEvents.count),count\n"
            csv += "\(snapshot.dateString),Medications,Taken Doses,\(medications.takenDoseEvents.count),count\n"
            csv += "\(snapshot.dateString),Medications,Skipped Doses,\(medications.skippedDoseEvents.count),count\n"

            let sortedMedications = medications.medications.sorted { lhs, rhs in
                if lhs.exportName == rhs.exportName {
                    return lhs.conceptIdentifier < rhs.conceptIdentifier
                }
                return lhs.exportName < rhs.exportName
            }
            for medication in sortedMedications {
                let name = medication.exportName
                let status = medication.isArchived ? "archived" : "active"
                let schedule = medication.hasSchedule ? "scheduled" : "as_needed"
                appendCSVRow(category: "Medications", metric: "Medication", value: name, unit: "\(status);\(schedule)", to: &csv)
                appendCSVRow(category: "Medications", metric: "Medication Concept Identifier", value: "\(name): \(medication.conceptIdentifier)", to: &csv)
                appendCSVRow(category: "Medications", metric: "Medication Display Name", value: "\(name): \(medication.displayName)", to: &csv)
                appendCSVRow(category: "Medications", metric: "Medication Export Name", value: name, to: &csv)
                appendCSVRow(category: "Medications", metric: "Medication General Form", value: "\(name): \(medication.generalForm)", to: &csv)
                appendCSVRow(category: "Medications", metric: "Medication Archived", value: "\(name): \(csvBool(medication.isArchived))", unit: "boolean", to: &csv)
                appendCSVRow(category: "Medications", metric: "Medication Has Schedule", value: "\(name): \(csvBool(medication.hasSchedule))", unit: "boolean", to: &csv)

                if let nickname = medication.nickname, !nickname.isEmpty {
                    appendCSVRow(category: "Medications", metric: "Medication Nickname", value: "\(name): \(nickname)", to: &csv)
                }
                for coding in medication.relatedCodings.sorted(by: { lhs, rhs in
                    if lhs.system != rhs.system { return lhs.system < rhs.system }
                    if lhs.code != rhs.code { return lhs.code < rhs.code }
                    return (lhs.version ?? "") < (rhs.version ?? "")
                }) {
                    var value = "\(name): system=\(coding.system); code=\(coding.code)"
                    if let version = coding.version, !version.isEmpty {
                        value += "; version=\(version)"
                    }
                    appendCSVRow(category: "Medications", metric: "Medication Related Coding", value: value, unit: "coding", to: &csv)
                }
                for code in medication.rxNormCodes.sorted() {
                    appendCSVRow(category: "Medications", metric: "Medication RxNorm Code", value: "\(name): \(code)", unit: "rxnorm", to: &csv)
                }
            }

            let isoFormatter = ExportDateFormatting.utcISO8601Formatter()
            let sortedDoseEvents = medications.doseEvents.sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.startDate < rhs.startDate
            }
            for event in sortedDoseEvents {
                let timestamp = isoFormatter.string(from: event.startDate)
                let name = event.displayMedicationName
                var value = "\(name) \(event.logStatus.displayName)"
                if let doseQuantity = event.doseQuantity {
                    value += " \(csvNumber(doseQuantity)) \(event.unit)"
                }
                appendCSVRow(category: "Medications", metric: "Dose Event", value: value, unit: event.scheduleType.rawValue, timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event ID", value: event.id.uuidString, unit: "uuid", timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event Medication Concept Identifier", value: event.medicationConceptIdentifier, timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event Medication Name", value: name, timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event Start", value: timestamp, unit: "datetime", timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event End", value: isoFormatter.string(from: event.endDate), unit: "datetime", timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event Status", value: event.logStatus.rawValue, timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event Status Display", value: event.logStatus.displayName, timestamp: timestamp, to: &csv)
                appendCSVRow(category: "Medications", metric: "Dose Event Schedule Type", value: event.scheduleType.rawValue, timestamp: timestamp, to: &csv)
                if !event.unit.isEmpty {
                    appendCSVRow(category: "Medications", metric: "Dose Event Unit", value: event.unit, timestamp: timestamp, to: &csv)
                }
                if let scheduledDate = event.scheduledDate {
                    appendCSVRow(category: "Medications", metric: "Dose Event Scheduled Date", value: isoFormatter.string(from: scheduledDate), unit: "datetime", timestamp: timestamp, to: &csv)
                }
                if let doseQuantity = event.doseQuantity {
                    appendCSVRow(category: "Medications", metric: "Dose Event Dose Quantity", value: csvNumber(doseQuantity), unit: event.unit, timestamp: timestamp, to: &csv)
                }
                if let scheduledDoseQuantity = event.scheduledDoseQuantity {
                    appendCSVRow(category: "Medications", metric: "Dose Event Scheduled Dose Quantity", value: csvNumber(scheduledDoseQuantity), unit: event.unit, timestamp: timestamp, to: &csv)
                }
                for (key, value) in event.metadata.sorted(by: { $0.key < $1.key }) {
                    appendCSVRow(category: "Medications", metric: "Dose Event Metadata \(key)", value: value, unit: "metadata", timestamp: timestamp, to: &csv)
                }
            }
        }

        // Other
        if snapshot.otherHealth.hasData {
            for m in snapshot.metricsForCategory(.other) {
                csv += "\(snapshot.dateString),Other,\(m.label),\(m.value),\(structuredUnitsByKey[m.key] ?? "")\n"
            }
        }

        try csv.finish()
    }
}
