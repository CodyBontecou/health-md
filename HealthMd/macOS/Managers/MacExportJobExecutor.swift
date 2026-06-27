import Foundation

#if os(macOS)

/// Executes iOS-originated Mac export jobs without consulting the legacy Mac
/// health-data cache. The job's records and `ExportSettingsSnapshot` are the
/// complete source of truth.
@MainActor
final class MacExportJobExecutor {
    typealias ProgressHandler = (MacExportProgress) -> Void

    private var activeJobID: UUID?
    private var cancelledJobIDs: Set<UUID> = []

    init() {}

    var isBusy: Bool { activeJobID != nil }
    var currentJobID: UUID? { activeJobID }

    func cancel(jobID: UUID) {
        cancelledJobIDs.insert(jobID)
    }

    func execute(
        _ job: MacExportJob,
        vaultManager: VaultManager,
        progress: ProgressHandler? = nil
    ) async -> Result<MacExportResultPayload, MacExportFailure> {
        guard activeJobID == nil else {
            return .failure(MacExportFailure(
                jobID: job.jobID,
                reason: .macBusy,
                message: "This Mac is already exporting another job."
            ))
        }

        activeJobID = job.jobID
        defer {
            activeJobID = nil
            cancelledJobIDs.remove(job.jobID)
        }

        let requestedDates = Self.requestedDates(for: job)
        let totalDays = requestedDates.count
        let formatsPerDate = Self.looseFormatsPerDate(for: job.settingsSnapshot)

        sendProgress(
            jobID: job.jobID,
            phase: .receiving,
            processedDays: 0,
            totalDays: totalDays,
            currentDate: nil,
            filesWritten: 0,
            message: "Received export job from \(job.sourceDeviceName)",
            progress: progress
        )

        if cancelledJobIDs.contains(job.jobID) || Task.isCancelled {
            return .success(cancelledResult(for: job, totalDays: totalDays, formatsPerDate: formatsPerDate, vaultManager: vaultManager))
        }

        sendProgress(
            jobID: job.jobID,
            phase: .validating,
            processedDays: 0,
            totalDays: totalDays,
            currentDate: nil,
            filesWritten: 0,
            message: "Validating Mac destination…",
            progress: progress
        )

        if let validationFailure = validate(job, vaultManager: vaultManager) {
            return .failure(validationFailure)
        }

        let settings = job.settingsSnapshot.makeAdvancedExportSettings()
        let recordsByDate = Self.recordsByStartOfDay(job.records)
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        var successfulRecords: [HealthData] = []
        var totalFilesWritten = 0
        var processedDays = 0

        for date in requestedDates {
            if cancelledJobIDs.contains(job.jobID) || Task.isCancelled {
                let result = MacExportResultPayload(
                    jobID: job.jobID,
                    status: .cancelled,
                    successCount: successCount,
                    totalCount: totalDays,
                    formatsPerDate: formatsPerDate,
                    totalFilesWritten: totalFilesWritten,
                    failedDateDetails: failedDateDetails,
                    destinationDisplayName: vaultManager.vaultName,
                    destinationPathForDisplay: vaultManager.vaultURL?.path,
                    completedAt: Date()
                )
                sendProgress(
                    jobID: job.jobID,
                    phase: .cancelled,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: date,
                    filesWritten: totalFilesWritten,
                    message: "Mac export cancelled.",
                    progress: progress
                )
                return .success(result)
            }

            processedDays += 1
            guard let record = recordsByDate[Calendar.current.startOfDay(for: date)] else {
                failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                sendProgress(
                    jobID: job.jobID,
                    phase: .exporting,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: date,
                    filesWritten: totalFilesWritten,
                    message: "No health data for \(Self.displayDate(date))",
                    progress: progress
                )
                continue
            }

            sendProgress(
                jobID: job.jobID,
                phase: .writing,
                processedDays: processedDays - 1,
                totalDays: totalDays,
                currentDate: record.date,
                filesWritten: totalFilesWritten,
                message: "Writing \(Self.displayDate(record.date))…",
                progress: progress
            )

            do {
                try await vaultManager.exportHealthData(record, settings: settings)
                successCount += 1
                successfulRecords.append(record)
                totalFilesWritten += formatsPerDate
                sendProgress(
                    jobID: job.jobID,
                    phase: .writing,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: record.date,
                    filesWritten: totalFilesWritten,
                    message: "Wrote \(Self.displayDate(record.date))",
                    progress: progress
                )
            } catch {
                failedDateDetails.append(Self.failedDateDetail(for: record.date, error: error))
                sendProgress(
                    jobID: job.jobID,
                    phase: .failed,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: record.date,
                    filesWritten: totalFilesWritten,
                    message: error.localizedDescription,
                    progress: progress
                )
            }
        }

        let rollupRecords = Self.rollupRecords(
            for: requestedDates,
            recordsByDate: recordsByDate,
            settings: settings
        )
        if !settings.archiveExportFiles,
           !rollupRecords.isEmpty,
           HealthRollupExporter.isEnabled(settings: settings) {
            sendProgress(
                jobID: job.jobID,
                phase: .writing,
                processedDays: processedDays,
                totalDays: totalDays,
                currentDate: nil,
                filesWritten: totalFilesWritten,
                message: "Writing roll-up summaries…",
                progress: progress
            )

            do {
                let rollupResults = try vaultManager.exportRollupSummaries(from: rollupRecords, settings: settings)
                totalFilesWritten += rollupResults.count
            } catch {
                let sortedDates = rollupRecords.map(\.date).sorted()
                failedDateDetails.append(FailedDateDetail(
                    date: sortedDates.first ?? Date(),
                    reason: .fileWriteError,
                    errorDetails: "Roll-up summary export failed: \(error.localizedDescription)"
                ))
            }
        }

        if settings.archiveExportFiles && !successfulRecords.isEmpty {
            sendProgress(
                jobID: job.jobID,
                phase: .writing,
                processedDays: processedDays,
                totalDays: totalDays,
                currentDate: nil,
                filesWritten: totalFilesWritten,
                message: "Writing ZIP archive…",
                progress: progress
            )
            totalFilesWritten += Self.writeArchive(
                from: successfulRecords,
                rollupHealthData: rollupRecords,
                selectedDates: requestedDates,
                vaultManager: vaultManager,
                settings: settings,
                failedDateDetails: &failedDateDetails
            )
        }

        let status: MacExportResultStatus
        if successCount == totalDays && failedDateDetails.isEmpty {
            status = .success
        } else if successCount > 0 {
            status = .partialSuccess
        } else {
            status = .failure
        }

        let result = MacExportResultPayload(
            jobID: job.jobID,
            status: status,
            successCount: successCount,
            totalCount: totalDays,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: totalFilesWritten,
            failedDateDetails: failedDateDetails,
            destinationDisplayName: vaultManager.vaultName,
            destinationPathForDisplay: vaultManager.vaultURL?.path,
            completedAt: Date()
        )

        sendProgress(
            jobID: job.jobID,
            phase: status == .failure ? .failed : .completed,
            processedDays: processedDays,
            totalDays: totalDays,
            currentDate: nil,
            filesWritten: totalFilesWritten,
            message: Self.completionMessage(for: result),
            progress: progress
        )

        return .success(result)
    }

