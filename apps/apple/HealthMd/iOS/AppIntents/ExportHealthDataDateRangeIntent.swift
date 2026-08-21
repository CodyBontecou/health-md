import AppIntents
import Foundation

/// Exports every day in a closed date range. Mirrors the Date Range picker in
/// the app and lets users back-fill arbitrary windows from Shortcuts.
struct ExportHealthDataDateRangeIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Health Data for Date Range"

    static var description = IntentDescription(
        "Exports every day from start to end (inclusive) to your Health.md vault.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    /// Optional export profile name (trimmed, case-insensitive). Empty uses
    /// the active profile once profiles exist.
    @Parameter(
        title: "Profile",
        description: "Name of the export profile to run. Leave empty to use the active profile."
    )
    var profile: String?

    @Parameter(title: "Start Date")
    var startDate: Date

    @Parameter(title: "End Date")
    var endDate: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Export health data from \(\.$startDate) to \(\.$endDate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let end = calendar.startOfDay(for: max(startDate, endDate))
        let dates = ExportOrchestrator.dateRange(from: start, to: end, calendar: calendar)
        let outcome = await ExportIntentRunner.run(dates: dates, profileName: profile)
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
