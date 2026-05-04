import SwiftUI

/// Inline schedule configuration surface used by the Schedule tab.
/// Binds directly to `SchedulingManager.schedule` so edits persist as they happen.
struct ScheduleSettingsView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
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
                updated.frequency = newValue
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

    var body: some View {
        Form {
            automaticExportSection
            if schedulingManager.schedule.isEnabled {
                scheduleSection
            }
            exportHistorySection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
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

    private var automaticExportSection: some View {
        Section {
            Toggle("Enable Scheduled Exports", isOn: isEnabledBinding)
                .tint(Color.accent)
                .accessibilityIdentifier(AccessibilityID.Schedule.enableToggle)
                .accessibilityLabel("Automatic export schedule")
                .accessibilityValue(schedulingManager.schedule.isEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Double tap to \(schedulingManager.schedule.isEnabled ? "disable" : "enable") scheduled exports")
        } header: {
            Text("Automatic Export")
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if schedulingManager.schedule.isEnabled, let nextExport = schedulingManager.getNextExportDescription() {
                    Text("Next export: \(nextExport)")
                }

                Text("Note: Your iPhone must be unlocked for exports to work—iOS protects health data when locked. If locked, we'll send a notification at the scheduled time; tap it to run the export. The scheduled time is approximate; iOS controls when background tasks run based on usage patterns and system conditions.")
            }
            .font(Typography.caption())
            .foregroundStyle(Color.textSecondary)
        }
    }

    private var scheduleSection: some View {
        Section {
            Picker("Frequency", selection: frequencyBinding) {
                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                    Text(freq.description).tag(freq)
                }
            }
            .tint(Color.accent)
            .accessibilityIdentifier(AccessibilityID.Schedule.frequencyPicker)
            .accessibilityLabel("Export frequency")
            .accessibilityValue(schedulingManager.schedule.frequency.description)

            timeRow
        } header: {
            Text("Schedule")
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
        } footer: {
            Text(schedulingManager.schedule.frequency == .daily
                ? "Exports yesterday's data daily."
                : "Exports the last 7 days of data weekly."
            )
            .font(Typography.caption())
            .foregroundStyle(Color.textSecondary)
        }
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Time")
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: Spacing.sm) {
                hourMenu
                Text(":")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                minuteMenu
                periodMenu
                Spacer()
            }
        }
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
        HStack(spacing: Spacing.xs) {
            Text(text)
                .font(.body.weight(.medium).monospaced())
                .foregroundStyle(Color.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var exportHistorySection: some View {
        Section {
            if exportHistory.history.isEmpty {
                Text("No exports yet")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(exportHistory.history.prefix(10)) { entry in
                    ExportHistoryRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntry = entry
                        }
                }

                if exportHistory.history.count > 10 {
                    Text("\(exportHistory.history.count - 10) more entries...")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            }
        } header: {
            HStack {
                Text("Export History")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if !exportHistory.history.isEmpty {
                    Button("Clear") {
                        exportHistory.clearHistory()
                    }
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    // MARK: - Retry Export

    private func retryExport(_ entry: ExportHistoryEntry) {
        isRetrying = true
        retryProgress = 0.0
        retryStatusMessage = "Preparing..."

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

        guard vaultManager.hasVaultAccess else {
            await MainActor.run {
                retryErrorMessage = ExportFailureReason.noVaultSelected.detailedDescription
                showRetryError = true
            }
            return
        }

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()

        let totalDays = datesToExport.count
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (index, date) in datesToExport.enumerated() {
            await MainActor.run {
                retryStatusMessage = "Exporting \(dateFormatter.string(from: date))... (\(index + 1)/\(totalDays))"
                retryProgress = Double(index) / Double(totalDays)
            }

            do {
                let healthData = try await healthKitManager.fetchHealthData(for: date)

                if !healthData.hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: advancedSettings)

                if success {
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

            if failedDateDetails.isEmpty && successCount > 0 {
                retryStatusMessage = String(localized: "Successfully exported \(successCount) files", comment: "Export success message")
                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: successCount,
                    totalCount: totalDays
                )
            } else if successCount > 0 {
                retryStatusMessage = "Exported \(successCount)/\(totalDays) files"
                exportHistory.recordSuccess(
                    source: .manual,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: successCount,
                    totalCount: totalDays,
                    failedDateDetails: failedDateDetails
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
                    failedDateDetails: failedDateDetails
                )
            }
        }
    }
}

// MARK: - Retry Progress Overlay

struct RetryProgressOverlay: View {
    let message: String
    let progress: Double

    var body: some View {
        ZStack {
            // Frosted background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.lg) {
                // Animated progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.3), value: progress)

                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accent)
                }
                .accessibilityHidden(true)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                ProgressView(value: progress)
                    .tint(Color.accent)
                    .frame(width: 200)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
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
            return .green
        } else if entry.isPartialSuccess {
            return .orange
        } else {
            return .red
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
            return "Partial success"
        } else {
            return "Failed"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 16))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // Summary
                Text(entry.summaryDescription)
                    .font(Typography.body())
                    .foregroundStyle(Color.textPrimary)

                // Timestamp and source
                HStack(spacing: Spacing.xs) {
                    Image(systemName: entry.source.icon)
                        .font(.system(size: 10))
                    Text(formatTimestamp(entry.timestamp))
                        .font(Typography.caption())
                }
                .foregroundStyle(Color.textMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
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
        !entry.isFullSuccess
    }

    private var statusColor: Color {
        if entry.isFullSuccess {
            return .green
        } else if entry.isPartialSuccess {
            return .orange
        } else {
            return .red
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
                        Text("\(entry.successCount) of \(entry.totalCount)")
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

                // Failed Dates Section (if applicable)
                if !entry.failedDateDetails.isEmpty {
                    Section {
                        ForEach(entry.failedDateDetails, id: \.date) { detail in
                            HStack {
                                Text(detail.dateString)
                                    .foregroundStyle(Color.textPrimary)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(detail.reason.shortDescription)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.red)
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
