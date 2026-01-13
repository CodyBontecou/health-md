import SwiftUI

struct ScheduleSettingsView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled: Bool
    @State private var frequency: ScheduleFrequency
    @State private var preferredHour: Int
    @State private var preferredMinute: Int

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

                    Section {
                        if let lastExport = schedulingManager.schedule.lastExportDate {
                            HStack {
                                Text("Last Export")
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text(formatDate(lastExport))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .font(Typography.body())
                        } else {
                            Text("No exports yet")
                                .font(Typography.body())
                                .foregroundStyle(Color.textSecondary)
                        }
                    } header: {
                        Text("History")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
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

#Preview {
    ScheduleSettingsView()
        .environmentObject(SchedulingManager.shared)
}
