import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color Palette
// Health.md adaptive theme with signature purple accent.
// These tokens follow the user's system appearance instead of requiring a
// global color-scheme override.

extension Color {
    #if os(iOS)
    // Neutral backgrounds
    static let bgPrimary = adaptiveColor(light: "FAFAFA", dark: "141414")
    static let bgSecondary = adaptiveColor(light: "F1F1F4", dark: "1E1E1E")
    static let bgTertiary = adaptiveColor(light: "FFFFFF", dark: "262626")

    // Borders
    static let borderSubtle = adaptiveColor(light: "E1E1E6", dark: "2E2E2E")
    static let borderDefault = adaptiveColor(light: "CACAD2", dark: "3E3E3E")
    static let borderStrong = adaptiveColor(light: "A8A8B3", dark: "4E4E4E")

    // Text hierarchy
    static let textPrimary = adaptiveColor(light: "18181B", dark: "E8E8E8")
    static let textSecondary = adaptiveColor(light: "4B4B55", dark: "A8A8A8")
    static let textMuted = adaptiveColor(light: "73737F", dark: "9A9AA2")

    // Signature purple accent (matching app icon crystal heart)
    static let accent = Color(hex: "9B6DD7")         // Medium purple (from icon heart)
    static let accentHover = Color(hex: "B48BE8")    // Lighter purple hover
    static let accentSubtle = Color(hex: "9B6DD7").opacity(0.15) // Backgrounds

    // Semantic colors - restrained, not vibrant
    static let success = Color(hex: "4A9B6D")        // Muted green
    static let error = Color(hex: "C74545")          // Muted red
    static let warning = Color(hex: "D4A958")        // Muted amber
    #elseif os(macOS)
    static let bgPrimary = adaptiveColor(light: "fbf9fa", dark: "0f0c0e")
    static let bgSecondary = adaptiveColor(light: "f2edf1", dark: "171316")
    static let bgTertiary = adaptiveColor(light: "ffffff", dark: "211b1f")

    static let borderSubtle = adaptiveColor(light: "e5dce2", dark: "2d2429")
    static let borderDefault = adaptiveColor(light: "d1c3cc", dark: "3a2f36")
    static let borderStrong = adaptiveColor(light: "b8a8b2", dark: "4a3d45")

    static let textPrimary = adaptiveColor(light: "1d171b", dark: "f6f1f3")
    static let textSecondary = adaptiveColor(light: "554950", dark: "c9c0c5")
    static let textMuted = adaptiveColor(light: "7d7078", dark: "8e8188")

    // Signature purple — matches website --accent: #7A57A7
    static let accent = Color(hex: "7A57A7")
    static let accentHover = Color(hex: "9B6DD7")
    static let accentSubtle = Color(hex: "7A57A7").opacity(0.15)

    static let success = Color(hex: "4A9B6D")
    static let error = Color(hex: "C74545")
    static let warning = Color(hex: "D4A958")
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
            (a, r, g, b) = (1, 1, 1, 0)
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

// MARK: - No Gradients
// Flat colors only - gradients removed for minimal aesthetic

// MARK: - Animation Timings
// Subtle, fast, functional - no decorative animations

struct AnimationTimings {
    static let fast = Animation.easeInOut(duration: 0.15)        // Quick transitions
    static let standard = Animation.easeInOut(duration: 0.2)     // Standard interactions
    static let smooth = Animation.easeOut(duration: 0.25)        // Smooth movements
}

// MARK: - Spacing System
// Generous whitespace - minimal aesthetic needs breathing room

struct Spacing {
    static let xs: CGFloat = 6      // Minimal gap
    static let sm: CGFloat = 12     // Small spacing
    static let md: CGFloat = 20     // Standard spacing (increased)
    static let lg: CGFloat = 32     // Large spacing (increased)
    static let xl: CGFloat = 48     // Extra large (increased)
    static let xxl: CGFloat = 64    // Maximum spacing (increased)
    static let xxxl: CGFloat = 96   // Section separation
}

// MARK: - Typography
// Clean geometric sans-serif + monospace for technical precision
// Now uses Dynamic Type for accessibility

struct Typography {
    // Hero - extra large for main screen titles (scales with accessibility)
    static func hero() -> Font {
        .largeTitle.weight(.bold)
    }

    // Display - clean geometric sans-serif (no rounded)
    static func displayLarge() -> Font {
        .largeTitle.weight(.bold)
    }

    static func displayMedium() -> Font {
        .title2.weight(.semibold)
    }

    // Headlines - clean and direct
    static func headline() -> Font {
        .headline
    }

    static func headlineEmphasis() -> Font {
        .headline.weight(.bold)
    }

    // Body text - highly readable
    static func body() -> Font {
        .body
    }

    static func bodyEmphasis() -> Font {
        .body.weight(.medium)
    }

    static func bodyLarge() -> Font {
        .title3
    }

    // Monospace - for technical info (paths, values)
    static func mono() -> Font {
        .subheadline.monospaced()
    }

    static func monoEmphasis() -> Font {
        .subheadline.weight(.medium).monospaced()
    }

    // Keep old bodyMono for compatibility
    static func bodyMono() -> Font {
        .subheadline.monospaced()
    }

    // Small text - captions and labels
    static func caption() -> Font {
        .subheadline
    }

