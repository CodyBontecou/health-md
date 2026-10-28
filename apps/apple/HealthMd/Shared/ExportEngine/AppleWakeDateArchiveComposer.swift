import Foundation

/// Combines bounded core aggregates with the independently versioned native source archive.
/// Only immutable inputs enter the worker; the returned plan hashes final, file-backed bytes.
nonisolated enum AppleWakeDateArchiveComposer {
    struct Source: Sendable {
        let ownerDate: String
        let format: ExportFormat
        let archive: HealthKitRecordArchive?
        let captureStatus: String
        let markdownDiagnostics: String
    }

    @MainActor
    static func compose(plan: NativeExportArtifactPlan, pin: AppleExportEnginePin,
        prepared: [PreparedHealthDataExport], settings: AdvancedExportSettings,
        healthSubfolder: String, dailyOutputOwnerDates: Set<String>) async throws -> NativeExportArtifactPlan {
        var sources: [String: Source] = [:]
        let root = URL(fileURLWithPath: "/__HealthMdPlanningRoot__", isDirectory: true)
        for day in prepared {
            let owner = HealthKitDailyOwnershipMetadata.ownerDate(for: day.filteredData.date,
                calendarTimeZoneIdentifier: pin.calendarTimeZoneIdentifier)
            guard dailyOutputOwnerDates.contains(owner) else { continue }
            if let archive = day.snapshot.healthKitRecordArchive {
                guard archive.dailyOwnership.ownerDate == owner,
                      archive.dailyOwnership.calendarTimeZoneIdentifier == pin.calendarTimeZoneIdentifier else {
                    throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                }
            }
            let diagnostics = day.filteredData.losslessHealthRecordsMarkdown(snapshot: day.snapshot,
                headerPrefix: String(repeating: "#", count: settings.formatCustomization.markdownTemplate.sectionHeaderLevel))
            for target in ExportPathPlanner.aggregateOutputTargets(vaultURL: root,
                healthSubfolder: healthSubfolder, settings: settings, date: day.filteredData.date) {
                guard sources.updateValue(Source(ownerDate: owner, format: target.format,
                    archive: day.snapshot.healthKitRecordArchive,
                    captureStatus: day.snapshot.losslessArchiveDiagnostics.captureStatus,
                    markdownDiagnostics: diagnostics), forKey: target.relativePath) == nil else {
                    throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                }
            }
        }
        let frozenSources = sources
        let worker = Task.detached(priority: .utility) {
            try composeFrozen(plan: plan, pin: pin, sources: frozenSources)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func composeFrozen(plan: NativeExportArtifactPlan, pin: AppleExportEnginePin,
        sources: [String: Source]) throws -> NativeExportArtifactPlan {
        guard pin.hasExplicitWakeDateContracts, plan.profile == pin.coreProfile else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        let artifacts = try plan.artifacts.map { artifact -> NativeExportArtifact in
            try Task.checkCancellation()
            guard let source = sources[artifact.relativePath], source.format != .obsidianBases else { return artifact }
            if source.format == .json, case .none = source.archive { return artifact }
            if source.format == .markdown && source.markdownDiagnostics.isEmpty { return artifact }
            let aggregate = try artifact.content.materializedData()
            let file = try ExportArtifactIO.renderTemporary(prefix: "healthmd-wake-source", mediaType: artifact.mediaType) { sink in
                switch source.format {
                case .json:
                    guard let object = try JSONSerialization.jsonObject(with: aggregate) as? [String: Any],
                          object["schema_profile"] as? String == "apple-v11",
                          object["healthkit_record_archive"] == nil,
                          object["raw_capture_status"] as? String == source.captureStatus else {
                        throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                    }
                    try HealthKitRecordArchiveSerializer.writeDailyJSONObject(object, archive: source.archive,
                        to: sink, outputFormatting: [.prettyPrinted, .sortedKeys])
                case .csv:
                    guard let text = String(data: aggregate, encoding: .utf8) else {
                        throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                    }
                    let prefix = "\(source.ownerDate),Raw HealthKit,Raw Capture Status,"
                    var lines = text.components(separatedBy: "\n")
                    let matches = lines.indices.filter { lines[$0].hasPrefix(prefix) }
                    guard matches.count == 1 else { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
                    lines[matches[0]] = prefix + source.captureStatus + ",status,"
                    try sink.write(Data(lines.joined(separator: "\n").utf8))
                    if let archive = source.archive {
                        try HealthKitArchiveCSVProjection.write(archive: archive, ownerDate: source.ownerDate, to: sink)
                    }
                case .markdown:
                    try sink.write(aggregate)
                    try sink.write(Data(source.markdownDiagnostics.utf8))
                case .obsidianBases: break
                }
            }
            let id = NativeExportArtifactPlan.artifactID(requestID: plan.requestID, sessionID: plan.sessionID,
                profile: plan.profile, relativePath: artifact.relativePath, mediaType: artifact.mediaType,
                writeMode: artifact.writeMode, contentSHA256: file.descriptor.sha256)
            return try NativeExportArtifact(role: artifact.role, id: id, relativePath: artifact.relativePath,
                mediaType: artifact.mediaType, writeMode: artifact.writeMode, file: file,
                byteCount: file.descriptor.byteCount, sha256: file.descriptor.sha256)
        }
        let totalByteCount = try artifacts.reduce(UInt64(0)) { total, artifact in
            let result = total.addingReportingOverflow(artifact.byteCount)
            guard !result.overflow else { throw ExportArtifactIOError.byteCountOverflow }
            return result.partialValue
        }
        return try NativeExportArtifactPlan(artifactPlanVersion: plan.artifactPlanVersion,
            requestID: plan.requestID, sessionID: plan.sessionID, profile: plan.profile,
            artifacts: artifacts, totalByteCount: totalByteCount, pin: pin)
    }
}
