import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if !TestMode.isUITesting {
            AppsFlyerManager.shared.configure()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if !TestMode.isUITesting {
            AppsFlyerManager.shared.start()
        }
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AppsFlyerManager.shared.handleOpenURL(url, options: options)
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        AppsFlyerManager.shared.continueUserActivity(userActivity)
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
        Task { @MainActor in
            await SchedulingManager.shared.performSilentPushExport()
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Check if this is our export reminder notification
        if response.notification.request.identifier.contains("export.reminder") {
            Task { @MainActor in
                await SchedulingManager.shared.performNotificationTriggeredExport()
            }
        }
        completionHandler()
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
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var syncService = SyncService()

    init() {
        // Register defaults for sync settings
        UserDefaults.standard.register(defaults: [
            "autoSyncAfterExport": true
        ])

        #if DEBUG
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

            // If onboarding is complete, request HealthKit authorization on launch.
            // During onboarding, the OnboardingView handles this at the right step.
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if hasCompletedOnboarding {
                if HealthKitManager.shared.isHealthDataAvailable && !HealthKitManager.shared.isAuthorized {
                    try? await HealthKitManager.shared.requestAuthorization()
                }
            }

            // Request notification permissions after HealthKit auth sheet is dismissed
            _ = await SchedulingManager.shared.requestNotificationPermissions()

            // If scheduling is enabled, set up HealthKit background delivery
            if SchedulingManager.shared.schedule.isEnabled {
                await HealthKitManager.shared.enableBackgroundDelivery()
                HealthKitManager.shared.setupObserverQueries()
            }
        }
    }

    #if DEBUG
    /// Configure the app for marketing screenshot capture.
    /// Sets up the same deterministic state as test mode so screens look populated.
    private func configureMarketingMode() {
        Task { @MainActor in
            healthKitManager.isAuthorized = true
            PurchaseManager.shared.setUnlocked(true)
            syncService.connectionState = .connected
            syncService.connectedPeerName = "MacBook Pro"
            var schedule = schedulingManager.schedule
            schedule.isEnabled = true
            schedulingManager.schedule = schedule
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(true, forKey: "discordPromoDismissed")
        }
    }
    #endif

    /// Configure deterministic test state from launch environment variables.
    /// Skips all real HealthKit, StoreKit, and network interactions.
    private func configureTestMode() {
        // All managers are @MainActor — set state in Task
        Task { @MainActor in
            // HealthKit: set authorization state without showing dialogs
            healthKitManager.isAuthorized = TestMode.healthAuthorized

            // Purchase: set unlock/quota state without StoreKit
            if TestMode.purchaseUnlocked {
                PurchaseManager.shared.setUnlocked(true)
            }
            PurchaseManager.shared.setFreeExportsUsed(TestMode.freeExportsUsed)

            // Sync: set connection state
            switch TestMode.syncState {
            case "connected":
                syncService.connectionState = .connected
                syncService.connectedPeerName = "Test Mac"
            case "connecting":
                syncService.connectionState = .connecting
            default:
                syncService.connectionState = .disconnected
            }

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
            .task {
                setupSyncMessageHandler()

                // Start advertising if sync was previously enabled
                if UserDefaults.standard.bool(forKey: "syncEnabled") {
                    syncService.startAdvertising()
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
                    await self.handleDataRequest(dates: dates)
                    self.syncService.isSyncing = false
                case .requestAllData:
                    self.syncService.isSyncing = true
                    await self.handleAllDataRequest()
                    self.syncService.isSyncing = false
                case .ping:
                    self.syncService.send(.pong)
                case .pong:
                    break // Keepalive response
                case .healthData, .syncProgress:
                    break // iOS doesn't receive health data or progress — only macOS does
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
