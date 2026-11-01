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

        init(formats: [String], dateFormat: String, filename: String, metricCount: Int, dailyNotes: Bool) {
            self.formats = formats.sorted()
            self.dateFormat = dateFormat
            self.filename = filename
            self.metricCount = metricCount
            self.dailyNotes = dailyNotes
        }

        init(_ profile: SharedSetupV2.Profile) {
            self.init(
                formats: profile.export.formats.map(\.rawValue),
                dateFormat: profile.presentation.dateFormat.rawValue,
                filename: profile.export.filenameTemplate,
                metricCount: profile.metrics.enabledIDs.count,
                dailyNotes: profile.dailyNotes.enabled
            )
        }
    }

    enum Field: Equatable {
        case formats, dateFormat, filename, metrics, dailyNotes
    }

    struct Row: Equatable, Identifiable {
        let field: Field
        let before: String
        let after: String
        var id: String { "\(field)" }
    }

    let rows: [Row]

    /// Only fields that differ appear, in the design's order.
    init(current: Facts, incoming: Facts, on: String, off: String) {
        func row(_ field: Field, _ before: String, _ after: String) -> Row? {
            before == after ? nil : Row(field: field, before: before, after: after)
        }
        rows = [
            row(.formats, current.formats.joined(separator: " + "), incoming.formats.joined(separator: " + ")),
            row(.dateFormat, current.dateFormat, incoming.dateFormat),
            row(.filename, current.filename, incoming.filename),
            row(.metrics, "\(current.metricCount)", "\(incoming.metricCount)"),
            row(.dailyNotes, current.dailyNotes ? on : off, incoming.dailyNotes ? on : off)
        ].compactMap { $0 }
    }
}
