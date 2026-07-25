import AppIntents
import Foundation

/// Toggles the daily/weekly scheduled background export from Shortcuts.
/// Useful for "pause exports while I'm on vacation" or "resume on my first
/// day back" automations.
struct SetScheduledExportEnabledIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Scheduled Export On or Off"

    static var description = IntentDescription(
        "Enables or disables Health.md's automatic background export schedule.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Enabled",
        description: "Whether scheduled background exports should run."
    )
    var enabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set Health.md scheduled export to \(\.$enabled)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        // Scheduled exports are a paid feature — surface that early so the
        // user isn't surprised by silently dropped runs.
        if enabled {
            await PurchaseManager.shared.refreshStatus()
            guard PurchaseManager.shared.isUnlocked else {
                return .result(
                    value: false,
                    dialog: "Scheduled exports require Health.md Unlock. Open the app to upgrade."
                )
            }
        }

        var schedule = SchedulingManager.shared.schedule
        let wasEnabled = schedule.isEnabled
        schedule.isEnabled = enabled
        SchedulingManager.shared.schedule = schedule

        let dialog: String
        if wasEnabled == enabled {
            dialog = enabled
                ? "Scheduled export is already on."
                : "Scheduled export is already off."
        } else {
            dialog = enabled
                ? "Scheduled export turned on."
                : "Scheduled export turned off."
        }

        return .result(value: enabled, dialog: IntentDialog(stringLiteral: dialog))
    }
}
