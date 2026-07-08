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
        if result.successCount > 0 {
            try pendingExportStore.clearCompletedRequests(ids: [request.id])
            exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
            return .clearedAfterSuccess
        }

        try pendingExportStore.upsert(request)

        if result.primaryFailureReason == .deviceLocked {
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: request)
            return .preservedDeviceLocked
        }

        return result.totalCount > 0 ? .preservedFailure : .preservedWithoutAttempt
    }

    private func makePendingScheduledExportRequest(
        schedule: ExportSchedule,
        fireDate: Date
    ) throws -> PendingExportRequest {
        let existingRequest = try pendingExportStore.loadAll().first { request in
            request.source == .scheduled
                && request.scheduledFireDate == fireDate
        }

        return PendingExportRequest(
            id: existingRequest?.id ?? makeID(),
            dates: ScheduleDateMath.scheduledExportDates(
                schedule: schedule,
                fireDate: fireDate,
                calendar: calendar
            ),
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: existingRequest?.createdAt ?? now(),
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: schedule.target,
            calendar: calendar
        )
    }
}
