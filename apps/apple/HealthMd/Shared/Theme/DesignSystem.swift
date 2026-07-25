import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Geist Design Tokens
// Tokens are sourced from DESIGN.md and design.dark.md. iOS and macOS share the
// same Geist vocabulary so the app presents one visual system across platforms.

extension Color {
    #if os(iOS)
    // Backgrounds
    static let bgPrimary = adaptiveColor(light: "FFFFFF", dark: "000000")
    static let bgSecondary = adaptiveColor(light: "FAFAFA", dark: "000000")
    static let bgTertiary = adaptiveColor(light: "FFFFFF", dark: "1A1A1A")

    // Geist gray scale
    static let geistGray100 = adaptiveColor(light: "F2F2F2", dark: "1A1A1A")
    static let geistGray200 = adaptiveColor(light: "EBEBEB", dark: "1F1F1F")
    static let geistGray300 = adaptiveColor(light: "E6E6E6", dark: "292929")
    static let geistGray400 = adaptiveColor(light: "EAEAEA", dark: "2E2E2E")
    static let geistGray500 = adaptiveColor(light: "C9C9C9", dark: "454545")
    static let geistGray600 = adaptiveColor(light: "A8A8A8", dark: "878787")
    static let geistGray700 = adaptiveColor(light: "8F8F8F", dark: "8F8F8F")
    static let geistGray800 = adaptiveColor(light: "7D7D7D", dark: "7D7D7D")
    static let geistGray900 = adaptiveColor(light: "4D4D4D", dark: "A0A0A0")
    static let geistGray1000 = adaptiveColor(light: "171717", dark: "EDEDED")

    // Borders
    static let borderSubtle = adaptiveColor(light: "EAEAEA", dark: "2E2E2E")
    static let borderDefault = adaptiveColor(light: "C9C9C9", dark: "454545")
    static let borderStrong = adaptiveColor(light: "A8A8A8", dark: "878787")

    // Text hierarchy
    static let textPrimary = adaptiveColor(light: "171717", dark: "EDEDED")
    static let textSecondary = adaptiveColor(light: "4D4D4D", dark: "A0A0A0")
    static let textMuted = adaptiveColor(light: "8F8F8F", dark: "8F8F8F")

    // Accent and semantic states
    static let accent = adaptiveColor(light: "8A66AA", dark: "A37DBD")
    static let accentHover = adaptiveColor(light: "7D50A3", dark: "BFA4D4")
    static let accentSubtle = adaptiveColor(light: "F8F3FB", dark: "1E1439")
    static let success = adaptiveColor(light: "28A948", dark: "00AC3A")
    static let error = adaptiveColor(light: "EA001D", dark: "E2162A")
    static let warning = adaptiveColor(light: "AA4D00", dark: "FF9300")

    // Component surfaces
    static let controlBackground = adaptiveColor(light: "FFFFFF", dark: "000000")
    static let controlPressed = adaptiveColor(light: "F2F2F2", dark: "1A1A1A")
    static let selectedBackground = adaptiveColor(light: "F8F3FB", dark: "1E1439")
    #elseif os(macOS)
    // Backgrounds
    static let bgPrimary = adaptiveColor(light: "FFFFFF", dark: "000000")
    static let bgSecondary = adaptiveColor(light: "FAFAFA", dark: "000000")
    static let bgTertiary = adaptiveColor(light: "FFFFFF", dark: "1A1A1A")

    // Geist gray scale
    static let geistGray100 = adaptiveColor(light: "F2F2F2", dark: "1A1A1A")
    static let geistGray200 = adaptiveColor(light: "EBEBEB", dark: "1F1F1F")
    static let geistGray300 = adaptiveColor(light: "E6E6E6", dark: "292929")
    static let geistGray400 = adaptiveColor(light: "EAEAEA", dark: "2E2E2E")
    static let geistGray500 = adaptiveColor(light: "C9C9C9", dark: "454545")
    static let geistGray600 = adaptiveColor(light: "A8A8A8", dark: "878787")
    static let geistGray700 = adaptiveColor(light: "8F8F8F", dark: "8F8F8F")
    static let geistGray800 = adaptiveColor(light: "7D7D7D", dark: "7D7D7D")
    static let geistGray900 = adaptiveColor(light: "4D4D4D", dark: "A0A0A0")
    static let geistGray1000 = adaptiveColor(light: "171717", dark: "EDEDED")

