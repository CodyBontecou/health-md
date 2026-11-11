import Combine
import Foundation

/// The date range of the Mac export this iPhone started, so MacDestG can say
/// "Exporting Oct 24 – 30 to the Mac…". The Mac's progress messages carry only day
/// counts; the range comes from the job the iPhone built. Nothing is persisted.
@MainActor
final class MacExportRequestRange: ObservableObject {
    static let shared = MacExportRequestRange()

    /// Keep deallocation on the releasing thread, matching the settings-store convention.
    nonisolated deinit {}

    @Published private(set) var jobID: UUID?
    @Published private(set) var startDate: Date?
    @Published private(set) var endDate: Date?

    func update(jobID: UUID?, startDate: Date?, endDate: Date?) {
        self.jobID = jobID
        self.startDate = jobID == nil ? nil : startDate
        self.endDate = jobID == nil ? nil : endDate
    }

    /// The range for `jobID`, or nil when this iPhone did not start that job or has no dates yet.
    func rangeText(for jobID: UUID, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard self.jobID == jobID, let startDate, let endDate else { return nil }
        return Self.rangeText(start: startDate, end: endDate, locale: locale, timeZone: timeZone)
    }

    /// "Oct 24 – 30", "Oct 28 – Nov 3" or "Oct 30" in the user's locale.
    nonisolated static func rangeText(start: Date, end: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        let showsYear = !calendar.isDate(start, equalTo: end, toGranularity: .year)
        formatter.dateTemplate = showsYear ? "yMMMd" : "MMMd"
        return formatter.string(from: min(start, end), to: max(start, end))
    }
}
