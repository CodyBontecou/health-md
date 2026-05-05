#if os(macOS)
import SwiftUI

// MARK: - Main macOS Window

struct MacContentView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore

    @AppStorage("hasCompletedMacOnboarding") private var hasCompletedOnboarding = false

    enum SidebarItem: String, CaseIterable, Identifiable {
        case sync = "Sync"
        case export = "Export"
        case schedule = "Schedule"
        case history = "History"
        case settings = "Settings"

        var id: Self { self }

        var icon: String {
            switch self {
            case .sync:     return "arrow.triangle.2.circlepath"
            case .export:   return "arrow.up.doc"
            case .schedule: return "clock"
            case .history:  return "list.bullet.clipboard"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var selectedItem: SidebarItem? = .sync

    var body: some View {
        Group {
            if shouldShowOnboarding {
                MacOnboardingView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .onAppear(perform: skipOnboardingIfAlreadyOnboarded)
        .onChange(of: healthDataStore.recordCount) { _, _ in
            skipOnboardingIfAlreadyOnboarded()
        }
    }

    /// Treat existing users (who already have synced data) as onboarded so the
    /// flow never shows after an app update.
    private func skipOnboardingIfAlreadyOnboarded() {
        if !hasCompletedOnboarding && healthDataStore.recordCount > 0 {
            hasCompletedOnboarding = true
        }
    }

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding && healthDataStore.recordCount == 0
    }

    private var mainContent: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Brand header
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accent)
                    Text("health.md")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Sidebar navigation
                List(SidebarItem.allCases, selection: $selectedItem) { item in
                    Label {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(Color.accent)
                    }
                    .tag(item)
                }
                .listStyle(.sidebar)

                // Connection status footer
                Divider()
                    .opacity(0.3)

                HStack(spacing: 6) {
                    Circle()
                        .fill(syncService.connectionState == .connected ? Color.success : Color.textMuted)
                        .frame(width: 6, height: 6)
                    Text(sidebarStatusLabel)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    if healthDataStore.recordCount > 0 {
                        Text("\(healthDataStore.recordCount)d")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.accent.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            Group {
                switch selectedItem {
                case .sync:
                    MacSyncView()
                case .export:
                    MacExportView()
                case .schedule:
                    MacScheduleView()
                case .history:
                    MacHistoryView()
                case .settings:
                    MacDetailSettingsView()
                case .none:
                    brandPlaceholder
                }
            }
        }
    }

    // MARK: - Helpers

    private var sidebarStatusLabel: String {
        switch syncService.connectionState {
        case .connected:
            return syncService.connectedPeerName ?? "Connected"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "No iPhone"
        }
    }

    private var brandPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(Color.accent)
            Text("health.md")
                .font(BrandTypography.heading())
                .foregroundStyle(Color.textPrimary)
            Text("Select a section from the sidebar")
                .font(BrandTypography.body())
                .foregroundStyle(Color.textMuted)
        }
    }
}

#endif
