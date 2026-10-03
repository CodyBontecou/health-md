import Foundation

/// Pure decision logic behind the interactive Export tab confirmation guard.
///
/// A customer once tapped the All Time preset by accident and started an
/// interactive export of their entire health history; the export saturated the
/// main actor and the app crashed. This helper decides, without touching any UI
/// state, whether the selected range is small enough to export immediately or
/// large enough that the user must confirm the scale first.
///
/// It deliberately knows nothing about SwiftUI so it stays unit-testable and
/// reusable from any presentation that needs the same scale rule.
enum ExportScaleGuard {
    /// Interactive exports spanning more than this many days require confirmation.
    ///
    /// Incident rationale: multi-thousand-day interactive exports (for example
    /// the All Time preset) saturate the main actor for hours and risk jetsam
    /// termination, so a range beyond this size must be an explicit choice.
    /// Ninety days keeps every rolling-review window (7, 30, and 90 days)
    /// prompt-free while catching year-plus and All Time ranges.
    static let confirmationDayThreshold = 90

    /// The measured scale that drives the confirmation copy.
    struct Scale: Equatable {
        /// Inclusive number of calendar days covered by the selected range.
        let dayCount: Int
        /// Rough output estimate shown in the confirmation copy: one item per
        /// day in Daily Notes Only mode, otherwise days multiplied by formats.
        let estimatedFileCount: Int
        /// True when Lossless Health Records is enabled for a range that already
        /// requires confirmation. Lossless exports retain every source record,
        /// so a large lossless export can run for hours and exhaust memory.
        let includesGranularData: Bool
    }

    enum Verdict: Equatable {
        /// The range is small enough to export without confirmation.
        case proceed
        /// The range is large enough that the user must confirm first.
        case confirm(Scale)
    }

    /// Evaluates the selected date range against the confirmation threshold.
    ///
    /// `startDate` and `endDate` may arrive in either order; both endpoints are
    /// included, and a same-day range counts as a single day.
    static func verdict(
        startDate: Date,
        endDate: Date,
        granularDataEnabled: Bool,
        formatCount: Int,
        dailyNotesOnlyMode: Bool,
        calendar: Calendar = .current
    ) -> Verdict {
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let end = calendar.startOfDay(for: max(startDate, endDate))
        let daySpan = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let dayCount = max(daySpan + 1, 1)

        guard dayCount > confirmationDayThreshold else { return .proceed }

        let estimatedFileCount = dailyNotesOnlyMode
            ? dayCount
            : dayCount * max(formatCount, 1)

        return .confirm(Scale(
            dayCount: dayCount,
            estimatedFileCount: estimatedFileCount,
            includesGranularData: granularDataEnabled
        ))
    }
}
