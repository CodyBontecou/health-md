import SwiftUI

// MARK: - Geist Buttons

struct PrimaryButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let icon: String
    let gradient: LinearGradient? // retained for source compatibility
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
            HStack(spacing: Spacing.s2) {
                if isLoading {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                            .accessibilityHidden(true)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.bgPrimary))
                            .scaleEffect(0.82)
                            .accessibilityHidden(true)
                    }
                } else {
                    Image(systemName: icon)
                        .accessibilityHidden(true)
                }

                Text(LocalizedStringKey(isLoading ? "Exporting…" : title))
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.bgPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.horizontal, Spacing.s4)
            .background(isDisabled ? Color.geistGray300 : (isPressed ? Color.geistGray900 : Color.geistGray1000))
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.7 : 1)
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.99 : 1.0))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation { isPressed = pressing }
        }, perform: {})
        .accessibilityLabel(isLoading ? "Exporting" : title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isDisabled ? "Button disabled" : "Double tap to activate")
        .accessibilityValue(isLoading ? "In progress" : "")
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(AnimationTimings.fast, updates)
        }
    }
}

struct SecondaryButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            HStack(spacing: Spacing.s2) {
                if let icon {
                    Image(systemName: icon)
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .medium, design: .default))
            }
            .foregroundStyle(color)
            .frame(minHeight: 40)
            .padding(.horizontal, Spacing.s3)
            .background(isPressed ? Color.controlPressed : Color.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.99 : 1.0))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation { isPressed = pressing }
        }, perform: {})
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to activate")
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(AnimationTimings.fast, updates)
        }
    }
}

struct IconButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let color: Color
    let size: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isPressed = false

    init(
        icon: String,
        color: Color = .textPrimary,
        size: CGFloat = 40,
        accessibilityLabel: String = "Button",
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.color = color
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(isPressed ? Color.controlPressed : Color.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.98 : 1.0))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation { isPressed = pressing }
        }, perform: {})
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to activate")
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(AnimationTimings.fast, updates)
        }
    }
}

struct DestructiveButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Color.error)
                .frame(minHeight: 40)
                .padding(.horizontal, Spacing.s3)
                .background(isPressed ? Color.controlPressed : Color.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(Color.error.opacity(0.35), lineWidth: 1)
                )
                .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.99 : 1.0))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withOptionalMotionAnimation { isPressed = pressing }
        }, perform: {})
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to \(title.lowercased())")
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(AnimationTimings.fast, updates)
        }
    }
}
