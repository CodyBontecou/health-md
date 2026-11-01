#if os(iOS)
import SwiftUI

/// ScheduleG. Same fields and save path as `ProfileScheduleEditorSheet`, plus the same
/// pending-recovery discard as `ProfileScheduleSection`.
struct GlassScheduleSheet: View {
    let profile: ExportProfile
    let entryStore: ScheduledExportEntryStore
    let onSave: (ScheduledExportEntry) -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var draft: ScheduledExportEntry
    @State private var showDiscardConfirmation = false
    @State private var isDiscardingRecovery = false
    @State private var showRecoveryError = false

    init(
        profile: ExportProfile,
        entry: ScheduledExportEntry?,
        entryStore: ScheduledExportEntryStore,
        onSave: @escaping (ScheduledExportEntry) -> Void
    ) {
        self.profile = profile
        self.entryStore = entryStore
        self.onSave = onSave
        _draft = State(initialValue: entry ?? ScheduledExportEntry(
            profileID: profile.id,
            isEnabled: true,
            frequency: .daily
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    panel {
                        Toggle(isOn: $draft.isEnabled) { label(String(localized: "Enabled")) }
                            .toggleStyle(GlassToggleStyle())
                    }

                    GlassSegmentedControl(
                        segments: ScheduleFrequency.allCases.map { .init(value: $0, title: $0.description) },
                        selection: $draft.frequency
                    )

                    panel {
                        if draft.frequency == .weekly {
                            Picker(String(localized: "Day"), selection: $draft.weekday) {
                                ForEach(1...7, id: \.self) { day in
                                    Text(ExportProfileCadenceSummary.weekdayName(day)).tag(day)
                                }
                            }
                        }
                        if draft.frequency == .custom {
                            Stepper(value: $draft.customInterval, in: 1...365) {
                                label(ScheduleDisplayCopy.cadence(
                                    count: draft.customInterval,
                                    unit: draft.customUnit,
                                    at: timeLabel
                                ))
                            }
                            Picker(String(localized: "Unit"), selection: $draft.customUnit) {
                                ForEach(ScheduleIntervalUnit.allCases, id: \.self) { unit in
                                    Text(ScheduleDisplayCopy.unitChoiceLabel(unit)).tag(unit)
                                }
                            }
                        }
                        DatePicker(String(localized: "Time"), selection: time, displayedComponents: .hourAndMinute)
                    }

                    panel {
                        Stepper(
                            value: $draft.lookbackDays,
                            in: ExportSchedule.minimumLookbackDays...ExportSchedule.maximumLookbackDays
                        ) {
                            label(draft.lookbackDays == 1
                                ? String(localized: "Lookback: 1 day")
                                : String(localized: "Lookback: \(draft.lookbackDays) days"))
                        }
                        Toggle(isOn: $draft.todayRefreshEnabled) { label(String(localized: "Today Refresh")) }
                            .toggleStyle(GlassToggleStyle())
                        if draft.todayRefreshEnabled {
                            Picker(String(localized: "Refresh Interval"), selection: $draft.todayRefreshMinutes) {
                                ForEach(ExportSchedule.todayRefreshMinuteOptions, id: \.self) { minutes in
                                    Text(ExportSchedule.todayRefreshLabel(minutes)).tag(minutes)
                                }
                            }
                        }
                    }

                    if schedulingManager.pendingRecoveryProfileIDs.contains(profile.id) {
                        GlassSectionLabel(title: String(localized: "Pending recovery"))
                        GlassPanel {
                            Button(role: .destructive) {
                                configurationProtection.performConfigurationChange {
                                    showDiscardConfirmation = true
                                }
                            } label: {
                                GlassRow(title: String(localized: "Discard Pending Recovery")) {
                                    Image(systemName: "trash").foregroundStyle(palette.coral)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isDiscardingRecovery)
                            .accessibilityIdentifier("glass.schedule.discardRecovery")
                        }
                    }

                    Text("iOS chooses the exact moment; runs can slip when locked or in Low Power Mode")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                    Text("Scheduled exports need an active trial, subscription or Lifetime access.")
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                }
                .padding(GlassMetrics.screenMargin)
            }
            .tint(palette.accent)
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        configurationProtection.performConfigurationChange {
                            onSave(draft)
                            dismiss()
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("glass.schedule")
        .confirmationDialog(
            "Discard Pending Recovery?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Pending Recovery", role: .destructive, action: discardRecovery)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Discard unresolved scheduled exports for \(profile.name)? Your profile, API credentials, export history, completed files and completed-run progress stay unchanged. No export starts now; an enabled schedule waits for its next ordinary occurrence.")
        }
        .alert("Unable to discard pending recovery", isPresented: $showRecoveryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pending recovery could not be fully cleared. Please try again. Your profile and credentials were not removed.")
        }
        .overlay(alignment: .top) {
            ConfigurationProtectionToast(configurationProtection: configurationProtection)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil { dismiss() }
        }
    }

    /// Protection may have been enabled while the confirmation was open.
    private func discardRecovery() {
        configurationProtection.performConfigurationChange {
            isDiscardingRecovery = true
            defer { isDiscardingRecovery = false }
            do {
                try schedulingManager.discardPendingRecovery(profileID: profile.id)
                _ = entryStore.allEntries()
            } catch {
                showRecoveryError = true
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).glassFont(.body).foregroundStyle(palette.text)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
            .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
    }

    private var timeLabel: String {
        ExportProfileCadenceSummary.timeLabel(
            hour: draft.preferredHour,
            minute: draft.preferredMinute,
            locale: .current
        )
    }

    private var time: Binding<Date> {
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
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.preferredHour = parts.hour ?? 8
                draft.preferredMinute = parts.minute ?? 0
            }
        )
    }
}
#endif