    static func label() -> Font {
        .footnote.weight(.medium)
    }

    // Uppercase labels - strategic use
    static func labelUppercase() -> Font {
        .caption.weight(.semibold)
    }
}

// MARK: - Liquid Glass Card Modifier
// Apple's Liquid Glass design: frosted glass with soft borders and depth

struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 20, padding: CGFloat = Spacing.lg) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    // Aliases for compatibility
    func minimalCard(cornerRadius: CGFloat = 20, padding: CGFloat = Spacing.lg) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = Spacing.lg) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - iPad Liquid Glass Card
// Enhanced glass card with specular highlight and directional border for iPad

struct iPadLiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var minHeight: CGFloat? = nil

    func body(content: Content) -> some View {
        content
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Top specular highlight — light catching glass
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func iPadLiquidGlass(cornerRadius: CGFloat = 20, minHeight: CGFloat? = nil) -> some View {
        modifier(iPadLiquidGlassModifier(cornerRadius: cornerRadius, minHeight: minHeight))
    }
}

// MARK: - iPad Section Label Style
// Branded accent-tinted uppercase labels for iPad card headers

struct iPadSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accent.opacity(0.7))
            .tracking(2)
    }
}

// MARK: - Liquid Glass Shadows
// Soft, layered shadows for depth in the Liquid Glass design

extension View {
    func subtleShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    func liquidGlassShadow() -> some View {
        self
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    // Soft glow for interactive elements
    func softGlow(_ color: Color, radius: CGFloat = 12) -> some View {
        self.shadow(color: color.opacity(0.4), radius: radius, x: 0, y: 4)
    }
}

// MARK: - Liquid Glass Capsule
// Floating action capsule that uses iOS/macOS 26 .glassEffect when available
// and gracefully falls back to a tinted material capsule on older OS versions.

struct LiquidGlassCapsuleModifier: ViewModifier {
    var tint: Color? = nil
    var isInteractive: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            modern(content)
        } else {
            fallback(content)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @ViewBuilder
    private func modern(_ content: Content) -> some View {
        switch (tint, isInteractive) {
        case (let t?, true):
            content.glassEffect(.regular.tint(t.opacity(0.55)).interactive(), in: .capsule)
        case (let t?, false):
            content.glassEffect(.regular.tint(t.opacity(0.55)), in: .capsule)
        case (nil, true):
            content.glassEffect(.regular.interactive(), in: .capsule)
        case (nil, false):
            content.glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if let tint {
            content
                .background(
                    Capsule()
                        .fill(tint.opacity(0.7))
                        .background(Capsule().fill(.ultraThinMaterial))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: tint.opacity(0.25), radius: 14, x: 0, y: 6)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        }
    }
}

// MARK: - Simple Fade Animation
// Single fade in, no stagger

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

    // Deprecated - no stagger in minimal aesthetic
    func staggeredAppear(index: Int) -> some View {
        self // Return self without stagger
    }
}

// MARK: - macOS Brand Components (Liquid Glass + HealthMD identity)

#if os(macOS)

/// Uppercase purple monospace label — matches website section headers
/// e.g. "HOW IT WORKS", "CAPABILITIES", "PRIVACY FIRST"
struct BrandLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.medium).monospaced())
            .foregroundStyle(Color.accent)
            .kerning(2.2)
    }
}

/// Glass card with optional purple tint — primary content container
struct BrandGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tintOpacity: Double = 0.06

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Color.accent.opacity(tintOpacity)),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
        }
    }
}

/// Glass capsule for status pills and badges
struct BrandGlassPillModifier: ViewModifier {
    var tintColor: Color = .clear

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tintColor.opacity(0.15)),
                    in: .capsule
                )
        } else {
            content
                .background(Color.bgTertiary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
        }
    }
}

/// Interactive glass button — press-responsive with purple tint
struct BrandGlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Color.accent.opacity(0.12)).interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(Color.accent.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}

extension View {
    /// Apply a branded glass card container
    func brandGlassCard(cornerRadius: CGFloat = 16, tintOpacity: Double = 0.06) -> some View {
        modifier(BrandGlassCardModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }

    /// Apply a branded glass capsule (for pills / badges)
    func brandGlassPill(tint: Color = .clear) -> some View {
        modifier(BrandGlassPillModifier(tintColor: tint))
    }

    /// Apply an interactive branded glass button treatment
    func brandGlassButton() -> some View {
        modifier(BrandGlassButtonModifier())
    }
}

/// Monospace brand typography for macOS — matches JetBrains Mono from website
/// Now uses Dynamic Type for accessibility
struct BrandTypography {
    static func sectionLabel() -> Font {
        .caption.weight(.medium).monospaced()
    }
    static func heading() -> Font {
        .title2.weight(.semibold).monospaced()
    }
    static func subheading() -> Font {
        .headline.weight(.medium).monospaced()
    }
    static func body() -> Font {
        .body.monospaced()
    }
    static func bodyMedium() -> Font {
        .body.weight(.medium).monospaced()
    }
    static func detail() -> Font {
        .footnote.monospaced()
    }
    static func value() -> Font {
        .body.weight(.medium).monospaced()
    }
    static func caption() -> Font {
        .caption.monospaced()
    }
}

/// Branded data row — label on left, value on right, monospace
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
