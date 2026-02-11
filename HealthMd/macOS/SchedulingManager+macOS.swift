#if os(macOS)
import Foundation
import Combine
import ServiceManagement
import UserNotifications
import os.log

/// macOS SchedulingManager — uses in-app Timer + Login Item instead of BGTaskScheduler.
/// The app persists in the menu bar, so a simple timer checks hourly whether an export is due.
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
        }
    }

    private var exportTimer: Timer?
    private var isExporting = false

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
            // Also set up HealthKit observer queries off
            HealthKitManager.shared.stopObserverQueries()
            HealthKitManager.shared.stopPollingTimer()
            return
        }

        // Set up HealthKit observer queries + polling
        let hkm = HealthKitManager.shared
        hkm.onBackgroundDelivery = { [weak self] in
            Task { await self?.handleNewHealthData() }
        }
        hkm.setupObserverQueries()
        hkm.setupPollingTimer()

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

    /// Called when new health data is detected via observer queries
    private func handleNewHealthData() async {
        guard schedule.isEnabled else { return }
        logger.info("New health data detected, checking if export is due")
        await performExportIfDue()
    }

    /// Checks if an export is due based on schedule and last export date
    private func performExportIfDue() async {
        guard schedule.isEnabled, !isExporting else { return }

        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!)

        // Check if it's past the preferred time
        let todayComponents = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinuteOfDay = (todayComponents.hour ?? 0) * 60 + (todayComponents.minute ?? 0)
        let preferredMinuteOfDay = schedule.preferredHour * 60 + schedule.preferredMinute

        guard currentMinuteOfDay >= preferredMinuteOfDay else {
            logger.info("Not yet at preferred export time, skipping")
            return
        }

        // Check if we already exported recently
        if let lastExport = schedule.lastExportDate {
            let lastExportDay = calendar.startOfDay(for: lastExport)
            if lastExportDay >= yesterday {
                // Already exported today or yesterday was already handled
                return
            }
        }

        logger.info("Export is due, performing catch-up export")
        await performCatchUpExport()
    }

    /// Performs catch-up export for any missed days
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

        // If yesterday's data is already exported, nothing to do
        guard lastExportedDataDay < yesterday else {
            logger.info("All data up to date")
            return
        }

        let dayAfterLastExport = calendar.date(byAdding: .day, value: 1, to: lastExportedDataDay)!
        let dates = ExportOrchestrator.dateRange(
            from: max(dayAfterLastExport, oldestDateToExport),
            to: yesterday
        )

        guard !dates.isEmpty else {
            logger.info("No dates to export")
            return
        }

        logger.info("Catch-up export: \(dates.count) day(s)")

        let healthKitManager = HealthKitManager.shared
        let vaultManager = VaultManager()
        let settings = AdvancedExportSettings()

        guard vaultManager.hasVaultAccess else {
            logger.error("No vault access")
            await sendNotification(
                title: "Export Failed",
                body: "No export folder selected. Open Health.md to choose one."
            )
            return
        }

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()

        let result = await ExportOrchestrator.exportDatesBackground(
            dates,
            healthKitManager: healthKitManager,
            vaultManager: vaultManager,
            settings: settings
        )

        vaultManager.stopVaultAccess()

        if result.successCount > 0 {
            var updatedSchedule = schedule
            updatedSchedule.updateLastExport()
            schedule = updatedSchedule

            ExportOrchestrator.recordResult(
                result,
                source: .scheduled,
                dateRangeStart: dates.first!,
                dateRangeEnd: dates.last!
            )

            await sendNotification(
                title: "Export Complete",
                body: result.isFullSuccess
                    ? "Exported \(result.successCount) day\(result.successCount == 1 ? "" : "s") of health data."
                    : "Exported \(result.successCount)/\(result.totalCount) days."
            )

            logger.info("Catch-up export done: \(result.successCount)/\(result.totalCount)")
        } else {
            let reason = result.primaryFailureReason?.shortDescription ?? "Unknown error"
            await sendNotification(
                title: "Export Failed",
                body: reason
            )
            logger.error("Catch-up export failed: \(reason)")
        }
    }

    /// Performs catch-up when app becomes active
    func performCatchUpExportIfNeeded() async {
        guard schedule.isEnabled else { return }
        await performCatchUpExport()
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
        case .success:         return "Export Completed"
        case .partialSuccess:  return "Partial Export"
        case .failure:         return "Export Failed"
        case .noExportNeeded:  return "Up to Date"
        }
    }

    var message: String {
        switch status {
        case .success(let days):
            return days == 1
                ? "Successfully exported yesterday's health data"
                : "Successfully exported \(days) days of health data"
        case .partialSuccess(let exported, let total):
            return "Exported \(exported) of \(total) days"
        case .failure(let reason):
            return reason
        case .noExportNeeded:
            return "Your health data is already up to date"
        }
    }
}

#endif
