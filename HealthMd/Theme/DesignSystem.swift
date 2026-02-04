import SwiftUI

// MARK: - Color Palette
// Health.md-inspired dark theme with signature purple

extension Color {
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

    // Signature purple accent
    static let accent = Color(hex: "8B5CF6")         // Signature purple
    static let accentHover = Color(hex: "A78BFA")    // Lighter purple hover
    static let accentSubtle = Color(hex: "8B5CF6").opacity(0.15) // Backgrounds

    // Semantic colors - restrained, not vibrant
    static let success = Color(hex: "4A9B6D")        // Muted green
    static let error = Color(hex: "C74545")          // Muted red
    static let warning = Color(hex: "D4A958")        // Muted amber

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

struct Typography {
    // Hero - extra large for main screen titles
    static func hero() -> Font {
        .system(size: 48, weight: .bold, design: .default)
    }

    // Display - clean geometric sans-serif (no rounded)
    static func displayLarge() -> Font {
        .system(size: 36, weight: .bold, design: .default)
    }

    static func displayMedium() -> Font {
        .system(size: 28, weight: .semibold, design: .default)
    }

    // Headlines - clean and direct
    static func headline() -> Font {
        .system(size: 20, weight: .semibold, design: .default)
    }

    static func headlineEmphasis() -> Font {
        .system(size: 20, weight: .bold, design: .default)
    }

    // Body text - highly readable (enlarged)
    static func body() -> Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    static func bodyEmphasis() -> Font {
        .system(size: 17, weight: .medium, design: .default)
    }

    static func bodyLarge() -> Font {
        .system(size: 19, weight: .regular, design: .default)
    }

    // Monospace - for technical info (paths, values)
    static func mono() -> Font {
        .system(size: 14, weight: .regular, design: .monospaced)
    }

    static func monoEmphasis() -> Font {
        .system(size: 14, weight: .medium, design: .monospaced)
    }

    // Keep old bodyMono for compatibility
    static func bodyMono() -> Font {
        .system(size: 14, weight: .regular, design: .monospaced)
    }

    // Small text - captions and labels
    static func caption() -> Font {
        .system(size: 14, weight: .regular, design: .default)
    }

    static func label() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }

    // Uppercase labels - strategic use
    static func labelUppercase() -> Font {
        .system(size: 12, weight: .semibold, design: .default)
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
