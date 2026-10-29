import Foundation

/// Compatibility stage facts retain their captured whole-session bounds and native
/// identities; existing semantic-adapter ownership checks and shared-core SDK-summary
/// validation remain intact.
nonisolated struct AppleWakeDateSleepStageProjection: Sendable {
    enum ProjectionError: Error { case invalidStage, invalidAggregate }
    let stages: [SleepStageSample]
    let bounds: SleepData.SourceSessionBounds
    var hasRecords: Bool { !stages.isEmpty }

    init(data: HealthData) {
        stages = data.sleep.stages
        bounds = data.sleep.sourceSessionBounds ?? .init(start: data.sleep.sessionStart, end: data.sleep.sessionEnd)
    }

    static func aggregatePresentation(from data: HealthData) -> HealthData {
        var aggregate = data
        aggregate.sleep.stages = []
        return aggregate
    }

    func object(_ stage: SleepStageSample) throws -> [String: Any] {
        try Task.checkCancellation()
        let duration = stage.endDate.timeIntervalSince(stage.startDate)
        guard ["deep", "rem", "core", "awake", "inBed", "unspecified"].contains(stage.stage),
              let parentStart = bounds.start, let parentEnd = bounds.end, parentStart < parentEnd,
              parentStart.timeIntervalSinceReferenceDate.isFinite, parentEnd.timeIntervalSinceReferenceDate.isFinite,
              stage.startDate >= parentStart, stage.endDate <= parentEnd, stage.endDate >= stage.startDate,
              duration.isFinite,
              let start = CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: stage.startDate),
              let end = CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: stage.endDate) else {
            throw ProjectionError.invalidStage
        }
        var result: [String: Any] = ["stage": stage.stage, "startDate": start, "endDate": end, "durationSeconds": duration]
        if !stage.metadata.isEmpty { result["metadata"] = stage.metadata }
        return result
    }

    func addJSON(to root: inout [String: Any]) throws {
        guard hasRecords else { return }
        if let value = root["sleep"], !(value is [String: Any]) { throw ProjectionError.invalidAggregate }
        var sleep = root["sleep"] as? [String: Any] ?? [:]
        guard sleep["sleepStages"] == nil else { throw ProjectionError.invalidAggregate }
        sleep["sleepStages"] = FoundationJSONLazyArray(stages) { try self.object($0) }
        root["sleep"] = sleep
    }

    func writeMarkdown(headerPrefix: String, to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\n\(headerPrefix) Sleep Stage Details\n\n| Start (UTC) | End (UTC) | Stage | Native Record (JSON) |\n|---|---|---|---|\n".utf8))
        for stage in stages {
            let value = try object(stage)
            guard let start = value["startDate"] as? String, let end = value["endDate"] as? String else { throw ProjectionError.invalidStage }
            try sink.write(Data("| \(start) | \(end) | \(stage.stage) | `".utf8))
            let escaped = MarkdownJSONCodeCellSink(output: sink)
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(value, archive: nil, to: escaped,
                outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            _ = try escaped.finish()
            try sink.write(Data("` |\n".utf8))
        }
    }

    func writeFrontmatterBlock(to sink: ExportByteSink) throws {
        guard hasRecords else { return }
        try sink.write(Data("\nsleep_stage_details:\n".utf8))
        for stage in stages {
            try sink.write(Data("  - ".utf8))
            try HealthKitRecordArchiveSerializer.writeDailyJSONObject(object(stage), archive: nil, to: sink,
                outputFormatting: [.sortedKeys, .withoutEscapingSlashes])
            try sink.write(Data("\n".utf8))
        }
    }
}
