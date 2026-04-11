import SwiftUI

// MARK: - Liquid Glass Tab Bar
// iOS-inspired floating pill navbar with frosted glass effect

enum NavTab: Int, CaseIterable {
    case export
    case schedule
    case sync
    case settings

    var icon: String {
        switch self {
        case .export: return "arrow.up.doc"
        case .schedule: return "clock"
        case .sync: return "arrow.triangle.2.circlepath"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .export: return "arrow.up.doc.fill"
        case .schedule: return "clock.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .export: return "Export"
        case .schedule: return "Schedule"
        case .sync: return "Sync"
        case .settings: return "Settings"
        }
    }

    var accessibilityID: String {
        switch self {
        case .export: return AccessibilityID.Tab.export
        case .schedule: return AccessibilityID.Tab.schedule
        case .sync: return AccessibilityID.Tab.sync
        case .settings: return AccessibilityID.Tab.settings
        }
    }
}

struct LiquidGlassNavBar: View {
    @Binding var selectedTab: NavTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NavTab.allCases, id: \.rawValue) { tab in
                TabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

struct TabButton: View {
    let tab: NavTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 22, weight: .medium))

                Text(LocalizedStringKey(tab.label))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.accessibilityID)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityHint("Tab \(tab.rawValue + 1) of \(NavTab.allCases.count)")
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()

        VStack {
            Spacer()
            LiquidGlassNavBar(selectedTab: .constant(.export))
        }
    }
    .preferredColorScheme(.dark)
}
