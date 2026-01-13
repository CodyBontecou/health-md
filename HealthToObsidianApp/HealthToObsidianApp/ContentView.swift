import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @EnvironmentObject var schedulingManager: SchedulingManager

    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showFolderPicker = false
    @State private var showExportModal = false
    @State private var showScheduleSettings = false
    @State private var showAdvancedSettings = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Clean minimal background
            AnimatedMeshBackground()

            // Main content
            VStack(spacing: 0) {
                // Header
                AnimatedHeader()
                    .staggeredAppear(index: 0)
                    .padding(.horizontal, Spacing.lg)

                Spacer()

                // Central content area
                VStack(spacing: Spacing.xl) {
                    // Status badges - compact display
                    HStack(spacing: Spacing.lg) {
                        CompactStatusBadge(
                            icon: "heart.fill",
                            title: "Health",
                            isConnected: healthKitManager.isAuthorized,
                            action: !healthKitManager.isAuthorized ? {
                                Task {
                                    try? await healthKitManager.requestAuthorization()
                                }
                            } : nil
                        )

                        CompactStatusBadge(
                            icon: "folder.fill",
                            title: vaultManager.vaultURL != nil ? vaultManager.vaultName : "Vault",
                            isConnected: vaultManager.vaultURL != nil,
                            action: {
                                showFolderPicker = true
                            }
                        )
                    }
                    .staggeredAppear(index: 1)

                    // Main Export Button
                    PrimaryButton(
                        "Export Health Data",
                        icon: "arrow.up.doc.fill",
                        isLoading: isExporting,
                        isDisabled: !canExport,
                        action: { showExportModal = true }
                    )
                    .staggeredAppear(index: 2)

                    // Schedule Settings Button
                    Button(action: { showScheduleSettings = true }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: schedulingManager.schedule.isEnabled ? "clock.fill" : "clock")
                                .font(.system(size: 14, weight: .medium))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(schedulingManager.schedule.isEnabled ? "Schedule Active" : "Schedule Exports")
                                    .font(Typography.body())

                                if schedulingManager.schedule.isEnabled,
                                   let nextExport = schedulingManager.getNextExportDescription() {
                                    Text(nextExport)
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(schedulingManager.schedule.isEnabled ? Color.accent : Color.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.bgSecondary.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            schedulingManager.schedule.isEnabled ? Color.accent.opacity(0.3) : Color.borderDefault,
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .staggeredAppear(index: 3)

                    // Advanced Settings Button
                    Button(action: { showAdvancedSettings = true }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14, weight: .medium))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Advanced Settings")
                                    .font(Typography.body())

                                Text("\(advancedSettings.exportFormat.rawValue) • \(selectedDataTypesText)")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.bgSecondary.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.borderDefault, lineWidth: 1)
                                )
                        )
                    }
                    .staggeredAppear(index: 4)

                    // Export progress indicator
                    if isExporting && !exportStatusMessage.isEmpty {
                        VStack(spacing: Spacing.xs) {
                            Text(exportStatusMessage)
                                .font(Typography.caption())
                                .foregroundStyle(Color.textSecondary)

                            ProgressView(value: exportProgress)
                                .tint(.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, Spacing.lg)
                    }

                    // Export status feedback
                    if let status = vaultManager.lastExportStatus {
                        ExportStatusBadge(
                            status: status.starts(with: "Exported")
                                ? .success(status)
                                : .error(status)
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)

                Spacer()
                Spacer()
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
        .sheet(isPresented: $showExportModal) {
            ExportModal(
                startDate: $startDate,
                endDate: $endDate,
                subfolder: $vaultManager.healthSubfolder,
                vaultName: vaultManager.vaultName,
                onExport: exportData,
                onSubfolderChange: { vaultManager.saveSubfolderSetting() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScheduleSettings) {
            ScheduleSettingsView()
                .environmentObject(schedulingManager)
        }
        .sheet(isPresented: $showAdvancedSettings) {
            AdvancedSettingsView(settings: advancedSettings)
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

    private var selectedDataTypesText: String {
        var types: [String] = []
        if advancedSettings.dataTypes.sleep { types.append("Sleep") }
        if advancedSettings.dataTypes.activity { types.append("Activity") }
        if advancedSettings.dataTypes.vitals { types.append("Vitals") }
        if advancedSettings.dataTypes.body { types.append("Body") }
        if advancedSettings.dataTypes.workouts { types.append("Workouts") }

        if types.count == 5 {
            return "All data types"
        } else if types.isEmpty {
            return "No data types"
        } else {
            return types.joined(separator: ", ")
        }
    }

    // MARK: - Export

    private func exportData() {
        isExporting = true
        exportProgress = 0.0
        exportStatusMessage = ""

        Task {
            defer {
                isExporting = false
                exportProgress = 0.0
            }

            do {
                // Calculate all dates in the range
                var dates: [Date] = []
                var currentDate = startDate
                let calendar = Calendar.current

                // Normalize dates to start of day
                currentDate = calendar.startOfDay(for: currentDate)
                let normalizedEndDate = calendar.startOfDay(for: endDate)

                while currentDate <= normalizedEndDate {
                    dates.append(currentDate)
                    guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                        break
                    }
                    currentDate = nextDate
                }

                let totalDays = dates.count
                var successCount = 0
                var failedDates: [String] = []
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                // Export data for each date
                for (index, date) in dates.enumerated() {
                    exportStatusMessage = "Exporting \(dateFormatter.string(from: date))... (\(index + 1)/\(totalDays))"

                    do {
                        let healthData = try await healthKitManager.fetchHealthData(for: date)
                        try await vaultManager.exportHealthData(healthData, settings: advancedSettings)
                        successCount += 1
                    } catch {
                        failedDates.append(dateFormatter.string(from: date))
                    }

                    exportProgress = Double(index + 1) / Double(totalDays)
                }

                // Update final status
                if failedDates.isEmpty {
                    exportStatusMessage = "Successfully exported \(successCount) file\(successCount == 1 ? "" : "s")"
                    vaultManager.lastExportStatus = "Exported \(successCount) file\(successCount == 1 ? "" : "s")"
                } else {
                    exportStatusMessage = "Exported \(successCount)/\(totalDays) files. Failed: \(failedDates.joined(separator: ", "))"
                    vaultManager.lastExportStatus = "Partial export: \(successCount)/\(totalDays) succeeded"
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                exportStatusMessage = ""
            }
        }
    }
}

#Preview {
    ContentView()
}
