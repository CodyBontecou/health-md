import AppIntents
import Foundation

/// Exports the last N days, ending yesterday unless Include Today is enabled.
struct ExportLastNDaysIntent: AppIntent {
    static let defaultDays = 7

    static var title: LocalizedStringResource = "Export Last N Days of Health Data"

    static var description = IntentDescription(
        "Exports the most recent days of health data, ending yesterday or optionally today.",
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

    @Parameter(
        title: "Number of Days",
        description: "How many days to export, ending yesterday or today when Include Today is on.",
        default: 7
    )
    var days: Int

    @Parameter(
        title: "Include Today",
        description: "End the selected window today, including today’s incomplete health data.",
        default: false
    )
    var includeToday: Bool

    init() {
        self.includeToday = false
        self.days = Self.defaultDays
    }

    init(days: Int, includeToday: Bool = false) {
        self.includeToday = includeToday
        self.days = max(days, 1)
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Export the last \(\.$days) days of health data") {
            \.$includeToday
            \.$profile
        }
    }

    static func exportDates(
        days: Int,
        includeToday: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let requestedDays = max(days, 1)
        let endDate = calendar.startOfDay(
            for: includeToday ? now : calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let earliest = calendar.date(byAdding: .day, value: -(requestedDays - 1), to: endDate)!
        var dates: [Date] = []
        var current = earliest

        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return dates
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dates = Self.exportDates(days: days, includeToday: includeToday)
        let outcome = await ExportIntentRunner.run(dates: dates, profileName: profile)
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