    // Borders
    static let borderSubtle = adaptiveColor(light: "EAEAEA", dark: "2E2E2E")
    static let borderDefault = adaptiveColor(light: "C9C9C9", dark: "454545")
    static let borderStrong = adaptiveColor(light: "A8A8A8", dark: "878787")

    // Text hierarchy
    static let textPrimary = adaptiveColor(light: "171717", dark: "EDEDED")
    static let textSecondary = adaptiveColor(light: "4D4D4D", dark: "A0A0A0")
    static let textMuted = adaptiveColor(light: "8F8F8F", dark: "8F8F8F")

    // Accent and semantic states
    static let accent = adaptiveColor(light: "8A66AA", dark: "A37DBD")
    static let accentHover = adaptiveColor(light: "7D50A3", dark: "BFA4D4")
    static let accentSubtle = adaptiveColor(light: "F8F3FB", dark: "1E1439")
    static let success = adaptiveColor(light: "28A948", dark: "00AC3A")
    static let error = adaptiveColor(light: "EA001D", dark: "E2162A")
    static let warning = adaptiveColor(light: "AA4D00", dark: "FF9300")

    // Component surfaces
    static let controlBackground = adaptiveColor(light: "FFFFFF", dark: "000000")
    static let controlPressed = adaptiveColor(light: "F2F2F2", dark: "1A1A1A")
    static let selectedBackground = adaptiveColor(light: "F8F3FB", dark: "1E1439")
    #endif

    private static func adaptiveColor(light: String, dark: String) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traitCollection in
            UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: bestMatch == .darkAqua ? dark : light)
        })
        #else
        return Color(hex: light)
        #endif
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: String) {
        let components = rgbaComponents(from: hex)
        self.init(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: String) {
        let components = rgbaComponents(from: hex)
        self.init(
            calibratedRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }
}
#endif

private func rgbaComponents(from hexString: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3:
        (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6:
        (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8:
        (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
        (a, r, g, b) = (255, 0, 0, 0)
    }

    return (
        red: CGFloat(Double(r) / 255),
        green: CGFloat(Double(g) / 255),
        blue: CGFloat(Double(b) / 255),
        alpha: CGFloat(Double(a) / 255)
    )
}

// MARK: - Animation Timings

struct AnimationTimings {
    static let fast = Animation.easeInOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.2)
    static let smooth = Animation.easeOut(duration: 0.25)
}

// MARK: - Spacing System
// Geist 4px scale with legacy aliases retained for existing views.

struct Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s16: CGFloat = 64
    static let s24: CGFloat = 96

    static let xs: CGFloat = s1
    static let sm: CGFloat = s2
    static let md: CGFloat = s4
    static let lg: CGFloat = s6
    static let xl: CGFloat = s8
    static let xxl: CGFloat = s10
    static let xxxl: CGFloat = s16
}

// MARK: - Radii

struct GeistRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let full: CGFloat = 9999
}

// MARK: - Typography
// Geist Sans/Mono are represented with SF Pro/SF Mono on iOS for native Dynamic
// Type behavior while preserving the token names used in DESIGN.md.

