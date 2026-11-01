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
    let onPreview: () -> Void
    let onExport: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var range: ExportNowRange = .yesterday
    @State private var pendingScale: ExportScaleGuard.Scale?

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
        }
        .glassSheet(palette: palette)
        .onAppear(perform: applyRequest)
        .geistDialog(
            isPresented: Binding(
                get: { pendingScale != nil },
                set: { if !$0 { pendingScale = nil } }
            ),
            title: Text("Export \(pendingScale?.dayCount ?? 0) days?"),
            message: Text(largeConfirmationMessage),
            actions: [
                .cancel {
                    pendingScale = nil
                },
                .action("Export Anyway") {
                    pendingScale = nil
                    closeAndExport()
                }
            ]
        )
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
                selection: Binding(get: { range }, set: select)
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
            Text("\(rangeText) · sleep counts noon → noon. For last night, choose Yesterday.")
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
                    dismiss()
                    onPreview()
                } label: {
                    Text(verbatim: String(localized: "Preview") + " →")
                        .glassFont(.caption)
                        .foregroundStyle(palette.accent)
                        .frame(minHeight: GlassMetrics.touchTarget)
                }
                .buttonStyle(.plain)
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

    private var rangeText: String {
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        guard !calendar.isDate(startDate, inSameDayAs: endDate) else {
            return startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "\(start) – \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var summaryText: String {
        if advancedSettings.summaryOnlyExport {
            return String(localized: "1 range summary for \(rangeText)")
        }
        let files = dayCount * max(advancedSettings.exportFormats.count, 1)
        return String(localized: "About \(files) file(s) · \(dayCount) day(s)")
    }

    private var ctaTitle: String {
        if advancedSettings.summaryOnlyExport { return String(localized: "Write summary") }
        return range == .yesterday
            ? String(localized: "Export yesterday")
            : String(localized: "Export \(dayCount) days")
    }

    private var largeConfirmationMessage: String {
        guard let scale = pendingScale else { return "" }
        return String(localized: "This export covers \(scale.dayCount) days and writes about \(scale.estimatedFileCount) files. Exports this large can take a long time to finish.")
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

    private func select(_ newRange: ExportNowRange) {
        configurationProtection.performConfigurationChange {
            range = newRange
            guard let days = newRange.dayCount else {
                dateRangePreset = .custom
                return
            }
            if days == 1 {
                selectPreset(.yesterday)
                return
            }
            dateRangePreset = .custom
            let today = calendar.startOfDay(for: Date())
            endDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            startDate = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
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
        case .confirm(let scale): pendingScale = scale
        }
    }

    private func closeAndExport() {
        dismiss()
        onExport()
    }
}
#endif
