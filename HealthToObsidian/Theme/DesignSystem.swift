import SwiftUI

// MARK: - Color Palette
// Minimal aesthetic inspired by Teenage Engineering & codybontecou.com

extension Color {
    // Neutral background - clean and restrained
    static let bgPrimary = Color(hex: "0F0E12")      // Near-black, subtle warmth
    static let bgSecondary = Color(hex: "1A1A1D")    // Slightly lighter for elevation
    static let bgTertiary = Color(hex: "242428")     // Cards and surfaces

    // Borders - subtle separation
    static let borderSubtle = Color(hex: "2A2A2E")   // Minimal contrast
    static let borderDefault = Color(hex: "3A3A3E")  // Standard borders
    static let borderStrong = Color(hex: "4A4A4E")   // Focused/hover

    // Text hierarchy - high contrast, readable
    static let textPrimary = Color(hex: "E8E8E8")    // Primary text
    static let textSecondary = Color(hex: "A8A8A8")  // Secondary text
    static let textMuted = Color(hex: "6A6A6E")      // Muted/disabled

    // Single accent color - strategic use only
    static let accent = Color(hex: "5B8DEF")         // Calm blue, not too bright
    static let accentHover = Color(hex: "7AA3F2")    // Hover state
    static let accentSubtle = Color(hex: "5B8DEF").opacity(0.15) // Backgrounds

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

// MARK: - Minimal Fills (No Gradients)
// Flat colors only - no decorative gradients

struct AppFills {
    // Use solid colors for all fills
    // Gradients removed for minimal aesthetic
}

// MARK: - Animation Timings
// Subtle, fast, functional - no decorative animations

struct AnimationTimings {
    static let fast = Animation.easeInOut(duration: 0.15)        // Quick transitions
    static let standard = Animation.easeInOut(duration: 0.2)     // Standard interactions
    static let smooth = Animation.easeOut(duration: 0.25)        // Smooth movements
    // Removed pulse and stagger - too decorative for minimal aesthetic
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
    // Display - clean geometric sans-serif (no rounded)
    static func displayLarge() -> Font {
        .system(size: 32, weight: .semibold, design: .default)
    }

    static func displayMedium() -> Font {
        .system(size: 24, weight: .medium, design: .default)
    }

    // Headlines - clean and direct
    static func headline() -> Font {
        .system(size: 17, weight: .medium, design: .default)
    }

    static func headlineEmphasis() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }

    // Body text - highly readable
    static func body() -> Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    static func bodyEmphasis() -> Font {
        .system(size: 15, weight: .medium, design: .default)
    }

    // Monospace - for technical info (paths, values)
    static func mono() -> Font {
        .system(size: 13, weight: .regular, design: .monospaced)
    }

    static func monoEmphasis() -> Font {
        .system(size: 13, weight: .medium, design: .monospaced)
    }

    // Small text - captions and labels
    static func caption() -> Font {
        .system(size: 12, weight: .regular, design: .default)
    }

    static func label() -> Font {
        .system(size: 11, weight: .medium, design: .default)
    }

    // Uppercase labels - strategic use
    static func labelUppercase() -> Font {
        .system(size: 10, weight: .semibold, design: .default)
    }
}

// MARK: - Minimal Card Modifier
// Simple borders, no glass effects or gradients

struct MinimalCard: ViewModifier {
    var cornerRadius: CGFloat = 8   // Reduced corner radius for sharper look
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderDefault, lineWidth: 1)
            )
    }
}

extension View {
    func minimalCard(cornerRadius: CGFloat = 8, padding: CGFloat = Spacing.lg) -> some View {
        modifier(MinimalCard(cornerRadius: cornerRadius, padding: padding))
    }

    // Keep old name for compatibility
    func glassCard(cornerRadius: CGFloat = 8, padding: CGFloat = Spacing.lg) -> some View {
        modifier(MinimalCard(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Subtle Shadow (No Glows)
// Minimal depth with single subtle shadow

extension View {
    func subtleShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    // Deprecated - minimal aesthetic doesn't use glows
    func glow(_ color: Color, radius: CGFloat = 10) -> some View {
        self // Return self without glow
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
