#if os(macOS)
import SwiftUI

// MARK: - Main macOS Window

struct MacContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings

    enum SidebarItem: String, CaseIterable, Identifiable {
        case export = "Export"
        case schedule = "Schedule"
        case history = "History"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .export:   return "arrow.up.doc"
            case .schedule: return "clock"
            case .history:  return "list.bullet.clipboard"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var selectedItem: SidebarItem? = .export

    var body: some View {
        Group {
            if !healthKitManager.isHealthDataAvailable {
                healthKitUnavailableView
            } else {
                mainContent
            }
        }
        .task {
            if healthKitManager.isHealthDataAvailable && !healthKitManager.isAuthorized {
                try? await healthKitManager.requestAuthorization()
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedItem {
                case .export:
                    MacExportView()
                case .schedule:
                    MacScheduleView()
                case .history:
                    MacHistoryView()
                case .settings:
                    MacDetailSettingsView()
                case .none:
                    ContentUnavailableView(
                        "Health.md",
                        systemImage: "heart.text.square",
                        description: Text("Select a section from the sidebar.")
                    )
                }
            }
        }
    }

    // MARK: - HealthKit Unavailable

    private var healthKitUnavailableView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("HealthKit Not Available")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                Text("Health.md requires Apple Health, which is only available on Apple Silicon Macs running macOS 14 or later.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Text("Make sure:")
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 6) {
                    Label("You're using an Apple Silicon Mac (M1 or later)", systemImage: "cpu")
                    Label("macOS 14 (Sonoma) or later is installed", systemImage: "desktopcomputer")
                    Label("The Health app is set up on this Mac", systemImage: "heart.text.square")
                    Label("iCloud Health sync is enabled in System Settings", systemImage: "icloud")
                }
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            .frame(maxWidth: 460)

            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preferences") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(40)
    }
}

#endif
