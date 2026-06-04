import Foundation

enum ScheduledExportCompletion: Equatable {
    case clearedAfterSuccess
    case preservedDeviceLocked
    case preservedFailure
    case preservedWithoutAttempt
}

@MainActor
final class ScheduledExportCoordinator {
    private let pendingExportStore: PendingExportStoring
    private let exportNotificationScheduler: ExportNotificationScheduling
    private let pendingRequestBuilder: AutomationPendingScheduledExportRequestBuilder
    private let completionPolicy = AutomationPendingExportCompletionPolicy()

    init(
        pendingExportStore: PendingExportStoring,
        exportNotificationScheduler: ExportNotificationScheduling,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.pendingExportStore = pendingExportStore
        self.exportNotificationScheduler = exportNotificationScheduler
        self.pendingRequestBuilder = AutomationPendingScheduledExportRequestBuilder(
            calendar: calendar,
            now: now,
            makeID: makeID,
            metadata: ["notification": ExportNotificationType.pendingExport.rawValue]
        )
    }

    func preparePendingScheduledExport(
        schedule: ExportSchedule,
        fireDate: Date
    ) async throws -> PendingExportRequest {
        let request = try makePendingScheduledExportRequest(schedule: schedule, fireDate: fireDate)
        try pendingExportStore.upsert(request)
        try await exportNotificationScheduler.schedulePendingExportNotification(for: request)
        return request
    }

    @discardableResult
    func completePendingScheduledExport(
        _ request: PendingExportRequest,
        result: ExportOrchestrator.ExportResult
    ) async throws -> ScheduledExportCompletion {
        let backgroundResult = result.automationPendingExportResult
        let completion = completionPolicy.completion(for: backgroundResult)

        if completion.shouldClearRequest {
            try pendingExportStore.clearCompletedRequests(ids: [request.id])
            exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
            return .clearedAfterSuccess
        }

        let preservedRequest = request.with(reason: completionPolicy.pendingReason(for: backgroundResult))
        try pendingExportStore.upsert(preservedRequest)

        if completion.shouldSendImmediateFallbackNotification {
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: preservedRequest)
            return .preservedDeviceLocked
        }

        return completion == .preservedFailure ? .preservedFailure : .preservedWithoutAttempt
    }

    private func makePendingScheduledExportRequest(
        schedule: ExportSchedule,
        fireDate: Date
    ) throws -> PendingExportRequest {
        pendingRequestBuilder.makeRequest(
            schedule: schedule.automationSchedule(timeZone: pendingRequestBuilder.calendar.timeZone),
            fireDate: fireDate,
            existingRequests: try pendingExportStore.loadAll()
        )
    }
}

private extension ExportOrchestrator.ExportResult {
    var automationPendingExportResult: AutomationBackgroundExportResult {
        AutomationBackgroundExportResult(
            successCount: successCount,
            totalCount: totalCount,
            primaryFailureReason: wasCancelled
                ? .cancelled
                : primaryFailureReason?.automationBackgroundFailureReason,
            wasCancelled: wasCancelled
        )
    }
}

private extension ExportFailureReason {
    var automationBackgroundFailureReason: AutomationBackgroundExportFailureReason {
        switch self {
        case .noVaultSelected, .accessDenied:
            return .noDestination
        case .noHealthData:
            return .noData
        case .deviceLocked:
            return .protectedDataUnavailable
        case .backgroundTaskExpired:
            return .timeLimitExceeded
        case .healthKitError, .fileWriteError:
            return .exportFailed
        case .unknown:
            return .unknown
        }
    }
}
