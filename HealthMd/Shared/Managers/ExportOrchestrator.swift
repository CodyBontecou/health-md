import Foundation
import ExportKit
import ExportAutomationKit

private extension WriteMode {
    var orchestratorExportKitWriteMode: ExportWriteMode {
        switch self {
        case .overwrite:
            return .overwrite
        case .append:
            return .append
        case .update:
            return .update
        }
    }
}

/// Shared export orchestration logic used by both iOS and macOS.
/// Eliminates duplication between manual export (ContentView), scheduled export
/// (SchedulingManager), and future macOS export triggers.
@MainActor
struct ExportOrchestrator {

    // MARK: - Result Type

    struct ExportResult {
        let successCount: Int
        let totalCount: Int
        let failedDateDetails: [FailedDateDetail]
        let partialFailures: [ExportPartialFailure]
        let wasCancelled: Bool
        /// Number of files written per successful date (= count of selected formats at export time).
        let formatsPerDate: Int

        init(
            successCount: Int,
            totalCount: Int,
            failedDateDetails: [FailedDateDetail],
            partialFailures: [ExportPartialFailure] = [],
            formatsPerDate: Int = 1,
            wasCancelled: Bool = false
        ) {
            self.successCount = successCount
            self.totalCount = totalCount
            self.failedDateDetails = failedDateDetails
            self.partialFailures = partialFailures
            self.formatsPerDate = formatsPerDate
            self.wasCancelled = wasCancelled
        }

        var hasPartialFailures: Bool { !partialFailures.isEmpty }
        var partialFailureSummary: String {
            guard let first = partialFailures.first else { return "" }
            if partialFailures.count == 1 {
                return "Warning: \(first.summary)"
            }
            return "Warning: \(partialFailures.count) metric fetches failed, including \(first.summary)"
        }
        var isFullSuccess: Bool { successCount == totalCount && totalCount > 0 && !wasCancelled && !hasPartialFailures }
        var isPartialSuccess: Bool {
            (successCount > 0 && successCount < totalCount) ||
            (successCount > 0 && wasCancelled) ||
            (successCount > 0 && hasPartialFailures)
        }
        var isFailure: Bool { successCount == 0 && totalCount > 0 }
        var primaryFailureReason: ExportFailureReason? { failedDateDetails.first?.reason }
        /// Total file count = days that succeeded × formats per day.
        var totalFilesWritten: Int { successCount * formatsPerDate }
    }

    // MARK: - Date Range Helper

    /// Builds an array of calendar days from startDate through endDate (inclusive).
    static func dateRange(from startDate: Date, to endDate: Date) -> [Date] {
        ExportDateWindowRequest(startDate: startDate, endDate: endDate).dates(calendar: .current)
    }

    // MARK: - Foreground Export (security-scoped)

    /// Export health data for a list of dates.
    /// Each date manages its own security-scoped access via VaultManager's async method.
    /// Suitable for manual/foreground exports.
    static func exportDates(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        let formatsPerDate = settings.exportFormats.count
        var partialFailures: [ExportPartialFailure] = []
        let formatIDs = settings.sortedExportFormats.map(\.exportKitFormatID)

        let request = ExportRunRequest<Date>(
            recordInputs: dates,
            formatIDs: formatIDs,
            destination: vaultManager.currentExportDestination,
            writeMode: settings.writeMode.orchestratorExportKitWriteMode,
            recordReference: { date in
                recordReference(for: date)
            }
        )

        let dataSource = AnyExportRecordDataSource<Date, HealthExportRecord> { date in
            let healthData = try await healthKitManager.fetchHealthData(
                for: date,
                includeGranularData: settings.includeGranularData,
                metricSelection: settings.metricSelection
            )
            partialFailures.append(contentsOf: healthData.partialFailures)

            guard healthData.filtered(by: settings.metricSelection).hasAnyData else {
                return ExportFetchedRecord(record: nil)
            }

            return ExportFetchedRecord(record: HealthExportRecord(healthData: healthData))
        }

        let writer = AnyExportRecordWriter<HealthExportRecord> { record, context in
            try await vaultManager.exportHealthData(record.healthData, settings: settings)
            return ExportRecordWriteSummary(filesWritten: context.formatIDs.count)
        }

        let orchestrator = ExportRunOrchestrator(
            dataSource: dataSource,
            writer: writer,
            failureMapper: exportRunFailure(for:)
        )
        let runResult = await orchestrator.run(request) { progress in
            guard progress.phase == .fetching,
                  progress.currentIndex > 0,
                  let dateString = progress.currentRecord?.displayName else {
                return
            }
            onProgress?(progress.currentIndex, progress.totalRecords, dateString)
        }

        return exportResult(
            from: runResult,
            partialFailures: partialFailures,
            formatsPerDate: formatsPerDate
        )
    }

    // MARK: - Background Export (caller-managed scope)

    /// Export health data for a list of dates without managing security scope.
    /// Caller must start/stop vault access. Suitable for background tasks and
    /// scheduled exports where scope is managed externally.
    static func exportDatesBackground(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings
    ) async -> ExportResult {
        let formatsPerDate = settings.exportFormats.count
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []

        for date in dates {
            // Check for cancellation before each date
            if Task.isCancelled {
                return ExportResult(
                    successCount: successCount,
                    totalCount: dates.count,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: formatsPerDate,
                    wasCancelled: true
                )
            }

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection
                )
                partialFailures.append(contentsOf: healthData.partialFailures)

                if !healthData.filtered(by: settings.metricSelection).hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: settings)