    private func validate(_ job: MacExportJob, vaultManager: VaultManager) -> MacExportFailure? {
        guard vaultManager.vaultURL != nil else {
            return MacExportFailure(
                jobID: job.jobID,
                reason: .noMacFolderSelected,
                message: "Choose a destination folder on this Mac before exporting."
            )
        }

        guard vaultManager.canAccessSelectedVaultFolder() else {
            return MacExportFailure(
                jobID: job.jobID,
                reason: .macFolderAccessDenied,
                message: "Health.md can’t access the selected Mac folder. Re-select the destination folder on this Mac and try again."
            )
        }

        guard !job.settingsSnapshot.exportFormats.isEmpty else {
            return MacExportFailure(
                jobID: job.jobID,
                reason: .noFormatsSelected,
                message: "At least one export format must be selected on iPhone."
            )
        }

        guard !job.records.isEmpty else {
            return MacExportFailure(
                jobID: job.jobID,
                reason: .noHealthRecordsReceived,
                message: "No health records were received from iPhone."
            )
        }

        return nil
    }

    private func sendProgress(
        jobID: UUID,
        phase: MacExportPhase,
        processedDays: Int,
        totalDays: Int,
        currentDate: Date?,
        filesWritten: Int,
        message: String,
        progress: ProgressHandler?
    ) {
        progress?(MacExportProgress(
            jobID: jobID,
            phase: phase,
            processedDays: processedDays,
            totalDays: totalDays,
            currentDate: currentDate,
            filesWritten: filesWritten,
            message: message
        ))
    }

