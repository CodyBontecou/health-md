import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Shared by the real presenter and card. Keep the shipped handler-before-dismissal
/// order, first-secondary cancellation, and first-prominent submission policy.
struct GeistDialogInteraction {
    let actions: [GeistDialogAction]

    var primaryAction: GeistDialogAction? {
        actions.first { $0.role != .secondary }
    }

    /// Quiet actions sit left/on top, preserving order within both groups.
    var orderedActions: [GeistDialogAction] {
        actions.filter { $0.role == .secondary } + actions.filter { $0.role != .secondary }
    }

    func perform(_ action: GeistDialogAction, isPresented: Binding<Bool>) {
        action.handler()
        isPresented.wrappedValue = false
    }

    func cancel(isPresented: Binding<Bool>) {
        if let cancel = actions.first(where: { $0.role == .secondary }) {
            perform(cancel, isPresented: isPresented)
        } else {
            isPresented.wrappedValue = false
        }
    }

    func submit(
        fieldIndex: Int,
        fieldCount: Int,
        advancesFocus: Bool,
        focus: (Int) -> Void,
        onAction: (GeistDialogAction) -> Void
    ) {
        if advancesFocus && fieldIndex + 1 < fieldCount {
            focus(fieldIndex + 1)
        } else if let primaryAction {
            onAction(primaryAction)
        }
        // A final field without a prominent action still does nothing on Return.
        // Do not turn Done into a new cancel, validation or dismissal policy.
    }
}

/// The environment is read by the production views, never overridden for tests.
enum GeistDialogMotion {
    static func presentationAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08)
    }

    static func pressAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : AnimationTimings.fast
    }
}

private enum GeistDialogScrollTarget: Hashable {
    case field(Int)
}

private struct GeistDialogContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The production card, including its real scrolling surface and native fields.
/// One stable scroll hierarchy keeps focus/drafts when the keyboard or viewport
/// changes. Everything scrolls together, so long copy cannot trap the actions.
struct GeistDialogCard: View {
    let title: Text
    let message: Text?
    let messageAccessibilityIdentifier: String?
    let actions: [GeistDialogAction]
    let fields: [GeistDialogField]
    let maximumHeight: CGFloat
    let onAction: (GeistDialogAction) -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: Int?
    @State private var contentHeight: CGFloat?

    private var interaction: GeistDialogInteraction { GeistDialogInteraction(actions: actions) }

    private var contentPadding: CGFloat {
        #if os(iOS)
        Spacing.s4
        #else
        Spacing.s6
        #endif
    }

    private var scrollingContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    title
                        .font(Typography.headline())
                        .tracking(-0.32)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("geist-dialog.title")

                    if let message {
                        message
                            .font(Typography.body())
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .modifier(GeistDialogAccessibilityIdentifier(messageAccessibilityIdentifier))
                    }

                    ForEach(fields.indices, id: \.self) { index in
                        GeistDialogLabeledField(
                            field: fields[index],
                            index: index,
                            isLast: index == fields.indices.last,
                            focus: $focusedField,
                            onSubmit: { submitField(at: index) }
                        )
                    }

                    if !actions.isEmpty {
                        actionsView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentPadding)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: GeistDialogContentHeight.self, value: geometry.size.height)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            #if os(iOS)
            // This hides only the keyboard; drafts and dialog callbacks are untouched.
            .scrollDismissesKeyboard(.interactively)
            #endif
            .accessibilityIdentifier("geist-dialog.scroll")
            .onPreferenceChange(GeistDialogContentHeight.self) { contentHeight = $0 }
            .onChange(of: focusedField) { _, index in
                if let index { proxy.scrollTo(GeistDialogScrollTarget.field(index), anchor: .center) }
            }
            .onChange(of: maximumHeight) { previous, current in
                // Reveal only when space is lost (keyboard arrival/shorter window).
                // Re-scrolling on every expanding interactive-dismissal frame
                // fights the native keyboard gesture. Extra space needs no move.
                guard current < previous else { return }
                // Target the exact input, not its potentially much taller label.
                if let focusedField {
                    proxy.scrollTo(GeistDialogScrollTarget.field(focusedField), anchor: .center)
                }
            }
        }
    }

    var body: some View {
        // A real native modal boundary owns Escape and contains the scroll's
        // distinct accessibility node; a single-child SwiftUI VStack coalesces
        // its modal metadata/identifier with the scroll on iOS.
        Group {
            #if os(iOS)
            GeistDialogAccessibilityHost(onCancel: onCancel) { scrollingContent }
            #else
            scrollingContent
            #endif
        }
        .frame(height: min(contentHeight ?? maximumHeight, max(0, maximumHeight)))
        .frame(maxWidth: 420)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 24)
        #if os(macOS)
        .onExitCommand(perform: onCancel)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("geist-dialog.card")
        .onAppear {
            #if os(iOS)
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            #endif
            // Unlike the old shared Boolean binding, each native input has one focus ID.
            focusedField = fields.indices.first
        }
    }

    private func submitField(at index: Int) {
        #if os(iOS)
        let advancesFocus = true
        #else
        // macOS keeps Return-to-submit and native Tab traversal / Escape cancellation.
        let advancesFocus = false
        #endif
        interaction.submit(fieldIndex: index, fieldCount: fields.count, advancesFocus: advancesFocus,
                           focus: { focusedField = $0 }, onAction: onAction)
    }

    @ViewBuilder
    private var actionsView: some View {
        if interaction.orderedActions.count <= 2 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s2) {
                    ForEach(Array(interaction.orderedActions.enumerated()), id: \.offset) { _, action in
                        GeistDialogActionButton(action: action, onAction: onAction)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                stackedActions
            }
        } else {
            stackedActions
        }
    }

    private var stackedActions: some View {
        VStack(spacing: Spacing.s2) {
            ForEach(Array(interaction.orderedActions.enumerated()), id: \.offset) { _, action in
                GeistDialogActionButton(action: action, onAction: onAction)
            }
        }
    }
}

