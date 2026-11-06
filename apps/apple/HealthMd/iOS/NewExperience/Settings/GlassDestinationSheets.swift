#if os(iOS)
import SwiftUI

/// Shared layout for APIDestG and GatewayDestG. Fields edit a draft; Save commits it
/// through the configuration lock in one change. Pushed from Settings, Back discards the
/// draft; presented as a sheet (from Needs attention), Cancel does.
private struct GlassDestinationForm<Fields: View, Status: View, Footer: View>: View {
    let title: String
    let sectionTitle: String
    let presentedAsSheet: Bool
    /// What Health.md sends. Part of the public contract, so keep it accurate.
    var contractNote: String?
    var showsStatus = true
    var trustNote: String?
    let removeTitle: String
    let canRemove: Bool
    let hasChanges: Bool
    let onSave: () -> Void
    let onRemove: () -> Void
    @ViewBuilder let fields: Fields
    @ViewBuilder let status: Status
    @ViewBuilder let footer: Footer

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var confirmingRemoval = false

    var body: some View {
        if presentedAsSheet {
            NavigationStack { form }
                .overlay(alignment: .top) {
                    ConfigurationProtectionToast(configurationProtection: configurationProtection)
                }
                .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
                    if requestID != nil { dismiss() }
                }
        } else {
            // Pushed: the app's own toast shows, and Settings follows the lock's navigation request.
            form
        }
    }

    private var form: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: 6) {
                        GlassSectionLabel(title: sectionTitle).padding(.horizontal, 20)
                        GlassPanel { fields }
                        if let contractNote {
                            Text(contractNote)
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.muted)
                                .padding(.horizontal, 20)
                        }
                    }

                    if showsStatus {
                        VStack(alignment: .leading, spacing: 6) {
                            GlassSectionLabel(title: String(localized: "Status")).padding(.horizontal, 20)
                            GlassPanel { status }
                        }
                    }

                    if let trustNote { trustNoteView(trustNote) }

                    footer

                    if canRemove {
                        GlassPanel {
                            Button(role: .destructive) { confirmingRemoval = true } label: {
                                Text(removeTitle)
                                    .glassFont(.body)
                                    .foregroundStyle(palette.coral)
                                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                                    .padding(.horizontal, GlassMetrics.panelPadding)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .tint(palette.accent)
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentedAsSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel")) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        configurationProtection.performConfigurationChange {
                            onSave()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges)
                }
            }
            .confirmationDialog(removeTitle, isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button(removeTitle, role: .destructive) {
                    configurationProtection.performConfigurationChange(onRemove)
                }
            }
    }

    private func trustNoteView(_ trustNote: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(trustNote)
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.sec)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.panelSmallRadius, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A labelled field row inside a destination panel: caption above, input below,
/// optional helper text underneath.
private struct GlassDestinationFieldRow<Field: View>: View {
    let label: String
    var helper: String?
    var showsDivider = false
    @ViewBuilder let field: Field

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).glassFont(.caption).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .foregroundStyle(palette.text)
                .frame(minHeight: 28)
            if let helper {
                Text(helper).font(.system(size: 12)).foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle().fill(palette.line).frame(height: 1)
                    .padding(.horizontal, GlassMetrics.panelPadding)
            }
        }
    }
}

struct GlassAPIDestinationSheet: View {
    @ObservedObject var settings: APIExportSettings
    /// False when pushed from Settings (APIDestG): Back instead of Cancel.
    var presentedAsSheet = true
    @ObservedObject private var history = ExportHistoryManager.shared

    @Environment(\.glassPalette) private var palette
    @State private var name: String
    @State private var endpoint: String
    @State private var token: String
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running
        case finished(statusCode: Int)
        case failed(String)
    }

    private let names = DestinationNameStore()

    init(settings: APIExportSettings, presentedAsSheet: Bool = true) {
        self.settings = settings
        self.presentedAsSheet = presentedAsSheet
        _name = State(initialValue: DestinationNameStore().apiEndpointName)
        _endpoint = State(initialValue: settings.endpointURLString)
        _token = State(initialValue: settings.bearerToken)
    }

    /// Same validation as `APIExportSettings.endpointURL`, applied to the draft.
    private var draftURL: URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != names.apiEndpointName
            || endpoint != settings.endpointURLString
            || token != settings.bearerToken
    }

    var body: some View {
        GlassDestinationForm(
            title: String(localized: "API endpoint"),
            sectionTitle: String(localized: "Endpoint"),
            presentedAsSheet: presentedAsSheet,
            trustNote: String(localized: "Only send Apple Health data to endpoints you control or trust. Uploads use this profile’s metrics and data detail."),
            removeTitle: String(localized: "Remove endpoint"),
            canRemove: !settings.endpointURLString.isEmpty || !settings.bearerToken.isEmpty,
            hasChanges: hasChanges,
            onSave: {
                names.apiEndpointName = name
                settings.endpointURLString = endpoint
                settings.bearerToken = token
            },
            onRemove: {
                settings.endpointURLString = ""
                settings.bearerToken = ""
                names.apiEndpointName = ""
                name = ""
                endpoint = ""
                token = ""
                testState = .idle
            }
        ) {
            GlassDestinationFieldRow(label: String(localized: "Name")) {
                TextField(String(localized: "Optional label on this device"), text: $name)
                    .glassFont(.body)
                    .accessibilityLabel(String(localized: "Endpoint name"))
            }
            GlassDestinationFieldRow(label: String(localized: "Endpoint URL"), showsDivider: true) {
                TextField("https://api.example.com/healthmd", text: $endpoint)
                    .glassFont(.monoBody)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("API endpoint URL")
            }
            GlassDestinationFieldRow(
                label: String(localized: "Token"),
                helper: String(localized: "Stored in Keychain. Optional if your endpoint doesn’t need one."),
                showsDivider: true
            ) {
                SecureField("Optional bearer token", text: $token)
                    .glassFont(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("API bearer token")
            }
        } status: {
            Button(action: testConnection) {
                GlassRow(
                    title: String(localized: "Test connection"),
                    subtitle: testSubtitle
                ) {
                    testTrailing
                }
            }
            .buttonStyle(.plain)
            .disabled(draftURL == nil || testState == .running)
            .accessibilityIdentifier("glass.api.testConnection")
            GlassSettingsValueRow(
                title: String(localized: "Last delivery"),
                value: SettingsDestinationActivity.lastSuccess(to: .apiEndpoint, in: history.history)
                    .map { SettingsDestinationActivity.timestampText($0) }
                    ?? String(localized: "None yet"),
                showsDivider: true
            )
        } footer: {
            EmptyView()
        }
        .onChange(of: endpoint) { _, _ in testState = .idle }
        .onChange(of: token) { _, _ in testState = .idle }
    }

    private var testSubtitle: String {
        if draftURL == nil { return String(localized: "Enter a valid HTTP or HTTPS URL") }
        if case .failed(let message) = testState { return message }
        return String(localized: "Sends a HEAD request — no health data")
    }

    @ViewBuilder private var testTrailing: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
        case .finished(let code):
            GlassSettingsBadge(
                title: SettingsDestinationActivity.httpStatusText(code),
                tone: (200..<400).contains(code) ? .ok : .attention
            )
        case .failed:
            GlassSettingsBadge(title: String(localized: "Failed"), tone: .attention)
        }
    }

    /// Tests the draft, so a URL can be checked before it is saved.
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
                let code = try await APIEndpointConnectionTester().statusCode(for: destination)
                testState = .finished(statusCode: code)
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}

