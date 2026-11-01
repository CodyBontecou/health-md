#if os(iOS)
import SwiftUI

/// OutputG: where an automation writes, how files are named, and what happens to a file
/// that already exists. New destinations reuse the profile editor's forms.
struct GlassOutputScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var destinationStore: ProfileDestinationStore
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var target: ExportTargetSelection
    @State private var folderVaultID: UUID?
    @State private var apiEndpointID: UUID?
    @State private var gatewayID: UUID?
    @State private var draft: ExportSettingsSnapshot
    @State private var showFolderImporter = false
    @State private var showEndpointForm = false
    @State private var showGatewayForm = false

    private static let dateTokens = ["{date}", "{year}", "{month}", "{day}", "{weekday}", "{monthName}", "{quarter}"]

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        _destinationStore = ObservedObject(wrappedValue: coordinator.destinationStore)
        self.profile = profile
        _target = State(initialValue: profile.target)
        _folderVaultID = State(initialValue: profile.folderVaultID)
        _apiEndpointID = State(initialValue: profile.apiEndpointID)
        _gatewayID = State(initialValue: coordinator.destinationStore.agentDataGatewayBinding(profileID: profile.id))
        _draft = State(initialValue: profile.settings)
    }

    var body: some View {
        GlassSettingsSheet(title: String(localized: "Output"), onSave: save) {
            GlassSectionLabel(title: String(localized: "Where"))
            GlassPanel {
                GlassMenuRow(
                    title: String(localized: "Destination"),
                    selection: $target,
                    options: [.localIPhoneFolder, .connectedMac, .apiEndpoint, .agentDataGateway],
                    label: Self.targetTitle
                )
                destinationBinding
            }

            GlassPanel {
                GlassTemplateField(title: String(localized: "Subfolder"), text: subfolder)
                GlassTemplateField(
                    title: String(localized: "Folder organization"),
                    text: $draft.folderStructure,
                    tokens: Self.dateTokens
                )
                GlassTemplateField(
                    title: String(localized: "Filename"),
                    text: $draft.filenameFormat,
                    tokens: Self.dateTokens
                )
                GlassToggleRow(
                    title: String(localized: "Format folders"),
                    subtitle: String(localized: "Format folders are off by default so existing plugins and shortcuts keep working."),
                    isOn: $draft.organizeFormatsIntoFolders
                )
            }

            GlassSectionLabel(title: String(localized: "When file exists"))
            GlassSegmentedControl(
                segments: WriteMode.allCases.map { .init(value: $0, title: $0.localizedDisplayName) },
                selection: $draft.writeMode
            )
            Text("Overwrite replaces the file. Append adds to the end. Update merges new values and keeps your edits.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)

            GlassPanel { GlassPathPreview(paths: draft.glassPreviewPaths) }

            if !overlappingNames.isEmpty {
                let names = overlappingNames.joined(separator: ", ")
                GlassBanner(
                    title: String(localized: "Overlaps \(names): later runs overwrite earlier ones. Choose a different folder or filename template to keep them separate."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
        }
        .sheet(isPresented: $showFolderImporter) {
            FolderPicker { url in
                configurationProtection.performConfigurationChange {
                    if let id = coordinator.importFolderSelection(url) { folderVaultID = id }
                }
            }
        }
        .sheet(isPresented: $showEndpointForm) {
            ExportProfileEndpointFormSheet { name, url, token in
                configurationProtection.performConfigurationChange {
                    if let id = coordinator.importAPIEndpointSelection(
                        name: name,
                        endpointURLString: url,
                        bearerToken: token
                    ) { apiEndpointID = id }
                }
            }
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
                        ?? String(localized: "Current folder (from Export tab)")
                }
            )
            addRow(String(localized: "Choose New Folder…")) { showFolderImporter = true }
        case .apiEndpoint:
            GlassMenuRow(
                title: String(localized: "Endpoint"),
                selection: $apiEndpointID,
                options: [nil] + destinationStore.apiEndpoints.map { Optional($0.id) },
                label: { id in
                    destinationStore.apiEndpoints.first { $0.id == id }?.name
                        ?? String(localized: "Current endpoint (from Export tab)")
                }
            )
            addRow(String(localized: "Add Endpoint…")) { showEndpointForm = true }
        case .agentDataGateway:
            GlassMenuRow(
                title: String(localized: "Gateway"),
                selection: $gatewayID,
                options: [nil] + destinationStore.agentDataGateways.map { Optional($0.id) },
                label: { id in
                    destinationStore.agentDataGateways.first { $0.id == id }?.name
                        ?? String(localized: "Current gateway (from Export tab)")
                }
            )
            addRow(String(localized: "Add Gateway…")) { showGatewayForm = true }
        case .connectedMac:
            EmptyView()
        }
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            configurationProtection.performConfigurationChange(action)
        } label: {
            GlassRow(title: title) { Image(systemName: "plus").foregroundStyle(palette.accent) }
        }
        .buttonStyle(.plain)
    }

    private static func targetTitle(_ target: ExportTargetSelection) -> String {
        switch target {
        case .localIPhoneFolder: return String(localized: "Local Folder")
        case .connectedMac: return String(localized: "Connected Mac")
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

    private var overlappingNames: [String] {
        coordinator.overlapPreviewNames(target: target, folderVaultID: folderVaultID, settings: draft)
    }

    private func save() {
        _ = coordinator.updateProfile(
            id: profile.id,
            name: profile.name,
            target: target,
            folderVaultID: target == .localIPhoneFolder ? folderVaultID : nil,
            apiEndpointID: target == .apiEndpoint ? apiEndpointID : nil,
            agentDataGatewayID: target == .agentDataGateway ? gatewayID : nil,
            settings: draft
        )
    }
}
#endif
