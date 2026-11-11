#if os(iOS)
import SwiftUI

/// Which day the composer previews, and how to title it. Pure, so it is unit tested.
enum ComposerPreviewPlan {
    enum Kind: Equatable { case tomorrow, nextRun, yesterday }

    struct Target: Equatable {
        let date: Date
        let kind: Kind
    }

    /// A scheduled run writes the days before its run date (or the run date itself when it
    /// includes today). Future days have no data yet, so the target never passes today.
    static func target(nextRun: Date?, includesToday: Bool, now: Date, calendar: Calendar) -> Target {
        let today = calendar.startOfDay(for: now)
        guard let nextRun else {
            return Target(date: calendar.date(byAdding: .day, value: -1, to: today) ?? today, kind: .yesterday)
        }
        let runDay = calendar.startOfDay(for: nextRun)
        let written = includesToday ? runDay : (calendar.date(byAdding: .day, value: -1, to: runDay) ?? runDay)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return Target(
            date: min(written, today),
            kind: calendar.isDate(runDay, inSameDayAs: tomorrow) ? .tomorrow : .nextRun
        )
    }

    struct Line: Equatable, Identifiable {
        let number: Int
        let text: String
        /// Frontmatter fences, JSON braces and the date key render muted, as on the board.
        let isMeta: Bool
        var id: Int { number }
    }

    /// The first `limit` lines of a rendered file, numbered from 1.
    static func lines(of text: String, limit: Int) -> (lines: [Line], isTruncated: Bool) {
        var all = text.components(separatedBy: "\n")
        while all.last?.isEmpty == true { all.removeLast() }
        let shown = all.prefix(limit).enumerated().map { index, line in
            Line(number: index + 1, text: line, isMeta: isMeta(line))
        }
        return (Array(shown), all.count > limit)
    }

    private static func isMeta(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "{" || trimmed == "}"
            || trimmed.hasPrefix("date:") || trimmed.hasPrefix("\"date\":")
    }
}

/// "Tomorrow's file": the next run's file rendered by the exporter from the day's data so far.
struct ComposerFilePreview: View {
    let settings: ExportSettingsSnapshot
    let entry: ScheduledExportEntry?
    var showsLiveSuffix = false
    var lineLimit = 12

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @State private var rendered: Rendered?
    @State private var isLoading = true

    private struct Rendered: Equatable {
        let lines: [ComposerPreviewPlan.Line]
        let isTruncated: Bool
    }

    private struct LoadKey: Equatable {
        let settings: ExportSettingsSnapshot
        let date: Date
        let isAuthorized: Bool
    }

    private var target: ComposerPreviewPlan.Target {
        let now = Date()
        let nextRun = entry.flatMap { entry -> Date? in
            guard entry.isEnabled else { return nil }
            return ScheduleDateMath.calculateNextRunDate(schedule: entry.dateMathProjection, now: now)
        }
        return ComposerPreviewPlan.target(
            nextRun: nextRun,
            includesToday: entry?.includeToday ?? false,
            now: now,
            calendar: .current
        )
    }

    private var format: ExportFormat? {
        ExportProfileCardSummary.sortedFormats(settings.exportFormats).first
    }

    private var title: String {
        let base: String
        switch target.kind {
        case .tomorrow: base = String(localized: "Tomorrow’s file")
        case .nextRun: base = String(localized: "Next run’s file")
        case .yesterday: base = String(localized: "Yesterday’s file")
        }
        return showsLiveSuffix ? base + " · " + String(localized: "live") : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).glassFont(.caption).foregroundStyle(palette.muted)
                Spacer(minLength: 8)
                if let path = path {
                    Text(verbatim: path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            content
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("glass.composer.file")
        .task(id: LoadKey(settings: settings, date: target.date, isAuthorized: healthKitManager.isAuthorized)) {
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        if let rendered {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rendered.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(line.number)")
                            .foregroundStyle(palette.muted.opacity(0.6))
                            .frame(width: 26, alignment: .trailing)
                            .padding(.trailing, 12)
                        Text(verbatim: line.text)
                            .foregroundStyle(line.isMeta ? palette.muted : palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 22)
                }
                if rendered.isTruncated {
                    Text(verbatim: "…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(palette.muted)
                        .padding(.leading, 38)
                }
            }
            .padding(.trailing, 18)
        } else {
            Text(isLoading
                 ? String(localized: "Rendering…")
                 : String(localized: "Connect Apple Health to see this file rendered."))
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 18)
        }
    }

    private var path: String? {
        guard let format, let defaults = UserDefaults(suiteName: "com.healthmd.glass.output-preview") else { return nil }
        let advanced = AdvancedExportSettings(snapshot: settings, userDefaults: defaults)
        return [
            settings.healthSubfolder,
            advanced.formatFolderPath(for: target.date, format: format),
            advanced.filename(for: target.date, format: format)
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let format, let defaults = UserDefaults(suiteName: "com.healthmd.glass.output-preview") else {
            rendered = nil
            return
        }
        let advanced = AdvancedExportSettings(snapshot: settings, userDefaults: defaults)
        let date = target.date
        var data: HealthData?
        #if DEBUG
        if TestMode.useHealthKitExportPreviewFixtures || MarketingCapture.isActive {
            data = UITestHealthKitFixtures.exportPreviewHealthData(for: date, includeGranularData: false)
        }
        #endif
        if data == nil {
            guard healthKitManager.isAuthorized else {
                rendered = nil
                return
            }
            data = try? await healthKitManager.fetchHealthData(
                for: date,
                detailPolicy: .summary,
                metricSelection: advanced.metricSelection,
                timeZone: advanced.exportTimeZoneOverride ?? .current
            )
        }
        guard !Task.isCancelled else { return }
        guard let data else {
            rendered = nil
            return
        }
        let text = data.export(format: format, settings: advanced)
        let result = ComposerPreviewPlan.lines(of: text, limit: lineLimit)
        rendered = Rendered(lines: result.lines, isTruncated: result.isTruncated)
    }
}
#endif
