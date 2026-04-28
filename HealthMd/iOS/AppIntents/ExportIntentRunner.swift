import Foundation
import os.log

/// Shared runner for export-style App Intents. Centralizes the paywall gate,
/// vault scope handling, orchestrator call, history recording, free-export
/// accounting, and schedule bookkeeping so each intent can stay short.
@MainActor
enum ExportIntentRunner {
    enum Outcome {
        case success(daysExported: Int)
        case partial(exported: Int, total: Int, reason: String)
        case noVault
        case paywall
        case failure(reason: String)
    }

    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "ExportIntent")

    static func run(dates: [Date], source: ExportSource = .scheduled) async -> Outcome {
        guard !dates.isEmpty else {
            return .failure(reason: "No dates to export")
        }

        await PurchaseManager.shared.refreshStatus()

        guard PurchaseManager.shared.canExport else {
            return .paywall
        }

        let healthKitManager = HealthKitManager.shared
        let vaultManager = VaultManager()
        let settings = AdvancedExportSettings()

        guard vaultManager.hasVaultAccess else {
            return .noVault
        }

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()
        defer { vaultManager.stopVaultAccess() }

        let result = await ExportOrchestrator.exportDatesBackground(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        let sortedDates = dates.sorted()
        ExportOrchestrator.recordResult(
            result,
            source: source,
            dateRangeStart: sortedDates.first!,
            dateRangeEnd: sortedDates.last!
        )

        if result.successCount == 0 {
            let reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
            logger.error("Shortcut export failed: \(reason)")
            return .failure(reason: reason)
        }

        PurchaseManager.shared.recordExportUse()

        // Only mark the schedule's lastExport when yesterday was part of this
        // run — otherwise an arbitrary back-fill export would suppress the
        // next scheduled run.
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        if dates.contains(where: { calendar.isDate($0, inSameDayAs: yesterday) }) {
            var schedule = SchedulingManager.shared.schedule
            schedule.updateLastExport()
            SchedulingManager.shared.schedule = schedule
        }

        if result.successCount == result.totalCount {
            return .success(daysExported: result.successCount)
        }

        let reason = result.primaryFailureReason?.shortDescription ?? "Some days had no data"
        return .partial(
            exported: result.successCount,
            total: result.totalCount,
            reason: reason
        )
    }

    /// Builds a localized dialog string for the outcome. Keeps user-facing
    /// copy consistent across export intents.
    static func dialog(for outcome: Outcome) -> String {
        switch outcome {
        case .success(let days):
            return days == 1
                ? "Exported 1 day of health data."
                : "Exported \(days) days of health data."
        case .partial(let exported, let total, let reason):
            return "Exported \(exported) of \(total) days. \(reason)."
        case .noVault:
            return "No vault selected. Open Health.md and choose a vault first."
        case .paywall:
            return "Free export limit reached. Unlock Health.md in the app to keep exporting."
        case .failure(let reason):
            return "Export failed: \(reason)."
        }
    }
}
