#if os(iOS)
import SwiftUI

// UI-only pieces shared by the real format screens and isolated accessibility tests.
// Callers own settings, transformations and live configuration-protection guards.

struct FormatPageScroll<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content(viewport.size.height)
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Spacing.sm : Spacing.md)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
    }
}

struct FormatSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Spacing.sm : Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bgTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
    }
}

struct FormatSelectionControl<Value: Hashable>: View {
    let title: String
    let subtitle: String
    let selection: Value
    let options: [Value]
    let optionTitle: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(LocalizedStringKey(title))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(subtitle))
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Both the closed value and native popover options keep their full
            // reading width. The popover owns its own bounded scrolling window.
            A11ySelectionMenu(selection: selection, options: options,
                              optionLabel: { Text(optionTitle($0)) }, onSelect: onSelect) {
                FormatSelectionValueLabel(value: optionTitle(selection))
            }
            .accessibilityLabel(title)
            .accessibilityValue(optionTitle(selection))
            .accessibilityIdentifier("format.selection.\(title)")
        }
        .padding(.vertical, Spacing.sm)
    }
}

/// This is the real Menu label, separately measurable without a menu-renderer placeholder.
struct FormatSelectionValueLabel: View {
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct FormatToggleControl: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // A single native, named toggle; never a row gesture plus a second switch.
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .toggleStyle(A11ySwitchToggleStyle())
            .tint(Color.accent)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isOn ? "Enabled" : "Disabled")
            .accessibilityHint(subtitle)

            // Explanations need not compete with the switch thumb for reading width.
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true) // Spoken as the toggle's hint.
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct FormatTextFieldControl: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let defaultValue: String
    let accessibilityLabel: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Default: \(defaultValue)")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(placeholder, text: $text,
                      prompt: Text(placeholder).foregroundStyle(Color.textSecondary))
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .frame(minHeight: 44)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
                // The native glyph editor keeps its intrinsic height. The entire
                // padded 44pt-or-larger control must also acquire editing focus.
                .simultaneousGesture(TapGesture().onEnded { isFocused = true })
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(text.isEmpty ? defaultValue : text)
                .accessibilityIdentifier("format.input.\(title)")

            // Keep single-line native editing semantics, including exact spaces/newlines
            // in externally supplied values. Overflow gets a wrapping reading surface,
            // not a transformed/shortened binding or a viewport-tall editing target.
            FormatOverflowValue(text: text)
                .padding(.horizontal, Spacing.sm)
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct FormatOverflowValue: View {
    let text: String

    var body: some View {
        if text.contains("\n") {
            readingValue
        } else if !text.isEmpty {
            ViewThatFits(in: .horizontal) {
                // Measure the same font at its unwrapped width. No visual text scaling.
                Text(text)
                    .font(Typography.monoCaption())
                    .fixedSize()
                    .hidden()
                    .frame(height: 0)
                    .accessibilityHidden(true)
                readingValue
            }
        }
    }

    private var readingValue: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Current Value")
                .font(.caption)
            Text(text)
                .font(Typography.monoCaption())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormatFrontmatterFieldContent<RenameButton: View>: View {
    let originalKey: String
    let customKey: String
    @Binding var isEnabled: Bool
    @ViewBuilder var renameButton: () -> RenameButton

    private var renamed: Bool { customKey != originalKey && !customKey.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: $isEnabled) {
                Text(originalKey)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary) // Off is still an operable control.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .toggleStyle(A11ySwitchToggleStyle())
            .tint(Color.accent)
            .accessibilityLabel(renamed ? "\(originalKey) renamed to \(customKey)" : originalKey)
            .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
            .accessibilityHint("Double tap to \(isEnabled ? "disable" : "enable") this field")
            .accessibilityIdentifier("format.field.toggle.\(originalKey)")

            if renamed {
                Text("Renamed to \(customKey)")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityHidden(true) // Included in the toggle's full label.
            } else {
                Text(isEnabled ? "Included in frontmatter" : "Not exported")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Kept outside the Toggle, so Rename can never also change enabled state.
            renameButton()
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct FormatFrontmatterEntry: View {
    let key: String
    let value: String
    let deleteLabel: String
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(key)
                .font(Typography.monoEmphasis())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(role: .destructive, action: onDelete) {
                FormatActionLabel(title: "Delete Field", systemImage: "trash")
                    .foregroundStyle(Color.errorText)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.error.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(deleteLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.sm)
    }
}

struct FormatTemplateEditor: View {
    @Binding var text: String
    let availableHeight: CGFloat
    @FocusState private var isFocused: Bool

    var body: some View {
        FormatSectionCard(
            title: "Custom Template",
            subtitle: "Use placeholders to control the Markdown body."
        ) {
            TextEditor(text: $text)
                .font(.caption.monospaced())
                .foregroundStyle(Color.textPrimary)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Geometry comes from outside the outer scroll, and responds to the
                // keyboard/remaining window. Content scrolls without imposing 220 pt.
                .frame(height: max(44, availableHeight / 2))
                .padding(.horizontal, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityLabel("Custom template")
                .accessibilityIdentifier("format.template.editor")

            FormatDivider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Available Placeholders")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("{{date}}, {{#section}}...{{/section}}, {{metrics}}")
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.vertical, Spacing.sm)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isFocused {
                    Spacer()
                    Button { isFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.body)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss keyboard")
                    .accessibilityIdentifier("format.template.dismiss-keyboard")
                }
            }
        }
    }
}

struct FormatNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accent.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Color.accent.opacity(0.18), lineWidth: 1))
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(title))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(LocalizedStringKey(subtitle))
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FormatValuePill(text: status)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct FormatCodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.monoCaption())
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }
}

struct FormatStatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }
}

struct FormatValuePill: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSecondary))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderSubtle, lineWidth: 1))
    }
}

struct FormatEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormatActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct FormatInlineButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FormatActionLabel(title: title, systemImage: systemImage)
                .foregroundStyle(Color.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

struct FormatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
#endif
