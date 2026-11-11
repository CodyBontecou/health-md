import Foundation

/// The "Example" preview on the individual entries page: the path and frontmatter an entry
/// would get with the current settings. Both come from the exporter's own formatters. The
/// example carries no health value, so nothing in it is invented.
struct IndividualEntryExample: Equatable {
    let path: String
    /// Generic entry frontmatter. Workout notes use a richer renderer that needs a real
    /// workout, so they show the path only.
    let frontmatter: String?

    /// Picks the first tracked metric in catalog order, preferring one with generic
    /// frontmatter. Returns nil when the profile tracks nothing individually.
    @MainActor
    static func make(
        settings: IndividualTrackingSnapshot,
        enabledMetricIDs: Set<String>,
        date: Date,
        timeZone: TimeZone = .current
    ) -> IndividualEntryExample? {
        let tracked = HealthMetrics.availableInCurrentBuild.filter {
            enabledMetricIDs.contains($0.id) && settings.metricConfigs[$0.id]?.trackIndividually == true
        }
        guard let metric = tracked.first(where: { $0.id != workoutsMetricID }) ?? tracked.first else { return nil }

        let live = IndividualTrackingSettings()
        settings.apply(to: live)
        let path = [live.folderPath(for: metric), live.filename(for: metric, date: date, time: date, calendarTimeZone: timeZone)]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        guard metric.id != workoutsMetricID else { return IndividualEntryExample(path: path, frontmatter: nil) }
        let sample = IndividualHealthSample(
            metricId: metric.id,
            metricName: metric.name,
            category: metric.category,
            timestamp: date,
            value: NoValue(),
            unit: metric.unit
        )
        let frontmatter = IndividualEntryExporter().previewEntryContent(
            for: sample,
            formatSettings: FormatCustomization(),
            calendarTimeZone: timeZone
        )
        return IndividualEntryExample(path: path, frontmatter: frontmatter)
    }

    private static let workoutsMetricID = "workouts"

    /// Not a Double, Int or String, so the exporter writes no `value:` line.
    private struct NoValue {}
}
