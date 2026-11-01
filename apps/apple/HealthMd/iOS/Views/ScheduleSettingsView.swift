import SwiftUI

struct ScheduleRetryExportPolicy {
    static func shouldWriteDataDictionary(currentFileCount: Int) -> Bool {
        currentFileCount == 0
    }

    static func canRetry(_ entry: ExportHistoryEntry) -> Bool {
        guard !entry.isFullSuccess,
              entry.source != .macAgent,
              entry.operationDetails == nil else { return false }
        if entry.exportTarget == .localIPhoneFolder { return true }
        // Legacy local-folder entries predate the typed target. They either
        // had no label or used the established iPhone prefix.
        return entry.exportTarget == nil
            && (entry.targetLabel == nil || entry.targetLabel?.hasPrefix("iPhone: ") == true)
    }

    static func failedDateDetail(for date: Date, exportError: ExportError) -> FailedDateDetail {
        let reason: ExportFailureReason
        let details: String?
        switch exportError {
        case .noVaultSelected:
            reason = .noVaultSelected
            details = nil
        case .noHealthData:
            reason = .noHealthData
            details = nil
        case .accessDenied:
            reason = .accessDenied
            details = nil
        case .destinationChanged:
            reason = .accessDenied
            details = exportError.localizedDescription
        case .noFormatsSelected:
            reason = .unknown
            details = exportError.localizedDescription
        case .markdownMergeRejected, .dailyNotePathConflict, .invalidExportPath:
            reason = .fileWriteError
            details = exportError.localizedDescription
        }
        return FailedDateDetail(date: date, reason: reason, errorDetails: details)
    }

    static func failedWriteDetail(for date: Date, error: Error) -> FailedDateDetail {
        if let exportError = error as? ExportError {
            return failedDateDetail(for: date, exportError: exportError)
        }
        return FailedDateDetail(
            date: date,
            reason: .fileWriteError,
            errorDetails: error.localizedDescription
        )
    }

    static func failedDailyNoteDetail(
        for date: Date,
        result: DailyNoteInjector.InjectionResult?
    ) -> FailedDateDetail? {
        switch result {
        case .updated:
            return nil
        case .skipped(let reason):
            return FailedDateDetail(date: date, reason: .noHealthData, errorDetails: reason)
        case .failed(let error):
            return failedWriteDetail(for: date, error: error)
        case .none:
            return FailedDateDetail(
                date: date,
                reason: .fileWriteError,
                errorDetails: "Daily note update was not performed."
            )
        }
    }

    static func failedHealthKitDetail(for date: Date, error: Error) -> FailedDateDetail {
        if let healthKitError = error as? HealthKitManager.HealthKitError {
            let reason: ExportFailureReason
            switch healthKitError {
            case .dataProtectedWhileLocked:
                reason = .deviceLocked
            case .dataNotAvailable, .notAuthorized, .medicationAuthorizationUnsupported,
                 .visionAuthorizationUnsupported:
                reason = .healthKitError
            }
            return FailedDateDetail(date: date, reason: reason)
        }
        return FailedDateDetail(
            date: date,
            reason: .unknown,
            errorDetails: error.localizedDescription
        )
    }
}

