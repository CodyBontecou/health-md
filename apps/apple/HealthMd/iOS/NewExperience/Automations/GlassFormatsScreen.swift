#if os(iOS)
import SwiftUI

/// FormatsG: formats, data detail and packaging, saved through the profile editor's
/// coordinator path.
struct GlassFormatsScreen: View {
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @State private var draft: ExportSettingsSnapshot
    @State private var showHelp = false

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        _draft = State(initialValue: profile.settings)
    }

    var body: some View {
        GlassSettingsSheet(
            title: String(localized: "Formats"),
            canSave: draft.hasFileDestinationOutput,
            onSave: { coordinator.saveSettings(draft, for: profile) }
        ) {
            GlassPanel {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    GlassToggleRow(title: format.localizedDisplayName, isOn: binding(format))
                        .disabled(draft.dailyNotesOnlyModeEnabled)
                }
            }
            Button(String(localized: "Which should I use?")) { showHelp = true }
                .buttonStyle(.plain)
                .glassFont(.caption)
                .foregroundStyle(palette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)

            if !draft.hasFileDestinationOutput {
                GlassBanner(
                    title: String(localized: "Select at least one export format, or enable Daily Notes Only."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }

            GlassSectionLabel(title: String(localized: "Data detail"))
            GlassSegmentedControl(segments: detailSegments, selection: detail)
            Text(AppleExportDetailPreset(policy: draft.detailPolicy).localizedDescription)
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
            Text("API and gateway uploads use this setting too.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)

            GlassSectionLabel(title: String(localized: "Packaging"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Daily Notes only"),
                    subtitle: String(localized: "Skip aggregate files, ZIPs, roll-ups, entries and sidecars — settings are kept"),
                    isOn: dailyNotesOnly
                )
                GlassToggleRow(
                    title: String(localized: "Zip export files"),
                    subtitle: String(localized: "One archive instead of loose files"),
                    isOn: $draft.archiveExportFiles
                )
                GlassToggleRow(
                    title: String(localized: "Write data dictionary"),
                    subtitle: String(localized: "Adds health_md_data_dictionary.md"),
                    isOn: $draft.includeDataDictionary
                )
                GlassToggleRow(
                    title: String(localized: "Range summaries"),
                    subtitle: String(localized: "Also write a roll-up for each requested range"),
                    isOn: $draft.generateRangeSummary
                )
                GlassToggleRow(
                    title: String(localized: "Summary only"),
                    isOn: $draft.summaryOnlyExport
                )
            }
        }
        .sheet(isPresented: $showHelp) {
            GlassFormatHelpScreen().glassTheme()
        }
    }

    /// Archive Only stays selectable only for profiles that already use it.
    private var detailSegments: [GlassSegmentedControl<AppleExportDetailPreset>.Segment] {
        var presets: [AppleExportDetailPreset] = [.summary, .detailedTimeSeries, .losslessHealthRecords]
        if draft.detailPolicy == .archiveOnly { presets.append(.archiveOnly) }
        return presets.map { .init(value: $0, title: Self.shortTitle($0)) }
    }

    private static func shortTitle(_ preset: AppleExportDetailPreset) -> String {
        switch preset {
        case .summary: return preset.localizedTitle
        case .detailedTimeSeries: return String(localized: "Time series")
        case .losslessHealthRecords: return String(localized: "Lossless")
        case .archiveOnly: return String(localized: "Archive")
        }
    }

    private var detail: Binding<AppleExportDetailPreset> {
        Binding(
            get: { AppleExportDetailPreset(policy: draft.detailPolicy) },
            set: { draft.detailPolicy = $0.policy }
        )
    }

    /// Daily Notes Only has no effect unless injection is on, so turning it on enables both.
    private var dailyNotesOnly: Binding<Bool> {
        Binding(
            get: { draft.dailyNotesOnlyModeEnabled },
            set: { isOn in
                draft.dailyNoteInjection.dailyNotesOnly = isOn
                if isOn { draft.dailyNoteInjection.enabled = true }
            }
        )
    }

    private func binding(_ format: ExportFormat) -> Binding<Bool> {
        Binding(
            get: { draft.exportFormats.contains(format) },
            set: { isOn in
                if isOn { draft.exportFormats.insert(format) } else { draft.exportFormats.remove(format) }
            }
        )
    }
}

/// FormatHelpG.
struct GlassFormatHelpScreen: View {
    private struct Item: Identifiable {
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let sample: String
        let bestFor: LocalizedStringKey
        var id: String { sample }
    }

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let items = [
        Item(
            title: "Markdown & Obsidian Bases",
            subtitle: "Readable notes and flat properties",
            sample: "sleep_total_hours: 7.2\nsteps: 8412",
            bestFor: "Best for daily notes, Obsidian browsing, and Bases tables. Nested health data is summarized or flattened for easier querying."
        ),
        Item(
            title: "JSON",
            subtitle: "Complete structured data",
            sample: "{ \"sleep\": { \"total_hours\": 7.2 } }",
            bestFor: "Best for backups, automation, and future re-imports. Preserves workouts, route points, timestamped samples, medications, and metadata."
        ),
        Item(
            title: "CSV",
            subtitle: "Spreadsheet-friendly rows",
            sample: "date,metric,value\n2026-10-30,steps,8412",
            bestFor: "Best for spreadsheets and data analysis tools. Nested data is expanded into rows instead of preserved as objects."
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text("Choose the format for your workflow").glassFont(.screenTitle).foregroundStyle(palette.text)
                    Text("All formats share one schema version; they differ in how you read and reuse the data.")
                        .glassFont(.body)
                        .foregroundStyle(palette.sec)
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).glassFont(.navTitle).foregroundStyle(palette.text)
                            Text(item.subtitle).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                            Text(verbatim: item.sample).glassFont(.monoBody).foregroundStyle(palette.sec)
                            Text(item.bestFor).glassFont(.rowSubtitle).foregroundStyle(palette.sec)
                        }
                        .padding(GlassMetrics.panelPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface()
                    }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Formats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}
#endif