#if os(iOS)
/// UIKit's public modal/escape boundary, not a replacement for the SwiftUI
/// fields or actions. The complete live view environment crosses this boundary.
private struct GeistDialogAccessibilityHost<Content: View>: UIViewControllerRepresentable {
    let onCancel: () -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> GeistDialogAccessibilityController {
        GeistDialogAccessibilityController(content: AnyView(content().environment(\.self, context.environment)), onCancel: onCancel)
    }

    func updateUIViewController(_ controller: GeistDialogAccessibilityController, context: Context) {
        controller.host.rootView = AnyView(content().environment(\.self, context.environment))
        controller.modalView.onCancel = onCancel
    }
}

private final class GeistDialogAccessibilityView: UIView {
    var onCancel: () -> Void = {}

    override func accessibilityPerformEscape() -> Bool {
        onCancel()
        return true
    }
}

private final class GeistDialogAccessibilityController: UIViewController {
    let host: UIHostingController<AnyView>
    let modalView = GeistDialogAccessibilityView()

    init(content: AnyView, onCancel: @escaping () -> Void) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
        modalView.onCancel = onCancel
        modalView.accessibilityViewIsModal = true
        modalView.isAccessibilityElement = false
        modalView.accessibilityIdentifier = "geist-dialog.card"
        host.safeAreaRegions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() { view = modalView }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}
#endif

/// A stateless native field used by the production card, with a persistent full
/// label. Editing remains single-line to retain native Return/Next semantics.
struct GeistDialogLabeledField: View {
    let field: GeistDialogField
    let index: Int
    let isLast: Bool
    let focus: FocusState<Int?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(field.placeholder)
                .font(Typography.body())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("geist-dialog.field-label.\(index)")

            TextField(field.placeholder, text: field.text, prompt: Text(""))
                .textFieldStyle(.plain)
                .font(Typography.body())
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.textPrimary)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(isLast ? .done : .next)
                #endif
                .onSubmit(onSubmit)
                .focused(focus, equals: index)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
                .frame(minWidth: minimumHeight, minHeight: minimumHeight)
                .background(Color.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(focus.wrappedValue == index ? Color.accent : Color.borderSubtle, lineWidth: 1)
                }
                .contentShape(Rectangle())
                // Include the padded input edge, without replacing native selection/editing.
                .simultaneousGesture(TapGesture().onEnded { focus.wrappedValue = index })
                .accessibilityLabel(Text(field.placeholder))
                .accessibilityIdentifier("geist-dialog.field.\(index)")
                .id(GeistDialogScrollTarget.field(index))

            if !field.text.wrappedValue.isEmpty {
                // A native single-line editor scrolls horizontally. Overflow also gets a
                // full wrapping reading surface, without rewriting any bound characters.
                ViewThatFits(in: .horizontal) {
                    if !field.text.wrappedValue.contains("\n") {
                        Text(verbatim: field.text.wrappedValue)
                            .fixedSize()
                            .hidden()
                            .frame(height: 0)
                            .padding(.horizontal, Spacing.s3)
                    }
                    Text(verbatim: field.text.wrappedValue)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
                // The input already exposes the exact full value to VoiceOver.
                .accessibilityHidden(true)
            }
        }
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        40
        #endif
    }
}

struct GeistDialogActionButton: View {
    let action: GeistDialogAction
    let onAction: (GeistDialogAction) -> Void

    var body: some View {
        Button {
            onAction(action)
        } label: {
            Text(action.label)
                .font(Typography.bodyEmphasis())
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
                .frame(minWidth: minimumHeight, maxWidth: .infinity, minHeight: minimumHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(GeistDialogButtonStyle(role: action.role))
        .modifier(GeistDialogAccessibilityIdentifier(action.accessibilityIdentifier))
    }

    private var minimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        40
        #endif
    }
}

/// Applies an accessibility identifier when present; no-op otherwise.
struct GeistDialogAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) { self.identifier = identifier }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct GeistDialogButtonStyle: ButtonStyle {
    let role: GeistDialogAction.Role
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(labelColor)
            .background(fillColor(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(GeistDialogMotion.pressAnimation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var labelColor: Color {
        switch role {
        case .primary: Color.bgPrimary
        case .secondary: Color.textPrimary
        case .destructive: Color.white
        }
    }

    private var borderColor: Color {
        role == .secondary ? Color.borderDefault : Color.clear
    }

    private func fillColor(pressed: Bool) -> Color {
        switch role {
        case .primary: pressed ? Color.accentHover : Color.accent
        case .secondary: pressed ? Color.geistGray100 : Color.bgPrimary
        case .destructive: Color.error
        }
    }
}
