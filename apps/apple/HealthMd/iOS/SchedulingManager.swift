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
    // Keep deallocation on the releasing thread. Avoid Swift 6.2+'s crashing
    // isolated-deinit executor hop (swiftlang/swift#85663), which aborted CI
    // test processes on older iOS runtimes when the last release happened off
    // the main actor during app-host teardown. Matches AdvancedExportSettings.
    nonisolated deinit {}
    enum PendingExportDrainTrigger {
        case notificationTap
        case appActive
    }

    typealias ScheduledPendingExportRunner = @MainActor ([Date]) async -> ExportOrchestrator.ExportResult
    typealias ScheduledTargetExportRunner = @MainActor ([Date], ExportTargetSelection) async -> ExportOrchestrator.ExportResult
    typealias ScheduledLocalDestinationPreflight = @MainActor ([Date]) -> ExportOrchestrator.ExportResult?
    typealias ScheduledExportQuotaAccess = @MainActor (UUID?) -> Bool
    typealias ScheduledExportQuotaRecorder = @MainActor (UUID?) throws -> Void

    private struct ScheduledMacExportContext {
        let dateRangeStart: Date
        let dateRangeEnd: Date
        let requestedDates: [Date]
        let settings: AdvancedExportSettings
        let notificationOperationID: UUID?
        let continuation: CheckedContinuation<ExportOrchestrator.ExportResult, Never>
    }

    @MainActor static let shared = SchedulingManager()

    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "SchedulingManager")
    private static let exportLimitReachedMessage = String(
        localized: "Free export limit reached. Scheduled exports use the same \(PurchaseManager.freeExportLimit)-export allowance as manual exports. Unlock Full Access to continue.",
        comment: "Message shown when a scheduled export cannot run because free quota is exhausted"
    )

    /// Background task identifier - must match Info.plist entry
    static let backgroundTaskIdentifier = "com.codybontecou.healthmd.dataexport"

    /// Key for tracking last successful export date in UserDefaults
    private let lastExportDateKey = "lastSuccessfulExportDate"

    private let pendingExportStore: PendingExportStoring
    private let exportNotificationScheduler: ExportNotificationScheduling
    private let shortcutExportRunner: @MainActor ([Date]) async -> ExportIntentRunner.Outcome
    private let scheduledPendingExportRunner: ScheduledPendingExportRunner?
    private let scheduledTargetExportRunner: ScheduledTargetExportRunner?
    private let scheduledLocalDestinationPreflight: ScheduledLocalDestinationPreflight?
    private let scheduledExportQuotaAccess: ScheduledExportQuotaAccess
    private let scheduledExportQuotaRecorder: ScheduledExportQuotaRecorder
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
    /// Phase-3 per-profile occurrence keys: "profileID|kind|fireMinute". Two
    /// profiles firing at the same minute never deduplicate each other
    /// (decision 6), while a duplicate trigger for the same profile does.
    @MainActor private var inFlightProfileOccurrenceKeys: Set<String> = []
    @MainActor private var scheduledExportDependenciesConfigured = false
    @MainActor private var scheduledExportDependencyWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Phase 3 profile scheduling

    /// Scheduled entries, profile store, and destination store. Separate
    /// instances read the same UserDefaults keys the UI layer writes, so the
    /// runtime observes UI mutations on next read.
    private let scheduledEntryStore: ScheduledExportEntryStore
    private let scheduledProfileStore: ExportProfileStore
    private let scheduledDestinationStore: ProfileDestinationStore
    /// Serializes local-folder profile runs: adopting a profile's vault writes
    /// shared persisted destination state that `VaultManager()` resolves, so
    /// folder-target runs must not overlap. Non-folder targets run
    /// concurrently (decision 6).
    private let profileFolderRunGate = AsyncSemaphore()
    /// Overridable destination adoption for tests; production adopts through
    /// persisted vault keys + APIExportSettings exactly like the UI
    /// coordinator.
    private let scheduledProfileDestinationAdopter: @MainActor (ExportProfile?) -> Void

    /// Result from notification-triggered export, observed by UI to show alert
    /// when no in-app activity banner owns the operation.
    @MainActor @Published var notificationExportResult: NotificationExportResult? {
        didSet {
            guard let notificationExportResult else { return }
            NotificationExportActivityTracker.shared.finish(with: notificationExportResult)
        }
    }

    /// True when the legacy schedule or any scheduled entry is enabled. The
    /// UI master toggle and status pills read this instead of the legacy
    /// schedule alone (phase 3: entries own scheduling after migration).
    @MainActor @Published private(set) var isSchedulingActive: Bool = false

    /// Re-arms background automation and worker sync for the current state:
    /// the legacy schedule and every scheduled entry. Called from the legacy
    /// `schedule` didSet and by the UI after entry mutations.
    @MainActor func refreshScheduledAutomation() {
        isSchedulingActive = schedule.isEnabled || hasEnabledProfileEntries
        guard systemSideEffectsEnabled else { return }
        guard !TestMode.isUITesting else { return }
        #if DEBUG
        guard !MarketingCapture.isActive else { return }
        #endif
        let active = isSchedulingActive
        Task { @MainActor in
            if active {
                self.scheduleBackgroundTask()
                await self.setupHealthKitBackgroundDelivery()
                await PushRegistrationManager.shared.registerForRemoteNotificationsIfNeeded()
            } else {
                self.cancelBackgroundTask()
                await self.disableHealthKitBackgroundDelivery()
            }
        }
        // Mirror the coalesced state to the worker so server-side cron can
        // deliver silent push at the earliest preferred minute. Disabling
        // everything sends isEnabled:false so the worker drops the row.
        // Fresh read: the UI mutates entries through the coordinator's store
        // instance, so the manager must re-read before syncing.
        PushRegistrationManager.shared.syncSchedules(
            scheduledEntryStore.allEntries(),
            legacy: schedule
        )
    }

    @MainActor @Published var schedule: ExportSchedule {
        didSet {
            if persistScheduleChanges {
                schedule.save()
            }
            refreshScheduledAutomation()
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
        scheduledLocalDestinationPreflight: ScheduledLocalDestinationPreflight? = nil,
        scheduledExportQuotaAccess: @escaping ScheduledExportQuotaAccess = { jobID in
            guard let jobID else { return PurchaseManager.shared.canExport }
            return PurchaseManager.shared.canExport(jobID: jobID)
        },
        scheduledExportQuotaRecorder: @escaping ScheduledExportQuotaRecorder = { jobID in
            if let jobID {
                try PurchaseManager.shared.recordExportUse(jobID: jobID)
            } else {
                PurchaseManager.shared.recordExportUse()
            }
        },
        scheduledMacExportTimeout: TimeInterval = 120,
        now: @MainActor @escaping () -> Date = Date.init,
        scheduledEntryStore: ScheduledExportEntryStore = ScheduledExportEntryStore(),
        scheduledProfileStore: ExportProfileStore = ExportProfileStore(),
        scheduledDestinationStore: ProfileDestinationStore = ProfileDestinationStore(),
        scheduledProfileDestinationAdopter: (@MainActor (ExportProfile?) -> Void)? = nil
    ) {
        self.pendingExportStore = pendingExportStore
        self.exportNotificationScheduler = exportNotificationScheduler
        self.shortcutExportRunner = shortcutExportRunner
        self.scheduledPendingExportRunner = scheduledPendingExportRunner
        self.scheduledTargetExportRunner = scheduledTargetExportRunner
        self.scheduledLocalDestinationPreflight = scheduledLocalDestinationPreflight
        self.scheduledExportQuotaAccess = scheduledExportQuotaAccess
        self.scheduledExportQuotaRecorder = scheduledExportQuotaRecorder
        self.scheduledMacExportTimeout = scheduledMacExportTimeout
        self.persistScheduleChanges = persistScheduleChanges
        self.systemSideEffectsEnabled = systemSideEffectsEnabled
        self.now = now
        self.scheduledEntryStore = scheduledEntryStore
        self.scheduledProfileStore = scheduledProfileStore
        self.scheduledDestinationStore = scheduledDestinationStore
        self.scheduledProfileDestinationAdopter = scheduledProfileDestinationAdopter
            ?? { profile in Self.defaultAdoptProfileDestinations(profile) }
        self.scheduledExportCoordinator = ScheduledExportCoordinator(
            pendingExportStore: pendingExportStore,
            exportNotificationScheduler: exportNotificationScheduler
        )
        self.schedule = initialSchedule
        isSchedulingActive = self.schedule.isEnabled || self.hasEnabledProfileEntries
    }

    @MainActor func configureScheduledExportDependencies(
        syncService: SyncService,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) {
        self.scheduledSyncService = syncService
        self.scheduledExternalIntegrations = externalIntegrations
        scheduledExportDependenciesConfigured = true

        let waiters = scheduledExportDependencyWaiters
        scheduledExportDependencyWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    /// Lifecycle notification callbacks can arrive before the SwiftUI root task
    /// has installed sync handlers and scheduled-export dependencies. Waiting
    /// here prevents a cold notification launch from being recorded as a false
    /// Connected Mac configuration failure.
    @MainActor func waitForScheduledExportDependencies() async {
        guard !scheduledExportDependenciesConfigured else { return }
        await withCheckedContinuation { continuation in
            scheduledExportDependencyWaiters.append(continuation)
        }
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

        // Phase 3 dual-mode: entries first when enabled, then the legacy
        // schedule's due occurrence, so both run when both are enabled.
        if hasEnabledProfileEntries {
            await runDueProfileOccurrences()
        }
        _ = await runDueLegacyOccurrence()
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

        guard schedule.isEnabled || hasEnabledProfileEntries else {
            logger.info("Schedule disabled, not scheduling background task")
            return
        }

        // Use BGProcessingTask for longer runtime and better reliability
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)

        // Calculate next execution time
        let nextRunPlan = calculateNextRunPlan()
        let nextRunDate = nextRunPlan?.occurrence.fireDate ?? now().addingTimeInterval(3600)
        request.earliestBeginDate = nextRunDate

        // Prefer running when connected to power for better reliability.
        // API Endpoint and Connected Mac scheduled targets need networking.
        request.requiresExternalPower = false  // Don't require, but prefer
        request.requiresNetworkConnectivity = schedule.target.requiresNetworkForScheduledExport
            || scheduledEntryStore.enabledEntries()
                .contains { $0.dateMathProjection.target.requiresNetworkForScheduledExport }

        if TestMode.isUnitTesting {
            // Submitting an unregistered identifier aborts the unit-test host
            // process (BGTaskScheduler assertion). The fallback arming below
            // is what unit tests verify; the OS task is meaningless there.
            logger.info("Skipping BGTaskScheduler submission in unit tests")
        } else {
            do {
                try BGTaskScheduler.shared.submit(request)
                logger.info("Background processing task scheduled for \(nextRunDate)")
            } catch {
                logger.error("Failed to schedule background task: \(error.localizedDescription)")
            }
        }

        schedulePendingExportFallbackNotification(
            for: nextRunDate,
            kind: nextRunPlan?.occurrence.kind ?? .completedDay,
            entry: nextRunPlan?.entry
        )
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
            await runPendingShortcutExport(request)
        }
    }

    @MainActor private func runPendingShortcutExport(_ request: PendingExportRequest) async {
        guard beginPendingExport(request) else { return }
        defer { finishPendingExport(request) }

        guard isPendingExportRequestStillStored(request) else { return }

        beginNotificationExportActivity(
            operationID: request.id,
            source: .shortcut,
            dates: request.dates,
            target: .localIPhoneFolder
        )

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
        case .noVault, .destinationChanged, .paywall, .failure, .profileNotFound:
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
        guard await shouldAttemptPendingScheduledExport(request, trigger: trigger) else { return }
        guard shouldAttemptPendingScheduledExportTarget(request) else { return }
        // Dedupe gate: profile requests use the per-profile occurrence key so
        // a retry never collides with another profile's run at the same fire
        // minute; legacy requests keep the shared fire-minute key.
        guard beginOccurrenceExport(for: request) else { return }
        defer { finishOccurrenceExport(for: request) }
        guard beginPendingExport(request) else { return }
        defer { finishPendingExport(request) }

        guard isPendingExportRequestStillStored(request) else { return }

        // Mark the request attempted before the run: if the process dies
        // mid-run, bulk fallback cancellation must still classify the stored
        // request as a preserved retry rather than an armed fallback.
        markPendingExportRequestAttempted(request)

        // The armed +60s fallback for this request is superseded the moment
        // the run starts: defuse it so it cannot fire mid-run. Delivered
        // copies stay visible — a run that ends without progress or a
        // re-armed retry (see completePendingScheduledExport) must not leave
        // the user without a recovery notification.
        exportNotificationScheduler.cancelArmedPendingExportNotification(id: request.id)

        logger.info("Draining pending scheduled export request \(request.id.uuidString)")
        let target = scheduledTarget(for: request)
        // Phase 3: profile requests run against their profile's destinations;
        // the active profile's destinations are restored afterward.
        let profileForRun: ExportProfile?
        if let profileID = request.profileID {
            profileForRun = scheduledProfileStore.profile(id: profileID)
        } else {
            profileForRun = nil
        }
        // Every executed pending run owns the notification activity banner,
        // including plain app-active drains: a cold-launch drain can outrun
        // the notification tap handler, and without banner ownership its
        // result would surface as an unexpected bare alert instead of the
        // in-app activity banner the tap path presents.
        let notificationOperationID = request.id
        beginNotificationExportActivity(
            operationID: request.id,
            source: .scheduled,
            dates: request.dates,
            target: target
        )
        let result: ExportOrchestrator.ExportResult
        if let profileForRun {
            result = await runProfileScopedExport(
                profile: profileForRun,
                dates: request.dates,
                target: target,
                settings: request.settingsSnapshot
                    ?? ExportSettingsSnapshot.from(AdvancedExportSettings()),
                quotaJobID: request.id,
                notificationOperationID: notificationOperationID
            )
        } else {
            result = await runScheduledExport(
                dates: request.dates,
                target: target,
                settingsSnapshot: request.settingsSnapshot,
                quotaJobID: request.id,
                notificationOperationID: notificationOperationID
            )
        }

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
    ) async -> Bool {
        // Phase 3: profile requests gate on their entry's enabled state, not
        // the legacy schedule.
        if let profileID = request.profileID {
            let entry = scheduledEntryStore.entry(profileID: profileID)
            guard entry?.isEnabled == true else {
                logger.info("Profile schedule disabled, skipping pending request \(request.id.uuidString)")
                if trigger == .notificationTap {
                    // Mirror the legacy-disabled tap surface: a tap on a
                    // recovery notification whose schedule was turned off
                    // must tell the user, not return silently.
                    notificationExportResult = NotificationExportResult(
                        status: .failure(reason: String(
                            localized: "Scheduling is disabled for \(request.profileName ?? "this profile")",
                            comment: "Error message when a tapped recovery notification's profile schedule is disabled"
                        )),
                        timestamp: now()
                    )
                }
                return false
            }
            if let fireDate = request.scheduledFireDate, fireDate > now() {
                logger.info("Skipping future profile pending request \(request.id.uuidString)")
                return false
            }
            // Mirror the legacy enabled-period discard: a retry preserved
            // before the entry was disabled predates the current opt-in, so
            // re-enabling days later must not drain a stale window (and burn
            // quota on dates the user no longer expects).
            if let enabledAt = entry?.enabledAt,
               let fireDate = request.scheduledFireDate,
               fireDate <= enabledAt {
                logger.info("Discarding profile pending request from before the entry's current enabled period: \(request.id.uuidString)")
                discardPendingScheduledExportRequest(request)
                return false
            }
            return true
        }

        guard schedule.isEnabled || hasEnabledProfileEntries else {
            logger.info("Schedule disabled, skipping pending scheduled export request \(request.id.uuidString)")
            if trigger == .notificationTap {
                notificationExportResult = NotificationExportResult(
                    status: .failure(reason: String(localized: "Scheduling is disabled", comment: "Error message when scheduling is disabled")),
                    timestamp: now()
                )
            }
            return false
        }

        guard schedule.isEnabled else {
            // Profile entries own scheduling; a legacy-shaped pending request
            // (pre-profile build or legacy fallback) is obsolete. Discard it
            // and honor a notification tap by running due profile work — the
            // notification promised a retry, so it must not dead-end with
            // "Scheduling is disabled" while entries are actively scheduled.
            logger.info("Discarding legacy pending request superseded by profile scheduling: \(request.id.uuidString)")
            discardPendingScheduledExportRequest(request)
            if trigger == .notificationTap {
                await runDueProfileOccurrences()
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

    /// A cold launch starts the iPhone-to-Mac transport asynchronously. Keep the
    /// exact pending request untouched until the peer handshake and destination
    /// status exist instead of recording a misleading "open iPhone" failure.
    @MainActor private func shouldAttemptPendingScheduledExportTarget(
        _ request: PendingExportRequest
    ) -> Bool {
        guard scheduledTarget(for: request) == .connectedMac else { return true }
        guard scheduledSyncService != nil else {
            logger.info("Deferring pending Connected Mac export until app services are configured")
            return false
        }
        guard scheduledConnectedMacHandshakeComplete else {
            logger.info("Deferring pending Connected Mac export until the Mac handshake completes")
            return false
        }
        return true
    }

    /// Retries deferred Connected Mac work once the app observes a fully ready
    /// Mac destination. This is the second half of cold-launch recovery: the
    /// notification opens the app, transport reconnects, then the exact stored
    /// dates run without requiring another tap.
    @MainActor func resumePendingConnectedMacExportsIfReady() async {
        guard let syncService = scheduledSyncService,
              syncService.canExportToConnectedMac else { return }

        let requests: [PendingExportRequest]
        do {
            requests = try pendingExportStore.loadAll().sorted(by: pendingExportSort)
        } catch {
            logger.error("Failed to load pending Connected Mac exports: \(error.localizedDescription)")
            return
        }

        for request in requests where request.source == .scheduled
            && scheduledTarget(for: request) == .connectedMac {
            await runPendingScheduledExport(request, trigger: .appActive)
        }

        if schedule.target == .connectedMac {
            await performCatchUpExportIfNeeded()
        }
    }

    @MainActor private var scheduledConnectedMacHandshakeComplete: Bool {
        guard let syncService = scheduledSyncService else { return false }
        return syncService.connectionState == .connected
            && syncService.remoteCapabilities != nil
            && syncService.macDestinationStatus != nil
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

    @MainActor private func beginOccurrenceExport(for request: PendingExportRequest) -> Bool {
        guard let fireDate = request.scheduledFireDate else { return true }
        guard let profileID = request.profileID else {
            return beginScheduledOccurrenceExport(fireDate: fireDate)
        }
        return beginProfileOccurrenceExport(
            profileID: profileID,
            kind: request.scheduledKind,
            fireDate: fireDate
        )
    }

    @MainActor private func finishOccurrenceExport(for request: PendingExportRequest) {
        guard let fireDate = request.scheduledFireDate else { return }
        guard let profileID = request.profileID else {
            finishScheduledOccurrenceExport(fireDate: fireDate)
            return
        }
        finishProfileOccurrenceExport(
            profileID: profileID,
            kind: request.scheduledKind,
            fireDate: fireDate
        )
    }

    @MainActor private func beginProfileOccurrenceExport(
        profileID: UUID,
        kind: ScheduledExportKind,
        fireDate: Date
    ) -> Bool {
        let key = profileOccurrenceKey(profileID: profileID, kind: kind, fireDate: fireDate)
        guard !inFlightProfileOccurrenceKeys.contains(key) else {
            logger.info("Profile occurrence already in flight, skipping duplicate: \(key)")
            return false
        }
        inFlightProfileOccurrenceKeys.insert(key)
        return true
    }

    @MainActor private func finishProfileOccurrenceExport(
        profileID: UUID,
        kind: ScheduledExportKind,
        fireDate: Date
    ) {
        inFlightProfileOccurrenceKeys.remove(
            profileOccurrenceKey(profileID: profileID, kind: kind, fireDate: fireDate)
        )
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
            if let profileID = request.profileID {
                // Phase 3: profile requests advance their entry's progress
                // state; the legacy schedule stays untouched.
                scheduledEntryStore.recordSuccess(
                    profileID: profileID,
                    kind: request.scheduledKind,
                    occurrenceDate: request.scheduledFireDate ?? now()
                )
            } else {
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
        }

        if !isExportLimitResult(result), result.successCount > 0 || result.totalCount > 0 {
            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: range.start,
                dateRangeEnd: range.end,
                targetLabel: targetLabel,
                exportTarget: target,
                appleExportEnginePin: request.settingsSnapshot?.appleExportEnginePin,
                profileName: request.profileName
            )
        }

        notificationExportResult = makeNotificationExportResult(from: result)
    }

    private func isExportLimitResult(_ result: ExportOrchestrator.ExportResult) -> Bool {
        result.failedDateDetails.first?.errorDetails == Self.exportLimitReachedMessage
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
            let firstErrorDetails = result.failedDateDetails.first?.errorDetails
            let reason: String
            if let firstErrorDetails,
               firstErrorDetails == VaultManager.destinationChangedMessage
                || firstErrorDetails == Self.exportLimitReachedMessage {
                reason = firstErrorDetails
            } else {
                reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
            }
            return NotificationExportResult(
                status: .failure(reason: reason),
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
    private func beginNotificationExportActivity(
        operationID: UUID,
        source: NotificationExportActivityTracker.Source,
        dates: [Date],
        target: ExportTargetSelection
    ) {
        notificationExportResult = nil
        let targetLabel = scheduledTargetLabel(for: target) ?? target.title
        let dayDescription = dates.count == 1 ? "1 day" : "\(dates.count) days"
        NotificationExportActivityTracker.shared.begin(
            operationID: operationID,
            source: source,
            targetLabel: targetLabel,
            totalDays: dates.count,
            message: "Starting \(dayDescription) to \(targetLabel)…"
        )
    }

    @MainActor
    private func updateNotificationExportActivity(
        operationID: UUID?,
        phase: NotificationExportActivityTracker.Phase,
        processedDays: Int,
        totalDays: Int,
        message: String
    ) {
        guard let operationID else { return }
        NotificationExportActivityTracker.shared.update(
            operationID: operationID,
            phase: phase,
            processedDays: processedDays,
            totalDays: totalDays,
            message: message
        )
    }

    @MainActor
    private func makeSettingsSnapshotForNewScheduledOperation(
        target: ExportTargetSelection
    ) async -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings()
        let calendarTimeZone = TimeZone.current
        switch target {
        case .localIPhoneFolder:
            let hasNativeOnlyCompanionAction = ConnectedAppsFeature.isEnabled
                && (scheduledExternalIntegrations?.connectedProviderCount ?? 0) > 0
            return await ExportSettingsSnapshot.forNewAppleOperation(
                settings,
                healthSubfolder: VaultManager().healthSubfolder,
                calendarTimeZone: calendarTimeZone,
                surface: .localVaultRangeWithoutSideEffects,
                hasNativeOnlyCompanionAction: hasNativeOnlyCompanionAction
            )
        case .apiEndpoint:
            return await ExportSettingsSnapshot.forNewAppleOperation(
                settings,
                calendarTimeZone: calendarTimeZone,
                surface: .apiEndpoint
            )
        case .connectedMac:
            let hasNativeOnlyCompanionAction = ConnectedAppsFeature.isEnabled
                && (scheduledExternalIntegrations?.connectedProviderCount ?? 0) > 0
            return await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(
                settings,
                healthSubfolder: VaultManager().healthSubfolder,
                calendarTimeZone: calendarTimeZone,
                hasNativeOnlyCompanionAction: hasNativeOnlyCompanionAction
            )
        }
    }

    @MainActor
    private func runScheduledExport(
        dates: [Date],
        target: ExportTargetSelection,
        settingsSnapshot: ExportSettingsSnapshot? = nil,
        quotaJobID: UUID?,
        notificationOperationID: UUID? = nil
    ) async -> ExportOrchestrator.ExportResult {
        if target == .localIPhoneFolder,
           let blockedResult = scheduledLocalDestinationPreflight?(dates) {
            return blockedResult
        }

        guard scheduledExportQuotaAccess(quotaJobID) else {
            logger.info("Scheduled export skipped — free export limit reached")
            return scheduledFailureResult(
                dates: dates,
                reason: .unknown,
                message: Self.exportLimitReachedMessage
            )
        }

        let result: ExportOrchestrator.ExportResult
        if let scheduledTargetExportRunner {
            result = await scheduledTargetExportRunner(dates, target)
        } else if let scheduledPendingExportRunner {
            // Preserve older unit-test seams that only cared about dates.
            result = await scheduledPendingExportRunner(dates)
        } else {
            switch target {
            case .localIPhoneFolder:
                result = await performBackgroundExport(
                    dates: dates,
                    settingsSnapshot: settingsSnapshot,
                    notificationOperationID: notificationOperationID
                )
            case .apiEndpoint:
                result = await performBackgroundAPIEndpointExport(
                    dates: dates,
                    settingsSnapshot: settingsSnapshot,
                    notificationOperationID: notificationOperationID
                )
            case .connectedMac:
                result = await performBackgroundConnectedMacExport(
                    dates: dates,
                    settingsSnapshot: settingsSnapshot,
                    quotaJobID: quotaJobID,
                    notificationOperationID: notificationOperationID
                )
            }
        }

        recordScheduledExportQuotaUseIfNeeded(for: result, jobID: quotaJobID)
        return result
    }

    @MainActor
    private func recordScheduledExportQuotaUseIfNeeded(
        for result: ExportOrchestrator.ExportResult,
        jobID: UUID?
    ) {
        guard result.successCount > 0 else { return }
        do {
            try scheduledExportQuotaRecorder(jobID)
        } catch {
            logger.error("Could not record scheduled export quota use: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func performBackgroundAPIEndpointExport(
        dates: [Date],
        settingsSnapshot: ExportSettingsSnapshot?,
        notificationOperationID: UUID?
    ) async -> ExportOrchestrator.ExportResult {
        let settings = settingsSnapshot?.makeAdvancedExportSettings() ?? AdvancedExportSettings()
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
            externalIntegrations: externalIntegrations,
            onProgress: { [weak self] processed, total in
                self?.updateNotificationExportActivity(
                    operationID: notificationOperationID,
                    phase: .capturing,
                    processedDays: processed,
                    totalDays: total,
                    message: "Preparing Apple Health data for the API endpoint…"
                )
            }
        )
    }

    @MainActor
    private func performBackgroundConnectedMacExport(
        dates: [Date],
        settingsSnapshot: ExportSettingsSnapshot?,
        quotaJobID: UUID?,
        notificationOperationID: UUID?
    ) async -> ExportOrchestrator.ExportResult {
        let sourceTimeZone = settingsSnapshot?.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:)) ?? .current
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let normalizedDates = dates.map { sourceCalendar.startOfDay(for: $0) }.sorted()
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

        let settings = settingsSnapshot?.makeAdvancedExportSettings() ?? AdvancedExportSettings()
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
        // Reuse the pending scheduled request ID so a durable Connected Mac
        // completion can be reconciled and quota-accounted after an app restart.
        let jobID = quotaJobID ?? UUID()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let providerTimeZone = settingsSnapshot?.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? settings.exportTimeZoneOverride
            ?? .current
        var providerCalendar = Calendar(identifier: .gregorian)
        providerCalendar.timeZone = providerTimeZone
        let externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
        if ConnectedAppsFeature.isEnabled,
           let scheduledExternalIntegrations,
           scheduledExternalIntegrations.connectedProviderCount > 0 {
            externalRecordFetcher = { date in
                await scheduledExternalIntegrations.fetchDailyRecords(
                    for: date,
                    calendar: providerCalendar
                )
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
                    settingsSnapshot: settingsSnapshot,
                    negotiation: negotiation,
                    externalRecordFetcher: externalRecordFetcher,
                    syncService: syncService,
                    notificationOperationID: notificationOperationID
                )
            }

            let job = try await HealthKitQueryExecutionController.withController {
                try await MacExportJobBuilder.build(
                jobID: jobID,
                sourceDeviceName: UIDevice.current.name,
                startDate: startDate,
                endDate: endDate,
                requestedDates: normalizedDates,
                settings: settings,
                healthSubfolder: VaultManager.savedHealthSubfolder(),
                destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
                frozenSettingsSnapshot: settingsSnapshot,
                fetchHealthData: { date, includeGranularData in
                    try await HealthKitManager.shared.fetchHealthData(
                        for: date,
                        includeGranularData: includeGranularData,
                        metricSelection: settings.metricSelection,
                        timeZone: providerTimeZone
                    )
                },
                fetchExternalDailyRecords: externalRecordFetcher,
                onProgress: { processed, total, date in
                    self.updateNotificationExportActivity(
                        operationID: notificationOperationID,
                        phase: .capturing,
                        processedDays: processed,
                        totalDays: total,
                        message: "Prepared \(processed) of \(total) days on iPhone."
                    )
                    syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                        jobID: jobID,
                        processedDays: processed,
                        totalDays: total,
                        currentDate: date,
                        message: "Prepared \(processed) of \(total) days on iPhone."
                    )))
                }
                )
            }

            guard syncService.canExportToConnectedMac(requiring: settings) else {
                syncService.isSyncing = false
                return scheduledFailureResult(
                    dates: normalizedDates,
                    reason: .unknown,
                    message: syncService.macExportReadinessMessage(requiring: settings)
                )
            }

            return await awaitScheduledMacExport(
                job: job,
                settings: settings,
                syncService: syncService,
                notificationOperationID: notificationOperationID
            )
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
        settingsSnapshot: ExportSettingsSnapshot?,
        negotiation: ConnectedCorpusTransferNegotiation,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        notificationOperationID: UUID?
    ) async -> ExportOrchestrator.ExportResult {
        await withCheckedContinuation { continuation in
            scheduledMacExportContexts[jobID] = ScheduledMacExportContext(
                dateRangeStart: startDate,
                dateRangeEnd: endDate,
                requestedDates: requestedDates,
                settings: settings,
                notificationOperationID: notificationOperationID,
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
                        frozenSettingsSnapshot: settingsSnapshot,
                        negotiation: negotiation,
                        healthKitManager: HealthKitManager.shared,
                        externalRecordFetcher: externalRecordFetcher,
                        syncService: syncService,
                        origin: .scheduledIPhone,
                        progress: { update in
                            self.resetScheduledMacExportTimeout(jobID: jobID)
                            let activityPhase: NotificationExportActivityTracker.Phase
                            switch update.phase {
                            case .preparing, .prepared:
                                activityPhase = .capturing
                            case .transferring, .finalizing:
                                activityPhase = .transferring
                            }
                            self.updateNotificationExportActivity(
                                operationID: notificationOperationID,
                                phase: activityPhase,
                                processedDays: update.preparedDays,
                                totalDays: update.totalDays,
                                message: update.message
                            )
                            syncService.send(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
                                jobID: jobID,
                                processedDays: update.preparedDays,
                                totalDays: update.totalDays,
                                currentDate: update.activeDate,
                                message: update.message
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
        syncService: SyncService,
        notificationOperationID: UUID?
    ) async -> ExportOrchestrator.ExportResult {
        await withCheckedContinuation { continuation in
            scheduledMacExportContexts[job.jobID] = ScheduledMacExportContext(
                dateRangeStart: job.dateRangeStart,
                dateRangeEnd: job.dateRangeEnd,
                requestedDates: job.requestedDates
                    ?? ExportOrchestrator.dateRange(from: job.dateRangeStart, to: job.dateRangeEnd),
                settings: settings,
                notificationOperationID: notificationOperationID,
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
        guard let context = scheduledMacExportContexts[progress.jobID] else { return }
        resetScheduledMacExportTimeout(jobID: progress.jobID)
        updateNotificationExportActivity(
            operationID: context.notificationOperationID,
            phase: .transferring,
            processedDays: 0,
            totalDays: 0,
            message: progress.message
        )
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
        guard payload.hasConsistentFileAccounting else { return false }
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

    /// Reconciles a durable scheduled Mac result delivered after the in-memory
    /// continuation was lost to app termination. New scheduled transports use
    /// the pending request ID as their wire job ID, making this exact and safe
    /// to replay.
    @discardableResult
    @MainActor func completeRecoveredScheduledMacExport(
        with payload: MacExportResultPayload
    ) async -> Bool {
        guard payload.hasConsistentFileAccounting else { return false }
        let request: PendingExportRequest
        do {
            guard let storedRequest = try pendingExportStore.loadAll().first(where: {
                $0.id == payload.jobID
                    && $0.source == .scheduled
                    && scheduledTarget(for: $0) == .connectedMac
            }) else { return false }
            request = storedRequest
        } catch {
            logger.error("Could not load a recovered scheduled Mac export: \(error.localizedDescription)")
            return false
        }

        guard isValidScheduledMacExportResult(payload, requestedDates: request.dates) else {
            logger.error("Recovered scheduled Mac export returned inconsistent completion data")
            return false
        }

        let settings = request.settingsSnapshot?.makeAdvancedExportSettings()
            ?? AdvancedExportSettings()
        let result = scheduledMacExportResult(from: payload, settings: settings)
        recordScheduledExportQuotaUseIfNeeded(for: result, jobID: request.id)

        let range = scheduledExportHistoryRange(for: request)
        await processAutomaticScheduledExportResult(
            result,
            pendingRequest: request,
            target: .connectedMac,
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            fallbackDaysToExport: range.totalCount,
            scheduledFireDate: request.scheduledFireDate ?? now()
        )
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
        guard payload.hasConsistentFileAccounting,
              payload.totalCount == requestedDates.count,
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
        settings _: AdvancedExportSettings
    ) -> ExportOrchestrator.ExportResult {
        ExportOrchestrator.ExportResult(macExportPayload: payload)
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
        guard schedule.isEnabled || hasEnabledProfileEntries else {
            logger.info("Schedule disabled, skipping notification-triggered export")
            notificationExportResult = NotificationExportResult(
                status: .failure(reason: String(localized: "Scheduling is disabled", comment: "Error message when scheduling is disabled")),
                timestamp: now()
            )
            return
        }
        guard schedule.isEnabled else {
            // Profile entries own scheduling: honor the tap with due profile
            // work instead of the legacy window math.
            logger.info("Notification-triggered export running due profile occurrences (legacy schedule off)")
            await runDueProfileOccurrences()
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
        let notificationOperationID = pendingRequest?.id ?? UUID()

        beginNotificationExportActivity(
            operationID: notificationOperationID,
            source: .scheduled,
            dates: dates,
            target: target
        )
        cancelPendingExportFallbackNotification(for: pendingRequest)
        let result = await runScheduledExport(
            dates: dates,
            target: target,
            settingsSnapshot: pendingRequest?.settingsSnapshot,
            quotaJobID: notificationOperationID,
            notificationOperationID: notificationOperationID
        )
        let completion = await completePendingScheduledExport(pendingRequest, result: result)
        let didCompleteRequest = completion == .clearedAfterSuccess
            || (pendingRequest == nil && result.didCompleteAllRequestedDates)

        if didCompleteRequest {
            var updatedSchedule = schedule
            updatedSchedule.updateLastExport(at: pendingRequest?.scheduledFireDate ?? currentDate)
            schedule = updatedSchedule
        }

        if result.totalCount > 0 {
            if !isExportLimitResult(result) {
                ExportOrchestrator.recordResult(
                    result, source: .scheduled,
                    dateRangeStart: startDate, dateRangeEnd: endDate,
                    targetLabel: targetLabel,
                    exportTarget: target,
                    appleExportEnginePin: pendingRequest?.settingsSnapshot?.appleExportEnginePin
                )
            }
            notificationExportResult = makeNotificationExportResult(from: result)
        } else {
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
        guard schedule.isEnabled || hasEnabledProfileEntries else {
            logger.info("Silent push received but scheduling is disabled")
            return
        }
        // Dual-mode: wake entry evaluation first so an enabled legacy schedule
        // does not starve profile occurrences (and vice versa), then fall
        // through to the legacy occurrence handling below.
        if hasEnabledProfileEntries {
            await runDueProfileOccurrences()
        }
        guard schedule.isEnabled else { return }
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
        let result = await runScheduledExport(
            dates: dates,
            target: target,
            settingsSnapshot: pendingRequest?.settingsSnapshot,
            quotaJobID: pendingRequest?.id
        )

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
        let currentDate = now()
        if schedule.target == .connectedMac, !scheduledConnectedMacHandshakeComplete {
            logger.info("Catch-up deferred until the Connected Mac handshake completes")
            return NotificationExportResult(status: .noExportNeeded, timestamp: currentDate)
        }

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
            settingsSnapshot: await makeSettingsSnapshotForNewScheduledOperation(target: target),
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

        let result = await runScheduledExport(
            dates: pendingRequest.dates,
            target: target,
            settingsSnapshot: pendingRequest.settingsSnapshot,
            quotaJobID: pendingRequest.id
        )
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
        if vaultManager.requiresVaultReselection {
            return scheduledFailureResult(
                dates: dates,
                reason: .accessDenied,
                message: VaultManager.destinationChangedMessage,
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }
        guard vaultManager.hasVaultAccess else {
            let reason: ExportFailureReason = vaultManager.hasSavedVaultFolder ? .accessDenied : .noVaultSelected
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: reason) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }

        guard let accessLease = vaultManager.beginVaultAccess() else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .accessDenied) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }
        defer { accessLease.stop() }

        return await ExportOrchestrator.exportDatesBackground(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: advancedSettings,
            externalIntegrations: scheduledExternalIntegrations
        )
    }

    // MARK: - Background Task Execution

    /// Handles background task execution
    // MARK: - Phase 3 profile scheduling runtime

    /// True when any scheduled entry is enabled; background triggers use the
    /// per-profile evaluator instead of the legacy single schedule.
    @MainActor var hasEnabledProfileEntries: Bool {
        !scheduledEntryStore.enabledEntries().isEmpty
    }

    /// Production destination adoption: writes the profile's folder binding
    /// into the persisted vault keys (a fresh `VaultManager()` resolves them
    /// during the run) and loads the profile's API endpoint into
    /// `APIExportSettings`. Nil adopts the active profile's destinations,
    /// restoring the state the UI expects after a profile run.
    @MainActor private static func defaultAdoptProfileDestinations(_ profile: ExportProfile?) {
        let destinationStore = ProfileDestinationStore()
        if let profile,
           let bindingID = profile.folderVaultID,
           let destination = destinationStore.vault(id: bindingID) {
            VaultManager().adoptPersistedVault(
                bookmarkData: destination.bookmarkData,
                standardizedPath: destination.standardizedPath,
                displayName: destination.name
            )
        }
        if let profile,
           let endpointID = profile.apiEndpointID,
           let endpoint = destinationStore.apiEndpoint(id: endpointID) {
            let apiSettings = APIExportSettings()
            apiSettings.endpointURLString = endpoint.endpointURLString
            apiSettings.bearerToken = destinationStore.token(for: endpoint.id) ?? ""
        }
    }

    /// Per-profile occurrence in-flight key. Unlike the legacy fire-minute
    /// key, this includes the profile so two profiles at the same minute run
    /// independently.
    @MainActor private func profileOccurrenceKey(
        profileID: UUID,
        kind: ScheduledExportKind,
        fireDate: Date
    ) -> String {
        let minute = scheduledOccurrenceKey(for: fireDate).timeIntervalSince1970
        return "\(profileID.uuidString)|\(kind.rawValue)|\(Int(minute))"
    }

    /// Evaluates every enabled entry and runs each due occurrence. The
    /// coalesced wake-up's single decision point: one BGTask wake-up or
    /// HealthKit delivery calls this. Local-folder runs serialize on the
    /// folder gate (persisted vault state is global); all other targets run
    /// concurrently.
    @MainActor func runDueProfileOccurrences() async {
        let due = scheduledEntryStore.dueOccurrences(now: now())
        guard !due.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for occurrence in due {
                group.addTask { [weak self] in
                    await self?.runProfileOccurrence(occurrence)
                }
            }
        }

        // Re-arm the wake-up for the next occurrence across all entries.
        // cancelPendingFallbacks:false mirrors the legacy run body: the runs
        // above may have just preserved retry requests (device-locked or
        // partial outcomes) whose fallback windows are still open, and the
        // bulk cancel would delete the recovery surface milliseconds after
        // it was advertised.
        if systemSideEffectsEnabled, !TestMode.isUITesting {
            scheduleBackgroundTask(cancelPendingFallbacks: false)
        }
    }

    /// Legacy-path companion for wake-ups (phase 3 dual-mode): runs the legacy
    /// schedule's single due occurrence when one is due. Wake-ups run entries
    /// first (`runDueProfileOccurrences`) and then this, so an enabled legacy
    /// schedule keeps auto-running beside enabled profile entries instead of
    /// arming fallback notifications only a manual tap could satisfy.
    ///
    /// Consolidates the former `handleBackgroundTask` and
    /// `handleHealthKitBackgroundDelivery` bodies (including the delivery
    /// path's already-exported guard, which is a safe no-op for the BG-task
    /// path). `onExpirationArmed` receives the expiration closure right before
    /// the export starts so the BG-task wrapper can install it on its task.
    enum LegacyOccurrenceOutcome {
        /// Nothing was due, already exported, or deduped against an in-flight run.
        case skipped
        /// The export ran; carries `didCompleteAllRequestedDates`.
        case ran(completed: Bool)
    }

    @MainActor private func runDueLegacyOccurrence(
        onExpirationArmed: (@escaping () -> Void) -> Void = { _ in }
    ) async -> LegacyOccurrenceOutcome {
        guard schedule.isEnabled else { return .skipped }

        let currentDate = now()
        guard let occurrence = ScheduleDateMath.dueScheduledOccurrences(
            schedule: schedule,
            now: currentDate
        ).first else {
            logger.info("Wake-up skipped: no scheduled occurrence is due")
            scheduleBackgroundTask()
            return .skipped
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
                logger.info("Wake-up skipped: no eligible export dates")
                return .skipped
            }

            if let lastExport = schedule.lastExportDate {
                let lastExportDay = calendar.startOfDay(for: lastExport)
                let lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: lastExportDay) ?? lastExportDay
                if lastExportedDataDay >= eligibleEndDate {
                    logger.info("Scheduled occurrence already exported, skipping")
                    return .skipped
                }
            }
        }

        guard beginScheduledOccurrenceExport(fireDate: fireDate) else { return .skipped }
        defer { finishScheduledOccurrenceExport(fireDate: fireDate) }

        let pendingRequest = await preparePendingScheduledExport(fireDate: fireDate, kind: kind)
        let range = pendingRequest.map(scheduledExportHistoryRange) ?? fallbackScheduledExportHistoryRange(kind: kind)
        let dates = pendingRequest?.dates ?? fallbackScheduledExportDates(kind: kind)
        let target = scheduledTarget(for: pendingRequest)
        cancelPendingExportFallbackNotification(for: pendingRequest)

        // Schedule the next task without clearing the pending occurrence this
        // run is about to fulfill (preserved retries keep their fallbacks).
        scheduleBackgroundTask(cancelPendingFallbacks: false)

        onExpirationArmed({ [weak self] in
            guard let self else { return }
            self.logger.warning("Background task expired")
            Task { @MainActor in
                await self.sendExportNotification(success: false, daysExported: 0, failureReason: .backgroundTaskExpired)
                ExportHistoryManager.shared.recordFailure(
                    source: .scheduled,
                    dateRangeStart: range.start,
                    dateRangeEnd: range.end,
                    reason: .backgroundTaskExpired,
                    totalCount: range.totalCount,
                    exportTarget: target,
                    appleExportEnginePin: pendingRequest?.settingsSnapshot?.appleExportEnginePin
                )
            }
        })

        let result = await runScheduledExport(
            dates: dates,
            target: target,
            settingsSnapshot: pendingRequest?.settingsSnapshot,
            quotaJobID: pendingRequest?.id
        )

        await processAutomaticScheduledExportResult(
            result,
            pendingRequest: pendingRequest,
            target: target,
            dateRangeStart: range.start,
            dateRangeEnd: range.end,
            fallbackDaysToExport: range.totalCount,
            scheduledFireDate: fireDate
        )

        return .ran(completed: result.didCompleteAllRequestedDates)
    }

    /// MainActor body executed under the folder gate: adopt destinations,
    /// run, restore. Called from the sendable gate closure with `await`.
    @MainActor private func runGatedFolderProfileExport(
        profile: ExportProfile,
        dates: [Date],
        target: ExportTargetSelection,
        settings: ExportSettingsSnapshot,
        quotaJobID: UUID?,
        notificationOperationID: UUID?
    ) async -> ExportOrchestrator.ExportResult {
        scheduledProfileDestinationAdopter(profile)
        defer {
            scheduledProfileDestinationAdopter(scheduledProfileStore.activeProfile)
        }
        return await runScheduledExport(
            dates: dates,
            target: target,
            settingsSnapshot: settings,
            quotaJobID: quotaJobID,
            notificationOperationID: notificationOperationID
        )
    }

    /// Runs one profile-scoped export with destination adoption and restore.
    /// Local-folder runs serialize on the folder gate because adopted vault
    /// state is process-global; other targets run without the gate.
    @MainActor private func runProfileScopedExport(
        profile: ExportProfile,
        dates: [Date],
        target: ExportTargetSelection,
        settings: ExportSettingsSnapshot,
        quotaJobID: UUID?,
        notificationOperationID: UUID? = nil
    ) async -> ExportOrchestrator.ExportResult {
        if target == .localIPhoneFolder {
            return await profileFolderRunGate.withPermit {
                await self.runGatedFolderProfileExport(
                    profile: profile,
                    dates: dates,
                    target: target,
                    settings: settings,
                    quotaJobID: quotaJobID,
                    notificationOperationID: notificationOperationID
                )
            }
        }

        scheduledProfileDestinationAdopter(profile)
        defer {
            scheduledProfileDestinationAdopter(scheduledProfileStore.activeProfile)
        }
        return await runScheduledExport(
            dates: dates,
            target: target,
            settingsSnapshot: settings,
            quotaJobID: quotaJobID,
            notificationOperationID: notificationOperationID
        )
    }

    @MainActor private func runProfileOccurrence(
        _ due: ScheduledExportEntryStore.DueEntryOccurrence
    ) async {
        guard beginProfileOccurrenceExport(
            profileID: due.profileID,
            kind: due.kind,
            fireDate: due.fireDate
        ) else { return }
        defer {
            finishProfileOccurrenceExport(
                profileID: due.profileID,
                kind: due.kind,
                fireDate: due.fireDate
            )
        }

        guard let entry = scheduledEntryStore.entry(id: due.entryID) else { return }
        guard let profile = scheduledProfileStore.profile(id: due.profileID) else {
            logger.error("Scheduled entry references a missing profile; disabling entry")
            scheduledEntryStore.update(profileID: due.profileID) { $0.isEnabled = false }
            return
        }

        let dates: [Date]
        switch due.kind {
        case .completedDay:
            dates = due.exportDates.isEmpty
                ? ScheduleDateMath.scheduledExportDates(
                    schedule: entry.dateMathProjection,
                    fireDate: due.fireDate
                )
                : due.exportDates
        case .todayRefresh:
            dates = [Calendar.current.startOfDay(for: now())]
        }

        let context = ScheduledExportCoordinator.ScheduledProfileRequestContext(
            profileID: profile.id,
            profileName: profile.name,
            target: profile.target,
            settings: profile.settings
        )
        let pendingRequest: PendingExportRequest?
        do {
            pendingRequest = try await scheduledExportCoordinator.preparePendingScheduledExport(
                schedule: entry.dateMathProjection,
                fireDate: due.fireDate,
                kind: due.kind,
                profile: context
            )
        } catch {
            logger.error("Failed to prepare profile scheduled export: \(error.localizedDescription)")
            pendingRequest = nil
        }
        cancelPendingExportFallbackNotification(for: pendingRequest)

        let target = context.target
        let result = await runProfileScopedExport(
            profile: profile,
            dates: dates,
            target: target,
            settings: context.settings,
            quotaJobID: pendingRequest?.id
        )

        if result.didCompleteAllRequestedDates {
            scheduledEntryStore.recordSuccess(
                profileID: due.profileID,
                kind: due.kind,
                occurrenceDate: due.fireDate
            )
        }

        let completion = await completePendingScheduledExport(pendingRequest, result: result)
        _ = completion

        let rangeStart = dates.first ?? due.fireDate
        let rangeEnd = dates.last ?? due.fireDate
        if result.successCount > 0 || result.dailyNoteSkipCount > 0 {
            if result.didCompleteAllRequestedDates {
                await sendExportNotification(
                    success: true,
                    daysExported: result.successCount,
                    dailyNoteUpdateCount: result.dailyNoteUpdateCount,
                    dailyNoteSkipCount: result.dailyNoteSkipCount
                )
            }
            if !isExportLimitResult(result) {
                ExportOrchestrator.recordResult(
                    result,
                    source: .scheduled,
                    dateRangeStart: rangeStart,
                    dateRangeEnd: rangeEnd,
                    targetLabel: scheduledTargetLabel(for: target),
                    exportTarget: target,
                    appleExportEnginePin: context.settings.appleExportEnginePin,
                    profileName: profile.name
                )
            }
        } else if result.totalCount > 0, !isExportLimitResult(result) {
            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: rangeStart,
                dateRangeEnd: rangeEnd,
                targetLabel: scheduledTargetLabel(for: target),
                exportTarget: target,
                appleExportEnginePin: context.settings.appleExportEnginePin,
                profileName: profile.name
            )
        }
    }

    @MainActor private func handleBackgroundTask(_ task: BGProcessingTask) async {
        logger.info("Background processing task started")

        // Phase 3 dual-mode: entries first when enabled, then the legacy
        // schedule's due occurrence, so both run when both are enabled.
        if hasEnabledProfileEntries {
            // Profile legs get a minimal expiration record so an expiry while
            // they run still logs and history-records the interruption (the
            // legacy leg installs its richer handler via onExpirationArmed).
            task.expirationHandler = { [weak self] in
                guard let self else { return }
                self.logger.warning("Background task expired during profile occurrences")
                Task { @MainActor in
                    ExportHistoryManager.shared.recordFailure(
                        source: .scheduled,
                        dateRangeStart: Date(),
                        dateRangeEnd: Date(),
                        reason: .backgroundTaskExpired,
                        totalCount: 0,
                        exportTarget: nil
                    )
                }
            }
            await runDueProfileOccurrences()
        }

        let outcome = await runDueLegacyOccurrence { expirationHandler in
            task.expirationHandler = expirationHandler
        }

        switch outcome {
        case .skipped:
            task.setTaskCompleted(success: true)
        case .ran(let completed):
            task.setTaskCompleted(success: completed)
        }
    }

    /// Performs the actual health data export in the background using shared ExportOrchestrator
    private func performBackgroundExport(
        dates: [Date],
        settingsSnapshot: ExportSettingsSnapshot?,
        notificationOperationID: UUID?
    ) async -> ExportOrchestrator.ExportResult {
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
        let advancedSettings = settingsSnapshot?.makeAdvancedExportSettings()
            ?? AdvancedExportSettings()

        // Check if vault is configured and currently accessible.
        vaultManager.refreshVaultAccess()
        if vaultManager.requiresVaultReselection {
            logger.error("Scheduled export blocked because the saved destination changed")
            return scheduledFailureResult(
                dates: dates,
                reason: .accessDenied,
                message: VaultManager.destinationChangedMessage,
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }
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

        logger.info("Vault access confirmed")
        logger.info("Exporting \(dates.count) days of data")

        guard let accessLease = vaultManager.beginVaultAccess() else {
            logger.error("Could not start vault security scope in background")
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .accessDenied) },
                formatsPerDate: advancedSettings.looseFormatsPerDate
            )
        }
        defer { accessLease.stop() }

        let result = await ExportOrchestrator.exportDatesBackground(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: advancedSettings,
            frozenSettingsSnapshot: settingsSnapshot,
            operationSurface: settingsSnapshot == nil
                ? .legacyOnly
                : .localVaultRangeWithoutSideEffects,
            externalIntegrations: scheduledExternalIntegrations,
            onProgress: { [weak self] processed, total, date in
                self?.updateNotificationExportActivity(
                    operationID: notificationOperationID,
                    phase: .capturing,
                    processedDays: processed,
                    totalDays: total,
                    message: "Exporting \(date) to the iPhone folder…"
                )
            }
        )

        logger.info("Background export completed. Success: \(result.successCount)/\(result.totalCount)")
        return result
    }

    @MainActor
    private func preparePendingScheduledExport(
        fireDate: Date? = nil,
        kind: ScheduledExportKind = .completedDay,
        entry: ScheduledExportEntry? = nil
    ) async -> PendingExportRequest? {
        let resolvedFireDate = fireDate
            ?? ScheduleDateMath.latestScheduledOccurrenceDate(schedule: schedule, kind: kind, now: now())
            ?? now()

        // Profile entries arm their fallback request with the profile's own
        // context so a notification tap retries the profile's exact dates
        // against its destinations. A legacy-shaped request could never run
        // from a tap while the legacy schedule is off ("Scheduling is
        // disabled"), even though the armed occurrence belonged to the entry.
        let profileContext: ScheduledExportCoordinator.ScheduledProfileRequestContext?
        if let entry {
            guard let profile = scheduledProfileStore.profile(id: entry.profileID) else {
                logger.error("Cannot arm profile fallback: entry \(entry.profileID.uuidString) references a missing profile")
                return nil
            }
            profileContext = ScheduledExportCoordinator.ScheduledProfileRequestContext(
                profileID: profile.id,
                profileName: profile.name,
                target: profile.target,
                settings: profile.settings
            )
        } else {
            profileContext = nil
        }

        do {
            return try await scheduledExportCoordinator.preparePendingScheduledExport(
                schedule: entry?.dateMathProjection ?? schedule,
                fireDate: resolvedFireDate,
                kind: kind,
                profile: profileContext,
                makeSettingsSnapshot: {
                    await makeSettingsSnapshotForNewScheduledOperation(
                        target: profileContext?.target ?? schedule.target
                    )
                }
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
            // The stored request stays as this run's preserved retry; mark it
            // attempted so a later bulk fallback cancel cannot destroy it.
            markPendingExportRequestAttempted(request)
            return nil
        }
    }

    /// Re-persists a pending request with `attemptedAt` set so bulk fallback
    /// cancellation classifies it as a preserved retry rather than an armed
    /// fallback. Used on paths that preserve the request without going
    /// through `ScheduledExportCoordinator`'s retry creation.
    @MainActor private func markPendingExportRequestAttempted(_ request: PendingExportRequest) {
        guard request.attemptedAt == nil else { return }
        let attempted = request.markingAttempted(at: now())
        do {
            try pendingExportStore.upsert(attempted)
        } catch {
            logger.error("Failed to mark pending export attempted: \(error.localizedDescription)")
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
                exportTarget: target,
                appleExportEnginePin: pendingRequest?.settingsSnapshot?.appleExportEnginePin
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

            if !isExportLimitResult(result) {
                ExportOrchestrator.recordResult(
                    result,
                    source: .scheduled,
                    dateRangeStart: dateRangeStart,
                    dateRangeEnd: dateRangeEnd,
                    targetLabel: targetLabel,
                    exportTarget: target,
                    appleExportEnginePin: pendingRequest?.settingsSnapshot?.appleExportEnginePin
                )
            }
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
            content.title = errorDetails == Self.exportLimitReachedMessage
                ? String(localized: "Free Export Limit Reached", comment: "Notification title when scheduled export quota is exhausted")
                : String(localized: "Export Failed", comment: "Notification title for failure")
            var body: String
            if errorDetails == Self.exportLimitReachedMessage {
                body = Self.exportLimitReachedMessage
            } else if errorDetails == VaultManager.destinationChangedMessage {
                body = String(
                    localized: "The saved export folder changed. Open Health.md and re-select the intended folder before the next export.",
                    comment: "Scheduled export notification when the saved folder resolves elsewhere"
                )
            } else if let reason = failureReason {
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

    /// Sends a "tap to export" reminder notification when export fails due to device lock
    @MainActor
    private func sendExportReminderNotification() async {
        let request = await makePendingExportRequest(
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

    private func schedulePendingExportFallbackNotification(
        for nextRunDate: Date,
        kind: ScheduledExportKind = .completedDay,
        entry: ScheduledExportEntry? = nil
    ) {
        Task {
            if await preparePendingScheduledExport(fireDate: nextRunDate, kind: kind, entry: entry) != nil {
                logger.info("Pending export fallback notification scheduled for \(nextRunDate)")
            } else {
                logger.error("Failed to schedule pending export fallback notification")
            }
        }
    }

    @MainActor private func cancelScheduledPendingExportFallbackNotifications() {
        // Only still-armed fallbacks are stale when automation is re-armed or
        // disabled: their occurrence has not fired yet, so the request will be
        // re-armed for whatever occurrence comes next. A request that a run
        // attempted is a preserved retry — deleting it would destroy the
        // recovery surface the run just advertised, regardless of how recently
        // it was preserved. The fallback-window check only classifies
        // pre-marker requests persisted by older builds.
        let fallbackWindow = exportNotificationScheduler.fallbackDelay
        cancelScheduledPendingExportFallbackNotifications(matching: { request in
            guard request.attemptedAt == nil,
                  let fireDate = request.scheduledFireDate else { return false }
            return fireDate.addingTimeInterval(fallbackWindow) > now()
        })
    }

    @MainActor private func cancelScheduledPendingExportFallbackNotifications(matching shouldCancel: (PendingExportRequest) -> Bool) {
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

    private func makePendingExportRequest(scheduledFireDate: Date?) async -> PendingExportRequest {
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
            exportTarget: schedule.target,
            settingsSnapshot: await makeSettingsSnapshotForNewScheduledOperation(
                target: schedule.target
            )
        )
    }

    // MARK: - Helper Methods

    /// Calculates the next scheduled run date based on current settings.
    /// The next plan pairs the winning occurrence with its owning scheduled
    /// entry so the fallback notification armed for it is profile-scoped
    /// (phase 3): a legacy-shaped fallback request can never run from a
    /// notification tap while the legacy schedule is off.
    private struct NextRunPlan {
        let occurrence: ScheduleDateMath.DueScheduledOccurrence
        /// Owning enabled entry when the next occurrence belongs to a
        /// profile; nil for the legacy schedule.
        let entry: ScheduledExportEntry?
    }

    private func calculateNextRunPlan() -> NextRunPlan? {
        // Phase 3: the coalesced wake-up arms for the earliest next occurrence
        // across every enabled entry, falling back to the legacy schedule.
        // Fresh read: the UI saves schedule edits through its own store
        // instance, and the next-occurrence projection must observe them
        // immediately (next-export status, BGTask begin date, worker sync).
        let entryPlans: [NextRunPlan] = scheduledEntryStore.enabledEntries()
            .flatMap { entry in
                ScheduleDateMath.nextScheduledOccurrences(schedule: entry.dateMathProjection, now: now())
                    .map { NextRunPlan(occurrence: $0, entry: entry) }
            }
        if hasEnabledProfileEntries {
            let legacy: [NextRunPlan] = schedule.isEnabled
                ? ScheduleDateMath.nextScheduledOccurrences(schedule: schedule, now: now())
                    .map { NextRunPlan(occurrence: $0, entry: nil) }
                : []
            return (entryPlans + legacy).min { $0.occurrence.fireDate < $1.occurrence.fireDate }
        }
        return ScheduleDateMath.nextScheduledOccurrences(schedule: schedule, now: now())
            .map { NextRunPlan(occurrence: $0, entry: nil) }
            .first
    }

    private func calculateNextRunDate() -> Date {
        calculateNextRunPlan()?.occurrence.fireDate
            ?? now().addingTimeInterval(3600)
    }

    /// Returns a human-readable string describing the next scheduled export.
    @MainActor func getNextExportDescription() -> String? {
        guard isSchedulingActive else { return nil }

        let nextDate = calculateNextRunDate()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: nextDate)
    }
}
