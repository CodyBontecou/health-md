#if os(macOS)
import SwiftUI

// MARK: - Export View

struct MacExportView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings

    @State private var startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var isExporting = false
    @State private var exportProgress = 0.0
    @State private var exportStatusMessage = ""
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var resultIsError = false
    @State private var showMetricSelection = false

    var body: some View {
        Form {
            // MARK: Health Connection
            Section {
                HStack {
                    statusDot(healthKitManager.isAuthorized ? .green : .secondary)
                    Text(healthKitManager.isAuthorized ? "Connected to Apple Health" : "Not Connected")
                        .foregroundStyle(healthKitManager.isAuthorized ? .primary : .secondary)
                    Spacer()
                    if !healthKitManager.isAuthorized {
                        Button("Authorize…") {
                            Task { try? await healthKitManager.requestAuthorization() }
                        }
                    }
                }
            } header: {
                Text("Health Connection")
            } footer: {
                if !healthKitManager.isAuthorized {
                    Text("After authorizing, grant access in System Settings → Privacy & Security → Health.")
                }
            }

            // MARK: Export Folder
            MacVaultFolderSection()

            // MARK: Date Range
            Section("Date Range") {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)

                HStack(spacing: 12) {
                    Button("Yesterday") {
                        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                        startDate = yesterday
                        endDate = yesterday
                    }
                    .buttonStyle(.bordered)

                    Button("Last 7 Days") {
                        endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                        startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                    }
                    .buttonStyle(.bordered)

                    Button("Last 30 Days") {
                        endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                        startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // MARK: Export Options
            Section("Export Options") {
                Picker("Format", selection: $advancedSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                    ForEach(WriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Health Metrics")
                        Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Configure…") {
                        showMetricSelection = true
                    }
                }
            }

            // MARK: Export Action
            if isExporting {
                Section("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(exportStatusMessage)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: exportProgress)
                    }
                }
            } else if !canExport {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        if !healthKitManager.isAuthorized && vaultManager.vaultURL == nil {
                            Text("Connect to Apple Health and choose an export folder to get started.")
                        } else if !healthKitManager.isAuthorized {
                            Text("Connect to Apple Health to export your data.")
                        } else {
                            Text("Choose an export folder to get started.")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Export")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportData()
                } label: {
                    Label("Export Now", systemImage: "arrow.up.doc.fill")
                }
                .disabled(!canExport || isExporting)
                .keyboardShortcut("e", modifiers: .command)
            }
        }
        .sheet(isPresented: $showMetricSelection) {
            MacMetricSelectionView(selectionState: advancedSettings.metricSelection)
                .frame(minWidth: 500, minHeight: 500)
        }
        .alert(resultIsError ? "Export Failed" : "Export Complete", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Helpers

    private var canExport: Bool {
        healthKitManager.isAuthorized && vaultManager.vaultURL != nil
    }

    @ViewBuilder
    private func statusDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func exportData() {
        isExporting = true
        exportProgress = 0.0

        Task {
            defer {
                isExporting = false
                exportProgress = 0.0
                exportStatusMessage = ""
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

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: dates.first ?? startDate,
                dateRangeEnd: dates.last ?? endDate
            )

            if result.isFullSuccess {
                resultIsError = false
                resultMessage = "Successfully exported \(result.successCount) file\(result.successCount == 1 ? "" : "s")."
            } else if result.isPartialSuccess {
                resultIsError = false
                resultMessage = "Exported \(result.successCount) of \(result.totalCount) files. Some dates had no data."
            } else {
                resultIsError = true
                resultMessage = result.primaryFailureReason?.detailedDescription ?? "Unknown error."
            }
            showResult = true
        }
    }
}

#endif