/// Inline schedule configuration surface used by the Schedule tab.
/// Binds directly to `SchedulingManager.schedule` so edits persist as they happen.
struct ScheduleSettingsView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject var apiExportSettings: APIExportSettings
    @ObservedObject var agentDataGatewaySettings: AgentDataGatewaySettings
    @Binding var showFolderPicker: Bool
    /// Built by ContentView when the main UI appears; forwarded so
    /// `GlassProfileScheduleList` observes the shared profile stores.
    var profileCoordinator: ExportProfileCoordinator? = nil
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    @Environment(\.glassPalette) private var palette

    @State private var selectedEntry: ExportHistoryEntry?
    /// History is paged in tens; "N more entries…" reveals the next page.
    @State private var visibleHistoryCount = ScheduleSettingsView.historyPageSize
    @State private var showAPIEndpointSettings = false
    @State private var showAgentDataGatewaySettings = false
    @State private var showTodayRefreshInfo = false

    // Retry export state
    @State private var isRetrying = false
    @State private var retryProgress: Double = 0.0
    @State private var retryStatusMessage = ""
    @State private var showRetryError = false
    @State private var retryErrorMessage = ""

    /// Phase 3: the master toggle reflects any active schedule (legacy or
    /// per-profile entries). On: enables the first profile's entry (seeded
    /// from the legacy preferred time). Off: disables every entry and the
    /// legacy schedule.
    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { schedulingManager.isSchedulingActive },
            set: { newValue in
                let wasEnabled = schedulingManager.isSchedulingActive
                if newValue && !wasEnabled {
                    trackScheduleEnableAttempt()
                    Task { @MainActor in
                        _ = await schedulingManager.requestNotificationPermissions()
                        configurationProtection.performConfigurationChange {
                            self.enableFirstProfileEntry()
                            UIAccessibility.post(notification: .announcement, argument: String(localized: "Schedule enabled"))
                        }
                    }
                } else {
                    configurationProtection.performConfigurationChange {
                        self.disableAllSchedules()
                    }
                    if wasEnabled && !newValue {
                        UIAccessibility.post(notification: .announcement, argument: String(localized: "Schedule disabled"))
                    }
                }
            }
        )
    }

    private var frequencyBinding: Binding<ScheduleFrequency> {
        Binding(
            get: { schedulingManager.schedule.frequency },
            set: { newValue in
                var updated = schedulingManager.schedule
                let previousDefault = ExportSchedule.defaultLookbackDays(
                    for: updated.frequency,
                    customInterval: updated.customInterval,
                    customUnit: updated.customUnit
                )
                let shouldFollowFrequencyDefault = updated.lookbackDays == previousDefault
                if newValue == .custom, updated.frequency != .custom {
                    updated.customAnchorDate = Calendar.current.startOfDay(for: Date())
                }
                updated.frequency = newValue
                if shouldFollowFrequencyDefault {
                    updated.lookbackDays = ExportSchedule.defaultLookbackDays(
                        for: newValue,
                        customInterval: updated.customInterval,
                        customUnit: updated.customUnit
                    )
                }
                schedulingManager.schedule = updated
            }
        )
    }

    private var customIntervalBinding: Binding<Int> {
        Binding(
            get: { schedulingManager.schedule.customInterval },
            set: { newValue in
                var updated = schedulingManager.schedule
                let previousDefault = ExportSchedule.defaultLookbackDays(
                    for: .custom,
                    customInterval: updated.customInterval,
                    customUnit: updated.customUnit
                )
                let shouldFollowFrequencyDefault = updated.lookbackDays == previousDefault
                updated.customInterval = ExportSchedule.clampedCustomInterval(newValue)
                if shouldFollowFrequencyDefault {
                    updated.lookbackDays = ExportSchedule.defaultLookbackDays(
                        for: .custom,
                        customInterval: updated.customInterval,
                        customUnit: updated.customUnit
                    )
                }
                schedulingManager.schedule = updated
            }
        )
    }

    private var customUnitBinding: Binding<ScheduleIntervalUnit> {
        Binding(
            get: { schedulingManager.schedule.customUnit },
            set: { newValue in
                var updated = schedulingManager.schedule
                let previousDefault = ExportSchedule.defaultLookbackDays(
                    for: .custom,
                    customInterval: updated.customInterval,
                    customUnit: updated.customUnit
                )
                let shouldFollowFrequencyDefault = updated.lookbackDays == previousDefault
                updated.customUnit = newValue
                if shouldFollowFrequencyDefault {
                    updated.lookbackDays = ExportSchedule.defaultLookbackDays(
                        for: .custom,
                        customInterval: updated.customInterval,
                        customUnit: updated.customUnit
                    )
                }
                schedulingManager.schedule = updated
            }
        )
    }

    private var customAnchorDateBinding: Binding<Date> {
        Binding(
            get: { schedulingManager.schedule.customAnchorDate },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.customAnchorDate = Calendar.current.startOfDay(for: newValue)
                schedulingManager.schedule = updated
            }
        )
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { schedulingManager.schedule.preferredHour },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.preferredHour = newValue
                schedulingManager.schedule = updated
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { schedulingManager.schedule.preferredMinute },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.preferredMinute = newValue
                schedulingManager.schedule = updated
            }
        )
    }

    private var lookbackDaysBinding: Binding<Int> {
        Binding(
            get: { schedulingManager.schedule.lookbackDays },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.lookbackDays = ExportSchedule.clampedLookbackDays(newValue)
                schedulingManager.schedule = updated
            }
        )
    }

    private var todayRefreshEnabledBinding: Binding<Bool> {
        Binding(
            get: { schedulingManager.schedule.todayRefreshEnabled },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.todayRefreshEnabled = newValue
                schedulingManager.schedule = updated
            }
        )
    }

    private var todayRefreshIntervalBinding: Binding<Int> {
        Binding(
            get: { schedulingManager.schedule.todayRefreshMinutes },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.todayRefreshMinutes = newValue
                schedulingManager.schedule = updated
            }
        )
    }

    private var targetBinding: Binding<ExportTargetSelection> {
        Binding(
            get: { schedulingManager.schedule.target },
            set: { newValue in
                var updated = schedulingManager.schedule
                updated.target = newValue
                schedulingManager.schedule = updated
            }
        )
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                scheduleSections(availableWidth: viewport.size.width)
                    .padding(.horizontal, GlassMetrics.screenMargin)
                    .padding(.top, 12)
                    .padding(.bottom, GlassMetrics.scrollBottomInset)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .tint(palette.accent)
        // The glass shell pushes this screen from Automations, so it keeps the
        // system back button instead of a brand header.
        .navigationTitle(String(localized: "Schedule & history"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            ExportHistoryDetailView(entry: entry, onRetry: retryExport)
                .glassTheme()
        }
        .sheet(isPresented: $showAPIEndpointSettings) {
            APIExportSettingsSheet(settings: apiExportSettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAgentDataGatewaySettings) {
            AgentDataGatewaySettingsSheet(settings: agentDataGatewaySettings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .geistDialog(
            isPresented: $showTodayRefreshInfo,
            title: Text("Today Refresh"),
            message: Text(todayRefreshInfoMessage),
            actions: [.action("Got it", role: .secondary)]
        )
        .overlay {
            if isRetrying {
                RetryProgressOverlay(
                    message: retryStatusMessage,
                    progress: retryProgress
                )
            }
        }
        .geistDialog(
            isPresented: $showRetryError,
            title: Text("Retry Failed"),
            message: Text(retryErrorMessage),
            actions: [.action("OK", role: .secondary)]
        )
    }

    // MARK: - Sections

    private func scheduleSections(availableWidth: CGFloat) -> some View {
        AdaptivePageColumns(availableWidth: availableWidth, spacing: GlassMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                scheduleAutomationCard
#if os(iOS)
                if let profileCoordinator {
                    // Per-profile schedule toggles and cadence editors mutate
                    // profile automation, so the whole card stays inspectable
                    // but is intercepted by the shared lock.
                    GlassProfileScheduleList(coordinator: profileCoordinator)
                        .configurationChangesProtected()
                }
#endif
                if schedulingManager.schedule.isEnabled {
                    scheduledDestinationSection
                        .configurationChangesProtected()
                    scheduleConfigurationCard
                }
            }
        } secondary: {
            exportHistoryCard
        }
    }

    private var scheduleAutomationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Automation"))
                .accessibilityAddTraits(.isHeader)
            GlassPanel {
                automaticExportRow
                    .configurationChangesProtected()

                if !schedulingManager.isSchedulingActive {
                    glassDivider()
                    disabledScheduleRow
                }
            }
        }
    }

    private var scheduleConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Schedule"))
                .accessibilityAddTraits(.isHeader)
            GlassPanel {
                frequencyRow
                    .configurationChangesProtected()
                glassDivider()
                timeRow
                    .configurationChangesProtected()
                glassDivider()
                lookbackRow
                    .configurationChangesProtected()
                glassDivider()
                todayRefreshRow
                glassDivider()
                backgroundGuidanceRow
            }
        }
    }

    /// Glass toggle row: the next run lives in the subtitle, so the old
    /// On/Next/Enabled pills are gone.
    private var automaticExportRow: some View {
        Toggle(isOn: isEnabledBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Scheduled Exports")
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(automaticExportSummary)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(GlassToggleStyle())
        .accessibilityIdentifier(AccessibilityID.Schedule.enableToggle)
        .accessibilityLabel("Automatic export schedule")
        .accessibilityValue(schedulingManager.isSchedulingActive ? String(localized: "Enabled") : String(localized: "Disabled"))
        .accessibilityHint(schedulingManager.isSchedulingActive
            ? String(localized: "Double tap to disable scheduled exports")
            : String(localized: "Double tap to enable scheduled exports"))
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 8)
    }

    private func enableFirstProfileEntry() {
        let entryStore = ScheduledExportEntryStore()
        let profileStore = ExportProfileStore()
        guard let profile = profileStore.profiles.first ?? profileStore.activeProfile else { return }
        if entryStore.entry(profileID: profile.id) == nil {
            let legacy = schedulingManager.schedule
            _ = entryStore.upsert(
                ScheduledExportEntry(
                    profileID: profile.id,
                    isEnabled: true,
                    frequency: .daily,
                    preferredHour: legacy.preferredHour,
                    preferredMinute: legacy.preferredMinute,
                    lookbackDays: 1
                )
            )
        } else {
            _ = entryStore.update(profileID: profile.id) { $0.isEnabled = true }
        }
        schedulingManager.refreshScheduledAutomation()
    }

    private func disableAllSchedules() {
        let entryStore = ScheduledExportEntryStore()
        for entry in entryStore.entries {
            _ = entryStore.update(profileID: entry.profileID) { $0.isEnabled = false }
        }
        if schedulingManager.schedule.isEnabled {
            var updated = schedulingManager.schedule
            updated.isEnabled = false
            schedulingManager.schedule = updated
        }
        schedulingManager.refreshScheduledAutomation()
    }

    private var automaticExportSummary: String {
        if schedulingManager.isSchedulingActive, let nextExport = schedulingManager.getNextExportDescription() {
            return String(localized: "Next export: \(nextExport).")
        }
        return String(localized: "Off. Turn on automation to configure timing, lookback, and reminder behavior.")
    }

    private var disabledScheduleRow: some View {
        guidanceRow(
            icon: "pause.circle",
            title: "Schedule Off",
            message: String(localized: "Scheduled exports are paused. Manual exports remain available from the Export tab."),
            status: String(localized: "Manual Only"),
            tone: .paused
        )
    }

    private var frequencyRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            controlHeader(
                icon: "repeat",
                title: "Frequency",
                message: String(localized: "Choose how often Health.md prepares an export.")
            )

            SchedulingChoicePicker(
                title: "Frequency",
                choices: ScheduleFrequency.allCases.map { SchedulingChoice(value: $0, title: $0.description, titleIsResolved: true) },
                selection: frequencyBinding
            )
            .accessibilityIdentifier(AccessibilityID.Schedule.frequencyPicker)
            .accessibilityLabel("Export frequency")
            .accessibilityValue(schedulingManager.schedule.frequency.description)

            if schedulingManager.schedule.frequency == .custom {
                customFrequencyControls
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, GlassMetrics.panelPadding)
    }

    private var customFrequencyControls: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SchedulingNumberControl(
                title: "Custom frequency interval", value: customIntervalBinding,
                bounds: ExportSchedule.minimumCustomInterval...ExportSchedule.maximumCustomInterval,
                identifier: AccessibilityID.Schedule.customIntervalStepper,
                valueDescription: String(localized: "Every")
            )

            SchedulingValueMenu(
                title: "Custom frequency unit",
                choices: ScheduleIntervalUnit.allCases.map {
                    SchedulingChoice(value: $0, title: ScheduleDisplayCopy.unitChoiceLabel($0), titleIsResolved: true)
                },
                selection: customUnitBinding
            )
            .accessibilityIdentifier(AccessibilityID.Schedule.customUnitPicker)

            SchedulingLabeledControl(title: "Starting", value: Text(schedulingManager.schedule.customAnchorDate, style: .date)) {
                DatePicker(
                    "Starting",
                    selection: customAnchorDateBinding,
                    displayedComponents: .date
                )
                .tint(palette.accent)
                .accessibilityIdentifier(AccessibilityID.Schedule.customStartDatePicker)
                .accessibilityHint("Sets the first day and repeating phase of the custom schedule")
            }

            Text(customCadenceSummary)
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.iconTileRadius, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.iconTileRadius, style: .continuous)
                .strokeBorder(palette.line, lineWidth: 1)
        )
    }

    private var customCadenceSummary: String {
        let interval = schedulingManager.schedule.customInterval
        let unit = schedulingManager.schedule.customUnit
        let start = schedulingManager.schedule.customAnchorDate.formatted(date: .abbreviated, time: .omitted)
        return ScheduleDisplayCopy.cadenceStartingSummary(count: interval, unit: unit, starting: start)
    }

    private enum DayPeriod: String { case am = "AM", pm = "PM" }

    private var displayHour12: Int {
        let h = schedulingManager.schedule.preferredHour
        if h == 0 { return 12 }
        if h > 12 { return h - 12 }
        return h
    }

    private var displayPeriod: DayPeriod {
        schedulingManager.schedule.preferredHour < 12 ? .am : .pm
    }

    private func setHour12(_ hour12: Int, period: DayPeriod) {
        let hour24: Int
        switch period {
        case .am:
            hour24 = (hour12 == 12) ? 0 : hour12
        case .pm:
            hour24 = (hour12 == 12) ? 12 : hour12 + 12
        }
        hourBinding.wrappedValue = hour24
    }

    private var timeRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            controlHeader(
                icon: "clock",
                title: "Preferred Time",
                message: String(localized: "iOS uses this as the target time for notifications and background scheduling.")
            )

            SchedulingTimeControls(
                hour: Binding(get: { displayHour12 }, set: { setHour12($0, period: displayPeriod) }),
                minute: minuteBinding,
                period: Binding(
                    get: { displayPeriod.rawValue },
                    set: { if let period = DayPeriod(rawValue: $0) { setHour12(displayHour12, period: period) } }
                ),
                hourIdentifier: AccessibilityID.Schedule.hourPicker,
                minuteIdentifier: AccessibilityID.Schedule.minutePicker,
                periodIdentifier: AccessibilityID.Schedule.periodPicker
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, GlassMetrics.panelPadding)
    }

    private var preferredTimeText: String {
        String(format: "%d:%02d %@", displayHour12, schedulingManager.schedule.preferredMinute, displayPeriod.rawValue)
    }

    private var lookbackDayLabel: String {
        let days = schedulingManager.schedule.lookbackDays
        return days == 1
            ? String(localized: "1 day")
            : String(localized: "\(days) days")
    }

    private var lookbackDescription: String {
        let days = schedulingManager.schedule.lookbackDays
        return days == 1
            ? String(localized: "Each run exports the past 1 day ending with yesterday.")
            : String(localized: "Each run exports the past \(days) days ending with yesterday.")
    }

    private var lookbackRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            controlHeader(icon: "calendar.badge.minus", title: "Lookback Window", message: lookbackDescription)
            SchedulingNumberControl(
                title: "Lookback window", value: lookbackDaysBinding,
                bounds: ExportSchedule.minimumLookbackDays...ExportSchedule.maximumLookbackDays,
                identifier: "schedule.lookback", valueDescription: lookbackDayLabel
            )
            .accessibilityHint("Adjusts how many past days each scheduled export includes")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, GlassMetrics.panelPadding)
    }

    private var todayRefreshRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Today Refresh")
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    todayRefreshInfoButton
                    Spacer(minLength: 0)
                    if schedulingManager.schedule.todayRefreshEnabled {
                        StatusBadge(
                            title: ExportSchedule.todayRefreshLabel(schedulingManager.schedule.todayRefreshMinutes),
                            status: .inProgress
                        )
                    }
                }

                Toggle(isOn: todayRefreshEnabledBinding) {
                    Text("Refresh today's export")
                        .glassFont(.body)
                        .foregroundStyle(palette.sec)
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .toggleStyle(GlassToggleStyle())
                    .configurationChangesProtected()
                    .accessibilityIdentifier("schedule.todayRefresh.toggle")
                    .accessibilityLabel("Today Refresh")
                    .accessibilityValue(schedulingManager.schedule.todayRefreshEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                    .accessibilityHint(schedulingManager.schedule.todayRefreshEnabled
                        ? String(localized: "Double tap to disable Today Refresh")
                        : String(localized: "Double tap to enable Today Refresh"))
            }
            .accessibilityElement(children: .contain)

            if schedulingManager.schedule.todayRefreshEnabled {
                SchedulingChoicePicker(
                    title: "Today Refresh interval",
                    choices: ExportSchedule.todayRefreshMinuteOptions.map {
                        SchedulingChoice(value: $0, title: ExportSchedule.todayRefreshLabel($0), titleIsResolved: true)
                    },
                    selection: todayRefreshIntervalBinding
                )
                .accessibilityIdentifier("schedule.todayRefresh.interval")
                .configurationChangesProtected()

                if schedulingManager.schedule.target == .apiEndpoint {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("API Refresh Behavior")
                            .glassFont(.body)
                            .foregroundStyle(palette.text)

                        Text("Each refresh fetches today's data again and sends a complete JSON snapshot. The endpoint should replace or upsert its previous snapshot for the date.")
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("When File Exists")
                                .glassFont(.body)
                                .foregroundStyle(palette.text)

                            Text(advancedSettings.writeMode.description)
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SchedulingChoicePicker(
                            title: "Write Mode",
                            choices: WriteMode.allCases.map { SchedulingChoice(value: $0, title: $0.rawValue) },
                            selection: $advancedSettings.writeMode
                        )
                        .accessibilityLabel("File handling mode")
                        .accessibilityValue(advancedSettings.writeMode.rawValue)
                        .configurationChangesProtected()
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, GlassMetrics.panelPadding)
    }

    private var todayRefreshInfoButton: some View {
        SchedulingInfoButton { showTodayRefreshInfo = true }
    }

    private var todayRefreshInfoMessage: String {
        let interval = schedulingManager.schedule.todayRefreshMinutes
        let refreshBehavior: String
        if schedulingManager.schedule.target == .apiEndpoint {
            refreshBehavior = String(localized: "For API Endpoint exports, each run fetches the day again and sends a complete replacement snapshot. The endpoint should upsert the latest snapshot by date.")
        } else {
            refreshBehavior = String(localized: "For file exports, Update or Overwrite replaces the current JSON snapshot with the latest data.")
        }
        return String(localized: """
        Today Refresh rewrites today's export while the day is still in progress.

        \(refreshBehavior)

        \(ExportSchedule.todayRefreshLabel(interval)) is relative to your Preferred Time (\(preferredTimeText)). Health.md targets \(preferredTimeText), then repeats at that interval until midnight. If you enable it after a target time has passed, the next future slot is used.

        Automatic background exports depend on iOS. If Health.md needs your attention, unlock your device and tap the notification to run the pending export.
        """)
    }

    private var scheduledDestinationSection: some View {
        ExportTargetSectionView(
            title: String(localized: "Export Destination"),
            selection: targetBinding,
            localSubtitle: scheduledLocalTargetSubtitle,
            macSubtitle: scheduledMacTargetSubtitle,
            apiSubtitle: scheduledAPITargetSubtitle,
            gatewaySubtitle: scheduledAgentDataGatewayTargetSubtitle,
            canExportToConnectedMac: canScheduleToConnectedMac,
            // See the export tab: prompt from current destination usability, not
            // retained-selection metadata, so unavailable folders still open the picker.
            shouldPromptForLocalFolder: !vaultManager.isVaultDestinationUsable,
            localAccessibilityIdentifier: AccessibilityID.Schedule.localTargetOption,
            macAccessibilityIdentifier: AccessibilityID.Schedule.macTargetOption,
            apiAccessibilityIdentifier: AccessibilityID.Schedule.apiTargetOption,
            gatewayAccessibilityIdentifier: AccessibilityID.Schedule.agentDataGatewayTargetOption,
            onRequestFolderPicker: { showFolderPicker = true },
            onOpenAPISettings: { showAPIEndpointSettings = true },
            onOpenGatewaySettings: { showAgentDataGatewaySettings = true }
        )
    }

    private var scheduledAgentDataGatewayTargetSubtitle: String {
        let settings = AgentDataGatewaySettings()
        if settings.isConfigured {
            return String(localized: "Scheduled exports upload artifacts to \(settings.displayName).")
        }
        return String(localized: "Scheduled exports upload artifacts to your Agent Data gateway.")
    }

    private var scheduledLocalTargetSubtitle: String {
        if vaultManager.requiresVaultReselection {
            return String(localized: "Saved folder changed. Review it in Files, then re-select the intended folder.")
        }
        if vaultManager.vaultURL != nil {
            return String(localized: "Scheduled exports write to \(vaultManager.vaultName) on this iPhone.")
        }
        if vaultManager.hasSavedVaultFolder {
            return String(localized: "Saved folder unavailable. Reconnect it in Files or tap to re-select.")
        }
        return String(localized: "Local iPhone folder. Tap to choose a folder.")
    }

    private var scheduledMacTargetSubtitle: String {
        if canScheduleToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return String(localized: "Ready on Mac: \(path). Keep the Mac awake with Health.md open at schedule time.")
            }
            if let name = syncService.macDestinationStatus?.destinationDisplayName {
                return String(localized: "Ready on Mac: \(name). Keep the Mac awake with Health.md open at schedule time.")
            }
            return String(localized: "Ready now. Keep the Mac awake with Health.md open at schedule time.")
        }
        return scheduledMacTargetUnavailableMessage
    }

    private var scheduledAPITargetSubtitle: String {
        if apiExportSettings.isConfigured {
            return String(localized: "Scheduled JSON exports POST to \(apiExportSettings.displayName). Tap to edit.")
        }
        return String(localized: "Send scheduled JSON exports to your HTTP(S) endpoint. Tap to configure.")
    }

    private var canScheduleToConnectedMac: Bool {
        syncService.canExportToConnectedMac(requiring: advancedSettings)
    }

    private var scheduledMacTargetUnavailableMessage: String {
        guard syncService.connectionState == .connected else {
            return String(localized: "No Mac connected. Open Health.md on your Mac before choosing this target.")
        }
        guard let capabilities = syncService.remoteCapabilities else {
            return syncService.macExportReadinessMessage(requiring: advancedSettings)
        }
        guard capabilities.platform == .macOS,
              capabilities.isCompatibleWithMacExportJobs else {
            return String(localized: "Incompatible Mac. Update Health.md on Mac.")
        }
        if syncService.canExportToConnectedMac,
           !syncService.canExportToConnectedMac(requiring: advancedSettings) {
            return syncService.macExportReadinessMessage(requiring: advancedSettings)
        }
        guard let status = syncService.macDestinationStatus else {
            return syncService.macExportReadinessMessage(requiring: advancedSettings)
        }
        if status.activeJobID != nil {
            return String(localized: "Mac busy. Wait for the current export to finish.")
        }
        if !status.destinationFolderSelected {
            return String(localized: "No folder selected. Choose a folder on Mac.")
        }
        if !status.folderAccessHealthy {
            let destination = status.destinationPathForDisplay
                ?? status.destinationDisplayName
                ?? String(localized: "the saved Mac folder")
            return String(localized: "Saved Mac destination \(destination) needs access. Re-select it on Mac.")
        }
        return syncService.macExportReadinessMessage(requiring: advancedSettings)
    }

    private var backgroundGuidanceRow: some View {
        guidanceRow(
            icon: "bell.badge",
            title: "Background Timing",
            message: String(localized: "Your iPhone must be unlocked when Health.md reads Health data. If data is locked, tap the notification to run the export."),
            status: String(localized: "iOS Managed"),
            tone: .partial
        )
    }

    static let historyPageSize = 10

    private var visibleHistory: [ExportHistoryEntry] {
        Array(exportHistory.history.prefix(visibleHistoryCount))
    }

    private var exportHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            historyHeading

            GlassPanel {
                if exportHistory.history.isEmpty {
                    emptyHistoryState
                } else {
                    ForEach(Array(visibleHistory.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            glassDivider()
                        }
                        Button {
                            selectedEntry = entry
                        } label: {
                            ExportHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }

                    let remaining = exportHistory.history.count - visibleHistory.count
                    if remaining > 0 {
                        glassDivider()
                        Button {
                            visibleHistoryCount += Self.historyPageSize
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(remaining) more entries…")
                                    .glassFont(.caption)
                                    .foregroundStyle(palette.accent)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.muted)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, GlassMetrics.panelPadding)
                            .frame(minHeight: GlassMetrics.rowMinHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Clearing is immediate, as before; the configuration lock still intercepts it.
    private var historyHeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Export History"))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !exportHistory.history.isEmpty {
                Button {
                    configurationProtection.performConfigurationChange {
                        exportHistory.clearHistory()
                        visibleHistoryCount = Self.historyPageSize
                    }
                } label: {
                    Text("Clear History")
                        .glassFont(.caption)
                        .foregroundStyle(palette.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: GlassMetrics.touchTarget, minHeight: GlassMetrics.touchTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear export history")
                .accessibilityIdentifier("schedule.history.clear")
            }
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("No Exports Yet")
                    .glassFont(.navTitle)
                    .foregroundStyle(palette.text)

                Text("Run a manual export or turn on automation to start building history.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, GlassMetrics.panelPadding)
        .accessibilityElement(children: .combine)
    }

    private func glassDivider() -> some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: 1)
            .padding(.leading, GlassMetrics.panelPadding)
            .accessibilityHidden(true)
    }

    /// Titles are controlled keys; messages are resolved prose, never lookup keys.
    /// The icon argument is kept for call-site readability; glass rows are text-only.
    private func controlHeader(icon: String, title: LocalizedStringKey, message: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .glassFont(.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Callers resolve controlled copy; interpolated values are never looked up.
    private func guidanceRow(
        icon: String,
        title: LocalizedStringKey,
        message: String,
        status label: String,
        tone: CoverageStatus
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            controlHeader(icon: icon, title: title, message: message)
            Spacer(minLength: 8)
            StatusBadge(title: label, status: tone)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, GlassMetrics.panelPadding)
        .accessibilityElement(children: .combine)
    }

    private func trackScheduleEnableAttempt() {
    }

    // MARK: - Retry Export

    private func retryExport(_ entry: ExportHistoryEntry) {
        isRetrying = true
        retryProgress = 0.0
        retryStatusMessage = String(localized: "Preparing…")

        Task {
            await HealthKitQueryExecutionController.withController {
                await performRetryExport(entry)
            }
        }
    }

    private func performRetryExport(_ entry: ExportHistoryEntry) async {
        defer {
            Task { @MainActor in
                isRetrying = false
                retryProgress = 0.0
                retryStatusMessage = ""
            }
        }

        // Determine which dates to retry
        let datesToExport: [Date]
        if !entry.failedDateDetails.isEmpty {
            // Retry only the failed dates
            datesToExport = entry.failedDateDetails.map { $0.date }
        } else {
            // Retry all dates in the range
            var dates: [Date] = []
            var currentDate = Calendar.current.startOfDay(for: entry.dateRangeStart)
            let endDate = Calendar.current.startOfDay(for: entry.dateRangeEnd)

            while currentDate <= endDate {
                dates.append(currentDate)
                guard let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) else {
                    break
                }
                currentDate = nextDate
            }
            datesToExport = dates
        }

        guard !datesToExport.isEmpty else {
            await MainActor.run {
                retryErrorMessage = String(localized: "No dates to retry")
                showRetryError = true
            }
            return
        }

        guard purchaseManager.canExport else {
            await MainActor.run {
                retryErrorMessage = String(localized: "Retrying this export requires an active trial or subscription, or Lifetime access.")
                showRetryError = true
            }
            return
        }

        vaultManager.refreshVaultAccess()
        if vaultManager.requiresVaultReselection {
            await MainActor.run {
                retryErrorMessage = VaultManager.destinationChangedMessage
                showRetryError = true
            }
            return
        }
        guard vaultManager.hasVaultAccess else {
            await MainActor.run {
                retryErrorMessage = vaultManager.hasSavedVaultFolder
                    ? ExportFailureReason.accessDenied.detailedDescription
                    : ExportFailureReason.noVaultSelected.detailedDescription
                showRetryError = true
            }
            return
        }

        guard let accessLease = vaultManager.beginVaultAccess() else {
            await MainActor.run {
                retryErrorMessage = ExportFailureReason.accessDenied.detailedDescription
                showRetryError = true
            }
            return
        }
        defer { accessLease.stop() }

        let totalDays = datesToExport.count
        var successCount = 0
        var looseAggregateFileCount = 0
        var individualEntryFileCount = 0
        var dataDictionaryFileCount = 0
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (index, date) in datesToExport.enumerated() {
            await MainActor.run {
                retryStatusMessage = String(localized: "Preparing \(dateFormatter.string(from: date))… (\(index)/\(totalDays) complete)")
                retryProgress = Double(index) / Double(totalDays)
            }

            let healthData: HealthData
            do {
                healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    detailPolicy: advancedSettings.effectiveDetailPolicy,
                    metricSelection: advancedSettings.metricSelection
                )
            } catch {
                failedDateDetails.append(
                    ScheduleRetryExportPolicy.failedHealthKitDetail(for: date, error: error)
                )
                continue
            }

            if !healthData.filtered(by: advancedSettings.metricSelection).hasAnyData {
                failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                continue
            }

            do {
                let writeResult = try vaultManager.exportHealthDataResult(
                    healthData,
                    for: date,
                    settings: advancedSettings,
                    writeDataDictionary: ScheduleRetryExportPolicy.shouldWriteDataDictionary(
                        currentFileCount: dataDictionaryFileCount
                    )
                )
                partialFailures.append(contentsOf: healthData.partialFailures)
                partialFailures.append(contentsOf: writeResult.individualEntryCoverageGaps)
                looseAggregateFileCount += writeResult.aggregateFileCount
                individualEntryFileCount += writeResult.individualEntryFileCount
                dataDictionaryFileCount += writeResult.dataDictionaryFileCount
                dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                dailyNoteSkipCount += writeResult.dailyNoteSkippedCount

                if advancedSettings.dailyNotesOnlyModeEnabled,
                   let failedDetail = ScheduleRetryExportPolicy.failedDailyNoteDetail(
                    for: date,
                    result: writeResult.dailyNoteResult
                   ) {
                    failedDateDetails.append(failedDetail)
                } else {
                    successCount += 1
                }
            } catch {
                failedDateDetails.append(
                    ScheduleRetryExportPolicy.failedWriteDetail(for: date, error: error)
                )
            }
        }

        await MainActor.run {
            retryProgress = 1.0

            if successCount > 0 {
                purchaseManager.recordExportUse()
            }

            // Record the result
            let startDate = datesToExport.min() ?? entry.dateRangeStart
            let endDate = datesToExport.max() ?? entry.dateRangeEnd

            let generatedFileCount = looseAggregateFileCount
                + individualEntryFileCount
                + dataDictionaryFileCount
            let outputBreakdown = ExportHistoryOutputBreakdown(
                requestedDataDayCount: totalDays,
                successfulDataDayCount: successCount,
                looseAggregateFileCount: looseAggregateFileCount,
                individualEntryFileCount: individualEntryFileCount,
                dataDictionaryFileCount: dataDictionaryFileCount,
                isFileCategoryBreakdownComplete: true
            )
            let retryResult = ExportOrchestrator.ExportResult(
                successCount: successCount,
                totalCount: totalDays,
                failedDateDetails: failedDateDetails,
                partialFailures: partialFailures,
                formatsPerDate: 0,
                looseAggregateFileCount: looseAggregateFileCount,
                individualEntryFileCount: individualEntryFileCount,
                dataDictionaryFileCount: dataDictionaryFileCount,
                authoritativeFileCount: generatedFileCount,
                isFileCategoryBreakdownComplete: true,
                dailyNoteUpdateCount: dailyNoteUpdateCount,
                dailyNoteSkipCount: dailyNoteSkipCount,
                completedDates: datesToExport.filter { date in
                    !failedDateDetails.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
                }
            )

            if successCount > 0 || dailyNoteSkipCount > 0 {
                retryStatusMessage = retryResult.localizedGeneratedFileAndDataDayDescription
                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails,
                    targetLabel: "iPhone: \(vaultManager.vaultName)",
                    exportTarget: .localIPhoneFolder,
                    fileCount: generatedFileCount,
                    outputBreakdown: outputBreakdown,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    partialFailures: partialFailures
                )
            } else {
                let primaryReason = failedDateDetails.first?.reason ?? .unknown
                retryErrorMessage = primaryReason.detailedDescription
                showRetryError = true

                exportHistory.recordFailure(
                    source: .manual,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    reason: primaryReason,
                    successCount: 0,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails,
                    targetLabel: "iPhone: \(vaultManager.vaultName)",
                    exportTarget: .localIPhoneFolder,
                    fileCount: generatedFileCount,
                    outputBreakdown: outputBreakdown,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    partialFailures: partialFailures
                )
            }
        }
    }
}

