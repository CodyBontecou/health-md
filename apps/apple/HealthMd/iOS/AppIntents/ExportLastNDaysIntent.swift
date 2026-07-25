import AppIntents
import Foundation

/// Exports the last N days ending yesterday (today is excluded since it's
/// incomplete). Useful for "catch up the past week" automations.
struct ExportLastNDaysIntent: AppIntent {
    static let defaultDays = 7

    static var title: LocalizedStringResource = "Export Last N Days of Health Data"

    static var description = IntentDescription(
        "Exports the most recent days of health data, ending yesterday.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Number of Days",
        description: "How many days back to export, ending yesterday.",
        default: 7
    )
    var days: Int

    init() {
        self.days = Self.defaultDays
    }

    init(days: Int) {
        self.days = max(days, 1)
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Export the last \(\.$days) days of health data")
    }

    static func exportDates(
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let requestedDays = max(days, 1)
        let yesterday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let earliest = calendar.date(byAdding: .day, value: -(requestedDays - 1), to: yesterday)!
        var dates: [Date] = []
        var current = earliest

        while current <= yesterday {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dates = Self.exportDates(days: days)
        let outcome = await ExportIntentRunner.run(dates: dates)
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
