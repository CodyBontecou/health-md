#if os(iOS)
import SwiftUI

/// Presentation only: the caller still owns selection, availability and permission guards.
/// Keeping the name/detail inside the native Toggle gives the row one named action.
struct ReadingMetricToggle: View {
    let name: String
    let detail: String
    @Binding var isOn: Bool
    var isUnavailable = false
    let accessibilityHint: String

    var body: some View {
        Toggle(isOn: $isOn) {
            ReadingMetricLabel(name: name, detail: detail, isUnavailable: isUnavailable)
                .padding(.vertical, Spacing.s3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .toggleStyle(A11ySwitchToggleStyle())
        .tint(Color.success)
        .padding(.horizontal, Spacing.s4)
        .contentShape(Rectangle())
        .disabled(isUnavailable)
        .accessibilityLabel(detail.isEmpty ? name : "\(name), \(detail)")
        .accessibilityValue(isOn ? "Enabled" : "Disabled")
        .accessibilityHint(accessibilityHint)
    }
}

struct ReadingMetricLabel: View {
    let name: String
    let detail: String
    var isUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(name)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(isUnavailable ? Color.textMuted : Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(detail)
                    .font(Typography.monoCaption())
                    .foregroundStyle(isUnavailable ? Color.textMuted : Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
}

/// The entire header expands only. Its pill is a status display, not a bulk toggle.
struct ReadingMetricCategoryHeader<Status: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let isExpanded: Bool
    let accessibilityLabel: String
    let onExpand: () -> Void
    @ViewBuilder var status: () -> Status

    var body: some View {
        Button(action: onExpand) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s2) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .accessibilityHidden(true)
                    status()
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(Spacing.s4)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap anywhere on the category to \(isExpanded ? "collapse" : "expand")")
    }
}

struct ReadingMetricCategoryStatus: View {
    let label: String
    let icon: String
    let tint: Color
    let textColor: Color

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }
}

// MARK: - Settings rows

enum SettingsStatusTone {
    case accent
    case success
    case warning
    case muted

    var foreground: Color {
        switch self {
        case .success: return Color.successText
        case .accent, .warning, .muted: return Color.textSecondary
        }
    }

    var background: Color {
        switch self {
        case .accent: return Color.accent.opacity(0.12)
        case .success: return Color.success.opacity(0.12)
        case .warning: return Color.warning.opacity(0.14)
        case .muted: return Color.bgSecondary
        }
    }

    var border: Color {
        switch self {
        case .accent: return Color.accent.opacity(0.24)
        case .success: return Color.success.opacity(0.22)
        case .warning: return Color.warning.opacity(0.25)
        case .muted: return Color.borderSubtle
        }
    }
}

struct SettingsStatusPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let text: String
    let tone: SettingsStatusTone

    private var usesExpandedLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .lineLimit(usesExpandedLayout ? nil : 1)
            .fixedSize(horizontal: false, vertical: usesExpandedLayout)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone.background))
            .overlay(Capsule().strokeBorder(tone.border, lineWidth: 1))
    }
}

/// Preserve the compact Settings rail at standard text sizes. At XXXL and
/// accessibility sizes, essential copy receives the full row width and the
/// decorative/status rail moves below it instead of compressing the text.
struct ReadingSettingsRowLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let icon: String
    let title: String
    let subtitle: String
    let status: String?
    let statusTone: SettingsStatusTone
    var identifier: String? = nil

    private var usesExpandedLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    var body: some View {
        Group {
            if usesExpandedLayout {
                expandedLayout
            } else {
                compactLayout
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var compactLayout: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(LocalizedStringKey(title))
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)

                Text(LocalizedStringKey(subtitle))
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .modifier(ReadingRowIdentifier(identifier: identifier.map { "\($0).description" }))
            }
            .layoutPriority(1)

            Spacer(minLength: Spacing.sm)

            if let status {
                SettingsStatusPill(text: status, tone: statusTone)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
    }

    private var expandedLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(LocalizedStringKey(title))
                .font(Typography.headline())
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(subtitle))
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(ReadingRowIdentifier(identifier: identifier.map { "\($0).description" }))
            if let status {
                SettingsStatusPill(text: status, tone: statusTone)
            }
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct SettingsRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let title: String
    let subtitle: String
    let status: String?
    let statusTone: SettingsStatusTone
    let isActive: Bool
    let accessibilityHint: String
    let accessibilityIdentifier: String?
    let action: () -> Void

    @State private var isPressed = false

    init(
        icon: String,
        title: String,
        subtitle: String,
        status: String? = nil,
        statusTone: SettingsStatusTone = .muted,
        isActive: Bool,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusTone = statusTone
        self.isActive = isActive
        self.accessibilityHint = accessibilityHint ?? "Double tap to open \(title)"
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ReadingSettingsRowLabel(icon: icon, title: title, subtitle: subtitle, status: status, statusTone: statusTone, identifier: accessibilityIdentifier)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPressed ? Color.bgSecondary : Color.clear)
                )
                .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.99 : 1.0))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            if reduceMotion {
                isPressed = pressing
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { isPressed = pressing }
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(status ?? (isActive ? "Configured" : "Not configured"))
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .modifier(ReadingRowIdentifier(identifier: accessibilityIdentifier))
    }
}

