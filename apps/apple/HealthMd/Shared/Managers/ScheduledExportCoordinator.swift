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
    // Keep deallocation on the releasing thread. Avoid Swift 6.2+'s crashing
    // isolated-deinit executor hop (swiftlang/swift#85663), which aborted CI
    // test processes on older iOS runtimes when the last release happened off
    // the main actor. Matches the AdvancedExportSettings convention.
    nonisolated deinit {}
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
        kind: ScheduledExportKind = .completedDay,
        profile: ScheduledProfileRequestContext? = nil,
        makeSettingsSnapshot: () async -> ExportSettingsSnapshot? = { nil }
    ) async throws -> PendingExportRequest {
        let request = try await makePendingScheduledExportRequest(
            schedule: schedule,
            fireDate: fireDate,
            kind: kind,
            profile: profile,
            makeSettingsSnapshot: makeSettingsSnapshot
        )
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
                settingsSnapshot: request.settingsSnapshot,
                profileID: request.profileID,
                profileName: request.profileName,
                googleDriveDestinationSnapshot: request.googleDriveDestinationSnapshot,
                attemptedAt: now(),
                calendar: calendar
            )
        } else if result.didCompleteAllRequestedDates {
            try pendingExportStore.clearCompletedRequests(ids: [request.id])
            exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
            return .clearedAfterSuccess
        } else {
            // Legacy aggregate-only partial results cannot identify which days
            // remain, so conservatively retain the original request — marked
            // attempted so bulk fallback cancellation cannot destroy it.
            retryRequest = request.markingAttempted(at: now())
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

    /// Profile-scoped context for a scheduled request: the frozen snapshot and
    /// target come from the profile, and dedup is per profile so two profiles'
    /// requests at the same fire date never collapse into one.
    struct ScheduledProfileRequestContext {
        let profileID: UUID
        let profileName: String
        let target: ExportTargetSelection
        let settings: ExportSettingsSnapshot
        let googleDriveDestinationSnapshot: GoogleDriveDestinationSnapshot?

        init(
            profileID: UUID,
            profileName: String,
            target: ExportTargetSelection,
            settings: ExportSettingsSnapshot,
            googleDriveDestinationSnapshot: GoogleDriveDestinationSnapshot? = nil
        ) {
            self.profileID = profileID
            self.profileName = profileName
            self.target = target
            self.settings = settings
            self.googleDriveDestinationSnapshot = googleDriveDestinationSnapshot
        }
    }

    private func makePendingScheduledExportRequest(
        schedule: ExportSchedule,
        fireDate: Date,
        kind: ScheduledExportKind = .completedDay,
        profile: ScheduledProfileRequestContext? = nil,
        makeSettingsSnapshot: () async -> ExportSettingsSnapshot? = { nil }
    ) async throws -> PendingExportRequest {
        let existingRequest = try pendingExportStore.loadAll().first { request in
            request.source == .scheduled
                && request.scheduledFireDate == fireDate
                && request.scheduledKind == kind
                && request.profileID == profile?.profileID
        }
        if let existingRequest {
            return existingRequest
        }

        let frozenSettings: ExportSettingsSnapshot?
        if let profile {
            frozenSettings = profile.settings
        } else {
            frozenSettings = await makeSettingsSnapshot()
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
            exportTarget: profile?.target ?? schedule.target,
            settingsSnapshot: frozenSettings,
            profileID: profile?.profileID,
            profileName: profile?.profileName,
            googleDriveDestinationSnapshot: profile?.googleDriveDestinationSnapshot,
            calendar: calendar
        )
    }
}
