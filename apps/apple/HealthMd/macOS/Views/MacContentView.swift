#if os(macOS)
import SwiftUI

// MARK: - Main macOS Window

/// The Mac app is a destination/agent surface. Export configuration and
/// initiation live on iPhone; this window only manages connection, folder
/// readiness, job status, and recent activity.
struct MacContentView: View {
    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: MacSidebarDestination? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MacSidebarDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination as MacSidebarDestination?)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Health.md")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView(for: selection ?? .home)
                .navigationTitle((selection ?? .home).title)
        }
        .onAppear {
            // Retire the legacy Mac onboarding flow so new users land on the
            // destination-agent screen instead of the old cache-sync flow.
            hasCompletedOnboarding = true
        }
    }

    @ViewBuilder
    private func detailView(for destination: MacSidebarDestination) -> some View {
        switch destination {
        case .home:
            MacSyncView()
        case .cli:
            MacCLIView()
        case .settings:
            MacDetailSettingsView()
        }
    }
}

private enum MacSidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case cli
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .cli:
            return "CLI"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .cli:
            return "terminal"
        case .settings:
            return "gearshape"
        }
    }
}

#endif
