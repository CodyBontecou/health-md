import HealthMdConnectionCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import WidgetKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if !TestMode.suppressesRuntimeServices {
            Task { @MainActor in
                await SchedulingManager.shared.waitForScheduledExportDependencies()
                await SchedulingManager.shared.drainPendingExportsIfNeeded(trigger: .appActive)
                await SchedulingManager.shared.performCatchUpExportIfNeeded()
                IPhoneCorpusExportRecoveryManager.shared.applicationDidBecomeActive()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: - Remote notifications (server-driven scheduled exports)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrationManager.shared.submitDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on simulators (no APNs). Real failures surface on the server
        // when no push lands; we don't bubble up further here.
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard userInfo["type"] as? String == "scheduled-export" else {
            completionHandler(.noData)
            return
        }
        let fireDate = scheduledExportFireDate(from: userInfo)
        let kind = scheduledExportKind(from: userInfo)
        Task { @MainActor in
            await SchedulingManager.shared.performSilentPushExport(fireDate: fireDate, kind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            completionHandler(.newData)
        }
    }

    private func scheduledExportKind(from userInfo: [AnyHashable: Any]) -> ScheduledExportKind {
        let keys = ["scheduleKind", "schedule_kind", "kind"]
        for key in keys {
            guard let value = userInfo[key] as? String else { continue }
            if let kind = ScheduledExportKind(rawValue: value) { return kind }
            if value == "completedDay" { return .completedDay }
            if value == "todayRefresh" { return .todayRefresh }
        }
        return .completedDay
    }

    private func scheduledExportFireDate(from userInfo: [AnyHashable: Any]) -> Date? {
        let stringKeys = ["fireAt", "fire_at", "scheduledFireDate", "scheduled_fire_date"]
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for key in stringKeys {
            guard let value = userInfo[key] as? String else { continue }
            if let date = formatter.date(from: value) ?? fractionalFormatter.date(from: value) {
                return date
            }
        }

        let numericKeys = ["fireAt", "fire_at", "scheduledFireDate", "scheduled_fire_date"]
        for key in numericKeys {
            if let value = userInfo[key] as? TimeInterval {
                return Date(timeIntervalSince1970: value)
            }
            if let value = userInfo[key] as? NSNumber {
                return Date(timeIntervalSince1970: value.doubleValue)
            }
        }

        return nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let pendingExportPayload = PendingExportNotificationPayload(userInfo: request.content.userInfo)

        if let pendingExportPayload = pendingExportPayload {
            Task { @MainActor in
                await SchedulingManager.shared.waitForScheduledExportDependencies()
                await SchedulingManager.shared.performNotificationTriggeredExport(payload: pendingExportPayload)
                completionHandler()
            }
        } else if request.identifier.contains("export.reminder") {
            Task { @MainActor in
                await SchedulingManager.shared.waitForScheduledExportDependencies()
                await SchedulingManager.shared.performNotificationTriggeredExport()
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    // Allow notifications to show while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct HealthMdApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var syncService = SyncService()
    @StateObject private var directCLIService = IPhoneDirectCLIService()
    @StateObject private var cliExportActivity = CLIExportActivityTracker.shared
    @StateObject private var notificationExportActivity = NotificationExportActivityTracker.shared
    @StateObject private var externalIntegrationManager = ExternalIntegrationManager()
    @StateObject private var iPhoneExportRequestHandler = IPhoneExportRequestHandler()
    @StateObject private var corpusRecoveryManager = IPhoneCorpusExportRecoveryManager.shared
    #if DEBUG
    @StateObject private var exportPerformanceLab = IPhoneExportPerformanceLabCoordinator()
    #endif
    private let pricingAnalyticsClient = PricingAnalyticsClient.shared

    init() {
        configureTransparentTabBarAppearance()

        // Register defaults for local Mac destination compatibility.
        UserDefaults.standard.register(defaults: [
            "autoSyncAfterExport": false
        ])

        if TestMode.isUnitTesting {
            return
        }

        #if DEBUG
        if MarketingCapture.isIAPReviewActive {
            configureIAPReviewMode()
            return
        }

        if MarketingCapture.isActive {
            configureMarketingMode()
            return
        }
        #endif

        if TestMode.isUITesting {
            configureTestMode()
            return
        }

        // Register background tasks at app launch - must happen before app finishes launching
        Task { @MainActor in
            SchedulingManager.shared.registerBackgroundTask()

            // If scheduling is enabled, set up HealthKit background delivery.
            // Notification permission is requested when the user enables a schedule.
            if SchedulingManager.shared.schedule.isEnabled {
                await HealthKitManager.shared.enableBackgroundDelivery()
                HealthKitManager.shared.setupObserverQueries()
            }
        }
    }

    private func configureTransparentTabBarAppearance() {
        // Intentional: the bottom tab bar should remain transparent in both
        // light and dark mode. UIKit's default/material tab bar background can
        // appear as a grey footer, especially in light mode, so keep every
        // appearance slot clear and shadowless.
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.backgroundColor = .clear
        tabBar.isTranslucent = true
    }

    #if DEBUG
    /// Configure the app for marketing screenshot capture.
    /// Sets up the same deterministic state as test mode so screens look populated.
    private func configureMarketingMode() {
        Task { @MainActor in
            healthKitManager.isAuthorized = true
            PurchaseManager.shared.setUnlocked(true)
            UserDefaults.standard.set(true, forKey: "syncEnabled")
            syncService.connectionState = .connected
            syncService.connectedPeerName = "Test Mac"
            let capabilities = SyncPeerCapabilities.current(platform: .macOS)
            syncService.remoteCapabilities = capabilities
            syncService.macDestinationStatus = MacDestinationStatus(
                isConnected: true,
                isReadyForExports: true,
                destinationFolderSelected: true,
                folderAccessHealthy: true,
                destinationDisplayName: "Test Mac",
                destinationPathForDisplay: "/Users/cody/Health",
                lastError: nil,
                activeJobID: nil,
                capabilities: capabilities
            )
            var schedule = schedulingManager.schedule
            schedule.isEnabled = true
            schedulingManager.schedule = schedule
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(true, forKey: "discordPromoDismissed")
        }
    }

    /// Configure only the state needed to present the paywall for App Store
    /// Connect IAP review screenshots. Unlike the broader marketing capture,
    /// this keeps the purchase locked so the screenshot reflects the real gate.
    private func configureIAPReviewMode() {
        Task { @MainActor in
            healthKitManager.isAuthorized = true
            PurchaseManager.shared.setFreeExportsUsed(PurchaseManager.freeExportLimit)
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(true, forKey: "discordPromoDismissed")
        }
    }
    #endif

    /// Configure deterministic test state from launch environment variables.
    /// Skips all real HealthKit, StoreKit, and network interactions.
    private func configureTestMode() {
        if TestMode.showsOnboarding {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
        if TestMode.showsReleaseNotes {
            HealthMdReleaseNotes.resetSeenVersionForUITesting()
        }

        // All managers are @MainActor — set state in Task
        Task { @MainActor in
            // HealthKit: set authorization state without showing dialogs
            healthKitManager.isAuthorized = TestMode.healthAuthorized
            UserDefaults.standard.set(ExportTargetSelection.localIPhoneFolder.rawValue, forKey: ExportTargetSelection.storageKey)

            // Purchase: set unlock/quota state without StoreKit
            if TestMode.purchaseUnlocked {
                PurchaseManager.shared.setUnlocked(true)
            }
            PurchaseManager.shared.setFreeExportsUsed(TestMode.freeExportsUsed)

            // Sync: set connection/Mac-export state without Multipeer.
            syncService.configureForUITestingIfNeeded()

            // Schedule: set enabled state
            if TestMode.scheduleEnabled {
                var schedule = schedulingManager.schedule
                schedule.isEnabled = true
                schedulingManager.schedule = schedule
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    iPadContentView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(schedulingManager)
            .environmentObject(healthKitManager)
            .environmentObject(syncService)
            .environmentObject(directCLIService)
            .environmentObject(externalIntegrationManager)
            .environmentObject(corpusRecoveryManager)
            .safeAreaInset(edge: .top, spacing: 0) {
                Group {
                    if let snapshot = notificationExportActivity.snapshot {
                        NotificationExportActivityBanner(snapshot: snapshot)
                    } else if let snapshot = cliExportActivity.snapshot {
                        CLIExportActivityBanner(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.s2)
                .padding(.bottom, Spacing.s1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            .animation(AnimationTimings.standard, value: notificationExportActivity.snapshot?.operationID)
            .animation(AnimationTimings.standard, value: cliExportActivity.snapshot?.jobID)
            #if DEBUG
            .sheet(isPresented: $exportPerformanceLab.isConfirmationPresented) {
                IPhoneExportPerformanceLabConfirmationView(
                    coordinator: exportPerformanceLab,
                    start: {
                        let externalIntegrations: ExternalIntegrationDailyRecordProviding? =
                            ConnectedAppsFeature.isEnabled ? externalIntegrationManager : nil
                        exportPerformanceLab.start(
                            healthKitManager: healthKitManager,
                            syncService: syncService,
                            externalIntegrations: externalIntegrations
                        )
                    }
                )
            }
            .alert(
                "Configure Private Export Sink?",
                isPresented: $exportPerformanceLab.isAPISetupConfirmationPresented
            ) {
                Button("Cancel", role: .cancel) {
                    exportPerformanceLab.completeInitialAPISetup(approved: false)
                }
                Button("Configure") {
                    exportPerformanceLab.completeInitialAPISetup(approved: true)
                }
            } message: {
                Text(exportPerformanceLab.apiSetupSummary)
            }
            .fileImporter(
                isPresented: $exportPerformanceLab.isLocalSetupPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                exportPerformanceLab.completeLocalSetup(result)
            }
            #endif
            .keepsScreenAwake(
                while: cliExportActivity.keepsScreenAwake
                    || notificationExportActivity.keepsScreenAwake
            )
            .task {
                guard !TestMode.isUnitTesting else { return }
                CLIExportLiveActivityController.shared.reconcile(with: cliExportActivity.snapshot)
                corpusRecoveryManager.configure(
                    syncService: syncService,
                    healthKitManager: healthKitManager,
                    externalIntegrations: externalIntegrationManager
                )
                setupSyncMessageHandler()
                corpusRecoveryManager.applicationDidBecomeActive()
                directCLIService.exportRequestHandler = { request, binding, negotiation, channel, protocolAuthority in
                    await IPhoneDirectExportCoordinator.shared.handle(
                        request,
                        peerBinding: binding,
                        negotiation: negotiation,
                        channel: channel,
                        protocolAuthority: protocolAuthority,
                        healthKitManager: healthKitManager,
                        externalIntegrations: externalIntegrationManager
                    )
                }
                directCLIService.cancelHandler = { jobID in
                    IPhoneDirectExportCoordinator.shared.cancel(jobID: jobID)
                }
                directCLIService.queryRequestHandler = { request, channel in
                    await IPhoneDirectQueryCoordinator.shared.handle(
                        request,
                        channel: channel,
                        healthKitManager: healthKitManager
                    )
                }
                directCLIService.statusProvider = {
                    await PurchaseManager.shared.refreshStatus()
                    let protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
                    let exportInProgress = IPhoneDirectExportCoordinator.shared.isExporting
                    let queryInProgress = IPhoneDirectQueryCoordinator.shared.isQuerying
                    let canStartOperation = protectedDataAvailable
                        && healthKitManager.isAuthorized
                        && PurchaseManager.shared.canExport
                        && !exportInProgress
                        && !queryInProgress
                    let message: String
                    if !protectedDataAvailable {
                        message = "Unlock iPhone before starting a direct export."
                    } else if !healthKitManager.isAuthorized {
                        message = "Authorize Health access before starting a direct export."
                    } else if !PurchaseManager.shared.canExport {
                        message = "Export limit reached. Unlock Full Access to continue."
                    } else if exportInProgress || queryInProgress {
                        message = "Another direct operation is already active."
                    } else {
                        message = "Direct queries, raw extraction, and file exports are available."
                    }
                    return DirectIPhoneStatus(
                        name: UIDevice.current.name,
                        appActive: true,
                        protectedDataAvailable: protectedDataAvailable,
                        exportInProgress: exportInProgress,
                        canTriggerRawExports: canStartOperation,
                        canTriggerFileExports: canStartOperation,
                        queryInProgress: queryInProgress,
                        canTriggerQueries: canStartOperation,
                        activeJobID: IPhoneDirectExportCoordinator.shared.currentJobID,
                        activeQueryRequestID: IPhoneDirectQueryCoordinator.shared.activeRequestID,
                        message: message
                    )
                }
                directCLIService.applicationDidBecomeActive()

                // Start advertising if sync was previously enabled
                if UserDefaults.standard.bool(forKey: "syncEnabled") {
                    syncService.startAdvertising()
                    syncService.restoreSavedManualIPConnectionIfNeeded()
                }

                // Configure this last. AppDelegate callbacks may already be
                // waiting on cold launch, and Connected Mac exports require the
                // message handler and reconnect attempt above to exist first.
                schedulingManager.configureScheduledExportDependencies(
                    syncService: syncService,
                    externalIntegrations: externalIntegrationManager
                )
            }
            .onOpenURL { url in
                #if DEBUG
                if exportPerformanceLab.handle(url: url) {
                    if exportPerformanceLab.canAutonomouslyStart {
                        let externalIntegrations: ExternalIntegrationDailyRecordProviding? =
                            ConnectedAppsFeature.isEnabled ? externalIntegrationManager : nil
                        exportPerformanceLab.start(
                            healthKitManager: healthKitManager,
                            syncService: syncService,
                            externalIntegrations: externalIntegrations
                        )
                    }
                    return
                }
                #endif
                guard let pairingLink = IPhoneDirectCLIPairingLink(url: url) else { return }
                directCLIService.prepare(pairingLink: pairingLink)
            }
            .onChange(of: scenePhase) { _, phase in
                guard !TestMode.suppressesRuntimeServices else { return }
                if phase == .active {
                    syncService.restoreSavedManualIPConnectionIfNeeded()
                    directCLIService.applicationDidBecomeActive()
                } else if phase == .background {
                    #if DEBUG
                    exportPerformanceLab.applicationDidEnterBackground()
                    #endif
                    IPhoneDirectQueryCoordinator.shared.clearCachedContext()
                    directCLIService.applicationDidEnterBackground()
                }
            }
            .onChange(of: syncService.connectionState) { _, state in
                switch state {
                case .connected:
                    corpusRecoveryManager.handlePeerConnected()
                case .disconnected:
                    corpusRecoveryManager.handlePeerDisconnected()
                case .connecting:
                    break
                }
            }
            .onChange(of: syncService.canExportToConnectedMac) { _, isReady in
                guard isReady else { return }
                Task { @MainActor in
                    await schedulingManager.resumePendingConnectedMacExportsIfReady()
                }
            }
        }
    }

    // MARK: - Sync Message Handling (iOS side)

    private func setupSyncMessageHandler() {
        syncService.onMessageReceived = { message in
            Task { @MainActor in
                switch message {
                case .requestData(let dates):
                    self.syncService.isSyncing = true
                    await HealthKitQueryExecutionController.withController {
                        await self.handleDataRequest(dates: dates)
                    }
                    self.syncService.isSyncing = false
                case .requestAllData:
                    self.syncService.isSyncing = true
                    await HealthKitQueryExecutionController.withController {
                        await self.handleAllDataRequest()
                    }
                    self.syncService.isSyncing = false
                case .ping:
                    self.syncService.send(.pong)
                case .pong:
                    break // Keepalive response
                case .hello(let capabilities):
                    self.syncService.remoteCapabilities = capabilities
                    self.corpusRecoveryManager.handlePeerConnected()
                case .macStatus(let status):
                    self.syncService.macDestinationStatus = status
                case .macExportAccepted(let acknowledgement):
                    CLIExportActivityTracker.shared.setMessage(
                        jobID: acknowledgement.jobID,
                        phase: .transferring,
                        message: acknowledgement.message ?? "The Mac accepted the CLI export."
                    )
                    self.syncService.publishMacExportMessage(message)
                case .macExportProgress(let progress):
                    SchedulingManager.shared.handleScheduledMacExportProgress(progress)
                    CLIExportActivityTracker.shared.updateMac(progress)
                    self.syncService.publishMacExportMessage(message)
                case .macExportResult(let payload):
                    self.syncService.cancelMacExportStreamAckWaiters(jobID: payload.jobID)
                    let scheduledHandled = SchedulingManager.shared.completeScheduledMacExport(
                        with: payload
                    )
                    let requestHandled = self.iPhoneExportRequestHandler.complete(with: payload)
                    let recoveredScheduledHandled = if !scheduledHandled && !requestHandled {
                        await SchedulingManager.shared.completeRecoveredScheduledMacExport(
                            with: payload
                        )
                    } else {
                        false
                    }
                    if scheduledHandled || requestHandled || recoveredScheduledHandled {
                        self.syncService.isSyncing = false
                    }
                    if scheduledHandled || recoveredScheduledHandled {
                        self.corpusRecoveryManager.markCompletionRecorded(jobID: payload.jobID)
                    } else if !requestHandled {
                        self.corpusRecoveryManager.recordRecoveredCompletion(payload)
                    }
                    self.syncService.publishMacExportMessage(message)
                case .macExportFailed(let failure):
                    if let jobID = failure.jobID {
                        self.syncService.cancelMacExportStreamAckWaiters(jobID: jobID)
                    }
                    if SchedulingManager.shared.completeScheduledMacExport(with: failure) {
                        self.syncService.isSyncing = false
                    }
                    if self.iPhoneExportRequestHandler.complete(with: failure) {
                        self.syncService.isSyncing = false
                    }
                    self.syncService.publishMacExportMessage(message)
                case .iphoneExportRequest(let request):
                    let externalIntegrations: ExternalIntegrationDailyRecordProviding? = ConnectedAppsFeature.isEnabled ? self.externalIntegrationManager : nil
                    await self.iPhoneExportRequestHandler.handle(
                        request,
                        syncService: self.syncService,
                        healthKitManager: self.healthKitManager,
                        externalIntegrations: externalIntegrations
                    )
                case .iphoneExportRejected(let failure):
                    if let jobID = failure.jobID {
                        self.syncService.cancelMacExportStreamAckWaiters(jobID: jobID)
                    }
                    self.iPhoneExportRequestHandler.completeRejected(jobID: failure.jobID)
                    self.syncService.publishMacExportMessage(message)
                case .macExportStreamChunkAck(let ack):
                    if !self.syncService.resolveMacExportStreamChunkAck(ack) {
                        _ = self.iPhoneExportRequestHandler.handleStreamChunkAck(ack)
                        self.syncService.publishMacExportMessage(message)
                    }
                case .connectedTransferAck(let acknowledgement):
                    _ = self.syncService.resolveConnectedTransferAck(acknowledgement)
                case .connectedTransferFinalAck(let acknowledgement):
                    _ = self.syncService.resolveConnectedTransferFinalAck(acknowledgement)
                case .connectedTransferAbort(let abort):
                    self.syncService.recordConnectedTransferAbort(abort)
                    _ = self.iPhoneExportRequestHandler.handleConnectedTransferAbort(
                        abort,
                        syncService: self.syncService
                    )
                    _ = SchedulingManager.shared.handleScheduledConnectedTransferAbort(abort)
                case .iphoneExportCancel(let jobID):
                    if self.iPhoneExportRequestHandler.cancel(jobID: jobID, syncService: self.syncService) {
                        self.syncService.isSyncing = false
                    }
                case .connectedCorpusTransferDisposition(let disposition):
                    _ = self.syncService.resolveConnectedCorpusDisposition(disposition)
                case .connectedCorpusTransferFinalAck(let acknowledgement):
                    _ = self.syncService.resolveConnectedCorpusFinalAck(acknowledgement)
                case .connectedCorpusTransferCancel(let cancel):
                    if self.corpusRecoveryManager.journal(jobID: cancel.jobID) != nil {
                        await self.corpusRecoveryManager.acknowledgeRemoteCancellation(
                            cancel,
                            syncService: self.syncService
                        )
                        self.syncService.isSyncing = false
                    } else if self.iPhoneExportRequestHandler.cancel(
                        jobID: cancel.jobID,
                        syncService: self.syncService
                    ) {
                        self.syncService.isSyncing = false
                    } else {
                        self.syncService.send(.connectedCorpusTransferCancelAck(ConnectedCorpusTransferCancelAck(
                            sessionID: cancel.sessionID,
                            jobID: cancel.jobID,
                            accepted: false,
                            acknowledgedAt: Date(),
                            message: "No matching iPhone corpus producer is active."
                        )))
                    }
                case .connectedCorpusTransferCancelAck(let acknowledgement):
                    _ = self.syncService.resolveConnectedCorpusCancelAck(acknowledgement)
                case .connectedCorpusStatus:
                    break // The iPhone is the durable producer and sends these snapshots to the Mac.
                case .iphoneExportAccepted, .iphoneExportPreparationProgress, .iphoneExportRawData:
                    break // iOS sends these for Mac-initiated export requests
                case .healthData, .syncProgress, .macExportRequest, .macExportCancel,
                     .macExportStreamStart, .macExportStreamChunk,
                     .macExportStreamComplete, .macExportStreamAbort,
                     .connectedTransferStart, .connectedTransferChunk, .connectedTransferComplete,
                     .connectedCorpusTransferOpen, .connectedCorpusTransferFinalize:
                    break // iOS sends these Mac-bound transfer messages.
                }
            }
        }
    }

    /// Fetch health data from HealthKit for the requested dates and send to the connected Mac.
    private func handleDataRequest(dates: [Date]) async {
        var records: [HealthData] = []

        for date in dates {
            do {
                let data = try await healthKitManager.fetchHealthData(for: date)
                if data.hasAnyData {
                    records.append(data)
                }
            } catch is CancellationError {
                return
            } catch {
                // Skip dates that fail — don't block the entire sync
                continue
            }
        }

        guard !records.isEmpty else { return }

        let payload = SyncPayload(
            deviceName: UIDevice.current.name,
            syncTimestamp: Date(),
            healthRecords: records
        )

        syncService.sendLargePayload(.healthData(payload))
    }

    /// Handle a request for ALL available health data.
    /// Discovers the earliest HealthKit data date and sends data in batches with progress updates.
    private func handleAllDataRequest() async {
        // Find the earliest date with health data
        guard let earliestDate = await healthKitManager.findEarliestHealthDataDate() else {
            // No data found — send a completion progress message
            syncService.send(.syncProgress(SyncProgressInfo(
                totalDays: 0, processedDays: 0, recordsInBatch: 0,
                isComplete: true, message: "No health data found on this device."
            )))
            return
        }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: earliestDate)
        let endDate = calendar.startOfDay(for: Date())

        // Build the full list of dates
        var allDates: [Date] = []
        var current = startDate
        while current <= endDate {
            allDates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? endDate.addingTimeInterval(1)
        }

        let totalDays = allDates.count

        // Send initial progress
        syncService.send(.syncProgress(SyncProgressInfo(
            totalDays: totalDays, processedDays: 0, recordsInBatch: 0,
            isComplete: false, message: "Starting all-time sync (\(totalDays) days)…"
        )))

        // Process in batches of 30 days to balance memory usage and transfer reliability
        let batchSize = 30
        var processedDays = 0

        for batchStart in stride(from: 0, to: allDates.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, allDates.count)
            let batchDates = Array(allDates[batchStart..<batchEnd])

            var records: [HealthData] = []
            for date in batchDates {
                do {
                    let data = try await healthKitManager.fetchHealthData(for: date)
                    if data.hasAnyData {
                        records.append(data)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
            }

            processedDays += batchDates.count

            // Send this batch of records if any had data
            if !records.isEmpty {
                let payload = SyncPayload(
                    deviceName: UIDevice.current.name,
                    syncTimestamp: Date(),
                    healthRecords: records
                )
                syncService.sendLargePayload(.healthData(payload))

                // Small delay to let the transfer complete before sending progress
                try? await Task.sleep(for: .milliseconds(200))
            }

            // Send progress update
            let isComplete = processedDays >= totalDays
            syncService.send(.syncProgress(SyncProgressInfo(
                totalDays: totalDays,
                processedDays: processedDays,
                recordsInBatch: records.count,
                isComplete: isComplete,
                message: isComplete
                    ? "Sync complete!"
                    : "Syncing… \(processedDays)/\(totalDays) days"
            )))

            // Small delay between batches to avoid overwhelming the connection
            if !isComplete {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
