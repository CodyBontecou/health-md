#if os(macOS)
import SwiftUI
import UserNotifications

// MARK: - Window Manager (bridges SwiftUI openWindow to AppKit)

final class WindowManager {
    static let shared = WindowManager()
    /// Captured from the SwiftUI environment so AppKit code can open the main window.
    var openMainWindow: (() -> Void)?
    private init() {}
}

// MARK: - macOS App Delegate

class MacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Perform catch-up export if the schedule was missed while the app was inactive
        Task { @MainActor in
            await SchedulingManager.shared.performCatchUpExportIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Re-open the main window when the user clicks the Dock icon while no windows are visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.openMainWindow?()
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.contains("export") {
            NSApp.activate(ignoringOtherApps: true)
            WindowManager.shared.openMainWindow?()
        }
        completionHandler()
    }

    // MARK: - Remote notifications (server-driven scheduled exports)

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrationManager.shared.submitDeviceToken(deviceToken)
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Dev builds without the entitlement may fail here; the server simply
        // won't push to this device.
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        guard userInfo["type"] as? String == "scheduled-export" else { return }
        Task { @MainActor in
            await SchedulingManager.shared.performCatchUpExportIfNeeded()
        }
    }
}

// MARK: - macOS Main App

@main
struct HealthMdApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @StateObject private var syncService = SyncService()
    @StateObject private var healthDataStore = HealthDataStore()

    init() {
        Task { @MainActor in
            if SchedulingManager.shared.schedule.isEnabled {
                SchedulingManager.shared.rescheduleTimer()
            }
        }
    }

    var body: some Scene {
        Window("Health.md", id: "main-window") {
            MacContentView()
                .environmentObject(schedulingManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .environmentObject(syncService)
                .environmentObject(healthDataStore)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(.dark)
                .tint(Color.accent)
                .task {
                    setupSyncMessageHandler()
                    syncService.startBrowsing()
                }
                .withWindowManagerBridge()
        }
        .defaultSize(width: 920, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) { }
            MainWindowCommands()
        }

        MenuBarExtra("Health.md", systemImage: "heart.text.square") {
            MacMenuBarView()
                .environmentObject(schedulingManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .environmentObject(syncService)
                .environmentObject(healthDataStore)
                .tint(Color.accent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsWindow()
                .environmentObject(schedulingManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .environmentObject(syncService)
                .environmentObject(healthDataStore)
                .preferredColorScheme(.dark)
                .tint(Color.accent)
        }
    }

    // MARK: - Sync Message Handling

    private func setupSyncMessageHandler() {
        syncService.onMessageReceived = { message in
            Task { @MainActor in
                switch message {
                case .healthData(let payload):
                    healthDataStore.store(payload.healthRecords, fromDevice: payload.deviceName)
                    SyncEventHistoryManager.shared.record(syncEvent(from: payload))
                case .syncProgress(let progress):
                    healthDataStore.updateSyncProgress(progress)
                    if progress.isComplete {
                        SyncEventHistoryManager.shared.record(
                            SyncEvent(
                                peerName: syncService.connectedPeerName ?? "iPhone",
                                kind: .progressComplete,
                                recordCount: progress.processedDays
                            )
                        )
                    }
                case .pong:
                    break // Connection keepalive response
                case .ping:
                    syncService.send(.pong)
                case .requestData, .requestAllData:
                    break // macOS doesn't serve data — only iOS does
                }
            }
        }
    }

    private func syncEvent(from payload: SyncPayload) -> SyncEvent {
        let dates = payload.healthRecords.map(\.date)
        let byteEstimate = (try? JSONEncoder().encode(payload).count) ?? 0
        return SyncEvent(
            timestamp: payload.syncTimestamp,
            peerName: payload.deviceName,
            kind: .dataReceived,
            recordCount: payload.healthRecords.count,
            payloadByteEstimate: byteEstimate,
            dateRangeStart: dates.min(),
            dateRangeEnd: dates.max()
        )
    }
}

// MARK: - Window Manager Bridge

/// Captures the SwiftUI `openWindow` action and stores it in the shared
/// `WindowManager` so that AppKit code (app delegate, menu bar extra) can
/// re-open the main window reliably.
private struct WindowManagerBridge: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowManager.shared.openMainWindow = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main-window")
                }
            }
    }
}

extension View {
    func withWindowManagerBridge() -> some View {
        modifier(WindowManagerBridge())
    }
}

// MARK: - Commands

private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File ▸ Show Health.md  (⌘0) — always available even when Window menu is empty
        CommandGroup(after: .newItem) {
            Button("Show Health.md") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main-window")
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        // Window ▸ Health.md — standard location users expect
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Health.md") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main-window")
            }
            .keyboardShortcut("1", modifiers: .command)
        }
    }
}

#endif