#if os(iOS)
// MARK: - Profile Schedules

/// Glass layout of the per-profile schedule list (the former `ProfileScheduleSection`
/// card). Same stores, toggles, editor save path, pending-recovery discard and
/// accessibility identifiers; editing opens the glass `GlassScheduleSheet`, as the
/// Automations detail does.
private struct GlassProfileScheduleList: View {
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    @Environment(\.glassPalette) private var palette
    @State private var editingProfile: ExportProfile?
    @State private var recoveryProfile: ExportProfile?
    @State private var showDiscardConfirmation = false
    @State private var isDiscardingRecovery = false
    @State private var showRecoveryError = false

    init(coordinator: ExportProfileCoordinator) {
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Profile Schedules"))
                .accessibilityAddTraits(.isHeader)

            GlassPanel {
                ForEach(Array(profileStore.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.line)
                            .frame(height: 1)
                            .padding(.leading, GlassMetrics.panelPadding)
                            .accessibilityHidden(true)
                    }
                    profileRow(profile)
                }
            }

            if !entryStore.entries.contains(where: \.isEnabled) {
                Text(String(
                    localized: "No profile schedules enabled.",
                    comment: "Profile schedule footer when nothing is enabled"
                ))
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }
        }
        .sheet(item: $editingProfile) { profile in
            GlassScheduleSheet(
                profile: profile,
                entry: entryStore.entry(profileID: profile.id),
                entryStore: entryStore
            ) { entry in
                _ = entryStore.upsert(entry)
                schedulingManager.refreshScheduledAutomation()
            }
            .glassTheme()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Discard Pending Recovery?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Pending Recovery", role: .destructive) {
                guard let profile = recoveryProfile else { return }
                // Protection may have been enabled while the confirmation was open.
                configurationProtection.performConfigurationChange {
                    isDiscardingRecovery = true
                    defer { isDiscardingRecovery = false }
                    do {
                        try schedulingManager.discardPendingRecovery(profileID: profile.id)
                        _ = entryStore.allEntries()
                    } catch {
                        showRecoveryError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let profile = recoveryProfile {
                Text("Discard unresolved scheduled exports for \(profile.name)? Your profile, API credentials, export history, completed files and completed-run progress stay unchanged. No export starts now; an enabled schedule waits for its next ordinary occurrence.")
            }
        }
        .alert("Unable to discard pending recovery", isPresented: $showRecoveryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pending recovery could not be fully cleared. Please try again. Your profile and credentials were not removed.")
        }
    }

    private func profileRow(_ profile: ExportProfile) -> some View {
        let entry = entryStore.entry(profileID: profile.id)
        let identifier = "schedule.profile.\(profile.id.uuidString)"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(identifier + ".name")
                    Text(cadenceSummary(for: entry))
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(identifier + ".summary")
                }
                Spacer(minLength: 8)
                Toggle(isOn: Binding(
                    get: { entry?.isEnabled ?? false },
                    set: { setEntryEnabled($0, for: profile, existing: entry) }
                )) {
                    EmptyView()
                }
                .toggleStyle(GlassToggleStyle())
                .fixedSize()
                .accessibilityLabel(Text("Schedule \(profile.name)"))
                .accessibilityIdentifier(identifier + ".enabled")
            }

            HStack(spacing: 20) {
                Button {
                    editingProfile = profile
                } label: {
                    Text("Edit Schedule")
                        .glassFont(.caption)
                        .foregroundStyle(palette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: GlassMetrics.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Edit schedule for \(profile.name)"))
                .accessibilityIdentifier(identifier + ".edit")

                if schedulingManager.pendingRecoveryProfileIDs.contains(profile.id), entry != nil {
                    Button {
                        configurationProtection.performConfigurationChange {
                            recoveryProfile = profile
                            showDiscardConfirmation = true
                        }
                    } label: {
                        Text("Discard Pending Recovery")
                            .glassFont(.caption)
                            .foregroundStyle(palette.coral)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: GlassMetrics.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(identifier + ".discardRecovery")
                    .accessibilityLabel(Text("Discard pending recovery for \(profile.name)"))
                    .accessibilityHint("Keeps credentials, history and completed exports. Requires confirmation.")
                    .disabled(isDiscardingRecovery)
                }
            }
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func setEntryEnabled(
        _ isEnabled: Bool,
        for profile: ExportProfile,
        existing entry: ScheduledExportEntry?
    ) {
        if entry != nil {
            _ = entryStore.update(profileID: profile.id) { $0.isEnabled = isEnabled }
        } else {
            // Seed new entries from the legacy schedule's preferred time so a
            // user migrating from single-schedule mode keeps their routine.
            let legacy = schedulingManager.schedule
            _ = entryStore.upsert(ScheduledExportEntry(
                profileID: profile.id,
                isEnabled: isEnabled,
                frequency: .daily,
                preferredHour: legacy.preferredHour,
                preferredMinute: legacy.preferredMinute,
                lookbackDays: 1
            ))
        }
        if isEnabled {
            Task { @MainActor in
                _ = await schedulingManager.requestNotificationPermissions()
            }
        }
        schedulingManager.refreshScheduledAutomation()
    }

    private func cadenceSummary(for entry: ScheduledExportEntry?) -> String {
        guard let entry, entry.isEnabled else {
            return String(localized: "Not scheduled. Tap to configure.", comment: "Profile schedule row summary when off")
        }

        let time = String(
            format: "%d:%02d",
            locale: Locale.current,
            entry.preferredHour,
            entry.preferredMinute
        )
        switch entry.frequency {
        case .daily:
            return String(localized: "Daily at \(time)", comment: "Profile schedule cadence summary")
        case .weekly:
            // ISO 1 = Monday … 7 = Sunday; veryShortWeekdaySymbols starts Sunday.
            let weekday = Calendar.current.veryShortWeekdaySymbols[entry.weekday % 7]
            return String(localized: "Weekly on \(weekday) at \(time)", comment: "Profile schedule cadence summary")
        case .custom:
            return ScheduleDisplayCopy.cadence(count: entry.customInterval, unit: entry.customUnit, at: time)
        }
    }
}
#endif

// MARK: - Retry Progress Overlay

struct RetryProgressOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glassPalette) private var palette
    let message: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(palette.track, lineWidth: 3)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(reduceMotion ? .zero : .degrees(-90))
                        .animation(reduceMotion ? nil : AnimationTimings.standard, value: progress)

                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("Retrying Export")
                        .glassFont(.navTitle)
                        .foregroundStyle(palette.text)

                    Text(message)
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.sec)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: progress)
                    .tint(palette.accent)
                    .frame(width: 200)
                    .accessibilityHidden(true)

                StatusBadge(title: String(localized: "\(Int((progress * 100).rounded()))% Complete"), status: .inProgress)
                    .accessibilityHidden(true)
            }
            .padding(24)
            .glassSurface(cornerRadius: GlassMetrics.dialogRadius, style: .strong)
            .padding(.horizontal, 28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Retrying export")
            .accessibilityValue("\(message), \(Int(progress * 100)) percent complete")
        }
    }
}

