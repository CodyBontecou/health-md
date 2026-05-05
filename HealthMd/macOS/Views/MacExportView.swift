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
    @State private var showPaywall = false
    @State private var showPreview = false
    @State private var exportTask: Task<Void, Never>?
    @ObservedObject private var purchaseManager = PurchaseManager.shared

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
                            .accessibilityHidden(true)

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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(healthDataStore.recordCount > 0 
                        ? "Health data status: \(healthDataStore.recordCount) days synced" 
                        : "Health data status: No synced data. Sync from iPhone first.")

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
                                .accessibilityHidden(true)
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
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Export folder: \(vaultManager.vaultName)")
                            .accessibilityValue(url.path(percentEncoded: false))
                        } else {
                            Image(systemName: "folder")
                                .foregroundStyle(Color.textMuted)
                                .font(.system(size: 16))
                                .accessibilityHidden(true)
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
                        .accessibilityLabel(vaultManager.vaultURL != nil ? "Change export folder" : "Choose export folder")
                        .accessibilityHint("Opens folder picker to select export destination")
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
                                .accessibilityLabel("Subfolder name")
                                .accessibilityValue(vaultManager.healthSubfolder.isEmpty ? "Health" : vaultManager.healthSubfolder)
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
                        DatePicker("From date", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.accent)
                            .accessibilityLabel("Start date")
                    }

                    HStack {
                        Text("To")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        DatePicker("To date", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(Color.accent)
                            .accessibilityLabel("End date")
                    }

                    HStack(spacing: 10) {
                        quickDateButton("Yesterday", hint: "Sets date range to yesterday only") {
                            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = yesterday
                            endDate = yesterday
                        }
                        quickDateButton("7 Days", hint: "Sets date range to the last 7 days") {
                            endDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                        }
                        quickDateButton("30 Days", hint: "Sets date range to the last 30 days") {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Formats")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Toggle(format.rawValue, isOn: Binding(
                                get: { advancedSettings.exportFormats.contains(format) },
                                set: { isOn in
                                    if isOn { advancedSettings.exportFormats.insert(format) }
                                    else { advancedSettings.exportFormats.remove(format) }
                                }
                            ))
                            .tint(Color.accent)
                            .accessibilityLabel(format.rawValue)
                            .accessibilityValue(advancedSettings.exportFormats.contains(format) ? "Enabled" : "Disabled")
                        }
                        if advancedSettings.exportFormats.isEmpty {
                            Text("Select at least one export format.")
                                .font(BrandTypography.caption())
                                .foregroundStyle(Color.red)
                        }
                    }

                    HStack {
                        Text("Write Mode")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Picker("Write mode", selection: $advancedSettings.writeMode) {
                            ForEach(WriteMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accent)
                        .frame(width: 180)
                        .accessibilityLabel("File write mode")
                        .accessibilityValue(advancedSettings.writeMode.rawValue)
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Health metrics")
                        .accessibilityValue("\(advancedSettings.metricSelection.totalEnabledCount) of \(advancedSettings.metricSelection.totalMetricCount) enabled")
                        Spacer()
                        Button("Configure…") {
                            showMetricSelection = true
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                        .accessibilityLabel("Configure health metrics")
                        .accessibilityHint("Opens metric selection to choose which health data to export")
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
                            .accessibilityLabel("Stop export")
                            .accessibilityHint("Cancels the current export operation")
                        }

                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                            Text(exportStatusMessage)
                                .font(BrandTypography.detail())
                                .foregroundStyle(Color.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Export progress")
                        .accessibilityValue("\(exportStatusMessage), \(Int(exportProgress * 100)) percent complete")
                        
                        ProgressView(value: exportProgress)
                            .tint(Color.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard()
                }

                // MARK: - Free Exports Remaining
                if !isExporting && !purchaseManager.isUnlocked && purchaseManager.freeExportsRemaining > 0 {
                    let remaining = purchaseManager.freeExportsRemaining
                    HStack(spacing: 8) {
                        Image(systemName: "gift")
                            .foregroundStyle(Color.accent)
                        Text(remaining == 1
                             ? "1 free export remaining — unlock for unlimited access."
                             : "\(remaining) free exports remaining — unlock for unlimited access.")
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.textMuted)
                        Spacer()
                        Button("Unlock") { showPaywall = true }
                            .buttonStyle(.bordered)
                            .tint(Color.accent)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard(tintOpacity: 0.04)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(remaining) free export\(remaining == 1 ? "" : "s") remaining")
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
                    showPreview = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("Preview")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                .disabled(!canPreview || isExporting)
                .keyboardShortcut("p", modifiers: .command)
                .tint(Color.accent)
                .accessibilityLabel("Preview export")
                .accessibilityHint("Shows the files and contents that will be exported")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if purchaseManager.canExport {
                        exportData()
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: purchaseManager.canExport ? "arrow.up.doc.fill" : "lock.fill")
                        Text(purchaseManager.canExport ? "Export Now" : "Unlock to Export")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                .disabled(!canExport || isExporting)
                .keyboardShortcut("e", modifiers: .command)
                .tint(Color.accent)
                .accessibilityLabel(isExporting ? "Exporting" : (purchaseManager.canExport ? "Export now" : "Unlock to export"))
                .accessibilityHint(purchaseManager.canExport ? "Exports health data to the selected folder" : "Opens the unlock screen")
                .accessibilityValue(isExporting ? "\(Int(exportProgress * 100)) percent complete" : "")
            }
        }
        .sheet(isPresented: $showPaywall) {
            MacPaywallView()
        }
        .sheet(isPresented: $showMetricSelection) {
            MacMetricSelectionView(selectionState: advancedSettings.metricSelection)
                .frame(minWidth: 500, minHeight: 500)
        }
        .sheet(isPresented: $showPreview) {
            ExportPreviewView(
                startDate: startDate,
                endDate: endDate,
                vaultManager: vaultManager,
                settings: advancedSettings,
                fetchHealthData: { date in
                    healthDataStore.fetchHealthData(for: date)
                }
            )
            .frame(minWidth: 600, minHeight: 600)
        }
        .alert(resultIsError ? "Export Failed" : "Export Complete", isPresented: $showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Helpers

    private var canExport: Bool {
        healthDataStore.recordCount > 0
            && vaultManager.vaultURL != nil
            && !advancedSettings.exportFormats.isEmpty
    }

    private var canPreview: Bool {
        healthDataStore.recordCount > 0 && !advancedSettings.exportFormats.isEmpty
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
    private func quickDateButton(_ label: String, hint: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BrandTypography.caption())
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textSecondary)
        .brandGlassPill(tint: Color.accent)
        .accessibilityLabel(label)
        .accessibilityHint(hint.isEmpty ? "Sets date range to \(label.lowercased())" : hint)
    }

    // MARK: - Export Logic

    private func exportData() {
        guard purchaseManager.canExport else {
            showPaywall = true
            return
        }

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
                        formatsPerDate: advancedSettings.exportFormats.count,
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
                failedDateDetails: failedDateDetails,
                formatsPerDate: advancedSettings.exportFormats.count
            )

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: dates.first ?? startDate,
                dateRangeEnd: dates.last ?? endDate
            )

            // Count this as one export action against the free quota.
            if result.successCount > 0 {
                purchaseManager.recordExportUse()
            }

            if result.isFullSuccess {
                resultIsError = false
                if result.formatsPerDate > 1 {
                    resultMessage = String(localized: "Successfully exported \(result.totalFilesWritten) files (\(result.successCount) days × \(result.formatsPerDate) formats).", comment: "Multi-format export success message")
                } else {
                    resultMessage = String(localized: "Successfully exported \(result.successCount) files.", comment: "Export success message")
                }
            } else if result.isPartialSuccess {
                resultIsError = false
                if result.formatsPerDate > 1 {
                    resultMessage = String(localized: "Exported \(result.totalFilesWritten) files (\(result.successCount) of \(result.totalCount) days × \(result.formatsPerDate) formats). Some dates had no synced data.", comment: "Multi-format partial export message")
                } else {
                    resultMessage = String(localized: "Exported \(result.successCount) of \(result.totalCount) files. Some dates had no synced data.", comment: "Partial export message")
                }
            } else {
                resultIsError = true
                resultMessage = result.primaryFailureReason?.detailedDescription ?? String(localized: "No synced data found for the selected date range.", comment: "Export failure reason")
            }
            showResult = true
        }
    }
}

#endif
