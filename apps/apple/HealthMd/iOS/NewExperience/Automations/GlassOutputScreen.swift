#if os(iOS)
import SwiftUI

/// OutputG: where an automation writes, how files are named, and what happens to a file
/// that already exists. New destinations reuse the profile editor's forms. A pushed page
/// that saves as it changes.
struct GlassOutputScreen: View {
    /// Everything this page saves, compared as one value for autosave.
    private struct Draft: Equatable {
        var target: ExportTargetSelection
        var folderVaultID: UUID?
        var apiEndpointID: UUID?
        var googleDriveDestinationID: UUID?
        // Connection/store changes must also trigger autosave validation.
        var googleDriveBindingIsValid: Bool
        var gatewayID: UUID?
        var settings: ExportSettingsSnapshot
    }

    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var destinationStore: ProfileDestinationStore
    let profile: ExportProfile
    @ObservedObject private var googleDriveDestinationStore: GoogleDriveDestinationStore
    @StateObject private var googleDriveConnectionManager: GoogleDriveConnectionManager

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var target: ExportTargetSelection
    @State private var folderVaultID: UUID?
    @State private var apiEndpointID: UUID?
    @State private var googleDriveDestinationID: UUID?
    @State private var gatewayID: UUID?
    @State private var draft: ExportSettingsSnapshot
    @State private var showFolderImporter = false
    @State private var endpointEditor: EndpointEditorRequest?
    @State private var showGatewayForm = false
    @State private var showGoogleDrivePrivacyDisclosure = false
    @State private var driveAuthorizationRequestID: UUID?
    @State private var driveConnectionError: String?
    @State private var connectingDrive = false

    /// Which endpoint the shared editor sheet is creating or editing.
    private struct EndpointEditorRequest: Identifiable {
        let id = UUID()
        let endpointID: UUID?
    }