struct GlassGatewayDestinationSheet: View {
    @ObservedObject var settings: AgentDataGatewaySettings
    /// False when pushed from Settings (GatewayDestG): Back instead of Cancel.
    var presentedAsSheet = true
    /// Opens Clinic access from the "Clinic destination" row (GatewayDestG links it).
    var onOpenClinicAccess: (() -> Void)?

    @State private var name: String
    @State private var endpoint: String

    private let names = DestinationNameStore()

    init(
        settings: AgentDataGatewaySettings,
        presentedAsSheet: Bool = true,
        onOpenClinicAccess: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.presentedAsSheet = presentedAsSheet
        self.onOpenClinicAccess = onOpenClinicAccess
        _name = State(initialValue: DestinationNameStore().agentDataGatewayName)
        _endpoint = State(initialValue: settings.endpointURLString)
    }

    private var draftSnapshot: AgentDataGatewayDestinationSnapshot? {
        AgentDataGatewayDestinationSnapshot(endpointURLString: endpoint)
    }

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != names.agentDataGatewayName
            || endpoint != settings.endpointURLString
    }

    var body: some View {
        GlassDestinationForm(
            title: String(localized: "Agent Data gateway"),
            sectionTitle: String(localized: "Gateway"),
            presentedAsSheet: presentedAsSheet,
            contractNote: String(localized: "Uploads each exported file unchanged to /v1/ingest. Always includes the JSON daily export. No token needed in this version."),
            showsStatus: false,
            removeTitle: String(localized: "Remove gateway"),
            canRemove: !settings.endpointURLString.isEmpty,
            hasChanges: hasChanges,
            onSave: {
                names.agentDataGatewayName = name
                settings.endpointURLString = endpoint
            },
            onRemove: {
                settings.endpointURLString = ""
                names.agentDataGatewayName = ""
                name = ""
                endpoint = ""
            }
        ) {
            GlassDestinationFieldRow(label: String(localized: "Name")) {
                TextField(String(localized: "Optional label on this device"), text: $name)
                    .glassFont(.body)
                    .accessibilityLabel(String(localized: "Gateway name"))
            }
            GlassDestinationFieldRow(
                label: String(localized: "Gateway URL"),
                helper: endpoint.isEmpty || draftSnapshot != nil ? nil : String(localized: "Enter a valid HTTP or HTTPS URL"),
                showsDivider: true
            ) {
                TextField("https://gateway.example.com", text: $endpoint)
                    .glassFont(.monoBody)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Agent Data gateway endpoint URL")
            }
        } status: {
            EmptyView()
        } footer: {
            if ClinicAccessFeature.isEnabled {
                GlassClinicDestinationNotice(onOpenClinicAccess: onOpenClinicAccess)
            }
        }
    }
}

/// GatewayDestG's "Also available" row. Practice-gated, so never shown in production.
/// Links to Clinic access when the presenter can open it; otherwise it is a plain notice.
private struct GlassClinicDestinationNotice: View {
    let onOpenClinicAccess: (() -> Void)?

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassSectionLabel(title: String(localized: "Also available")).padding(.horizontal, 20)
            GlassPanel {
                if let onOpenClinicAccess {
                    Button(action: onOpenClinicAccess) { row(showsChevron: true) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("glass.gateway.clinicAccess")
                } else {
                    row(showsChevron: false).accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func row(showsChevron: Bool) -> some View {
        GlassRow(
            title: String(localized: "Clinic destination"),
            subtitle: String(localized: "Managed by your clinic — use Clinic access to change")
        ) {
            HStack(spacing: 8) {
                GlassSettingsBadge(title: String(localized: "Managed"), tone: .off)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
#endif
