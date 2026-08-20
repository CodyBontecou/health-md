#if os(iOS)
import SwiftUI

/// Per-profile scheduled-export configuration card for the Schedule tab.
///
/// Phase 3 surface (see `docs/features/export-profiles.md`): one row per
/// export profile with a schedule toggle and cadence editor. Mutations go
/// through `ScheduledExportEntryStore` and finish with
/// `schedulingManager.refreshScheduledAutomation()` so background tasks and
/// worker sync follow immediately. The footer surfaces the projected monthly
/// exporting-request count (decision 4: the free plan's 10 actions are shared
/// across every profile, schedule, and manual export).
///
/// Observes the shared `ExportProfileCoordinator`'s stores so profiles created
/// or removed on other screens (for example Settings → Export Profiles) appear
/// here immediately; a private store instance would snapshot the list once and
/// go stale, hiding newly added profiles.
struct ProfileScheduleSection: View {
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    @State private var editingProfile: ExportProfile?

    init(coordinator: ExportProfileCoordinator) {
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
    }

    private func rowDivider(leading: CGFloat = 0) -> some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
            .padding(.leading, leading)
    }

    private func inlineIcon(_ systemName: String, isActive: Bool) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(isActive ? Color.accent : Color.textMuted)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                inlineIcon("person.crop.circle.badge.clock", isActive: entryStore.entries.contains(where: \.isEnabled))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Profile Schedules")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)

            ForEach(Array(profileStore.profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { rowDivider(leading: 40) }
                profileRow(profile)
            }

            rowDivider(leading: 0)
                .padding(.top, Spacing.s2)

            usageFooter
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s3)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bgPrimary)
        )
        .sheet(item: $editingProfile) { profile in
            ProfileScheduleEditorSheet(
                profile: profile,
                entry: entryStore.entry(profileID: profile.id),
                onSave: { entry in
                    _ = entryStore.upsert(entry)
                    schedulingManager.refreshScheduledAutomation()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Rows

    private func profileRow(_ profile: ExportProfile) -> some View {
        let entry = entryStore.entry(profileID: profile.id)
        return HStack(alignment: .center, spacing: Spacing.s3) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.body.weight(.medium))
                .foregroundStyle((entry?.isEnabled ?? false) ? Color.accent : Color.textMuted)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(Typography.body())
                    .foregroundStyle(Color.textPrimary)

                Text(cadenceSummary(for: entry))
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.s2)

            Toggle(
                "Schedule \(profile.name)",
                isOn: Binding(
                    get: { entry?.isEnabled ?? false },
                    set: { isEnabled in
                        setEntryEnabled(isEnabled, for: profile, existing: entry)
                    }
                )
            )
            .labelsHidden()
            .tint(Color.accent)
            .accessibilityLabel(String(localized: "Schedule \(profile.name)", comment: "Toggle label for a profile's schedule"))
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .contentShape(Rectangle())
        .onTapGesture {
            editingProfile = profile
        }
    }

    private func setEntryEnabled(
        _ isEnabled: Bool,
        for profile: ExportProfile,
        existing entry: ScheduledExportEntry?
    ) {
        if let entry {
            _ = entryStore.update(profileID: profile.id) { $0.isEnabled = isEnabled }
        } else {
            // Seed new entries from the legacy schedule's preferred time so a
            // user migrating from single-schedule mode keeps their routine.
            let legacy = schedulingManager.schedule
            let entry = ScheduledExportEntry(
                profileID: profile.id,
                isEnabled: isEnabled,
                frequency: .daily,
                preferredHour: legacy.preferredHour,
                preferredMinute: legacy.preferredMinute,
                lookbackDays: 1
            )
            _ = entryStore.upsert(entry)
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
            let weekday = weekdayName(entry.weekday)
            return String(localized: "Weekly on \(weekday) at \(time)", comment: "Profile schedule cadence summary")
        case .custom:
            let unit = entry.customUnit.label(for: entry.customInterval)
            return String(localized: "Every \(entry.customInterval) \(unit) at \(time)", comment: "Profile schedule cadence summary")
        }
    }

    private func weekdayName(_ isoWeekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        // ISO 1 = Monday … 7 = Sunday; veryShortWeekdaySymbols starts Sunday.
        let sundayFirst = isoWeekday % 7
        return symbols[sundayFirst]
    }

    // MARK: - Usage footer

    private var usageFooter: some View {
        let enabledCount = entryStore.entries.filter(\.isEnabled).count
        let monthlyTotal = ScheduledUsageProjection.projectedMonthlyTotal(entries: entryStore.entries)
        return VStack(alignment: .leading, spacing: 3) {
            if enabledCount > 0 {
                Text(String(
                    localized: "Projected use: about \(monthlyTotal) export actions per month across \(enabledCount) scheduled profile\(enabledCount == 1 ? "" : "s").",
                    comment: "Projected monthly scheduled export usage across profiles"
                ))
            } else {
                Text(String(
                    localized: "No profile schedules enabled.",
                    comment: "Profile schedule footer when nothing is enabled"
                ))
            }
            Text(String(
                localized: "The free plan includes 10 export actions total — shared by every profile, schedule, and manual export. Full Access removes the limit.",
                comment: "Free-plan quota explanation under profile schedules"
            ))
        }
        .font(Typography.caption())
        .foregroundStyle(Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Cadence editor sheet for one profile's schedule entry.
struct ProfileScheduleEditorSheet: View {
    let profile: ExportProfile
    /// Nil while the profile has no entry yet; the sheet creates one on save.
    let entry: ScheduledExportEntry?
    let onSave: (ScheduledExportEntry) -> Void

    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduledExportEntry

    init(
        profile: ExportProfile,
        entry: ScheduledExportEntry?,
        onSave: @escaping (ScheduledExportEntry) -> Void
    ) {
        self.profile = profile
        self.entry = entry
        self.onSave = onSave
        // Start from the existing entry, or daily defaults seeded later by the
        // caller's toggle path when none exists.
        _draft = State(initialValue: entry ?? ScheduledExportEntry(
            profileID: profile.id,
            isEnabled: true,
            frequency: .daily
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                } header: {
                    Text("Schedule")
                }

                Section {
                    Picker("Frequency", selection: $draft.frequency) {
                        Text("Daily").tag(ScheduleFrequency.daily)
                        Text("Weekly").tag(ScheduleFrequency.weekly)
                        Text("Custom").tag(ScheduleFrequency.custom)
                    }

                    if draft.frequency == .weekly {
                        Picker("Day", selection: $draft.weekday) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(weekdayLabel(weekday)).tag(weekday)
                            }
                        }
                    }

                    if draft.frequency == .custom {
                        Stepper(
                            "Every \(draft.customInterval) \(draft.customUnit.label(for: draft.customInterval))",
                            value: $draft.customInterval,
                            in: 1...365
                        )
                        Picker("Unit", selection: $draft.customUnit) {
                            Text("Days").tag(ScheduleIntervalUnit.day)
                            Text("Weeks").tag(ScheduleIntervalUnit.week)
                            Text("Months").tag(ScheduleIntervalUnit.month)
                        }
                    }

                    DatePicker(
                        "Time",
                        selection: timeBinding,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("Cadence")
                }

                Section {
                    Stepper(
                        "Lookback: \(draft.lookbackDays) day\(draft.lookbackDays == 1 ? "" : "s")",
                        value: $draft.lookbackDays,
                        in: ExportSchedule.minimumLookbackDays...ExportSchedule.maximumLookbackDays
                    )

                    Toggle("Today Refresh", isOn: $draft.todayRefreshEnabled)
                    if draft.todayRefreshEnabled {
                        Picker("Refresh Interval", selection: $draft.todayRefreshIntervalHours) {
                            ForEach(ExportSchedule.todayRefreshIntervalOptions, id: \.self) { hours in
                                Text("Every \(hours) hours").tag(hours)
                            }
                        }
                    }
                } header: {
                    Text("Scope")
                } footer: {
                    Text("Each run exports the profile's metrics and formats to its own destination. A run consumes one of the 10 free export actions unless you have Full Access.")
                }
            }
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // The cadence stays inspectable, but persisting a
                        // schedule entry mutates the profile's automation, so
                        // the shared lock can reject an editor that was
                        // already open when protection was turned on.
                        configurationProtection.performConfigurationChange {
                            onSave(normalizedDraft)
                            dismiss()
                        }
                    }
                }
            }
        }
        // The sheet covers the app-level toast, so blocked saves surface a
        // sheet-local one; its settings shortcut dismisses the editor.
        .overlay(alignment: .top) {
            ConfigurationProtectionToast(configurationProtection: configurationProtection)
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil {
                dismiss()
            }
        }
    }

    private var normalizedDraft: ScheduledExportEntry {
        var entry = draft
        // Keep lookback aligned with frequency defaults when it still carries
        // another frequency's default, mirroring the legacy schedule editor.
        let currentDefault = ExportSchedule.defaultLookbackDays(
            for: entry.frequency,
            customInterval: entry.customInterval,
            customUnit: entry.customUnit
        )
        if entry.lookbackDays == currentDefault { return entry }
        return entry
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: draft.preferredHour,
                    minute: draft.preferredMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.preferredHour = components.hour ?? 8
                draft.preferredMinute = components.minute ?? 0
            }
        )
    }

    private func weekdayLabel(_ isoWeekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let sundayFirst = isoWeekday % 7
        return symbols[sundayFirst]
    }
}
#endif
