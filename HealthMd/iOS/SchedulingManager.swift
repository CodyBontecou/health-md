import Foundation
import BackgroundTasks
import Combine
import UIKit
import UserNotifications
import WidgetKit
import os.log

/// Result of a notification-triggered export to display in the UI
struct NotificationExportResult: Equatable {
    enum Status: Equatable {
        case success(daysExported: Int)
        case partialSuccess(exported: Int, total: Int)
        case dailyNotesCompleted(updated: Int, skipped: Int)
        case failure(reason: String)
        case noExportNeeded
    }

    let status: Status
    let timestamp: Date

    var title: String {
        switch status {
        case .success:
            return String(localized: "Export Completed", comment: "Notification title for successful export")
        case .partialSuccess:
            return String(localized: "Partial Export", comment: "Notification title for partial export")
        case .dailyNotesCompleted:
            return String(localized: "Daily Notes Completed", comment: "Notification title for completed daily note updates with skips")
        case .failure:
            return String(localized: "Export Failed", comment: "Notification title for failed export")
        case .noExportNeeded:
            return String(localized: "Up to Date", comment: "Notification title when no export needed")
        }
    }

    var message: String {
        switch status {
        case .success(let days):
            return days == 1
                ? String(localized: "Successfully exported yesterday's health data", comment: "Export success message for 1 day")
                : String(localized: "Successfully exported \(days) days of health data", comment: "Export success message for multiple days")
        case .partialSuccess(let exported, let total):
            return String(localized: "Exported \(exported) of \(total) days", comment: "Partial export message")
        case .dailyNotesCompleted(let updated, let skipped):
            if updated == 0 {
                return String(localized: "Skipped \(skipped) missing daily note(s); no export files were created", comment: "Daily note only terminal skip message")
            }
            return String(localized: "Updated \(updated) and skipped \(skipped) daily note(s); no export files were created", comment: "Daily note only completed with skips message")
        case .failure(let reason):
            return reason
        case .noExportNeeded:
            return String(localized: "Your health data is already up to date", comment: "No export needed message")
        }
    }

    var isSuccess: Bool {
        switch status {
        case .success, .dailyNotesCompleted, .noExportNeeded:
            return true
        case .partialSuccess, .failure:
            return false
        }
    }
}

/// Manages background task scheduling for automated health data exports
class SchedulingManager: ObservableObject {
    enum PendingExportDrainTrigger {
        case notificationTap
        case appActive
    }

    typealias ScheduledPendingExportRunner = @MainActor ([Date]) async -> ExportOrchestrator.ExportResult
    typealias ScheduledTargetExportRunner = @MainActor ([Date], ExportTargetSelection) async -> ExportOrchestrator.ExportResult

    private struct ScheduledMacExportContext {
        let dateRangeStart: Date
        let dateRangeEnd: Date
        let requestedDates: [Date]
        let settings: AdvancedExportSettings
        let continuation: CheckedContinuation<ExportOrchestrator.ExportResult, Never>
    }

