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
        _ destination: APIExportDestinationSnapshot,
        _ dateRangeStart: Date,
        _ dateRangeEnd: Date
    ) async throws -> APIExportUploadResult

    /// Called after each requested date has been fetched (successfully or not),
    /// with the running count of dates processed so far and the total. Callers
    /// (for example the manual export UI) can use this to drive a progress bar
    /// across a potentially multi-batch export.
    typealias ProgressHandler = (_ datesProcessed: Int, _ totalDates: Int) -> Void

    private struct FailureOnlyBatch {
        let start: Date
        let end: Date
        let details: [FailedDateDetail]
    }

    /// Maximum number of calendar days uploaded in a single API export request.
    ///
    /// Large historical exports (many months of granular HealthKit data) can
    /// exceed upstream request-size and timeout limits if uploaded as one
    /// envelope. Instead, a selected date range is split into bounded,
    /// sequential batches of at most this many calendar days each. This is a
    /// conservative default; it is kept as an internal named constant so it
    /// can later be exposed as a user-configurable setting without changing
    /// the batching algorithm.
    nonisolated static let defaultMaxBatchDaySpan = 7

    static func export(
        dates: [Date],
        healthKitManager: HealthKitManager,
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        onProgress: ProgressHandler? = nil
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
            destination: destination,
            fetchHealthData: { date, includeGranularData, metricSelection in
                try await healthKitManager.fetchHealthData(
                    for: date,
                    includeGranularData: includeGranularData,
                    metricSelection: metricSelection
                )
            },
            fetchExternalDailyRecords: externalFetcher,
            upload: { records, failedDateDetails, externalRecords, settings, destination, start, end in
                try await APIExportClient().upload(
                    records: records,
                    failedDateDetails: failedDateDetails,
                    externalRecords: externalRecords,
                    settings: settings,
                    destination: destination,
                    dateRangeStart: start,
                    dateRangeEnd: end
                )
            },
            maxBatchDaySpan: defaultMaxBatchDaySpan,
            onProgress: onProgress
        )
    }

    static func export(
        dates: [Date],
        settings: AdvancedExportSettings,
        apiSettings: APIExportSettings,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        upload: Uploader,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan,
        onProgress: ProgressHandler? = nil
    ) async -> ExportOrchestrator.ExportResult {
        let normalizedDates = dates.map { Calendar.current.startOfDay(for: $0) }.sorted()
        guard !normalizedDates.isEmpty else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: [],
                formatsPerDate: 0,
                completedDates: []
            )
        }
        guard let destination = apiSettings.destinationSnapshot else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: APIExportClientError.invalidEndpoint.localizedDescription
            )
        }
        return await export(
            dates: normalizedDates,
            settings: settings,
            destination: destination,
            fetchHealthData: fetchHealthData,
            fetchExternalDailyRecords: fetchExternalDailyRecords,
            upload: upload,
            maxBatchDaySpan: maxBatchDaySpan,
            onProgress: onProgress
        )
    }

    private static func export(
        dates: [Date],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher?,
        upload: Uploader,
        maxBatchDaySpan: Int,
        onProgress: ProgressHandler?
    ) async -> ExportOrchestrator.ExportResult {
        let normalizedDates = dates.map { Calendar.current.startOfDay(for: $0) }.sorted()
        guard let dateRangeStart = normalizedDates.first else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: [],
                formatsPerDate: 0
            )
        }

        guard !settings.dailyNotesOnlyModeEnabled else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Daily Notes Only requires a filesystem destination and cannot export to an API endpoint."
            )
        }

        guard !settings.exportFormats.isEmpty else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Select at least one export format before exporting to an API endpoint."
            )
        }

        let batchSpan = max(1, maxBatchDaySpan)
        let batches: [[Date]] = stride(from: 0, to: normalizedDates.count, by: batchSpan).map {
            Array(normalizedDates[$0..<min($0 + batchSpan, normalizedDates.count)])
        }

        var totalSuccessCount = 0
        var completedDates: Set<Date> = []
        var allFailedDateDetails: [FailedDateDetail] = []
        var allPartialFailures: [ExportPartialFailure] = []
        var totalExternalRecordCount = 0
        var datesProcessed = 0

        // Failure-only batches are queued until the run encounters its first
        // deliverable record. This preserves the previous all-empty behavior
        // (no request at all), while ensuring any failure metadata that is sent
        // uses the exact date range it describes.
        var queuedFailureOnlyBatches: [FailureOnlyBatch] = []

        for (batchIndex, batch) in batches.enumerated() {
            guard let batchStart = batch.first, let batchEnd = batch.last else { continue }

            var batchRecords: [HealthData] = []
            var batchExternalRecords: [ExternalDailyRecord] = []
            var batchFailedDateDetails: [FailedDateDetail] = []

            for date in batch {
                if Task.isCancelled {
                    return ExportOrchestrator.ExportResult(
                        successCount: totalSuccessCount,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails + batchFailedDateDetails,
                        partialFailures: allPartialFailures,
                        formatsPerDate: 0,
                        externalRecordFileCount: totalExternalRecordCount,
                        wasCancelled: true,
                        completedDates: Array(completedDates)
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

                datesProcessed += 1
                onProgress?(datesProcessed, normalizedDates.count)
            }

            if Task.isCancelled {
                return ExportOrchestrator.ExportResult(
                    successCount: totalSuccessCount,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails + batchFailedDateDetails,
                    partialFailures: allPartialFailures,
                    formatsPerDate: 0,
                    externalRecordFileCount: totalExternalRecordCount,
                    wasCancelled: true,
                    completedDates: Array(completedDates)
                )
            }

            allFailedDateDetails.append(contentsOf: batchFailedDateDetails)

            guard !batchRecords.isEmpty else {
                let failureOnlyBatch = FailureOnlyBatch(
                    start: batchStart,
                    end: batchEnd,
                    details: batchFailedDateDetails
                )

                guard totalSuccessCount > 0 else {
                    queuedFailureOnlyBatches.append(failureOnlyBatch)
                    continue
                }

                do {
                    _ = try await upload(
                        [],
                        failureOnlyBatch.details,
                        [],
                        settings,
                        destination,
                        failureOnlyBatch.start,
                        failureOnlyBatch.end
                    )
                    completedDates.formUnion(terminalCompletedDates(in: failureOnlyBatch.details))
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: failureOnlyBatch.start,
                        failedBatchEnd: failureOnlyBatch.end,
                        undeliveredRecordDates: [],
                        notAttemptedDates: batches.dropFirst(batchIndex + 1).flatMap { $0 },
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
                continue
            }

            // Flush leading failure-only batches before this data batch so
            // requests remain in date order and every failed_date_details item
            // stays inside its envelope's date_range.
            for failureOnlyBatch in queuedFailureOnlyBatches {
                do {
                    _ = try await upload(
                        [],
                        failureOnlyBatch.details,
                        [],
                        settings,
                        destination,
                        failureOnlyBatch.start,
                        failureOnlyBatch.end
                    )
                    completedDates.formUnion(terminalCompletedDates(in: failureOnlyBatch.details))
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: failureOnlyBatch.start,
                        failedBatchEnd: failureOnlyBatch.end,
                        undeliveredRecordDates: [],
                        notAttemptedDates: batches.dropFirst(batchIndex).flatMap { $0 },
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
            }
            queuedFailureOnlyBatches.removeAll()

            do {
                _ = try await upload(
                    batchRecords,
                    batchFailedDateDetails,
                    batchExternalRecords,
                    settings,
                    destination,
                    batchStart,
                    batchEnd
                )
                totalSuccessCount += batchRecords.count
                completedDates.formUnion(batchRecords.map { Calendar.current.startOfDay(for: $0.date) })
                completedDates.formUnion(terminalCompletedDates(in: batchFailedDateDetails))
                totalExternalRecordCount += batchExternalRecords.count
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: batchStart,
                    failedBatchEnd: batchEnd,
                    undeliveredRecordDates: batchRecords.map(\.date),
                    notAttemptedDates: batches.dropFirst(batchIndex + 1).flatMap { $0 },
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
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
            externalRecordFileCount: totalExternalRecordCount,
            completedDates: Array(completedDates)
        )
    }

    private static func uploadFailureResult(
        error: Error,
        failedBatchStart: Date,
        failedBatchEnd: Date,
        undeliveredRecordDates: [Date],
        notAttemptedDates: [Date],
        successCount: Int,
        completedDates: Set<Date>,
        totalCount: Int,
        failedDateDetails: [FailedDateDetail],
        partialFailures: [ExportPartialFailure],
        externalRecordCount: Int
    ) -> ExportOrchestrator.ExportResult {
        let failedRange = rangeDescription(start: failedBatchStart, end: failedBatchEnd)
        let failureMessage = "Batch upload failed for \(failedRange): \(safeUploadFailureDescription(for: error))"
        let uploadFailureDates = undeliveredRecordDates.isEmpty
            ? [failedBatchStart]
            : undeliveredRecordDates
        let uploadFailures = uploadFailureDates.map {
            FailedDateDetail(
                date: $0,
                reason: .fileWriteError,
                errorDetails: failureMessage
            )
        }
        let notAttempted = notAttemptedDates.map {
            FailedDateDetail(
                date: $0,
                reason: .unknown,
                errorDetails: "Not attempted: an earlier batch upload failed for \(failedRange)."
            )
        }

        // Keep the transport failure first so UI/history surfaces the
        // actionable failed range instead of an earlier no-data warning, and
        // retain at most one durable failure entry per requested date.
        var seenDates: Set<Date> = []
        let orderedFailures = (uploadFailures + failedDateDetails + notAttempted).filter {
            seenDates.insert(Calendar.current.startOfDay(for: $0.date)).inserted
        }

        return ExportOrchestrator.ExportResult(
            successCount: successCount,
            totalCount: totalCount,
            failedDateDetails: orderedFailures,
            partialFailures: partialFailures,
            formatsPerDate: 0,
            externalRecordFileCount: externalRecordCount,
            wasCancelled: Task.isCancelled || error is CancellationError,
            completedDates: Array(completedDates)
        )
    }

    private static func terminalCompletedDates(
        in details: [FailedDateDetail],
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(details.compactMap { detail in
            guard detail.reason == .noHealthData else { return nil }
            return calendar.startOfDay(for: detail.date)
        })
    }

    private static func safeUploadFailureDescription(for error: Error) -> String {
        if let apiError = error as? APIExportClientError {
            return apiError.localizedDescription
        }
        if let urlError = error as? URLError {
            return "Network request failed (code \(urlError.code.rawValue))."
        }
        if error is CancellationError {
            return "The API upload was cancelled."
        }
        // Do not persist arbitrary error descriptions: injected/custom
        // transports can include response bodies, health payloads, or headers.
        return "The API endpoint upload failed."
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
