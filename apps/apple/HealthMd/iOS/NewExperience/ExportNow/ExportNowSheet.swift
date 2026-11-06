#if os(iOS)
import SwiftUI

struct ExportNowRequest: Identifiable, Equatable {
    let id = UUID()
    var profileID: UUID?
    var startDate: Date?
    var endDate: Date?
}

enum ExportNowRange: Hashable {
    case yesterday, last7, last30, custom

    var dayCount: Int? {
        switch self {
        case .yesterday: return 1
        case .last7: return 7
        case .last30: return 30
        case .custom: return nil
        }
    }

    /// The completed days a preset covers, ending yesterday. Nil for custom.
    func dates(now: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        guard let days = dayCount else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: -1, to: today),
              let start = calendar.date(byAdding: .day, value: -days, to: today) else { return nil }
        return (start, end)
    }
}

/// ExportNowG's "Will write" line: "About 14 files · 7 days · daily notes updated".
/// Pure. The file count stays "About": no-data days, roll-ups, sidecars and the data
/// dictionary make the real number differ from days × formats.
enum ExportNowWillWrite {
    static func summary(
        dayCount: Int,
        formatCount: Int,
        summaryOnly: Bool,
        dailyNotesOnly: Bool,
        updatesDailyNotes: Bool,
        rangeText: String,
        locale: Locale = .current
    ) -> String {
        if summaryOnly { return String(localized: "1 range summary for \(rangeText)") }
        let days = max(dayCount, 1)
        var parts: [String] = []
        if !dailyNotesOnly {
            let files = days * max(formatCount, 1)
            parts.append(files == 1 ? String(localized: "About 1 file") : String(localized: "About \(files) files"))
        }
        parts.append(ScheduleSheetCopy.count(days, unit: .day, locale: locale))
        if updatesDailyNotes || dailyNotesOnly {
            parts.append(String(localized: "daily notes updated"))
        }
        return parts.joined(separator: " · ")
    }
}

/// ExportNowG. Runs through the same `exportData` path as the existing Export tab. It closes
/// before exporting so the paywall and error sheets owned by `ContentView` can present.
struct ExportNowSheet: View {
    let request: ExportNowRequest
    let profiles: [ArchiveProfile]
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var dateRangePreset: ExportDateRangePreset
    let destinationLabel: String
    let activeProfileID: UUID?
    let onSelectProfile: (UUID) -> Void
    let resolveAllTime: () async -> (start: Date, end: Date)?
    /// ExportPreviewG, pushed inside this sheet. It gets the action its Export runs.
    let preview: (_ onExport: @escaping () -> Void) -> AnyView
    let onExport: () -> Void
    /// LargeConfirmG: the sheet closes first and the shell asks over the Archive.
    let onConfirmLargeExport: (ExportScaleGuard.Scale) -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var range: ExportNowRange = .yesterday
    @State private var showPreview = false

    private var calendar: Calendar { .current }

