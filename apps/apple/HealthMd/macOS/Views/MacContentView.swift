#if os(macOS)
import SwiftUI

// MARK: - Main macOS Window

/// The Mac app is a destination/agent surface. Export configuration and
/// initiation live on iPhone; this window only manages connection, folder
/// readiness, job status, and recent activity.
struct MacContentView: View {
    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedOnboarding = false
    @State private var selection: MacSidebarDestination?
    /// Help menu feedback handoffs present their copyable-report fallback here.
    @ObservedObject private var supportReporter = MacSupport.feedbackReporter

    init() {
        #if DEBUG
        let initialSelection = MacSidebarDestination(
            rawValue: MacMarketingCapture.initialSidebarDestination
        ) ?? .home
        _selection = State(initialValue: initialSelection)
        #else
        _selection = State(initialValue: .home)
        #endif
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MacSidebarDestination.visibleCases) { destination in
                    Text(destination.title)
                        .font(.system(size: 13))
                        .tag(destination as MacSidebarDestination?)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                // MacHomeG sidebar: crystal heart and wordmark above the destinations.
                HStack(spacing: 8) {
                    Image("HealthCrystalHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(verbatim: "Health.md")
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .navigationTitle("Health.md")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView(for: selection ?? .home)
                .glassFormChrome()
                .navigationTitle((selection ?? .home).title)
        }
        .glassTheme()
        .feedbackFailureSheet($supportReporter.failure)
        .onReceive(NotificationCenter.default.publisher(for: MacSidebarNavigation.didRequest)) { _ in
            consumeNavigationRequest()
        }
        .onAppear {
            consumeNavigationRequest()
            #if DEBUG
            if MacMarketingCapture.isActive { return }
            #endif
            // Retire the legacy Mac onboarding flow so new users land on the
            // destination-agent screen instead of the old cache-sync flow.
            hasCompletedOnboarding = true
        }
    }

    private func consumeNavigationRequest() {
        guard let requested = MacSidebarNavigation.takePending(),
              let destination = MacSidebarDestination(rawValue: requested.rawValue) else { return }
        selection = destination
    }

    @ViewBuilder
    private func detailView(for destination: MacSidebarDestination) -> some View {
        switch destination {
        case .home:
            MacSyncView()
        case .history:
            MacHistoryView()
        case .cli:
            MacCLIView()
        case .settings:
            MacDetailSettingsView()
        }
    }
}

private enum MacSidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case history
    case cli
    case settings

    var id: Self { self }

    /// History gets its own section in the Liquid Glass layout.
    static var visibleCases: [MacSidebarDestination] {
        allCases
    }

    var title: String {
        switch self {
        case .home:
            return String(localized: "Mac destination")
        case .history:
            return String(localized: "History")
        case .cli:
            return String(localized: "CLI & MCP")
        case .settings:
            return String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .history:
            return "clock"
        case .cli:
            return "terminal"
        case .settings:
            return "gearshape"
        }
    }
}

/// Lets other surfaces (the menu bar extra) select a sidebar destination in the main window,
/// including one that opens after the request.
enum MacSidebarNavigation {
    enum Destination: String {
        case home, history, cli, settings
    }

    static let didRequest = Notification.Name("HealthMd.MacSidebarNavigation.didRequest")

    @MainActor private static var pending: Destination?

    @MainActor
    static func request(_ destination: Destination) {
        pending = destination
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    @MainActor
    static func takePending() -> Destination? {
        defer { pending = nil }
        return pending
    }
}

#endif
