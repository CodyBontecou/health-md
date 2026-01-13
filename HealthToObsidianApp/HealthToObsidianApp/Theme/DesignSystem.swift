import SwiftUI

// MARK: - Color Palette

extension Color {
    // Deep background colors
    static let bgPrimary = Color(hex: "0A0A12")
    static let bgSecondary = Color(hex: "12121F")
    static let bgTertiary = Color(hex: "1A1A2E")

    // Accent colors - warm health tones
    static let healthCoral = Color(hex: "FF6B6B")
    static let healthRose = Color(hex: "F472B6")
    static let healthAmber = Color(hex: "FBBF24")
    static let healthPulse = Color(hex: "FF8585")

    // Obsidian crystal tones
    static let obsidianPurple = Color(hex: "A855F7")
    static let obsidianViolet = Color(hex: "8B5CF6")
    static let obsidianIndigo = Color(hex: "6366F1")
    static let obsidianDeep = Color(hex: "4C1D95")

    // Functional colors
    static let successGlow = Color(hex: "34D399")
    static let errorGlow = Color(hex: "F87171")
    static let textPrimary = Color(hex: "F8FAFC")
    static let textSecondary = Color(hex: "94A3B8")
    static let textMuted = Color(hex: "64748B")

    // Glass effect colors
    static let glassBorder = Color.white.opacity(0.1)
    static let glassBackground = Color.white.opacity(0.05)

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

// MARK: - Gradients

struct AppGradients {
    static let backgroundMesh = MeshGradient(
        width: 3,
        height: 3,
        points: [
            [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
            [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
            [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
        ],
        colors: [
            .bgPrimary, .bgSecondary, .bgPrimary,
            .bgSecondary, Color(hex: "1E1B4B"), .bgSecondary,
            .bgPrimary, .bgSecondary, .bgPrimary
        ]
    )

    static let healthGradient = LinearGradient(
        colors: [.healthCoral, .healthRose],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let obsidianGradient = LinearGradient(
        colors: [.obsidianPurple, .obsidianIndigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let exportGradient = LinearGradient(
        colors: [.obsidianViolet, .healthRose],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let successGradient = LinearGradient(
        colors: [.successGlow, Color(hex: "10B981")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGlow = RadialGradient(
        colors: [.obsidianPurple.opacity(0.3), .clear],
        center: .center,
        startRadius: 0,
        endRadius: 200
    )
}

// MARK: - Animation Timings

struct AnimationTimings {
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let springSmooth = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let easeOutExpo = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
    static let pulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    static let stagger = 0.08
}

// MARK: - Spacing System

struct Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Typography

struct Typography {
    static func displayLarge() -> Font {
        .system(size: 34, weight: .bold, design: .rounded)
    }

    static func displayMedium() -> Font {
        .system(size: 28, weight: .semibold, design: .rounded)
    }

    static func headline() -> Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }

    static func body() -> Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    static func bodyMono() -> Font {
        .system(size: 15, weight: .medium, design: .monospaced)
    }

    static func caption() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }

    static func label() -> Font {
        .system(size: 12, weight: .semibold, design: .rounded)
    }
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.glassBackground)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24, padding: CGFloat = Spacing.lg) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Glow Effect Modifier

struct GlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.3), radius: radius * 2, x: 0, y: 4)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 10) -> some View {
        modifier(GlowEffect(color: color, radius: radius))
    }
}

// MARK: - Staggered Animation Modifier

struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .onAppear {
                withAnimation(
                    AnimationTimings.easeOutExpo.delay(Double(index) * AnimationTimings.stagger)
                ) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}
