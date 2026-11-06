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

/// Vertical navigation for the iPhone Duo unfolded layout (DuoInnerArchiveG): the tab
/// capsule stands on end at the trailing edge with Export now below it.
struct NavigationRail<ID: Hashable, Accessory: View>: View {
    let items: [GlassNavigationItem<ID>]
    @Binding var selection: ID
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                ForEach(items) { item in
                    GlassNavigationButton(item: item, selection: $selection, isVertical: true)
                }
            }
            .padding(4)
            .glassSurface(cornerRadius: 30, style: .strong)
            accessory
        }
        .frame(maxHeight: .infinity)
    }
}

/// iPad navigation (iPadArchiveG): a glass sidebar with the app name, the sections,
/// and an optional list below them, such as the Archive's profiles.
struct GlassSidebar<ID: Hashable, Section: View, Accessory: View>: View {
    let title: String
    let items: [GlassNavigationItem<ID>]
    @Binding var selection: ID
    @ViewBuilder let section: Section
    @ViewBuilder let accessory: Accessory

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                #if os(iOS)
                Image("HealthCrystalHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                #endif
                Text(verbatim: title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.text)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                let isSelected = item.id == selection
                Button {
                    selection = item.id
                } label: {
                    Text(item.title)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                // `line` reads on the light glass sidebar too; `glassStrong`
                                // is near-white there and the selection vanished.
                                .fill(isSelected ? palette.line : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("glass.tab.\(String(describing: item.id))")
            }
            section
            Spacer(minLength: 8)
            accessory
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(width: GlassMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassSurface(cornerRadius: 28)
    }
}

extension GlassSidebar where Section == EmptyView {
    init(
        title: String,
        items: [GlassNavigationItem<ID>],
        selection: Binding<ID>,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title: title, items: items, selection: selection, section: { EmptyView() }, accessory: accessory)
    }
}

/// One row of a sidebar list: a coloured dot and a name, as iPadArchiveG's Profiles.
struct GlassSidebarListRow: View {
    let title: String
    let dotColor: Color
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(dotColor).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? palette.text : palette.sec)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? palette.line : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: GlassMetrics.touchTarget)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The small heading above a sidebar list.
struct GlassSidebarHeading: View {
    let title: String

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct GlassNavigationButton<ID: Hashable>: View {
    let item: GlassNavigationItem<ID>
    @Binding var selection: ID
    var isVertical = false

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
                    .font(.system(size: isVertical ? 10 : 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.sec)
            .padding(.horizontal, isVertical ? 2 : 12)
            .frame(
                minWidth: 64,
                maxWidth: isVertical ? 64 : nil,
                minHeight: isVertical ? 58 : GlassMetrics.touchTarget + 6
            )
            .background {
                if isVertical && isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.glassStrong)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("glass.tab.\(String(describing: item.id))")
    }
}
