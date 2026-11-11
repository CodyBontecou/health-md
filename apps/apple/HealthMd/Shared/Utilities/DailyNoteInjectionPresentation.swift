import Foundation

/// Display-only copy. Never owns, normalizes, or changes settings or preview paths.
nonisolated struct DailyNoteInjectionPresentation: Sendable {
    let statusTitle: String
    let headerLabel: String
    let toggleHint: String
    let modeExplanation: String
    let metricsTitle: String
    let metricsAccessibilityValue: String

    init(isEnabled: Bool, dailyNotesOnly: Bool, metricCount: Int,
         bundle: Bundle = .main, locale: Locale = .current) {
        statusTitle = isEnabled
            ? String(localized: "Enabled", bundle: bundle, locale: locale)
            : String(localized: "Disabled", bundle: bundle, locale: locale)
        headerLabel = String(localized: "Daily Note Injection, \(statusTitle)", bundle: bundle, locale: locale)
        toggleHint = isEnabled
            ? String(localized: "Double tap to disable daily note injection", bundle: bundle, locale: locale)
            : String(localized: "Double tap to enable daily note injection", bundle: bundle, locale: locale)
        modeExplanation = dailyNotesOnly
            ? String(localized: "Exports update only your daily notes. Other generated files stay configured but are skipped.", bundle: bundle, locale: locale)
            : String(localized: "Exports update YAML frontmatter in the daily notes you already keep, while normal export files still follow your selected formats.", bundle: bundle, locale: locale)
        metricsTitle = metricCount == 0
            ? String(localized: "No Metrics", bundle: bundle, locale: locale)
            : String(localized: "\(metricCount) metrics", bundle: bundle, locale: locale)
        metricsAccessibilityValue = metricCount == 0
            ? String(localized: "No metrics enabled", bundle: bundle, locale: locale)
            : String(localized: "\(metricCount) metrics enabled", bundle: bundle, locale: locale)
    }

    static func vaultRootWarning(_ healthSubfolder: String,
                                 bundle: Bundle = .main, locale: Locale = .current) -> String {
        String(localized: "With Folder set to Daily, notes are written to Daily/… at the vault root, not \(healthSubfolder)/Daily/….", bundle: bundle, locale: locale)
    }
}
