import Foundation

/// Display copy only: never changes stored units, intervals, or calendar arithmetic.
/// Date/time arguments are already formatted by the caller and remain verbatim.
enum ScheduleDisplayCopy {
    /// Neutral picker labels, not fragments for assembling cadence sentences.
    nonisolated static func unitChoiceLabel(
        _ unit: ScheduleIntervalUnit,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        switch unit {
        case .day: return String(localized: "Days", bundle: bundle, locale: locale)
        case .week: return String(localized: "Weeks", bundle: bundle, locale: locale)
        case .month: return String(localized: "Months", bundle: bundle, locale: locale)
        }
    }

    nonisolated static func cadence(
        count: Int,
        unit: ScheduleIntervalUnit,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        switch unit {
        case .day:
            return count == 1
                ? String(localized: "Every day", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) days", bundle: bundle, locale: locale)
        case .week:
            return count == 1
                ? String(localized: "Every week", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) weeks", bundle: bundle, locale: locale)
        case .month:
            return count == 1
                ? String(localized: "Every month", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) months", bundle: bundle, locale: locale)
        }
    }

    nonisolated static func cadence(
        count: Int,
        unit: ScheduleIntervalUnit,
        at time: String,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        switch unit {
        case .day:
            return count == 1
                ? String(localized: "Every day at \(time)", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) days at \(time)", bundle: bundle, locale: locale)
        case .week:
            return count == 1
                ? String(localized: "Every week at \(time)", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) weeks at \(time)", bundle: bundle, locale: locale)
        case .month:
            return count == 1
                ? String(localized: "Every month at \(time)", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) months at \(time)", bundle: bundle, locale: locale)
        }
    }

    nonisolated static func cadenceStartingSummary(
        count: Int,
        unit: ScheduleIntervalUnit,
        starting start: String,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        switch unit {
        case .day:
            return count == 1
                ? String(localized: "Every day starting \(start). Monthly schedules use the last day when a month is shorter.", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) days starting \(start). Monthly schedules use the last day when a month is shorter.", bundle: bundle, locale: locale)
        case .week:
            return count == 1
                ? String(localized: "Every week starting \(start). Monthly schedules use the last day when a month is shorter.", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) weeks starting \(start). Monthly schedules use the last day when a month is shorter.", bundle: bundle, locale: locale)
        case .month:
            return count == 1
                ? String(localized: "Every month starting \(start). Monthly schedules use the last day when a month is shorter.", bundle: bundle, locale: locale)
                : String(localized: "Every \(count) months starting \(start). Monthly schedules use the last day when a month is shorter.", bundle: bundle, locale: locale)
        }
    }
}
