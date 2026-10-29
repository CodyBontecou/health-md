import Foundation

/// Display copy only. Tracking authority, raw identifiers and export previews stay
/// in their existing owners. Names passed here must already be display names.
nonisolated struct IndividualTrackingPresentation: Sendable {
    var bundle: Bundle = .main
    var locale: Locale = .current

    func status(isEnabled: Bool) -> String {
        isEnabled
            ? String(localized: "Enabled", bundle: bundle, locale: locale)
            : String(localized: "Disabled", bundle: bundle, locale: locale)
    }

    func trackedTitle(_ count: Int) -> String {
        String(localized: "\(count) Tracked", bundle: bundle, locale: locale)
    }

    func headerState(isEnabled: Bool, count: Int) -> String {
        guard isEnabled else { return status(isEnabled: false) }
        guard count > 0 else { return String(localized: "Needs Metrics", bundle: bundle, locale: locale) }
        return trackedTitle(count)
    }

    func headerLabel(_ state: String) -> String {
        String(localized: "Individual Entry Tracking, \(state)", bundle: bundle, locale: locale)
    }

    func toggleHint(isEnabled: Bool) -> String {
        isEnabled
            ? String(localized: "Double tap to disable individual entry tracking", bundle: bundle, locale: locale)
            : String(localized: "Double tap to enable individual entry tracking", bundle: bundle, locale: locale)
    }

    func bulkValue(tracksAll: Bool) -> String {
        tracksAll
            ? String(localized: "All tracked", bundle: bundle, locale: locale)
            : String(localized: "Not all tracked", bundle: bundle, locale: locale)
    }

    func bulkHint(hasMetrics: Bool, tracksAll: Bool) -> String {
        guard hasMetrics else { return String(localized: "Enable metrics in Health Metrics first.", bundle: bundle, locale: locale) }
        return tracksAll
            ? String(localized: "Double tap to disable all individual tracking.", bundle: bundle, locale: locale)
            : String(localized: "Double tap to track all enabled metrics individually.", bundle: bundle, locale: locale)
    }

    func bulkSubtitle(total: Int, tracked: Int, tracksAll: Bool) -> String {
        guard total > 0 else {
            return String(localized: "Enable metrics in Health Metrics before choosing individual entries.", bundle: bundle, locale: locale)
        }
        if tracksAll {
            return String(localized: "Switch off to disable individual tracking for all enabled Health Metrics.", bundle: bundle, locale: locale)
        }
        if tracked == 0 {
            return String(localized: "Metrics currently enabled in Health Metrics: \(total).", bundle: bundle, locale: locale)
        }
        return trackedSummary(tracked: tracked, total: total)
    }

    // Label-style counts intentionally avoid count-dependent noun/verb endings.
    func trackedSummary(tracked: Int, total: Int) -> String {
        String(localized: "Tracked: \(tracked) of \(total)", bundle: bundle, locale: locale)
    }

    func categoryLabel(_ displayName: String, tracked: Int, total: Int) -> String {
        String(localized: "\(displayName), tracked: \(tracked) of \(total)", bundle: bundle, locale: locale)
    }

    func expansionHint(isExpanded: Bool) -> String {
        isExpanded
            ? String(localized: "Double tap to collapse this category", bundle: bundle, locale: locale)
            : String(localized: "Double tap to expand this category", bundle: bundle, locale: locale)
    }

    func metricValue(isTracked: Bool) -> String {
        isTracked
            ? String(localized: "Tracked", bundle: bundle, locale: locale)
            : String(localized: "Not tracked", bundle: bundle, locale: locale)
    }

    func metricHint(isTracked: Bool, displayName: String) -> String {
        isTracked
            ? String(localized: "Double tap to stop tracking individual entry files for \(displayName)", bundle: bundle, locale: locale)
            : String(localized: "Double tap to track individual entry files for \(displayName)", bundle: bundle, locale: locale)
    }
}
