import Foundation

enum ScheduledExportCompletion: Equatable {
    case clearedAfterSuccess
    case preservedPartialSuccess
    case preservedDeviceLocked
    case preservedFailure
    case preservedWithoutAttempt
    case discarded
}

enum ScheduledExportPreparationError: Error {
    case invalidated
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
    /// Runtime-owned authority. Recheck after suspensions before checkpointing or
    /// advertising recovery; a discarded request must never be resurrected.
    var shouldRetainRequest: @MainActor (PendingExportRequest) -> Bool = { _ in true }

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
        apiDestinationIdentity: ScheduledAPIEndpointIdentity? = nil,
        makeSettingsSnapshot: () async -> ExportSettingsSnapshot? = { nil }
    ) async throws -> PendingExportRequest {
        let request = try await makePendingScheduledExportRequest(
            schedule: schedule,
            fireDate: fireDate,
            kind: kind,
            profile: profile,
            apiDestinationIdentity: apiDestinationIdentity,
            makeSettingsSnapshot: makeSettingsSnapshot
        )
        guard shouldRetainRequest(request) else { throw ScheduledExportPreparationError.invalidated }
        try pendingExportStore.upsert(request)
        try await exportNotificationScheduler.schedulePendingExportNotification(for: request)
        guard try isRetained(request) else {
            try discard(request)
            throw ScheduledExportPreparationError.invalidated
        }
        return request
    }

    @discardableResult
    func completePendingScheduledExport(
        _ request: PendingExportRequest,
        result: ExportOrchestrator.ExportResult
    ) async throws -> ScheduledExportCompletion {
        guard try isRetained(request) else {
            try discard(request)
            return .discarded
        }
        let retryRequest: PendingExportRequest
        let requestCalendar = frozenCalendar(for: request.originalCalendarTimeZoneIdentifier)
        if let remainingDates = result.remainingDates(from: request.dates, calendar: requestCalendar) {
            guard !remainingDates.isEmpty else {
                try pendingExportStore.clearCompletedRequests(ids: [request.id])
                exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
                return .clearedAfterSuccess
            }
            retryRequest = request.replacingResidualDates(
                remainingDates,
                attemptedAt: now()
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
            guard try isRetained(retryRequest) else {
                try discard(retryRequest)
                return .discarded
            }
            return .preservedDeviceLocked
        }

        if result.completedDateCount > 0 || result.successCount > 0 {
            // The stable-ID notification carries the reduced request so a tap
            // retries only unresolved dates instead of duplicating completed
            // local/Connected Mac files.
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: retryRequest)
            guard try isRetained(retryRequest) else {
                try discard(retryRequest)
                return .discarded
            }
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
        var recoveryGeneration: Int = 0
        var enabledAt: Date? = nil
        var apiDestinationIdentity: ScheduledAPIEndpointIdentity? = nil
    }

    private func isRetained(_ request: PendingExportRequest) throws -> Bool {
        guard shouldRetainRequest(request) else { return false }
        return try pendingExportStore.loadAll().contains { $0.id == request.id }
    }

    private func discard(_ request: PendingExportRequest) throws {
        exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
        try pendingExportStore.remove(id: request.id)
    }

    private func makePendingScheduledExportRequest(
        schedule: ExportSchedule,
        fireDate: Date,
        kind: ScheduledExportKind = .completedDay,
        profile: ScheduledProfileRequestContext? = nil,
        apiDestinationIdentity: ScheduledAPIEndpointIdentity?,
        makeSettingsSnapshot: () async -> ExportSettingsSnapshot? = { nil }
    ) async throws -> PendingExportRequest {
        let existingRequest = try pendingExportStore.loadAll().first { request in
            request.source == .scheduled
                && request.scheduledFireDate == fireDate
                && request.scheduledKind == kind
                && request.profileID == profile?.profileID
                && request.recoveryGeneration == (profile?.recoveryGeneration ?? 0)
        }
        if let existingRequest {
            if shouldRetainRequest(existingRequest) { return existingRequest }
            try discard(existingRequest)
        }

        let captureContext = AppleSleepCaptureContext.resolve(
            timeZone: profile?.settings.calendarTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone,
            attribution: HealthKitManager.shared.sleepDayAttribution)
        let frozenSettings: ExportSettingsSnapshot?
        if let profile {
            frozenSettings = profile.settings
        } else {
            frozenSettings = await AppleSleepCaptureContext.pinned.withValue(captureContext) {
                await makeSettingsSnapshot()
            }
        }

        let requestCalendar = frozenCalendar(
            for: frozenSettings?.calendarTimeZoneIdentifier
        )
        return PendingExportRequest(
            id: makeID(),
            dates: ScheduleDateMath.exportDates(
                for: kind,
                schedule: schedule,
                fireDate: fireDate,
                calendar: requestCalendar
            ),
            source: .scheduled,
            scheduledFireDate: fireDate,
            scheduledKind: kind,
            createdAt: now(),
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: profile?.target ?? schedule.target,
            settingsSnapshot: frozenSettings,
            sleepCaptureContext: frozenSettings?.sleepCaptureContext ?? captureContext,
            profileID: profile?.profileID,
            profileName: profile?.profileName,
            recoveryGeneration: profile?.recoveryGeneration ?? 0,
            scheduleEnabledAt: profile?.enabledAt ?? schedule.enabledAt,
            apiDestinationIdentity: profile?.apiDestinationIdentity ?? apiDestinationIdentity,
            calendar: requestCalendar
        )
    }

    private func frozenCalendar(for timeZoneIdentifier: String?) -> Calendar {
        guard let timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return calendar
        }
        var frozen = Calendar(identifier: .gregorian)
        frozen.timeZone = timeZone
        return frozen
    }
}
