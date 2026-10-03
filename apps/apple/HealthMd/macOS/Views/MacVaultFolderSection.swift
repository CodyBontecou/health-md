#if os(macOS)
import SwiftUI

// MARK: - Reusable Vault Folder Section (Branded)

/// Shared vault folder picker section used in Settings tabs.
/// For custom glass layouts (Export view), inline the folder UI directly.
struct MacVaultFolderSection: View {
    @EnvironmentObject var vaultManager: VaultManager

    /// Whether to show the subfolder field
    var showSubfolder: Bool = true

    /// Whether to show the "Clear Folder" button
    var showClearButton: Bool = false

    var body: some View {
        Section {
            HStack {
                if vaultManager.hasVaultSelection {
                    Image(systemName: vaultManager.vaultURL == nil ? "folder.badge.exclamationmark" : "folder.fill")
                        .foregroundStyle(vaultManager.vaultURL == nil ? Color.warning : Color.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vaultManager.vaultName)
                            .font(BrandTypography.bodyMedium())
                        Text(vaultManager.pathForDisplay ?? vaultManager.vaultAvailabilityText)
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.textMuted)
                    Text("No folder selected")
                        .font(BrandTypography.body())
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                Button(
                    vaultManager.hasVaultSelection
                        ? String(localized: "Change…")
                        : String(localized: "Choose…")
                ) {
                    MacFolderPicker.show { url in
                        vaultManager.setVaultFolder(url)
                    }
                }
                .tint(Color.accent)
            }

            if showSubfolder, vaultManager.vaultURL != nil {
                LabeledContent("Subfolder") {
                    TextField("Optional", text: $vaultManager.healthSubfolder)
                        .font(BrandTypography.detail())
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: vaultManager.healthSubfolder) {
                            vaultManager.saveSubfolderSetting()
                        }
                }
            }

            if showClearButton, vaultManager.hasVaultSelection {
                Button("Clear Folder Selection", role: .destructive) {
                    vaultManager.clearVaultFolder()
                }
                .tint(Color.error)
            }
        } header: {
            BrandLabel("Destination Folder")
        }
    }
}

#endif
