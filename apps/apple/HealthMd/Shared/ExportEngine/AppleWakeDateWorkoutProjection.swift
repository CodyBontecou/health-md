import Foundation

/// Full selected workout records use the established native field mapper on the
/// composition worker. SDK-derived summaries retain their separate core authority.
nonisolated struct AppleWakeDateWorkoutProjection: Sendable {
    enum ProjectionError: Error { case invalidSelection, invalidAggregate }
    let source: HealthData
    let captureContext: AppleSleepCaptureContext
    let timeFormatIdentifier: String
    let hasSelectedOwner: Bool
    var hasRecords: Bool { !source.workouts.isEmpty }

    init(data: HealthData, captureContext: AppleSleepCaptureContext, timeFormatIdentifier: String,
        selectedOutputKeys: Set<String>) {
        source = HealthData(date: data.date, timeContext: data.timeContext, workouts: data.workouts)
        self.captureContext = captureContext
        self.timeFormatIdentifier = timeFormatIdentifier
        hasSelectedOwner = selectedOutputKeys.contains { $0 == "workouts" || $0.hasPrefix("workout_") }
    }

    static func selectedOutputKeys(from semanticResult: Data) throws -> Set<String> {
        guard let root = try JSONSerialization.jsonObject(with: semanticResult) as? [String: Any],
              let keys = root["selected_output_keys"] as? [String], Set(keys).count == keys.count else {
            throw ProjectionError.invalidSelection
        }
        return Set(keys)
    }

    func records() throws -> FoundationJSONLazyArray {
        try Task.checkCancellation()
        guard hasSelectedOwner, let timeFormat = TimeFormatPreference(rawValue: timeFormatIdentifier) else {
            throw ProjectionError.invalidSelection
        }
        return try source.wakeDateWorkoutJSONArray(captureContext: captureContext, timeFormat: timeFormat)
    }

    func addJSON(to root: inout [String: Any]) throws {
        guard hasRecords else { return }
        guard root["workouts"] == nil else { throw ProjectionError.invalidAggregate }
        root["workouts"] = try records()
    }

    func writeMarkdown(headerPrefix: String, to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\n\(headerPrefix) Workout Details\n\n| Native Record (JSON) |\n|---|\n".utf8))
        try records().forEach { value in
            try Task.checkCancellation()
            try sink.write(Data("| `".utf8))
            let escaped = MarkdownJSONCodeCellSink(output: sink)
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(["metric": "workout", "sample": value],
                archive: nil, to: escaped, outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            _ = try escaped.finish()
            try sink.write(Data("` |\n".utf8))
        }
    }

    func writeFrontmatterBlock(to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\nnative_workout_details:\n".utf8))
        try records().forEach { value in
            try Task.checkCancellation()
            try sink.write(Data("  - ".utf8))
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(["metric": "workout", "sample": value],
                archive: nil, to: sink, outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            try sink.write(Data("\n".utf8))
        }
    }
}