    @MainActor static let shared = SchedulingManager()

    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "SchedulingManager")

    /// Background task identifier - must match Info.plist entry
    static let backgroundTaskIdentifier = "com.codybontecou.healthmd.dataexport"

    /// Key for tracking last successful export date in UserDefaults
    private let lastExportDateKey = "lastSuccessfulExportDate"

    private let pendingExportStore: PendingExportStoring
    private let exportNotificationScheduler: ExportNotificationScheduling
    private let shortcutExportRunner: @MainActor ([Date]) async -> ExportIntentRunner.Outcome
    private let scheduledPendingExportRunner: ScheduledPendingExportRunner?
    private let scheduledTargetExportRunner: ScheduledTargetExportRunner?
    private let now: @MainActor () -> Date
    private let scheduledExportCoordinator: ScheduledExportCoordinator
    private let persistScheduleChanges: Bool
    private let systemSideEffectsEnabled: Bool
    private let scheduledMacExportTimeout: TimeInterval

    @MainActor private weak var scheduledSyncService: SyncService?
    @MainActor private weak var scheduledExternalIntegrations: ExternalIntegrationDailyRecordProviding?
    @MainActor private var scheduledMacExportContexts: [UUID: ScheduledMacExportContext] = [:]
    @MainActor private var scheduledMacExportTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    @MainActor private var scheduledMacExportTransferTasks: [UUID: Task<Void, Never>] = [:]
    @MainActor private var inFlightPendingExportIDs: Set<PendingExportRequest.ID> = []
    @MainActor private var inFlightScheduledOccurrenceKeys: Set<Date> = []

    /// Result from notification-triggered export, observed by UI to show alert
    @MainActor @Published var notificationExportResult: NotificationExportResult?

    @MainActor @Published var schedule: ExportSchedule {
        didSet {
            if persistScheduleChanges {
                schedule.save()
            }
            guard systemSideEffectsEnabled else { return }
            // Skip background task and HealthKit setup in UI test / marketing capture mode
            guard !TestMode.isUITesting else { return }
            #if DEBUG
            guard !MarketingCapture.isActive else { return }
            #endif
            Task {
                if schedule.isEnabled {
                    scheduleBackgroundTask()
                    await setupHealthKitBackgroundDelivery()
                    await PushRegistrationManager.shared.registerForRemoteNotificationsIfNeeded()
                } else {
                    cancelBackgroundTask()
                    await disableHealthKitBackgroundDelivery()
                }
            }
            // Mirror the schedule to the worker so server-side cron can
            // deliver silent push at the precise minute. Disabling sends
            // isEnabled:false so the worker drops the row.
            PushRegistrationManager.shared.syncSchedule(schedule)
        }
    }

    init(
        pendingExportStore: PendingExportStoring = PendingExportStore(),
        exportNotificationScheduler: ExportNotificationScheduling = UserNotificationExportScheduler(),
        initialSchedule: ExportSchedule = .load(),
        persistScheduleChanges: Bool = true,
        systemSideEffectsEnabled: Bool = true,
        shortcutExportRunner: @MainActor @escaping ([Date]) async -> ExportIntentRunner.Outcome = { dates in
            await ExportIntentRunner.run(dates: dates, source: .shortcut)
        },
        scheduledPendingExportRunner: ScheduledPendingExportRunner? = nil,
        scheduledTargetExportRunner: ScheduledTargetExportRunner? = nil,
        scheduledMacExportTimeout: TimeInterval = 120,
        now: @MainActor @escaping () -> Date = Date.init
    ) {
        self.pendingExportStore = pendingExportStore
        self.exportNotificationScheduler = exportNotificationScheduler
        self.shortcutExportRunner = shortcutExportRunner
        self.scheduledPendingExportRunner = scheduledPendingExportRunner
        self.scheduledTargetExportRunner = scheduledTargetExportRunner
        self.scheduledMacExportTimeout = scheduledMacExportTimeout
        self.persistScheduleChanges = persistScheduleChanges
        self.systemSideEffectsEnabled = systemSideEffectsEnabled
        self.now = now
        self.scheduledExportCoordinator = ScheduledExportCoordinator(
            pendingExportStore: pendingExportStore,
            exportNotificationScheduler: exportNotificationScheduler
        )
        self.schedule = initialSchedule
    }

    @MainActor func configureScheduledExportDependencies(
        syncService: SyncService,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) {
        self.scheduledSyncService = syncService
        self.scheduledExternalIntegrations = externalIntegrations
    }

    // MARK: - HealthKit Background Delivery Integration

    /// Sets up HealthKit background delivery when scheduling is enabled
    @MainActor private func setupHealthKitBackgroundDelivery() async {
        let healthKitManager = HealthKitManager.shared

        // Set up callback to handle background delivery
        healthKitManager.onBackgroundDelivery = { [weak self] in
            Task {
                await self?.handleHealthKitBackgroundDelivery()
            }
        }

        await healthKitManager.enableBackgroundDelivery()
        healthKitManager.setupObserverQueries()
        logger.info("HealthKit background delivery configured")
    }

    /// Disables HealthKit background delivery
    @MainActor private func disableHealthKitBackgroundDelivery() async {
        let healthKitManager = HealthKitManager.shared
        healthKitManager.onBackgroundDelivery = nil
        healthKitManager.stopObserverQueries()
        await healthKitManager.disableBackgroundDelivery()
        logger.info("HealthKit background delivery disabled")
    }

    /// Handles background delivery notifications from HealthKit
    @MainActor private func handleHealthKitBackgroundDelivery() async {
        logger.info("HealthKit background delivery received")
        WidgetCenter.shared.reloadAllTimelines()

        guard schedule.isEnabled else {
            logger.info("Schedule disabled, ignoring background delivery")
            return
        }

        let currentDate = now()
        guard let occurrence = ScheduleDateMath.dueScheduledOccurrences(
            schedule: schedule,
            now: currentDate
        ).first else {
            logger.info("HealthKit background delivery skipped: no scheduled occurrence is due")
            return
        }

        let fireDate = occurrence.fireDate
        let kind = occurrence.kind
        let calendar = Calendar.current

        if kind == .completedDay {
            let eligibleDates = ScheduleDateMath.scheduledExportDates(
                schedule: schedule,
                fireDate: fireDate,
                calendar: calendar
            )
            guard let eligibleEndDate = eligibleDates.last else {
                logger.info("HealthKit background delivery skipped: no eligible export dates")
                return
            }

            if let lastExport = schedule.lastExportDate {
                let lastExportDay = calendar.startOfDay(for: lastExport)
                let lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: lastExportDay) ?? lastExportDay
                if lastExportedDataDay >= eligibleEndDate {
                    logger.info("Scheduled occurrence already exported, skipping")
                    return
                }
            }
        }

        guard beginScheduledOccurrenceExport(fireDate: fireDate) else { return }
        defer { finishScheduledOccurrenceExport(fireDate: fireDate) }

        logger.info("Triggering export from HealthKit background delivery")
        let pendingRequest = await preparePendingScheduledExport(fireDate: fireDate, kind: kind)
        let range = pendingRequest.map(scheduledExportHistoryRange) ?? fallbackScheduledExportHistoryRange(kind: kind)
        let dates = pendingRequest?.dates ?? fallbackScheduledExportDates(kind: kind)
        let target = scheduledTarget(for: pendingRequest)
        cancelPendingExportFallbackNotification(for: pendingRequest)
        let result = await runScheduledExport(dates: dates, target: target)

        await processAutomaticScheduledExportResult(
            result,
            pendingRequest: pendingRequest,
            target: target,
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            fallbackDaysToExport: range.totalCount,
            scheduledFireDate: fireDate
        )
    }

    // MARK: - Background Task Registration

    /// Requests notification permissions
    @MainActor func requestNotificationPermissions() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            logger.info("Notification permission granted: \(granted)")
            return granted
        } catch {
            logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            return false
        }
    }

    /// Registers the background task handler - call this at app launch
    @MainActor func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }
            Task {
                // Handle as processing task for longer execution time
                await self.handleBackgroundTask(task as! BGProcessingTask)
            }
        }

        logger.info("Background task handler registered")
    }

    /// Schedules the next background task based on current schedule settings
    /// Uses BGProcessingTask for more reliable execution and longer runtime
    @MainActor func scheduleBackgroundTask(cancelPendingFallbacks: Bool = true) {
        // Cancel any existing tasks
        cancelBackgroundTask(cancelPendingFallbacks: cancelPendingFallbacks)

        guard schedule.isEnabled else {
            logger.info("Schedule disabled, not scheduling background task")
            return
        }

        // Use BGProcessingTask for longer runtime and better reliability
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)

        // Calculate next execution time
        let nextRunOccurrence = calculateNextRunOccurrence()
        let nextRunDate = nextRunOccurrence?.fireDate ?? now().addingTimeInterval(3600)
        request.earliestBeginDate = nextRunDate

        // Prefer running when connected to power for better reliability.
        // API Endpoint and Connected Mac scheduled targets need networking.
        request.requiresExternalPower = false  // Don't require, but prefer
        request.requiresNetworkConnectivity = schedule.target.requiresNetworkForScheduledExport

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background processing task scheduled for \(nextRunDate)")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }

        schedulePendingExportFallbackNotification(for: nextRunDate, kind: nextRunOccurrence?.kind ?? .completedDay)
    }

    /// Cancels all pending background tasks
    @MainActor func cancelBackgroundTask(cancelPendingFallbacks: Bool = true) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        if cancelPendingFallbacks {
            cancelScheduledPendingExportFallbackNotifications()
        }
        logger.info("Background task cancelled")
    }

    // MARK: - Catch-Up Logic

    /// Runs the exact persisted pending export request referenced by a recovery notification.
    @MainActor func performPendingExport(
        requestId: PendingExportRequest.ID,
        source expectedSource: PendingExportSource? = nil
    ) async {
        guard let request = loadPendingExportRequest(id: requestId, source: expectedSource) else {
            return
        }

        await runPendingExport(request, trigger: .notificationTap)
    }

    /// Drains persisted pending requests when the app becomes active.
    @MainActor func drainPendingExportsIfNeeded(trigger: PendingExportDrainTrigger = .appActive) async {
        let requests: [PendingExportRequest]
        do {
            requests = try pendingExportStore.loadAll().sorted(by: pendingExportSort)
        } catch {
            logger.error("Failed to load pending export requests: \(error.localizedDescription)")
            return
        }

        guard !requests.isEmpty else {
            logger.info("Pending export drain skipped: no pending requests")
            return
        }

        for request in requests {
            await runPendingExport(request, trigger: trigger)
        }
    }

    /// Runs an export when the user taps a "tap to retry" notification.
    /// Pending notifications carry exact requested dates and must not fall
    /// through to a recalculated scheduled-export lookback window.
    @MainActor func performNotificationTriggeredExport(payload: PendingExportNotificationPayload? = nil) async {
        guard let payload else {
            await performScheduledNotificationTriggeredExport()
            return
        }

        await performPendingExport(requestId: payload.requestID, source: payload.source)
    }

    @MainActor private func runPendingExport(
        _ request: PendingExportRequest,
        trigger: PendingExportDrainTrigger
    ) async {
        switch request.source {
        case .scheduled:
            await runPendingScheduledExport(request, trigger: trigger)
        case .shortcut:
            await runPendingShortcutExport(request, trigger: trigger)
        }
    }

    @MainActor private func runPendingShortcutExport(
        _ request: PendingExportRequest,
        trigger: PendingExportDrainTrigger
    ) async {
        guard beginPendingExport(request) else { return }
        defer { finishPendingExport(request) }

        guard isPendingExportRequestStillStored(request) else { return }

        let outcome = await shortcutExportRunner(request.dates)

        switch outcome {
        case .success(let daysExported, _, _):
            completePendingShortcutExportRequest(request)
            notificationExportResult = NotificationExportResult(
                status: .success(daysExported: daysExported),
                timestamp: now()
            )
        case .partial(let exported, let total, _, let dailyNotesUpdated, let dailyNotesSkipped, _):
            completePendingShortcutExportRequest(request)
            let status: NotificationExportResult.Status = if dailyNotesSkipped > 0,
                                                             exported + dailyNotesSkipped == total {
                .dailyNotesCompleted(updated: dailyNotesUpdated, skipped: dailyNotesSkipped)
            } else {
                .partialSuccess(exported: exported, total: total)
            }
            notificationExportResult = NotificationExportResult(
                status: status,
                timestamp: now()
            )
        case .pending:
            exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
            notificationExportResult = NotificationExportResult(
                status: .failure(reason: ExportIntentRunner.dialog(for: outcome)),
                timestamp: now()
            )
        case .noVault, .paywall, .failure:
            notificationExportResult = NotificationExportResult(
                status: .failure(reason: ExportIntentRunner.dialog(for: outcome)),
                timestamp: now()
            )
        }
    }

    @MainActor private func runPendingScheduledExport(
        _ request: PendingExportRequest,
        trigger: PendingExportDrainTrigger
    ) async {
        guard shouldAttemptPendingScheduledExport(request, trigger: trigger) else { return }
        guard beginScheduledOccurrenceExport(fireDate: request.scheduledFireDate) else { return }
        defer { finishScheduledOccurrenceExport(fireDate: request.scheduledFireDate) }
        guard beginPendingExport(request) else { return }
        defer { finishPendingExport(request) }

        guard isPendingExportRequestStillStored(request) else { return }

        logger.info("Draining pending scheduled export request \(request.id.uuidString)")
        let target = scheduledTarget(for: request)
        let result = await runScheduledExport(dates: request.dates, target: target)

        let completion = await completePendingScheduledExport(request, result: result)
        processPendingScheduledExportResult(
            result,
            request: request,
            target: target,
            completion: completion
        )
    }

    @MainActor private func shouldAttemptPendingScheduledExport(
        _ request: PendingExportRequest,
        trigger: PendingExportDrainTrigger
    ) -> Bool {
        guard schedule.isEnabled else {
            logger.info("Schedule disabled, skipping pending scheduled export request \(request.id.uuidString)")
            if trigger == .notificationTap {
                notificationExportResult = NotificationExportResult(
                    status: .failure(reason: String(localized: "Scheduling is disabled", comment: "Error message when scheduling is disabled")),
                    timestamp: now()
                )
            }
            return false
        }

        guard let fireDate = request.scheduledFireDate else {
            return true
        }

        let currentDate = now()
        if fireDate > currentDate {
            logger.info("Skipping future pending scheduled export request \(request.id.uuidString)")
            return false
        }

        if let enabledAt = schedule.enabledAt, fireDate <= enabledAt {
            logger.info("Discarding pending scheduled export request from before scheduling was enabled: \(request.id.uuidString)")
            discardPendingScheduledExportRequest(request)
            return false
        }

        return true
    }

    @MainActor private func discardPendingScheduledExportRequest(_ request: PendingExportRequest) {
        exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
        do {
            try pendingExportStore.remove(id: request.id)
        } catch {
            logger.error("Failed to remove stale pending scheduled export request: \(error.localizedDescription)")
        }
    }

    private func pendingExportSort(_ lhs: PendingExportRequest, _ rhs: PendingExportRequest) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    @MainActor private func loadPendingExportRequest(
        id: PendingExportRequest.ID,
        source expectedSource: PendingExportSource?
    ) -> PendingExportRequest? {
        do {
            guard let request = try pendingExportStore.loadAll().first(where: { $0.id == id }) else {
                logger.info("Pending export request not found: \(id.uuidString)")
                return nil
            }

            if let expectedSource, request.source != expectedSource {
                logger.warning(
                    "Pending export request source mismatch for \(id.uuidString): expected \(expectedSource.rawValue), found \(request.source.rawValue)"
                )
                return nil
            }

            return request
        } catch {
            logger.error("Failed to load pending export request: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor private func isPendingExportRequestStillStored(_ request: PendingExportRequest) -> Bool {
        loadPendingExportRequest(id: request.id, source: request.source) != nil
    }

    @MainActor private func beginPendingExport(_ request: PendingExportRequest) -> Bool {
        guard !inFlightPendingExportIDs.contains(request.id) else {
            logger.info("Pending export request already in flight, skipping duplicate run: \(request.id.uuidString)")
            return false
        }

        inFlightPendingExportIDs.insert(request.id)
        return true
    }

    @MainActor private func finishPendingExport(_ request: PendingExportRequest) {
        inFlightPendingExportIDs.remove(request.id)
    }

    @MainActor private func beginScheduledOccurrenceExport(fireDate: Date?) -> Bool {
        guard let fireDate else { return true }
        let key = scheduledOccurrenceKey(for: fireDate)
        guard !inFlightScheduledOccurrenceKeys.contains(key) else {
            logger.info("Scheduled export occurrence already in flight, skipping duplicate run: \(key)")
            return false
        }
        inFlightScheduledOccurrenceKeys.insert(key)
        return true
    }

    @MainActor private func finishScheduledOccurrenceExport(fireDate: Date?) {
        guard let fireDate else { return }
        inFlightScheduledOccurrenceKeys.remove(scheduledOccurrenceKey(for: fireDate))
    }

    @MainActor private func scheduledOccurrenceKey(for fireDate: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return calendar.date(from: components) ?? fireDate
    }

    @MainActor private func completePendingShortcutExportRequest(_ request: PendingExportRequest) {
        exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
        do {
            try pendingExportStore.remove(id: request.id)
        } catch {
            logger.error("Failed to remove completed pending export request: \(error.localizedDescription)")
        }
    }

    @MainActor private func processPendingScheduledExportResult(
        _ result: ExportOrchestrator.ExportResult,
        request: PendingExportRequest,
        target: ExportTargetSelection,
        completion: ScheduledExportCompletion?
    ) {
        let range = scheduledExportHistoryRange(for: request)
        let targetLabel = scheduledTargetLabel(for: target)
        let didCompleteRequest = completion == .clearedAfterSuccess
            || (completion == nil && result.didCompleteAllRequestedDates)

        if didCompleteRequest {
            var updatedSchedule = schedule
            switch request.scheduledKind {
            case .completedDay:
                updatedSchedule.updateLastExport(at: request.scheduledFireDate ?? now())
            case .todayRefresh:
                updatedSchedule.lastTodayRefreshDate = request.scheduledFireDate ?? now()
                updatedSchedule.save()
            }
            schedule = updatedSchedule
        }

        if result.successCount > 0 {
            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: range.start,
                dateRangeEnd: range.end,
                targetLabel: targetLabel,
                exportTarget: target
            )
        } else if result.totalCount > 0 {
            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: range.start,
                dateRangeEnd: range.end,
                targetLabel: targetLabel,
                exportTarget: target
            )
        }

        notificationExportResult = makeNotificationExportResult(from: result)
    }

    @MainActor private func makeNotificationExportResult(
        from result: ExportOrchestrator.ExportResult
    ) -> NotificationExportResult {
        if result.dailyNoteSkipCount > 0 && result.didCompleteAllRequestedDates {
            return NotificationExportResult(
                status: .dailyNotesCompleted(
                    updated: result.dailyNoteUpdateCount,
                    skipped: result.dailyNoteSkipCount
                ),
                timestamp: now()
            )
        }

        if result.successCount > 0 {
            return NotificationExportResult(
                status: result.isFullSuccess
                    ? .success(daysExported: result.successCount)
                    : .partialSuccess(exported: result.successCount, total: result.totalCount),
                timestamp: now()
            )
        }

        if result.totalCount > 0 {
            return NotificationExportResult(
                status: .failure(reason: result.primaryFailureReason?.shortDescription ?? "Unknown error"),
                timestamp: now()
            )
        }

        return NotificationExportResult(status: .noExportNeeded, timestamp: now())
    }

    @MainActor
    private func scheduledTarget(for request: PendingExportRequest?) -> ExportTargetSelection {
        request?.exportTarget ?? schedule.target
    }

    @MainActor
    private func scheduledTargetLabel(for target: ExportTargetSelection) -> String? {
        switch target {
        case .localIPhoneFolder:
            return nil
        case .apiEndpoint:
            return APIExportSettings().displayName
        case .connectedMac:
            return scheduledSyncService?.macDestinationStatus?.destinationDisplayName
                ?? scheduledSyncService?.connectedPeerName
                ?? ExportTargetSelection.connectedMac.title
        }
    }

    @MainActor
    private func runScheduledExport(
        dates: [Date],
        target: ExportTargetSelection
    ) async -> ExportOrchestrator.ExportResult {
        if let scheduledTargetExportRunner {
            return await scheduledTargetExportRunner(dates, target)
        }

        // Preserve older unit-test seams that only cared about dates.
        if let scheduledPendingExportRunner {
            return await scheduledPendingExportRunner(dates)
        }

        switch target {
        case .localIPhoneFolder:
            return await performBackgroundExport(dates: dates)
        case .apiEndpoint:
            return await performBackgroundAPIEndpointExport(dates: dates)
        case .connectedMac:
            return await performBackgroundConnectedMacExport(dates: dates)
        }
    }

    @MainActor
    private func performBackgroundAPIEndpointExport(dates: [Date]) async -> ExportOrchestrator.ExportResult {
        guard PurchaseManager.shared.isUnlocked else {
            logger.info("Scheduled API export skipped — app not unlocked")
            await sendUpgradeRequiredNotification()
            return ExportOrchestrator.ExportResult(successCount: 0, totalCount: 0, failedDateDetails: [])
        }

        let settings = AdvancedExportSettings()
        let apiSettings = APIExportSettings()
        guard let destination = apiSettings.destinationSnapshot else {
            return scheduledFailureResult(
                dates: dates,
                reason: .unknown,
                message: APIExportClientError.invalidEndpoint.localizedDescription
            )
        }
        let externalIntegrations: ExternalIntegrationDailyRecordProviding? = ConnectedAppsFeature.isEnabled
            ? scheduledExternalIntegrations
            : nil

        logger.info("Starting scheduled API Endpoint export")
        return await APIEndpointExportRunner.export(
            dates: dates,
            healthKitManager: HealthKitManager.shared,
            settings: settings,
            destination: destination,
            externalIntegrations: externalIntegrations
        )
    }

    @MainActor
    private func performBackgroundConnectedMacExport(dates: [Date]) async -> ExportOrchestrator.ExportResult {
        guard PurchaseManager.shared.isUnlocked else {
            logger.info("Scheduled Mac export skipped — app not unlocked")
            await sendUpgradeRequiredNotification()
            return ExportOrchestrator.ExportResult(successCount: 0, totalCount: 0, failedDateDetails: [])
        }

        let normalizedDates = dates.map { Calendar.current.startOfDay(for: $0) }.sorted()
        guard let startDate = normalizedDates.first,
              let endDate = normalizedDates.last else {
            return ExportOrchestrator.ExportResult(successCount: 0, totalCount: 0, failedDateDetails: [])
        }

        guard let syncService = scheduledSyncService else {
            return scheduledFailureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Open Health.md on iPhone before using scheduled Connected Mac exports."
            )
        }

        let settings = AdvancedExportSettings()
        guard syncService.canExportToConnectedMac(requiring: settings) else {
            return scheduledFailureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: syncService.macExportReadinessMessage(requiring: settings)
            )
        }

        guard syncService.remoteCapabilities?.supportsScheduledConnectedMacExports == true else {
            return scheduledFailureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Scheduled Connected Mac exports require an updated Mac with size-bounded streaming support."
            )
        }

        syncService.isSyncing = true
        let jobID = UUID()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
        if ConnectedAppsFeature.isEnabled,
           let scheduledExternalIntegrations,
           scheduledExternalIntegrations.connectedProviderCount > 0 {
            externalRecordFetcher = { date in
                await scheduledExternalIntegrations.fetchDailyRecords(for: date)
            }
        } else {
            externalRecordFetcher = nil
        }

        scheduledExternalIntegrations?.beginExportAction()
        defer { scheduledExternalIntegrations?.endExportAction() }
        do {
            if let remote = syncService.remoteCapabilities,
               let negotiation = SyncPeerCapabilities.current(platform: .iOS)
                    .negotiateConnectedCorpusTransfer(with: remote) {
                return await awaitScheduledCorpusExport(
                    jobID: jobID,
                    startDate: startDate,
                    endDate: endDate,
                    requestedDates: normalizedDates,
                    settings: settings,
                    negotiation: negotiation,
                    externalRecordFetcher: externalRecordFetcher,
                    syncService: syncService,
                    dateFormatter: dateFormatter
                )
            }

            let job = try await MacExportJobBuilder.build(
                jobID: jobID,
                sourceDeviceName: UIDevice.current.name,
                startDate: startDate,
                endDate: endDate,
                requestedDates: normalizedDates,
                settings: settings,
                healthSubfolder: VaultManager.savedHealthSubfolder(),
                destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                fetchHealthData: { date, includeGranularData in
                    try await HealthKitManager.shared.fetchHealthData(
                        for: date,
                        includeGranularData: includeGranularData,
                        metricSelection: settings.metricSelection
                    )
                },
                fetchExternalDailyRecords: externalRecordFetcher,
                onProgress: { processed, total, date in
                    syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                        jobID: jobID,
                        processedDays: processed,
                        totalDays: total,
                        currentDate: date,
                        message: "Preparing \(dateFormatter.string(from: date)) on iPhone…"
                    )))
                }
            )

            guard syncService.canExportToConnectedMac(requiring: settings) else {
                syncService.isSyncing = false
                return scheduledFailureResult(
                    dates: normalizedDates,
                    reason: .unknown,
                    message: syncService.macExportReadinessMessage(requiring: settings)
                )
            }

            return await awaitScheduledMacExport(job: job, settings: settings, syncService: syncService)
        } catch is CancellationError {
            syncService.isSyncing = false
            return scheduledFailureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Scheduled Mac export was cancelled."
            )
        } catch let error as HealthKitManager.HealthKitError {
            syncService.isSyncing = false
            return scheduledFailureResult(
                dates: normalizedDates,
                reason: scheduledFailureReason(for: error),
                message: scheduledMessage(for: error)
            )
        } catch {
            syncService.isSyncing = false
            return scheduledFailureResult(
                dates: normalizedDates,
                reason: .healthKitError,
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func awaitScheduledCorpusExport(
        jobID: UUID,
        startDate: Date,
        endDate: Date,
        requestedDates: [Date],
        settings: AdvancedExportSettings,
        negotiation: ConnectedCorpusTransferNegotiation,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        dateFormatter: DateFormatter
    ) async -> ExportOrchestrator.ExportResult {
        await withCheckedContinuation { continuation in
            scheduledMacExportContexts[jobID] = ScheduledMacExportContext(
                dateRangeStart: startDate,
                dateRangeEnd: endDate,
                requestedDates: requestedDates,
                settings: settings,
                continuation: continuation
            )
            resetScheduledMacExportTimeout(jobID: jobID)
            scheduledMacExportTransferTasks[jobID] = Task { @MainActor [weak self, weak syncService] in
                guard let self, let syncService else { return }
                do {
                    _ = try await IPhoneConnectedCorpusProducer.sendFileExport(
                        jobID: jobID,
                        startDate: startDate,
                        endDate: endDate,
                        requestedDates: requestedDates,
                        settings: settings,
                        healthSubfolder: VaultManager.savedHealthSubfolder(),
                        destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                        negotiation: negotiation,
                        healthKitManager: HealthKitManager.shared,
                        externalRecordFetcher: externalRecordFetcher,
                        syncService: syncService,
                        origin: .scheduledIPhone,
                        progress: { processed, total, date, _ in
                            self.resetScheduledMacExportTimeout(jobID: jobID)
                            syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                                jobID: jobID,
                                processedDays: processed,
                                totalDays: total,
                                currentDate: date,
                                message: "Preparing \(dateFormatter.string(from: date)) on iPhone…"
                            )))
                        }
                    )
                } catch is CancellationError {
                    // The result/timeout path owns continuation completion.
                } catch let error as ConnectedCorpusDurableSender.DurableSenderError {
                    if case .paused = error {
                        // Durable v2 jobs remain journaled and resume after the
                        // same Mac reconnects or the iPhone app relaunches.
                        return
                    }
                    _ = self.completeScheduledMacExport(with: MacExportFailure(
                        jobID: jobID,
                        reason: .payloadDecodeFailure,
                        message: "Durable scheduled Mac export failed.",
                        underlyingError: error.localizedDescription
                    ))
                } catch {
                    _ = self.completeScheduledMacExport(with: MacExportFailure(
                        jobID: jobID,
                        reason: .payloadDecodeFailure,
                        message: "Partitioned scheduled Mac export failed.",
                        underlyingError: error.localizedDescription
                    ))
                }
            }
        }
    }

    @MainActor
    private func awaitScheduledMacExport(
        job: MacExportJob,
        settings: AdvancedExportSettings,
        syncService: SyncService
    ) async -> ExportOrchestrator.ExportResult {
        await withCheckedContinuation { continuation in
            scheduledMacExportContexts[job.jobID] = ScheduledMacExportContext(
                dateRangeStart: job.dateRangeStart,
                dateRangeEnd: job.dateRangeEnd,
                requestedDates: job.requestedDates
                    ?? ExportOrchestrator.dateRange(from: job.dateRangeStart, to: job.dateRangeEnd),
                settings: settings,
                continuation: continuation
            )
            resetScheduledMacExportTimeout(jobID: job.jobID)

            scheduledMacExportTransferTasks[job.jobID] = Task { @MainActor [weak self, weak syncService] in
                guard let self, let syncService else { return }
                do {
                    let preparedFile = try ConnectedTransferFile.encode(job)
                    defer { preparedFile.remove() }
                    guard self.scheduledMacExportContexts[job.jobID] != nil else { return }
                    let transferResult = await syncService.sendConnectedTransfer(
                        preparedFile,
                        manifest: ConnectedTransferManifest(
                            kind: .macExportJobV1,
                            jobID: job.jobID,
                            payloadSchemaVersion: 1
                        ),
                        onValidatedProgress: { [weak self] _, _ in
                            self?.resetScheduledMacExportTimeout(jobID: job.jobID)
                        }
                    )
                    if case .failure(let abort) = transferResult {
                        _ = self.handleScheduledConnectedTransferAbort(abort)
                    }
                } catch {
                    _ = self.completeScheduledMacExport(with: MacExportFailure(
                        jobID: job.jobID,
                        reason: .payloadDecodeFailure,
                        message: "Could not encode the scheduled Mac export for streaming.",
                        underlyingError: error.localizedDescription
                    ))
                }
            }
        }
    }

    @MainActor func handleScheduledMacExportProgress(_ progress: MacExportProgress) {
        guard scheduledMacExportContexts[progress.jobID] != nil else { return }
        resetScheduledMacExportTimeout(jobID: progress.jobID)
    }

    @discardableResult
    @MainActor func handleScheduledConnectedTransferAbort(_ abort: ConnectedTransferAbort) -> Bool {
        guard let jobID = abort.jobID,
              scheduledMacExportContexts[jobID] != nil else { return false }
        return completeScheduledMacExport(with: MacExportFailure(
            jobID: jobID,
            reason: abort.reason == .cancelled ? .cancelled : .payloadDecodeFailure,
            message: abort.message
        ))
    }

    @discardableResult
    @MainActor func completeScheduledMacExport(with payload: MacExportResultPayload) -> Bool {
        guard let context = scheduledMacExportContexts.removeValue(forKey: payload.jobID) else {
            return false
        }
        scheduledMacExportTimeoutTasks.removeValue(forKey: payload.jobID)?.cancel()
        scheduledMacExportTransferTasks.removeValue(forKey: payload.jobID)?.cancel()
        scheduledSyncService?.isSyncing = false
        guard isValidScheduledMacExportResult(payload, requestedDates: context.requestedDates) else {
            context.continuation.resume(returning: scheduledFailureResult(
                dates: context.requestedDates,
                reason: .unknown,
                message: "The Mac returned inconsistent completion dates or counters."
            ))
            return true
        }
        context.continuation.resume(returning: scheduledMacExportResult(from: payload, settings: context.settings))
        return true
    }

    @discardableResult
    @MainActor func completeScheduledMacExport(with failure: MacExportFailure) -> Bool {
        guard let jobID = failure.jobID,
              let context = scheduledMacExportContexts.removeValue(forKey: jobID) else {
            return false
        }
        scheduledMacExportTimeoutTasks.removeValue(forKey: jobID)?.cancel()
        scheduledMacExportTransferTasks.removeValue(forKey: jobID)?.cancel()
        scheduledSyncService?.isSyncing = false
        context.continuation.resume(returning: scheduledMacFailureResult(
            failure,
            dateRangeStart: context.dateRangeStart,
            dateRangeEnd: context.dateRangeEnd,
            settings: context.settings
        ))
        return true
    }

    @MainActor private func resetScheduledMacExportTimeout(jobID: UUID) {
        guard scheduledMacExportContexts[jobID] != nil else { return }
        scheduledMacExportTimeoutTasks.removeValue(forKey: jobID)?.cancel()
        guard scheduledMacExportTimeout > 0 else { return }
        let timeout = scheduledMacExportTimeout
        scheduledMacExportTimeoutTasks[jobID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.completeScheduledMacExportTimedOut(jobID: jobID)
        }
    }

    @MainActor private func completeScheduledMacExportTimedOut(jobID: UUID) {
        guard scheduledMacExportContexts[jobID] != nil else { return }
        scheduledMacExportTimeoutTasks.removeValue(forKey: jobID)?.cancel()
        if let journal = IPhoneCorpusExportRecoveryManager.shared.journal(jobID: jobID),
           !journal.state.isTerminal,
           let context = scheduledMacExportContexts.removeValue(forKey: jobID) {
            // A scheduler deadline ends this invocation's wait, not the durable
            // export. Removing a Task handle does not cancel its producer.
            _ = scheduledMacExportTransferTasks.removeValue(forKey: jobID)
            scheduledSyncService?.isSyncing = false
            context.continuation.resume(returning: scheduledFailureResult(
                dates: context.requestedDates,
                reason: .unknown,
                message: "Scheduled export paused and will resume when the same Mac reconnects."
            ))
            return
        }
        // Cancelling the producer makes it send the stable corpus-session cancel.
        // Keep the context briefly so the Mac's exact durable-date cancellation
        // result can win over a conservative whole-range timeout result.
        scheduledMacExportTransferTasks.removeValue(forKey: jobID)?.cancel()
        scheduledSyncService?.isSyncing = false
        let cancellationGrace = min(20, max(scheduledMacExportTimeout, 0.05))
        scheduledMacExportTimeoutTasks[jobID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(cancellationGrace * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completeScheduledMacExportTimeoutGraceExpired(jobID: jobID)
            }
        }
    }

    @MainActor private func completeScheduledMacExportTimeoutGraceExpired(jobID: UUID) {
        guard let context = scheduledMacExportContexts.removeValue(forKey: jobID) else { return }
        scheduledMacExportTimeoutTasks.removeValue(forKey: jobID)?.cancel()
        scheduledSyncService?.isSyncing = false
        context.continuation.resume(returning: scheduledFailureResult(
            dates: context.requestedDates,
            reason: .unknown,
            message: "Timed out waiting for the Mac to finish the scheduled export."
        ))
    }

    private func isValidScheduledMacExportResult(
        _ payload: MacExportResultPayload,
        requestedDates: [Date]
    ) -> Bool {
        guard payload.totalCount == requestedDates.count,
              payload.successCount >= 0,
              payload.successCount <= payload.totalCount,
              payload.formatsPerDate >= 0,
              payload.totalFilesWritten >= 0,
              payload.externalRecordFileCount >= 0,
              payload.dailyNoteUpdateCount >= 0,
              payload.dailyNoteUpdateCount <= payload.totalCount,
              payload.dailyNoteSkipCount >= 0,
              payload.dailyNoteSkipCount <= payload.totalCount,
              payload.dailyNoteUpdateCount + payload.dailyNoteSkipCount <= payload.totalCount,
              let completedDates = payload.completedDates,
              Set(completedDates).count == completedDates.count else {
            return false
        }
        let requested = Set(requestedDates)
        guard completedDates.allSatisfy(requested.contains),
              payload.dailyNoteUpdateCount + payload.dailyNoteSkipCount <= completedDates.count else {
            return false
        }
        if payload.status == .success && completedDates.count != requested.count {
            return false
        }
        return true
    }

    private func scheduledMacExportResult(
        from payload: MacExportResultPayload,
        settings: AdvancedExportSettings
    ) -> ExportOrchestrator.ExportResult {
        let externalRecordFileCount = payload.externalRecordFileCount
        let derivedFileCount = max(payload.totalFilesWritten - (payload.successCount * payload.formatsPerDate) - externalRecordFileCount, 0)
        let archiveCount = settings.archiveModeEnabled && payload.successCount > 0
            ? min(derivedFileCount, 1)
            : 0
        let rollupFileCount = max(derivedFileCount - archiveCount, 0)

        return ExportOrchestrator.ExportResult(
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            failedDateDetails: payload.failedDateDetails,
            formatsPerDate: payload.formatsPerDate,
            rollupFileCount: rollupFileCount,
            archiveCount: archiveCount,
            externalRecordFileCount: externalRecordFileCount,
            dailyNoteUpdateCount: payload.dailyNoteUpdateCount,
            dailyNoteSkipCount: payload.dailyNoteSkipCount,
            wasCancelled: payload.status == .cancelled,
            completedDates: payload.completedDates
        )
    }

    private func scheduledMacFailureResult(
        _ failure: MacExportFailure,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        settings: AdvancedExportSettings
    ) -> ExportOrchestrator.ExportResult {
        let dates = ExportOrchestrator.dateRange(from: dateRangeStart, to: dateRangeEnd)
        let fallbackDates = dates.isEmpty ? [dateRangeStart] : dates
        let reason = scheduledFailureReason(for: failure.reason)
        return ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: max(fallbackDates.count, 1),
            failedDateDetails: fallbackDates.map {
                FailedDateDetail(
                    date: $0,
                    reason: reason,
                    errorDetails: failure.underlyingError ?? failure.message
                )
            },
            formatsPerDate: settings.looseFormatsPerDate,
            wasCancelled: failure.reason == .cancelled
        )
    }

    private func scheduledFailureResult(
        dates: [Date],
        reason: ExportFailureReason,
        message: String,
        formatsPerDate: Int = 0
    ) -> ExportOrchestrator.ExportResult {
        let failedDates = dates.isEmpty ? [Date()] : dates
        return ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: dates.count,
            failedDateDetails: failedDates.map {
                FailedDateDetail(date: $0, reason: reason, errorDetails: message)
            },
            formatsPerDate: formatsPerDate
        )
    }

    private func scheduledFailureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized, .dataNotAvailable, .medicationAuthorizationUnsupported,
             .visionAuthorizationUnsupported:
            return .healthKitError
        }
    }

    private func scheduledMessage(for error: HealthKitManager.HealthKitError) -> String {
        switch error {
        case .dataProtectedWhileLocked:
            return "Health data is protected while the iPhone is locked. Unlock iPhone and try again."
        case .notAuthorized:
            return "HealthKit access has not been granted on iPhone."
        case .dataNotAvailable:
            return "HealthKit data is not available on this device."
        case .medicationAuthorizationUnsupported:
            return "Medication authorization is not supported on this device."
        case .visionAuthorizationUnsupported:
            return "Vision prescription authorization is not supported on this device."
        }
    }

    private func scheduledFailureReason(for reason: MacExportFailureReason) -> ExportFailureReason {
        switch reason {
        case .noMacFolderSelected:
            return .noVaultSelected
        case .macFolderAccessDenied:
            return .accessDenied
        case .noHealthRecordsReceived:
            return .noHealthData
        case .noFormatsSelected, .payloadDecodeFailure, .exportWriteFailure:
            return .fileWriteError
        case .incompatibleProtocol, .macBusy, .cancelled:
            return .unknown
        }
    }

    /// Unlike `performCatchUpExportIfNeeded`, this always runs the full
    /// scheduled export window (yesterday for daily, last 7 days for weekly)
    /// rather than short-circuiting on `lastExportDate` — the user explicitly
    /// asked for an export, so honor that intent.
    @MainActor private func performScheduledNotificationTriggeredExport(pendingRequestID: PendingExportRequest.ID? = nil) async {
        guard schedule.isEnabled else {
            logger.info("Schedule disabled, skipping notification-triggered export")
            notificationExportResult = NotificationExportResult(
                status: .failure(reason: String(localized: "Scheduling is disabled", comment: "Error message when scheduling is disabled")),
                timestamp: now()
            )
            return
        }

        let calendar = Calendar.current
        let currentDate = now()
        let pendingRequest = loadPendingScheduledExportRequest(id: pendingRequestID)
        let dates = pendingRequest?.dates ?? ScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: currentDate,
            calendar: calendar
        )
        let fallbackDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        )
        let startDate = dates.first ?? fallbackDate
        let endDate = dates.last ?? fallbackDate
        let target = scheduledTarget(for: pendingRequest)
        let targetLabel = scheduledTargetLabel(for: target)

        cancelPendingExportFallbackNotification(for: pendingRequest)
        let result = await runScheduledExport(dates: dates, target: target)
        let completion = await completePendingScheduledExport(pendingRequest, result: result)
        let didCompleteRequest = completion == .clearedAfterSuccess
            || (pendingRequest == nil && result.didCompleteAllRequestedDates)

        if didCompleteRequest {
            var updatedSchedule = schedule
            updatedSchedule.updateLastExport(at: pendingRequest?.scheduledFireDate ?? currentDate)
            schedule = updatedSchedule
        }

        if result.totalCount > 0 {
            ExportOrchestrator.recordResult(
                result, source: .scheduled,
                dateRangeStart: startDate, dateRangeEnd: endDate,
                targetLabel: targetLabel,
                exportTarget: target
            )
            notificationExportResult = makeNotificationExportResult(from: result)
        } else {
            // runScheduledExport returns totalCount=0 for the unlock-gate
            // path, where the user can't actually export, so surface that as
            // "nothing to do" in the in-app alert.
            notificationExportResult = NotificationExportResult(
                status: .noExportNeeded, timestamp: now()
            )
        }
    }

    /// Runs a scheduled export and posts a user-visible UNNotification with
    /// the result. Used by the server-driven silent-push handler, which
    /// fires while the app is backgrounded — the in-app `notificationExportResult`
    /// alert is invisible at that moment, so we mirror the BG-task path's
    /// notification posting behavior here instead.
    @MainActor func performSilentPushExport(fireDate: Date? = nil, kind: ScheduledExportKind = .completedDay) async {
        guard schedule.isEnabled else {
            logger.info("Silent push received but schedule is disabled")
            return
        }
        if schedule.frequency == .custom, kind == .completedDay, fireDate == nil {
            logger.info("Custom schedule push skipped: missing fire date")
            return
        }

        let currentDate = now()
        guard let resolvedFireDate = fireDate
            ?? ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, kind: kind, now: currentDate)
        else {
            logger.info("Silent push skipped: no scheduled occurrence")
            return
        }

        guard ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            kind: kind,
            fireDate: resolvedFireDate,
            now: currentDate
        ) else {
            logger.info("Silent push skipped: scheduled occurrence is not due")
            return
        }

        guard beginScheduledOccurrenceExport(fireDate: resolvedFireDate) else { return }
        defer { finishScheduledOccurrenceExport(fireDate: resolvedFireDate) }

        let pendingRequest = await preparePendingScheduledExport(fireDate: resolvedFireDate, kind: kind)
        let range = pendingRequest.map(scheduledExportHistoryRange) ?? fallbackScheduledExportHistoryRange(kind: kind)
        let dates = pendingRequest?.dates ?? fallbackScheduledExportDates(kind: kind)
        let target = scheduledTarget(for: pendingRequest)
        cancelPendingExportFallbackNotification(for: pendingRequest)
        let result = await runScheduledExport(dates: dates, target: target)

        await processAutomaticScheduledExportResult(
            result,
            pendingRequest: pendingRequest,
            target: target,
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            fallbackDaysToExport: range.totalCount,
            scheduledFireDate: resolvedFireDate
        )
    }

    /// Checks for and exports any missed days since last export
    /// Call this when the app becomes active
    @MainActor func performCatchUpExportIfNeeded() async {
        guard schedule.isEnabled else {
            logger.info("Schedule disabled, skipping catch-up")
            return
        }
        _ = await performCatchUpExportInternal()
    }

    /// Internal method that performs catch-up export and returns result for UI display
    @MainActor private func performCatchUpExportInternal() async -> NotificationExportResult {
        // Scheduled exports are a paid feature — require unlock.
        guard PurchaseManager.shared.isUnlocked else {
            logger.info("Scheduled export skipped — app not unlocked")
            await sendUpgradeRequiredNotification()
            return NotificationExportResult(status: .noExportNeeded, timestamp: Date())
        }

        let currentDate = now()
        guard let fireDate = ScheduleDateMath.latestScheduledOccurrenceDate(
            schedule: schedule,
            now: currentDate
        ) else {
            logger.info("Catch-up skipped: no scheduled occurrence")
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }

        guard ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: fireDate,
            now: currentDate
        ) else {
            logger.info("Catch-up skipped: scheduled occurrence is not due")
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }

        do {
            let alreadyPending = try pendingExportStore.loadAll().contains { request in
                request.source == .scheduled
                    && request.scheduledFireDate == fireDate
                    && request.scheduledKind == .completedDay
            }
            if alreadyPending {
                logger.info("Catch-up skipped: unresolved dates for this occurrence are already pending")
                return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
            }
        } catch {
            logger.error("Catch-up could not inspect pending work: \(error.localizedDescription)")
            return NotificationExportResult(
                status: .failure(reason: "Could not inspect pending scheduled exports"),
                timestamp: currentDate
            )
        }

        guard beginScheduledOccurrenceExport(fireDate: fireDate) else {
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }
        defer { finishScheduledOccurrenceExport(fireDate: fireDate) }

        let calendar = Calendar.current
        let eligibleDates = ScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: fireDate,
            calendar: calendar
        )
        guard let oldestDateToExport = eligibleDates.first,
              let newestDateToExport = eligibleDates.last else {
            logger.info("Catch-up check: No eligible export dates")
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }

        // Check what dates are missing. lastExportDate is when the export RAN,
        // but exports are for the previous day's data.
        let lastExportedDataDay: Date
        if let lastExport = schedule.lastExportDate {
            let exportRunDay = calendar.startOfDay(for: lastExport)
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: exportRunDay)!
        } else {
            // Never exported, start from the beginning of the current eligible window.
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: oldestDateToExport)!
        }

        if lastExportedDataDay >= newestDateToExport {
            logger.info("Catch-up check: No missed exports")
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }

        // Calculate missed dates within the current eligible scheduled window.
        var missedDates: [Date] = []
        let dayAfterLastExport = calendar.date(byAdding: .day, value: 1, to: lastExportedDataDay)!
        var checkDate = max(dayAfterLastExport, oldestDateToExport)

        while checkDate <= newestDateToExport {
            missedDates.append(checkDate)
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
        }

        guard !missedDates.isEmpty else {
            logger.info("Catch-up check: No dates to export")
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }

        logger.info("Catch-up: Found \(missedDates.count) missed date(s) to export")

        // Persist the exact catch-up range before writing. A partial result is
        // reconciled to residual dates by ScheduledExportCoordinator, so a
        // later app-active drain cannot append successful local days again.
        let target = schedule.target
        let pendingRequest = PendingExportRequest(
            dates: missedDates,
            source: .scheduled,
            scheduledFireDate: fireDate,
            scheduledKind: .completedDay,
            createdAt: currentDate,
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: target,
            calendar: calendar
        )
        do {
            try pendingExportStore.upsert(pendingRequest)
        } catch {
            logger.error("Catch-up could not persist pending work: \(error.localizedDescription)")
            return NotificationExportResult(
                status: .failure(reason: "Could not save pending scheduled export"),
                timestamp: currentDate
            )
        }

        let result = await runScheduledExport(dates: pendingRequest.dates, target: target)
        let completion = await completePendingScheduledExport(pendingRequest, result: result)
        processPendingScheduledExportResult(
            result,
            request: pendingRequest,
            target: target,
            completion: completion
        )
        logger.info("Catch-up export completed: \(result.successCount)/\(result.totalCount) days")
        return makeNotificationExportResult(from: result)
    }

    /// Performs export for specific missed dates using shared ExportOrchestrator
    private func performCatchUpExport(for dates: [Date]) async -> ExportOrchestrator.ExportResult {
        let healthKitManager = HealthKitManager.shared
        let vaultManager = VaultManager()
        let advancedSettings = AdvancedExportSettings()

        vaultManager.refreshVaultAccess()
        guard vaultManager.hasVaultAccess else {
            let reason: ExportFailureReason = vaultManager.hasSavedVaultFolder ? .accessDenied : .noVaultSelected
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: reason) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }

        guard vaultManager.startVaultAccess() else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .accessDenied) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }

        let result = await ExportOrchestrator.exportDatesBackground(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: advancedSettings
        )

        vaultManager.stopVaultAccess()
        return result
    }

    // MARK: - Background Task Execution

    /// Handles background task execution
    @MainActor private func handleBackgroundTask(_ task: BGProcessingTask) async {
        logger.info("Background processing task started")

        let currentDate = now()
        guard let occurrence = ScheduleDateMath.dueScheduledOccurrences(
            schedule: schedule,
            now: currentDate
        ).first else {
            logger.info("Background task skipped: no scheduled occurrence is due")
            scheduleBackgroundTask()
            task.setTaskCompleted(success: true)
            return
        }

        let fireDate = occurrence.fireDate
        let kind = occurrence.kind

        guard beginScheduledOccurrenceExport(fireDate: fireDate) else {
            task.setTaskCompleted(success: true)
            return
        }
        defer { finishScheduledOccurrenceExport(fireDate: fireDate) }

        let pendingRequest = await preparePendingScheduledExport(fireDate: fireDate, kind: kind)
        let range = pendingRequest.map(scheduledExportHistoryRange) ?? fallbackScheduledExportHistoryRange(kind: kind)
        let dates = pendingRequest?.dates ?? fallbackScheduledExportDates(kind: kind)
        let target = scheduledTarget(for: pendingRequest)
        cancelPendingExportFallbackNotification(for: pendingRequest)

        // Schedule the next task without clearing the pending occurrence this
        // task is about to fulfill.
        scheduleBackgroundTask(cancelPendingFallbacks: false)

        // Set expiration handler
        task.expirationHandler = {
            self.logger.warning("Background task expired")
            Task {
                await self.sendExportNotification(success: false, daysExported: 0, failureReason: .backgroundTaskExpired)
                // Record task expiration in history
                ExportHistoryManager.shared.recordFailure(
                    source: .scheduled,
                    dateRangeStart: range.start,
                    dateRangeEnd: range.end,
                    reason: .backgroundTaskExpired,
                    totalCount: range.totalCount,
                    exportTarget: target
                )
            }
        }

        // Perform the export
        let result = await runScheduledExport(dates: dates, target: target)
        task.setTaskCompleted(success: result.didCompleteAllRequestedDates)

        await processAutomaticScheduledExportResult(
            result,
            pendingRequest: pendingRequest,
            target: target,
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            fallbackDaysToExport: range.totalCount,
            scheduledFireDate: fireDate
        )
    }

    /// Performs the actual health data export in the background using shared ExportOrchestrator
    private func performBackgroundExport(dates: [Date]) async -> ExportOrchestrator.ExportResult {
        // Scheduled exports are a paid feature — require unlock.
        let isUnlocked = await MainActor.run { PurchaseManager.shared.isUnlocked }
        guard isUnlocked else {
            logger.info("Background export skipped — app not unlocked")
            await sendUpgradeRequiredNotification()
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: []
            )
        }

        logger.info("Starting background export")

        guard !dates.isEmpty else {
            logger.info("No scheduled export dates to export")
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: []
            )
        }

        // Get the required managers
        let healthKitManager = await MainActor.run { HealthKitManager.shared }
        let vaultManager = VaultManager()
        let advancedSettings = AdvancedExportSettings()

        // Check if vault is configured and currently accessible.
        vaultManager.refreshVaultAccess()
        guard vaultManager.hasVaultAccess else {
            logger.error("No vault access in background")
            let reason: ExportFailureReason = vaultManager.hasSavedVaultFolder ? .accessDenied : .noVaultSelected
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: reason) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }

        logger.info("Vault access confirmed: \(vaultManager.vaultURL?.path ?? "unknown")")

        logger.info("Exporting \(dates.count) days of data")

        guard vaultManager.startVaultAccess() else {
            logger.error("Could not start vault security scope in background")
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .accessDenied) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }

        let result = await ExportOrchestrator.exportDatesBackground(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: advancedSettings
        )

        vaultManager.stopVaultAccess()

        logger.info("Background export completed. Success: \(result.successCount)/\(result.totalCount)")
        return result
    }

    @MainActor
    private func preparePendingScheduledExport(
        fireDate: Date? = nil,
        kind: ScheduledExportKind = .completedDay
    ) async -> PendingExportRequest? {
        let resolvedFireDate = fireDate
            ?? ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, kind: kind, now: now())
            ?? now()

        do {
            return try await scheduledExportCoordinator.preparePendingScheduledExport(
                schedule: schedule,
                fireDate: resolvedFireDate,
                kind: kind
            )
        } catch {
            logger.error("Failed to prepare pending scheduled export: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func loadPendingScheduledExportRequest(id: PendingExportRequest.ID?) -> PendingExportRequest? {
        guard let id else { return nil }

        do {
            return try pendingExportStore.loadAll().first { request in
                request.id == id && request.source == .scheduled
            }
        } catch {
            logger.error("Failed to load pending scheduled export request: \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func cancelPendingExportFallbackNotification(for request: PendingExportRequest?) {
        guard let request else { return }
        exportNotificationScheduler.cancelPendingExportNotification(id: request.id)
    }

    @MainActor
    private func completePendingScheduledExport(
        _ request: PendingExportRequest?,
        result: ExportOrchestrator.ExportResult
    ) async -> ScheduledExportCompletion? {
        guard let request else {
            if result.primaryFailureReason == .deviceLocked {
                await sendExportReminderNotification()
            }
            return nil
        }

        do {
            return try await scheduledExportCoordinator.completePendingScheduledExport(
                request,
                result: result
            )
        } catch {
            logger.error("Failed to complete pending scheduled export: \(error.localizedDescription)")
            if result.primaryFailureReason == .deviceLocked {
                await sendExportReminderNotification()
            }
            return nil
        }
    }

    @MainActor
    private func scheduledExportHistoryRange(for request: PendingExportRequest) -> (start: Date, end: Date, totalCount: Int) {
        if let first = request.dates.first, let last = request.dates.last {
            return (first, last, request.dates.count)
        }

        let calendar = Calendar.current
        let fireDate = request.scheduledFireDate ?? Date()
        let dates = ScheduleDateMath.exportDates(
            for: request.scheduledKind,
            schedule: schedule,
            fireDate: fireDate,
            calendar: calendar
        )

        if let first = dates.first, let last = dates.last {
            return (first, last, dates.count)
        }

        let fallback = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: fireDate) ?? fireDate)
        return (fallback, fallback, 0)
    }

    @MainActor
    private func fallbackScheduledExportDates(kind: ScheduledExportKind = .completedDay) -> [Date] {
        let fireDate = ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, kind: kind, now: now()) ?? now()
        return ScheduleDateMath.exportDates(
            for: kind,
            schedule: schedule,
            fireDate: fireDate
        )
    }

    @MainActor
    private func fallbackScheduledExportHistoryRange(kind: ScheduledExportKind = .completedDay) -> (start: Date, end: Date, totalCount: Int) {
        let fireDate = ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, kind: kind, now: now()) ?? now()
        let dates = ScheduleDateMath.exportDates(
            for: kind,
            schedule: schedule,
            fireDate: fireDate
        )
        if let first = dates.first, let last = dates.last { return (first, last, dates.count) }
        let fallback = Calendar.current.startOfDay(for: fireDate)
        return (fallback, fallback, 0)
    }

    @MainActor
    private func processAutomaticScheduledExportResult(
        _ result: ExportOrchestrator.ExportResult,
        pendingRequest: PendingExportRequest?,
        target: ExportTargetSelection,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        fallbackDaysToExport: Int,
        scheduledFireDate: Date
    ) async {
        let completion = await completePendingScheduledExport(pendingRequest, result: result)
        let targetLabel = scheduledTargetLabel(for: target)
        let hasActionablePendingNotification = completion == .preservedPartialSuccess
            || completion == .preservedDeviceLocked
        let didCompleteRequest = completion == .clearedAfterSuccess
            || (pendingRequest == nil && result.didCompleteAllRequestedDates)

        if didCompleteRequest {
            var updatedSchedule = schedule
            switch pendingRequest?.scheduledKind ?? .completedDay {
            case .completedDay:
                updatedSchedule.updateLastExport(at: pendingRequest?.scheduledFireDate ?? scheduledFireDate)
            case .todayRefresh:
                updatedSchedule.lastTodayRefreshDate = pendingRequest?.scheduledFireDate ?? now()
                updatedSchedule.save()
            }
            schedule = updatedSchedule
        }

        if result.successCount > 0 || result.dailyNoteSkipCount > 0 {
            if didCompleteRequest {
                logger.info("Scheduled export completed successfully")
                await sendExportNotification(
                    success: true,
                    daysExported: result.successCount,
                    dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                    dailyNoteSkipCount: result.dailyNoteSkipCount
                )
            } else {
                // ScheduledExportCoordinator has posted a stable-ID pending
                // notification whose payload retries only unresolved dates.
                logger.info("Scheduled export partially completed; pending dates preserved for retry")
                if !hasActionablePendingNotification {
                    await sendExportNotification(
                        success: false,
                        daysExported: max(result.totalCount, fallbackDaysToExport),
                        failureReason: result.primaryFailureReason,
                        errorDetails: result.failedDateDetails.first?.errorDetails
                    )
                }
            }

            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                targetLabel: targetLabel,
                exportTarget: target
            )
        } else if result.totalCount > 0 {
            logger.error("Scheduled export failed")

            let failureReason = result.primaryFailureReason
            if failureReason != .deviceLocked && !hasActionablePendingNotification {
                await sendExportNotification(
                    success: false,
                    daysExported: max(result.totalCount, fallbackDaysToExport),
                    failureReason: failureReason,
                    errorDetails: result.failedDateDetails.first?.errorDetails
                )
            }

            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                targetLabel: targetLabel,
                exportTarget: target
            )
        }
    }

    // MARK: - Notifications

    /// Sends a notification after a scheduled export completes
    private func sendExportNotification(
        success: Bool,
        daysExported: Int,
        failureReason: ExportFailureReason? = nil,
        errorDetails: String? = nil,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0
    ) async {
        let content = UNMutableNotificationContent()

        if success {
            if dailyNoteSkipCount > 0 {
                content.title = String(localized: "Daily Notes Completed", comment: "Notification title for daily note terminal skips")
                if dailyNoteUpdateCount == 0 {
                    content.body = String(localized: "Skipped \(dailyNoteSkipCount) missing daily note(s); no export files were created", comment: "Scheduled daily note only terminal skip body")
                } else {
                    content.body = String(localized: "Updated \(dailyNoteUpdateCount) and skipped \(dailyNoteSkipCount) daily note(s); no export files were created", comment: "Scheduled daily note only mixed completion body")
                }
            } else {
                content.title = String(localized: "Export Completed", comment: "Notification title")
                content.body = daysExported == 1
                    ? String(localized: "Successfully exported yesterday's health data", comment: "Export notification body for 1 day")
                    : String(localized: "Successfully exported \(daysExported) days of health data", comment: "Export notification body for multiple days")
            }
            content.sound = .default
        } else {
            content.title = String(localized: "Export Failed", comment: "Notification title for failure")
            var body: String
            if let reason = failureReason {
                body = reason.shortDescription
                if let details = errorDetails, !details.isEmpty {
                    body += ": \(details)"
                }
            } else if let details = errorDetails, !details.isEmpty {
                body = details
            } else {
                body = String(localized: "Failed to export health data. Please check your settings.", comment: "Generic export failure message")
            }
            content.body = body
            content.sound = .default
        }

        // Create the request with a unique identifier
        let request = UNNotificationRequest(
            identifier: "com.codybontecou.healthmd.export.\(UUID().uuidString)",
            content: content,
            trigger: nil // nil trigger means deliver immediately
        )

        // Add the notification request
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Notification sent: \(content.title)")
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Sends a notification prompting the user to unlock the app for scheduled exports.
    private func sendUpgradeRequiredNotification() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Scheduled Export Paused", comment: "Notification title when not unlocked")
        content.body = String(localized: "Unlock Health.md for automated scheduled exports.", comment: "Notification body prompting upgrade")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.codybontecou.healthmd.upgrade.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Upgrade required notification sent")
        } catch {
            logger.error("Failed to send upgrade notification: \(error.localizedDescription)")
        }
    }

    /// Sends a "tap to export" reminder notification when export fails due to device lock
    @MainActor
    private func sendExportReminderNotification() async {
        let request = makePendingExportRequest(
            scheduledFireDate: ScheduleDateMath.latestScheduledOccurrenceDate(
                schedule: schedule,
                now: Date()
            )
        )

        do {
            try pendingExportStore.upsert(request)
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: request)
            logger.info("Export reminder notification sent")
        } catch {
            logger.error("Failed to send export reminder notification: \(error.localizedDescription)")
        }
    }

    private func schedulePendingExportFallbackNotification(for nextRunDate: Date, kind: ScheduledExportKind = .completedDay) {
        Task {
            if await preparePendingScheduledExport(fireDate: nextRunDate, kind: kind) != nil {
                logger.info("Pending export fallback notification scheduled for \(nextRunDate)")
            } else {
                logger.error("Failed to schedule pending export fallback notification")
            }
        }
    }

    private func cancelScheduledPendingExportFallbackNotifications() {
        cancelScheduledPendingExportFallbackNotifications(matching: { $0.scheduledFireDate != nil })
    }

    private func cancelScheduledPendingExportFallbackNotifications(matching shouldCancel: (PendingExportRequest) -> Bool) {
        do {
            let scheduledRequestIDs = Set(try pendingExportStore.loadAll()
                .filter { $0.source == .scheduled && shouldCancel($0) }
                .map(\.id))
            guard !scheduledRequestIDs.isEmpty else { return }

            for requestID in scheduledRequestIDs {
                exportNotificationScheduler.cancelPendingExportNotification(id: requestID)
            }
            try pendingExportStore.clearCompletedRequests(ids: scheduledRequestIDs)
        } catch {
            logger.error("Failed to cancel pending export fallback notifications: \(error.localizedDescription)")
        }
    }

    private func makePendingExportRequest(scheduledFireDate: Date?) -> PendingExportRequest {
        let calendar = Calendar.current
        let referenceDate = scheduledFireDate
            ?? ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, now: Date(), calendar: calendar)
            ?? Date()

        return PendingExportRequest(
            dates: ScheduleDateMath.scheduledExportDates(
                schedule: schedule,
                fireDate: referenceDate,
                calendar: calendar
            ),
            source: .scheduled,
            scheduledFireDate: referenceDate,
            scheduledKind: .completedDay,
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            exportTarget: schedule.target
        )
    }

    // MARK: - Helper Methods

    /// Calculates the next scheduled run date based on current settings.
    private func calculateNextRunOccurrence() -> ScheduleDateMath.DueScheduledOccurrence? {
        ScheduleDateMath.nextScheduledOccurrences(schedule: schedule, now: now()).first
    }

    private func calculateNextRunDate() -> Date {
        calculateNextRunOccurrence()?.fireDate
            ?? now().addingTimeInterval(3600)
    }

    /// Returns a human-readable string describing the next scheduled export.
    @MainActor func getNextExportDescription() -> String? {
        guard schedule.isEnabled else { return nil }

        let nextDate = calculateNextRunDate()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: nextDate)
    }
}
