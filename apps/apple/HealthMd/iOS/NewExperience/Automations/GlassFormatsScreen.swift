#if os(iOS)
import SwiftUI

/// The format choices of FormatsG, saved through the profile editor's coordinator path.
/// Data detail, roll-ups and format customisation stay in the existing editor.
struct GlassFormatsScreen: View {
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var formats: Set<ExportFormat>

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        _formats = State(initialValue: profile.settings.exportFormats)
    }

    /// A profile needs some output: a format, or Daily Notes Only.
    private var canSave: Bool {
        !formats.isEmpty || profile.settings.dailyNotesOnlyModeEnabled
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    GlassPanel {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Toggle(isOn: binding(format)) {
                                Text(format.localizedDisplayName).glassFont(.body).foregroundStyle(palette.text)
                            }
                            .toggleStyle(GlassToggleStyle())
                            .padding(.horizontal, GlassMetrics.panelPadding)
                        }
                    }
                    if !canSave {
                        GlassBanner(
                            title: String(localized: "Select at least one export format, or enable Daily Notes Only."),
                            systemImage: "exclamationmark.triangle",
                            tone: .warning
                        )
                    }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Formats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save"), action: save).disabled(!canSave)
                }
            }
        }
    }

    private func binding(_ format: ExportFormat) -> Binding<Bool> {
        Binding(
            get: { formats.contains(format) },
            set: { isOn in
                if isOn { formats.insert(format) } else { formats.remove(format) }
            }
        )
    }

    private func save() {
        configurationProtection.performConfigurationChange {
            var settings = profile.settings
            settings.exportFormats = formats
            _ = coordinator.updateProfile(
                id: profile.id,
                name: profile.name,
                target: profile.target,
                folderVaultID: profile.folderVaultID,
                apiEndpointID: profile.apiEndpointID,
                agentDataGatewayID: coordinator.destinationStore.agentDataGatewayBinding(profileID: profile.id),
                settings: settings
            )
            dismiss()
        }
    }
}
#endif
