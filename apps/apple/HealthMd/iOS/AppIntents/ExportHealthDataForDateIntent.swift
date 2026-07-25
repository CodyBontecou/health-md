import AppIntents
import Foundation

/// Exports a single specific day's health data. Useful for back-filling a
/// missed day or piping a date computed elsewhere in a Shortcut into Health.md.
struct ExportHealthDataForDateIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Health Data for a Date"

    static var description = IntentDescription(
        "Exports a single day's health data to your Health.md vault.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Date",
        description: "The day to export. Time-of-day is ignored."
    )
    var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Export health data for \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let day = Calendar.current.startOfDay(for: date)
        let outcome = await ExportIntentRunner.run(dates: [day])
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
