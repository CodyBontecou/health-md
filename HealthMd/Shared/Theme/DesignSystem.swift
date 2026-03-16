import SwiftUI

// MARK: - Color Palette
// iOS: Health.md custom dark theme with signature purple accent
// macOS: Uses system colors for native appearance

extension Color {
    #if os(iOS)
    // Neutral background - deep greys
    static let bgPrimary = Color(hex: "141414")      // Deep dark grey
    static let bgSecondary = Color(hex: "1E1E1E")    // Slightly lighter for elevation
    static let bgTertiary = Color(hex: "262626")     // Cards and surfaces

    // Borders - subtle separation
    static let borderSubtle = Color(hex: "2E2E2E")   // Minimal contrast
    static let borderDefault = Color(hex: "3E3E3E")  // Standard borders
    static let borderStrong = Color(hex: "4E4E4E")   // Focused/hover

    // Text hierarchy - high contrast, readable
    static let textPrimary = Color(hex: "E8E8E8")    // Primary text
    static let textSecondary = Color(hex: "A8A8A8")  // Secondary text
    static let textMuted = Color(hex: "6A6A6E")      // Muted/disabled

    // Signature purple accent (matching app icon crystal heart)
    static let accent = Color(hex: "9B6DD7")         // Medium purple (from icon heart)
    static let accentHover = Color(hex: "B48BE8")    // Lighter purple hover
    static let accentSubtle = Color(hex: "9B6DD7").opacity(0.15) // Backgrounds

    // Semantic colors - restrained, not vibrant
    static let success = Color(hex: "4A9B6D")        // Muted green
    static let error = Color(hex: "C74545")          // Muted red
    static let warning = Color(hex: "D4A958")        // Muted amber
    #elseif os(macOS)
    // macOS: HealthMD brand — dark palette with warm purple accent
    // Derived from healthmd.isolated.tech brand identity
    static let bgPrimary = Color(hex: "0f0c0e")       // Deep warm black
    static let bgSecondary = Color(hex: "171316")      // Slightly elevated
    static let bgTertiary = Color(hex: "211b1f")       // Cards / surfaces

    static let borderSubtle = Color(hex: "2d2429")     // Warm dark border
    static let borderDefault = Color(hex: "3a2f36")    // Standard border
    static let borderStrong = Color(hex: "4a3d45")     // Focused / hover

    static let textPrimary = Color(hex: "f6f1f3")      // Warm off-white
    static let textSecondary = Color(hex: "c9c0c5")    // Secondary copy
    static let textMuted = Color(hex: "8e8188")         // Muted / disabled

    // Signature purple — matches website --accent: #7A57A7
    static let accent = Color(hex: "7A57A7")
    static let accentHover = Color(hex: "9B6DD7")
    static let accentSubtle = Color(hex: "7A57A7").opacity(0.15)

    static let success = Color(hex: "4A9B6D")
    static let error = Color(hex: "C74545")
    static let warning = Color(hex: "D4A958")
    #endif

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