    private var dayCount: Int {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    if profiles.count > 1 { profileChips }
                    rangeSection
                    summaryToggle
                    willWrite
                    if dayCount >= 30 && !advancedSettings.summaryOnlyExport {
                        GlassBanner(
                            title: String(localized: "Large export."),
                            message: String(localized: "This can take several minutes; keep Health.md open until it finishes."),
                            systemImage: "clock",
                            tone: .warning
                        )
                    }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .safeAreaInset(edge: .bottom) {
                Button(ctaTitle, action: exportTapped)
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .padding(.horizontal, GlassMetrics.screenMargin)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("glass.exportNow.confirm")
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Export now"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                // Export from the preview runs the same checks as this sheet's button.
                preview(exportTapped)
            }
        }
        .glassSheet(palette: palette)
        .onAppear(perform: applyRequest)
    }

    private var profileChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "Profile"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        GlassChip(title: profile.name, isSelected: profile.id == activeProfileID) {
                            configurationProtection.performConfigurationChange {
                                onSelectProfile(profile.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "Dates"))
            GlassSegmentedControl(
                segments: [
                    .init(value: .yesterday, title: ExportDateRangePreset.yesterday.title),
                    .init(value: .last7, title: String(localized: "7 days")),
                    .init(value: .last30, title: String(localized: "30 days")),
                    .init(value: .custom, title: ExportDateRangePreset.custom.title)
                ],
                selection: Binding(get: { range }, set: select),
                accessibilityIdentifierPrefix: "glass.exportNow.range"
            )
            if range == .custom {
                VStack(spacing: 0) {
                    DatePicker(String(localized: "From"), selection: $startDate, in: ...endDate, displayedComponents: .date)
                    DatePicker(String(localized: "To"), selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .padding(.vertical, 6)
                .foregroundStyle(palette.text)
                .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
                HStack(spacing: 8) {
                    GlassChip(title: ExportDateRangePreset.today.title) { selectPreset(.today) }
                    GlassChip(title: ExportDateRangePreset.allTime.title) { selectAllTime() }
                }
            }
            // The sleep day setting (FormatsG) decides which date holds last night; the
            // advice to pick that date only shows while the range leaves it out.
            Group {
                switch (healthKitManager.sleepDayAttribution, rangeIncludesLastNight) {
                case (.nightBegins, false):
                    Text("\(rangeText) · sleep counts noon → noon. For last night, choose Yesterday.")
                case (.nightBegins, true):
                    Text("\(rangeText) · sleep counts noon → noon, so last night is included.")
                case (.morningEnds, false):
                    Text("\(rangeText) · sleep counts on the day you wake. For last night, choose Today.")
                case (.morningEnds, true):
                    Text("\(rangeText) · sleep counts on the day you wake, so last night is included.")
                }
            }
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
        }
    }

    private var summaryToggle: some View {
        Toggle(isOn: Binding(
            get: { advancedSettings.summaryOnlyExport },
            set: { value in
                configurationProtection.performConfigurationChange {
                    advancedSettings.summaryOnlyExport = value
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Range summary only").glassFont(.body).foregroundStyle(palette.text)
                Text("One roll-up file; skips daily files, notes and entries")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
        }
        .toggleStyle(GlassToggleStyle())
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
    }

    private var willWrite: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle(String(localized: "Will write"))
                Spacer()
                Button {
                    showPreview = true
                } label: {
                    Text(verbatim: String(localized: "Preview") + " →")
                        .glassFont(.caption)
                        .foregroundStyle(palette.accent)
                        .frame(minHeight: GlassMetrics.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("glass.exportNow.preview")
            }
            Text(destinationLabel).glassFont(.monoBody).foregroundStyle(palette.muted)
            Text(summaryText).glassFont(.body).foregroundStyle(palette.text)
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).glassFont(.caption).foregroundStyle(palette.muted)
    }

    /// Whether the selected dates hold last night's sleep: yesterday when sleep counts
    /// noon → noon, today when it counts on the day you wake.
    private var rangeIncludesLastNight: Bool {
        let today = calendar.startOfDay(for: Date())
        let night = healthKitManager.sleepDayAttribution == .nightBegins
            ? calendar.date(byAdding: .day, value: -1, to: today) ?? today
            : today
        return calendar.startOfDay(for: startDate) <= night && night <= calendar.startOfDay(for: endDate)
    }

    private var rangeText: String {
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        guard !calendar.isDate(startDate, inSameDayAs: endDate) else {
            return startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "\(start) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var summaryText: String {
        ExportNowWillWrite.summary(
            dayCount: dayCount,
            formatCount: advancedSettings.exportFormats.count,
            summaryOnly: advancedSettings.summaryOnlyExport,
            dailyNotesOnly: advancedSettings.dailyNotesOnlyModeEnabled,
            updatesDailyNotes: updatesDailyNotes,
            rangeText: rangeText
        )
    }

    /// Daily notes are files in a folder; an API or gateway profile never touches them.
    private var updatesDailyNotes: Bool {
        guard advancedSettings.dailyNoteInjection.enabled else { return false }
        if let active = profiles.first(where: { $0.id == activeProfileID }),
           case .endpoint = active.outputPath {
            return false
        }
        return true
    }

    private var ctaTitle: String {
        if advancedSettings.summaryOnlyExport { return String(localized: "Write summary") }
        return range == .yesterday
            ? String(localized: "Export yesterday")
            : String(localized: "Export \(dayCount) days")
    }

    private func applyRequest() {
        if let profileID = request.profileID, profileID != activeProfileID {
            onSelectProfile(profileID)
        }
        if let start = request.startDate, let end = request.endDate {
            range = .custom
            dateRangePreset = .custom
            startDate = start
            endDate = end
        } else {
            select(.yesterday)
        }
    }

    /// The sheet's dates are a one-off choice for this run, not saved configuration,
    /// so Lock configuration never blocks them.
    private func select(_ newRange: ExportNowRange) {
        range = newRange
        guard let dates = newRange.dates(now: Date(), calendar: calendar) else {
            dateRangePreset = .custom
            return
        }
        dateRangePreset = newRange == .yesterday ? .yesterday : .custom
        startDate = dates.start
        endDate = dates.end
    }

    private func selectPreset(_ preset: ExportDateRangePreset) {
        dateRangePreset = preset
        guard let resolved = preset.resolvedRange(currentStartDate: startDate, currentEndDate: endDate) else { return }
        startDate = resolved.startDate
        endDate = resolved.endDate
    }

    private func selectAllTime() {
        dateRangePreset = .allTime
        Task {
            guard let resolved = await resolveAllTime(), dateRangePreset == .allTime else { return }
            startDate = resolved.start
            endDate = resolved.end
        }
    }

    private func exportTapped() {
        let verdict = ExportScaleGuard.verdict(
            startDate: startDate,
            endDate: endDate,
            granularDataEnabled: advancedSettings.effectiveDetailPolicy.includesCanonicalArchive,
            formatCount: advancedSettings.exportFormats.count,
            dailyNotesOnlyMode: advancedSettings.dailyNotesOnlyModeEnabled
        )
        switch verdict {
        case .proceed: closeAndExport()
        case .confirm(let scale):
            dismiss()
            onConfirmLargeExport(scale)
        }
    }

    private func closeAndExport() {
        dismiss()
        onExport()
    }
}
#endif