struct Typography {
    static func hero() -> Font { .system(size: 32, weight: .semibold, design: .default) }
    static func displayLarge() -> Font { .system(size: 32, weight: .semibold, design: .default) }
    static func displayMedium() -> Font { .system(size: 24, weight: .semibold, design: .default) }
    static func heading24() -> Font { .system(size: 24, weight: .semibold, design: .default) }
    static func heading20() -> Font { .system(size: 20, weight: .semibold, design: .default) }
    static func headline() -> Font { .system(size: 16, weight: .semibold, design: .default) }
    static func headlineEmphasis() -> Font { .system(size: 16, weight: .semibold, design: .default) }
    static func bodyLarge() -> Font { .system(size: 18, weight: .regular, design: .default) }
    static func body() -> Font { .system(size: 14, weight: .regular, design: .default) }
    static func bodyEmphasis() -> Font { .system(size: 14, weight: .medium, design: .default) }
    static func caption() -> Font { .system(size: 13, weight: .regular, design: .default) }
    static func label() -> Font { .system(size: 12, weight: .medium, design: .default) }
    static func labelUppercase() -> Font { .system(size: 12, weight: .medium, design: .default) }
    static func mono() -> Font { .system(size: 14, weight: .regular, design: .monospaced) }
    static func monoEmphasis() -> Font { .system(size: 14, weight: .medium, design: .monospaced) }
    static func monoCaption() -> Font { .system(size: 12, weight: .regular, design: .monospaced) }
    static func monoCaptionEmphasis() -> Font { .system(size: 12, weight: .medium, design: .monospaced) }
    static func monoLabel() -> Font { .system(size: 12, weight: .medium, design: .monospaced) }
    static func bodyMono() -> Font { mono() }
}

// MARK: - Branded Page Header

struct HealthMdSidebarToggle {
    let isSidebarVisible: Bool
    let toggle: () -> Void
}

private struct HealthMdSidebarToggleKey: EnvironmentKey {
    static let defaultValue: HealthMdSidebarToggle? = nil
}

extension EnvironmentValues {
    var healthMdSidebarToggle: HealthMdSidebarToggle? {
        get { self[HealthMdSidebarToggleKey.self] }
        set { self[HealthMdSidebarToggleKey.self] = newValue }
    }
}

struct HealthMdPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @Environment(\.healthMdSidebarToggle) private var sidebarToggle

    private let accessory: Accessory

    init(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                if let sidebarToggle, !sidebarToggle.isSidebarVisible {
                    Button(action: sidebarToggle.toggle) {
                        Label("Show Sidebar", systemImage: "arrow.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Color.accent)
                    .accessibilityLabel("Show sidebar")
                    .accessibilityHint("Reopens the iPad navigation sidebar")
                }

                HStack(spacing: Spacing.s2) {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                                .strokeBorder(Color.borderSubtle, lineWidth: 1)
                        )
                        .accessibilityHidden(true)

                    Text("health.md")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)
                        .tracking(-0.2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("health.md")

                Spacer(minLength: Spacing.s3)
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.heading24())
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.s1)
        .accessibilityElement(children: .contain)
    }
}

extension HealthMdPageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

// MARK: - Geist Surfaces

struct GeistCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GeistRadius.md
    var padding: CGFloat = Spacing.s6
    var outlined: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if outlined {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                }
            }
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
    }
}

struct GeistInsetCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GeistRadius.sm
    var padding: CGFloat = Spacing.s4

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }
}

struct GeistPillModifier: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background((tint ?? Color.bgPrimary).opacity(tint == nil ? 1 : 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder((tint ?? Color.borderSubtle).opacity(tint == nil ? 1 : 0.35), lineWidth: 1))
    }
}

