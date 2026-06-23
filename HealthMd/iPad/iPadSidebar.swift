import SwiftUI

// MARK: - iPad Navigation Items (matching macOS sidebar)

enum iPadNavItem: String, CaseIterable, Identifiable {
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

// MARK: - iPad Sidebar (matching macOS branded sidebar)

struct iPadSidebar: View {
    @Binding var selectedTab: iPadNavItem?
    @EnvironmentObject var syncService: SyncService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesCompactLabels: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 0) {
            // Brand header
            HStack(spacing: Spacing.s2) {
                if !usesCompactLabels {
                    Text("health.md")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)
                        .tracking(-0.2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s4)
            .padding(.bottom, Spacing.s3)

            // Sidebar navigation
            List(selection: $selectedTab) {
                ForEach(iPadNavItem.allCases) { item in
                    if usesCompactLabels {
                        Image(systemName: item.icon)
                            .accessibilityHidden(true)
                            .foregroundStyle(Color.accent)
                            .font(Typography.heading20())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityLabel(item.rawValue)
                            .tag(item)
                    } else {
                        Label {
                            Text(item.rawValue)
                                .font(Typography.bodyEmphasis())
                        } icon: {
                            Image(systemName: item.icon)
                                .accessibilityHidden(true)
                                .foregroundStyle(Color.accent)
                        }
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)

            // Connection status footer
            Divider()
                .background(Color.borderSubtle)

            HStack(spacing: 6) {
                Circle()
                    .fill(syncService.connectionState == .connected ? Color.success : Color.textMuted)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                if !usesCompactLabels {
                    Text(sidebarStatusLabel)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
        }
    }

    private var sidebarStatusLabel: String {
        switch syncService.connectionState {
        case .connected:
            return syncService.connectedPeerName ?? "Connected"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "No Mac"
        }
    }
}
