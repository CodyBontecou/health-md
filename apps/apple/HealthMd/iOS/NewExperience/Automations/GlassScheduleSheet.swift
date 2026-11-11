#if os(iOS)
import SwiftUI

/// ScheduleG. Same fields and save path as `ProfileScheduleEditorSheet`, plus the same
/// pending-recovery discard as `ProfileScheduleSection`. A pushed page that saves as it
/// changes (`onSave` runs for each saved edit); where a caller can only present a sheet,
/// wrap it in `GlassPageSheet`.
struct GlassScheduleSheet: View {
    let profile: ExportProfile
    let entryStore: ScheduledExportEntryStore
    let onSave: (ScheduledExportEntry) -> Void

    /// The scheduling guide's section on what iOS does and does not guarantee.
    static let backgroundTimingURL = URL(
        string: "https://healthmd.app/docs/scheduling/#what-ios-does-and-does-not-guarantee"
    )!

    private enum ExpandedPicker { case start, time }

    @Environment(\.glassPalette) private var palette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var draft: ScheduledExportEntry
    @State private var expandedPicker: ExpandedPicker?
    @State private var pendingRecoveryRange: String?
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
        // No entry means no schedule: start the draft off so the toggle tells the truth.
        // Autosave takes the first value as its baseline, so an "on" draft here was
        // shown as scheduled yet never saved; turning it on is now a real change.
        _draft = State(initialValue: entry ?? ScheduledExportEntry(
            profileID: profile.id,
            isEnabled: false,
            frequency: .daily
        ))
    }

    private var hasPendingRecovery: Bool {
        schedulingManager.pendingRecoveryProfileIDs.contains(profile.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                section(nil) {
                    GlassToggleRow(
                        title: String(localized: "Run on a schedule"),
                        subtitle: String(localized: "Runs even when this screen is closed"),
                        isOn: Binding(get: { draft.isEnabled }, set: setEnabled)
                    )
                    .accessibilityIdentifier("glass.schedule.enabled")
                }

                section(String(localized: "When")) { whenRows }

                VStack(alignment: .leading, spacing: 6) {
                    section(String(localized: "Today")) { todayRows }
                    // Today Refresh resends the current day's complete snapshot
                    // (docs/features/api-endpoint-export.md), so receivers must upsert.
                    if profile.target == .apiEndpoint {
                        footnote(String(localized: "API profiles resend a full JSON snapshot each refresh — your endpoint should replace or upsert."))
                    }
                }

                if hasPendingRecovery { pendingRecoveryCard }

                VStack(alignment: .leading, spacing: 6) {
                    section(nil) {
                        Button {
                            openURL(Self.backgroundTimingURL)
                        } label: {
                            GlassRow(
                                title: String(localized: "Background timing"),
                                subtitle: String(localized: "iOS chooses the exact moment; runs can slip when locked or in Low Power Mode")
                            ) { chevron }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isLink)
                        .accessibilityIdentifier("glass.schedule.backgroundTiming")
                    }
                    footnote(String(localized: "Scheduled exports need an active trial, subscription or Lifetime access."))
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .accessibilityIdentifier("glass.schedule.content")
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Schedule"))
        .navigationBarTitleDisplayMode(.inline)
        .glassAutosave(draft, revert: { draft = $0 }, save: onSave)
        .task(id: schedulingManager.pendingRecoveryProfileIDs) { refreshPendingRecoveryRange() }
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
    }

    /// "Run on a schedule" passes the lock first: while settings are locked the switch
    /// stays put and nothing else happens. Otherwise it carries the former master
    /// switch's side effects, judged with this draft in place.
    private func setEnabled(_ isEnabled: Bool) {
        guard isEnabled != draft.isEnabled else { return }
        configurationProtection.performConfigurationChange {
            draft.isEnabled = isEnabled
            let others = entryStore.entries.filter { $0.profileID != profile.id }
            AutomationScheduleSwitch.didSwitch(
                isEnabled: isEnabled,
                entries: others + [draft],
                schedulingManager: schedulingManager
            )
        }
    }

    // MARK: - When

    @ViewBuilder private var whenRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            label(String(localized: "Repeat"))
            GlassSegmentedControl(
                segments: ScheduleFrequency.allCases.map { .init(value: $0, title: $0.description) },
                selection: frequency
            )
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 12)

        if draft.frequency == .weekly {
            divider
            GlassRow(title: String(localized: "Day")) {
                menuPicker(String(localized: "Day"), selection: $draft.weekday, values: Array(1...7)) {
                    ExportProfileCadenceSummary.weekdayName($0)
                }
            }
        }

        if draft.frequency == .custom {
            divider
            // "− 3 days +": the unit sits inside the capsule and opens a menu of units.
            GlassRow(title: String(localized: "Every")) {
                GlassCountStepper(
                    title: String(localized: "Every"),
                    value: $draft.customInterval,
                    range: 1...365,
                    valueText: ScheduleSheetCopy.count(draft.customInterval, unit: draft.customUnit),
                    unit: GlassCountStepper.UnitChoice(
                        title: String(localized: "Unit"),
                        selection: $draft.customUnit,
                        values: ScheduleIntervalUnit.allCases,
                        label: { ScheduleDisplayCopy.unitChoiceLabel($0) }
                    )
                )
            }
            divider
            // The first day and repeating phase of the custom cadence (`customAnchorDate`).
            disclosureRow(
                String(localized: "Starting"),
                value: draft.customAnchorDate.formatted(date: .abbreviated, time: .omitted),
                picker: .start,
                identifier: "glass.schedule.starting"
            )
            if expandedPicker == .start {
                DatePicker(String(localized: "Starting"), selection: startDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, GlassMetrics.panelPadding)
            }
        }

        divider
        disclosureRow(
            String(localized: "Preferred time"),
            value: timeLabel,
            picker: .time,
            identifier: "glass.schedule.preferredTime"
        )
        if expandedPicker == .time {
            DatePicker(String(localized: "Preferred time"), selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
        }

        divider
        GlassRow(
            title: String(localized: "Look back"),
            subtitle: String(localized: "Re-exports recent days to catch late data")
        ) {
            GlassCountStepper(
                title: String(localized: "Look back"),
                value: $draft.lookbackDays,
                range: ExportSchedule.minimumLookbackDays...ExportSchedule.maximumLookbackDays,
                valueText: ScheduleSheetCopy.count(draft.lookbackDays, unit: .day)
            )
        }

        divider
        GlassToggleRow(
            title: String(localized: "Include today"),
            subtitle: String(localized: "End each range on today instead of yesterday"),
            isOn: $draft.includeToday
        )
    }

    // MARK: - Today

    @ViewBuilder private var todayRows: some View {
        GlassToggleRow(
            title: String(localized: "Refresh today"),
            subtitle: String(localized: "Keeps today’s partial file fresh"),
            isOn: $draft.todayRefreshEnabled
        )
        .accessibilityIdentifier("glass.schedule.todayRefresh")

        if draft.todayRefreshEnabled {
            divider
            VStack(alignment: .leading, spacing: 8) {
                label(String(localized: "Every"))
                GlassSegmentedControl(
                    segments: ExportSchedule.todayRefreshMinuteOptions.map {
                        .init(value: $0, title: ScheduleSheetCopy.refreshChipTitle(minutes: $0))
                    },
                    selection: $draft.todayRefreshMinutes
                )
                // The chips abbreviate; VoiceOver and UI tests read the full interval.
                .accessibilityRepresentation {
                    Picker(String(localized: "Refresh Interval"), selection: $draft.todayRefreshMinutes) {
                        ForEach(ExportSchedule.todayRefreshMinuteOptions, id: \.self) { minutes in
                            Text(ExportSchedule.todayRefreshLabel(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .accessibilityIdentifier("glass.schedule.refreshInterval")
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Pending recovery

    private var pendingRecoveryCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .foregroundStyle(palette.coral)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Pending recovery"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(ScheduleSheetCopy.pendingRecoveryMessage(range: pendingRecoveryRange))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    configurationProtection.performConfigurationChange {
                        showDiscardConfirmation = true
                    }
                } label: {
                    Text(String(localized: "Discard pending recovery"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .frame(minHeight: GlassMetrics.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDiscardingRecovery)
                .accessibilityIdentifier("glass.schedule.discardRecovery")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.panelSmallRadius, style: .continuous)
                .strokeBorder(palette.coral, lineWidth: 1)
        )
    }

    private func refreshPendingRecoveryRange() {
        pendingRecoveryRange = hasPendingRecovery
            ? ScheduleSheetCopy.pendingRecoveryRange(schedulingManager.pendingRecoveryDates(profileID: profile.id))
            : nil
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

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                GlassSectionLabel(title: title)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            GlassPanel {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.vertical, 4)
            }
        }
    }

    private var divider: some View {
        palette.line
            .frame(height: 1)
            .padding(.horizontal, GlassMetrics.panelPadding)
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.muted)
            .accessibilityHidden(true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    private func label(_ text: String) -> some View {
        Text(text).glassFont(.body).foregroundStyle(palette.text)
    }

    private func disclosureRow(
        _ title: String,
        value: String,
        picker: ExpandedPicker,
        identifier: String
    ) -> some View {
        let isExpanded = expandedPicker == picker
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                expandedPicker = isExpanded ? nil : picker
            }
        } label: {
            GlassRow(title: title) {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(isExpanded ? palette.accent : palette.muted)
                chevron.rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func menuPicker<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value],
        name: @escaping (Value) -> String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { Text(name($0)).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(palette.muted)
        .accessibilityLabel(title)
    }

    // MARK: - Bindings

    /// Entering Custom starts its cadence today, matching the schedule settings editor.
    private var frequency: Binding<ScheduleFrequency> {
        Binding(
            get: { draft.frequency },
            set: { newValue in
                if newValue == .custom, draft.frequency != .custom {
                    draft.customAnchorDate = Calendar.current.startOfDay(for: Date())
                }
                draft.frequency = newValue
            }
        )
    }

    private var startDate: Binding<Date> {
        Binding(
            get: { draft.customAnchorDate },
            set: { draft.customAnchorDate = Calendar.current.startOfDay(for: $0) }
        )
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

/// ScheduleG's "− 3 days +" capsule. One adjustable element for VoiceOver. With a unit
/// choice, the value in the middle is also a menu of units, so the unit stays inline.
private struct GlassCountStepper: View {
    struct UnitChoice {
        let title: String
        @Binding var selection: ScheduleIntervalUnit
        let values: [ScheduleIntervalUnit]
        let label: (ScheduleIntervalUnit) -> String
    }

    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let valueText: String
    var unit: UnitChoice?

    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            stepButton("−", delta: -1)
            if let unit {
                Menu {
                    Picker(unit.title, selection: unit.$selection) {
                        ForEach(unit.values, id: \.self) { Text(unit.label($0)).tag($0) }
                    }
                } label: {
                    valueLabel
                }
            } else {
                valueLabel
            }
            stepButton("+", delta: 1)
        }
        .background(Capsule().fill(palette.surface2))
        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
        .frame(minHeight: GlassMetrics.touchTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityActions {
            if let unit {
                ForEach(unit.values.filter { $0 != unit.selection }, id: \.self) { choice in
                    Button(unit.label(choice)) { unit.selection = choice }
                }
            }
        }
    }

    private var valueLabel: some View {
        Text(valueText)
            .font(.system(size: 14, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(palette.text)
            .frame(minWidth: 56)
            .contentShape(Rectangle())
    }

    private func stepButton(_ glyph: String, delta: Int) -> some View {
        Button { step(delta) } label: {
            Text(verbatim: glyph)
                .font(.system(size: 18))
                .frame(width: 38, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text)
        .disabled(!range.contains(value + delta))
    }

    private func step(_ delta: Int) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}
#endif
