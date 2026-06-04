import Foundation

// MARK: - Health.md Portable Aggregate Export Runner

/// Health.md-specific aggregate-file runner backed by the reusable
/// `PortableExportOrchestrator`.
///
/// This intentionally exports only the per-day aggregate files that
/// `VaultManager.writeOneFormat` writes today. It does not manage
/// security-scoped bookmarks and does not run side effects such as Daily Note
/// Injection or Individual Entry Tracking.
@MainActor
struct HealthMdPortableAggregateExportRunner {
    func export(
        healthData: HealthData,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        trigger: PortableExportTriggerSource = .manual
    ) async -> HealthMdPortableAggregateExportResult {
        let date = healthData.date
        let formatsPerDate = settings.exportFormats.count

        guard healthData.filtered(by: settings.metricSelection).hasAnyData else {
            return .failure(
                reason: .noData,
                date: date,
                trigger: trigger,
                formatsPerDate: formatsPerDate,
                message: ExportError.noHealthData.localizedDescription,
                portableCategory: .noData
            )
        }

        guard !settings.exportFormats.isEmpty else {
            return .failure(
                reason: .noFormats,
                date: date,
                trigger: trigger,
                formatsPerDate: formatsPerDate,
                message: ExportError.noFormatsSelected.localizedDescription,
                portableCategory: .unknown
            )
        }

        let record = HealthMdPortableExportRecord(healthData: healthData, settings: settings)
        let configuration = HealthMdPortableExportAdapter.configuration(
            settings: settings,
            healthSubfolder: healthSubfolder
        )
        let plannedTargets = ExportPathPlanner.aggregateOutputTargets(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        )
        let leadingAction = Self.leadingStatusAction(
            for: plannedTargets.first,
            settings: settings
        )

        let orchestrator = PortableExportOrchestrator(
            dataSource: HealthMdPortableExportAdapter.dataSource(records: [record]),
            renderers: HealthMdPortableExportAdapter.renderers(for: settings)
        )
        let portableResult = await orchestrator.export(
            request: PortableExportRequest(dates: [date], trigger: trigger),
            destinationRoot: vaultURL,
            configuration: configuration
        )

        let outcome: HealthMdPortableAggregateExportOutcome
        if portableResult.isFullSuccess {
            outcome = .success
        } else if let noDataFailure = portableResult.failures.first(where: { $0.category == .noData }) {
            outcome = .failed(.noData)
            return HealthMdPortableAggregateExportResult(
                outcome: outcome,
                portableResult: portableResult,
                plannedTargets: [],
                writtenRelativePaths: [],
                writtenFilenames: [],
                relativeFolderPath: "",
                leadingStatusAction: nil,
                date: date,
                formatsPerDate: formatsPerDate,
                failureMessage: noDataFailure.message
            )
        } else {
            outcome = .failed(.exportFailed(portableResult.failures.first?.message ?? "Export failed"))
        }

        let writtenTargets = portableResult.isFullSuccess ? plannedTargets : []
        return HealthMdPortableAggregateExportResult(
            outcome: outcome,
            portableResult: portableResult,
            plannedTargets: plannedTargets,
            writtenRelativePaths: writtenTargets.map(\.relativePath),
            writtenFilenames: writtenTargets.map(\.filename),
            relativeFolderPath: ExportPathPlanner.aggregateFolderRelativePath(
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: date
            ),
            leadingStatusAction: portableResult.isFullSuccess ? leadingAction : nil,
            date: date,
            formatsPerDate: formatsPerDate,
            failureMessage: portableResult.failures.first?.message
        )
    }

    private static func leadingStatusAction(
        for firstTarget: ExportPathPlanner.AggregateOutputTarget?,
        settings: AdvancedExportSettings
    ) -> String {
        guard let firstTarget else { return "Exported to" }
        guard FileManager.default.fileExists(atPath: firstTarget.url.path) else {
            return "Exported to"
        }

        switch settings.writeMode {
        case .append:
            return "Appended to"
        case .update where firstTarget.format == .markdown:
            return "Updated"
        case .update, .overwrite:
            return "Exported to"
        }
    }
}

enum HealthMdPortableAggregateExportFailureReason: Equatable {
    case noData
    case noFormats
    case exportFailed(String)
}

enum HealthMdPortableAggregateExportOutcome: Equatable {
    case success
    case failed(HealthMdPortableAggregateExportFailureReason)
}

@MainActor
struct HealthMdPortableAggregateExportResult {
    let outcome: HealthMdPortableAggregateExportOutcome
    let portableResult: PortableExportRunResult
    let plannedTargets: [ExportPathPlanner.AggregateOutputTarget]
    let writtenRelativePaths: [String]
    let writtenFilenames: [String]
    let relativeFolderPath: String
    let leadingStatusAction: String?
    let date: Date
    let formatsPerDate: Int
    let failureMessage: String?

    var isSuccess: Bool {
        outcome == .success && portableResult.isFullSuccess
    }

    var filesWritten: Int {
        portableResult.filesWritten
    }

    /// Status text equivalent to the aggregate-file portion of
    /// `VaultManager.lastExportStatus`. Side-effect suffixes are intentionally
    /// absent because this runner does not run Daily Note Injection or
    /// Individual Entry Tracking.
    var legacyAggregateStatusMessage: String? {
        guard isSuccess else { return nil }
        return HealthMdAggregateExportStatusFormatter.aggregateOnlyStatusMessage(
            leadingAction: leadingStatusAction ?? "Exported to",
            relativeFolderPath: relativeFolderPath,
            writtenFilenames: writtenFilenames
        )
    }

    /// Adapter for callers that still record aggregate exports through the
    /// existing `ExportOrchestrator.ExportResult` model.
    var exportResult: ExportOrchestrator.ExportResult {
        switch outcome {
        case .success:
            return ExportOrchestrator.ExportResult(
                successCount: 1,
                totalCount: 1,
                failedDateDetails: [],
                formatsPerDate: formatsPerDate
            )
        case .failed(let reason):
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 1,
                failedDateDetails: [FailedDateDetail(
                    date: date,
                    reason: Self.exportFailureReason(for: reason),
                    errorDetails: failureMessage
                )],
                formatsPerDate: formatsPerDate
            )
        }
    }

    static func failure(
        reason: HealthMdPortableAggregateExportFailureReason,
        date: Date,
        trigger: PortableExportTriggerSource,
        formatsPerDate: Int,
        message: String,
        portableCategory: PortableExportFailureCategory
    ) -> HealthMdPortableAggregateExportResult {
        HealthMdPortableAggregateExportResult(
            outcome: .failed(reason),
            portableResult: PortableExportRunResult(
                successfulRecordCount: 0,
                totalRecordCount: 1,
                filesWritten: 0,
                failures: [PortableExportFailure(
                    recordID: nil,
                    date: date,
                    category: portableCategory,
                    message: message
                )],
                trigger: trigger
            ),
            plannedTargets: [],
            writtenRelativePaths: [],
            writtenFilenames: [],
            relativeFolderPath: "",
            leadingStatusAction: nil,
            date: date,
            formatsPerDate: formatsPerDate,
            failureMessage: message
        )
    }

    private static func exportFailureReason(
        for reason: HealthMdPortableAggregateExportFailureReason
    ) -> ExportFailureReason {
        switch reason {
        case .noData:
            return .noHealthData
        case .noFormats:
            return .unknown
        case .exportFailed:
            return .fileWriteError
        }
    }
}
