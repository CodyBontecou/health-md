import SwiftUI

/// Inline schedule configuration surface used by the Schedule tab.
/// Binds directly to `SchedulingManager.schedule` so edits persist as they happen.
struct ScheduleSettingsView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()

    @State private var selectedEntry: ExportHistoryEntry?

    // Retry export state
    @State private var isRetrying = false
    @State private var retryProgress: Double = 0.0
    @State private var retryStatusMessage = ""
    @State private var showRetryError = false
    @State private var retryErrorMessage = ""

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { schedulingManager.schedule.isEnabled },
            set: { newValue in
                let wasEnabled = schedulingManager.schedule.isEnabled
                if newValue && !wasEnabled {
                    trackScheduleEnableAttempt()
                    // Request notification permissions when turning the schedule on
                    Task { @MainActor in
                        _ = await schedulingManager.requestNotificationPermissions()
                        var updated = schedulingManager.schedule
                        updated.isEnabled = true
                        schedulingManager.schedule = updated
                        UIAccessibility.post(notification: .announcement, argument: "Schedule enabled")
                    }
                } else {
                    var updated = schedulingManager.schedule
                    updated.isEnabled = newValue
                    schedulingManager.schedule = updated
                    if wasEnabled && !newValue {
                        UIAccessibility.post(notification: .announcement, argument: "Schedule disabled")
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
                let previousDefault = ExportSchedule.defaultLookbackDays(for: updated.frequency)
                let shouldFollowFrequencyDefault = updated.lookbackDays == previousDefault
                updated.frequency = newValue
                if shouldFollowFrequencyDefault {
                    updated.lookbackDays = ExportSchedule.defaultLookbackDays(for: newValue)
                }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                heroHeader
                scheduleAutomationCard
                exportHistoryCard
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s4)
            .padding(.bottom, 132)
        }
        .background(Color.bgSecondary.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedEntry) { entry in
            ExportHistoryDetailView(entry: entry, onRetry: retryExport)
        }
        .overlay {
            if isRetrying {
                RetryProgressOverlay(
                    message: retryStatusMessage,
                    progress: retryProgress
                )
            }
        }
        .alert("Retry Failed", isPresented: $showRetryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(retryErrorMessage)
        }
    }

    // MARK: - Sections

    private var heroHeader: some View {
        HealthMdPageHeader(
            title: "Scheduled Exports",
            subtitle: "Keep your local Health.md folder updated with recurring Apple Health exports."
        ) {
            HStack(spacing: Spacing.s2) {
                statusPill(
                    label: schedulingManager.schedule.isEnabled ? "On" : "Off",
                    icon: schedulingManager.schedule.isEnabled ? "checkmark" : "pause",
                    tint: schedulingManager.schedule.isEnabled ? Color.success : Color.textMuted
                )

                if schedulingManager.schedule.isEnabled, let nextExport = schedulingManager.getNextExportDescription() {
                    statusPill(label: "Next", value: nextExport, icon: "clock", tint: Color.accent)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var scheduleAutomationCard: some View {
        sectionCard(title: "Automation") {
            VStack(spacing: 0) {
                automaticExportRow

                rowDivider()

                if schedulingManager.schedule.isEnabled {
                    frequencyRow
                    rowDivider(leading: 40)
                    timeRow
                    rowDivider(leading: 40)
                    lookbackRow
                    rowDivider()
                    destinationGuidanceRow
                    rowDivider(leading: 40)
                    backgroundGuidanceRow
                } else {
                    disabledScheduleRow
                }
            }
        }
    }

    private var automaticExportRow: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            inlineIcon("arrow.triangle.2.circlepath", isActive: schedulingManager.schedule.isEnabled)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Automatic Export")
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)

                Text(automaticExportSummary)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.s2)

            statusPill(
                label: schedulingManager.schedule.isEnabled ? "Enabled" : "Disabled",
                icon: schedulingManager.schedule.isEnabled ? "checkmark" : "circle",
                tint: schedulingManager.schedule.isEnabled ? Color.success : Color.textMuted
            )
            .accessibilityHidden(true)

            Toggle("Enable Scheduled Exports", isOn: isEnabledBinding)
                .labelsHidden()
                .tint(Color.accent)
                .accessibilityIdentifier(AccessibilityID.Schedule.enableToggle)
                .accessibilityLabel("Automatic export schedule")
                .accessibilityValue(schedulingManager.schedule.isEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Double tap to \(schedulingManager.schedule.isEnabled ? "disable" : "enable") scheduled exports")
        }
        .padding(.vertical, Spacing.s3)
    }

    private var automaticExportSummary: String {
        if schedulingManager.schedule.isEnabled, let nextExport = schedulingManager.getNextExportDescription() {
            return "Next export: \(nextExport)."
        }
        return "Off. Turn on automation to configure timing, lookback, and reminder behavior."
    }

    private var disabledScheduleRow: some View {
        guidanceRow(
            icon: "pause.circle",
            title: "Schedule Off",
            message: "Scheduled exports are paused. Manual exports remain available from the Export tab.",
            status: "Manual Only",
            statusTint: Color.textMuted
        )
    }

    private var frequencyRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            controlHeader(
                icon: "repeat",
                title: "Frequency",
                message: "Choose how often Health.md prepares a local iPhone export."
            )

            Picker("Frequency", selection: frequencyBinding) {
                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                    Text(freq.description).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .tint(Color.accent)
            .padding(.leading, 40)
            .accessibilityIdentifier(AccessibilityID.Schedule.frequencyPicker)
            .accessibilityLabel("Export frequency")
            .accessibilityValue(schedulingManager.schedule.frequency.description)
        }
        .padding(.vertical, Spacing.s3)
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
                message: "iOS uses this as the target time for notifications and background scheduling."
            )

            HStack(spacing: Spacing.s2) {
                hourMenu
                Text(":")
                    .font(Typography.headline())
                    .foregroundStyle(Color.textSecondary)
                minuteMenu
                periodMenu
                Spacer(minLength: 0)
            }
            .padding(.leading, 40)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preferred time")
            .accessibilityValue(preferredTimeText)
        }
        .padding(.vertical, Spacing.s3)
    }

    private var hourMenu: some View {
        Menu {
            ForEach(1...12, id: \.self) { hour in
                Button(String(format: "%d", hour)) {
                    setHour12(hour, period: displayPeriod)
                }
            }
        } label: {
            timeMenuLabel(text: String(format: "%d", displayHour12))
        }
        .accessibilityIdentifier(AccessibilityID.Schedule.hourPicker)
        .accessibilityLabel("Hour")
        .accessibilityValue(String(format: "%d", displayHour12))
        .accessibilityHint("Double tap to select hour")
    }

    private var minuteMenu: some View {
        Menu {
            ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                Button(String(format: "%02d", minute)) {
                    minuteBinding.wrappedValue = minute
                }
            }
        } label: {
            timeMenuLabel(text: String(format: "%02d", schedulingManager.schedule.preferredMinute))
        }
        .accessibilityIdentifier(AccessibilityID.Schedule.minutePicker)
        .accessibilityLabel("Minute")
        .accessibilityValue(String(format: "%02d", schedulingManager.schedule.preferredMinute))
        .accessibilityHint("Double tap to select minute")
    }

    private var periodMenu: some View {
        Menu {
            Button("AM") { setHour12(displayHour12, period: .am) }
            Button("PM") { setHour12(displayHour12, period: .pm) }
        } label: {
            timeMenuLabel(text: displayPeriod.rawValue)
        }
        .accessibilityIdentifier(AccessibilityID.Schedule.periodPicker)
        .accessibilityLabel("Period")
        .accessibilityValue(displayPeriod.rawValue)
        .accessibilityHint("Double tap to switch between AM and PM")
    }

    private func timeMenuLabel(text: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Text(text)
                .font(Typography.monoEmphasis())
                .foregroundStyle(Color.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private var preferredTimeText: String {
        String(format: "%d:%02d %@", displayHour12, schedulingManager.schedule.preferredMinute, displayPeriod.rawValue)
    }

    private var lookbackRow: some View {
        Stepper(
            value: lookbackDaysBinding,
            in: ExportSchedule.minimumLookbackDays...ExportSchedule.maximumLookbackDays
        ) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                inlineIcon("calendar.badge.minus")

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    HStack(spacing: Spacing.s2) {
                        Text("Lookback Window")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)

                        statusPill(
                            label: "\(schedulingManager.schedule.lookbackDays) day\(schedulingManager.schedule.lookbackDays == 1 ? "" : "s")",
                            icon: "number",
                            tint: Color.textMuted
                        )
                    }

                    Text("Each run exports the past \(schedulingManager.schedule.lookbackDays) day\(schedulingManager.schedule.lookbackDays == 1 ? "" : "s") ending with yesterday.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Color.accent)
        .padding(.vertical, Spacing.s3)
        .accessibilityLabel("Lookback window")
        .accessibilityValue("\(schedulingManager.schedule.lookbackDays) day\(schedulingManager.schedule.lookbackDays == 1 ? "" : "s")")
        .accessibilityHint("Adjusts how many past days each scheduled export includes")
    }

    private var destinationGuidanceRow: some View {
        guidanceRow(
            icon: "folder",
            title: "Export Destination",
            message: "Scheduled exports and Shortcuts write to the selected iPhone folder. Connected Mac exports stay manual from the Export tab.",
            status: "iPhone Folder",
            statusTint: Color.accent,
            isActive: true
        )
    }

    private var backgroundGuidanceRow: some View {
        guidanceRow(
            icon: "bell.badge",
            title: "Background Timing",
            message: "Your iPhone must be unlocked when Health.md reads Health data. If data is locked, tap the notification to run the export.",
            status: "iOS Managed",
            statusTint: Color.warning
        )
    }

    private var exportHistoryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .center, spacing: Spacing.s3) {
                sectionLabel("Export History")

                Spacer()

                if !exportHistory.history.isEmpty {
                    Button("Clear History") {
                        exportHistory.clearHistory()
                    }
                    .font(Typography.label())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                    .background(Color.bgPrimary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
                    .accessibilityLabel("Clear export history")
                }
            }

            VStack(spacing: 0) {
                if exportHistory.history.isEmpty {
                    emptyHistoryState
                } else {
                    ForEach(Array(exportHistory.history.prefix(10).enumerated()), id: \.element.id) { index, entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            ExportHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)

                        if index < min(exportHistory.history.count, 10) - 1 {
                            rowDivider(leading: 40)
                        }
                    }

                    if exportHistory.history.count > 10 {
                        rowDivider(leading: 40)
                        Text("\(exportHistory.history.count - 10) more entries…")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Spacing.s3)
                            .padding(.leading, 40)
                    }
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 2, x: 0, y: 1)
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.s1) {
                Text("No Exports Yet")
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)

                Text("Run a manual export or turn on automation to start building history.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            sectionLabel(title)

            VStack(spacing: 0) {
                content()
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.025), radius: 2, x: 0, y: 1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption())
            .foregroundStyle(Color.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowDivider(leading: CGFloat = 0) -> some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
            .padding(.leading, leading)
    }

    private func inlineIcon(_ systemName: String, isActive: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(isActive ? Color.accent : Color.textSecondary)
            .frame(width: 28, height: 28)
            .background(isActive ? Color.selectedBackground : Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isActive ? Color.accent.opacity(0.35) : Color.borderSubtle, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private func controlHeader(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            inlineIcon(icon)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)

                Text(message)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func guidanceRow(
        icon: String,
        title: String,
        message: String,
        status: String,
        statusTint: Color,
        isActive: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            inlineIcon(icon, isActive: isActive)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(spacing: Spacing.s2) {
                    Text(title)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)

                    statusPill(label: status, icon: nil, tint: statusTint)
                }

                Text(message)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s3)
        .accessibilityElement(children: .combine)
    }

    private func statusPill(label: String, value: String? = nil, icon: String? = nil, tint: Color) -> some View {
        HStack(spacing: Spacing.s1) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }

            Text(value.map { "\(label): \($0)" } ?? label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.s2)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 1))
    }

    private func trackScheduleEnableAttempt() {
        if purchaseManager.isUnlocked {
            PricingAnalyticsClient.shared.trackScheduleEnableUnblocked(
                quotaState: purchaseManager.analyticsQuotaState
            )
        } else {
            PricingAnalyticsClient.shared.trackScheduleEnableBlocked(
                quotaState: purchaseManager.analyticsQuotaState
            )
        }
    }

    // MARK: - Retry Export

    private func retryExport(_ entry: ExportHistoryEntry) {
        isRetrying = true
        retryProgress = 0.0
        retryStatusMessage = "Preparing…"

        Task {
            await performRetryExport(entry)
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
                retryErrorMessage = "No dates to retry"
                showRetryError = true
            }
            return
        }

        vaultManager.refreshVaultAccess()
        guard vaultManager.hasVaultAccess else {
            await MainActor.run {
                retryErrorMessage = vaultManager.hasSavedVaultFolder
                    ? ExportFailureReason.accessDenied.detailedDescription
                    : ExportFailureReason.noVaultSelected.detailedDescription
                showRetryError = true
            }
            return
        }

        guard vaultManager.startVaultAccess() else {
            await MainActor.run {
                retryErrorMessage = ExportFailureReason.accessDenied.detailedDescription
                showRetryError = true
            }
            return
        }

        let totalDays = datesToExport.count
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (index, date) in datesToExport.enumerated() {
            await MainActor.run {
                retryStatusMessage = "Exporting \(dateFormatter.string(from: date))… (\(index + 1)/\(totalDays))"
                retryProgress = Double(index) / Double(totalDays)
            }

            do {
                let healthData = try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: advancedSettings.includeGranularData,
                    metricSelection: advancedSettings.metricSelection
                )

                if !healthData.filtered(by: advancedSettings.metricSelection).hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: advancedSettings)

                if success {
                    partialFailures.append(contentsOf: healthData.partialFailures)
                    successCount += 1
                } else {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .fileWriteError))
                }
            } catch {
                failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
            }
        }

        vaultManager.stopVaultAccess()

        await MainActor.run {
            retryProgress = 1.0

            // Record the result
            let startDate = datesToExport.min() ?? entry.dateRangeStart
            let endDate = datesToExport.max() ?? entry.dateRangeEnd

            if failedDateDetails.isEmpty && partialFailures.isEmpty && successCount > 0 {
                retryStatusMessage = String(localized: "Successfully exported \(successCount) files", comment: "Export success message")
                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: successCount,
                    totalCount: totalDays,
                    targetLabel: "iPhone: \(vaultManager.vaultName)",
                    fileCount: successCount * max(advancedSettings.exportFormats.count, 1)
                )
            } else if successCount > 0 {
                retryStatusMessage = partialFailures.isEmpty
                    ? "Exported \(successCount)/\(totalDays) files"
                    : "Exported \(successCount)/\(totalDays) files with \(partialFailures.count) warning(s)"
                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails,
                    targetLabel: "iPhone: \(vaultManager.vaultName)",
                    fileCount: successCount * max(advancedSettings.exportFormats.count, 1),
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
                    fileCount: 0,
                    partialFailures: partialFailures
                )
            }
        }
    }
}

