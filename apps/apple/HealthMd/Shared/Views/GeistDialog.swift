import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Geist Dialog
// A custom modal following DESIGN.md (Geist) instead of native `.alert`.
// Surfaces: 12px radius (menus and modals), background-100 card with a subtle
// border, and the documented modal elevation shadow. Motion: ~300ms overlay
// transition with the Geist easing curve, honoring reduced-motion.
//
// Attach at the root of a full-screen (or full-window) view, e.g.:
//
//     .geistDialog(
//         isPresented: $showRollupHelp,
//         title: Text("Roll-Up Summaries"),
//         message: Text(ExportRolloutCopy.rollupSummariesHelp),
//         actions: [.action("Done", role: .secondary)]
//     )

struct GeistDialogAction {
    enum Role {
        /// Filled brand-accent button; the main action of the dialog.
        case primary
        /// Bordered quiet button; use for cancel and dismiss-only actions.
        case secondary
        /// Filled error button for destructive confirmations.
        case destructive
    }

    let label: LocalizedStringKey
    let role: Role
    let accessibilityIdentifier: String?
    let handler: () -> Void

    /// The main action. Rendered filled with the brand accent.
    static func action(
        _ label: LocalizedStringKey,
        role: Role = .primary,
        accessibilityIdentifier: String? = nil,
        handler: @escaping () -> Void = {}
    ) -> GeistDialogAction {
        GeistDialogAction(label: label, role: role, accessibilityIdentifier: accessibilityIdentifier, handler: handler)
    }

    /// A cancel/dismiss action. Rendered as a quiet bordered button.
    static func cancel(
        _ label: LocalizedStringKey = "Cancel",
        accessibilityIdentifier: String? = nil,
        handler: @escaping () -> Void = {}
    ) -> GeistDialogAction {
        GeistDialogAction(label: label, role: .secondary, accessibilityIdentifier: accessibilityIdentifier, handler: handler)
    }

    /// A destructive action. Rendered filled with the error color.
    static func destructive(
        _ label: LocalizedStringKey,
        accessibilityIdentifier: String? = nil,
        handler: @escaping () -> Void = {}
    ) -> GeistDialogAction {
        GeistDialogAction(label: label, role: .destructive, accessibilityIdentifier: accessibilityIdentifier, handler: handler)
    }
}

/// A text entry field shown between the message and the actions.
/// Configured for names/keys: autocorrection off and, on iOS, no autocapitalization.
struct GeistDialogField {
    let placeholder: LocalizedStringKey
    let text: Binding<String>

    init(placeholder: LocalizedStringKey, text: Binding<String>) {
        self.placeholder = placeholder
        self.text = text
    }
}

// MARK: - Presentation

private struct GeistDialogModifier<Presenting: View>: View {
    @Binding var isPresented: Bool
    let title: Text
    let message: Text?
    let messageAccessibilityIdentifier: String?
    let actions: [GeistDialogAction]
    let fields: [GeistDialogField]

    let presenting: Presenting

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dialogAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.15)
        }
        // DESIGN.md motion: ~300ms for overlays and modals with a snappy,
        // slightly overshooting curve (cubic-bezier(0.175, 0.885, 0.32, 1.1)).
        return .spring(duration: 0.3, bounce: 0.08)
    }

    var body: some View {
        presenting.overlay {
            ZStack {
                if isPresented {
                    Color.dialogScrim
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture(perform: performCancelDismissal)
                        .accessibilityHidden(true)

                    GeistDialogCard(
                        title: title,
                        message: message,
                        messageAccessibilityIdentifier: messageAccessibilityIdentifier,
                        actions: actions,
                        fields: fields,
                        onAction: performAction,
                        onCancel: performCancelDismissal
                    )
                    .padding(Spacing.s6)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96))
                    )
                }
            }
            .animation(dialogAnimation, value: isPresented)
        }
    }

    private func performAction(_ action: GeistDialogAction) {
        action.handler()
        isPresented = false
    }

    private func performCancelDismissal() {
        if let cancel = actions.first(where: { $0.role == .secondary }) {
            performAction(cancel)
        } else {
            isPresented = false
        }
    }
}

extension View {
    /// Presents a Geist-styled modal dialog in place of a native `.alert`.
    ///
    /// Tap the scrim or press Escape to dismiss through the cancel action.
    /// Any action button dismisses the dialog before running its handler.
    func geistDialog(
        isPresented: Binding<Bool>,
        title: Text,
        message: Text? = nil,
        messageAccessibilityIdentifier: String? = nil,
        actions: [GeistDialogAction] = [],
        fields: [GeistDialogField] = []
    ) -> some View {
        GeistDialogModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            messageAccessibilityIdentifier: messageAccessibilityIdentifier,
            actions: actions,
            fields: fields,
            presenting: self
        )
    }
}

