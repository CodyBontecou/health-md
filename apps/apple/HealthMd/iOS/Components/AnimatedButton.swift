import SwiftUI

// MARK: - Native Buttons

struct PrimaryButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let icon: String
    let gradient: LinearGradient? // retained for source compatibility
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

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
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.82)
                            .accessibilityHidden(true)
                    }
                } else {
                    Image(systemName: icon)
                        .accessibilityHidden(true)
                }

                Text(LocalizedStringKey(isLoading ? "Exporting…" : title))
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, Spacing.s4)
        }
        .modifier(HealthGlassActionStyle(prominent: true))
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(isLoading ? "Exporting" : title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isDisabled ? "Button disabled" : "Double tap to activate")
        .accessibilityValue(isLoading ? "In progress" : "")
    }
}

/// Shared bordered treatment for secondary buttons and menu triggers.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = .textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .default))
            .foregroundStyle(color)
            .frame(minHeight: 40)
            .padding(.horizontal, Spacing.s3)
            .background(configuration.isPressed ? Color.controlPressed : Color.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.99 : 1.0))
            .animation(reduceMotion ? nil : AnimationTimings.fast, value: configuration.isPressed)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let color: Color
    let action: () -> Void

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
            }
        }
        .modifier(HealthGlassActionStyle())
        .tint(color)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to activate")
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
        Button(role: .destructive, action: action) {
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
