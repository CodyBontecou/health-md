#if os(macOS)
import SwiftUI
import UserNotifications

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
            if let window = NSApp.windows.first(where: { $0.isVisible || $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        completionHandler()
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
                case .syncProgress(let progress):
                    healthDataStore.updateSyncProgress(progress)
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
}

// MARK: - Commands

private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Health.md") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main-window")
            }
        }
    }
}

#endif
