import SwiftUI

@main
struct HealthToObsidianApp: App {
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
