import AppIntents
import Foundation

/// Exports yesterday's health data on demand. Designed to be invoked from the
/// iOS Shortcuts app — pair with a "Time of Day" personal automation for a
/// daily morning export without opening Health.md.
struct ExportYesterdayHealthDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Yesterday's Health Data"

    static var description = IntentDescription(
        "Exports yesterday's health data to your Health.md vault.",
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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: Date())!
        )

        let outcome = await ExportIntentRunner.run(dates: [yesterday], profileName: profile)
        try ExportIntentRunner.requireNoForegroundTransition(outcome)
        return .result(dialog: IntentDialog(stringLiteral: ExportIntentRunner.dialog(for: outcome)))
    }
}