    private func cancelledResult(
        for job: MacExportJob,
        totalDays: Int,
        formatsPerDate: Int,
        vaultManager: VaultManager
    ) -> MacExportResultPayload {
        MacExportResultPayload(
            jobID: job.jobID,
            status: .cancelled,
            successCount: 0,
            totalCount: totalDays,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: 0,
            failedDateDetails: [],
            destinationDisplayName: vaultManager.vaultName,
            destinationPathForDisplay: vaultManager.vaultURL?.path,
            completedAt: Date()
        )
    }

    private static func requestedDates(for job: MacExportJob) -> [Date] {
        let dates = ExportOrchestrator.dateRange(from: job.dateRangeStart, to: job.dateRangeEnd)
        if !dates.isEmpty { return dates }
        return job.records.map(\.date).sorted()
    }

    private static func looseFormatsPerDate(for snapshot: ExportSettingsSnapshot) -> Int {
        snapshot.archiveExportFiles ? 0 : snapshot.exportFormats.count
    }

    private static func recordsByStartOfDay(_ records: [HealthData]) -> [Date: HealthData] {
        var result: [Date: HealthData] = [:]
        for record in records {
            result[Calendar.current.startOfDay(for: record.date)] = record
        }
        return result
    }

    private static func rollupRecords(
        for requestedDates: [Date],
        recordsByDate: [Date: HealthData],
        settings: AdvancedExportSettings
    ) -> [HealthData] {
        guard HealthRollupExporter.isEnabled(settings: settings) else { return [] }
        let sourceDates = ExportOrchestrator.rollupSourceDates(for: requestedDates, settings: settings)
        return sourceDates.compactMap { date in
            recordsByDate[Calendar.current.startOfDay(for: date)]
        }
    }

    private static func writeArchive(
        from successfulRecords: [HealthData],
        rollupHealthData: [HealthData],
        selectedDates: [Date],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        failedDateDetails: inout [FailedDateDetail]
    ) -> Int {
        guard settings.archiveExportFiles else { return 0 }
        guard !successfulRecords.isEmpty else { return 0 }

        let sortedDates = selectedDates.sorted()
        let startDate = sortedDates.first ?? successfulRecords.map(\.date).min() ?? Date()
        let endDate = sortedDates.last ?? successfulRecords.map(\.date).max() ?? startDate

        do {
            return try vaultManager.exportArchive(
                from: successfulRecords,
                rollupHealthData: rollupHealthData,
                settings: settings,
                startDate: startDate,
                endDate: endDate
            ) == nil ? 0 : 1
        } catch {
            failedDateDetails.append(FailedDateDetail(
                date: startDate,
                reason: .fileWriteError,
                errorDetails: "ZIP archive export failed: \(error.localizedDescription)"
            ))
            return 0
        }
    }

    private static func failedDateDetail(for date: Date, error: Error) -> FailedDateDetail {
        if let exportError = error as? ExportError {
            switch exportError {
            case .noVaultSelected:
                return FailedDateDetail(date: date, reason: .noVaultSelected)
            case .noHealthData:
                return FailedDateDetail(date: date, reason: .noHealthData)
            case .accessDenied:
                return FailedDateDetail(date: date, reason: .accessDenied)
            case .noFormatsSelected, .dailyNotePathConflict:
                return FailedDateDetail(date: date, reason: .fileWriteError, errorDetails: exportError.localizedDescription)
            }
        }
        return FailedDateDetail(date: date, reason: .fileWriteError, errorDetails: error.localizedDescription)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func completionMessage(for result: MacExportResultPayload) -> String {
        switch result.status {
        case .success:
            return "Export complete on Mac."
        case .partialSuccess:
            return "Mac export completed with some skipped dates."
        case .failure:
            return "Mac export failed."
        case .cancelled:
            return "Mac export cancelled."
        }
    }
}

#endif
