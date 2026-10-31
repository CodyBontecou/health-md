import Foundation

/// How one health date stands for one export profile. This describes the health
/// dates covered, not the times exports ran.
enum CoverageStatus: String, Codable, CaseIterable {
    case complete
    case partial
    case missing
    /// The profile's cadence has not covered this date, or it predates known history.
    case notDue
    /// The profile's schedule was paused. Never counted as a gap.
    case paused
    case inProgress
}

/// Who wrote a date most recently. Labels are resolved by the presentation layer.
enum CoverageWriter: String, Codable {
    case schedule
    case manual
    case cli
    case shortcut
}

/// The quality of a date's output. Ordered so that merging can only improve it.
enum CoverageOutcome: Int, Codable, Comparable {
    case failed = 0
    case partial = 1
    case complete = 2

    static func < (lhs: CoverageOutcome, rhs: CoverageOutcome) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A calendar date in the time zone the export ran under, stored as `yyyy-MM-dd`.
/// Export profiles deliberately carry no time zone, so the key is fixed at record
/// time. Keys sort chronologically as plain strings.
enum CoverageDateKey {
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
