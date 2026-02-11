#if os(macOS)
import SwiftUI

// MARK: - Reusable Vault Folder Section

/// Shared vault folder picker section used in Export view and Settings.
/// Eliminates 3x duplication of the same folder selection UI.
struct MacVaultFolderSection: View {
    @EnvironmentObject var vaultManager: VaultManager

    /// Whether to show the subfolder field
    var showSubfolder: Bool = true

    /// Whether to show the "Clear Folder" button
    var showClearButton: Bool = false

    var body: some View {
        Section("Export Folder") {
            HStack {
                if let url = vaultManager.vaultURL {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vaultManager.vaultName)
                            .fontWeight(.medium)
                        Text(url.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(vaultManager.vaultURL != nil ? "Change…" : "Choose…") {
                    MacFolderPicker.show { url in
                        vaultManager.setVaultFolder(url)
                    }
                }
            }

            if showSubfolder, vaultManager.vaultURL != nil {
                LabeledContent("Subfolder") {
                    TextField("Health", text: $vaultManager.healthSubfolder)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: vaultManager.healthSubfolder) {
                            vaultManager.saveSubfolderSetting()
                        }
                }
            }

            if showClearButton, vaultManager.vaultURL != nil {
                Button("Clear Folder Selection", role: .destructive) {
                    vaultManager.clearVaultFolder()
                }
                .foregroundStyle(.red)
            }
        }
    }
}

#endif
