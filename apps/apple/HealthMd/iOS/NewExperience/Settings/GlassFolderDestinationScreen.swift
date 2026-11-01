#if os(iOS)
import SwiftUI

/// FolderDestG. The folder choice uses the app's existing picker, which owns bookmarks.
struct GlassFolderDestinationScreen: View {
    @ObservedObject var vaultManager: VaultManager
    let profiles: [ExportProfile]
    @Binding var showFolderPicker: Bool

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

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

                Button(needsReselection ? String(localized: "Choose folder again") : String(localized: "Choose New Folder…")) {
                    configurationProtection.performConfigurationChange { showFolderPicker = true }
                }
                .buttonStyle(GlassPrimaryButtonStyle())

                GlassPanel {
                    GlassRow(
                        title: String(localized: "Folder"),
                        subtitle: vaultManager.hasVaultSelection ? vaultManager.vaultName : nil
                    ) { EmptyView() }
                    GlassTemplateField(
                        title: String(localized: "Subfolder"),
                        text: configurationProtection.protecting($vaultManager.healthSubfolder)
                    )
                }

                if !profiles.isEmpty {
                    GlassSectionLabel(title: String(localized: "Used by"))
                    GlassPanel {
                        ForEach(profiles) { profile in
                            GlassRow(title: profile.name) { EmptyView() }
                        }
                    }
                }

                Text("Works best with iCloud Drive, On My iPhone, or a synced app folder. Health.md writes directly — no account needed.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Folder"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.folderDestination")
    }
}
#endif
