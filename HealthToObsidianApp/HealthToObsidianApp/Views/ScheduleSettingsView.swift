import SwiftUI

struct ScheduleSettingsView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @ObservedObject private var exportHistory = ExportHistoryManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled: Bool
    @State private var frequency: ScheduleFrequency
    @State private var preferredHour: Int
    @State private var preferredMinute: Int
    @State private var selectedEntry: ExportHistoryEntry?

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

                        Text("Note: iOS controls when background tasks run based on device usage patterns, battery level, and system conditions. The scheduled time is a suggestion, not a guarantee.")
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

                        HStack {
                            Text("Time")
                                .foregroundStyle(Color.textPrimary)

                            Spacer()

                            HStack(spacing: 4) {
                                // Hour Picker
                                Picker("", selection: $preferredHour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Color.accent)
                                .accessibilityLabel("Hour")

                                Text(":")
                                    .foregroundStyle(Color.textSecondary)

                                // Minute Picker
                                Picker("", selection: $preferredMinute) {
                                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Color.accent)
                                .accessibilityLabel("Minute")
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
                ExportHistoryDetailView(entry: entry)
            }
        }
    }

    private func saveSchedule() {
        var newSchedule = schedulingManager.schedule
        newSchedule.isEnabled = isEnabled
        newSchedule.frequency = frequency
        newSchedule.preferredHour = preferredHour
        newSchedule.preferredMinute = preferredMinute
        schedulingManager.schedule = newSchedule
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
    @Environment(\.dismiss) private var dismiss

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
}
