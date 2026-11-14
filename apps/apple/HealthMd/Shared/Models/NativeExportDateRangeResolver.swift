import Foundation
import SwiftUI

/// Admission for native iPhone/iPad exports, including restored selections and
/// Preview actions. All Time resolves readable query coverage; the capture-time
/// history assessment records authorization uncertainty separately. Saved dates
/// never substitute for a fresh discovery of the selected scope.
@MainActor
enum NativeExportDateRangeResolver {
    struct Request: Equatable {
        let selection: ExportDateRangeSelection
        let enabledMetricIDs: Set<String>
        let timeZone: TimeZone

        init(selection: ExportDateRangeSelection, enabledMetricIDs: Set<String>, timeZone: TimeZone) {
            self.selection = selection
            self.enabledMetricIDs = enabledMetricIDs
            self.timeZone = timeZone
        }

        /// The constructor every app surface uses every surface uses, so identical selections
        /// compare equal. All Time ignores the stored dates (discovery decides
        /// them) and the zone is normalized through its identifier, as the
        /// history scope records it.
        init(preset: ExportDateRangePreset, startDate: Date, endDate: Date,
             enabledMetricIDs: Set<String>, timeZoneIdentifier: String) {
            let placeholder = Date(timeIntervalSinceReferenceDate: 0)
            self.init(
                selection: ExportDateRangeSelection(
                    preset: preset,
                    startDate: preset == .allTime ? placeholder : startDate,
                    endDate: preset == .allTime ? placeholder : endDate),
                enabledMetricIDs: enabledMetricIDs,
                timeZone: TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!)
        }

        init(preset: ExportDateRangePreset, startDate: Date, endDate: Date,
             settings: AdvancedExportSettings) {
            self.init(preset: preset, startDate: startDate, endDate: endDate,
                      enabledMetricIDs: settings.metricSelection.enabledMetrics,
                      timeZoneIdentifier: (settings.exportTimeZoneOverride ?? .current).identifier)
        }
    }

    /// A resolved range together with the exact request it answers.
    struct ResolvedRange: Equatable {
        let request: Request
        let range: ExportDateRange
    }

    enum ResolutionError: LocalizedError, Equatable {
        case incompleteDiscovery
        case noHealthData
        case selectionChanged

        var errorDescription: String? {
            switch self {
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
        // A failed query could hide older data, so it blocks All Time. Metrics
        // with no queryable history (clinical records, attachments, types this
        // OS or build lacks) are not failures: they are exported for whatever
        // range the other metrics establish, as before range admission existed.
        // Completion never proves unrestricted access; history assessment
        // records that separately.
        guard discovery.failedTypeIdentifiers.isEmpty else {
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

/// Display-only All Time range for day counts, size estimates and path
/// previews. It never admits an export: Export and Preview resolve again.
struct AllTimeDisplayRangeResolution: ViewModifier {
    let request: NativeExportDateRangeResolver.Request?
    let healthKitManager: HealthKitManager
    @Binding var resolved: NativeExportDateRangeResolver.ResolvedRange?

    func body(content: Content) -> some View {
        content.task(id: request) {
            guard let request, request.selection.preset == .allTime else { return }
            guard resolved?.request != request, healthKitManager.isAuthorized else { return }
            guard let range = try? await NativeExportDateRangeResolver.resolve(
                request, using: healthKitManager, currentRequest: { request }) else { return }
            resolved = .init(request: request, range: range)
        }
    }
}

extension NativeExportDateRangeResolver.ResolvedRange? {
    /// The resolved range when it answers `request`, otherwise nil.
    func range(for request: NativeExportDateRangeResolver.Request) -> ExportDateRange? {
        guard let self, self.request == request else { return nil }
        return self.range
    }
}
