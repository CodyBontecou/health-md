import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var vaultManager = VaultManager()

    @State private var selectedDate = Date()
    @State private var showFolderPicker = false
    @State private var isExporting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Clean background
            AnimatedMeshBackground()

            // Main content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    AnimatedHeader()

                    // Cards with increased spacing
                    VStack(spacing: Spacing.lg) {
                        // Health Connection Card
                        HealthConnectionCard(
                            isAuthorized: healthKitManager.isAuthorized,
                            statusText: healthKitManager.authorizationStatus
                        ) {
                            try await healthKitManager.requestAuthorization()
                        }

                        // Vault Selection Card
                        VaultSelectionCard(
                            vaultName: vaultManager.vaultName,
                            isSelected: vaultManager.vaultURL != nil,
                            onSelectVault: { showFolderPicker = true },
                            onClear: { vaultManager.clearVaultFolder() }
                        )

                        // Export Settings Card
                        ExportSettingsCard(
                            subfolder: $vaultManager.healthSubfolder,
                            selectedDate: $selectedDate,
                            exportPath: exportPath,
                            onSubfolderChange: { vaultManager.saveSubfolderSetting() }
                        )

                        // Spacer before action
                        Spacer()
                            .frame(height: Spacing.md)

                        // Export Button & Status
                        VStack(spacing: Spacing.md) {
                            PrimaryButton(
                                "Export Health Data",
                                icon: "arrow.up.doc.fill",
                                isLoading: isExporting,
                                isDisabled: !canExport,
                                action: exportData
                            )

                            // Export status feedback
                            if let status = vaultManager.lastExportStatus {
                                ExportStatusBadge(
                                    status: status.starts(with: "Exported")
                                        ? .success(status)
                                        : .error(status)
                                )
                            }
                        }

                        // Bottom spacing
                        Spacer()
                            .frame(height: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                vaultManager.setVaultFolder(url)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            // Request health authorization on launch if not already authorized
            if healthKitManager.isHealthDataAvailable && !healthKitManager.isAuthorized {
                do {
                    try await healthKitManager.requestAuthorization()
                } catch {
                    // Silent fail on launch - user can tap Connect button
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var canExport: Bool {
        healthKitManager.isAuthorized && vaultManager.vaultURL != nil
    }

    private var exportPath: String {
        let subfolder = vaultManager.healthSubfolder.isEmpty ? "" : vaultManager.healthSubfolder + "/"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return "\(vaultManager.vaultName)/\(subfolder)\(dateFormatter.string(from: selectedDate)).md"
    }

    // MARK: - Export

    private func exportData() {
        isExporting = true

        Task {
            defer { isExporting = false }

            do {
                let healthData = try await healthKitManager.fetchHealthData(for: selectedDate)
                try await vaultManager.exportHealthData(healthData)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    ContentView()
}
