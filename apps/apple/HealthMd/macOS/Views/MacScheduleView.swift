#if os(macOS)
import SwiftUI

// MARK: - Schedule View — Branded Form

struct MacScheduleView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager

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
                    Picker("Frequency", selection: frequencyBinding) {
                        ForEach(ScheduleFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.description).tag(frequency)
                        }
                    }
                    .tint(Color.accent)

                    if schedulingManager.schedule.frequency == .custom {
                        Stepper(
                            "Repeat every \(schedulingManager.schedule.customInterval)",
                            value: customIntervalBinding,
                            in: ExportSchedule.minimumCustomInterval...ExportSchedule.maximumCustomInterval
                        )

                        Picker("Interval Unit", selection: customUnitBinding) {
                            ForEach(ScheduleIntervalUnit.allCases, id: \.self) { unit in
                                Text(unit.label(for: schedulingManager.schedule.customInterval).capitalized)
                                    .tag(unit)
                            }
                        }

                        DatePicker(
                            "Starting",
                            selection: customAnchorDateBinding,
                            displayedComponents: .date
                        )
                        .tint(Color.accent)

                        Text("The start date sets the repeating phase. Monthly schedules use the last day when a month is shorter.")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)
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
