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
        let dates = ExportOrchestrator.dateRange(from: start, to: end)

        // Hard cap to keep an intent run from spiraling — anything past a year
        // is almost certainly a malformed shortcut.
        guard dates.count <= 366 else {
            return .result(dialog: "Range too large. Please choose 366 days or fewer.")
        }

        let outcome = await ExportIntentRunner.run(dates: dates)
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