// MARK: - Retry Progress Overlay

struct RetryProgressOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: String
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: Spacing.s4) {
                ZStack {
                    Circle()
                        .stroke(Color.borderSubtle, lineWidth: 3)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(reduceMotion ? .zero : .degrees(-90))
                        .animation(reduceMotion ? nil : AnimationTimings.standard, value: progress)

                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accent)
                }
                .accessibilityHidden(true)

                VStack(spacing: Spacing.s1) {
                    Text("Retrying Export")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)

                    Text(message)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: progress)
                    .tint(Color.accent)
                    .frame(width: 200)
                    .accessibilityHidden(true)

                Text("\(Int((progress * 100).rounded()))% Complete")
                    .font(Typography.monoCaptionEmphasis())
                    .foregroundStyle(Color.accent)
                    .geistPill(tint: Color.accent)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.s6)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Retrying export")
            .accessibilityValue("\(message), \(Int(progress * 100)) percent complete")
        }
    }
}

// MARK: - Export History Row

struct ExportHistoryRow: View {
    let entry: ExportHistoryEntry

    private var statusColor: Color {
        if entry.isFullSuccess {
            return .success
        } else if entry.isPartialSuccess {
            return .warning
        } else {
            return .error
        }
    }

    private var statusIcon: String {
        if entry.isFullSuccess {
            return "checkmark.circle.fill"
        } else if entry.isPartialSuccess {
            return "exclamationmark.circle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }

    private var statusDescription: String {
        if entry.isFullSuccess {
            return "Success"
        } else if entry.isPartialSuccess {
            return "Partial Success"
        } else {
            return "Failed"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: statusIcon)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .background(statusColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.20), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(spacing: Spacing.s2) {
                    Text(entry.summaryDescription)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    Text(statusDescription)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(statusColor.opacity(0.22), lineWidth: 1))
                }

                HStack(spacing: Spacing.s2) {
                    Label(entry.source.rawValue, systemImage: entry.source.icon)
                        .labelStyle(.titleAndIcon)

                    Text(formatTimestamp(entry.timestamp))

                    if let targetLabel = entry.targetLabel {
                        Text("→ \(targetLabel)")
                            .lineLimit(1)
                    }
                }
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
            }

            Spacer(minLength: Spacing.s2)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusDescription): \(entry.summaryDescription)")
        .accessibilityValue("\(entry.source.rawValue), \(formatTimestamp(entry.timestamp))")
        .accessibilityHint("Double tap to view details")
        .accessibilityAddTraits(.isButton)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Export History Detail View

struct ExportHistoryDetailView: View {
    let entry: ExportHistoryEntry
    let onRetry: ((ExportHistoryEntry) -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(entry: ExportHistoryEntry, onRetry: ((ExportHistoryEntry) -> Void)? = nil) {
        self.entry = entry
        self.onRetry = onRetry
    }

    private var canRetry: Bool {
        !entry.isFullSuccess && entry.source != .macAgent
    }

    private var statusColor: Color {
        if entry.isFullSuccess {
            return .success
        } else if entry.isPartialSuccess {
            return .warning
        } else {
            return .error
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section {
                    HStack {
                        Text("Status")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(entry.isFullSuccess ? "Success" : (entry.isPartialSuccess ? "Partial" : "Failed"))
                            .foregroundStyle(statusColor)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Source")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: entry.source.icon)
                            Text(entry.source.rawValue)
                        }
                        .foregroundStyle(Color.textPrimary)
                    }

                    if let targetLabel = entry.targetLabel {
                        HStack {
                            Text("Target")
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(targetLabel)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }

                    HStack {
                        Text("Time")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatFullTimestamp(entry.timestamp))
                            .foregroundStyle(Color.textPrimary)
                    }
                } header: {
                    Text("Overview")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                }

                // Export Details Section
                Section {
                    HStack {
                        Text("Date Range")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatDateRange(entry.dateRangeStart, entry.dateRangeEnd))
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack {
                        Text("Files Exported")
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(filesExportedText(entry))
                            .foregroundStyle(Color.textPrimary)
                    }
                } header: {
                    Text("Details")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                }

                // Failure Reason Section (if applicable)
                if let reason = entry.failureReason {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(reason.shortDescription)
                                .font(Typography.body())
                                .foregroundStyle(Color.textPrimary)
                                .fontWeight(.medium)

                            Text(reason.detailedDescription)
                                .font(Typography.caption())
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Failure Reason")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if !entry.partialFailures.isEmpty {
                    Section {
                        ForEach(Array(entry.partialFailures.enumerated()), id: \.offset) { _, failure in
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.warning)
                                Text(failure.summary)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    } header: {
                        Text("Partial Export Warnings")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // Failed Dates Section (if applicable)
                if !entry.failedDateDetails.isEmpty {
                    Section {
                        ForEach(entry.failedDateDetails, id: \.date) { detail in
                            HStack {
                                Text(detail.dateString)
                                    .foregroundStyle(Color.textPrimary)
                                    .font(Typography.bodyMono())
                                Spacer()
                                Text(detail.reason.shortDescription)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.error)
                            }
                        }
                    } header: {
                        Text("Failed Dates")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // Retry Section (for failed or partial exports)
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
                            .foregroundStyle(Color.accent)
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
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle("Export Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func filesExportedText(_ entry: ExportHistoryEntry) -> String {
        if let fileCount = entry.fileCount {
            return "\(fileCount) file\(fileCount == 1 ? "" : "s") (\(entry.successCount)/\(entry.totalCount) days)"
        }
        return "\(entry.successCount) of \(entry.totalCount)"
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

#Preview {
    NavigationStack {
        ScheduleSettingsView()
            .environmentObject(SchedulingManager.shared)
            .environmentObject(HealthKitManager.shared)
    }
}
