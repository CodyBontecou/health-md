import Foundation

/// Destination-neutral capture of one HealthKit day.
///
/// This component owns the behavior that must remain consistent across API and
/// connected-Mac exports: HealthKit fetches, record transforms, safe error
/// classification, partial-failure propagation, no-data handling, and optional
/// external-provider capture. Delivery, retries, and durable completion remain
/// destination-specific.
@MainActor
enum HealthKitDailyCapture {
    typealias HealthDataFetcher = (
        _ date: Date,
        _ includeGranularData: Bool,
        _ metricSelection: MetricSelectionState
    ) async throws -> HealthData

    typealias ExternalDailyRecordFetcher = (_ date: Date) async -> [ExternalDailyRecord]

    enum RecordTransform {
        /// Preserve the fetched record exactly.
        case none
        /// Apply the request's metric selection.
        case filterToSelection
        /// Strip an archive that was not requested while otherwise preserving the record.
        case sanitizeGranular
        /// Apply both connected-export archive sanitization and metric filtering.
        case sanitizeGranularAndFilter
    }

    enum EmptyRecordPolicy: Equatable {
        /// Preserve empty records for destinations that perform their own file/no-data accounting.
        case retain
        /// Convert an empty record into a terminal `.noHealthData` capture outcome.
        case reportNoData
    }

    /// Error semantics are explicit because API and connected-Mac results have
    /// established compatibility contracts. Keeping both mappings here prevents
    /// accidental drift while allowing a future coordinated contract migration.
    enum FailurePolicy: Equatable {
        case apiEndpoint
        case connectedMac
    }

    struct Outcome {
        let sourceDate: Date
        let record: HealthData?
        let externalDailyRecords: [ExternalDailyRecord]
        let partialFailures: [ExportPartialFailure]
        let failure: FailedDateDetail?

        var hasRecord: Bool { record != nil }
    }

    static func normalizedDates(
        _ dates: [Date],
        calendar: Calendar = .current
    ) -> [Date] {
        Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
    }

    static func capture(
        date: Date,
        includeGranularData: Bool,
        metricSelection: MetricSelectionState,
        transform: RecordTransform,
        emptyRecordPolicy: EmptyRecordPolicy,
        fetchExternalRecords: Bool,
        failurePolicy: FailurePolicy,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher?
    ) async throws -> Outcome {
        try Task.checkCancellation()

        do {
            let fetched = try await fetchHealthData(
                date,
                includeGranularData,
                metricSelection
            )
            try Task.checkCancellation()

            let record = transformed(
                fetched,
                includeGranularData: includeGranularData,
                metricSelection: metricSelection,
                transform: transform
            )
            let partialFailures = record.partialFailures

            if !record.hasAnyData, emptyRecordPolicy == .reportNoData {
                return Outcome(
                    sourceDate: date,
                    record: nil,
                    externalDailyRecords: [],
                    partialFailures: partialFailures,
                    failure: FailedDateDetail(date: date, reason: .noHealthData)
                )
            }

            let externalDailyRecords: [ExternalDailyRecord]
            if fetchExternalRecords,
               record.hasAnyData,
               let fetchExternalDailyRecords {
                externalDailyRecords = await fetchExternalDailyRecords(date).filter(\.shouldExport)
            } else {
                externalDailyRecords = []
            }

            return Outcome(
                sourceDate: date,
                record: record,
                externalDailyRecords: externalDailyRecords,
                partialFailures: partialFailures,
                failure: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HealthKitManager.HealthKitError {
            return Outcome(
                sourceDate: date,
                record: nil,
                externalDailyRecords: [],
                partialFailures: [],
                failure: failedDateDetail(for: error, date: date, policy: failurePolicy)
            )
        } catch {
            return Outcome(
                sourceDate: date,
                record: nil,
                externalDailyRecords: [],
                partialFailures: [],
                failure: FailedDateDetail(
                    date: date,
                    reason: .healthKitError,
                    errorDetails: unknownFailureMessage(for: error, policy: failurePolicy)
                )
            )
        }
    }

    static func failedDateDetail(
        for error: HealthKitManager.HealthKitError,
        date: Date,
        policy: FailurePolicy
    ) -> FailedDateDetail {
        FailedDateDetail(
            date: date,
            reason: failureReason(for: error, policy: policy),
            errorDetails: failureMessage(for: error, policy: policy)
        )
    }

    static func failureReason(
        for error: HealthKitManager.HealthKitError,
        policy: FailurePolicy
    ) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized:
            return policy == .connectedMac ? .accessDenied : .healthKitError
        case .dataNotAvailable, .medicationAuthorizationUnsupported,
             .visionAuthorizationUnsupported:
            return .healthKitError
        }
    }

    static func failureMessage(
        for error: HealthKitManager.HealthKitError,
        policy: FailurePolicy
    ) -> String {
        switch error {
        case .dataProtectedWhileLocked:
            return policy == .connectedMac
                ? "Health data is protected while the iPhone is locked."
                : error.localizedDescription
        case .notAuthorized:
            return policy == .connectedMac
                ? "HealthKit access has not been granted on iPhone."
                : error.localizedDescription
        case .dataNotAvailable:
            return policy == .connectedMac
                ? "HealthKit data is not available on this device."
                : error.localizedDescription
        case .medicationAuthorizationUnsupported:
            return policy == .connectedMac
                ? "Medication authorization is not supported on this device."
                : error.localizedDescription
        case .visionAuthorizationUnsupported:
            return policy == .connectedMac
                ? "Vision prescription authorization is not supported on this device."
                : error.localizedDescription
        }
    }

    private static func transformed(
        _ record: HealthData,
        includeGranularData: Bool,
        metricSelection: MetricSelectionState,
        transform: RecordTransform
    ) -> HealthData {
        switch transform {
        case .none:
            return record
        case .filterToSelection:
            return record.filtered(by: metricSelection)
        case .sanitizeGranular:
            return ConnectedExportGranularMode.sanitized(
                record,
                includesGranularData: includeGranularData
            )
        case .sanitizeGranularAndFilter:
            return ConnectedExportGranularMode.sanitized(
                record,
                includesGranularData: includeGranularData
            ).filtered(by: metricSelection)
        }
    }

    private static func unknownFailureMessage(
        for error: Error,
        policy: FailurePolicy
    ) -> String {
        switch policy {
        case .apiEndpoint:
            return error.localizedDescription
        case .connectedMac:
            return "HealthKit query failed for the requested day."
        }
    }
}
