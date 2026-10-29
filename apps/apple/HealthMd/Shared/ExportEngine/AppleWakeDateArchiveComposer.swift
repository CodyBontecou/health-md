import Foundation

/// Combines bounded core aggregates with native source archives and partial-capture facts.
/// Only immutable inputs enter the worker; the returned plan hashes final, file-backed bytes.
nonisolated enum AppleWakeDateArchiveComposer {
    struct Source: Sendable {
        let ownerDate: String
        let format: ExportFormat
        let archive: HealthKitRecordArchive?
        let captureStatus: String
        let markdownDiagnostics: String
        let partialFailures: [ExportPartialFailure]
        let headerPrefix: String
        let providers: HealthProviderSections?
        let providerMarkdown: String
        let includeMetadata: Bool
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
            let providerMarkdown = day.filteredData.whoopProviderMarkdown(snapshot: day.snapshot,
                headerPrefix: String(repeating: "#", count: settings.formatCustomization.markdownTemplate.sectionHeaderLevel))
            for target in ExportPathPlanner.aggregateOutputTargets(vaultURL: root,
                healthSubfolder: healthSubfolder, settings: settings, date: day.filteredData.date) {
                guard sources.updateValue(Source(ownerDate: owner, format: target.format,
                    archive: day.snapshot.healthKitRecordArchive,
                    captureStatus: day.snapshot.losslessArchiveDiagnostics.captureStatus,
                    markdownDiagnostics: diagnostics,
                    partialFailures: day.snapshot.partialFailures,
                    headerPrefix: String(repeating: "#", count: settings.formatCustomization.markdownTemplate.sectionHeaderLevel),
                    providers: day.snapshot.providers,
                    providerMarkdown: providerMarkdown,
                    includeMetadata: settings.includeMetadata), forKey: target.relativePath) == nil else {
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
            guard let source = sources[artifact.relativePath] else { return artifact }
            let hasProviders = source.providers?.isEmpty == false
            if source.format == .obsidianBases && source.partialFailures.isEmpty && !hasProviders { return artifact }
            if source.format == .json, case .none = source.archive, source.partialFailures.isEmpty && !hasProviders { return artifact }
            if source.format == .markdown && source.markdownDiagnostics.isEmpty && source.partialFailures.isEmpty && !hasProviders { return artifact }
            var aggregate = try artifact.content.materializedData()
            if let providers = source.providers, hasProviders {
                _ = try AppleWakeDateProviderProjection.lazyJSONObject(providers)
                if source.format == .markdown || source.format == .obsidianBases {
                    aggregate = try AppleWakeDateProviderProjection.addingFrontmatter(to: aggregate,
                        providers: providers, includeMetadata: source.includeMetadata)
                }
            }
            let file = try ExportArtifactIO.renderTemporary(prefix: "healthmd-wake-source", mediaType: artifact.mediaType) { sink in
                switch source.format {
                case .json:
                    guard var object = try JSONSerialization.jsonObject(with: aggregate) as? [String: Any],
                          object["schema_profile"] as? String == "apple-v11",
                          object["healthkit_record_archive"] == nil,
                          object["diagnostics"] == nil,
                          object["providers"] == nil,
                          object["raw_capture_status"] as? String == source.captureStatus else {
                        throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                    }
                    if !source.partialFailures.isEmpty {
                        object["diagnostics"] = ExportDiagnosticSerializer.lazyDiagnostics(source.partialFailures)
                    }
                    if let providers = source.providers, hasProviders {
                        object["providers"] = try AppleWakeDateProviderProjection.lazyJSONObject(providers)
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
                    try HealthKitArchiveCSVProjection.writePartialFailures(source.partialFailures,
                        ownerDate: source.ownerDate, to: sink)
                    if let providers = source.providers { try WHOOPCSVProjection.write(providers, ownerDate: source.ownerDate, to: sink) }
                case .markdown, .obsidianBases:
                    try sink.write(aggregate)
                    if source.format == .markdown { try sink.write(Data(source.markdownDiagnostics.utf8)) }
                    try ExportDiagnosticSerializer.writeMarkdownSection(source.partialFailures,
                        headerPrefix: source.headerPrefix, to: sink)
                    if let providers = source.providers, hasProviders {
                        if source.format == .markdown { try sink.write(Data(source.providerMarkdown.utf8)) }
                        try AppleWakeDateProviderProjection.writeMarkdownSection(providers,
                            headerPrefix: source.headerPrefix, to: sink)
                    }
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