// MARK: - Card

private struct GeistDialogCard: View {
    let title: Text
    let message: Text?
    let messageAccessibilityIdentifier: String?
    let actions: [GeistDialogAction]
    let fields: [GeistDialogField]
    let onAction: (GeistDialogAction) -> Void
    let onCancel: () -> Void

    @FocusState private var isFieldFocused: Bool

    private var primaryAction: GeistDialogAction? {
        actions.first(where: { $0.role != .secondary })
    }

    /// Quiet actions sit left (or on top); filled actions anchor right (or bottom).
    private var orderedActions: [GeistDialogAction] {
        let quiet = actions.filter { $0.role == .secondary }
        let prominent = actions.filter { $0.role != .secondary }
        return quiet + prominent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            title
                .font(Typography.headline())
                .tracking(-0.32)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let message {
                message
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(GeistDialogAccessibilityIdentifier(messageAccessibilityIdentifier))
            }

            if !fields.isEmpty {
                VStack(spacing: Spacing.s2) {
                    ForEach(fields.indices, id: \.self) { index in
                        dialogField(fields[index])
                    }
                }
            }

            if !actions.isEmpty {
                actionsView
            }
        }
        .padding(Spacing.s6)
        .frame(minWidth: 280, maxWidth: 420, alignment: .leading)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        // DESIGN.md modal elevation: three-layer shadow.
        .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 24)
        #if os(macOS)
        .onExitCommand(perform: onCancel)
        #endif
        .accessibilityElement(children: .contain)
        #if os(iOS)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            if !fields.isEmpty {
                isFieldFocused = true
            }
        }
        #else
        .onAppear {
            if !fields.isEmpty {
                isFieldFocused = true
            }
        }
        #endif
    }

    @ViewBuilder
    private func dialogField(_ field: GeistDialogField) -> some View {
        TextField("", text: field.text, prompt: Text(field.placeholder).foregroundStyle(Color.textMuted))
            .font(Typography.body())
            .foregroundStyle(Color.textPrimary)
            .autocorrectionDisabled(true)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            #endif
            .onSubmit {
                if let primaryAction {
                    onAction(primaryAction)
                }
            }
            .focused($isFieldFocused)
            .padding(.horizontal, Spacing.s3)
            .frame(height: 40)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var actionsView: some View {
        if orderedActions.count <= 2 {
            HStack(spacing: Spacing.s2) {
                ForEach(Array(orderedActions.enumerated()), id: \.offset) { _, action in
                    dialogButton(action, fillsWidth: true)
                }
            }
        } else {
            VStack(spacing: Spacing.s2) {
                ForEach(Array(orderedActions.enumerated()), id: \.offset) { _, action in
                    dialogButton(action, fillsWidth: true)
                }
            }
        }
    }

    private func dialogButton(_ action: GeistDialogAction, fillsWidth: Bool) -> some View {
        Button {
            onAction(action)
        } label: {
            Text(action.label)
                .font(Typography.bodyEmphasis())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 40)
                .padding(.horizontal, Spacing.s3)
        }
        .buttonStyle(GeistDialogButtonStyle(role: action.role))
        .modifier(GeistDialogAccessibilityIdentifier(action.accessibilityIdentifier))
    }
}

/// Applies an accessibility identifier when present; no-op otherwise.
private struct GeistDialogAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

// MARK: - Button Style

private struct GeistDialogButtonStyle: ButtonStyle {
    let role: GeistDialogAction.Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(labelColor)
            .background(fillColor(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(AnimationTimings.fast, value: configuration.isPressed)
    }

    private var labelColor: Color {
        switch role {
        case .primary:
            // Brand accent fill inverts against the page surface in each theme.
            Color.bgPrimary
        case .secondary:
            Color.textPrimary
        case .destructive:
            Color.white
        }
    }

    private var borderColor: Color {
        role == .secondary ? Color.borderDefault : Color.clear
    }

    private func fillColor(pressed: Bool) -> Color {
        switch role {
        case .primary:
            pressed ? Color.accentHover : Color.accent
        case .secondary:
            pressed ? Color.geistGray100 : Color.bgPrimary
        case .destructive:
            Color.error
        }
    }
}
