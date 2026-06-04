import Foundation
import os.log

/// Shared runner for export-style App Intents. Centralizes the paywall gate,
/// vault scope handling, orchestrator call, history recording, free-export
/// accounting, and schedule bookkeeping so each intent can stay short.
@MainActor
enum ExportIntentRunner {
    enum Outcome {
        case success(daysExported: Int, formatsPerDate: Int)
        case partial(exported: Int, total: Int, formatsPerDate: Int, reason: String)
        case pending(reason: String)
        case noVault
        case paywall
        case failure(reason: String)
    }

    private static let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "ExportIntent")

    struct Dependencies {
        var refreshPurchaseStatus: () async -> Void
        var canExport: () -> Bool
        var trackExportBlockedByQuota: () -> Void
        var hasVaultAccess: () -> Bool
        var refreshVaultAccess: () -> Void
        var startVaultAccess: () -> Void
        var stopVaultAccess: () -> Void
        var targetLabel: () -> String
        var makeSettings: () -> AdvancedExportSettings
        var exportDatesBackground: ([Date], AdvancedExportSettings) async -> ExportOrchestrator.ExportResult
        var recordResult: (ExportOrchestrator.ExportResult, ExportSource, Date, Date, String?) -> Void
        var recordExportUse: () -> Void
        var trackExportSucceeded: (PricingAnalyticsExportMetadata) -> Void
        var updateScheduleLastExport: () -> Void
        var pendingExportStore: PendingExportStoring
        var exportNotificationScheduler: ExportNotificationScheduling
        var now: () -> Date
        var calendar: Calendar

        static func live() -> Self {
            let vaultManager = VaultManager()
            let settings = AdvancedExportSettings()

            return Self(
                refreshPurchaseStatus: {
                    await PurchaseManager.shared.refreshStatus()
                },
                canExport: {
                    PurchaseManager.shared.canExport
                },
                trackExportBlockedByQuota: {
                    PricingAnalyticsClient.shared.trackExportBlockedByQuota(
                        context: .shortcut,
                        targetType: .localFile,
                        quotaState: PurchaseManager.shared.analyticsQuotaState
                    )
                },
                hasVaultAccess: {
                    vaultManager.hasVaultAccess
                },
                refreshVaultAccess: {
                    vaultManager.refreshVaultAccess()
                },
                startVaultAccess: {
                    vaultManager.startVaultAccess()
                },
                stopVaultAccess: {
                    vaultManager.stopVaultAccess()
                },
                targetLabel: {
                    "iPhone: \(vaultManager.vaultName)"
                },
                makeSettings: {
                    settings
                },
                exportDatesBackground: { dates, settings in
                    await ExportOrchestrator.exportDatesBackground(
                        dates,
                        healthKitManager: HealthKitManager.shared,
                        vaultManager: vaultManager,
                        settings: settings
                    )
                },
                recordResult: { result, source, dateRangeStart, dateRangeEnd, targetLabel in
                    ExportOrchestrator.recordResult(
                        result,
                        source: source,
                        dateRangeStart: dateRangeStart,
                        dateRangeEnd: dateRangeEnd,
                        targetLabel: targetLabel
                    )
                },
                recordExportUse: {
                    PurchaseManager.shared.recordExportUse()
                },
                trackExportSucceeded: { metadata in
                    PricingAnalyticsClient.shared.trackExportSucceeded(
                        metadata: metadata,
                        quotaState: PurchaseManager.shared.analyticsQuotaState
                    )
                },
                updateScheduleLastExport: {
                    var schedule = SchedulingManager.shared.schedule
                    schedule.updateLastExport()
                    SchedulingManager.shared.schedule = schedule
                },
                pendingExportStore: PendingExportStore(),
                exportNotificationScheduler: UserNotificationExportScheduler(),
                now: Date.init,
                calendar: .current
            )
        }
    }

    static func run(dates: [Date], source: ExportTriggerSource = .shortcut) async -> Outcome {
        await run(dates: dates, source: source, dependencies: .live())
    }

    static func run(dates: [Date], source: ExportTriggerSource = .shortcut, dependencies: Dependencies) async -> Outcome {
        guard !dates.isEmpty else {
            return .failure(reason: "No dates to export")
        }

        let triggerPolicy = source.policy()

        await dependencies.refreshPurchaseStatus()

        guard dependencies.canExport() else {
            dependencies.trackExportBlockedByQuota()
            return .paywall
        }

        let settings = dependencies.makeSettings()

        guard dependencies.hasVaultAccess() else {
            return .noVault
        }

        dependencies.refreshVaultAccess()
        dependencies.startVaultAccess()
        defer { dependencies.stopVaultAccess() }

        // Shortcuts run without an interactive Mac peer handshake, so they keep
        // the existing local iPhone-vault destination semantics even if the app's
        // manual Export tab is currently set to Connected Mac.
        let result = await dependencies.exportDatesBackground(dates, settings)

        let sortedDates = dates.sorted()

        if result.successCount == 0 {
            let reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
            if result.primaryFailureReason == .deviceLocked {
                let didPersistPendingRequest = await createPendingShortcutRequest(
                    dates: dates,
                    reason: reason,
                    dependencies: dependencies
                )
                guard didPersistPendingRequest else {
                    return .failure(reason: reason)
                }
                return .pending(reason: reason)
            }

            dependencies.recordResult(
                result,
                ExportSource(sourceFamily: triggerPolicy.sourceFamily),
                sortedDates.first!,
                sortedDates.last!,
                dependencies.targetLabel()
            )
            logger.error("Shortcut export failed: \(reason)")
            return .failure(reason: reason)
        }

        dependencies.recordResult(
            result,
            ExportSource(sourceFamily: triggerPolicy.sourceFamily),
            sortedDates.first!,
            sortedDates.last!,
            dependencies.targetLabel()
        )

        if triggerPolicy.shouldRecordQuota(successCount: result.successCount) {
            dependencies.recordExportUse()
        }
        let metadata = PricingAnalyticsExportMetadata(
            targetType: .localFile,
            formatCount: settings.exportFormats.count,
            metricCount: settings.metricSelection.totalEnabledCount,
            dateRangePreset: PricingAnalyticsDateRangePreset.custom,
            startDate: sortedDates.first!,
            endDate: sortedDates.last!
        )
        dependencies.trackExportSucceeded(metadata)

        // Only mark the schedule's lastExport when the trigger policy allows it.
        // Shortcut exports preserve the existing behavior: update only when
        // yesterday was part of the run, so arbitrary back-fill exports do not
        // suppress the next scheduled run.
        if triggerPolicy.shouldUpdateLastExport(
            successCount: result.successCount,
            exportedDates: dates,
            now: dependencies.now(),
            calendar: dependencies.calendar
        ) {
            dependencies.updateScheduleLastExport()
        }

        if result.isFullSuccess {
            return .success(daysExported: result.successCount, formatsPerDate: result.formatsPerDate)
        }

        let reason = result.hasPartialFailures
            ? result.partialFailureSummary
            : (result.primaryFailureReason?.shortDescription ?? "Some days had no data")
        return .partial(
            exported: result.successCount,
            total: result.totalCount,
            formatsPerDate: result.formatsPerDate,
            reason: reason
        )
    }

    private static func createPendingShortcutRequest(
        dates: [Date],
        reason: String,
        dependencies: Dependencies
    ) async -> Bool {
        let request = PendingExportRequest(
            dates: dates,
            source: .shortcut,
            reason: .protectedDataUnavailable,
            notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
            calendar: dependencies.calendar
        )

        do {
            try dependencies.pendingExportStore.upsert(request)
        } catch {
            logger.error("Failed to persist pending Shortcut export: \(error.localizedDescription)")
            return false
        }

        do {
            try await dependencies.exportNotificationScheduler.sendImmediatePendingExportNotification(for: request)
            logger.info("Shortcut export deferred as pending: \(reason)")
        } catch {
            logger.error("Failed to send pending Shortcut export notification: \(error.localizedDescription)")
        }
        return true
    }

    /// Builds a localized dialog string for the outcome. Keeps user-facing
    /// copy consistent across export intents.
    static func dialog(for outcome: Outcome) -> String {
        switch outcome {
        case .success(let days, let formats):
            if formats > 1 {
                let dayWord = days == 1 ? "day" : "days"
                return "Exported \(days) \(dayWord) × \(formats) formats of health data."
            }
            return days == 1
                ? "Exported 1 day of health data."
                : "Exported \(days) days of health data."
        case .partial(let exported, let total, let formats, let reason):
            if formats > 1 {
                return "Exported \(exported) of \(total) days × \(formats) formats. \(reason)."
            }
            return "Exported \(exported) of \(total) days. \(reason)."
        case .pending:
            return "Pending. Unlock your phone and tap the Health.md notification to export."
        case .noVault:
            return "No vault selected. Open Health.md and choose a vault first."
        case .paywall:
            return "Free export limit reached. Unlock Health.md in the app to keep exporting."
        case .failure(let reason):
            return "Export failed: \(reason)."
        }
    }
}
