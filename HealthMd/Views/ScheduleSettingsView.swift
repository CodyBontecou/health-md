import SwiftUI

struct ScheduleSettingsView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var advancedSettings = AdvancedExportSettings()
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled: Bool
    @State private var frequency: ScheduleFrequency
    @State private var preferredHour: Int
    @State private var preferredMinute: Int
    @State private var selectedEntry: ExportHistoryEntry?

    // Retry export state
    @State private var isRetrying = false
    @State private var retryProgress: Double = 0.0
    @State private var retryStatusMessage = ""
    @State private var showRetryError = false
    @State private var retryErrorMessage = ""

    init() {
        let schedule = ExportSchedule.load()
        _isEnabled = State(initialValue: schedule.isEnabled)
        _frequency = State(initialValue: schedule.frequency)
        _preferredHour = State(initialValue: schedule.preferredHour)
        _preferredMinute = State(initialValue: schedule.preferredMinute)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Scheduled Exports", isOn: $isEnabled)
                        .tint(Color.accent)
                } header: {
                    Text("Automatic Export")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if isEnabled, let nextExport = schedulingManager.getNextExportDescription() {
                            Text("Next export: \(nextExport)")
                        }

                        Text("Note: Your iPhone must be unlocked for exports to work—iOS protects health data when locked. If locked, we'll send a notification at the scheduled time; tap it to run the export. The scheduled time is approximate; iOS controls when background tasks run based on usage patterns and system conditions.")
                    }
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                }

                if isEnabled {
                    Section {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                Text(freq.description).tag(freq)
                            }
                        }
                        .tint(Color.accent)

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Time")
                                .foregroundStyle(Color.textPrimary)

                            HStack(spacing: Spacing.sm) {
                                // Hour with Liquid Glass
                                Menu {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Button(String(format: "%02d", hour)) {
                                            preferredHour = hour
                                        }
                                    }
                                } label: {
                                    HStack(spacing: Spacing.xs) {
                                        Text(String(format: "%02d", preferredHour))
                                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.accent)
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

                                Text(":")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)

                                // Minute with Liquid Glass
                                Menu {
                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                        Button(String(format: "%02d", minute)) {
                                            preferredMinute = minute
                                        }
                                    }
                                } label: {
                                    HStack(spacing: Spacing.xs) {
                                        Text(String(format: "%02d", preferredMinute))
                                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Color.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.accent)
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

                                Spacer()
                            }
                        }
                    } header: {
                        Text("Schedule")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                    } footer: {
                        Text(frequency == .daily
                            ? "Exports yesterday's data daily."
                            : "Exports the last 7 days of data weekly."
                        )
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                    }

                }

                // Export History section (always visible)
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
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSchedule()
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                }
            }
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
    }

    private func saveSchedule() {
        let wasEnabled = schedulingManager.schedule.isEnabled

        // If user is enabling scheduled exports, request notification permissions first
        if isEnabled && !wasEnabled {
            Task { @MainActor in
                _ = await schedulingManager.requestNotificationPermissions()

                // Save the schedule after requesting permissions
                var newSchedule = schedulingManager.schedule
                newSchedule.isEnabled = isEnabled
                newSchedule.frequency = frequency
                newSchedule.preferredHour = preferredHour
                newSchedule.preferredMinute = preferredMinute
                schedulingManager.schedule = newSchedule
            }
        } else {
            // Save normally if not enabling or already enabled
            var newSchedule = schedulingManager.schedule
            newSchedule.isEnabled = isEnabled
            newSchedule.frequency = frequency
            newSchedule.preferredHour = preferredHour
            newSchedule.preferredMinute = preferredMinute
            schedulingManager.schedule = newSchedule
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                retryStatusMessage = "Successfully exported \(successCount) file\(successCount == 1 ? "" : "s")"
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

                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                ProgressView(value: progress)
                    .tint(Color.accent)
                    .frame(width: 200)
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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 16))

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
        }
        .padding(.vertical, 4)
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
    ScheduleSettingsView()
        .environmentObject(SchedulingManager.shared)
        .environmentObject(HealthKitManager.shared)
}
