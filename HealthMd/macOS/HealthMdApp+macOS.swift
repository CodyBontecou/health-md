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
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()

    init() {
        Task { @MainActor in
            if SchedulingManager.shared.schedule.isEnabled {
                HealthKitManager.shared.setupObserverQueries()
                HealthKitManager.shared.setupPollingTimer()
                SchedulingManager.shared.rescheduleTimer()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .environmentObject(schedulingManager)
                .environmentObject(healthKitManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 920, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra("Health.md", systemImage: "heart.text.square") {
            MacMenuBarView()
                .environmentObject(schedulingManager)
                .environmentObject(healthKitManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsWindow()
                .environmentObject(schedulingManager)
                .environmentObject(healthKitManager)
                .environmentObject(vaultManager)
                .environmentObject(advancedSettings)
        }
    }
}

#endif
