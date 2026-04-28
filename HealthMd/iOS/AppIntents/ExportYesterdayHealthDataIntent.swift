import AppIntents
import Foundation
import os.log

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

    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "ExportIntent")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // PurchaseManager hydrates unlock state asynchronously in its init.
        // When the intent runs in a fresh process, that Task may not have
        // completed yet — await it explicitly before gating.
        await PurchaseManager.shared.refreshStatus()

        guard PurchaseManager.shared.canExport else {
            return .result(dialog: "Free export limit reached. Unlock Health.md in the app to keep exporting.")
        }

        let healthKitManager = HealthKitManager.shared
        let vaultManager = VaultManager()
        let settings = AdvancedExportSettings()

        guard vaultManager.hasVaultAccess else {
            return .result(dialog: "No vault selected. Open Health.md and choose a vault first.")
        }

        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -1, to: Date())!
        )

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()
        defer { vaultManager.stopVaultAccess() }

        let result = await ExportOrchestrator.exportDatesBackground(
            [yesterday],
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        ExportOrchestrator.recordResult(
            result,
            source: .scheduled,
            dateRangeStart: yesterday,
            dateRangeEnd: yesterday
        )

        if result.successCount > 0 {
            PurchaseManager.shared.recordExportUse()
            var schedule = SchedulingManager.shared.schedule
            schedule.updateLastExport()
            SchedulingManager.shared.schedule = schedule
            Self.logger.info("Shortcut export succeeded for \(yesterday)")
            return .result(dialog: "Exported yesterday's health data.")
        }

        let reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
        Self.logger.error("Shortcut export failed: \(reason)")
        return .result(dialog: "Export failed: \(reason)")
    }
}

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
    }
}
