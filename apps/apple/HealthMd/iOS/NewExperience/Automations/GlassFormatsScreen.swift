#if os(iOS)
import SwiftUI

/// FormatsG: formats, data detail and packaging. A pushed page that saves as it changes,
/// through the profile editor's coordinator path.
struct GlassFormatsScreen: View {
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var draft: ExportSettingsSnapshot
    @State private var showHelp = false

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        _draft = State(initialValue: profile.settings)
    }

    var body: some View {
        GlassSettingsPage(title: String(localized: "Formats")) {
            GlassSectionLabel(title: String(localized: "Formats"))
            GlassPanel {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    GlassToggleRow(
                        title: format.localizedDisplayName,
                        subtitle: Self.formatDescription(format),
                        isOn: binding(format)
                    )
                    .disabled(draft.dailyNotesOnlyModeEnabled)
                    .accessibilityIdentifier("glass.formats.format.\(String(describing: format))")
                }
                Button { showHelp = true } label: {
                    GlassRow(title: String(localized: "Which should I use?")) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.muted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
            }

            // Not on the board: the old Export tab's Markdown options, kept with the format
            // they shape (CoverageMap maps that tab's settings to FormatsG).
            if draft.exportFormats.contains(.markdown) && !draft.dailyNotesOnlyModeEnabled {
                GlassPanel {
                    GlassToggleRow(
                        title: String(localized: "Include frontmatter metadata"),
                        subtitle: String(localized: "Adds YAML metadata at the top of markdown files"),
                        isOn: $draft.includeMetadata
                    )
                    .accessibilityIdentifier("glass.formats.includeMetadata")
                    GlassToggleRow(
                        title: String(localized: "Group by category"),
                        subtitle: String(localized: "Organizes health data under category headings"),
                        isOn: $draft.groupByCategory
                    )
                    .accessibilityIdentifier("glass.formats.groupByCategory")
                }
            }

            if !draft.hasFileDestinationOutput {
                GlassBanner(
                    title: String(localized: "Select at least one export format, or enable Daily Notes Only."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Data detail")).glassFont(.body).foregroundStyle(palette.text)
                    GlassSegmentedControl(segments: detailSegments, selection: detail)
                    Text(AppleExportDetailPreset(policy: draft.detailPolicy).localizedDescription)
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .padding(.vertical, 12)
                Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
                ExportDetailOverridesSection(policy: $draft.detailPolicy)
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, GlassMetrics.panelPadding)
                Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
                sleepDayRow
            }
            Text("API and gateway uploads use this setting too.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 20)

            GlassSectionLabel(title: String(localized: "Packaging"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Daily notes only"),
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
                // Not on the board as its own row: it only applies to range roll-ups, so it
                // stays reachable beneath Range summaries instead of being dropped.
                if draft.generateRangeSummary || draft.summaryOnlyExport {
                    GlassToggleRow(
                        title: String(localized: "Range summary only"),
                        subtitle: String(localized: "Skips daily export files and writes only the enabled roll-up summaries"),
                        isOn: $draft.summaryOnlyExport
                    )
                    .padding(.leading, 16)
                }
            }
        }
        .glassAutosave(
            draft,
            isValid: draft.hasFileDestinationOutput,
            invalidReason: String(localized: "Select at least one export format, or enable Daily Notes Only."),
            revert: { draft = $0 },
            save: { coordinator.saveSettings($0, for: profile) }
        )
        .sheet(isPresented: $showHelp) {
            GlassFormatHelpScreen().glassTheme()
        }
    }

    /// Issue #104: which date owns a midnight-spanning sleep session. Not on the board; the
    /// old Export tab kept it beside data detail. It is stored on this iPhone, applies to
    /// every capture path and automation, and saves at once rather than with the profile.
    private var sleepDayRow: some View {
        GlassRow(
            title: String(localized: "Sleep day"),
            subtitle: healthKitManager.sleepDayAttribution.localizedDescription
                + " " + String(localized: "Applies to every automation on this iPhone.")
        ) {
            Picker(String(localized: "Sleep day"), selection: Binding(
                get: { healthKitManager.sleepDayAttribution },
                set: { mode in
                    guard mode.isAvailableForShippedProfiles else { return }
                    configurationProtection.performConfigurationChange {
                        healthKitManager.setSleepDayAttribution(mode)
                    }
                }
            )) {
                ForEach(SleepDayAttribution.allCases, id: \.rawValue) { mode in
                    Text(mode.localizedDisplayName).tag(mode)
                        .disabled(!mode.isAvailableForShippedProfiles)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(palette.muted)
            .accessibilityLabel(String(localized: "Sleep day"))
            .accessibilityIdentifier(AccessibilityID.Export.sleepDayAttributionPicker)
        }
    }

    /// Per-format subtitles from FormatsG.
    private static func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .markdown: return String(localized: "Readable notes with flat properties")
        case .obsidianBases: return String(localized: "Database views in Obsidian")
        case .json: return String(localized: "Complete structured data")
        case .csv: return String(localized: "Spreadsheet-friendly rows")
        }
    }

    /// Archive Only stays selectable only for profiles that already use it.
    private var detailSegments: [GlassSegmentedControl<AppleExportDetailPreset>.Segment] {
        var presets: [AppleExportDetailPreset] = [.summary, .detailedTimeSeries, .losslessHealthRecords]
        if draft.detailPolicy.basePolicy == .archiveOnly { presets.append(.archiveOnly) }
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
            set: { draft.detailPolicy = draft.detailPolicy.replacingBase(with: $0.policy) }
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
        let bestFor: String
        var id: String { sample }
    }

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let items = [
        Item(
            title: "Markdown & Obsidian Bases",
            subtitle: "Readable notes and flat properties",
            sample: "sleep_total_hours: 7.2\nsteps: 8412",
            bestFor: String(localized: "Obsidian, journaling, Bases views")
        ),
        Item(
            title: "JSON",
            subtitle: "Complete structured data",
            sample: "{ \"sleep\": { \"total_hours\": 7.2 } }",
            bestFor: String(localized: "Scripts, agents, long-term archives")
        ),
        Item(
            title: "CSV",
            subtitle: "Spreadsheet-friendly rows",
            sample: "date,metric,value\n2026-10-30,steps,8412",
            bestFor: String(localized: "Numbers, Excel, pandas")
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
                            (Text(String(localized: "Best for")).bold() + Text(verbatim: " · " + item.bestFor))
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.sec)
                        }
                        .padding(GlassMetrics.panelPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface()
                    }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Export formats"))
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
