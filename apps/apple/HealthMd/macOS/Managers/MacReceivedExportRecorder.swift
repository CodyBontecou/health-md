#if os(macOS)
import Foundation

/// What the Mac knows about an export it received from an iPhone, independent of the
/// transport (a whole `MacExportJob` or a partitioned connected-corpus session).
struct MacReceivedExport: Equatable {
    let jobID: UUID
    let sourceDeviceName: String
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let targetLabel: String
    let calendarTimeZoneIdentifier: String?
    let looseFormatsPerDate: Int

    init(job: MacExportJob) {
        self.init(
            jobID: job.jobID,
            sourceDeviceName: job.sourceDeviceName,
            dateRangeStart: job.dateRangeStart,
            dateRangeEnd: job.dateRangeEnd,
            requestedTarget: job.requestedTarget,
            settingsSnapshot: job.settingsSnapshot
        )
    }

    init(jobID: UUID, manifest: ConnectedCorpusExportManifest) {
        self.init(
            jobID: jobID,
            sourceDeviceName: manifest.sourceDeviceName,
            dateRangeStart: manifest.dateRangeStart,
            dateRangeEnd: manifest.dateRangeEnd,
            requestedTarget: manifest.requestedTarget,
            settingsSnapshot: manifest.settingsSnapshot
        )
    }

    private init(
        jobID: UUID,
        sourceDeviceName: String,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        requestedTarget: ExportTargetSnapshot?,
        settingsSnapshot: ExportSettingsSnapshot
    ) {
        self.jobID = jobID
        self.sourceDeviceName = sourceDeviceName
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.targetLabel = requestedTarget?.destinationDisplayName ?? requestedTarget?.displayName ?? "Mac"
        self.calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier
        self.looseFormatsPerDate = settingsSnapshot.makeAdvancedExportSettings().looseFormatsPerDate
    }
}

/// Records a received iPhone export into the stores the Mac Home, Activity and History
/// read (`ExportHistoryManager` and `SyncEventHistoryManager`). Every receive path that
/// writes files must call this; entries are keyed by job ID so a replayed terminal
/// result updates its entry instead of adding a second one.
enum MacReceivedExportRecorder {
    @MainActor
    static func record(_ export: MacReceivedExport, result: MacExportResultPayload) {
        ExportOrchestrator.recordResult(
            ExportOrchestrator.ExportResult(macExportPayload: result),
            source: .macAgent,
            dateRangeStart: export.dateRangeStart,
            dateRangeEnd: export.dateRangeEnd,
            targetLabel: export.targetLabel,
            fileCount: result.hasAuthoritativeFileCount ? result.totalFilesWritten : nil,
            idempotencyKey: export.jobID
        )
        SyncEventHistoryManager.shared.record(activityEvent(for: export, result: result))
    }

    @MainActor
    static func record(_ export: MacReceivedExport, failure: MacExportFailure) {
        ExportOrchestrator.recordResult(
            historyResult(for: export, failure: failure),
            source: .macAgent,
            dateRangeStart: export.dateRangeStart,
            dateRangeEnd: export.dateRangeEnd,
            targetLabel: export.targetLabel,
            fileCount: 0,
            idempotencyKey: export.jobID
        )
        SyncEventHistoryManager.shared.record(activityEvent(for: export, failure: failure))
    }

    // MARK: Pure builders (unit-tested; they never touch the persisted stores)

    static func activityEvent(
        for export: MacReceivedExport,
        result: MacExportResultPayload,
        timestamp: Date = Date()
    ) -> SyncEvent {
        SyncEvent(
            id: export.jobID,
            timestamp: timestamp,
            peerName: export.sourceDeviceName,
            kind: syncEventKind(for: result.status),
            recordCount: max(result.totalFilesWritten, result.dailyNoteUpdateCount),
            recordCountIsLowerBound: result.hasAuthoritativeFileCount ? nil : true,
            dateRangeStart: export.dateRangeStart,
            dateRangeEnd: export.dateRangeEnd,
            failureMessage: activityFailureMessage(for: result)
        )
    }

    static func activityEvent(
        for export: MacReceivedExport,
        failure: MacExportFailure,
        timestamp: Date = Date()
    ) -> SyncEvent {
        SyncEvent(
            id: export.jobID,
            timestamp: timestamp,
            peerName: export.sourceDeviceName,
            kind: failure.reason == .cancelled ? .macExportCancelled : .macExportFailed,
            recordCount: 0,
            dateRangeStart: export.dateRangeStart,
            dateRangeEnd: export.dateRangeEnd,
            failureMessage: activityFailureMessage(for: failure)
        )
    }

    static func historyResult(
        for export: MacReceivedExport,
        failure: MacExportFailure
    ) -> ExportOrchestrator.ExportResult {
        let failedDetail = FailedDateDetail(
            date: export.dateRangeStart,
            reason: exportFailureReason(for: failure.reason),
            errorDetails: failure.underlyingError ?? failure.message
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = export.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:)) ?? .gmt
        let totalCount = max(ExportOrchestrator.dateRange(
            from: export.dateRangeStart,
            to: export.dateRangeEnd,
            calendar: calendar
        ).count, 1)
        return ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: totalCount,
            failedDateDetails: [failedDetail],
            formatsPerDate: export.looseFormatsPerDate,
            wasCancelled: failure.reason == .cancelled
        )
    }

    private static func syncEventKind(for status: MacExportResultStatus) -> SyncEventKind {
        switch status {
        case .success:
            return .macExportSucceeded
        case .partialSuccess:
            return .macExportPartialSuccess
        case .failure:
            return .macExportFailed
        case .cancelled:
            return .macExportCancelled
        }
    }

    private static func activityFailureMessage(for result: MacExportResultPayload) -> String? {
        switch result.status {
        case .success:
            return nil
        case .partialSuccess:
            if result.dailyNoteSkipCount > 0,
               result.hasAuthoritativeFileCount,
               result.totalFilesWritten == 0,
               result.completedDates?.count == result.totalCount {
                return String(localized: "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) missing daily note(s); no export files were created.")
            }
            guard result.hasAuthoritativeFileCount else {
                return String(localized: "Mac export partially completed")
            }
            return String(localized: "Mac export wrote \(result.totalFilesWritten) file(s); \(result.failedDateDetails.count) date(s) need attention.")
        case .failure:
            guard let detail = result.failedDateDetails.first?.reason.shortDescription else {
                return String(localized: "Mac export failed")
            }
            return String(localized: "Mac export failed. Details: \(detail)")
        case .cancelled:
            return result.successCount > 0 && result.hasAuthoritativeFileCount
                ? String(localized: "Mac export stopped after writing \(result.totalFilesWritten) file(s).")
                : String(localized: "Mac export cancelled")
        }
    }

    private static func activityFailureMessage(for failure: MacExportFailure) -> String {
        let detail = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = failure.reason == .cancelled
            ? String(localized: "Mac export cancelled")
            : String(localized: "Mac export failed")
        guard !detail.isEmpty, detail != summary else { return summary }
        return String(localized: "\(summary). Details: \(detail)")
    }

    private static func exportFailureReason(for reason: MacExportFailureReason) -> ExportFailureReason {
        switch reason {
        case .noMacFolderSelected:
            return .noVaultSelected
        case .macFolderAccessDenied:
            return .accessDenied
        case .noHealthRecordsReceived:
            return .noHealthData
        case .exportWriteFailure:
            return .fileWriteError
        case .cancelled:
            return .unknown
        case .incompatibleProtocol, .noFormatsSelected, .payloadDecodeFailure, .macBusy:
            return .unknown
        }
    }
}
#endif
