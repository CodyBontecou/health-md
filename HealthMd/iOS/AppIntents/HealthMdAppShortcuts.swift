import AppIntents

/// Registers Health.md's App Intents with iOS Shortcuts and Siri. Voice
/// phrases are intentionally limited to the three highest-traffic intents to
/// avoid Siri ambiguity — the rest are still available as actions in the
/// Shortcuts app.
struct HealthMdAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportYesterdayHealthDataIntent(),
            phrases: [
                "Export yesterday's health data with \(.applicationName)",
                "Run \(.applicationName) export",
                "\(.applicationName) export yesterday"
            ],
            shortTitle: "Export Yesterday",
            systemImageName: "square.and.arrow.up.on.square"
        )

        AppShortcut(
            intent: ExportLastNDaysIntent(),
            phrases: [
                "Export the last week of health data with \(.applicationName)",
                "Catch up \(.applicationName) export"
            ],
            shortTitle: "Export Last N Days",
            systemImageName: "calendar.badge.clock"
        )

        AppShortcut(
            intent: GetHealthSummaryForDateIntent(),
            phrases: [
                "Get health summary from \(.applicationName)",
                "\(.applicationName) summary"
            ],
            shortTitle: "Get Health Summary",
            systemImageName: "heart.text.square"
        )

        AppShortcut(
            intent: ExportHealthDataForDateIntent(),
            phrases: ["Export a day of health data with \(.applicationName)"],
            shortTitle: "Export a Specific Day",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: ExportHealthDataDateRangeIntent(),
            phrases: ["Export a date range with \(.applicationName)"],
            shortTitle: "Export Date Range",
            systemImageName: "calendar.badge.plus"
        )

        AppShortcut(
            intent: GetLastExportStatusIntent(),
            phrases: ["Check \(.applicationName) export status"],
            shortTitle: "Get Last Export Status",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: SetScheduledExportEnabledIntent(),
            phrases: ["Toggle \(.applicationName) scheduled export"],
            shortTitle: "Set Scheduled Export",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
