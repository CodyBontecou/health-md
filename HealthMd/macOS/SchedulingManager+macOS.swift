#if os(macOS)
import Foundation
import Combine
import ServiceManagement
import UserNotifications
import os.log

/// macOS SchedulingManager — uses in-app Timer + Login Item instead of BGTaskScheduler.
/// The app persists in the menu bar, so a simple timer checks hourly whether an export is due.
///
/// On macOS, scheduled exports read from HealthDataStore (local cache synced from iPhone)
/// rather than HealthKit (which doesn't work on macOS).
@MainActor
class SchedulingManager: ObservableObject {
    static let shared = SchedulingManager()

    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "SchedulingManager-macOS")

    /// Result from a notification-triggered or catch-up export
    @Published var notificationExportResult: NotificationExportResult?

    @Published var schedule: ExportSchedule {
        didSet {
            schedule.save()
            rescheduleTimer()
            if schedule.isEnabled {
                Task { @MainActor in
                    await PushRegistrationManager.shared.registerForRemoteNotificationsIfNeeded()
                }
            }
            PushRegistrationManager.shared.syncSchedule(schedule)
        }
    }

    private var exportTimer: Timer?
    private var isExporting = false
    private let pendingExportStore = PendingExportStore()

    // MARK: - Init

    private init() {
        self.schedule = ExportSchedule.load()
    }

    // MARK: - Timer-based Scheduling

    /// Reschedule the export timer. Call after any schedule change.
    func rescheduleTimer() {
        exportTimer?.invalidate()
        exportTimer = nil

        guard schedule.isEnabled else {
            logger.info("Schedule disabled, timer cancelled")
            return
        }

        // Check every 30 minutes if an export is due
        exportTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performExportIfDue()
            }
        }

        // Also check immediately
        Task {
            await performExportIfDue()
        }

        logger.info("Export timer scheduled (30-min check interval)")
    }

    // MARK: - Login Item

    var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enableLoginItem() {
        do {
            try SMAppService.mainApp.register()
            logger.info("Login item registered")
        } catch {
            logger.error("Failed to register login item: \(error.localizedDescription)")
        }
    }

    func disableLoginItem() {
        do {
            try SMAppService.mainApp.unregister()
            logger.info("Login item unregistered")
        } catch {
            logger.error("Failed to unregister login item: \(error.localizedDescription)")
        }
    }

    // MARK: - Export Logic

    /// Checks if an export is due based on schedule and last export date
    private func performExportIfDue() async {
        guard schedule.isEnabled, !isExporting else { return }

        let calendar = Calendar.current
        let now = Date()

        var preferredComponents = calendar.dateComponents([.year, .month, .day], from: now)
        preferredComponents.hour = schedule.preferredHour
        preferredComponents.minute = schedule.preferredMinute
        preferredComponents.second = 0

        guard let fireDate = calendar.date(from: preferredComponents) else { return }

        guard fireDate <= now else {
            logger.info("Not yet at preferred export time, skipping")
            return
        }

        guard ScheduleDateMath.shouldRunScheduledOccurrence(
            schedule: schedule,
            fireDate: fireDate,
            now: now,
            calendar: calendar
        ) else {
            logger.info("Scheduled occurrence is not due, skipping")
            return
        }

        let eligibleDates = ScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: fireDate,
            calendar: calendar
        )
        guard let eligibleEndDate = eligibleDates.last else { return }

        let hasPendingResidual = (try? pendingExportStore.loadAll().contains {
            $0.source == .scheduled && !$0.dates.isEmpty
        }) ?? false

        // A persisted residual remains due even after the schedule marker moves
        // forward to prevent completed days from being re-expanded.
        if let lastExport = schedule.lastExportDate {
            let lastExportDay = calendar.startOfDay(for: lastExport)
            let lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: lastExportDay) ?? lastExportDay
            if lastExportedDataDay >= eligibleEndDate && !hasPendingResidual {
                return
            }
        }

        logger.info("Export is due, performing catch-up export")
        await performCatchUpExport()
    }

    /// Performs catch-up export for any missed days using HealthDataStore (local cache).
    private func performCatchUpExport() async {
        guard !isExporting else {
            logger.info("Export already in progress, skipping")
            return
        }

        isExporting = true
        defer { isExporting = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let oldestDateToExport: Date
        if schedule.frequency == .weekly {
            oldestDateToExport = calendar.date(byAdding: .day, value: -7, to: today)!
        } else {
            oldestDateToExport = yesterday
        }

        // Determine what dates need exporting
        let lastExportedDataDay: Date
        if let lastExport = schedule.lastExportDate {
            let exportRunDay = calendar.startOfDay(for: lastExport)
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: exportRunDay)!
        } else {
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: oldestDateToExport)!
        }

        let existingPendingRequest = try? pendingExportStore.loadAll()
            .filter { $0.source == .scheduled }
            .sorted { $0.createdAt < $1.createdAt }
            .first
        guard lastExportedDataDay < yesterday || existingPendingRequest != nil else {
            logger.info("All data up to date")
            return
        }

        let newlyDueDates: [Date]
        if lastExportedDataDay < yesterday {
            let dayAfterLastExport = calendar.date(byAdding: .day, value: 1, to: lastExportedDataDay)!
            newlyDueDates = ExportOrchestrator.dateRange(
                from: max(dayAfterLastExport, oldestDateToExport),
                to: yesterday
            )
        } else {
            newlyDueDates = []
        }
        let dates = Array(Set((existingPendingRequest?.dates ?? []) + newlyDueDates)).sorted()

        guard !dates.isEmpty else {
            logger.info("No dates to export")
            return
        }

        logger.info("Catch-up export: \(dates.count) day(s)")

        // Use HealthDataStore (local cache) instead of HealthKitManager
        let healthDataStore = HealthDataStore()
        let vaultManager = VaultManager()
        let settings = AdvancedExportSettings()

        vaultManager.refreshVaultAccess()
        guard vaultManager.hasVaultAccess else {
            logger.error("No vault access")
            let body = vaultManager.hasSavedVaultFolder
                ? String(localized: "Could not access the selected export folder. Reconnect or re-select it in Health.md.", comment: "Vault unavailable notification body")
                : String(localized: "No export folder selected. Open Health.md to choose one.", comment: "No vault access notification body")
            await sendNotification(
                title: String(localized: "Export Failed", comment: "Notification title"),
                body: body
            )
            return
        }

        guard vaultManager.startVaultAccess() else {
            logger.error("Could not start vault security scope")
            await sendNotification(
                title: String(localized: "Export Failed", comment: "Notification title"),
                body: String(localized: "Could not access the selected export folder. Reconnect or re-select it in Health.md.", comment: "Vault access denied notification body")
            )
            return
        }

        var successCount = 0
        var completedDates: [Date] = []
        var failedDateDetails: [FailedDateDetail] = []
        var successfulHealthData: [HealthData] = []
        var rollupFileCount = 0
        var archiveCount = 0
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        let requiresDerivedOutput = settings.archiveModeEnabled || settings.summaryOnlyModeEnabled

        for date in dates {
            guard let healthData = healthDataStore.fetchHealthData(for: date) else {
                // Mac cache absence is retryable: iPhone sync may populate it later.
                failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                continue
            }

            if !healthData.hasAnyData {
                failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                continue
            }

            do {
                let writeResult = try vaultManager.exportHealthDataResult(
                    healthData,
                    for: date,
                    settings: settings
                )
                dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                dailyNoteSkipCount += writeResult.dailyNoteSkippedCount
                if settings.dailyNotesOnlyModeEnabled {
                    switch writeResult.dailyNoteResult {
                    case .updated:
                        break
                    case .skipped(let reason):
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .noHealthData,
                            errorDetails: reason
                        ))
                        completedDates.append(date)
                        continue
                    case .failed(let error):
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .fileWriteError,
                            errorDetails: error.localizedDescription
                        ))
                        continue
                    case .none:
                        failedDateDetails.append(FailedDateDetail(
                            date: date,
                            reason: .fileWriteError,
                            errorDetails: "Daily note update was not performed."
                        ))
                        continue
                    }
                }
                successCount += 1
                successfulHealthData.append(healthData)
                if !requiresDerivedOutput {
                    completedDates.append(date)
                }
            } catch {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: .fileWriteError,
                    errorDetails: error.localizedDescription
                ))
            }
        }

        var rollupHealthData = successfulHealthData
        let retainedRollupDays = Set(rollupHealthData.map { calendar.startOfDay(for: $0.date) })
        for rollupDate in ExportOrchestrator.rollupSourceDates(for: dates, settings: settings)
            where !retainedRollupDays.contains(calendar.startOfDay(for: rollupDate)) {
            if let data = healthDataStore.fetchHealthData(for: rollupDate), data.hasAnyData {
                rollupHealthData.append(data)
            }
        }

        if settings.archiveModeEnabled && !successfulHealthData.isEmpty {
            do {
                if try await vaultManager.exportArchive(
                    from: successfulHealthData,
                    rollupHealthData: rollupHealthData,
                    settings: settings,
                    startDate: dates.first ?? yesterday,
                    endDate: dates.last ?? yesterday
                ) != nil {
                    archiveCount = 1
                    completedDates.append(contentsOf: successfulHealthData.map(\.date))
                } else {
                    throw ExportError.noHealthData
                }
            } catch {
                failedDateDetails.append(contentsOf: successfulHealthData.map {
                    FailedDateDetail(date: $0.date, reason: .fileWriteError, errorDetails: error.localizedDescription)
                })
                successCount = 0
            }
        } else if settings.summaryOnlyModeEnabled && !successfulHealthData.isEmpty {
            do {
                let results = try vaultManager.exportRollupSummaries(
                    from: rollupHealthData,
                    settings: settings
                )
                if results.isEmpty {
                    failedDateDetails.append(contentsOf: successfulHealthData.map {
                        FailedDateDetail(date: $0.date, reason: .noHealthData)
                    })
                    successCount = 0
                } else {
                    rollupFileCount = results.count
                }
                completedDates.append(contentsOf: successfulHealthData.map(\.date))
            } catch {
                failedDateDetails.append(contentsOf: successfulHealthData.map {
                    FailedDateDetail(date: $0.date, reason: .fileWriteError, errorDetails: error.localizedDescription)
                })
                successCount = 0
            }
        }

        vaultManager.stopVaultAccess()

        let result = ExportOrchestrator.ExportResult(
            successCount: successCount,
            totalCount: dates.count,
            failedDateDetails: failedDateDetails,
            formatsPerDate: settings.looseFormatsPerDate,
            rollupFileCount: rollupFileCount,
            archiveCount: archiveCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            completedDates: completedDates
        )
        let originalRequest: PendingExportRequest
        if let existingPendingRequest {
            originalRequest = PendingExportRequest(
                id: existingPendingRequest.id,
                dates: dates,
                source: existingPendingRequest.source,
                scheduledFireDate: existingPendingRequest.scheduledFireDate,
                scheduledKind: existingPendingRequest.scheduledKind,
                createdAt: existingPendingRequest.createdAt,
                notificationMetadata: existingPendingRequest.notificationMetadata,
                exportTarget: existingPendingRequest.exportTarget,
                calendar: calendar
            )
        } else {
            originalRequest = PendingExportRequest(
                dates: dates,
                source: .scheduled,
                scheduledFireDate: today,
                createdAt: Date(),
                notificationMetadata: ["notification": ExportNotificationType.pendingExport.rawValue],
                exportTarget: .localIPhoneFolder,
                calendar: calendar
            )
        }
        let remainingDates = result.remainingDates(from: originalRequest.dates, calendar: calendar)
            ?? originalRequest.dates
        var didPersistReconciliation = false
        if remainingDates.isEmpty {
            do {
                try pendingExportStore.remove(id: originalRequest.id)
                didPersistReconciliation = true
            } catch {
                logger.error("Could not clear completed Mac schedule: \(error.localizedDescription)")
            }
        } else {
            let retryRequest = PendingExportRequest(
                id: originalRequest.id,
                dates: remainingDates,
                source: originalRequest.source,
                scheduledFireDate: originalRequest.scheduledFireDate,
                scheduledKind: originalRequest.scheduledKind,
                createdAt: originalRequest.createdAt,
                notificationMetadata: originalRequest.notificationMetadata,
                exportTarget: originalRequest.exportTarget,
                calendar: calendar
            )
            do {
                try pendingExportStore.upsert(retryRequest)
                didPersistReconciliation = true
            } catch {
                logger.error("Could not save remaining Mac schedule dates: \(error.localizedDescription)")
            }
        }
        if didPersistReconciliation {
            // The residual request is now the source of truth for gaps, so the
            // scalar marker can advance without re-expanding completed dates.
            var updatedSchedule = schedule
            updatedSchedule.updateLastExport()
            schedule = updatedSchedule
        }

        if result.successCount > 0 || result.dailyNoteSkipCount > 0 {
            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: dates.first!,
                dateRangeEnd: dates.last!
            )

            let completedDailyNoteBody: String? = if result.dailyNoteSkipCount > 0 && remainingDates.isEmpty {
                result.dailyNoteUpdateCount == 0
                    ? String(localized: "Skipped \(result.dailyNoteSkipCount) missing daily note(s); no export files were created.", comment: "Mac daily note terminal skip notification body")
                    : String(localized: "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) daily note(s); no export files were created.", comment: "Mac daily note mixed completion notification body")
            } else {
                nil
            }
            await sendNotification(
                title: completedDailyNoteBody != nil
                    ? String(localized: "Daily Notes Completed", comment: "Mac daily note terminal skip notification title")
                    : (remainingDates.isEmpty
                        ? String(localized: "Export Complete", comment: "Notification title")
                        : String(localized: "Health Export Needs Attention", comment: "Partial export notification title")),
                body: completedDailyNoteBody ?? (remainingDates.isEmpty
                    ? String(localized: "Exported \(result.successCount) day(s) of health data.", comment: "Export success notification body")
                    : String(localized: "Exported \(result.successCount)/\(result.totalCount) days. Open Health.md to retry the remaining dates.", comment: "Partial export notification body"))
            )

            logger.info("Catch-up export done: \(result.successCount)/\(result.totalCount)")
        } else if !remainingDates.isEmpty && result.completedDateCount > 0 {
            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: dates.first!,
                dateRangeEnd: dates.last!
            )
            await sendNotification(
                title: String(localized: "Health Export Needs Attention", comment: "Partial export notification title"),
                body: String(localized: "Some dates had no synced data and other dates remain. Open Health.md to retry.", comment: "No-data partial export notification body")
            )
            logger.info("Catch-up export retained \(remainingDates.count) unresolved date(s)")
        } else {
            let reason = result.primaryFailureReason?.shortDescription ?? String(localized: "No synced data available", comment: "Default failure reason")
            await sendNotification(
                title: String(localized: "Export Failed", comment: "Notification title"),
                body: String(localized: "\(reason). Sync from your iPhone first.", comment: "Export failure notification body")
            )
            logger.error("Catch-up export failed: \(reason)")
        }
    }

    /// Performs catch-up when app becomes active
    func performCatchUpExportIfNeeded() async {
        guard schedule.isEnabled else { return }
        await performExportIfDue()
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.codybontecou.healthmd.export.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Notification sent: \(title)")
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper

    /// Human-readable description of the next scheduled export
    func getNextExportDescription() -> String? {
        guard schedule.isEnabled else { return nil }

        let calendar = Calendar.current
        let now = Date()

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = schedule.preferredHour
        components.minute = schedule.preferredMinute

        guard var nextDate = calendar.date(from: components) else { return nil }

        if nextDate <= now {
            switch schedule.frequency {
            case .daily:
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate)!
            case .weekly:
                nextDate = calendar.date(byAdding: .day, value: 7, to: nextDate)!
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: nextDate)
    }

    /// Requests notification permissions
    func requestNotificationPermissions() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            return false
        }
    }
}

/// Result of a notification-triggered export (shared type name, macOS implementation)
struct NotificationExportResult: Equatable {
    enum Status: Equatable {
        case success(daysExported: Int)
        case partialSuccess(exported: Int, total: Int)
        case failure(reason: String)
        case noExportNeeded
    }

    let status: Status
    let timestamp: Date

    var title: String {
        switch status {
        case .success:         return String(localized: "Export Completed", comment: "Export result title")
        case .partialSuccess:  return String(localized: "Partial Export", comment: "Export result title")
        case .failure:         return String(localized: "Export Failed", comment: "Export result title")
        case .noExportNeeded:  return String(localized: "Up to Date", comment: "Export result title")
        }
    }

    var message: String {
        switch status {
        case .success(let days):
            return days == 1
                ? String(localized: "Successfully exported yesterday's health data", comment: "Export success message")
                : String(localized: "Successfully exported \(days) days of health data", comment: "Export success message")
        case .partialSuccess(let exported, let total):
            return String(localized: "Exported \(exported) of \(total) days", comment: "Partial export message")
        case .failure(let reason):
            return reason
        case .noExportNeeded:
            return String(localized: "Your health data is already up to date", comment: "No export needed message")
        }
    }
}

#endif
