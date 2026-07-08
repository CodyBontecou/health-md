import SwiftUI

// MARK: - iPad Schedule View

struct iPadScheduleView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @StateObject private var apiExportSettings = APIExportSettings()
    @Binding var showFolderPicker: Bool
    @State private var showAPIEndpointSettings = false

    private var targetBinding: Binding<ExportTargetSelection> {
        Binding(
            get: { schedulingManager.schedule.target },
            set: { target in
                var schedule = schedulingManager.schedule
                schedule.target = target
                schedulingManager.schedule = schedule
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HealthMdPageHeader(
                    title: "Scheduled Exports",
                    subtitle: "Keep your Health.md destinations updated with recurring Apple Health exports"
                )

                VStack(alignment: .leading, spacing: Spacing.s3) {
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("Automatic Export")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(schedulingManager.schedule.isEnabled ? "Enabled" : "Disabled")
                                .font(Typography.caption())
                                .foregroundStyle(schedulingManager.schedule.isEnabled ? Color.success : Color.textMuted)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { schedulingManager.schedule.isEnabled },
                            set: { enabled in
                                var schedule = schedulingManager.schedule
                                schedule.isEnabled = enabled
                                schedulingManager.schedule = schedule
                            }
                        ))
                        .labelsHidden()
                        .tint(Color.accent)
                    }

                    Text("Health.md will automatically export your health data on the schedule below.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                if schedulingManager.schedule.isEnabled {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        iPadBrandLabel("Configuration")

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.s1) {
                                Text("Frequency")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                Text("Choose how often Health.md prepares an export.")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            Picker("Frequency", selection: Binding(
                                get: { schedulingManager.schedule.frequency },
                                set: { frequency in
                                    var schedule = schedulingManager.schedule
                                    schedule.frequency = frequency
                                    schedulingManager.schedule = schedule
                                }
                            )) {
                                Text("Daily").tag(ScheduleFrequency.daily)
                                Text("Weekly").tag(ScheduleFrequency.weekly)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        Divider().background(Color.borderSubtle)

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.s1) {
                                Text("Preferred Time")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                Text("iOS uses this as the target time for background scheduling.")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer()
                            DatePicker(
                                "Preferred Time",
                                selection: Binding(
                                    get: {
                                        var components = DateComponents()
                                        components.hour = schedulingManager.schedule.preferredHour
                                        components.minute = schedulingManager.schedule.preferredMinute
                                        return Calendar.current.date(from: components) ?? Date()
                                    },
                                    set: { date in
                                        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                                        var schedule = schedulingManager.schedule
                                        schedule.preferredHour = components.hour ?? 8
                                        schedule.preferredMinute = components.minute ?? 0
                                        schedulingManager.schedule = schedule
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .tint(Color.accent)
                        }

                    }
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()

                    scheduledDestinationSection

                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        iPadBrandLabel("Background")
                        Text("iOS determines the optimal background task timing. Make sure Background App Refresh is enabled for Health.md in Settings.")
                            .font(Typography.body())
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()

                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        iPadBrandLabel("Status")

                        iPadBrandDataRow(
                            label: "Last Export",
                            value: schedulingManager.schedule.lastExportDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never"
                        )

                        if let next = schedulingManager.getNextExportDescription() {
                            Divider().background(Color.borderSubtle)
                            iPadBrandDataRow(label: "Next Export", value: next)
                        }

                    }
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s8)
            .iPadContentColumn()
        }
        .scrollIndicators(.hidden)
        .iPadPageBackground()
        .navigationTitle("Schedule")
        .iPadHiddenSystemNavigationTitle()
        .sheet(isPresented: $showAPIEndpointSettings) {
            APIExportSettingsSheet(settings: apiExportSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var scheduledDestinationSection: some View {
        ExportTargetSectionView(
            title: "Export Destination",
            localTitle: "Local iPad Folder",
            localIcon: "ipad",
            selection: targetBinding,
            localSubtitle: scheduledLocalTargetSubtitle,
            macSubtitle: scheduledMacTargetSubtitle,
            apiSubtitle: scheduledAPITargetSubtitle,
            canExportToConnectedMac: canScheduleToConnectedMac,
            shouldPromptForLocalFolder: vaultManager.vaultURL == nil,
            localAccessibilityIdentifier: AccessibilityID.Schedule.localTargetOption,
            macAccessibilityIdentifier: AccessibilityID.Schedule.macTargetOption,
            apiAccessibilityIdentifier: AccessibilityID.Schedule.apiTargetOption,
            onRequestFolderPicker: { showFolderPicker = true },
            onOpenAPISettings: { showAPIEndpointSettings = true }
        )
    }

    private var scheduledLocalTargetSubtitle: String {
        if vaultManager.vaultURL != nil {
            return "Scheduled exports write to \(vaultManager.vaultName) on this iPad."
        }
        if vaultManager.hasSavedVaultFolder {
            return "Saved folder unavailable. Reconnect it in Files or tap to re-select."
        }
        return "Local iPad folder. Tap to choose a folder."
    }

    private var scheduledMacTargetSubtitle: String {
        if canScheduleToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return "Ready on Mac: \(path). Keep the Mac awake with Health.md open at schedule time."
            }
            if let name = syncService.macDestinationStatus?.destinationDisplayName {
                return "Ready on Mac: \(name). Keep the Mac awake with Health.md open at schedule time."
            }
            return "Ready now. Keep the Mac awake with Health.md open at schedule time."
        }
        return scheduledMacTargetUnavailableMessage
    }

    private var scheduledAPITargetSubtitle: String {
        if apiExportSettings.isConfigured {
            return "Scheduled JSON exports POST to \(apiExportSettings.displayName). Tap to edit."
        }
        return "Send scheduled JSON exports to your HTTP(S) endpoint. Tap to configure."
    }

    private var canScheduleToConnectedMac: Bool {
        syncService.canExportToConnectedMac(requiring: advancedSettings)
    }

    private var scheduledMacTargetUnavailableMessage: String {
        guard syncService.connectionState == .connected else {
            return "No Mac connected. Open Health.md on your Mac before choosing this target."
        }
        guard let capabilities = syncService.remoteCapabilities else {
            return syncService.macExportReadinessMessage(requiring: advancedSettings)
        }
        guard capabilities.platform == .macOS,
              capabilities.isCompatibleWithMacExportJobs else {
            return "Incompatible Mac. Update Health.md on Mac."
        }
        if syncService.canExportToConnectedMac,
           !syncService.canExportToConnectedMac(requiring: advancedSettings) {
            return syncService.macExportReadinessMessage(requiring: advancedSettings)
        }
        guard let status = syncService.macDestinationStatus else {
            return syncService.macExportReadinessMessage(requiring: advancedSettings)
        }
        if status.activeJobID != nil {
            return "Mac busy. Wait for the current export to finish."
        }
        if !status.destinationFolderSelected {
            return "No folder selected. Choose a folder on Mac."
        }
        if !status.folderAccessHealthy {
            return "Mac folder access denied. Re-select the folder on Mac."
        }
        return syncService.macExportReadinessMessage(requiring: advancedSettings)
    }
}
