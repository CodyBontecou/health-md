import Foundation

/// Captured, selected native quantities compose after bounded aggregate attestation.
/// The source arrays stay immutable and are serialized one sample at a time.
nonisolated struct AppleWakeDateQuantityProjection: Sendable {
    struct Series: Sendable {
        let category: String
        let field: String
        let metric: String
        let unit: String
        let label: String
        let samples: [TimeSample]
    }

    enum ProjectionError: Error { case invalidSample, invalidAggregate }
    let series: [Series]
    var hasRecords: Bool { !series.isEmpty }

    init(data: HealthData) {
        series = [
            Series(category: "heart", field: "heartRateSamples", metric: "heart_rate", unit: "bpm", label: "Heart Rate", samples: data.heart.heartRateSamples),
            Series(category: "heart", field: "hrvSamples", metric: "hrv_sdnn", unit: "ms", label: "HRV SDNN", samples: data.heart.hrvSamples),
            Series(category: "vitals", field: "bloodOxygenSamples", metric: "blood_oxygen", unit: "ratio_0_1", label: "Blood Oxygen", samples: data.vitals.bloodOxygenSamples),
            Series(category: "vitals", field: "bloodGlucoseSamples", metric: "blood_glucose", unit: "mg/dL", label: "Blood Glucose", samples: data.vitals.bloodGlucoseSamples),
            Series(category: "vitals", field: "respiratoryRateSamples", metric: "respiratory_rate", unit: "breaths/min", label: "Respiratory Rate", samples: data.vitals.respiratoryRateSamples),
        ].filter { !$0.samples.isEmpty }
    }

    static func aggregateRecord(from data: HealthData) -> HealthData {
        var aggregate = data
        aggregate.heart.heartRateSamples = []
        aggregate.heart.hrvSamples = []
        aggregate.vitals.bloodOxygenSamples = []
        aggregate.vitals.bloodGlucoseSamples = []
        aggregate.vitals.respiratoryRateSamples = []
        return aggregate
    }

    static func sampleObject(_ sample: TimeSample, unit: String) throws -> [String: Any] {
        try Task.checkCancellation()
        guard sample.value.isFinite,
              unit != "ratio_0_1" || (0...1).contains(sample.value),
              let timestamp = CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: sample.timestamp) else {
            throw ProjectionError.invalidSample
        }
        var object: [String: Any] = ["timestamp": timestamp, "value": sample.value]
        if !sample.metadata.isEmpty { object["metadata"] = sample.metadata }
        return object
    }

    static func recordObject(_ sample: TimeSample, series: Series) throws -> [String: Any] {
        ["metric": series.metric, "unit": series.unit, "sample": try sampleObject(sample, unit: series.unit)]
    }

    func addJSON(to root: inout [String: Any]) throws {
        for item in series {
            if let value = root[item.category], !(value is [String: Any]) { throw ProjectionError.invalidAggregate }
            var category = root[item.category] as? [String: Any] ?? [:]
            guard category[item.field] == nil else { throw ProjectionError.invalidAggregate }
            category[item.field] = FoundationJSONLazyArray(item.samples) { try Self.sampleObject($0, unit: item.unit) }
            root[item.category] = category
        }
    }

    func writeMarkdown(headerPrefix: String, to sink: ExportByteSink) throws {
        for item in series {
            try sink.write(Data("\n\(headerPrefix) \(item.label) Sample Details\n\n| Timestamp (UTC) | Value | Unit |\n|---|---|---|\n".utf8))
            for sample in item.samples {
                let object = try Self.sampleObject(sample, unit: item.unit)
                guard let timestamp = object["timestamp"] as? String else { throw ProjectionError.invalidSample }
                try sink.write(Data("| \(timestamp) | \(sample.value) | \(item.unit) |\n".utf8))
            }
        }
    }

    func writeFrontmatterBlock(to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\nnative_quantity_details:\n".utf8))
        for item in series {
            for sample in item.samples {
                try sink.write(Data("  - ".utf8))
                try HealthKitRecordArchiveSerializer.writeDailyJSONObject(Self.recordObject(sample, series: item),
                    archive: nil, to: sink, outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
                try sink.write(Data("\n".utf8))
            }
        }
    }
}
