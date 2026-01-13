import SwiftUI

@main
struct HealthToObsidianApp: App {
    @StateObject private var schedulingManager = SchedulingManager.shared

    init() {
        // Register background tasks at app launch
        Task { @MainActor in
            SchedulingManager.shared.registerBackgroundTask()

            // Request notification permissions
            _ = await SchedulingManager.shared.requestNotificationPermissions()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(schedulingManager)
        }
    }
}
