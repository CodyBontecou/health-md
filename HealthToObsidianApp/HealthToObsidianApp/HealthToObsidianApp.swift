import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Check if this is our export reminder notification
        if response.notification.request.identifier.contains("export.reminder") {
            Task { @MainActor in
                await SchedulingManager.shared.performCatchUpExportIfNeeded()
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
struct HealthToObsidianApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var schedulingManager = SchedulingManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register background tasks at app launch - must happen before app finishes launching
        Task { @MainActor in
            SchedulingManager.shared.registerBackgroundTask()

            // Request notification permissions
            _ = await SchedulingManager.shared.requestNotificationPermissions()

            // If scheduling is enabled, set up HealthKit background delivery
            if SchedulingManager.shared.schedule.isEnabled {
                await HealthKitManager.shared.enableBackgroundDelivery()
                HealthKitManager.shared.setupObserverQueries()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(schedulingManager)
                .environmentObject(healthKitManager)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Perform catch-up export when app becomes active
                        Task { @MainActor in
                            await schedulingManager.performCatchUpExportIfNeeded()
                        }
                    }
                }
        }
    }
}
