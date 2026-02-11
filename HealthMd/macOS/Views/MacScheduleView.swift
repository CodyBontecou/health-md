#if os(macOS)
import SwiftUI

// MARK: - Schedule View

struct MacScheduleView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager

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
            } footer: {
                Text("Health.md will automatically export your health data on the schedule below.")
            }

            // MARK: Schedule Configuration
            if schedulingManager.schedule.isEnabled {
                Section("Configuration") {
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
                }

                // MARK: Login Item
                Section {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { schedulingManager.isLoginItemEnabled },
                        set: { enabled in
                            if enabled {
                                schedulingManager.enableLoginItem()
                            } else {
                                schedulingManager.disableLoginItem()
                            }
                        }
                    ))
                } header: {
                    Text("Background")
                } footer: {
                    Text("Health.md runs in the menu bar to perform scheduled exports. Enable \"Launch at Login\" so exports happen automatically when your Mac starts.")
                }

                // MARK: Status
                Section("Status") {
                    if let lastExport = schedulingManager.schedule.lastExportDate {
                        LabeledContent("Last Export") {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(lastExport, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        LabeledContent("Last Export") {
                            Text("Never")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let next = schedulingManager.getNextExportDescription() {
                        LabeledContent("Next Export") {
                            Text(next)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedule")
    }
}

#endif
