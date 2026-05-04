import SwiftUI
import UIKit

// MARK: - iPad Root View (matching macOS NavigationSplitView layout)

struct iPadContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var schedulingManager: SchedulingManager
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()

    @State private var selectedTab: iPadNavItem? = .export
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var showFolderPicker = false
    @State private var showExportModal = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var exportTask: Task<Void, Never>?
    @State private var showSubfolderPrompt = false
    @State private var pendingFolderURL: URL?
    @State private var tempSubfolderName = ""
    @State private var showPaywall = false
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    var body: some View {
        NavigationSplitView {
            iPadSidebar(selectedTab: $selectedTab)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            Group {
                switch selectedTab {
                case .sync:
                    iPadSyncView()
                case .export:
                    iPadExportView(
                        healthKitManager: healthKitManager,
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        startDate: $startDate,
                        endDate: $endDate,
                        isExporting: $isExporting,
                        exportProgress: $exportProgress,
                        exportStatusMessage: $exportStatusMessage,
                        showFolderPicker: $showFolderPicker,
                        canExport: canExport,
                        onCancelExport: cancelExport,
                        onExport: exportData,
                        onExportTapped: {
                            if purchaseManager.canExport {
                                showExportModal = true
                            } else {
                                showPaywall = true
                            }
                        }
                    )
                case .schedule:
                    iPadScheduleView()
                        .environmentObject(schedulingManager)
                        .environmentObject(healthKitManager)
                case .history:
                    iPadHistoryView()
                case .settings:
                    iPadSettingsView(
                        vaultManager: vaultManager,
                        advancedSettings: advancedSettings,
                        showFolderPicker: $showFolderPicker
                    )
                case .none:
                    brandPlaceholder
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.accent)
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                pendingFolderURL = url
                tempSubfolderName = vaultManager.healthSubfolder
                showSubfolderPrompt = true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Name Your Export Folder", isPresented: $showSubfolderPrompt) {
            TextField("Health", text: $tempSubfolderName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                pendingFolderURL = nil
                tempSubfolderName = ""
            }
            Button("Save") {
                if let url = pendingFolderURL {
                    vaultManager.setVaultFolder(url)
                    vaultManager.healthSubfolder = tempSubfolderName.isEmpty ? "Health" : tempSubfolderName
                    vaultManager.saveSubfolderSetting()
                }
                pendingFolderURL = nil
                tempSubfolderName = ""
            }
        } message: {
            Text("Enter a name for the subfolder where your health data will be exported.")
        }
        .sheet(isPresented: $showExportModal) {
            ExportModal(
                startDate: $startDate,
                endDate: $endDate,
                subfolder: $vaultManager.healthSubfolder,
                vaultName: vaultManager.vaultName,
                onExport: exportData,
                onSubfolderChange: { vaultManager.saveSubfolderSetting() },
                exportSettings: advancedSettings
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert(
            schedulingManager.notificationExportResult?.title ?? "Export",
            isPresented: Binding(
                get: { schedulingManager.notificationExportResult != nil },
                set: { if !$0 { schedulingManager.notificationExportResult = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                schedulingManager.notificationExportResult = nil
            }
        } message: {
            if let result = schedulingManager.notificationExportResult {
                Text(result.message)
            }
        }
        .task {
            if healthKitManager.isHealthDataAvailable && !healthKitManager.isAuthorized {
                do {
                    try await healthKitManager.requestAuthorization()
                } catch {
                    // Silent fail on launch
                }
            }
        }
    }

    // MARK: - Placeholder

    private var brandPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(Color.accent)
            Text("health.md")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
            Text("Select a section from the sidebar")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Computed Properties

    private var canExport: Bool {
        healthKitManager.isAuthorized
            && vaultManager.vaultURL != nil
            && !advancedSettings.exportFormats.isEmpty
    }

    // MARK: - Auto-Sync

    private func autoSyncDates(_ dates: [Date]) async {
        var records: [HealthData] = []
        for date in dates {
            if let data = try? await healthKitManager.fetchHealthData(for: date), data.hasAnyData {
                records.append(data)
            }
        }
        guard !records.isEmpty else { return }

        let payload = SyncPayload(
            deviceName: UIDevice.current.name,
            syncTimestamp: Date(),
            healthRecords: records
        )
        syncService.sendLargePayload(.healthData(payload))
    }

    // MARK: - Export

    private func cancelExport() {
        exportTask?.cancel()
    }

    private func exportData() {
        guard purchaseManager.canExport else {
            showExportModal = false
            showPaywall = true
            return
        }

        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""

        exportTask = Task {
            defer {
                isExporting = false
                exportProgress = 0.0
                exportTask = nil
            }

            let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)

            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: advancedSettings,
                onProgress: { current, total, dateStr in
                    exportStatusMessage = "Exporting \(dateStr)… (\(current)/\(total))"
                    exportProgress = Double(current) / Double(total)
                }
            )

            let normalizedStartDate = dates.first ?? startDate
            let normalizedEndDate = dates.last ?? endDate

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: normalizedStartDate,
                dateRangeEnd: normalizedEndDate
            )

            // Count this as one export action against the free quota.
            if result.successCount > 0 {
                purchaseManager.recordExportUse()
            }

            if result.successCount > 0,
               syncService.connectionState == .connected,
               UserDefaults.standard.bool(forKey: "syncEnabled"),
               UserDefaults.standard.bool(forKey: "autoSyncAfterExport") {
                await autoSyncDates(dates)
            }

            if result.wasCancelled {
                if result.successCount > 0 {
                    exportStatusMessage = String(localized: "Export stopped — \(result.successCount) of \(result.totalCount) files exported", comment: "Export cancelled with partial success")
                } else {
                    exportStatusMessage = String(localized: "Export cancelled", comment: "Export was cancelled")
                }
            } else if result.isFullSuccess {
                exportStatusMessage = String(localized: "Successfully exported \(result.successCount) files", comment: "Export success message")
            } else if result.isPartialSuccess {
                let failedDatesStr = result.failedDateDetails.map { $0.dateString }.joined(separator: ", ")
                exportStatusMessage = String(localized: "Exported \(result.successCount)/\(result.totalCount) files. Failed: \(failedDatesStr)", comment: "Partial export with failures")
            } else {
                let primaryReason = result.primaryFailureReason ?? .unknown
                exportStatusMessage = String(localized: "Export failed: \(primaryReason.shortDescription)", comment: "Export failure message")

                if let firstFailedDetail = result.failedDateDetails.first {
                    errorMessage = firstFailedDetail.detailedMessage
                } else {
                    errorMessage = primaryReason.detailedDescription
                }
                showError = true
            }
        }
    }
}
