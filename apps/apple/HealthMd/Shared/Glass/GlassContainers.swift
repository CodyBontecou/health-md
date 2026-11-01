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
/// Does nothing with the flag off.
private struct GlassFormChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if NewExperienceFeature.isEnabled {
            let palette = GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
            content
                .scrollContentBackground(.hidden)
                .background(palette.bg.ignoresSafeArea())
                .tint(palette.accent)
                .glassTheme()
        } else {
            content
        }
    }
}

/// Gives a `Form` section the glass panel fill. Does nothing with the flag off.
private struct GlassFormRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        if NewExperienceFeature.isEnabled {
            content.listRowBackground(Color.glassAdaptive(.clear, \.glassStrong))
        } else {
            content
        }
    }
}

extension View {
    func glassFormRows() -> some View {
        modifier(GlassFormRowModifier())
    }

    func glassFormChrome() -> some View {
        modifier(GlassFormChromeModifier())
    }
}
