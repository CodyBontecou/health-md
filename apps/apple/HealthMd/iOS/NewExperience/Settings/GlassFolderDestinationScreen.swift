#if os(iOS)
import SwiftUI

/// FolderDestG. The default folder uses the app's existing picker, which owns bookmarks.
/// An automation's own folder is chosen in its Output screen (OutputG).
struct GlassFolderDestinationScreen: View {
    @ObservedObject var vaultManager: VaultManager
    let coordinator: ExportProfileCoordinator?
    @Binding var showFolderPicker: Bool

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @ObservedObject private var history = ExportHistoryManager.shared
    @AppStorage(NewAutomationDestinationPreference.key) private var newAutomationsUseDefaultFolder = false

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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

    private var defaultFolderUsers: [String] {
        let profiles = (coordinator?.profileStore.profiles ?? []).filter { $0.target == .localIPhoneFolder }
        return SettingsDestinationActivity.profilesUsingDefaultFolder(
            profiles: profiles,
            savedFolders: coordinator?.destinationStore.vaults ?? [],
            defaultFolderPath: vaultManager.vaultURL?.standardizedFileURL.path
        )
    }

    private var folderLocation: String? {
        vaultManager.vaultURL.flatMap {
            FolderLocationDescription.parentLocation(
                of: $0,
                onDeviceTitle: isPad ? String(localized: "On My iPad") : String(localized: "On My iPhone")
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                if needsReselection { reselectionBanner }

                GlassSectionLabel(title: String(localized: "Folder"))
                GlassPanel {
                    Button {
                        chooseFolder()
                    } label: {
                        GlassRow(
                            title: String(localized: "Folder"),
                            subtitle: vaultManager.hasVaultSelection ? folderLocation : nil
                        ) {
                            HStack(spacing: 8) {
                                Text(vaultManager.hasVaultSelection
                                     ? vaultManager.vaultName
                                     : String(localized: "No folder chosen"))
                                    .glassFont(.body)
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                                chevron
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Choose New Folder…"))
                    .accessibilityIdentifier("glass.folderDestination.chooseDefault")

                    GlassRow(title: String(localized: "Subfolder")) {
                        TextField(
                            String(localized: "Subfolder"),
                            text: configurationProtection.protecting($vaultManager.healthSubfolder)
                        )
                        .textFieldStyle(.plain)
                        .glassFont(.body)
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    }
                    .overlay(alignment: .top) { divider }

                    GlassToggleRow(
                        title: String(localized: "Default destination"),
                        subtitle: String(localized: "New profiles use this folder"),
                        isOn: configurationProtection.protecting($newAutomationsUseDefaultFolder)
                    )
                    .overlay(alignment: .top) { divider }
                    .accessibilityIdentifier("glass.folderDestination.defaultDestination")
                }

                if vaultManager.hasVaultSelection {
                    GlassSectionLabel(title: String(localized: "Activity"))
                    GlassPanel {
                        GlassSettingsValueRow(
                            title: String(localized: "Used by"),
                            value: defaultFolderUsers.isEmpty
                                ? String(localized: "No automations")
                                : ListFormatter.localizedString(byJoining: defaultFolderUsers)
                        )
                        GlassSettingsValueRow(
                            title: String(localized: "Last write"),
                            value: SettingsDestinationActivity.lastSuccess(to: .localIPhoneFolder, in: history.history)
                                .map { SettingsDestinationActivity.timestampText($0) }
                                ?? String(localized: "None yet"),
                            showsDivider: true
                        )
                    }
                    .accessibilityIdentifier("glass.folderDestination.activity")
                }

                Text(isPad
                     ? String(localized: "Works best with iCloud Drive, On My iPad, or a synced app folder. Health.md writes directly — no account needed.")
                     : String(localized: "Works best with iCloud Drive, On My iPhone, or a synced app folder. Health.md writes directly — no account needed."))
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(isPad ? String(localized: "Vault on this iPad") : String(localized: "Vault on this iPhone"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.folderDestination")
    }

    /// FolderDestG's warning banner, with its "Choose folder again" action inside.
    private var reselectionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(palette.coral)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs review").glassFont(.caption).foregroundStyle(palette.text)
                    Text("iOS lost access to this folder after it was moved. Choose it again to keep exporting — nothing has been deleted.")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.sec)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Button(String(localized: "Choose folder again"), action: chooseFolder)
                .buttonStyle(GlassPrimaryButtonStyle())
                .accessibilityIdentifier("glass.folderDestination.chooseAgain")
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
    }

    private func chooseFolder() {
        configurationProtection.performConfigurationChange { showFolderPicker = true }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.muted)
            .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle().fill(palette.line).frame(height: 1)
            .padding(.horizontal, GlassMetrics.panelPadding)
    }
}
#endif
