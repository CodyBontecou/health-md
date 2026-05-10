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
            HStack(spacing: 8) {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                if !usesCompactLabels {
                    Text("health.md")
                        .font(.headline.weight(.semibold).monospaced())
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Sidebar navigation
            List(selection: $selectedTab) {
                ForEach(iPadNavItem.allCases) { item in
                    if usesCompactLabels {
                        Image(systemName: item.icon)
                            .foregroundStyle(Color.accent)
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityLabel(item.rawValue)
                            .tag(item)
                    } else {
                        Label {
                            Text(item.rawValue)
                                .font(Typography.monoEmphasis())
                        } icon: {
                            Image(systemName: item.icon)
                                .foregroundStyle(Color.accent)
                        }
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)

            // Connection status footer
            Divider()
                .opacity(0.3)

            HStack(spacing: 6) {
                Circle()
                    .fill(syncService.connectionState == .connected ? Color.success : Color.textMuted)
                    .frame(width: 6, height: 6)
                if !usesCompactLabels {
                    Text(sidebarStatusLabel)
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
