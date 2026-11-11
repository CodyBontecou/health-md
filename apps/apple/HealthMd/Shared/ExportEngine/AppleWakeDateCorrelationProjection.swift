import Foundation

/// Paired captured measurements stay native while accepted summaries cross the bounded core handoff.
nonisolated struct AppleWakeDateCorrelationProjection: Sendable {
    enum ProjectionError: Error { case invalidSample, invalidAggregate }
    let samples: [BloodPressureSample]
    var hasRecords: Bool { !samples.isEmpty }

    init(data: HealthData) { samples = data.vitals.bloodPressureSamples }

    static func aggregateRecord(from data: HealthData) -> HealthData {
        var aggregate = data
        aggregate.vitals.bloodPressureSamples = []
        return aggregate
    }

    func object(_ sample: BloodPressureSample) throws -> [String: Any] {
        try Task.checkCancellation()
        guard sample.systolic.isFinite, sample.diastolic.isFinite, sample.endDate >= sample.startDate,
              let start = CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: sample.startDate),
              let end = CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: sample.endDate) else {
            throw ProjectionError.invalidSample
        }
        var value: [String: Any] = ["timestamp": start, "endDate": end, "systolic": sample.systolic,
            "diastolic": sample.diastolic, "unit": "mmHg"]
        if let id = sample.correlationUUID { value["id"] = id.uuidString }
        if let source = sample.sourceRevision { value["sourceRevision"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) }
        if let device = sample.device { value["device"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) }
        if !sample.metadata.isEmpty { value["metadata"] = sample.metadata }
        return value
    }

    func record(_ sample: BloodPressureSample) throws -> [String: Any] {
        ["metric": "blood_pressure", "unit": "mmHg", "sample": try object(sample)]
    }

    func addJSON(to root: inout [String: Any]) throws {
        guard hasRecords else { return }
        if let value = root["vitals"], !(value is [String: Any]) { throw ProjectionError.invalidAggregate }
        var vitals = root["vitals"] as? [String: Any] ?? [:]
        guard vitals["bloodPressureSamples"] == nil else { throw ProjectionError.invalidAggregate }
        vitals["bloodPressureSamples"] = FoundationJSONLazyArray(samples) { try self.object($0) }
        root["vitals"] = vitals
    }

    func writeMarkdown(headerPrefix: String, to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\n\(headerPrefix) Blood Pressure Correlation Details\n\n| Timestamp (UTC) | End (UTC) | Systolic | Diastolic | Unit |\n|---|---|---|---|---|\n".utf8))
        for sample in samples {
            let value = try object(sample)
            guard let start = value["timestamp"] as? String, let end = value["endDate"] as? String else { throw ProjectionError.invalidSample }
            try sink.write(Data("| \(start) | \(end) | \(sample.systolic) | \(sample.diastolic) | mmHg |\n".utf8))
        }
    }

    func writeFrontmatterBlock(to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\nnative_correlation_details:\n".utf8))
        for sample in samples {
            try sink.write(Data("  - ".utf8))
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(record(sample), archive: nil, to: sink,
                outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            try sink.write(Data("\n".utf8))
        }
    }
}
