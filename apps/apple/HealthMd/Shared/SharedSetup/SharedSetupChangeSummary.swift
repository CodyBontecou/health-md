import Foundation

/// ImportSetupG's before-and-after list. Read-only: it describes what the review shows,
/// and the full per-profile review stays the authority on what will be applied.
struct SharedSetupChangeSummary: Equatable {
    struct Facts: Equatable {
        var formats: [String]
        var dateFormat: String
        var filename: String
        var metricCount: Int
        var dailyNotes: Bool
        /// Today Refresh interval in minutes; nil when Today Refresh is off.
        var todayRefreshMinutes: Int?

        init(
            formats: [String],
            dateFormat: String,
            filename: String,
            metricCount: Int,
            dailyNotes: Bool,
            todayRefreshMinutes: Int? = nil
        ) {
            self.formats = formats.sorted()
            self.dateFormat = dateFormat
            self.filename = filename
            self.metricCount = metricCount
            self.dailyNotes = dailyNotes
            self.todayRefreshMinutes = todayRefreshMinutes
        }

        init(_ profile: SharedSetupV2.Profile) {
            self.init(
                formats: profile.export.formats.map(\.rawValue),
                dateFormat: profile.presentation.dateFormat.rawValue,
                filename: profile.export.filenameTemplate,
                metricCount: profile.metrics.enabledIDs.count,
                dailyNotes: profile.dailyNotes.enabled,
                todayRefreshMinutes: Self.todayRefreshMinutes(profile)
            )
        }

        /// What applying would set. Only the Apple extension carries Today Refresh, in
        /// whole hours; imports from other platforms leave it off.
        static func todayRefreshMinutes(_ profile: SharedSetupV2.Profile) -> Int? {
            guard let schedule = profile.platformExtensions.apple?.schedule, schedule.todayRefreshRequested else {
                return nil
            }
            return schedule.todayRefreshIntervalHours * 60
        }
    }

    enum Field: Equatable {
        case formats, dateFormat, filename, metrics, todayRefresh, dailyNotes
    }

    struct Row: Equatable, Identifiable {
        let field: Field
        let before: String
        let after: String
        var id: String { "\(field)" }
    }

    let rows: [Row]

    /// Only fields that differ appear, in the design's order.
    init(
        current: Facts,
        incoming: Facts,
        on: String,
        off: String,
        todayRefreshLabel: (Int) -> String = { "\($0) min" }
    ) {
        func refresh(_ minutes: Int?) -> String { minutes.map(todayRefreshLabel) ?? off }
        func row(_ field: Field, _ before: String, _ after: String) -> Row? {
            before == after ? nil : Row(field: field, before: before, after: after)
        }
        rows = [
            row(.formats, current.formats.joined(separator: " + "), incoming.formats.joined(separator: " + ")),
            row(.dateFormat, current.dateFormat, incoming.dateFormat),
            row(.filename, current.filename, incoming.filename),
            row(.metrics, "\(current.metricCount)", "\(incoming.metricCount)"),
            row(.todayRefresh, refresh(current.todayRefreshMinutes), refresh(incoming.todayRefreshMinutes)),
            row(.dailyNotes, current.dailyNotes ? on : off, incoming.dailyNotes ? on : off)
        ].compactMap { $0 }
    }
}