private struct ReadingRowIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// No guard lives here: Settings supplies the real manager's setEnabled binding.
/// Expanded text sizes move the explanation below the one native switch action.
struct ReadingProtectionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var isEnabled: Bool
    let accessibilityIdentifier: String

    private var usesExpandedLayout: Bool {
        dynamicTypeSize >= .xxxLarge
    }

    var body: some View {
        Group {
            if usesExpandedLayout {
                expandedControl
            } else {
                compactControl
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
    }

    private var compactControl: some View {
        Toggle(isOn: $isEnabled) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lock Configuration Changes")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(isEnabled
                     ? "Configuration changes are blocked on this device."
                     : "Configuration can be edited normally.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reading.protection.description")
            }
        }
        .toggleStyle(A11ySwitchToggleStyle())
        .tint(Color.accent)
        .accessibilityLabel("Prevent Accidental Changes")
        .accessibilityValue(isEnabled ? "On" : "Off")
        .accessibilityHint("Double tap to \(isEnabled ? "allow" : "prevent") configuration changes")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var expandedControl: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Toggle(isOn: $isEnabled) {
                Text("Lock Configuration Changes")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .toggleStyle(A11ySwitchToggleStyle())
            .tint(Color.accent)
            .accessibilityLabel("Prevent Accidental Changes")
            .accessibilityValue(isEnabled ? "On" : "Off")
            .accessibilityHint("Double tap to \(isEnabled ? "allow" : "prevent") configuration changes")
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(isEnabled
                 ? "Configuration changes are blocked on this device."
                 : "Configuration can be edited normally.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reading.protection.description")
        }
    }
}

// MARK: - Connection editing

/// Keeps the existing native editor/focus/keyboard supplied by Sync. The full
/// value below it remains readable even when the single-line editor scrolls to
/// the insertion point. No trimming, filtering, normalization or persistence.
struct ReadingConnectionEntry<Editor: View>: View {
    let title: String
    let value: String
    let identifier: String
    let focusEditor: () -> Void
    @ViewBuilder var editor: () -> Editor

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(LocalizedStringKey(title))
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier).label")
            editor()
                // Retain the native field's 17 pt body base size while scaling.
                .font(Typography.scaled(size: 17, monospaced: true))
                .textFieldStyle(ReadingConnectionTextFieldStyle())
                // Native editor glyph bounds do not own the style's padding.
                // Use the caller's existing focus binding, not a competing
                // private FocusState that could break submission/dismissal.
                .simultaneousGesture(TapGesture().onEnded { focusEditor() })
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
            if !value.isEmpty {
                Text(verbatim: value)
                    .font(Typography.scaled(size: 17, monospaced: true))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).value")
            }
        }
    }
}

private struct ReadingConnectionTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.bgPrimary, in: RoundedRectangle(cornerRadius: GeistRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: GeistRadius.sm).strokeBorder(Color.borderSubtle, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Full-width native actions, primary first; labels never compete for a column.
struct ReadingConnectionActions: View {
    let primaryTitle: String
    let primaryIcon: String
    let isEnabled: Bool
    let onPrimary: () -> Void
    var secondaryTitle: String? = nil
    var onSecondary: () -> Void = {}
    var identifierPrefix = "reading.connection"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onPrimary) {
                Label {
                    Text(LocalizedStringKey(primaryTitle))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: primaryIcon).accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
            .accessibilityIdentifier("\(identifierPrefix).primary")

            if let secondaryTitle {
                Button(action: onSecondary) {
                    Text(LocalizedStringKey(secondaryTitle))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("\(identifierPrefix).secondary")
            }
        }
    }
}
#endif
