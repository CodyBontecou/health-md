import Foundation
import BackgroundTasks
import Combine
import UIKit
import UserNotifications
import os.log

/// Result of a notification-triggered export to display in the UI
struct NotificationExportResult: Equatable {
    enum Status: Equatable {
        case success(daysExported: Int)
        case partialSuccess(exported: Int, total: Int)
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
        case .failure(let reason):
            return reason
        case .noExportNeeded:
            return String(localized: "Your health data is already up to date", comment: "No export needed message")
        }
    }

    var isSuccess: Bool {
        switch status {
        case .success, .noExportNeeded:
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
    private let now: @MainActor () -> Date
    private let protectedDataAvailable: @MainActor () -> Bool
    private let scheduledExportCoordinator: ScheduledExportCoordinator
    private let automationBackgroundRunner: AutomationScheduledBackgroundRunner
    private let pendingRetryCoordinator: AutomationPendingExportForegroundRetryCoordinator
    private let persistScheduleChanges: Bool
    private let systemSideEffectsEnabled: Bool

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
        scheduledExportCalendar: Calendar = .current,
        automationBackgroundRunner: AutomationScheduledBackgroundRunner? = nil,
        protectedDataAvailable: @MainActor @escaping () -> Bool = {
            UIApplication.shared.isProtectedDataAvailable
        },
        now: @MainActor @escaping () -> Date = Date.init
    ) {
        self.pendingExportStore = pendingExportStore
        self.exportNotificationScheduler = exportNotificationScheduler
        self.shortcutExportRunner = shortcutExportRunner
        self.scheduledPendingExportRunner = scheduledPendingExportRunner
        self.automationBackgroundRunner = automationBackgroundRunner ?? AutomationScheduledBackgroundRunner(calendar: scheduledExportCalendar)
        self.pendingRetryCoordinator = AutomationPendingExportForegroundRetryCoordinator(
            pendingExportStore: pendingExportStore
        )
        self.protectedDataAvailable = protectedDataAvailable
        self.persistScheduleChanges = persistScheduleChanges
        self.systemSideEffectsEnabled = systemSideEffectsEnabled
        self.now = now
        self.scheduledExportCoordinator = ScheduledExportCoordinator(
            pendingExportStore: pendingExportStore,
            exportNotificationScheduler: exportNotificationScheduler,
            calendar: scheduledExportCalendar
        )
        self.schedule = initialSchedule
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
    private func handleHealthKitBackgroundDelivery() async {
        logger.info("HealthKit background delivery received")

        // Check if we should export (daily frequency and haven't exported today's data yet)
        let currentSchedule = await MainActor.run { schedule }
        guard currentSchedule.isEnabled else {
            logger.info("Schedule disabled, ignoring background delivery")
            return
        }

        // For daily exports, check if yesterday's data needs exporting
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)

        if let lastExport = currentSchedule.lastExportDate {
            let lastExportDay = calendar.startOfDay(for: lastExport)
            if lastExportDay >= yesterday {
                logger.info("Yesterday's data already exported, skipping")
                return
            }
        }

        logger.info("Triggering export from HealthKit background delivery")
        await runAutomaticScheduledExport(trigger: .dataSourceBackgroundDelivery)
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
        let nextRunDate = calculateNextRunDate()
        request.earliestBeginDate = nextRunDate

        // Prefer running when connected to power for better reliability
        request.requiresExternalPower = false  // Don't require, but prefer
        request.requiresNetworkConnectivity = false  // No network needed for local export

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background processing task scheduled for \(nextRunDate)")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }

        schedulePendingExportFallbackNotification(for: nextRunDate)
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
        await pendingRetryCoordinator.retryPendingExport(
            requestID: requestId,
            source: expectedSource,
            trigger: .notificationTap,
            shouldAttempt: { request, trigger in
                self.pendingExportRetryEligibility(for: request, trigger: trigger)
            },
            execute: { request, trigger in
                await self.executePendingExportRetry(request, trigger: trigger)
            },
            onSkip: { request, trigger, reason in
                await self.handlePendingExportRetrySkip(request: request, trigger: trigger, reason: reason)
            }
        )
    }

    /// Drains persisted pending requests when the app becomes active.
    @MainActor func drainPendingExportsIfNeeded(trigger: PendingExportDrainTrigger = .appActive) async {
        let outcomes = await pendingRetryCoordinator.drainPendingExports(
            trigger: trigger.automationRetryTrigger,
            shouldAttempt: { request, trigger in
                self.pendingExportRetryEligibility(for: request, trigger: trigger)
            },
            execute: { request, trigger in
                await self.executePendingExportRetry(request, trigger: trigger)
            },
            onSkip: { request, trigger, reason in
                await self.handlePendingExportRetrySkip(request: request, trigger: trigger, reason: reason)
            }
        )

        if outcomes.isEmpty {
            logger.info("Pending export drain skipped: no pending requests")
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

    @MainActor private func pendingExportRetryEligibility(
        for request: PendingExportRequest,
        trigger: AutomationPendingExportRetryTrigger
    ) -> AutomationPendingExportRetryEligibility {
        switch request.source {
        case .scheduled:
            guard schedule.isEnabled else {
                return .skipped(.scheduleDisabled)
            }
            return .eligible
        case .shortcut:
            return .eligible
        }
    }

    @MainActor private func executePendingExportRetry(
        _ request: PendingExportRequest,
        trigger: AutomationPendingExportRetryTrigger
    ) async {
        switch request.source {
        case .scheduled:
            await executePendingScheduledExportRetry(request, trigger: trigger)
        case .shortcut:
            await executePendingShortcutExportRetry(request)
        }
    }

    @MainActor private func executePendingShortcutExportRetry(_ request: PendingExportRequest) async {
        let outcome = await shortcutExportRunner(request.dates)

        switch outcome {
        case .success(let daysExported, _):
            completePendingShortcutExportRequest(request)
            notificationExportResult = NotificationExportResult(
                status: .success(daysExported: daysExported),
                timestamp: now()
            )
        case .partial(let exported, let total, _, _):
            completePendingShortcutExportRequest(request)
            notificationExportResult = NotificationExportResult(
                status: .partialSuccess(exported: exported, total: total),
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

    @MainActor private func executePendingScheduledExportRetry(
        _ request: PendingExportRequest,
        trigger: AutomationPendingExportRetryTrigger
    ) async {
        logger.info("Draining pending scheduled export request \(request.id.uuidString)")
        let result: ExportOrchestrator.ExportResult
        if let scheduledPendingExportRunner {
            result = await scheduledPendingExportRunner(request.dates)
        } else {
            result = await performBackgroundExport(dates: request.dates)
        }

        await completePendingScheduledExport(request, result: result)
        processPendingScheduledExportResult(result, request: request, retryTrigger: trigger)
    }

    @MainActor private func handlePendingExportRetrySkip(
        request: PendingExportRequest?,
        trigger: AutomationPendingExportRetryTrigger,
        reason: AutomationPendingExportRetrySkipReason
    ) async {
        switch reason {
        case .loadFailed(let message):
            logger.error("Failed to load pending export requests: \(message)")
        case .requestNotFound(let id):
            logger.info("Pending export request not found: \(id.uuidString)")
        case .sourceMismatch(let expected, let actual):
            let id = request?.id.uuidString ?? "unknown"
            logger.warning(
                "Pending export request source mismatch for \(id): expected \(expected.rawValue), found \(actual.rawValue)"
            )
        case .scheduleDisabled:
            if let request {
                logger.info("Schedule disabled, skipping pending scheduled export request \(request.id.uuidString)")
            } else {
                logger.info("Schedule disabled, skipping pending scheduled export request")
            }
            if trigger == .notificationTap {
                notificationExportResult = NotificationExportResult(
                    status: .failure(reason: String(localized: "Scheduling is disabled", comment: "Error message when scheduling is disabled")),
                    timestamp: now()
                )
            }
        case .alreadyInFlight(let id):
            logger.info("Pending export request already in flight, skipping duplicate run: \(id.uuidString)")
        case .requestNoLongerPending(let id):
            logger.info("Pending export request no longer pending, skipping retry: \(id.uuidString)")
        }
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
        retryTrigger: AutomationPendingExportRetryTrigger
    ) {
        let range = scheduledExportHistoryRange(for: request)
        let triggerPolicy = retryTrigger.exportTriggerSource.policy(
            resolvedSourceFamily: request.source.exportTriggerSourceFamily
        )

        if result.successCount > 0 {
            if triggerPolicy.shouldUpdateLastExport(
                successCount: result.successCount,
                exportedDates: request.dates,
                now: now(),
                calendar: Calendar.current
            ) {
                var updatedSchedule = schedule
                updatedSchedule.updateLastExport()
                schedule = updatedSchedule
            }
            ExportOrchestrator.recordResult(
                result,
                triggerSource: retryTrigger.exportTriggerSource,
                resolvedSourceFamily: request.source.exportTriggerSourceFamily,
                dateRangeStart: range.start,
                dateRangeEnd: range.end
            )
        } else if result.totalCount > 0 {
            ExportOrchestrator.recordResult(
                result,
                triggerSource: retryTrigger.exportTriggerSource,
                resolvedSourceFamily: request.source.exportTriggerSourceFamily,
                dateRangeStart: range.start,
                dateRangeEnd: range.end
            )
        }

        notificationExportResult = makeNotificationExportResult(from: result)
    }

    @MainActor private func makeNotificationExportResult(
        from result: ExportOrchestrator.ExportResult
    ) -> NotificationExportResult {
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

        cancelPendingExportFallbackNotification(for: pendingRequest)
        let result = await performBackgroundExport(dates: dates)
        await completePendingScheduledExport(pendingRequest, result: result)

        if result.successCount > 0 {
            let triggerPolicy = ExportTriggerSource.notificationTapRetry.policy(resolvedSourceFamily: .scheduled)
            if triggerPolicy.shouldUpdateLastExport(
                successCount: result.successCount,
                exportedDates: dates,
                now: now(),
                calendar: calendar
            ) {
                var updatedSchedule = schedule
                updatedSchedule.updateLastExport()
                schedule = updatedSchedule
            }
            ExportOrchestrator.recordResult(
                result,
                triggerSource: .notificationTapRetry,
                resolvedSourceFamily: .scheduled,
                dateRangeStart: startDate,
                dateRangeEnd: endDate
            )
            notificationExportResult = NotificationExportResult(
                status: result.isFullSuccess
                    ? .success(daysExported: result.successCount)
                    : .partialSuccess(exported: result.successCount, total: result.totalCount),
                timestamp: now()
            )
        } else if result.totalCount > 0 {
            let reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
            ExportOrchestrator.recordResult(
                result,
                triggerSource: .notificationTapRetry,
                resolvedSourceFamily: .scheduled,
                dateRangeStart: startDate,
                dateRangeEnd: endDate
            )
            notificationExportResult = NotificationExportResult(
                status: .failure(reason: reason),
                timestamp: now()
            )
        } else {
            // performBackgroundExport returns totalCount=0 for the unlock-gate
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
    @MainActor func performSilentPushExport(fireDate: Date? = nil) async {
        let outcome = await runAutomaticScheduledExport(
            trigger: .silentPush,
            fireDate: fireDate
        )

        if outcome.skipReason == .scheduleDisabled {
            logger.info("Silent push received but schedule is disabled")
        }
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

        let missedDates = ScheduleDateMath.catchUpDatesNeeded(
            schedule: schedule,
            now: Date(),
            calendar: .current
        )

        guard !missedDates.isEmpty else {
            logger.info("Catch-up check: No missed exports")
            return NotificationExportResult(status: .noExportNeeded, timestamp: Date())
        }

        logger.info("Catch-up: Found \(missedDates.count) missed date(s) to export")

        // Perform catch-up export
        let result = await performCatchUpExport(for: missedDates)

        if result.successCount > 0 {
            var updatedSchedule = schedule
            updatedSchedule.updateLastExport()
            schedule = updatedSchedule

            // Record in history
            ExportOrchestrator.recordResult(
                result,
                triggerSource: .scheduled,
                dateRangeStart: missedDates.first!,
                dateRangeEnd: missedDates.last!
            )

            logger.info("Catch-up export completed: \(result.successCount)/\(result.totalCount) days")

            // Return appropriate result
            if result.isFullSuccess {
                return NotificationExportResult(
                    status: .success(daysExported: result.successCount),
                    timestamp: Date()
                )
            } else {
                return NotificationExportResult(
                    status: .partialSuccess(exported: result.successCount, total: result.totalCount),
                    timestamp: Date()
                )
            }
        } else {
            // All failed
            let reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
            return NotificationExportResult(
                status: .failure(reason: reason),
                timestamp: Date()
            )
        }
    }

    /// Performs export for specific missed dates using shared ExportOrchestrator
    private func performCatchUpExport(for dates: [Date]) async -> ExportOrchestrator.ExportResult {
        let healthKitManager = HealthKitManager.shared
        let vaultManager = VaultManager()
        let advancedSettings = AdvancedExportSettings()

        guard vaultManager.hasVaultAccess else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .noVaultSelected) },
                formatsPerDate: advancedSettings.exportFormats.count
            )
        }

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()

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
    private func handleBackgroundTask(_ task: BGProcessingTask) async {
        logger.info("Background processing task started")

        let outcome = await runAutomaticScheduledExport(
            trigger: .backgroundTask,
            beforeExport: { prepared in
                // Schedule the next task without clearing the pending occurrence this
                // task is about to fulfill.
                self.scheduleBackgroundTask(cancelPendingFallbacks: false)

                let range = prepared.dateRange
                task.expirationHandler = {
                    self.logger.warning("Background task expired")
                    Task {
                        let timeout = AutomationBackgroundExportResult.timedOut(totalCount: range.totalCount)
                        await self.sendExportNotification(
                            success: false,
                            daysExported: 0,
                            failureReason: timeout.healthMdFailureReason
                        )
                        // Record task expiration in history
                        ExportHistoryManager.shared.recordFailure(
                            source: ExportSource(triggerSource: .backgroundTask),
                            dateRangeStart: range.start,
                            dateRangeEnd: range.end,
                            reason: .backgroundTaskExpired,
                            totalCount: range.totalCount
                        )
                    }
                }
            },
            afterExport: { result, _ in
                task.setTaskCompleted(success: result.successCount > 0)
            }
        )

        if outcome.exportResult == nil {
            task.setTaskCompleted(success: false)
        }
    }

    @MainActor
    @discardableResult
    private func runAutomaticScheduledExport(
        trigger: AutomationBackgroundTrigger,
        fireDate: Date? = nil,
        beforeExport: @MainActor @escaping (AutomationScheduledBackgroundPreparedRun<PendingExportRequest>) async -> Void = { _ in },
        afterExport: @MainActor @escaping (
            ExportOrchestrator.ExportResult,
            AutomationScheduledBackgroundRunOutcome<PendingExportRequest, ExportOrchestrator.ExportResult>
        ) async -> Void = { _, _ in }
    ) async -> AutomationScheduledBackgroundRunOutcome<PendingExportRequest, ExportOrchestrator.ExportResult> {
        let calendar = automationBackgroundRunner.calendar
        let scheduleSnapshot = schedule
        let automationSchedule = scheduleSnapshot.automationSchedule(timeZone: calendar.timeZone)

        let outcome = await automationBackgroundRunner.runScheduledExport(
            trigger: trigger,
            schedule: automationSchedule,
            requestedFireDate: fireDate,
            now: now(),
            preparePendingWork: { context in
                guard let request = await self.preparePendingScheduledExport(fireDate: context.resolvedFireDate) else {
                    return nil
                }

                return AutomationPreparedScheduledBackgroundWork(
                    request: request,
                    dates: request.dates,
                    scheduledFireDate: request.scheduledFireDate
                )
            },
            cancelPendingFallback: { pendingWork in
                self.cancelPendingExportFallbackNotification(for: pendingWork?.request)
            },
            beforeExport: beforeExport,
            export: { dates, _ in
                let result: ExportOrchestrator.ExportResult
                if let scheduledPendingExportRunner = self.scheduledPendingExportRunner {
                    result = await scheduledPendingExportRunner(dates)
                } else {
                    result = await self.performBackgroundExport(dates: dates)
                }
                return (result, result.automationBackgroundExportResult)
            }
        )

        guard let result = outcome.exportResult,
              let range = outcome.dateRange else {
            return outcome
        }

        await afterExport(result, outcome)
        await processAutomaticScheduledExportResult(
            result,
            triggerSource: trigger.exportTriggerSource,
            pendingRequest: outcome.pendingWork?.request,
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            fallbackDaysToExport: range.totalCount
        )
        return outcome
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

        let advancedSettings = AdvancedExportSettings()

        let canReadProtectedData = await MainActor.run { protectedDataAvailable() }
        guard canReadProtectedData else {
            logger.error("Protected data unavailable in background")
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .deviceLocked) },
                formatsPerDate: advancedSettings.exportFormats.count
            )
        }

        // Get the required managers
        let healthKitManager = await MainActor.run { HealthKitManager.shared }
        let vaultManager = VaultManager()

        // Check if vault is configured
        guard vaultManager.hasVaultAccess else {
            logger.error("No vault access in background")
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .noVaultSelected) },
                formatsPerDate: advancedSettings.exportFormats.count
            )
        }

        logger.info("Vault access confirmed: \(vaultManager.vaultURL?.path ?? "unknown")")

        logger.info("Exporting \(dates.count) days of data")

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()

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
    private func preparePendingScheduledExport(fireDate: Date? = nil) async -> PendingExportRequest? {
        let resolvedFireDate = fireDate
            ?? ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, now: Date())
            ?? Date()

        do {
            return try await scheduledExportCoordinator.preparePendingScheduledExport(
                schedule: schedule,
                fireDate: resolvedFireDate
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
    ) async {
        guard let request else {
            if result.primaryFailureReason == .deviceLocked {
                await sendExportReminderNotification()
            }
            return
        }

        do {
            _ = try await scheduledExportCoordinator.completePendingScheduledExport(
                request,
                result: result
            )
        } catch {
            logger.error("Failed to complete pending scheduled export: \(error.localizedDescription)")
            if result.primaryFailureReason == .deviceLocked {
                await sendExportReminderNotification()
            }
        }
    }

    @MainActor
    private func scheduledExportHistoryRange(for request: PendingExportRequest) -> (start: Date, end: Date, totalCount: Int) {
        if let first = request.dates.first, let last = request.dates.last {
            return (first, last, request.dates.count)
        }

        let calendar = Calendar.current
        let fireDate = request.scheduledFireDate ?? Date()
        let dates = ScheduleDateMath.scheduledExportDates(
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
    private func fallbackScheduledExportDates() -> [Date] {
        let fireDate = ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, now: Date()) ?? Date()
        return ScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: fireDate
        )
    }

    @MainActor
    private func fallbackScheduledExportHistoryRange() -> (start: Date, end: Date, totalCount: Int) {
        let fireDate = ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, now: Date()) ?? Date()
        let dates = ScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: fireDate
        )

        if let first = dates.first, let last = dates.last {
            return (first, last, dates.count)
        }

        let fallback = Calendar.current.startOfDay(for: fireDate)
        return (fallback, fallback, 0)
    }

    @MainActor
    private func processAutomaticScheduledExportResult(
        _ result: ExportOrchestrator.ExportResult,
        triggerSource: ExportTriggerSource,
        pendingRequest: PendingExportRequest?,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        fallbackDaysToExport: Int
    ) async {
        await completePendingScheduledExport(pendingRequest, result: result)
        let triggerPolicy = triggerSource.policy(resolvedSourceFamily: .scheduled)
        let exportedDates = pendingRequest?.dates ?? ExportOrchestrator.dateRange(from: dateRangeStart, to: dateRangeEnd)

        if result.successCount > 0 {
            if triggerPolicy.shouldUpdateLastExport(
                successCount: result.successCount,
                exportedDates: exportedDates,
                now: now(),
                calendar: Calendar.current
            ) {
                var updatedSchedule = schedule
                updatedSchedule.updateLastExport()
                schedule = updatedSchedule
            }

            logger.info("Scheduled export completed successfully")
            await sendExportNotification(success: true, daysExported: result.successCount)

            ExportOrchestrator.recordResult(
                result,
                triggerSource: triggerSource,
                resolvedSourceFamily: .scheduled,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd
            )
        } else if result.totalCount > 0 {
            logger.error("Scheduled export failed")

            let failureReason = result.primaryFailureReason
            if failureReason != .deviceLocked {
                await sendExportNotification(
                    success: false,
                    daysExported: max(result.totalCount, fallbackDaysToExport),
                    failureReason: failureReason,
                    errorDetails: result.failedDateDetails.first?.errorDetails
                )
            }

            ExportOrchestrator.recordResult(
                result,
                triggerSource: triggerSource,
                resolvedSourceFamily: .scheduled,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd
            )
        }
    }

    // MARK: - Notifications

    /// Sends a notification after a scheduled export completes
    private func sendExportNotification(success: Bool, daysExported: Int, failureReason: ExportFailureReason? = nil, errorDetails: String? = nil) async {
        let content = UNMutableNotificationContent()

        if success {
            content.title = String(localized: "Export Completed", comment: "Notification title")
            content.body = daysExported == 1
                ? String(localized: "Successfully exported yesterday's health data", comment: "Export notification body for 1 day")
                : String(localized: "Successfully exported \(daysExported) days of health data", comment: "Export notification body for multiple days")
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
            ),
            reason: .protectedDataUnavailable
        )

        do {
            try pendingExportStore.upsert(request)
            try await exportNotificationScheduler.sendImmediatePendingExportNotification(for: request)
            logger.info("Export reminder notification sent")
        } catch {
            logger.error("Failed to send export reminder notification: \(error.localizedDescription)")
        }
    }

    private func schedulePendingExportFallbackNotification(for nextRunDate: Date) {
        Task {
            if await preparePendingScheduledExport(fireDate: nextRunDate) != nil {
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

    private func makePendingExportRequest(
        scheduledFireDate: Date?,
        reason: PendingExportReason? = nil
    ) -> PendingExportRequest {
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
            reason: reason,
            scheduledFireDate: referenceDate,
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue]
        )
    }

    // MARK: - Helper Methods

    /// Calculates the next scheduled run date based on current settings
    private func calculateNextRunDate() -> Date {
        let now = Date()
        return ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now) ?? now.addingTimeInterval(3600)
    }

    /// Returns a human-readable string describing the next scheduled export
    @MainActor func getNextExportDescription() -> String? {
        guard schedule.isEnabled else { return nil }

        let nextDate = calculateNextRunDate()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: nextDate)
    }
}

private extension SchedulingManager.PendingExportDrainTrigger {
    var automationRetryTrigger: AutomationPendingExportRetryTrigger {
        switch self {
        case .notificationTap:
            return .notificationTap
        case .appActive:
            return .appActiveDrain
        }
    }
}

private extension ExportOrchestrator.ExportResult {
    var automationBackgroundExportResult: AutomationBackgroundExportResult {
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

private extension AutomationBackgroundExportResult {
    var healthMdFailureReason: ExportFailureReason {
        primaryFailureReason?.healthMdFailureReason ?? .unknown
    }
}

private extension AutomationBackgroundExportFailureReason {
    var healthMdFailureReason: ExportFailureReason {
        switch self {
        case .noDestination:
            return .noVaultSelected
        case .protectedDataUnavailable:
            return .deviceLocked
        case .noData:
            return .noHealthData
        case .timeLimitExceeded:
            return .backgroundTaskExpired
        case .quotaBlocked, .cancelled, .exportFailed, .unknown:
            return .unknown
        }
    }
}
