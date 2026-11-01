import SwiftUI

struct GlassNavigationItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
}

/// Floating capsule tab bar with the separate round Export now button.
struct FloatingTabBar<ID: Hashable>: View {
    let items: [GlassNavigationItem<ID>]
    @Binding var selection: ID
    let accessoryTitle: String
    var accessorySystemImage = "arrow.up.doc"
    let accessoryAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(items) { item in
                    GlassNavigationButton(item: item, selection: $selection)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: GlassMetrics.tabBarHeight)
            .glassSurface(in: Capsule(), style: .strong, isInteractive: true)

            ExportNowAccessoryButton(
                title: accessoryTitle,
                systemImage: accessorySystemImage,
                action: accessoryAction
            )
        }
        .padding(.horizontal, GlassMetrics.screenMargin)
        .padding(.bottom, GlassMetrics.tabBarBottomOffset)
    }
}

struct ExportNowAccessoryButton: View {
    let title: String
    var systemImage = "arrow.up.doc"
    let action: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.accentInk)
                .frame(width: GlassMetrics.tabBarHeight, height: GlassMetrics.tabBarHeight)
                .background(Circle().fill(palette.accent))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("glass.exportNow")
    }
}

/// Vertical navigation for the iPhone Duo unfolded layout.
struct NavigationRail<ID: Hashable, Accessory: View>: View {
    let items: [GlassNavigationItem<ID>]
    @Binding var selection: ID
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                GlassNavigationButton(item: item, selection: $selection)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .glassSurface(cornerRadius: GlassMetrics.panelRadius, style: .strong)
    }
}

/// iPad navigation: a leading sidebar with the app name.
struct GlassSidebar<ID: Hashable, Accessory: View>: View {
    let title: String
    let items: [GlassNavigationItem<ID>]
    @Binding var selection: ID
    @ViewBuilder let accessory: Accessory

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .glassFont(.screenTitle)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            ForEach(items) { item in
                let isSelected = item.id == selection
                Button {
                    selection = item.id
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .glassFont(.navTitle)
                        .foregroundStyle(isSelected ? palette.accent : palette.text)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: GlassMetrics.iconTileRadius, style: .continuous)
                                .fill(isSelected ? palette.surface2 : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 8)
            accessory
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: GlassMetrics.sidebarWidth)
    }
}

private struct GlassNavigationButton<ID: Hashable>: View {
    let item: GlassNavigationItem<ID>
    @Binding var selection: ID

    @Environment(\.glassPalette) private var palette

    var body: some View {
        let isSelected = item.id == selection
        Button {
            selection = item.id
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 19, weight: .medium))
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.sec)
            .padding(.horizontal, 12)
            .frame(minWidth: 64, minHeight: GlassMetrics.touchTarget + 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("glass.tab.\(String(describing: item.id))")
    }
}