    private static let dateTokens = ["{date}", "{year}", "{month}", "{day}", "{weekday}", "{monthName}", "{quarter}", "{week}", "{weekYear}"]

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        _destinationStore = ObservedObject(wrappedValue: coordinator.destinationStore)
        self.profile = profile
        _googleDriveDestinationStore = ObservedObject(wrappedValue: coordinator.googleDriveDestinationStore)
        _googleDriveConnectionManager = StateObject(wrappedValue: GoogleDriveConnectionManager(
            destinationStore: coordinator.googleDriveDestinationStore
        ))
        _googleDriveDestinationID = State(initialValue: profile.googleDriveDestinationID)
        _target = State(initialValue: profile.target)
        _folderVaultID = State(initialValue: profile.folderVaultID)
        _apiEndpointID = State(initialValue: profile.apiEndpointID)
        _gatewayID = State(initialValue: coordinator.destinationStore.agentDataGatewayBinding(profileID: profile.id))
        _draft = State(initialValue: profile.settings)
    }

    var body: some View {
        GlassSettingsPage(title: String(localized: "Output")) {
            GlassSectionLabel(title: String(localized: "Where"))
            GlassPanel {
                GlassMenuRow(
                    title: String(localized: "Destination"),
                    selection: $target,
                    options: [.localIPhoneFolder, .connectedMac, .apiEndpoint, .googleDrive, .agentDataGateway],
                    label: Self.targetTitle
                )
                destinationBinding
                GlassTemplateField(title: String(localized: "Subfolder"), text: subfolder)
                GlassTemplateField(
                    title: String(localized: "Folder organization"),
                    text: $draft.folderStructure,
                    tokens: Self.dateTokens,
                    placeholder: String(localized: "Flat")
                )
                Button(String(localized: "By Year and Week")) {
                    draft.folderStructure = ISOWeekDateTokens.folderTemplate
                }
                GlassTemplateField(
                    title: String(localized: "Filename"),
                    text: $draft.filenameFormat,
                    tokens: Self.dateTokens
                )
                GlassToggleRow(
                    title: String(localized: "Format folders"),
                    isOn: $draft.organizeFormatsIntoFolders
                )
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When a file exists").glassFont(.body).foregroundStyle(palette.text)
                    GlassSegmentedControl(
                        segments: WriteMode.allCases.map { .init(value: $0, title: $0.localizedDisplayName) },
                        selection: $draft.writeMode
                    )
                    Text("Overwrite replaces the file. Append adds to the end. Update merges new values and keeps your edits.")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .padding(.vertical, 12)
            }

            GlassPanel { GlassPathPreview(paths: draft.glassPreviewPaths) }
            Text("Format folders are off by default so existing plugins and shortcuts keep working.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 4)

            if !overlappingNames.isEmpty {
                let names = overlappingNames.joined(separator: ", ")
                GlassBanner(
                    title: String(localized: "Overlaps \(names): later runs overwrite earlier ones. Choose a different folder or filename template to keep them separate."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
            if let invalidReason, driveInvalidReason == nil {
                GlassBanner(title: invalidReason, systemImage: "exclamationmark.triangle", tone: .warning)
            }
        }
        .glassAutosave(
            currentDraft,
            isValid: invalidReason == nil,
            invalidReason: invalidReason ?? "",
            revert: restore,
            save: save
        )
        .onAppear { refreshDriveReadiness() }
        .onChange(of: googleDriveDestinationID) { _, _ in refreshDriveReadiness() }
        .onChange(of: googleDriveDestinationStore.destinations) { _, _ in refreshDriveReadiness() }
        .onChange(of: target) { _, _ in
            driveConnectionError = nil
            driveAuthorizationRequestID = nil
        }
        .confirmationDialog(
            GoogleDrivePrivacyDisclosure.title,
            isPresented: $showGoogleDrivePrivacyDisclosure,
            titleVisibility: .visible
        ) {
            Button(GoogleDrivePrivacyDisclosure.confirm) {
                configurationProtection.performConfigurationChange {
                    driveAuthorizationRequestID = UUID()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(GoogleDrivePrivacyDisclosure.message)
        }
        .task(id: driveAuthorizationRequestID) {
            guard driveAuthorizationRequestID != nil else { return }
            await connectGoogleDrive()
        }
        .sheet(isPresented: $showFolderImporter) {
            FolderPicker { url in
                configurationProtection.performConfigurationChange {
                    if let id = coordinator.importFolderSelection(url) { folderVaultID = id }
                }
            }
        }
        .sheet(item: $endpointEditor) { request in
            endpointEditorSheet(for: request.endpointID)
        }
        .sheet(isPresented: $showGatewayForm) {
            ExportProfileGatewayFormSheet { name, url in
                configurationProtection.performConfigurationChange {
                    if let id = coordinator.importAgentDataGatewaySelection(name: name, endpointURLString: url) {
                        gatewayID = id
                    }
                }
            }
        }
    }

    @ViewBuilder private var destinationBinding: some View {
        switch target {
        case .localIPhoneFolder:
            GlassMenuRow(
                title: String(localized: "Folder"),
                selection: $folderVaultID,
                options: [nil] + destinationStore.vaults.map { Optional($0.id) },
                label: { id in
                    destinationStore.vaults.first { $0.id == id }?.name
                        ?? String(localized: "Folder from Settings")
                }
            )
            addRow(String(localized: "Choose New Folder…")) { showFolderImporter = true }
        case .googleDrive:
            GlassMenuRow(
                title: "Google Drive",
                selection: $googleDriveDestinationID,
                options: [nil] + googleDriveDestinationStore.destinations.map { Optional($0.id) },
                label: { id in googleDriveDestinationStore.destination(id: id)?.folderLabel ?? "Select a Google Drive folder" }
            )
            GoogleDriveConnectionButton(
                title: googleDriveDestinationID == nil ? "Connect & Choose Folder…" : "Reconnect or Change Folder…"
            ) { showGoogleDrivePrivacyDisclosure = true }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.vertical, 8)
            .disabled(connectingDrive || googleDriveConnectionManager.readiness == .configurationMissing)
            .accessibilityIdentifier("glass.output.connectGoogleDrive")
            if connectingDrive {
                ProgressView().padding(.horizontal, GlassMetrics.panelPadding)
            }
            if let reason = driveConnectionError ?? driveInvalidReason {
                GlassBanner(title: reason, systemImage: "exclamationmark.triangle", tone: .warning)
            }
        case .apiEndpoint:
            ForEach(destinationStore.apiEndpoints) { endpoint in
                savedEndpointRow(endpoint)
            }
            addRow(String(localized: "New endpoint")) { endpointEditor = EndpointEditorRequest(endpointID: nil) }
        case .agentDataGateway:
            GlassMenuRow(
                title: String(localized: "Gateway"),
                selection: $gatewayID,
                options: [nil] + destinationStore.agentDataGateways.map { Optional($0.id) },
                label: { id in
                    destinationStore.agentDataGateways.first { $0.id == id }?.name
                        ?? String(localized: "Gateway from Settings")
                }
            )
            addRow(String(localized: "Add Gateway…")) { showGatewayForm = true }
        case .connectedMac:
            EmptyView()
        }
    }

    /// One saved endpoint: tap to send this automation there; the visible edit
    /// button opens the shared editor, whose changes apply to every automation.
    private func savedEndpointRow(_ endpoint: SavedAPIEndpoint) -> some View {
        let isOn = apiEndpointID == endpoint.id
        let users = coordinator.profileNames(usingAPIEndpoint: endpoint.id)
        return HStack(spacing: 12) {
            Button { apiEndpointID = endpoint.id } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isOn ? palette.accent : palette.track)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: endpoint.name).glassFont(.body).foregroundStyle(palette.text)
                        Text(verbatim: Self.shortURL(endpoint.endpointURLString))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.sec)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(users.isEmpty
                             ? String(localized: "Not used yet")
                             : String(localized: "Used by \(users.joined(separator: ", "))"))
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(users.isEmpty ? palette.muted : palette.ok)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("glass.output.endpoint.\(endpoint.name)")

            Button {
                configurationProtection.performConfigurationChange {
                    endpointEditor = EndpointEditorRequest(endpointID: endpoint.id)
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                    .background(Circle().fill(palette.tint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit \(endpoint.name)"))
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func endpointEditorSheet(for endpointID: UUID?) -> some View {
        if let endpointID, let endpoint = destinationStore.apiEndpoint(id: endpointID) {
            GlassAPIEndpointEditorSheet(
                mode: .edit(
                    name: endpoint.name,
                    endpointURLString: endpoint.endpointURLString,
                    token: destinationStore.token(for: endpoint.id) ?? "",
                    usedBy: coordinator.profileNames(usingAPIEndpoint: endpoint.id)
                ),
                onSave: { draft in
                    coordinator.saveAPIEndpoint(
                        editingID: endpoint.id,
                        name: draft.name,
                        endpointURLString: draft.endpointURLString,
                        bearerToken: draft.bearerToken
                    ) != nil
                },
                onDelete: {
                    coordinator.deleteAPIEndpoint(id: endpoint.id)
                    if apiEndpointID == endpoint.id { apiEndpointID = nil }
                }
            )
        } else {
            GlassAPIEndpointEditorSheet(mode: .create) { draft in
                guard let id = coordinator.saveAPIEndpoint(
                    editingID: nil,
                    name: draft.name,
                    endpointURLString: draft.endpointURLString,
                    bearerToken: draft.bearerToken
                ) else { return false }
                apiEndpointID = id
                return true
            }
        }
    }

    static func shortURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

        private func addRow(_ title: String, systemImage: String = "plus", action: @escaping () -> Void) -> some View {
        Button {
            configurationProtection.performConfigurationChange(action)
        } label: {
            GlassRow(title: title) { Image(systemName: systemImage).foregroundStyle(palette.accent) }
        }
        .buttonStyle(.plain)
    }

    private static func targetTitle(_ target: ExportTargetSelection) -> String {
        switch target {
        case .localIPhoneFolder: return String(localized: "Vault on this iPhone")
        case .connectedMac: return String(localized: "Connected Mac")
        case .googleDrive: return "Google Drive"
        case .apiEndpoint: return String(localized: "API Endpoint")
        case .agentDataGateway: return String(localized: "Agent Data gateway")
        }
    }

    private var subfolder: Binding<String> {
        Binding(
            get: { draft.healthSubfolder ?? "" },
            set: { draft.healthSubfolder = $0.isEmpty ? nil : $0 }
        )
    }

    private var driveInvalidReason: String? {
        guard target == .googleDrive else { return nil }
        return GoogleDriveProfileBindingValidation.invalidReason(
            destination: googleDriveDestinationStore.destination(id: googleDriveDestinationID),
            readiness: googleDriveConnectionManager.readiness
        )
    }

    private var invalidReason: String? {
        driveInvalidReason ?? AutomationOutputPathValidation.invalidReason(
            folders: [draft.healthSubfolder ?? "", draft.folderStructure],
            filename: draft.filenameFormat
        )
    }

    private func refreshDriveReadiness() {
        googleDriveConnectionManager.refreshReadiness(destinationID: googleDriveDestinationID)
    }

    @MainActor private func connectGoogleDrive() async {
        guard configurationProtection.performConfigurationChange({}) else { return }
        connectingDrive = true
        defer { connectingDrive = false }
        do {
            let destination = try await googleDriveConnectionManager.connect(
                replacing: googleDriveDestinationID,
                commitAllowed: { configurationProtection.performConfigurationChange({}) }
            )
            try Task.checkCancellation()
            configurationProtection.performConfigurationChange {
                googleDriveDestinationID = destination.id
                driveConnectionError = nil
            }
        } catch is CancellationError {
            driveConnectionError = nil
        } catch {
            driveConnectionError = (error as? GoogleDriveError)?.errorDescription
                ?? GoogleDriveError(.reauthorizationRequired).errorDescription
        }
    }

    private var overlappingNames: [String] {
        coordinator.overlapPreviewNames(
            target: target,
            folderVaultID: folderVaultID,
            googleDriveDestinationID: googleDriveDestinationID,
            settings: draft,
            editingProfileID: profile.id
        )
    }

    private var currentDraft: Draft {
        Draft(
            target: target,
            folderVaultID: folderVaultID,
            apiEndpointID: apiEndpointID,
            googleDriveDestinationID: googleDriveDestinationID,
            googleDriveBindingIsValid: target != .googleDrive || driveInvalidReason == nil,
            gatewayID: gatewayID,
            settings: draft
        )
    }

    private func restore(_ saved: Draft) {
        target = saved.target
        folderVaultID = saved.folderVaultID
        apiEndpointID = saved.apiEndpointID
        googleDriveDestinationID = saved.googleDriveDestinationID
        gatewayID = saved.gatewayID
        draft = saved.settings
    }

    private func save(_ value: Draft) {
        if value.target == .googleDrive {
            googleDriveConnectionManager.refreshReadiness(destinationID: value.googleDriveDestinationID)
            guard GoogleDriveProfileBindingValidation.invalidReason(
                destination: googleDriveDestinationStore.destination(id: value.googleDriveDestinationID),
                readiness: googleDriveConnectionManager.readiness
            ) == nil else { return }
        }
        let name = coordinator.profileStore.profile(id: profile.id)?.name ?? profile.name
        _ = coordinator.updateProfile(
            id: profile.id,
            name: name,
            target: value.target,
            folderVaultID: value.target == .localIPhoneFolder ? value.folderVaultID : nil,
            apiEndpointID: value.target == .apiEndpoint ? value.apiEndpointID : nil,
            googleDriveDestinationID: value.target == .googleDrive ? value.googleDriveDestinationID : nil,
            agentDataGatewayID: value.target == .agentDataGateway ? value.gatewayID : nil,
            settings: value.settings
        )
    }
}
#endif
