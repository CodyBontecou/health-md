#if os(macOS)
import SwiftUI

// MARK: - Export View — Glass Card Layout

struct MacExportView: View {
    @EnvironmentObject var healthDataStore: HealthDataStore
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
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: - Data Source Status
                VStack(alignment: .leading, spacing: 14) {
                    BrandLabel("Health Data")

                    HStack(spacing: 12) {
                        Circle()
                            .fill(healthDataStore.recordCount > 0 ? Color.success : Color.textMuted)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthDataStore.recordCount > 0
                                 ? "\(healthDataStore.recordCount) days synced"
                                 : "No Synced Data")
                                .font(BrandTypography.bodyMedium())
                                .foregroundStyle(Color.textPrimary)

                            if let lastSync = healthDataStore.lastSyncDate {
                                Text("Last sync: \(lastSync, style: .relative) ago")
                                    .font(BrandTypography.detail())
                                    .foregroundStyle(Color.textMuted)
                            }
                            if let device = healthDataStore.lastSyncDevice {
                                Text("From: \(device)")
                                    .font(BrandTypography.detail())
                                    .foregroundStyle(Color.textMuted)
                            }
                        }

                        Spacer()

                        if healthDataStore.recordCount == 0 {
                            Text("Sync from iPhone first")
                                .font(BrandTypography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }

                    if healthDataStore.recordCount == 0 {
                        Text("Go to the Sync tab to connect your iPhone and download health data.")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .brandGlassCard()

                // MARK: - Export Folder
                VStack(alignment: .leading, spacing: 14) {
                    BrandLabel("Export Folder")

                    HStack(spacing: 10) {
                        if let url = vaultManager.vaultURL {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accent)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vaultManager.vaultName)
                                    .font(BrandTypography.bodyMedium())
                                    .foregroundStyle(Color.textPrimary)
                                Text(url.path(percentEncoded: false))
                                    .font(BrandTypography.caption())
                                    .foregroundStyle(Color.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } else {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.textMuted)
                                .font(.system(size: 16))
                            Text("No folder selected")
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Button(vaultManager.vaultURL != nil ? "Change…" : "Choose…") {
                            MacFolderPicker.show { url in
                                vaultManager.setVaultFolder(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }

                    if vaultManager.vaultURL != nil {
                        HStack {
                            Text("Subfolder")
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            TextField("Health", text: $vaultManager.healthSubfolder)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 200)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: vaultManager.healthSubfolder) {
                                    vaultManager.saveSubfolderSetting()
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .brandGlassCard()

                // MARK: - Date Range
                VStack(alignment: .leading, spacing: 14) {
                    BrandLabel("Date Range")

                    HStack {
                        Text("From")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.accent)
                    }

                    HStack {
                        Text("To")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.accent)
                    }

                    HStack(spacing: 10) {
                        quickDateButton("Yesterday") {
                            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = yesterday
                            endDate = yesterday
                        }
                        quickDateButton("7 Days") {
                            endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                        }
                        quickDateButton("30 Days") {
                            endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .brandGlassCard()

                // MARK: - Export Options
                VStack(alignment: .leading, spacing: 14) {
                    BrandLabel("Export Options")

                    HStack {
                        Text("Format")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Picker("", selection: $advancedSettings.exportFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accent)
                        .frame(width: 180)
                    }

                    HStack {
                        Text("Write Mode")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Picker("", selection: $advancedSettings.writeMode) {
                            ForEach(WriteMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accent)
                        .frame(width: 180)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health Metrics")
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textSecondary)
                            Text("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                                .font(BrandTypography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Button("Configure…") {
                            showMetricSelection = true
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .brandGlassCard()

                // MARK: - Export Progress
                if isExporting {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            BrandLabel("Progress")
                            Spacer()
                            Button {
                                exportTask?.cancel()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Stop")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                }
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.15))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(exportStatusMessage)
                                .font(BrandTypography.detail())
                                .foregroundStyle(Color.textSecondary)
                        }
                        ProgressView(value: exportProgress)
                            .tint(Color.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard()
                }

                // MARK: - Ready / Not Ready
                if !isExporting && !canExport {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.textMuted)
                        Text(readinessMessage)
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard(tintOpacity: 0.02)
                }
            }
            .padding(24)
        }
        .navigationTitle("Export")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportData()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.doc.fill")
                        Text("Export Now")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                .disabled(!canExport || isExporting)
                .keyboardShortcut("e", modifiers: .command)
                .tint(Color.accent)
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
        healthDataStore.recordCount > 0 && vaultManager.vaultURL != nil
    }

    private var readinessMessage: String {
        if healthDataStore.recordCount == 0 && vaultManager.vaultURL == nil {
            return "Sync health data from your iPhone and choose an export folder to get started."
        } else if healthDataStore.recordCount == 0 {
            return "Sync health data from your iPhone to export."
        } else {
            return "Choose an export folder to get started."
        }
    }

    @ViewBuilder
    private func quickDateButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BrandTypography.caption())
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textSecondary)
        .brandGlassPill(tint: Color.accent)
    }

    // MARK: - Export Logic

    private func exportData() {
        isExporting = true
        exportProgress = 0.0

        exportTask = Task {
            defer {
                isExporting = false
                exportProgress = 0.0
                exportStatusMessage = ""
                exportTask = nil
            }

            let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            var successCount = 0
            let totalCount = dates.count
            var failedDateDetails: [FailedDateDetail] = []

            for (index, date) in dates.enumerated() {
                // Check for cancellation before each date
                if Task.isCancelled {
                    let result = ExportOrchestrator.ExportResult(
                        successCount: successCount,
                        totalCount: totalCount,
                        failedDateDetails: failedDateDetails,
                        wasCancelled: true
                    )

                    ExportOrchestrator.recordResult(
                        result,
                        source: .manual,
                        dateRangeStart: dates.first ?? startDate,
                        dateRangeEnd: dates.last ?? endDate
                    )

                    resultIsError = false
                    if successCount > 0 {
                        resultMessage = String(localized: "Export stopped — \(successCount) of \(totalCount) files exported.", comment: "Export cancelled with partial success")
                    } else {
                        resultMessage = String(localized: "Export cancelled.", comment: "Export was cancelled")
                    }
                    showResult = true
                    return
                }

                let dateString = dateFormatter.string(from: date)
                exportStatusMessage = "Exporting \(dateString)… (\(index + 1)/\(totalCount))"
                exportProgress = Double(index + 1) / Double(totalCount)

                guard let healthData = healthDataStore.fetchHealthData(for: date) else {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                do {
                    try await vaultManager.exportHealthData(healthData, settings: advancedSettings)
                    successCount += 1
                } catch {
                    failedDateDetails.append(FailedDateDetail(
                        date: date, reason: .unknown, errorDetails: error.localizedDescription
                    ))
                }
            }

            let result = ExportOrchestrator.ExportResult(
                successCount: successCount,
                totalCount: totalCount,
                failedDateDetails: failedDateDetails
            )

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: dates.first ?? startDate,
                dateRangeEnd: dates.last ?? endDate
            )

            if result.isFullSuccess {
                resultIsError = false
                resultMessage = String(localized: "Successfully exported \(result.successCount) files.", comment: "Export success message")
            } else if result.isPartialSuccess {
                resultIsError = false
                resultMessage = String(localized: "Exported \(result.successCount) of \(result.totalCount) files. Some dates had no synced data.", comment: "Partial export message")
            } else {
                resultIsError = true
                resultMessage = result.primaryFailureReason?.detailedDescription ?? String(localized: "No synced data found for the selected date range.", comment: "Export failure reason")
            }
            showResult = true
        }
    }
}

#endif