extension View {
    func geistCard(cornerRadius: CGFloat = GeistRadius.md, padding: CGFloat = Spacing.s6) -> some View {
        modifier(GeistCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func geistInsetCard(cornerRadius: CGFloat = GeistRadius.sm, padding: CGFloat = Spacing.s4) -> some View {
        modifier(GeistInsetCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func geistPill(tint: Color? = nil) -> some View {
        modifier(GeistPillModifier(tint: tint))
    }

    // Compatibility aliases: existing iOS code can keep the old names while the
    // implementation now follows the Geist card recipe instead of glass.
    func liquidGlassCard(cornerRadius: CGFloat = GeistRadius.md, padding: CGFloat = Spacing.s6) -> some View {
        geistCard(cornerRadius: cornerRadius, padding: padding)
    }

    func minimalCard(cornerRadius: CGFloat = GeistRadius.md, padding: CGFloat = Spacing.s6) -> some View {
        geistCard(cornerRadius: cornerRadius, padding: padding)
    }

    func glassCard(cornerRadius: CGFloat = GeistRadius.md, padding: CGFloat = Spacing.s6) -> some View {
        geistCard(cornerRadius: cornerRadius, padding: padding)
    }

    func subtleShadow() -> some View {
        shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
    }

    func liquidGlassShadow() -> some View {
        subtleShadow()
    }

    func softGlow(_ color: Color, radius: CGFloat = 0) -> some View {
        self
    }
}

// MARK: - iPad Compatibility

struct iPadLiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = GeistRadius.md
    var minHeight: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
    }
}

extension View {
    func iPadLiquidGlass(cornerRadius: CGFloat = GeistRadius.md, minHeight: CGFloat? = nil) -> some View {
        modifier(iPadLiquidGlassModifier(cornerRadius: cornerRadius, minHeight: minHeight))
    }

    func iPadContentColumn(maxWidth: CGFloat = 760) -> some View {
        self
            .frame(maxWidth: maxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    func iPadPageBackground() -> some View {
        background(Color.bgPrimary.ignoresSafeArea())
    }

    @ViewBuilder
    func iPadHiddenSystemNavigationTitle() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .navigationBar)
        } else {
            self.navigationBarHidden(true)
        }
        #else
        self
        #endif
    }
}

struct iPadSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Typography.label())
            .foregroundStyle(Color.textSecondary)
            .tracking(-0.1)
    }
}

// MARK: - Capsule Compatibility

struct LiquidGlassCapsuleModifier: ViewModifier {
    var tint: Color? = nil
    var isInteractive: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background((tint ?? Color.bgPrimary).opacity(tint == nil ? 1 : 0.12), in: Capsule())
            .overlay(Capsule().strokeBorder((tint ?? Color.borderSubtle).opacity(tint == nil ? 1 : 0.35), lineWidth: 1))
    }
}

// MARK: - Simple Fade Animation

struct SimpleFade: ViewModifier {
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(AnimationTimings.smooth) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func simpleFade() -> some View {
        modifier(SimpleFade())
    }

    func staggeredAppear(index: Int) -> some View {
        self
    }
}

// MARK: - macOS Geist Components

#if os(macOS)

struct BrandLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.label())
            .foregroundStyle(Color.textSecondary)
            .tracking(-0.1)
    }
}

struct BrandGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GeistRadius.md
    var tintOpacity: Double = 0

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.bgPrimary)
                    if tintOpacity > 0 {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accent.opacity(tintOpacity))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
    }
}

struct BrandGlassPillModifier: ViewModifier {
    var tintColor: Color = .clear

    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(Color.bgPrimary)
                    .overlay(Capsule().fill(tintColor.opacity(0.10)))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
                    .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
            )
    }
}

struct BrandGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.accent, in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .foregroundStyle(Color.bgPrimary)
    }
}

extension View {
    func brandGlassCard(cornerRadius: CGFloat = 16, tintOpacity: Double = 0.06) -> some View {
        modifier(BrandGlassCardModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }

    func brandGlassPill(tint: Color = .clear) -> some View {
        modifier(BrandGlassPillModifier(tintColor: tint))
    }

    func brandGlassButton() -> some View {
        modifier(BrandGlassButtonModifier())
    }
}

struct BrandTypography {
    static func sectionLabel() -> Font { Typography.label() }
    static func heading() -> Font { Typography.heading24() }
    static func subheading() -> Font { Typography.headline() }
    static func body() -> Font { Typography.body() }
    static func bodyMedium() -> Font { Typography.bodyEmphasis() }
    static func detail() -> Font { Typography.caption() }
    static func value() -> Font { Typography.bodyEmphasis() }
    static func caption() -> Font { Typography.caption() }
}

struct BrandDataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(BrandTypography.body())
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(BrandTypography.value())
                .foregroundStyle(Color.textPrimary)
        }
    }
}

#endif
