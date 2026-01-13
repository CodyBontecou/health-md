import SwiftUI

// MARK: - Primary Action Button
// Minimal design - flat accent color, no gradients or glows

struct PrimaryButton: View {
    let title: String
    let icon: String
    let gradient: LinearGradient  // Kept for compatibility, but not used
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    init(
        _ title: String,
        icon: String,
        gradient: LinearGradient = LinearGradient(colors: [.accent], startPoint: .leading, endPoint: .trailing),
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
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                }

                Text(isLoading ? "Exporting..." : title)
                    .font(Typography.bodyEmphasis())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isPressed ? Color.accentHover : Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isDisabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(AnimationTimings.fast) {
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
                .foregroundStyle(.error)
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
