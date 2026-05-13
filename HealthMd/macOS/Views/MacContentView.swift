#if os(macOS)
import SwiftUI

// MARK: - Main macOS Window

/// The Mac app is a destination/agent surface. Export configuration and
/// initiation live on iPhone; this window only manages connection, folder
/// readiness, job status, and recent activity.
struct MacContentView: View {
    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        MacSyncView()
            .onAppear {
                // Retire the legacy Mac onboarding flow so new users land on the
                // destination-agent screen instead of the old cache-sync flow.
                hasCompletedOnboarding = true
            }
    }
}

#endif
