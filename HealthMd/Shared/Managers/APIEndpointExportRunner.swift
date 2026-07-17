import Foundation

/// Testable API Endpoint export pipeline shared by manual and scheduled exports.
/// It prepares public daily JSON records for the requested dates, reports dates
/// with no readable data, and performs one API upload envelope per export run.
@MainActor
struct APIEndpointExportRunner {
    typealias HealthDataFetcher = (
        _ date: Date,
        _ includeGranularData: Bool,
        _ metricSelection: MetricSelectionState
    ) async throws -> HealthData

    typealias ExternalDailyRecordFetcher = (_ date: Date) async -> [ExternalDailyRecord]

    typealias Uploader = (
        _ records: [HealthData],
        _ failedDateDetails: [FailedDateDetail],
        _ externalRecords: [ExternalDailyRecord],
        _ settings: AdvancedExportSettings,
        _ apiSettings: APIExportSettings,
        _ dateRangeStart: Date,
        _ dateRangeEnd: Date
    ) async throws -> APIExportUploadResult

    /// Maximum number of calendar days uploaded in a single API export request.
    ///
    /// Large historical exports (many months of granular HealthKit data) can
    /// exceed upstream request-size and timeout limits if uploaded as one
    /// envelope. Instead, a selected date range is split into bounded,
    /// sequential batches of at most this many calendar days each. This is a
    /// conservative default; it is kept as an internal named constant so it
    /// can later be exposed as a user-configurable setting without changing
    /// the batching algorithm.
    static let defaultMaxBatchDaySpan = 7

