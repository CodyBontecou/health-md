import SwiftUI

// MARK: - Animated Mesh Background

struct AnimatedMeshBackground: View {
    @State private var phase: CGFloat = 0
    @State private var t: Float = 0.0
    let timer = Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base dark gradient
                LinearGradient(
                    colors: [.bgPrimary, .bgSecondary, .bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Animated mesh gradient
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [sinInRange(-0.8...(-0.2), offset: 0.439, timeScale: 0.342), sinInRange(0.3...0.7, offset: 3.42, timeScale: 0.984)],
                        [sinInRange(0.1...0.8, offset: 0.239, timeScale: 0.084), sinInRange(0.2...0.8, offset: 5.21, timeScale: 0.242)],
                        [sinInRange(1.0...1.5, offset: 0.939, timeScale: 0.084), sinInRange(0.4...0.8, offset: 0.25, timeScale: 0.642)],
                        [sinInRange(-0.8...0.0, offset: 1.439, timeScale: 0.442), sinInRange(1.4...1.9, offset: 3.42, timeScale: 0.984)],
                        [sinInRange(0.3...0.6, offset: 0.339, timeScale: 0.784), sinInRange(1.0...1.2, offset: 1.22, timeScale: 0.772)],
                        [sinInRange(1.0...1.5, offset: 0.939, timeScale: 0.056), sinInRange(1.3...1.7, offset: 0.47, timeScale: 0.342)]
                    ],
                    colors: [
                        .bgPrimary, Color(hex: "1E1B4B").opacity(0.8), .bgPrimary,
                        Color(hex: "312E81").opacity(0.5), .obsidianDeep.opacity(0.4), Color(hex: "1E1B4B").opacity(0.6),
                        .bgPrimary, Color(hex: "312E81").opacity(0.3), .bgPrimary
                    ],
                    smoothsColors: true
                )
                .opacity(0.7)

                // Floating orbs
                FloatingOrb(
                    color: .healthCoral,
                    size: 200,
                    position: CGPoint(
                        x: geometry.size.width * 0.8,
                        y: geometry.size.height * 0.15
                    ),
                    phase: phase
                )
                .blur(radius: 60)
                .opacity(0.3)

                FloatingOrb(
                    color: .obsidianPurple,
                    size: 300,
                    position: CGPoint(
                        x: geometry.size.width * 0.2,
                        y: geometry.size.height * 0.7
                    ),
                    phase: phase + .pi
                )
                .blur(radius: 80)
                .opacity(0.25)

                // Subtle noise overlay
                Rectangle()
                    .fill(
                        ImagePaint(
                            image: Image(systemName: "circle.fill"),
                            scale: 0.005
                        )
                    )
                    .opacity(0.02)
                    .blendMode(.overlay)
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            t += 0.01
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    private func sinInRange(_ range: ClosedRange<Float>, offset: Float, timeScale: Float) -> Float {
        let amplitude = (range.upperBound - range.lowerBound) / 2
        let midPoint = (range.upperBound + range.lowerBound) / 2
        return midPoint + amplitude * sin(timeScale * t + offset)
    }
}

// MARK: - Floating Orb

struct FloatingOrb: View {
    let color: Color
    let size: CGFloat
    let position: CGPoint
    let phase: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.5), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .position(
                x: position.x + cos(phase) * 30,
                y: position.y + sin(phase * 0.7) * 20
            )
    }
}

// MARK: - Header Title

struct AnimatedHeader: View {
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "heart.text.clipboard.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppGradients.healthGradient)
                    .symbolEffect(.pulse, options: .repeating, value: isVisible)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.textMuted)

                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppGradients.obsidianGradient)
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -10)

            Text("Health to Obsidian")
                .font(Typography.displayLarge())
                .foregroundStyle(.textPrimary)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)

            Text("Export your wellness journey")
                .font(Typography.body())
                .foregroundStyle(.textSecondary)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.md)
        .onAppear {
            withAnimation(AnimationTimings.easeOutExpo.delay(0.1)) {
                isVisible = true
            }
        }
    }
}
