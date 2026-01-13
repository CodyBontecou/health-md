import SwiftUI

// MARK: - Minimal Clean Background
// No animations, no gradients - just clean solid color

struct AnimatedMeshBackground: View {
    var body: some View {
        Color.bgPrimary
            .ignoresSafeArea()
    }
}

// MARK: - Minimal Header
// Clean, direct, no animations or decorative elements

struct AnimatedHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Small uppercase label
            Text("HEALTH EXPORTER")
                .font(Typography.labelUppercase())
                .foregroundStyle(.textMuted)
                .tracking(1.5)

            // Main title
            Text("Health to Obsidian")
                .font(Typography.displayLarge())
                .foregroundStyle(.textPrimary)

            // Subtitle
            Text("Export your wellness data to markdown")
                .font(Typography.body())
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
    }
}
