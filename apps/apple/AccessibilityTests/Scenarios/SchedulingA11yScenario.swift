#if os(iOS)
import SwiftUI

/// Route: scheduling. Only synthetic values/callbacks; no settings store,
/// protection substitute, scheduler, HealthKit, history, billing or folders.
struct SchedulingA11yScenario: View {
    @Environment(\.locale) private var locale
    @State private var frequency = "Daily"
    @State private var refresh = 3
    @State private var writeMode = "Update"
    @State private var hour = 11
    @State private var minute = 55
    @State private var period = "PM"
    @State private var interval = 364
    @State private var lookback = 1
    @State private var enabled = true
    @State private var preset = "today"
    @State private var start = Date(timeIntervalSince1970: 1_748_736_000)
    @State private var end = Date(timeIntervalSince1970: 1_749_945_600)
    @State private var changes = 0
    @State private var hourChanges = 0
    @State private var minuteChanges = 0
    @State private var periodChanges = 0
    @State private var edits = 0
    @State private var enables = 0
    @State private var deletes = 0
    @State private var clears = 0
    @State private var infos = 0
    @State private var previews = 0
    @State private var exports = 0

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Choices") { choicesPage }
                NavigationLink("Time") { timePage }
                NavigationLink("Profiles") { profilesPage }
                NavigationLink("Dates") { datesPage }
                NavigationLink("Footer") { footerPage }
            }
            .navigationTitle("Scheduling")
        }
    }

    private var profileName: String {
        switch locale.language.languageCode?.identifier {
        case "de": return "Wöchentliche Gesundheitszusammenfassung für die gesamte Familie"
        case "ar": return "الأرشيف الأسبوعي للبيانات الصحية لجميع أفراد العائلة"
        case "ja": return "家族全員の健康データを毎週まとめて保存するためのプロファイル"
        default: return "Weekly archive for a family with a complete descriptive profile name"
        }
    }

    private var choicesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                SchedulingChoicePicker(
                    title: "Frequency", choices: ["Daily", "Weekly", "Custom"].map { SchedulingChoice(value: $0, title: $0) },
                    selection: Binding(get: { frequency }, set: { frequency = $0; changes += 1 })
                )
                .accessibilityIdentifier("scheduling.frequency")
                SchedulingChoicePicker(
                    title: "Today Refresh interval",
                    choices: [3, 6, 12].map { SchedulingChoice(value: $0, title: "Every \($0) hours") },
                    selection: Binding(get: { refresh }, set: { refresh = $0; changes += 1 })
                )
                .accessibilityIdentifier("scheduling.refresh")
                SchedulingChoicePicker(
                    title: "Write Mode", choices: ["Overwrite", "Append", "Update"].map { SchedulingChoice(value: $0, title: $0) },
                    selection: Binding(get: { writeMode }, set: { writeMode = $0; changes += 1 })
                )
                .accessibilityIdentifier("scheduling.writeMode")
                Text(verbatim: "frequency:\(frequency) refresh:\(refresh) mode:\(writeMode) changes:\(changes)")
                    .accessibilityIdentifier("scheduling.choices.state")
            }
            .padding(Spacing.s4)
        }
        .navigationTitle("Choices")
    }

    private var timePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                SchedulingTimeControls(
                    hour: Binding(get: { hour }, set: { hour = $0; hourChanges += 1 }),
                    minute: Binding(get: { minute }, set: { minute = $0; minuteChanges += 1 }),
                    period: Binding(get: { period }, set: { period = $0; periodChanges += 1 }),
                    hourIdentifier: "scheduling.hour", minuteIdentifier: "scheduling.minute", periodIdentifier: "scheduling.period"
                )
                SchedulingNumberControl(title: "Custom frequency interval", value: $interval,
                                        bounds: 1...365, identifier: "scheduling.interval", valueDescription: "Every")
                SchedulingNumberControl(title: "Lookback window", value: $lookback,
                                        bounds: 1...30, identifier: "scheduling.lookback")
                SchedulingInfoButton { infos += 1 }
                Text(verbatim: "hour:\(hour)/\(hourChanges) minute:\(minute)/\(minuteChanges) period:\(period)/\(periodChanges) interval:\(interval) lookback:\(lookback) info:\(infos)")
                    .accessibilityIdentifier("scheduling.time.state")
            }
            .padding(Spacing.s4)
        }
        .navigationTitle("Time")
    }

    private var profilesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                SchedulingProfileRow(
                    name: profileName, summary: "Every 365 months at 23:55. Today Refresh every 12 hours.",
                    isEnabled: Binding(get: { enabled }, set: { enabled = $0; enables += 1 }),
                    identifier: "scheduling.profile", onEdit: { edits += 1 }
                )
                SchedulingProfileManagementAction(icon: "trash", title: "Delete Profile…", isDestructive: true) { deletes += 1 }
                    .accessibilityIdentifier("scheduling.profile.delete")
                SchedulingHistoryHeading(showsClear: true) { clears += 1 }
                Text(verbatim: "edits:\(edits) enables:\(enables) enabled:\(enabled) deletes:\(deletes) clears:\(clears)")
                    .accessibilityIdentifier("scheduling.profile.state")
                SchedulingProfileSummary(
                    name: profileName, destination: "Folder: Synthetic family archive — complete destination name",
                    cadence: "Weekly · Wednesday · 11:55 PM", formats: "Markdown · JSON · CSV · 123 metrics",
                    isActive: true, cadenceColor: .textSecondary
                )
                SchedulingProfileFact(title: "Folder structure", value: "{year}/{month}/{day}/complete-synthetic-archive")
                Text("Callbacks only. Live protection, confirmation and last-profile refusal are separate integration checks.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.s4)
        }
        .navigationTitle("Profiles")
    }

    private var datesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                SchedulingDatePresets(
                    options: [
                        SchedulingDatePreset(value: "today", title: "Today", hint: "Sets the export date range to today.", identifier: "scheduling.date.today"),
                        SchedulingDatePreset(value: "yesterday", title: "Yesterday", hint: "Sets the export date range to yesterday.", identifier: "scheduling.date.yesterday"),
                        SchedulingDatePreset(value: "allTime", title: "All Time", hint: "Sets the export date range to all available health data.", identifier: "scheduling.date.allTime"),
                        SchedulingDatePreset(value: "custom", title: "Custom", hint: "Shows start and end date pickers for a custom export range.", identifier: "scheduling.date.custom")
                    ], selection: preset
                ) { preset = $0; changes += 1 }
                if preset == "custom" {
                    SchedulingLabeledControl(title: "Start Date", value: Text(start, style: .date)) {
                        DatePicker("Start Date", selection: $start, in: ...end, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .accessibilityIdentifier("scheduling.date.start")
                    }
                    SchedulingLabeledControl(title: "End Date", value: Text(end, style: .date)) {
                        DatePicker("End Date", selection: $end, in: start...Date(timeIntervalSince1970: 1_751_328_000), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .accessibilityIdentifier("scheduling.date.end")
                    }
                }
                Text(verbatim: "preset:\(preset) changes:\(changes)")
                    .accessibilityIdentifier("scheduling.dates.state")
            }
            .padding(Spacing.s4)
        }
        .navigationTitle("Dates")
    }

    private var footerPage: some View {
        SchedulingExportScroll(showsFooter: true) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Synthetic export setup. No health data is requested.")
                    .font(Typography.heading24())
                ForEach(0..<8) { _ in
                    Text("The export footer must leave room to read this entire explanation, including in a short landscape window.")
                        .font(Typography.body())
                }
                Text("Last setup explanation")
                    .accessibilityIdentifier("scheduling.footer.lastContent")
                Text(verbatim: "previews:\(previews) exports:\(exports)")
                    .accessibilityIdentifier("scheduling.footer.state")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.s4)
        } footer: {
            SchedulingExportFooter(freeExportsRemaining: 3, freeExportsIdentifier: "scheduling.footer.free") {
                SchedulingExportActions(
                    previewIdentifier: "scheduling.footer.preview", exportIdentifier: "scheduling.footer.export",
                    previewHint: "Synthetic preview callback", exportHint: "Synthetic export callback",
                    onPreview: { previews += 1 }, onExport: { exports += 1 }
                )
            }
        }
        .navigationTitle("Footer")
    }
}
#endif
