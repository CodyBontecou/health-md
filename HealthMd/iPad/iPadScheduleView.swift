import SwiftUI

// MARK: - iPad Schedule View (matching macOS MacScheduleView Form layout)

struct iPadScheduleView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var healthKitManager: HealthKitManager

    var body: some View {
        Form {
            // MARK: Automatic Export Toggle
            Section {
                Toggle("Enable scheduled exports", isOn: Binding(
                    get: { schedulingManager.schedule.isEnabled },
                    set: { enabled in
                        var s = schedulingManager.schedule
                        s.isEnabled = enabled
                        schedulingManager.schedule = s
                    }
                ))
                .tint(Color.accent)
            } header: {
                iPadBrandLabel("Automation")
            } footer: {
                Text("Health.md will automatically export your health data on the schedule below.")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textMuted)
            }

            // MARK: Schedule Configuration
            if schedulingManager.schedule.isEnabled {
                Section {
                    Picker("Frequency", selection: Binding(
                        get: { schedulingManager.schedule.frequency },
                        set: { freq in
                            var s = schedulingManager.schedule
                            s.frequency = freq
                            schedulingManager.schedule = s
                        }
                    )) {
                        Text("Daily").tag(ScheduleFrequency.daily)
                        Text("Weekly").tag(ScheduleFrequency.weekly)
                    }
                    .tint(Color.accent)

                    DatePicker(
                        "Preferred Time",
                        selection: Binding(
                            get: {
                                var comps = DateComponents()
                                comps.hour = schedulingManager.schedule.preferredHour
                                comps.minute = schedulingManager.schedule.preferredMinute
                                return Calendar.current.date(from: comps) ?? Date()
                            },
                            set: { date in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                                var s = schedulingManager.schedule
                                s.preferredHour = comps.hour ?? 6
                                s.preferredMinute = comps.minute ?? 0
                                schedulingManager.schedule = s
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .tint(Color.accent)
                } header: {
                    iPadBrandLabel("Configuration")
                }

                // MARK: Background
                Section {
                    Text("iOS determines the optimal background task timing. Make sure background refresh is enabled for Health.md in Settings.")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                } header: {
                    iPadBrandLabel("Background")
                }

                // MARK: Status
                Section {
                    if let lastExport = schedulingManager.schedule.lastExportDate {
                        LabeledContent("Last Export") {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.success)
                                    .font(.caption)
                                Text(lastExport, style: .relative)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    } else {
                        LabeledContent("Last Export") {
                            Text("Never")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.textMuted)
                        }
                    }

                    if let next = schedulingManager.getNextExportDescription() {
                        LabeledContent("Next Export") {
                            Text(next)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                } header: {
                    iPadBrandLabel("Status")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedule")
    }
}
