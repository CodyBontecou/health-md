import Foundation

enum ScheduledExportCompletion: Equatable {
    case clearedAfterSuccess
    case preservedPartialSuccess
    case preservedDeviceLocked
    case preservedFailure
    case preservedWithoutAttempt
}

@MainActor
final class ScheduledExportCoordinator {
    private let pendingExportStore: PendingExportStoring
    private let exportNotificationScheduler: ExportNotificationScheduling
    private let calendar: Calendar
    private let now: () -> Date
    private let makeID: () -> UUID

    init(
        pendingExportStore: PendingExportStoring,
        exportNotificationScheduler: ExportNotificationScheduling,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init
    ) {
        self.pendingExportStore = pendingExportStore
        self.exportNotificationScheduler = exportNotificationScheduler
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
    }

    func preparePendingScheduledExport(
        schedule: ExportSchedule,
        fireDate: Date,
        kind: ScheduledExportKind = .completedDay
    ) async throws -> PendingExportRequest {
        let request = try makePendingScheduledExportRequest(schedule: schedule, fireDate: fireDate, kind: kind)
        try pendingExportStore.upsert(request)
        try await exportNotificationScheduler.schedulePendingExportNotification(for: request)
        return request
    }

    @discardableResult
    func completePendingScheduledExport(
        _ request: PendingExportRequest,
        result: ExportOrchestrator.ExportResult
    ) async throws -> ScheduledExportCompletion {
        if result.didCompleteAllRequestedDates {
            try pendingExportStore.clearCompletedRequests(ids: [request.id])
            exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
            return .clearedAfterSuccess
        }

        // A partial batch upload must leave the request available for retry.
        // Re-sending already accepted dates is safe because API endpoint
        // exports are idempotent by date, and retaining the original request
        // prevents later failed/unattempted dates from being forgotten.
        try pendingExportStore.upsert(request)

        if result.primaryFailureReason == .deviceLocked {
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: request)
            return .preservedDeviceLocked
        }

        if result.successCount > 0 {
            return .preservedPartialSuccess
        }

        return result.totalCount > 0 ? .preservedFailure : .preservedWithoutAttempt
    }

    private func makePendingScheduledExportRequest(
        schedule: ExportSchedule,
        fireDate: Date,
        kind: ScheduledExportKind = .completedDay
    ) throws -> PendingExportRequest {
        let existingRequest = try pendingExportStore.loadAll().first { request in
            request.source == .scheduled
                && request.scheduledFireDate == fireDate
                && request.scheduledKind == kind
        }

        return PendingExportRequest(
            id: existingRequest?.id ?? makeID(),
            dates: ScheduleDateMath.exportDates(
                for: kind,
                schedule: schedule,
                fireDate: fireDate,
                calendar: calendar
            ),
            source: .scheduled,
            scheduledFireDate: fireDate,
            scheduledKind: kind,
            createdAt: existingRequest?.createdAt ?? now(),
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: schedule.target,
            calendar: calendar
        )
    }
}
