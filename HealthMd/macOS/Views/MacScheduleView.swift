#if os(macOS)
import SwiftUI

// MARK: - Schedule View — Branded Form

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
                .tint(Color.accent)
            } header: {
                BrandLabel("Automation")
            } footer: {
                Text("Health.md will automatically export your health data on the schedule below.")
                    .font(BrandTypography.caption())
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
                    BrandLabel("Configuration")
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
                    .tint(Color.accent)
                } header: {
                    BrandLabel("Background")
                } footer: {
                    Text("Health.md runs in the menu bar to perform scheduled exports. Enable \"Launch at Login\" so exports happen automatically when your Mac starts.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
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
                                    .font(BrandTypography.value())
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    } else {
                        LabeledContent("Last Export") {
                            Text("Never")
                                .font(BrandTypography.value())
                                .foregroundStyle(Color.textMuted)
                        }
                    }

                    if let next = schedulingManager.getNextExportDescription() {
                        LabeledContent("Next Export") {
                            Text(next)
                                .font(BrandTypography.value())
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                } header: {
                    BrandLabel("Status")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedule")
    }
}

#endif
