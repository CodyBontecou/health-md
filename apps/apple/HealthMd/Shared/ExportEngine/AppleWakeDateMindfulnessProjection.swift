import Foundation

/// Full selected State of Mind records use the established native field mapper on the
/// composition worker. SDK-derived summaries retain their separate core authority.
nonisolated struct AppleWakeDateMindfulnessProjection: Sendable {
    enum ProjectionError: Error { case invalidSelection, invalidAggregate }
    let source: HealthData
    let captureContext: AppleSleepCaptureContext
    let timeFormatIdentifier: String
    let hasSelectedOwner: Bool
    var hasRecords: Bool { !source.mindfulness.exportedStateOfMindEntries.isEmpty }

    init(data: HealthData, captureContext: AppleSleepCaptureContext, timeFormatIdentifier: String,
        selectedOutputKeys: Set<String>) {
        source = HealthData(date: data.date, timeContext: data.timeContext, mindfulness: MindfulnessData(stateOfMind: data.mindfulness.exportedStateOfMindEntries))
        self.captureContext = captureContext
        self.timeFormatIdentifier = timeFormatIdentifier
        hasSelectedOwner = !selectedOutputKeys.isDisjoint(with: ["mood_entries", "mood_labels", "mood_associations"])
    }

    /// Validate before any snapshot may convert a selected average to integer percent.
    static func validateCapture(_ data: HealthData) throws {
        let mood = data.mindfulness
        let entries = mood.isStateOfMindEntriesExportEnabled || mood.isAverageValenceExportEnabled
            ? mood.stateOfMind : mood.dailyMoods + mood.momentaryEmotions
        for entry in entries {
            try Task.checkCancellation()
            guard entry.valence.isFinite, (-1...1).contains(entry.valence) else { throw ProjectionError.invalidAggregate }
            if mood.isStateOfMindEntriesExportEnabled {
                guard entry.endDate >= entry.timestamp,
                      CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: entry.timestamp) != nil,
                      CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: entry.endDate) != nil else {
                    throw ProjectionError.invalidAggregate
                }
            }
        }
    }

    func records() throws -> FoundationJSONLazyArray {
        try Task.checkCancellation()
        guard hasSelectedOwner, let timeFormat = TimeFormatPreference(rawValue: timeFormatIdentifier) else {
            throw ProjectionError.invalidSelection
        }
        try Self.validateCapture(source)
        return try source.wakeDateStateOfMindJSONArray(captureContext: captureContext, timeFormat: timeFormat)
    }

    func addJSON(to root: inout [String: Any]) throws {
        guard hasRecords else { return }
        if let value = root["mindfulness"], !(value is [String: Any]) { throw ProjectionError.invalidAggregate }
        var mood = root["mindfulness"] as? [String: Any] ?? [:]
        guard mood["stateOfMindEntries"] == nil else { throw ProjectionError.invalidAggregate }
        mood["stateOfMindEntries"] = try records()
        root["mindfulness"] = mood
    }

    func writeMarkdown(headerPrefix: String, to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\n\(headerPrefix) State of Mind Details\n\n| Native Record (JSON) |\n|---|\n".utf8))
        try records().forEach { value in
            try Task.checkCancellation()
            try sink.write(Data("| `".utf8))
            let escaped = MarkdownJSONCodeCellSink(output: sink)
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(["metric": "state_of_mind", "sample": value],
                archive: nil, to: escaped, outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            _ = try escaped.finish()
            try sink.write(Data("` |\n".utf8))
        }
    }

    func writeFrontmatterBlock(to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\nnative_mindfulness_details:\n".utf8))
        try records().forEach { value in
            try Task.checkCancellation()
            try sink.write(Data("  - ".utf8))
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(["metric": "state_of_mind", "sample": value],
                archive: nil, to: sink, outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            try sink.write(Data("\n".utf8))
        }
    }
}
