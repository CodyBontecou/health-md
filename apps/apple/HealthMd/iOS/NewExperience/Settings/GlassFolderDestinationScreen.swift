#if os(iOS)
import SwiftUI

/// FolderDestG. The default folder uses the app's existing picker, which owns bookmarks.
/// Each folder automation can instead write to its own saved folder on this iPhone.
struct GlassFolderDestinationScreen: View {
    @ObservedObject var vaultManager: VaultManager
    let coordinator: ExportProfileCoordinator?
    @Binding var showFolderPicker: Bool

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    /// The automation choosing a new folder of its own.
    @State private var pickingFolderFor: ExportProfile?
    @State private var revision = 0

    private var needsReselection: Bool {
        switch vaultManager.destinationState {
        case .requiresReviewIdentityUnavailable,
             .requiresReselectionDestinationChanged,
             .requiresReselectionMissingExpectedPath:
            return true
        case .notSelected, .available, .temporarilyUnavailable:
            return false
        }
    }

    private var folderProfiles: [ExportProfile] {
        _ = revision
        return (coordinator?.profileStore.profiles ?? []).filter { $0.target == .localIPhoneFolder }
    }

    private var savedFolders: [SavedVaultDestination] { coordinator?.destinationStore.vaults ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                if needsReselection {
                    GlassBanner(
                        title: String(localized: "Needs review"),
                        message: String(localized: "iOS lost access to this folder after it was moved. Choose it again to keep exporting — nothing has been deleted."),
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }

                GlassSectionLabel(title: String(localized: "Default folder"))
                GlassPanel {
                    Button {
                        configurationProtection.performConfigurationChange { showFolderPicker = true }
                    } label: {
                        GlassRow(
                            title: vaultManager.hasVaultSelection
                                ? vaultManager.vaultName
                                : String(localized: "No folder chosen"),
                            subtitle: needsReselection
                                ? String(localized: "Choose folder again")
                                : String(localized: "Choose New Folder…")
                        ) {
                            Image(systemName: "folder.badge.plus").foregroundStyle(palette.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("glass.folderDestination.chooseDefault")
                    Divider().overlay(palette.line)
                    GlassTemplateField(
                        title: String(localized: "Subfolder"),
                        text: configurationProtection.protecting($vaultManager.healthSubfolder)
                    )
                }
                Text("Automations without a folder of their own write here.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 4)

                if !folderProfiles.isEmpty {
                    GlassSectionLabel(title: String(localized: "Automations"))
                    GlassPanel {
                        ForEach(Array(folderProfiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 { Divider().overlay(palette.line) }
                            profileRow(profile)
                        }
                    }
                    Text("Give an automation its own folder to keep its notes apart, such as a separate vault.")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 4)
                }

                Text("Works best with iCloud Drive, On My iPhone, or a synced app folder. Health.md writes directly — no account needed.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Folder"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.folderDestination")
        .sheet(item: $pickingFolderFor) { profile in
            FolderPicker { url in
                configurationProtection.performConfigurationChange {
                    guard let id = coordinator?.importFolderSelection(url) else { return }
                    bind(profile, to: id)
                }
            }
        }
    }

    private func profileRow(_ profile: ExportProfile) -> some View {
        let current = savedFolders.first { $0.id == profile.folderVaultID }
        return Menu {
            Picker(profile.name, selection: Binding(
                get: { profile.folderVaultID },
                set: { newValue in
                    configurationProtection.performConfigurationChange { bind(profile, to: newValue) }
                }
            )) {
                Text("Default folder").tag(UUID?.none)
                ForEach(savedFolders) { folder in
                    Text(folder.name).tag(Optional(folder.id))
                }
            }
            Divider()
            Button {
                configurationProtection.performConfigurationChange { pickingFolderFor = profile }
            } label: {
                Label(String(localized: "Choose New Folder…"), systemImage: "folder.badge.plus")
            }
        } label: {
            GlassRow(
                title: profile.name,
                subtitle: current?.name ?? String(localized: "Default folder")
                    + (vaultManager.hasVaultSelection ? " · \(vaultManager.vaultName)" : "")
            ) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "Chooses where this automation writes"))
        .accessibilityIdentifier("glass.folderDestination.profile.\(profile.id.uuidString)")
    }

    /// Saved folders go through the explicit rebind confirmation; nil returns to the default.
    private func bind(_ profile: ExportProfile, to folderID: UUID?) {
        guard let coordinator, folderID != profile.folderVaultID else { return }
        if let folderID {
            try? coordinator.confirmFolderRebind(profileID: profile.id, destinationID: folderID)
        } else {
            _ = coordinator.updateProfile(
                id: profile.id,
                name: profile.name,
                target: profile.target,
                folderVaultID: nil,
                apiEndpointID: profile.apiEndpointID,
                agentDataGatewayID: coordinator.destinationStore.agentDataGatewayBinding(profileID: profile.id),
                settings: profile.settings
            )
        }
        revision += 1
    }
}
#endif
