import AppIntents
import Foundation

/// Exports the last N days ending yesterday (today is excluded since it's
/// incomplete). Useful for "catch up the past week" automations.
struct ExportLastNDaysIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Last N Days of Health Data"

    static var description = IntentDescription(
        "Exports the most recent days of health data, ending yesterday.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Number of Days",
        description: "How many days back to export, ending yesterday (1–366).",
        default: 7,
        inclusiveRange: (1, 366)
    )
    var days: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Export the last \(\.$days) days of health data")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: Date())!
        )
        let earliest = calendar.date(byAdding: .day, value: -(days - 1), to: yesterday)!
        let dates = ExportOrchestrator.dateRange(from: earliest, to: yesterday)

        let outcome = await ExportIntentRunner.run(dates: dates)
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
