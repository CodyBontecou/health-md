import SwiftUI

// MARK: - Primary Action Button
// Minimal design - flat accent color, no gradients or glows

struct PrimaryButton: View {
    let title: String
    let icon: String
    let gradient: LinearGradient?  // Kept for compatibility, but not used
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    init(
        _ title: String,
        icon: String,
        gradient: LinearGradient? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.0)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                }

                Text(isLoading ? "Exporting..." : title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(0.3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // Base gradient
                    LinearGradient(
                        colors: [
                            isPressed ? Color.accentHover : Color.accent,
                            isPressed ? Color.accentHover.opacity(0.9) : Color.accent.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Subtle inner glow
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.accent.opacity(isDisabled ? 0 : 0.3), radius: 12, x: 0, y: 4)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .opacity(isDisabled ? 0.5 : 1)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Secondary Button
// Ghost button style - border only

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    init(
        _ title: String,
        icon: String? = nil,
        color: Color = .textPrimary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(Typography.body())
            }
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isPressed ? Color.bgTertiary : Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.borderDefault, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(AnimationTimings.fast) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Icon Button
// Minimal icon-only button

struct IconButton: View {
    let icon: String
    let color: Color
    let size: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    init(
        icon: String,
        color: Color = .textPrimary,
        size: CGFloat = 36,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.color = color
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(isPressed ? Color.bgTertiary : Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.borderDefault, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(AnimationTimings.fast) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Destructive Button
// Minimal destructive action button

struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.body())
                .foregroundStyle(Color.error)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isPressed ? Color.error.opacity(0.1) : Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.error, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(AnimationTimings.fast) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