// MARK: - Export History Row

/// HistoryG row: when it ran, a short muted reason, a status capsule and a
/// chevron to the details. The full failure text stays in the details sheet
/// and in the VoiceOver label.
struct ExportHistoryRow: View {
    let entry: ExportHistoryEntry

    @Environment(\.glassPalette) private var palette

    private var badgeStatus: CoverageStatus {
        switch entry.presentationStatus {
        case .success: return .complete
        case .partialSuccess: return .partial
        case .failed: return .missing
        }
    }

    /// Failures lead with the plain reason; successes and partials keep the
    /// file/day summary.
    private var detailLine: String {
        if entry.presentationStatus == .failed, let reason = entry.failureReasonForDisplay {
            return reason.shortDescription
        }
        return entry.summaryDescription
    }

    private var metadataLine: String {
        var parts = [entry.sourceLabelForDisplay]
        if let profileName = entry.profileName, !profileName.isEmpty {
            parts.append(profileName)
        }
        if let targetLabel = entry.targetLabel, !targetLabel.isEmpty {
            parts.append(targetLabel)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(formatTimestamp(entry.timestamp))
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)

                Text(detailLine)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.sec)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metadataLine)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusBadge(title: entry.localizedShortStatusDescription, status: badgeStatus)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 12)
        .frame(minHeight: GlassMetrics.rowWithSubtitleMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(accessibilityMetadataDescription)
        .accessibilityHint("Double tap to view details")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityDescription: String {
        let status = "\(entry.localizedStatusDescription): \(entry.summaryDescription)"
        guard let message = entry.failureListMessage else { return status }
        return "\(status). \(message)"
    }

    private var accessibilityMetadataDescription: String {
        var parts = [entry.sourceLabelForDisplay, formatTimestamp(entry.timestamp)]
        if let profileName = entry.profileName, !profileName.isEmpty {
            parts.append("\(String(localized: "Export Profile")): \(profileName)")
        }
        if let targetLabel = entry.targetLabel, !targetLabel.isEmpty {
            let title = entry.exportTarget == .localIPhoneFolder
                ? String(localized: "Export Folder")
                : String(localized: "Target")
            parts.append("\(title): \(targetLabel)")
        }
        return parts.joined(separator: ", ")
    }

    private func formatTimestamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

// MARK: - Export History Detail View

struct ExportHistoryDetailView: View {
    let entry: ExportHistoryEntry
    let onRetry: ((ExportHistoryEntry) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassPalette) private var palette

    init(entry: ExportHistoryEntry, onRetry: ((ExportHistoryEntry) -> Void)? = nil) {
        self.entry = entry
        self.onRetry = onRetry
    }

    private var canRetry: Bool {
        ScheduleRetryExportPolicy.canRetry(entry)
    }

    private var statusColor: Color {
        switch entry.presentationStatus {
        case .success: return palette.ok
        case .partialSuccess: return palette.accent
        case .failed: return palette.coral
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    // Retry Section (top placement: keep the primary recovery
                    // action reachable without scrolling through long failure lists)
                    if canRetry, let onRetry = onRetry {
                        Section {
                            Button(action: {
                                dismiss()
                                onRetry(entry)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry Export")
                                }
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(palette.accent)
                            }
                            .accessibilityLabel("Retry export")
                            .accessibilityHint(entry.failedDateDetails.isEmpty
                                ? "Double tap to retry export for all dates"
                                : "Double tap to retry \(entry.failedDateDetails.count) failed dates")
                        } footer: {
                            Text(entry.failedDateDetails.isEmpty
                                ? "Re-export all dates from \(formatDateRange(entry.dateRangeStart, entry.dateRangeEnd))"
                                : "Re-export \(entry.failedDateDetails.count) failed date\(entry.failedDateDetails.count == 1 ? "" : "s")"
                            )
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(palette.muted)
                        }
                    }

                    // Status Section
                    Section {
                        HStack {
                            Text("Status")
                                .foregroundStyle(palette.muted)
                            Spacer()
                            Text(entry.localizedShortStatusDescription)
                                .foregroundStyle(statusColor)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Source")
                                .foregroundStyle(palette.muted)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: entry.sourceIconForDisplay)
                                Text(entry.sourceLabelForDisplay)
                            }
                            .foregroundStyle(palette.text)
                        }

                        if let profileName = entry.profileName, !profileName.isEmpty {
                            historyValueRow("Export Profile", value: profileName)
                        }

                        if let targetLabel = entry.targetLabel, !targetLabel.isEmpty {
                            if entry.exportTarget == .localIPhoneFolder {
                                historyValueRow("Export Folder", value: targetLabel)
                            } else {
                                historyValueRow("Target", value: targetLabel)
                            }
                        }

                        HStack {
                            Text("Time")
                                .foregroundStyle(palette.muted)
                            Spacer()
                            Text(formatFullTimestamp(entry.timestamp))
                                .foregroundStyle(palette.text)
                        }
                    } header: {
                        Text("Overview")
                            .glassFont(.caption)
                            .foregroundStyle(palette.muted)
                    }

                    // Export Details Section
                    Section {
                        HStack {
                            Text("Date Range")
                                .foregroundStyle(palette.muted)
                            Spacer()
                            Text(formatDateRange(entry.dateRangeStart, entry.dateRangeEnd))
                                .foregroundStyle(palette.text)
                        }

                        HStack {
                            Text(entry.resultCountLabel)
                                .foregroundStyle(palette.muted)
                            Spacer()
                            Text(entry.resultCountDescription)
                                .foregroundStyle(palette.text)
                        }
                    } header: {
                        Text("Details")
                            .glassFont(.caption)
                            .foregroundStyle(palette.muted)
                    }

                    if let details = entry.operationDetails {
                        Section {
                            historyValueRow("Operation", value: operationLabel(details.kind))
                            historyValueRow("Job ID", value: details.requestID.uuidString.lowercased(), monospaced: true)
                            historyValueRow("Requested Dates", value: dateSelectionLabel(details.dateSelection))
                            historyValueRow("Settings", value: settingsPolicyLabel(details.settingsPolicy))

                            if let profile = details.profile {
                                historyValueRow("Profile", value: profileLabel(profile))
                            }
                            if let detailLevel = details.detailLevel {
                                historyValueRow("Detail", value: detailLevelLabel(detailLevel))
                            }
                        } header: {
                            Text("CLI Request")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        } footer: {
                            Text("History stores request scope and counts only. Exported health values are not saved in this history.")
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.muted)
                        }

                        Section {
                            historyValueRow(
                                "Data Sent",
                                value: ByteCountFormatter.string(
                                    fromByteCount: details.transferredBytes,
                                    countStyle: .file
                                )
                            )
                            historyValueRow("Transfer Parts", value: "\(details.partitionCount)")

                            if let recordCount = details.recordCount {
                                historyValueRow("Records", value: "\(recordCount)")
                            }
                            if let sampleCount = details.sampleCount {
                                historyValueRow("HealthKit Samples", value: "\(sampleCount)")
                            }
                            if details.warningDayCount > 0 {
                                historyValueRow("Days With Warnings", value: "\(details.warningDayCount)")
                            }
                            if details.failedDayCount > 0 {
                                historyValueRow("Failed or Missing Days", value: "\(details.failedDayCount)")
                            }
                            if details.integrityWarningCount > 0 {
                                historyValueRow("Integrity Warnings", value: "\(details.integrityWarningCount)")
                            }
                            if details.partialFailureCount > 0 {
                                historyValueRow("Partial Metric Failures", value: "\(details.partialFailureCount)")
                            }
                        } header: {
                            Text("Transfer Summary")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        }

                        if details.metricIDs.isEmpty == false ||
                            details.categoryIDs.isEmpty == false ||
                            details.sourceIDs.isEmpty == false ||
                            details.objectPaths.isEmpty == false ||
                            details.fieldPointers.isEmpty == false {
                            Section {
                                if !details.metricIDs.isEmpty {
                                    historyScopeGroup(
                                        title: "Metrics",
                                        values: details.metricIDs.map(metricDisplayName)
                                    )
                                }
                                if !details.categoryIDs.isEmpty {
                                    historyScopeGroup(
                                        title: "Categories",
                                        values: details.categoryIDs.map(displayToken)
                                    )
                                }
                                if !details.sourceIDs.isEmpty {
                                    historyScopeGroup(
                                        title: "Sources",
                                        values: details.sourceIDs.map(displayToken)
                                    )
                                }
                                if !details.objectPaths.isEmpty {
                                    historyScopeGroup(title: "Objects", values: details.objectPaths, monospaced: true)
                                }
                                if !details.fieldPointers.isEmpty {
                                    historyScopeGroup(title: "Fields", values: details.fieldPointers, monospaced: true)
                                }
                            } header: {
                                Text("Request Scope")
                                    .glassFont(.caption)
                                    .foregroundStyle(palette.muted)
                            }
                        }
                    } else if entry.isCLIRawDelivery {
                        Section {
                            historyValueRow("Operation", value: String(localized: "Raw data export"))
                            if entry.targetLabel == "Direct CLI raw response" {
                                historyValueRow(
                                    "Job ID",
                                    value: entry.id.uuidString.lowercased(),
                                    monospaced: true
                                )
                            }
                        } header: {
                            Text("CLI Request")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        } footer: {
                            Text("This export predates detailed CLI history. New CLI exports include request scope and transfer counts here.")
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.muted)
                        }
                    }

                    // Failure explanation and next step (if applicable)
                    if let reason = entry.failureReasonForDisplay {
                        Section {
                            VStack(alignment: .leading, spacing: Spacing.s2) {
                                Label(reason.shortDescription, systemImage: "exclamationmark.octagon.fill")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(statusColor)

                                Text(reason.detailedDescription)
                                    .font(Typography.body())
                                    .foregroundStyle(palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, Spacing.s1)
                        } header: {
                            Text(entry.isPartialSuccess ? "Why some dates did not export" : "Why it failed")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        }

                        Section {
                            Label {
                                Text(reason.recoverySuggestion)
                                    .font(Typography.body())
                                    .foregroundStyle(palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundStyle(palette.accent)
                            }
                            .padding(.vertical, Spacing.s1)
                        } header: {
                            Text("What to do")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        }
                    }

                    if !entry.failureDiagnosticDetails.isEmpty {
                        Section {
                            ForEach(entry.failureDiagnosticDetails, id: \.self) { details in
                                Text(details)
                                    .font(Typography.bodyMono())
                                    .foregroundStyle(palette.muted)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } header: {
                            Text("Technical details")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        } footer: {
                            Text("If the suggested fix does not work, include this message in your bug report after removing any private folder or server information.")
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.muted)
                        }
                    }

                    if !entry.partialFailures.isEmpty {
                        Section {
                            ForEach(Array(entry.partialFailures.enumerated()), id: \.offset) { _, failure in
                                HStack(alignment: .top) {
                                    Image(systemName: failure.isInformational == true
                                        ? "info.circle"
                                        : "exclamationmark.triangle.fill")
                                        .foregroundStyle(failure.isInformational == true
                                            ? palette.muted
                                            : palette.coral)
                                    Text(failure.summary)
                                        .glassFont(.caption)
                                        .foregroundStyle(palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                        } header: {
                            // Informational omissions (for example an optional
                            // WorkoutKit plan this device cannot decode) do not
                            // reduce the export below full success, so the section
                            // reads as notes rather than warnings.
                            Text(LocalizedStringKey(
                                entry.isFullSuccess ? "Export Notes" : "Partial Export Warnings"
                            ))
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        }
                    }

                    // Failed Dates Section (if applicable). Capped like the
                    // Android history detail so large failures stay scrollable;
                    // retry counts and actions still reflect the full list.
                    if !entry.failedDateDetails.isEmpty {
                        Section {
                            ForEach(entry.failedDateDetails.prefix(8), id: \.date) { detail in
                                HStack {
                                    Text(detail.dateString)
                                        .foregroundStyle(palette.text)
                                        .font(Typography.bodyMono())
                                    Spacer()
                                    Text(detail.reason.shortDescription)
                                        .glassFont(.caption)
                                        .foregroundStyle(palette.coral)
                                }
                            }
                            if entry.failedDateDetails.count > 8 {
                                Text("+\(entry.failedDateDetails.count - 8) more")
                                    .glassFont(.caption)
                                    .foregroundStyle(palette.muted)
                            }
                        } header: {
                            Text("Failed Dates")
                                .glassFont(.caption)
                                .foregroundStyle(palette.muted)
                        }
                    }
                }
                .glassFormRows()
            }
            .glassFormChrome()
            .navigationTitle("Export Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
    }

    private func historyValueRow(
        _ label: LocalizedStringKey,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text(label)
                .foregroundStyle(palette.muted)
            Spacer(minLength: Spacing.s3)
            Text(value)
                .font(monospaced ? Typography.bodyMono() : Typography.body())
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func historyScopeGroup(
        title: LocalizedStringKey,
        values: [String],
        monospaced: Bool = false
    ) -> some View {
        DisclosureGroup {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(monospaced ? Typography.bodyMono() : Typography.body())
                    .foregroundStyle(palette.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            HStack(spacing: Spacing.s1) {
                Text(title)
                Text("(\(values.count))")
            }
        }
        .foregroundStyle(palette.text)
    }

    private func operationLabel(_ kind: ExportHistoryOperationDetails.Kind) -> String {
        switch kind {
        case .generatedFiles: return String(localized: "Generated files")
        case .rawExport: return String(localized: "Raw data export")
        case .canonicalExtraction: return String(localized: "Canonical extraction")
        case .agentDataGatewayUpload: return String(localized: "Agent Data gateway upload")
        }
    }

    private func dateSelectionLabel(_ value: String) -> String {
        value == "all_available"
            ? String(localized: "All available data")
            : String(localized: "Exact date range")
    }

    private func settingsPolicyLabel(_ value: String) -> String {
        value == "current_iphone_settings"
            ? String(localized: "Current iPhone settings")
            : String(localized: "Requested dates only")
    }

    private func profileLabel(_ value: String) -> String {
        switch value {
        case "canonical_source_records_v1": return String(localized: "Canonical source records")
        case "health_data_projection": return String(localized: "Health data projection")
        default: return displayToken(value)
        }
    }

    private func detailLevelLabel(_ value: String) -> String {
        switch value {
        case "summary": return String(localized: "Summary")
        case "detailed_time_series": return String(localized: "Detailed Time-Series")
        case "archive_only": return String(localized: "HealthKit Archive Only")
        case "lossless": return String(localized: "Lossless")
        default: return displayToken(value)
        }
    }

    private func metricDisplayName(_ id: String) -> String {
        guard let metric = HealthMetrics.all.first(where: { $0.id == id }) else {
            return displayToken(id)
        }
        return "\(metric.name) · \(id)"
    }

    private func displayToken(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        } else {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
    }
}

private struct ScheduleSettingsPreviewContainer: View {
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            ScheduleSettingsView(
                vaultManager: VaultManager(),
                advancedSettings: AdvancedExportSettings(),
                apiExportSettings: APIExportSettings(),
                agentDataGatewaySettings: AgentDataGatewaySettings(),
                showFolderPicker: $showFolderPicker
            )
            .environmentObject(SchedulingManager.shared)
            .environmentObject(HealthKitManager.shared)
            .environmentObject(SyncService())
            .environmentObject(ConfigurationProtectionManager())
        }
    }
}

#Preview {
    ScheduleSettingsPreviewContainer()
}
