import SwiftUI

// MARK: - Geist Dialog
// A custom modal following DESIGN.md (Geist) instead of native `.alert`.
// Surfaces: 12px radius (menus and modals), background-100 card with a subtle
// border, and the documented modal elevation shadow. Motion: ~300ms overlay
// transition with the Geist easing curve, omitted with reduced-motion.
//
// Attach at the root of a full-screen (or full-window), keyboard-safe view, e.g.:
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
/// The existing placeholder is also the persistent external/accessibility label.
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

    var body: some View {
        presenting
            .accessibilityHidden(isPresented)
            .allowsHitTesting(!isPresented)
            .overlay {
                // Only the scrim ignores safe areas. The card's actual remaining
                // proposal follows the native keyboard and short/narrow host bounds.
                GeometryReader { geometry in
                    let inset = geometry.size.width < 360 || geometry.size.height < 360 ? Spacing.s2 : Spacing.s6
                    ZStack {
                        if isPresented {
                            Color.dialogScrim
                                .ignoresSafeArea()
                                .onTapGesture(perform: performCancelDismissal)
                                .accessibilityHidden(true)
                                .transition(reduceMotion ? .identity : .opacity)

                            GeistDialogCard(
                                title: title,
                                message: message,
                                messageAccessibilityIdentifier: messageAccessibilityIdentifier,
                                actions: actions,
                                fields: fields,
                                maximumHeight: max(0, geometry.size.height - inset * 2),
                                onAction: performAction,
                                onCancel: performCancelDismissal
                            )
                            .frame(width: min(420, max(0, geometry.size.width - inset * 2)))
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("geist-dialog.overlay")
                    .accessibilityHidden(!isPresented)
                }
                .animation(GeistDialogMotion.presentationAnimation(reduceMotion: reduceMotion), value: isPresented)
            }
    }

    private func performAction(_ action: GeistDialogAction) {
        GeistDialogInteraction(actions: actions).perform(action, isPresented: $isPresented)
    }

    private func performCancelDismissal() {
        GeistDialogInteraction(actions: actions).cancel(isPresented: $isPresented)
    }
}

extension View {
    /// Presents a Geist-styled modal dialog in place of a native `.alert`.
    ///
    /// Tap the scrim, use VoiceOver Escape, or press macOS Escape to dismiss through
    /// the first secondary action. Any action runs its handler, then dismisses.
    /// iOS focuses the first field; Next advances and the final Done submits the
    /// first non-secondary action. macOS retains Return-to-submit and native Tab.
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
