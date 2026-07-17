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
        let retryRequest: PendingExportRequest
        if let remainingDates = result.remainingDates(from: request.dates, calendar: calendar) {
            guard !remainingDates.isEmpty else {
                try pendingExportStore.clearCompletedRequests(ids: [request.id])
                exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
                return .clearedAfterSuccess
            }
            retryRequest = PendingExportRequest(
                id: request.id,
                dates: remainingDates,
                source: request.source,
                scheduledFireDate: request.scheduledFireDate,
                scheduledKind: request.scheduledKind,
                createdAt: request.createdAt,
                notificationMetadata: request.notificationMetadata,
                exportTarget: request.exportTarget,
                calendar: calendar
            )
        } else if result.didCompleteAllRequestedDates {
            try pendingExportStore.clearCompletedRequests(ids: [request.id])
            exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
            return .clearedAfterSuccess
        } else {
            // Legacy aggregate-only partial results cannot identify which days
            // remain, so conservatively retain the original request.
            retryRequest = request
        }

        try pendingExportStore.upsert(retryRequest)

        if result.primaryFailureReason == .deviceLocked {
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: retryRequest)
            return .preservedDeviceLocked
        }

        if result.completedDateCount > 0 || result.successCount > 0 {
            // The stable-ID notification carries the reduced request so a tap
            // retries only unresolved dates instead of duplicating completed
            // local/Connected Mac files.
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: retryRequest)
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
        if let existingRequest {
            return existingRequest
        }

        return PendingExportRequest(
            id: makeID(),
            dates: ScheduleDateMath.exportDates(
                for: kind,
                schedule: schedule,
                fireDate: fireDate,
                calendar: calendar
            ),
            source: .scheduled,
            scheduledFireDate: fireDate,
            scheduledKind: kind,
            createdAt: now(),
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: schedule.target,
            calendar: calendar
        )
    }
}
