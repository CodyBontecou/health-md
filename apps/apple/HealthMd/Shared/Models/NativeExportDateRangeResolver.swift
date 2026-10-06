import Foundation

/// Admission for native iPhone/iPad exports, including restored selections and
/// Preview actions. A persisted All Time range is not authorization evidence.
@MainActor
enum NativeExportDateRangeResolver {
    struct Request: Equatable {
        let selection: ExportDateRangeSelection
        let enabledMetricIDs: Set<String>
        let timeZone: TimeZone
    }

    enum ResolutionError: LocalizedError, Equatable {
        case limitedHistory
        case unverifiedHistory
        case incompleteDiscovery
        case noHealthData
        case selectionChanged

        var errorDescription: String? {
            switch self {
            case .limitedHistory:
                return "All Time is unavailable because Apple Health history is limited for a selected metric. Earlier data is unknown, not absent. Review Health permissions or choose an explicit date range."
            case .unverifiedHistory:
                return "Full Apple Health history could not be verified for every selected metric. All Time requires a supported OS 27+ history assessment. Choose an explicit date range."
            case .incompleteDiscovery:
                return "The earliest date could not be determined for every selected metric. No All Time export was started. Try again or choose an explicit date range."
            case .noHealthData:
                return "No readable historical data was found for the selected metrics. Choose an explicit date range or review Health permissions."
            case .selectionChanged:
                return "The export selection changed while All Time was being checked. Tap Export again to check the current selection."
            }
        }
    }

    /// Rechecks the exact selected scope on every admission. The caller supplies
    /// its live request so an asynchronous result cannot authorize different
    /// metrics, dates, or calendar semantics from those that were assessed.
    static func resolve(
        _ request: Request,
        using healthKitManager: HealthKitManager,
        currentRequest: () -> Request,
        referenceDate: Date? = nil
    ) async throws -> ExportDateRange {
        try Task.checkCancellation()
        guard request.selection.preset == .allTime else {
            // Explicit ranges remain usable on older SDKs/runtimes and do not
            // trigger history authorization or earliest-date discovery.
            return ExportDateRange(
                startDate: request.selection.startDate,
                endDate: request.selection.endDate
            )
        }

        let discovery = await healthKitManager.discoverEarliestHealthDataDate(
            enabledMetricIDs: request.enabledMetricIDs,
            timeZone: request.timeZone
        )
        try Task.checkCancellation()
        guard request == currentRequest() else {
            throw ResolutionError.selectionChanged
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = request.timeZone
        // Discovery may span midnight; All Time must extend through the day
        // when it finishes, not the day when its serial queries began.
        return try allTimeRange(
            from: discovery,
            referenceDate: referenceDate ?? Date(),
            calendar: calendar
        )
    }

    static func allTimeRange(
        from discovery: HealthKitEarliestDataDiscovery,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> ExportDateRange {
        guard discovery.historyAuthorization.supportsUnqualifiedFullHistoryClaim else {
            throw discovery.historyAuthorization.state == .limitedHistory
                ? ResolutionError.limitedHistory
                : ResolutionError.unverifiedHistory
        }
        guard discovery.isComplete else {
            throw ResolutionError.incompleteDiscovery
        }
        guard let earliestDate = discovery.earliestDate else {
            throw ResolutionError.noHealthData
        }
        guard earliestDate <= referenceDate else {
            throw ResolutionError.incompleteDiscovery
        }
        return ExportDateRange(
            startDate: calendar.startOfDay(for: earliestDate),
            endDate: calendar.startOfDay(for: referenceDate)
        )
    }
}
