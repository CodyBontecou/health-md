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
        upload: Uploader
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

        var records: [HealthData] = []
        var externalRecords: [ExternalDailyRecord] = []
        var failedDateDetails: [FailedDateDetail] = []
        var partialFailures: [ExportPartialFailure] = []

        for date in normalizedDates {
            if Task.isCancelled {
                return ExportOrchestrator.ExportResult(
                    successCount: records.count,
                    totalCount: normalizedDates.count,
                    failedDateDetails: failedDateDetails,
                    partialFailures: partialFailures,
                    formatsPerDate: 0,
                    externalRecordFileCount: externalRecords.count,
                    wasCancelled: true
                )
            }

            do {
                let record = try await fetchHealthData(
                    date,
                    settings.includeGranularData,
                    settings.metricSelection
                ).filtered(by: settings.metricSelection)
                partialFailures.append(contentsOf: record.partialFailures)

                if record.hasAnyData {
                    records.append(record)
                    if let fetchExternalDailyRecords {
                        let providerRecords = await fetchExternalDailyRecords(date)
                        externalRecords.append(contentsOf: providerRecords.filter(\.shouldExport))
                    }
                } else {
                    failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                }
            } catch let error as HealthKitManager.HealthKitError {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: failureReason(for: error),
                    errorDetails: String(describing: error)
                ))
            } catch {
                failedDateDetails.append(FailedDateDetail(
                    date: date,
                    reason: .healthKitError,
                    errorDetails: error.localizedDescription
                ))
            }
        }

        guard !records.isEmpty else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: normalizedDates.count,
                failedDateDetails: failedDateDetails.isEmpty
                    ? [FailedDateDetail(date: dateRangeStart, reason: .noHealthData)]
                    : failedDateDetails,
                partialFailures: partialFailures,
                formatsPerDate: 0,
                externalRecordFileCount: externalRecords.count
            )
        }

        do {
            _ = try await upload(
                records,
                failedDateDetails,
                externalRecords,
                settings,
                apiSettings,
                dateRangeStart,
                dateRangeEnd
            )

            return ExportOrchestrator.ExportResult(
                successCount: records.count,
                totalCount: normalizedDates.count,
                failedDateDetails: failedDateDetails,
                partialFailures: partialFailures,
                formatsPerDate: 0,
                externalRecordFileCount: externalRecords.count
            )
        } catch {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: normalizedDates.count,
                failedDateDetails: [FailedDateDetail(
                    date: dateRangeStart,
                    reason: .fileWriteError,
                    errorDetails: error.localizedDescription
                )],
                partialFailures: partialFailures,
                formatsPerDate: 0,
                externalRecordFileCount: externalRecords.count
            )
        }
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
}
