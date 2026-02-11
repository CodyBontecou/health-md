import Foundation

/// Shared export orchestration logic used by both iOS and macOS.
/// Eliminates duplication between manual export (ContentView), scheduled export
/// (SchedulingManager), and future macOS export triggers.
@MainActor
struct ExportOrchestrator {

    // MARK: - Result Type

    struct ExportResult {
        let successCount: Int
        let totalCount: Int
        let failedDateDetails: [FailedDateDetail]

        var isFullSuccess: Bool { successCount == totalCount && totalCount > 0 }
        var isPartialSuccess: Bool { successCount > 0 && successCount < totalCount }
        var isFailure: Bool { successCount == 0 && totalCount > 0 }
        var primaryFailureReason: ExportFailureReason? { failedDateDetails.first?.reason }
    }

    // MARK: - Date Range Helper

    /// Builds an array of calendar days from startDate through endDate (inclusive).
    static func dateRange(from startDate: Date, to endDate: Date) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    // MARK: - Foreground Export (security-scoped)

    /// Export health data for a list of dates.
    /// Each date manages its own security-scoped access via VaultManager's async method.
    /// Suitable for manual/foreground exports.
    static func exportDates(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async -> ExportResult {
        let totalDays = dates.count
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (index, date) in dates.enumerated() {
            let dateString = dateFormatter.string(from: date)
            onProgress?(index + 1, totalDays, dateString)

            do {
                let healthData = try await healthKitManager.fetchHealthData(for: date)
                try await vaultManager.exportHealthData(healthData, settings: settings)
                successCount += 1
            } catch let error as ExportError {
                let reason: ExportFailureReason
                switch error {
                case .noVaultSelected: reason = .noVaultSelected
                case .noHealthData:    reason = .noHealthData
                case .accessDenied:    reason = .accessDenied
                }
                failedDateDetails.append(FailedDateDetail(date: date, reason: reason))
            } catch {
                failedDateDetails.append(FailedDateDetail(
                    date: date, reason: .unknown, errorDetails: error.localizedDescription
                ))
            }
        }

        return ExportResult(
            successCount: successCount,
            totalCount: totalDays,
            failedDateDetails: failedDateDetails
        )
    }

    // MARK: - Background Export (caller-managed scope)

    /// Export health data for a list of dates without managing security scope.
    /// Caller must start/stop vault access. Suitable for background tasks and
    /// scheduled exports where scope is managed externally.
    static func exportDatesBackground(
        _ dates: [Date],
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings
    ) async -> ExportResult {
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []

        for date in dates {
            do {
                let healthData = try await healthKitManager.fetchHealthData(for: date)

                if !healthData.hasAnyData {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    continue
                }

                let success = vaultManager.exportHealthData(healthData, for: date, settings: settings)

                if success {
                    successCount += 1
                } else {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .fileWriteError))
                }
            } catch let error as HealthKitManager.HealthKitError {
                switch error {
                case .dataProtectedWhileLocked:
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .deviceLocked))
                case .notAuthorized:
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
                case .dataNotAvailable:
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .healthKitError))
                }
            } catch {
                failedDateDetails.append(FailedDateDetail(
                    date: date, reason: .healthKitError, errorDetails: error.localizedDescription
                ))
            }
        }

        return ExportResult(
            successCount: successCount,
            totalCount: dates.count,
            failedDateDetails: failedDateDetails
        )
    }

    // MARK: - History Recording Helper

    /// Records an export result in the history manager.
    static func recordResult(
        _ result: ExportResult,
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date
    ) {
        let history = ExportHistoryManager.shared

        if result.successCount > 0 {
            history.recordSuccess(
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                successCount: result.successCount,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails
            )
        } else {
            history.recordFailure(
                source: source,
                dateRangeStart: dateRangeStart,
                dateRangeEnd: dateRangeEnd,
                reason: result.primaryFailureReason ?? .unknown,
                successCount: 0,
                totalCount: result.totalCount,
                failedDateDetails: result.failedDateDetails
            )
        }
    }
}
