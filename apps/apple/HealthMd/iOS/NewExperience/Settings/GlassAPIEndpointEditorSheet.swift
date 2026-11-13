#if os(iOS)
import SwiftUI

/// Values the API endpoint editor hands back on Save.
struct APIEndpointDraft: Equatable {
    var name: String
    var endpointURLString: String
    /// Empty removes a stored token.
    var bearerToken: String?
}

/// Onboarding v2's "New API endpoint" sheet (E1), also used to edit a saved
/// endpoint from onboarding and from an automation's Output page. Saving is
/// allowed whether or not the connection test ran or passed; only a valid URL
/// is required. Edits apply to every automation that uses the endpoint.
struct GlassAPIEndpointEditorSheet: View {
    enum Mode: Equatable {
        case create
        case edit(name: String, endpointURLString: String, token: String, usedBy: [String])
    }

    let mode: Mode
    let onSave: (APIEndpointDraft) -> Bool
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Resolved here, not read from the environment: a sheet sits outside the
    /// presenter's `glassTheme()`, and the environment default is the dark palette.
    private var palette: GlassPalette {
        GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }
    @State private var name: String
    @State private var endpoint: String
    @State private var token = ""
    @State private var showsToken = false
    @State private var testState: TestState = .idle
    @State private var saveError: String?
    @State private var confirmDelete = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, url, token }
    private enum TestState: Equatable {
        case idle, running
        case finished(Int)
        case failed(String)
    }

    init(mode: Mode, onSave: @escaping (APIEndpointDraft) -> Bool, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create:
            _name = State(initialValue: String(localized: "My API"))
            _endpoint = State(initialValue: "")
        case .edit(let name, let url, let token, _):
            _name = State(initialValue: name)
            _endpoint = State(initialValue: url)
            _token = State(initialValue: token)
        }
    }

    private var isEditing: Bool { mode != .create }
    private var draftURL: URL? { APIExportSettings.supportedEndpointURL(from: endpoint) }

    private var urlProblem: String? {
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch APIExportSettings.endpointProblem(for: endpoint) {
        case nil: return nil
        case .invalid: return String(localized: "Enter a valid HTTP or HTTPS URL")
        case .cleartextToInternetHost: return String(localized: "Use https:// — plain http:// only reaches local network addresses.")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.coral)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(palette.coral.opacity(0.12)))
                            .accessibilityHidden(true)
                        Text(introText)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.sec)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    field(String(localized: "Name")) {
                        TextField("", text: $name, prompt: prompt(String(localized: "My API")))
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .url }
                            .accessibilityIdentifier("apiEndpoint.name")
                    }

                    field(String(localized: "Endpoint URL"),
                          hint: urlProblem ?? String(localized: "Health.md sends only to this address. Use https://. Plain http:// works only on your local network."),
                          hintIsError: urlProblem != nil,
                          highlighted: focusedField == .url) {
                        TextField("", text: $endpoint, prompt: prompt("https://api.example.com/health"))
                            .font(.system(size: 14, design: .monospaced))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .url)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .token }
                            .onChange(of: endpoint) { _, _ in testState = .idle; saveError = nil }
                            .accessibilityIdentifier("apiEndpoint.url")
                    }

                    field(String(localized: "Bearer token (optional)"),
                          hint: String(localized: "Stored in the iPhone Keychain, never in your notes.")) {
                        HStack(spacing: 0) {
                            Group {
                                if showsToken {
                                    TextField("", text: tokenBinding, prompt: prompt(tokenPlaceholder))
                                } else {
                                    SecureField("", text: tokenBinding, prompt: prompt(tokenPlaceholder))
                                }
                            }
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .token)
                            .accessibilityIdentifier("apiEndpoint.token")
                            Button { showsToken.toggle() } label: {
                                Image(systemName: showsToken ? "eye.slash" : "eye")
                                    .foregroundStyle(palette.sec)
                                    .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showsToken ? String(localized: "Hide token") : String(localized: "Show token"))
                        }
                    }

                    testRow

                    if isEditing, case .edit(_, _, _, let usedBy) = mode, !usedBy.isEmpty {
                        Text("Changes apply to \(usedBy.joined(separator: ", ")).")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.sec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.coral)
                    }

                    if isEditing, onDelete != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text("Delete endpoint")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.coral)
                                .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("apiEndpoint.delete")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // Pinned, so Save stays reachable above the keyboard.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OnboardingPillButton(
                    title: String(localized: "Save endpoint"),
                    isDisabled: draftURL == nil,
                    action: save
                )
                .accessibilityIdentifier("apiEndpoint.save")
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(palette.bg)
            }
            .confirmationDialog(
                String(localized: "Delete this endpoint?"),
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete endpoint"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("Automations that use it stop sending until you choose another endpoint.")
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .glassTheme()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(GlassMetrics.sheetTopRadius)
        .onAppear { if mode == .create { focusedField = .url } }
    }

    /// E1's header: Cancel, then the title centred, both in palette colours so
    /// they read in light and dark (the system bar title did not).
    private var header: some View {
        ZStack {
            Text(isEditing ? String(localized: "Edit API endpoint") : String(localized: "New API endpoint"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(palette.sec)
                    .frame(minWidth: GlassMetrics.touchTarget, minHeight: GlassMetrics.touchTarget)
                    .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func prompt(_ text: String) -> Text {
        Text(verbatim: text).foregroundColor(palette.muted)
    }

    private var introText: String {
        String(localized: "Health.md sends one JSON payload per day with a POST. Saved endpoints can be reused by any automation.")
    }

    private var tokenPlaceholder: String { String(localized: "Optional bearer token") }

    private var tokenBinding: Binding<String> {
        Binding(get: { token }, set: { token = $0; testState = .idle })
    }

    @ViewBuilder private var testRow: some View {
        let (tint, text): (Color, String?) = {
            switch testState {
            case .idle: return (palette.text, nil)
            case .running: return (palette.sec, String(localized: "Testing…"))
            case .finished(let code) where (200..<400).contains(code):
                return (palette.ok, String(localized: "Connected · \(code) OK"))
            case .finished(let code):
                return (palette.coral, String(localized: "Server replied \(code). You can still save it."))
            case .failed(let message):
                return (palette.coral, String(localized: "Couldn’t connect: \(message). You can still save it."))
            }
        }()
        HStack(spacing: 12) {
            if let text {
                Text(verbatim: text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("apiEndpoint.testResult")
            } else {
                Text("Send an empty test request to check the URL.")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.sec)
            }
            Spacer(minLength: 8)
            Button(action: testConnection) {
                Text(testState == .idle ? String(localized: "Test connection") : String(localized: "Test again"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 14)
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .background(Capsule().fill(palette.glassStrong))
                    .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(draftURL == nil || testState == .running)
            .opacity(draftURL == nil ? 0.45 : 1)
            .accessibilityIdentifier("apiEndpoint.test")
        }
        .padding(.leading, 14)
        .padding(.vertical, 6)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint == palette.text ? palette.glassStrong : tint.opacity(0.12)))
    }

    private func field<Content: View>(
        _ label: String,
        hint: String? = nil,
        hintIsError: Bool = false,
        highlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.sec)
            content()
                .font(.system(size: 16))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.glassStrong))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(highlighted ? palette.accent : palette.line, lineWidth: highlighted ? 2 : 1)
                )
            if let hint {
                Text(verbatim: hint)
                    .font(.system(size: 12))
                    .foregroundStyle(hintIsError ? palette.coral : palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func testConnection() {
        guard let url = draftURL else { return }
        let destination = APIExportDestinationSnapshot(
            endpointURL: url,
            authorizationHeaderValue: APIEndpointConnectionTester.authorizationHeaderValue(for: token),
            displayName: url.host ?? url.absoluteString,
            redactedEndpointDescription: APIExportSettings.redactedEndpointDescription(for: url.absoluteString)
        )
        testState = .running
        Task { @MainActor in
            do {
                testState = .finished(try await APIEndpointConnectionTester().statusCode(for: destination))
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let url = draftURL else { return }
        let draft = APIEndpointDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            endpointURLString: url.absoluteString,
            bearerToken: token
        )
        if onSave(draft) {
            dismiss()
        } else {
            saveError = String(localized: "Another saved endpoint already uses this URL.")
        }
    }
}
#endif
