import Foundation
import BackgroundTasks
import Combine
import UserNotifications
import os.log

/// Result of a notification-triggered export to display in the UI
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
        case .success:
            return "Export Completed"
        case .partialSuccess:
            return "Partial Export"
        case .failure:
            return "Export Failed"
        case .noExportNeeded:
            return "Up to Date"
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

    var isSuccess: Bool {
        switch status {
        case .success, .noExportNeeded:
            return true
        case .partialSuccess, .failure:
            return false
        }
    }
}

/// Manages background task scheduling for automated health data exports
class SchedulingManager: ObservableObject {
    @MainActor static let shared = SchedulingManager()

    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "SchedulingManager")

    /// Background task identifier - must match Info.plist entry
    static let backgroundTaskIdentifier = "com.codybontecou.healthmd.dataexport"

    /// Key for tracking last successful export date in UserDefaults
    private let lastExportDateKey = "lastSuccessfulExportDate"

    /// Result from notification-triggered export, observed by UI to show alert
    @MainActor @Published var notificationExportResult: NotificationExportResult?

    @MainActor @Published var schedule: ExportSchedule {
        didSet {
            schedule.save()
            Task {
                if schedule.isEnabled {
                    scheduleBackgroundTask()
                    await setupHealthKitBackgroundDelivery()
                } else {
                    cancelBackgroundTask()
                    await disableHealthKitBackgroundDelivery()
                }
            }
        }
    }

    private init() {
        self.schedule = ExportSchedule.load()
    }

    // MARK: - HealthKit Background Delivery Integration

    /// Sets up HealthKit background delivery when scheduling is enabled
    @MainActor private func setupHealthKitBackgroundDelivery() async {
        let healthKitManager = HealthKitManager.shared

        // Set up callback to handle background delivery
        healthKitManager.onBackgroundDelivery = { [weak self] in
            Task {
                await self?.handleHealthKitBackgroundDelivery()
            }
        }

        await healthKitManager.enableBackgroundDelivery()
        healthKitManager.setupObserverQueries()
        logger.info("HealthKit background delivery configured")
    }

    /// Disables HealthKit background delivery
    @MainActor private func disableHealthKitBackgroundDelivery() async {
        let healthKitManager = HealthKitManager.shared
        healthKitManager.onBackgroundDelivery = nil
        healthKitManager.stopObserverQueries()
        await healthKitManager.disableBackgroundDelivery()
        logger.info("HealthKit background delivery disabled")
    }

    /// Handles background delivery notifications from HealthKit
    private func handleHealthKitBackgroundDelivery() async {
        logger.info("HealthKit background delivery received")

        // Check if we should export (daily frequency and haven't exported today's data yet)
        let currentSchedule = await MainActor.run { schedule }
        guard currentSchedule.isEnabled else {
            logger.info("Schedule disabled, ignoring background delivery")
            return
        }

        // For daily exports, check if yesterday's data needs exporting
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)

        if let lastExport = currentSchedule.lastExportDate {
            let lastExportDay = calendar.startOfDay(for: lastExport)
            if lastExportDay >= yesterday {
                logger.info("Yesterday's data already exported, skipping")
                return
            }
        }

        // Perform the export
        logger.info("Triggering export from HealthKit background delivery")
        let result = await performBackgroundExport()

        if result.success && result.successCount > 0 {
            await MainActor.run {
                var updatedSchedule = schedule
                updatedSchedule.updateLastExport()
                schedule = updatedSchedule
            }
            await sendExportNotification(success: true, daysExported: result.successCount)
        }
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
                // Handle as processing task for longer execution time
                await self.handleBackgroundTask(task as! BGProcessingTask)
            }
        }

        logger.info("Background task handler registered")
    }

    /// Schedules the next background task based on current schedule settings
    /// Uses BGProcessingTask for more reliable execution and longer runtime
    @MainActor func scheduleBackgroundTask() {
        // Cancel any existing tasks
        cancelBackgroundTask()

        guard schedule.isEnabled else {
            logger.info("Schedule disabled, not scheduling background task")
            return
        }

        // Use BGProcessingTask for longer runtime and better reliability
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)

        // Calculate next execution time
        let nextRunDate = calculateNextRunDate()
        request.earliestBeginDate = nextRunDate

        // Prefer running when connected to power for better reliability
        request.requiresExternalPower = false  // Don't require, but prefer
        request.requiresNetworkConnectivity = false  // No network needed for local export

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background processing task scheduled for \(nextRunDate)")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    /// Cancels all pending background tasks
    @MainActor func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        logger.info("Background task cancelled")
    }

    // MARK: - Catch-Up Logic

    /// Performs catch-up export triggered by notification tap and sets result for UI display
    @MainActor func performNotificationTriggeredExport() async {
        guard schedule.isEnabled else {
            logger.info("Schedule disabled, skipping notification-triggered export")
            notificationExportResult = NotificationExportResult(
                status: .failure(reason: "Scheduling is disabled"),
                timestamp: Date()
            )
            return
        }

        let result = await performCatchUpExportInternal()
        notificationExportResult = result
    }

    /// Checks for and exports any missed days since last export
    /// Call this when the app becomes active
    @MainActor func performCatchUpExportIfNeeded() async {
        guard schedule.isEnabled else {
            logger.info("Schedule disabled, skipping catch-up")
            return
        }

        _ = await performCatchUpExportInternal()
    }

    /// Internal method that performs catch-up export and returns result for UI display
    @MainActor private func performCatchUpExportInternal() async -> NotificationExportResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Determine the oldest date we should export
        let oldestDateToExport: Date
        if schedule.frequency == .weekly {
            // For weekly, go back 7 days
            oldestDateToExport = calendar.date(byAdding: .day, value: -7, to: today)!
        } else {
            // For daily, just yesterday
            oldestDateToExport = yesterday
        }

        // Check what dates are missing
        // lastExportDate is when the export RAN, but exports are for the previous day's data
        // So if we exported on Monday, we have data for Sunday (Monday - 1)
        let lastExportedDataDay: Date
        if let lastExport = schedule.lastExportDate {
            let exportRunDay = calendar.startOfDay(for: lastExport)
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: exportRunDay)!
        } else {
            // Never exported, start from oldest date
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: oldestDateToExport)!
        }

        // If we've already exported data for yesterday, nothing to do
        if lastExportedDataDay >= yesterday {
            logger.info("Catch-up check: No missed exports")
            return NotificationExportResult(status: .noExportNeeded, timestamp: Date())
        }

        // Calculate missed dates (from day after last exported data to yesterday)
        // But don't go further back than oldestDateToExport
        var missedDates: [Date] = []
        let dayAfterLastExport = calendar.date(byAdding: .day, value: 1, to: lastExportedDataDay)!
        var checkDate = max(dayAfterLastExport, oldestDateToExport)

        while checkDate <= yesterday {
            missedDates.append(checkDate)
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
        }

        guard !missedDates.isEmpty else {
            logger.info("Catch-up check: No dates to export")
            return NotificationExportResult(status: .noExportNeeded, timestamp: Date())
        }

        logger.info("Catch-up: Found \(missedDates.count) missed date(s) to export")

        // Perform catch-up export
        let result = await performCatchUpExport(for: missedDates)

        if result.successCount > 0 {
            var updatedSchedule = schedule
            updatedSchedule.updateLastExport()
            schedule = updatedSchedule

            // Record in history
            ExportHistoryManager.shared.recordSuccess(
                source: .scheduled,
                dateRangeStart: missedDates.first!,
                dateRangeEnd: missedDates.last!,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails
            )

            logger.info("Catch-up export completed: \(result.successCount)/\(result.totalCount) days")

            // Return appropriate result
            if result.successCount == result.totalCount {
                return NotificationExportResult(
                    status: .success(daysExported: result.successCount),
                    timestamp: Date()
                )
            } else {
                return NotificationExportResult(
                    status: .partialSuccess(exported: result.successCount, total: result.totalCount),
                    timestamp: Date()
                )
            }
        } else {
            // All failed
            let reason = result.failureReason?.shortDescription ?? "Unknown error"
            return NotificationExportResult(
                status: .failure(reason: reason),
                timestamp: Date()
            )
        }
    }

    /// Performs export for specific missed dates
    private func performCatchUpExport(for dates: [Date]) async -> BackgroundExportResult {
        let healthKitManager = HealthKitManager.shared
        let vaultManager = VaultManager()
        let advancedSettings = AdvancedExportSettings()

        guard vaultManager.hasVaultAccess else {
            return BackgroundExportResult(
                success: false,
                successCount: 0,
                totalCount: dates.count,
                failureReason: .noVaultSelected,
                failedDateDetails: []
            )
        }

        vaultManager.refreshVaultAccess()
        vaultManager.startVaultAccess()

        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []

        for date in dates {
            do {
                let healthData = try await healthKitManager.fetchHealthData(for: date)

                if !healthData.hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: advancedSettings)

                if success {
                    successCount += 1
                } else {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .fileWriteError))
                }
            } catch let error as HealthKitManager.HealthKitError {
                // Map HealthKit-specific errors to appropriate failure reasons
                switch error {
                case .dataProtectedWhileLocked:
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .deviceLocked))
                case .notAuthorized:
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
                case .dataNotAvailable:
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
                }
            } catch {
                failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError, errorDetails: error.localizedDescription))
            }
        }

        vaultManager.stopVaultAccess()

        return BackgroundExportResult(
            success: successCount > 0,
            successCount: successCount,
            totalCount: dates.count,
            failureReason: successCount == 0 ? (failedDateDetails.first?.reason ?? .unknown) : nil,
            failedDateDetails: failedDateDetails
        )
    }

    // MARK: - Background Task Execution

    /// Handles background task execution
    private func handleBackgroundTask(_ task: BGProcessingTask) async {
        logger.info("Background processing task started")

        // Schedule the next task
        await MainActor.run {
            scheduleBackgroundTask()
        }

        // Calculate date range for history recording
        let calendar = Calendar.current
        let currentSchedule = await MainActor.run { schedule }
        let daysToExport = currentSchedule.frequency == .weekly ? 7 : 1
        let endDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(daysToExport), to: Date())!)

        // Set expiration handler
        task.expirationHandler = {
            self.logger.warning("Background task expired")
            Task {
                await self.sendExportNotification(success: false, daysExported: 0, failureReason: .backgroundTaskExpired)
                // Record task expiration in history
                ExportHistoryManager.shared.recordFailure(
                    source: .scheduled,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    reason: .backgroundTaskExpired,
                    totalCount: daysToExport
                )
            }
        }

        // Perform the export
        let result = await performBackgroundExport()
        task.setTaskCompleted(success: result.success)

        if result.success && result.successCount > 0 {
            await MainActor.run {
                var updatedSchedule = schedule
                updatedSchedule.updateLastExport()
                schedule = updatedSchedule
            }
            logger.info("Background export completed successfully")
            await sendExportNotification(success: true, daysExported: result.successCount)

            // Record success in history
            if result.failedDateDetails.isEmpty {
                ExportHistoryManager.shared.recordSuccess(
                    source: .scheduled,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: result.successCount,
                    totalCount: result.totalCount
                )
            } else {
                // Partial success
                ExportHistoryManager.shared.recordSuccess(
                    source: .scheduled,
                    dateRangeStart: startDate,
                    dateRangeEnd: endDate,
                    successCount: result.successCount,
                    totalCount: result.totalCount,
                    failedDateDetails: result.failedDateDetails
                )
            }
        } else {
            logger.error("Background export failed")

            // If device was locked, send a "tap to export" reminder instead of failure notification
            if result.failureReason == .deviceLocked {
                await sendExportReminderNotification()
            } else {
                await sendExportNotification(success: false, daysExported: daysToExport, failureReason: result.failureReason, errorDetails: result.failedDateDetails.first?.errorDetails)
            }

            // Record failure in history
            ExportHistoryManager.shared.recordFailure(
                source: .scheduled,
                dateRangeStart: startDate,
                dateRangeEnd: endDate,
                reason: result.failureReason ?? .unknown,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails
            )
        }
    }

    /// Result of a background export operation
    struct BackgroundExportResult {
        let success: Bool
        let successCount: Int
        let totalCount: Int
        let failureReason: ExportFailureReason?
        let failedDateDetails: [FailedDateDetail]
    }

    /// Performs the actual health data export in the background
    private func performBackgroundExport() async -> BackgroundExportResult {
        logger.info("Starting background export")

        // Get the required managers
        let healthKitManager = await MainActor.run { HealthKitManager.shared }
        let vaultManager = VaultManager()

        // Load advanced settings
        let advancedSettings = AdvancedExportSettings()

        // Check if vault is configured
        guard vaultManager.hasVaultAccess else {
            logger.error("No vault access in background")
            return BackgroundExportResult(
                success: false,
                successCount: 0,
                totalCount: 0,
                failureReason: .noVaultSelected,
                failedDateDetails: []
            )
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
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []

        for (index, date) in dates.enumerated() {
            logger.info("Exporting date \(index + 1)/\(dates.count): \(date)")
            do {
                let healthData = try await healthKitManager.fetchHealthData(for: date)
                logger.info("Fetched health data for \(date)")

                if !healthData.hasAnyData {
                    logger.info("No health data for \(date)")
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: advancedSettings)

                if !success {
                    logger.error("Failed to export data for \(date)")
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .fileWriteError))
                } else {
                    logger.info("Successfully exported data for \(date)")
                    successCount += 1
                }
            } catch let error as HealthKitManager.HealthKitError {
                // Map HealthKit-specific errors to appropriate failure reasons
                switch error {
                case .dataProtectedWhileLocked:
                    logger.warning("Device locked, cannot access HealthKit data for \(date)")
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .deviceLocked))
                case .notAuthorized:
                    logger.error("Not authorized to access HealthKit data for \(date)")
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
                case .dataNotAvailable:
                    logger.error("HealthKit data not available for \(date)")
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
                }
            } catch {
                logger.error("Error fetching health data for \(date): \(error.localizedDescription)")
                failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError, errorDetails: error.localizedDescription))
            }
        }

        // Stop vault access
        vaultManager.stopVaultAccess()

        let overallSuccess = successCount > 0
        logger.info("Background export completed. Success: \(successCount)/\(dates.count)")

        return BackgroundExportResult(
            success: overallSuccess,
            successCount: successCount,
            totalCount: dates.count,
            failureReason: overallSuccess ? nil : (failedDateDetails.first?.reason ?? .unknown),
            failedDateDetails: failedDateDetails
        )
    }

    // MARK: - Notifications

    /// Sends a notification after a scheduled export completes
    private func sendExportNotification(success: Bool, daysExported: Int, failureReason: ExportFailureReason? = nil, errorDetails: String? = nil) async {
        let content = UNMutableNotificationContent()

        if success {
            content.title = "Export Completed"
            content.body = daysExported == 1
                ? "Successfully exported yesterday's health data"
                : "Successfully exported \(daysExported) days of health data"
            content.sound = .default
        } else {
            content.title = "Export Failed"
            var body: String
            if let reason = failureReason {
                body = reason.shortDescription
                if let details = errorDetails, !details.isEmpty {
                    body += ": \(details)"
                }
            } else if let details = errorDetails, !details.isEmpty {
                body = details
            } else {
                body = "Failed to export health data. Please check your settings."
            }
            content.body = body
            content.sound = .default
        }

        // Create the request with a unique identifier
        let request = UNNotificationRequest(
            identifier: "com.codybontecou.healthmd.export.\(UUID().uuidString)",
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

    /// Sends a "tap to export" reminder notification when export fails due to device lock
    private func sendExportReminderNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Device Was Locked"
        content.body = "Tap to retry your health export"
        content.sound = .default

        // Use a specific identifier pattern that AppDelegate looks for
        let request = UNNotificationRequest(
            identifier: "com.codybontecou.healthmd.export.reminder.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Export reminder notification sent")
        } catch {
            logger.error("Failed to send export reminder notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

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
