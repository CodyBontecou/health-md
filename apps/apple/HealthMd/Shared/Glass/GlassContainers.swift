import SwiftUI

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = GlassMetrics.panelRadius
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: cornerRadius)
    }
}

struct GlassRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).glassFont(.body).foregroundStyle(palette.text)
                if let subtitle {
                    Text(subtitle).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .frame(
            minHeight: subtitle == nil ? GlassMetrics.rowMinHeight : GlassMetrics.rowWithSubtitleMinHeight
        )
        .contentShape(Rectangle())
    }
}

extension GlassRow where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

struct GlassBanner: View {
    enum Tone { case info, warning, success }

    let title: String
    var message: String?
    var systemImage = "info.circle"
    var tone: Tone = .info

    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(toneColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).glassFont(.caption).foregroundStyle(palette.text)
                if let message {
                    Text(message).glassFont(.rowSubtitle).foregroundStyle(palette.sec)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
        .accessibilityElement(children: .combine)
    }

    private var toneColor: Color {
        switch tone {
        case .info: return palette.accent
        case .warning: return palette.coral
        case .success: return palette.ok
        }
    }
}

/// Glass chrome for a system `Form` whose order and wording are part of a consent flow.
private struct GlassFormChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let palette = GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
        content
            .scrollContentBackground(.hidden)
            .background(palette.bg.ignoresSafeArea())
            .tint(palette.accent)
            .glassTheme()
    }
}

extension View {
    func glassFormRows() -> some View {
        listRowBackground(Color.glassAdaptive(\.glassStrong))
    }

    func glassFormChrome() -> some View {
        modifier(GlassFormChromeModifier())
    }
}

// MARK: - iPad panes

/// iPadAutomationsG and iPadSettingsG: each column sits in its own bordered glass panel.
private struct GlassPaneModifier: ViewModifier {
    @Environment(\.glassPalette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassMetrics.paneRadius, style: .continuous)
        content
            .clipShape(shape)
            // Pane screens paint `bg` themselves, so the list pane does too: both columns
            // read the same, separated by the panes' edges.
            .background(shape.fill(palette.bg))
            .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
    }
}

/// The 22 pt bold heading that leads an iPad pane ("Automations", "healthmd CLI").
struct GlassPaneHeading: View {
    let title: String

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(palette.text)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One plain row of an iPad list pane: no card, a rounded highlight when selected.
struct GlassPaneRowBackground: ViewModifier {
    let isSelected: Bool
    var cornerRadius: CGFloat = 14

    @Environment(\.glassPalette) private var palette

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // `line` reads on light glass too, as in the sidebar.
                    .fill(isSelected ? palette.line : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    func glassPane() -> some View { modifier(GlassPaneModifier()) }
}
