import SwiftUI

/// Colours from `docs/design/liquid-glass/tokens.json`. The solid variants drive both
/// Reduce Transparency and the fallback on systems without Liquid Glass.
struct GlassPalette: Equatable {
    let fill, fillText, partial, bg, text, sec, muted, accent, accentInk, track: Color
    let coral, ok, surface, surface2, line, glass, glassStrong, edge, hi, tint: Color
    let profile2, profile3, profile4: Color

    /// Colour for the nth profile, cycling through the four design slots.
    func profileColor(at index: Int) -> Color {
        [accent, profile2, profile3, profile4][abs(index) % 4]
    }

    static let dark = GlassPalette(
        fill: .glassHex(0x3B3058), fillText: .glassHex(0xFFFFFF), partial: .glassWhite(0.07),
        bg: .glassHex(0x0E0E11), text: .glassHex(0xFFFFFF), sec: .glassHex(0xDAD4E8),
        muted: .glassHex(0xB3ABC6), accent: .glassHex(0xCDB6FF), accentInk: .glassHex(0x1A0F33),
        track: .glassWhite(0.20), coral: .glassHex(0xFFA184), ok: .glassHex(0x8BF0B4),
        surface: .glassWhite(0.10), surface2: .glassWhite(0.18), line: .glassWhite(0.14),
        glass: .glassWhite(0.06), glassStrong: .glassWhite(0.12), edge: .glassWhite(0.12),
        hi: .glassWhite(0.22), tint: .glassHex(0xCDB6FF, opacity: 0.30),
        profile2: .glassHex(0x7DB4FF), profile3: .glassHex(0x5ED3B0), profile4: .glassHex(0xF2B266)
    )

    static let light = GlassPalette(
        fill: .glassHex(0xDCCFFA), fillText: .glassHex(0x2D1F4F), partial: .glassWhite(0.9),
        bg: .glassHex(0xF2F2F5), text: .glassHex(0x14101D), sec: .glassHex(0x3B3550),
        muted: .glassHex(0x575070), accent: .glassHex(0x6A3FE0), accentInk: .glassHex(0xFFFFFF),
        track: .glassHex(0x14101D, opacity: 0.14), coral: .glassHex(0xB93C0A), ok: .glassHex(0x15803D),
        surface: .glassWhite(0.5), surface2: .glassWhite(0.85), line: .glassHex(0x14101D, opacity: 0.08),
        glass: .glassWhite(0.72), glassStrong: .glassWhite(0.92), edge: .glassHex(0x14101D, opacity: 0.06),
        hi: .glassWhite(1), tint: .glassHex(0x6A3FE0, opacity: 0.16),
        profile2: .glassHex(0x2F6FD6), profile3: .glassHex(0x0E8A6A), profile4: .glassHex(0xB26A00)
    )

    static let reduceTransparencyDark = dark.replacingSurfaces(
        surface2: .glassHex(0x2A2A31), glass: .glassHex(0x1C1C21), glassStrong: .glassHex(0x28282F),
        edge: .glassHex(0x2E2E36), hi: .glassWhite(0)
    )

    /// Not in `tokens.json`: derived with opaque equivalents of the light surfaces.
    static let reduceTransparencyLight = light.replacingSurfaces(
        surface2: .glassHex(0xFFFFFF), glass: .glassHex(0xFAFAFC), glassStrong: .glassHex(0xFFFFFF),
        edge: .glassHex(0xE2E1E7), hi: .glassWhite(0)
    )

    static func resolved(colorScheme: ColorScheme, reduceTransparency: Bool) -> GlassPalette {
        switch (colorScheme, reduceTransparency) {
        case (.dark, true): return .reduceTransparencyDark
        case (.dark, false): return .dark
        case (_, true): return .reduceTransparencyLight
        default: return .light
        }
    }

    /// The opaque palette for the same appearance, used where glass is unavailable.
    static func solid(colorScheme: ColorScheme) -> GlassPalette {
        resolved(colorScheme: colorScheme, reduceTransparency: true)
    }

    private func replacingSurfaces(
        surface2: Color, glass: Color, glassStrong: Color, edge: Color, hi: Color
    ) -> GlassPalette {
        GlassPalette(
            fill: fill, fillText: fillText, partial: partial, bg: bg, text: text, sec: sec,
            muted: muted, accent: accent, accentInk: accentInk, track: track, coral: coral, ok: ok,
            surface: surface, surface2: surface2, line: line, glass: glass, glassStrong: glassStrong,
            edge: edge, hi: hi, tint: tint, profile2: profile2, profile3: profile3, profile4: profile4
        )
    }
}