    static func export(
        dates: [Date],
        healthKitManager: HealthKitManager,
        settings: AdvancedExportSettings,
        apiSettings: APIExportSettings,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil
    ) async -> ExportOrchestrator.ExportResult {
        let externalFetcher: ExternalDailyRecordFetcher?
        if ConnectedAppsFeature.isEnabled,
           let externalIntegrations,
           externalIntegrations.connectedProviderCount > 0 {
            externalFetcher = { date in
                await externalIntegrations.fetchDailyRecords(for: date)
            }
        } else {
            externalFetcher = nil
        }

        return await export(
            dates: dates,
            settings: settings,
            apiSettings: apiSettings,
            fetchHealthData: { date, includeGranularData, metricSelection in
                try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: includeGranularData,
                    metricSelection: metricSelection
                )
            },
            fetchExternalDailyRecords: externalFetcher,
            upload: { records, failedDateDetails, externalRecords, settings, apiSettings, start, end in
                try await APIExportClient().upload(
                    records: records,
                    failedDateDetails: failedDateDetails,
                    externalRecords: externalRecords,
                    settings: settings,
                    apiSettings: apiSettings,
                    dateRangeStart: start,
                    dateRangeEnd: end
                )
            }
        )
    }

    static func export(
        dates: [Date],
        settings: AdvancedExportSettings,
        apiSettings: APIExportSettings,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        upload: Uploader,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan
    ) async -> ExportOrchestrator.ExportResult {
        let normalizedDates = dates.map { Calendar.current.startOfDay(for: $0) }.sorted()
        guard let dateRangeStart = normalizedDates.first,
              let dateRangeEnd = normalizedDates.last else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: [],
                formatsPerDate: 0
            )
        }

        guard !settings.exportFormats.isEmpty else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Select at least one export format before exporting to an API endpoint."
            )
        }

        guard apiSettings.isConfigured else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: APIExportClientError.invalidEndpoint.localizedDescription
            )
        }

        let batchSpan = max(1, maxBatchDaySpan)
        let batches: [[Date]] = stride(from: 0, to: normalizedDates.count, by: batchSpan).map {
            Array(normalizedDates[$0..<min($0 + batchSpan, normalizedDates.count)])
        }

        var totalSuccessCount = 0
        var allFailedDateDetails: [FailedDateDetail] = []
        var allPartialFailures: [ExportPartialFailure] = []
        var totalExternalRecordCount = 0

        for batch in batches {
            guard let batchStart = batch.first, let batchEnd = batch.last else { continue }

            var batchRecords: [HealthData] = []
            var batchExternalRecords: [ExternalDailyRecord] = []
            var batchFailedDateDetails: [FailedDateDetail] = []

            for date in batch {
                if Task.isCancelled {
                    return ExportOrchestrator.ExportResult(
                        successCount: totalSuccessCount + batchRecords.count,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails + batchFailedDateDetails,
                        partialFailures: allPartialFailures,
                        formatsPerDate: 0,
                        externalRecordFileCount: totalExternalRecordCount + batchExternalRecords.count,
                        wasCancelled: true
                    )
                }

                do {
                    let record = try await fetchHealthData(
                        date,
                        settings.includeGranularData,
                        settings.metricSelection
                    ).filtered(by: settings.metricSelection)
                    allPartialFailures.append(contentsOf: record.partialFailures)

                    if record.hasAnyData {
                        batchRecords.append(record)
                        if let fetchExternalDailyRecords {
                            let providerRecords = await fetchExternalDailyRecords(date)
                            batchExternalRecords.append(contentsOf: providerRecords.filter(\.shouldExport))
                        }
                    } else {
                        batchFailedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                    }
                } catch let error as HealthKitManager.HealthKitError {
                    batchFailedDateDetails.append(FailedDateDetail(
                        date: date,
                        reason: failureReason(for: error),
                        errorDetails: String(describing: error)
                    ))
                } catch {
                    batchFailedDateDetails.append(FailedDateDetail(
                        date: date,
                        reason: .healthKitError,
                        errorDetails: error.localizedDescription
                    ))
                }
            }

            allFailedDateDetails.append(contentsOf: batchFailedDateDetails)
            totalExternalRecordCount += batchExternalRecords.count

            guard !batchRecords.isEmpty else {
                // Nothing to upload for this batch; continue to the next one
                // so a single sparse batch doesn't abort the whole range.
                continue
            }

            do {
                _ = try await upload(
                    batchRecords,
                    batchFailedDateDetails,
                    batchExternalRecords,
                    settings,
                    apiSettings,
                    batchStart,
                    batchEnd
                )
                totalSuccessCount += batchRecords.count
            } catch {
                // Stop on the first failed batch. Prior successful batches
                // remain counted. The error message identifies the failed
                // date range without including health data or authorization
                // values (the underlying errors already omit those).
                allFailedDateDetails.append(FailedDateDetail(
                    date: batchStart,
                    reason: .fileWriteError,
                    errorDetails: "Batch upload failed for \(rangeDescription(start: batchStart, end: batchEnd)): \(error.localizedDescription)"
                ))

                return ExportOrchestrator.ExportResult(
                    successCount: totalSuccessCount,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    formatsPerDate: 0,
                    externalRecordFileCount: totalExternalRecordCount
                )
            }
        }

        if totalSuccessCount == 0 && allFailedDateDetails.isEmpty {
            allFailedDateDetails = [FailedDateDetail(date: dateRangeStart, reason: .noHealthData)]
        }

        return ExportOrchestrator.ExportResult(
            successCount: totalSuccessCount,
            totalCount: normalizedDates.count,
            failedDateDetails: allFailedDateDetails,
            partialFailures: allPartialFailures,
            formatsPerDate: 0,
            externalRecordFileCount: totalExternalRecordCount
        )
    }

    private static func failureResult(
        dates: [Date],
        reason: ExportFailureReason,
        message: String
    ) -> ExportOrchestrator.ExportResult {
        let failedDates = dates.isEmpty ? [Date()] : dates
        return ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: dates.count,
            failedDateDetails: failedDates.map {
                FailedDateDetail(date: $0, reason: reason, errorDetails: message)
            },
            formatsPerDate: 0
        )
    }

    private static func failureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked:
            return .deviceLocked
        case .notAuthorized, .dataNotAvailable, .medicationAuthorizationUnsupported,
             .visionAuthorizationUnsupported:
            return .healthKitError
        }
    }

    private static func rangeDescription(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: start)) to \(formatter.string(from: end))"
    }
}