                if success {
                    successCount += 1
                } else {
                    failedDateDetails.append(FailedDateDetail(
                        date: date,
                        reason: .fileWriteError,
                        errorDetails: vaultManager.lastExportStatus
                    ))
                }
            } catch let error as HealthKitManager.HealthKitError {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: failureReason(for: error)
                ))
            } catch {
                failedDateDetails.append(FailedDateDetail(
                    date: date, reason: .healthKitError, errorDetails: error.localizedDescription
                ))
            }
        }

        return ExportResult(
            successCount: successCount,
            totalCount: dates.count,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: formatsPerDate
        )
    }

    // MARK: - ExportKit Mapping

    private static func recordReference(for date: Date) -> ExportRecordReference {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return ExportRecordReference(id: dateString, date: date, displayName: dateString)
    }

    private static func exportRunFailure(for error: Error) -> ExportRunFailure {
        if let error = error as? ExportError {
            switch error {
            case .noVaultSelected:
                return ExportRunFailure(reason: .noDestination)
            case .noHealthData:
                return ExportRunFailure(reason: .noData)
            case .accessDenied:
                return ExportRunFailure(reason: .accessDenied)
            case .noFormatsSelected:
                return ExportRunFailure(reason: .noFormatsSelected, errorDescription: error.localizedDescription)
            case .dailyNotePathConflict:
                return ExportRunFailure(reason: .writeError, errorDescription: error.localizedDescription)
            }
        }

        if let error = error as? HealthKitManager.HealthKitError {
            switch error {
            case .dataProtectedWhileLocked:
                return ExportRunFailure(reason: .protectedDataUnavailable)
            case .notAuthorized, .dataNotAvailable, .medicationAuthorizationUnsupported:
                return ExportRunFailure(reason: .dataSourceError)
            }
        }

        return ExportRunFailure(reason: .unknown, errorDescription: error.localizedDescription)
    }

    private static func exportResult(
        from runResult: ExportRunResult,
        partialFailures: [ExportPartialFailure],
        formatsPerDate: Int
    ) -> ExportResult {
        let failedDateDetails = runResult.failedRecords.compactMap { failedRecord -> FailedDateDetail? in
            guard let date = failedRecord.record.date else { return nil }
            return FailedDateDetail(
                date: date,
                reason: failureReason(for: failedRecord.failure.reason),
                errorDetails: failedRecord.failure.errorDescription
            )
        }

        return ExportResult(
            successCount: runResult.successCount,
            totalCount: runResult.totalCount,
            failedDateDetails: failedDateDetails,
            partialFailures: partialFailures,
            formatsPerDate: formatsPerDate,
            wasCancelled: runResult.wasCancelled
        )
    }

    private static func failureReason(for reason: ExportRunFailureReason) -> ExportFailureReason {
        switch reason {
        case .noDestination:
            return .noVaultSelected
        case .accessDenied:
            return .accessDenied
        case .noData:
            return .noHealthData
        case .protectedDataUnavailable:
            return .deviceLocked
        case .dataSourceError:
            return .healthKitError
        case .renderError, .writeError:
            return .fileWriteError
        case .noFormatsSelected, .cancelled, .unknown:
            return .unknown
        }
    }

    // MARK: - Failure Mapping

    private static func failureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized, .dataNotAvailable, .medicationAuthorizationUnsupported:
            return .healthKitError
        }
    }

    // MARK: - History Recording Helper

    /// Records an export result in the history manager.
    static func recordResult(
        _ result: ExportResult,
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        targetLabel: String? = nil,
        fileCount: Int? = nil
    ) {
        recordResult(
            result,
            source: source,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            targetLabel: targetLabel,
            fileCount: fileCount,
            partialFailures: result.partialFailures
        )
    }

    /// Records an export result using the generic ExportAutomationKit trigger
    /// source policy, while preserving Health.md's current history labels.
    static func recordResult(
        _ result: ExportResult,
        triggerSource: ExportTriggerSource,
        resolvedSourceFamily: ExportTriggerSourceFamily? = nil,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        targetLabel: String? = nil,
        fileCount: Int? = nil
    ) {
        recordResult(
            result,
            source: ExportSource(triggerSource: triggerSource, resolvedSourceFamily: resolvedSourceFamily),
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            targetLabel: targetLabel,
            fileCount: fileCount,
            partialFailures: result.partialFailures
        )
    }

    private static func recordResult(
        _ result: ExportResult,
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        targetLabel: String?,
        fileCount: Int?,
        partialFailures: [ExportPartialFailure]
    ) {
        let history = ExportHistoryManager.shared
        let resolvedFileCount = fileCount ?? result.totalFilesWritten

        if result.successCount > 0 {
            history.recordSuccess(
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails,
                targetLabel: targetLabel,
                fileCount: resolvedFileCount,
                partialFailures: partialFailures
            )
        } else {
            history.recordFailure(
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                reason: result.primaryFailureReason ?? .unknown,
                successCount: 0,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails,
                targetLabel: targetLabel,
                fileCount: resolvedFileCount,
                partialFailures: partialFailures
            )
        }
    }
}