enum GlassMetrics {
    static let panelRadius: CGFloat = 26
    static let panelSmallRadius: CGFloat = 20
    static let sheetTopRadius: CGFloat = 34
    static let calendarTileRadius: CGFloat = 12
    static let iconTileRadius: CGFloat = 10
    static let dialogRadius: CGFloat = 30
    static let widgetRadius: CGFloat = 26

    static let screenMargin: CGFloat = 16
    static let sectionGap: CGFloat = 16
    static let panelPadding: CGFloat = 16
    static let rowMinHeight: CGFloat = 48
    static let rowWithSubtitleMinHeight: CGFloat = 58
    static let touchTarget: CGFloat = 44
    static let tabBarBottomOffset: CGFloat = 26
    static let scrollBottomInset: CGFloat = 120

    static let switchSize = CGSize(width: 60, height: 30)
    static let switchKnobSize = CGSize(width: 38, height: 26)
    static let segmentedHeight: CGFloat = 32
    static let primaryButtonHeight: CGFloat = 52
    static let tabBarHeight: CGFloat = 62
    static let chipHeight: CGFloat = 40
    static let issueDotSize: CGFloat = 5
}

/// Type scale from `tokens.json`. Sizes scale with Dynamic Type.
enum GlassTextStyle {
    case largeTitle, screenTitle, navTitle, body, rowSubtitle, caption, heroNumber, sentence, monoBody

    fileprivate var size: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .screenTitle: return 30
        case .navTitle: return 17
        case .body: return 16
        case .rowSubtitle, .monoBody: return 12.5
        case .caption: return 13
        case .heroNumber: return 56
        case .sentence: return 24
        }
    }

    fileprivate var weight: Font.Weight {
        switch self {
        case .largeTitle, .screenTitle, .heroNumber: return .bold
        case .navTitle, .caption: return .semibold
        case .sentence: return .medium
        case .body, .rowSubtitle, .monoBody: return .regular
        }
    }

    fileprivate var tracking: CGFloat {
        switch self {
        case .largeTitle: return -0.6
        case .heroNumber: return -2.5
        default: return 0
        }
    }

    fileprivate var relativeStyle: Font.TextStyle {
        switch self {
        case .largeTitle, .heroNumber: return .largeTitle
        case .screenTitle: return .title
        case .sentence: return .title2
        case .navTitle: return .headline
        case .body: return .body
        case .rowSubtitle, .monoBody: return .footnote
        case .caption: return .caption
        }
    }

    fileprivate var design: Font.Design { self == .monoBody ? .monospaced : .default }
}

private struct GlassFontModifier: ViewModifier {
    let style: GlassTextStyle
    @ScaledMetric private var size: CGFloat

    init(_ style: GlassTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight, design: style.design))
            .tracking(style.tracking)
    }
}

private struct GlassPaletteKey: EnvironmentKey {
    static var defaultValue: GlassPalette { .dark }
}

extension EnvironmentValues {
    var glassPalette: GlassPalette {
        get { self[GlassPaletteKey.self] }
        set { self[GlassPaletteKey.self] = newValue }
    }
}

private struct GlassThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.environment(
            \.glassPalette,
            GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
        )
    }
}

extension View {
    func glassFont(_ style: GlassTextStyle) -> some View {
        modifier(GlassFontModifier(style))
    }

    /// Resolves `glassPalette` for this subtree. Apply once at the shell root.
    func glassTheme() -> some View {
        modifier(GlassThemeModifier())
    }
}

extension Color {
    static func glassHex(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func glassWhite(_ opacity: Double) -> Color {
        Color(.sRGB, red: 1, green: 1, blue: 1, opacity: opacity)
    }
}

#if os(iOS)
import UIKit

extension Color {
    /// `legacy` with the flag off; the matching glass token with it on, for both appearances.
    /// Lets a large existing flow take the glass palette without touching its logic.
    static func glassAdaptive(_ legacy: Color, _ token: KeyPath<GlassPalette, Color>) -> Color {
        guard NewExperienceFeature.isEnabled else { return legacy }
        return Color(uiColor: UIColor { traits in
            let palette: GlassPalette = traits.userInterfaceStyle == .dark ? .dark : .light
            return UIColor(palette[keyPath: token])
        })
    }
}
#endif
