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
    @State private var showTodayRefreshInfo = false

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

    private var frequencyBinding: Binding<ScheduleFrequency> {
        Binding(
            get: { schedulingManager.schedule.frequency },
            set: { frequency in
                var schedule = schedulingManager.schedule
                let oldDefault = recommendedLookback(for: schedule)
                let followsDefault = schedule.lookbackDays == oldDefault
                if frequency == .custom, schedule.frequency != .custom {
                    schedule.customAnchorDate = Calendar.current.startOfDay(for: Date())
                }
                schedule.frequency = frequency
                if followsDefault { schedule.lookbackDays = recommendedLookback(for: schedule) }
                schedulingManager.schedule = schedule
            }
        )
    }

    private var customIntervalBinding: Binding<Int> {
        Binding(
            get: { schedulingManager.schedule.customInterval },
            set: { interval in
                var schedule = schedulingManager.schedule
                let oldDefault = recommendedLookback(for: schedule)
                let followsDefault = schedule.lookbackDays == oldDefault
                schedule.customInterval = ExportSchedule.clampedCustomInterval(interval)
                if followsDefault { schedule.lookbackDays = recommendedLookback(for: schedule) }
                schedulingManager.schedule = schedule
            }
        )
    }

    private var customUnitBinding: Binding<ScheduleIntervalUnit> {
        Binding(
            get: { schedulingManager.schedule.customUnit },
            set: { unit in
                var schedule = schedulingManager.schedule
                let oldDefault = recommendedLookback(for: schedule)
                let followsDefault = schedule.lookbackDays == oldDefault
                schedule.customUnit = unit
                if followsDefault { schedule.lookbackDays = recommendedLookback(for: schedule) }
                schedulingManager.schedule = schedule
            }
        )
    }

    private var customAnchorDateBinding: Binding<Date> {
        Binding(
            get: { schedulingManager.schedule.customAnchorDate },
            set: { date in
                var schedule = schedulingManager.schedule
                schedule.customAnchorDate = Calendar.current.startOfDay(for: date)
                schedulingManager.schedule = schedule
            }
        )
    }

    private func recommendedLookback(for schedule: ExportSchedule) -> Int {
        ExportSchedule.defaultLookbackDays(
            for: schedule.frequency,
            customInterval: schedule.customInterval,
            customUnit: schedule.customUnit
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
                    scheduledDestinationSection

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
                            Picker("Frequency", selection: frequencyBinding) {
                                ForEach(ScheduleFrequency.allCases, id: \.self) { frequency in
                                    Text(frequency.description).tag(frequency)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 300)
                        }

                        if schedulingManager.schedule.frequency == .custom {
                            Divider().background(Color.borderSubtle)

                            VStack(alignment: .leading, spacing: Spacing.s3) {
                                HStack(spacing: Spacing.s3) {
                                    Text("Every")
                                        .font(Typography.body())
                                        .foregroundStyle(Color.textSecondary)

                                    Stepper(
                                        "\(schedulingManager.schedule.customInterval)",
                                        value: customIntervalBinding,
                                        in: ExportSchedule.minimumCustomInterval...ExportSchedule.maximumCustomInterval
                                    )
                                    .fixedSize()

                                    Picker("Unit", selection: customUnitBinding) {
                                        ForEach(ScheduleIntervalUnit.allCases, id: \.self) { unit in
                                            Text(unit.label(for: schedulingManager.schedule.customInterval).capitalized)
                                                .tag(unit)
                                        }
                                    }
                                    .frame(width: 140)

                                    Spacer()
                                }

                                DatePicker(
                                    "Starting",
                                    selection: customAnchorDateBinding,
                                    displayedComponents: .date
                                )
                                .tint(Color.accent)

                                Text("The start date sets the repeating phase. Monthly schedules use the last day when a month is shorter.")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }
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

                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        HStack(spacing: Spacing.s2) {
                            iPadBrandLabel("Today Refresh")

                            Button {
                                showTodayRefreshInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("About Today Refresh")
                            .accessibilityHint("Explains how the refresh interval is scheduled")
                        }

                        Toggle("Refresh today’s export", isOn: Binding(
                            get: { schedulingManager.schedule.todayRefreshEnabled },
                            set: { enabled in
                                var schedule = schedulingManager.schedule
                                schedule.todayRefreshEnabled = enabled
                                schedulingManager.schedule = schedule
                            }
                        ))
                        .tint(Color.accent)

                        if schedulingManager.schedule.todayRefreshEnabled {
                            Picker("Refresh interval", selection: Binding(
                                get: { schedulingManager.schedule.todayRefreshIntervalHours },
                                set: { hours in
                                    var schedule = schedulingManager.schedule
                                    schedule.todayRefreshIntervalHours = ExportSchedule.clampedTodayRefreshIntervalHours(hours)
                                    schedulingManager.schedule = schedule
                                }
                            )) {
                                ForEach(ExportSchedule.todayRefreshIntervalOptions, id: \.self) { hours in
                                    Text("Every \(hours) hours").tag(hours)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading, spacing: Spacing.s2) {
                                VStack(alignment: .leading, spacing: Spacing.s1) {
                                    Text("When File Exists")
                                        .font(Typography.bodyEmphasis())
                                        .foregroundStyle(Color.textPrimary)

                                    Text(advancedSettings.writeMode.description)
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textSecondary)
                                }

                                Picker("Write Mode", selection: $advancedSettings.writeMode) {
                                    ForEach(WriteMode.allCases, id: \.self) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()

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
        .alert("Today Refresh", isPresented: $showTodayRefreshInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(todayRefreshInfoMessage)
        }
    }

    private var preferredTimeText: String {
        let hour = schedulingManager.schedule.preferredHour
        let minute = schedulingManager.schedule.preferredMinute
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let period = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", displayHour, minute, period)
    }

    private var todayRefreshInfoMessage: String {
        let interval = schedulingManager.schedule.todayRefreshIntervalHours
        return """
        Today Refresh rewrites today's export while the day is still in progress.

        Every \(interval) hours is relative to your Preferred Time (\(preferredTimeText)). Health.md targets \(preferredTimeText), then every \(interval) hours until midnight. If you enable it after a target time has passed, the next future slot is used.

        Automatic background exports depend on iOS. If Health.md needs your attention, unlock your device and tap the notification to run the pending export.
        """
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
