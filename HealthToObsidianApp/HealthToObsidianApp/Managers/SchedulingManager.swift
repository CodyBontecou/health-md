import Foundation
import BackgroundTasks
import Combine
import UserNotifications
import os.log

/// Manages background task scheduling for automated health data exports
class SchedulingManager: ObservableObject {
    @MainActor static let shared = SchedulingManager()

    private let logger = Logger(subsystem: "com.healthexporter", category: "SchedulingManager")

    /// Background task identifier - must match Info.plist entry
    static let backgroundTaskIdentifier = "com.healthexporter.dataexport"

    @MainActor @Published var schedule: ExportSchedule {
        didSet {
            schedule.save()
            Task {
                if schedule.isEnabled {
                    scheduleBackgroundTask()
                } else {
                    cancelBackgroundTask()
                }
            }
        }
    }

    private init() {
        self.schedule = ExportSchedule.load()
    }

    // MARK: - Background Task Registration

    /// Requests notification permissions
    @MainActor func requestNotificationPermissions() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            logger.info("Notification permission granted: \(granted)")
            return granted
        } catch {
            logger.error("Failed to request notification permissions: \(error.localizedDescription)")
            return false
        }
    }

    /// Registers the background task handler - call this at app launch
    @MainActor func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }
            Task {
                await self.handleBackgroundTask(task as! BGAppRefreshTask)
            }
        }

        logger.info("Background task handler registered")
    }

    /// Schedules the next background task based on current schedule settings
    func scheduleBackgroundTask() {
        // Cancel any existing tasks
        cancelBackgroundTask()

        guard schedule.isEnabled else {
            logger.info("Schedule disabled, not scheduling background task")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)

        // Calculate next execution time
        let nextRunDate = calculateNextRunDate()
        request.earliestBeginDate = nextRunDate

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background task scheduled for \(nextRunDate)")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Cancels all pending background tasks
    func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        logger.info("Background task cancelled")
    }

    // MARK: - Background Task Execution

    /// Handles background task execution
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        logger.info("Background task started")

        // Schedule the next task
        await MainActor.run {
            scheduleBackgroundTask()
        }

        // Set expiration handler
        task.expirationHandler = {
            self.logger.warning("Background task expired")
            Task {
                await self.sendExportNotification(success: false, daysExported: 0)
            }
        }

        // Determine how many days will be exported
        let daysToExport = await getDaysToExport()

        // Perform the export
        do {
            let success = await performBackgroundExport()
            task.setTaskCompleted(success: success)

            if success {
                await MainActor.run {
                    var updatedSchedule = schedule
                    updatedSchedule.updateLastExport()
                    schedule = updatedSchedule
                }
                logger.info("Background export completed successfully")
                await sendExportNotification(success: true, daysExported: daysToExport)
            } else {
                logger.error("Background export failed")
                await sendExportNotification(success: false, daysExported: daysToExport)
            }
        } catch {
            logger.error("Background export error: \(error.localizedDescription)")
            task.setTaskCompleted(success: false)
            await sendExportNotification(success: false, daysExported: daysToExport)
        }
    }

    /// Performs the actual health data export in the background
    private func performBackgroundExport() async -> Bool {
        logger.info("Starting background export")

        // Get the required managers
        let healthKitManager = HealthKitManager()
        let vaultManager = VaultManager()

        // Load advanced settings
        let advancedSettings = AdvancedExportSettings()

        // Check if vault is configured
        guard vaultManager.hasVaultAccess else {
            logger.error("No vault access in background")
            return false
        }

        logger.info("Vault access confirmed: \(vaultManager.vaultURL?.path ?? "unknown")")

        // Determine date range to export
        let calendar = Calendar.current
        let dates: [Date]

        let currentSchedule = await MainActor.run { schedule }

        // Daily: export yesterday only
        // Weekly: export last 7 days
        let daysToExport = currentSchedule.frequency == .weekly ? 7 : 1
        dates = (1...daysToExport).compactMap { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            return calendar.startOfDay(for: date)
        }

        logger.info("Exporting \(dates.count) days of data")

        // Refresh vault access if needed
        vaultManager.refreshVaultAccess()

        // Start security-scoped resource access for background task
        vaultManager.startVaultAccess()

        // Export each date
        var allSuccessful = true
        for (index, date) in dates.enumerated() {
            logger.info("Exporting date \(index + 1)/\(dates.count): \(date)")
            do {
                let healthData = try await healthKitManager.fetchHealthData(for: date)
                logger.info("Fetched health data for \(date)")

                let success = vaultManager.exportHealthData(healthData, for: date, settings: advancedSettings)

                if !success {
                    logger.error("Failed to export data for \(date)")
                    allSuccessful = false
                } else {
                    logger.info("Successfully exported data for \(date)")
                }
            } catch {
                logger.error("Error fetching health data for \(date): \(error.localizedDescription)")
                allSuccessful = false
            }
        }

        // Stop vault access
        vaultManager.stopVaultAccess()

        logger.info("Background export completed. Success: \(allSuccessful)")
        return allSuccessful
    }

    // MARK: - Notifications

    /// Sends a notification after a scheduled export completes
    private func sendExportNotification(success: Bool, daysExported: Int) async {
        let content = UNMutableNotificationContent()

        if success {
            content.title = "Export Completed"
            content.body = daysExported == 1
                ? "Successfully exported yesterday's health data"
                : "Successfully exported \(daysExported) days of health data"
            content.sound = .default
        } else {
            content.title = "Export Failed"
            content.body = "Failed to export health data. Please check your settings."
            content.sound = .default
        }

        // Create the request with a unique identifier
        let request = UNNotificationRequest(
            identifier: "com.healthexporter.export.\(UUID().uuidString)",
            content: content,
            trigger: nil // nil trigger means deliver immediately
        )

        // Add the notification request
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Failed to send notification: \(error.localizedDescription)")
            } else {
                self.logger.info("Notification sent: \(content.title)")
            }
        }
    }

    // MARK: - Helper Methods

    /// Determines how many days will be exported based on current settings
    private func getDaysToExport() async -> Int {
        let currentSchedule = await MainActor.run { schedule }
        return currentSchedule.frequency == .weekly ? 7 : 1
    }

    /// Calculates the next scheduled run date based on current settings
    private func calculateNextRunDate() -> Date {
        let calendar = Calendar.current
        let now = Date()

        // Get today at the preferred hour and minute
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = schedule.preferredHour
        components.minute = schedule.preferredMinute

        guard var nextDate = calendar.date(from: components) else {
            return now.addingTimeInterval(3600) // Fallback: 1 hour from now
        }

        // If that time has passed today, move to next occurrence
        if nextDate <= now {
            switch schedule.frequency {
            case .daily:
                nextDate = calendar.date(byAdding: .day, value: 1, to: nextDate)!
            case .weekly:
                nextDate = calendar.date(byAdding: .day, value: 7, to: nextDate)!
            }
        }

        return nextDate
    }

    /// Returns a human-readable string describing the next scheduled export
    @MainActor func getNextExportDescription() -> String? {
        guard schedule.isEnabled else { return nil }

        let nextDate = calculateNextRunDate()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return formatter.string(from: nextDate)
    }
}
