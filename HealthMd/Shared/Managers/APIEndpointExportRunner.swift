import Foundation

/// Testable API Endpoint export pipeline shared by manual and scheduled exports.
/// It captures one HealthKit day at a time and performs sequential uploads
/// bounded by both calendar-day count and the exact encoded envelope size.
@MainActor
struct APIEndpointExportRunner {
    typealias HealthDataFetcher = HealthKitDailyCapture.HealthDataFetcher
    typealias ExternalDailyRecordFetcher = HealthKitDailyCapture.ExternalDailyRecordFetcher

    /// Compatibility seam used by existing tests and custom runners.
    typealias Uploader = (
        _ records: [HealthData],
        _ failedDateDetails: [FailedDateDetail],
        _ externalRecords: [ExternalDailyRecord],
        _ settings: AdvancedExportSettings,
        _ destination: APIExportDestinationSnapshot,
        _ dateRangeStart: Date,
        _ dateRangeEnd: Date
    ) async throws -> APIExportUploadResult

    struct PreparedBatch {
        let requestedDates: [Date]
        let records: [HealthData]
        let failedDateDetails: [FailedDateDetail]
        let externalRecords: [ExternalDailyRecord]
        let dateRangeStart: Date
        let dateRangeEnd: Date
        let exportedAt: Date
        /// The exact body measured for batching and sent on the wire.
        let body: Data
    }

    typealias PreparedUploader = (
        _ batch: PreparedBatch,
        _ destination: APIExportDestinationSnapshot
    ) async throws -> APIExportUploadResult

    /// Called after each requested date has been fetched (successfully or not).
    typealias ProgressHandler = (_ datesProcessed: Int, _ totalDates: Int) -> Void

    private struct AccumulatingBatch {
        let exportedAt: Date
        var requestedDates: [Date] = []
        var records: [HealthData] = []
        var failedDateDetails: [FailedDateDetail] = []
        var externalRecords: [ExternalDailyRecord] = []

        init(exportedAt: Date = Date()) {
            self.exportedAt = exportedAt
        }

        mutating func append(_ outcome: HealthKitDailyCapture.Outcome) {
            requestedDates.append(outcome.sourceDate)
            if let record = outcome.record {
                records.append(record)
                externalRecords.append(contentsOf: outcome.externalDailyRecords)
            } else if let failure = outcome.failure {
                failedDateDetails.append(failure)
            }
        }

        func prepared(settings: AdvancedExportSettings) throws -> PreparedBatch {
            guard let start = requestedDates.first, let end = requestedDates.last else {
                throw APIExportClientError.invalidPayload
            }
            let body = try APIExportClient.makePayload(
                records: records,
                failedDateDetails: failedDateDetails,
                externalRecords: externalRecords,
                settings: settings,
                dateRangeStart: start,
                dateRangeEnd: end,
                exportedAt: exportedAt
            )
            return PreparedBatch(
                requestedDates: requestedDates,
                records: records,
                failedDateDetails: failedDateDetails,
                externalRecords: externalRecords,
                dateRangeStart: start,
                dateRangeEnd: end,
                exportedAt: exportedAt,
                body: body
            )
        }
    }

    /// Calendar bound prevents a request from spanning an unexpectedly broad range.
    nonisolated static let defaultMaxBatchDaySpan = 7
    /// Byte target prevents granular history imports from creating unbounded HTTP
    /// bodies. A single indivisible day may exceed this target and is sent alone.
    nonisolated static let defaultMaxBatchPayloadBytes = 8 * 1_024 * 1_024

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

        return await exportPrepared(
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
            upload: { batch, destination in
                try await APIExportClient().upload(
                    payload: batch.body,
                    destination: destination
                )
            },
            maxBatchDaySpan: defaultMaxBatchDaySpan,
            maxBatchPayloadBytes: defaultMaxBatchPayloadBytes,
            onProgress: onProgress
        )
    }

    static func export(
        dates: [Date],
        settings: AdvancedExportSettings,
        apiSettings: APIExportSettings,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        upload: @escaping Uploader,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan,
        maxBatchPayloadBytes: Int = APIEndpointExportRunner.defaultMaxBatchPayloadBytes,
        onProgress: ProgressHandler? = nil
    ) async -> ExportOrchestrator.ExportResult {
        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates)
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

        return await exportPrepared(
            dates: normalizedDates,
            settings: settings,
            destination: destination,
            fetchHealthData: fetchHealthData,
            fetchExternalDailyRecords: fetchExternalDailyRecords,
            upload: { batch, destination in
                try await upload(
                    batch.records,
                    batch.failedDateDetails,
                    batch.externalRecords,
                    settings,
                    destination,
                    batch.dateRangeStart,
                    batch.dateRangeEnd
                )
            },
            maxBatchDaySpan: maxBatchDaySpan,
            maxBatchPayloadBytes: maxBatchPayloadBytes,
            onProgress: onProgress
        )
    }

    private static func exportPrepared(
        dates: [Date],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher?,
        upload: @escaping PreparedUploader,
        maxBatchDaySpan: Int,
        maxBatchPayloadBytes: Int,
        onProgress: ProgressHandler?
    ) async -> ExportOrchestrator.ExportResult {
        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates)
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

        let dayLimit = max(1, maxBatchDaySpan)
        let byteLimit = max(1, maxBatchPayloadBytes)
        var totalSuccessCount = 0
        var completedDates: Set<Date> = []
        var allFailedDateDetails: [FailedDateDetail] = []
        var allPartialFailures: [ExportPartialFailure] = []
        var totalExternalRecordCount = 0
        var datesProcessed = 0
        var currentBatch: AccumulatingBatch?
        var queuedFailureOnlyBatches: [PreparedBatch] = []

        func cancelledResult() -> ExportOrchestrator.ExportResult {
            ExportOrchestrator.ExportResult(
                successCount: totalSuccessCount,
                totalCount: normalizedDates.count,
                failedDateDetails: allFailedDateDetails,
                partialFailures: allPartialFailures,
                formatsPerDate: 0,
                externalRecordFileCount: totalExternalRecordCount,
                wasCancelled: true,
                completedDates: Array(completedDates)
            )
        }

        /// Commits one fully prepared batch. Failure-only batches are retained
        /// until at least one record exists, preserving all-empty no-request behavior.
        func commit(
            _ batch: PreparedBatch,
            futureDates: [Date]
        ) async -> ExportOrchestrator.ExportResult? {
            if batch.records.isEmpty {
                guard totalSuccessCount > 0 else {
                    queuedFailureOnlyBatches.append(batch)
                    return nil
                }
                do {
                    _ = try await upload(batch, destination)
                    completedDates.formUnion(terminalCompletedDates(in: batch.failedDateDetails))
                    return nil
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: batch.dateRangeStart,
                        failedBatchEnd: batch.dateRangeEnd,
                        undeliveredRecordDates: [],
                        notAttemptedDates: futureDates,
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
            }

            for failureOnlyBatch in queuedFailureOnlyBatches {
                do {
                    _ = try await upload(failureOnlyBatch, destination)
                    completedDates.formUnion(
                        terminalCompletedDates(in: failureOnlyBatch.failedDateDetails)
                    )
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: failureOnlyBatch.dateRangeStart,
                        failedBatchEnd: failureOnlyBatch.dateRangeEnd,
                        undeliveredRecordDates: [],
                        notAttemptedDates: batch.requestedDates + futureDates,
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
                _ = try await upload(batch, destination)
                totalSuccessCount += batch.records.count
                completedDates.formUnion(batch.records.map {
                    Calendar.current.startOfDay(for: $0.date)
                })
                completedDates.formUnion(terminalCompletedDates(in: batch.failedDateDetails))
                totalExternalRecordCount += batch.externalRecords.count
                return nil
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: batch.dateRangeStart,
                    failedBatchEnd: batch.dateRangeEnd,
                    undeliveredRecordDates: batch.records.map(\.date),
                    notAttemptedDates: futureDates,
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }
        }

        for (index, date) in normalizedDates.enumerated() {
            if Task.isCancelled { return cancelledResult() }

            // The day-count boundary is known before the next HealthKit read.
            // Commit it now so cancellation during that read cannot erase a
            // fully prepared earlier batch.
            if let batch = currentBatch,
               batch.requestedDates.count >= dayLimit {
                do {
                    if let failure = await commit(
                        try batch.prepared(settings: settings),
                        futureDates: Array(normalizedDates.dropFirst(index))
                    ) {
                        return failure
                    }
                    currentBatch = nil
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: batch.requestedDates.first ?? date,
                        failedBatchEnd: batch.requestedDates.last ?? date,
                        undeliveredRecordDates: batch.records.map(\.date),
                        notAttemptedDates: Array(normalizedDates.dropFirst(index)),
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
            }

            let outcome: HealthKitDailyCapture.Outcome
            do {
                outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection,
                    transform: .filterToSelection,
                    emptyRecordPolicy: .reportNoData,
                    fetchExternalRecords: fetchExternalDailyRecords != nil,
                    failurePolicy: .apiEndpoint,
                    fetchHealthData: fetchHealthData,
                    fetchExternalDailyRecords: fetchExternalDailyRecords
                )
            } catch is CancellationError {
                return cancelledResult()
            } catch {
                return uploadFailureResult(
                    error: APIExportClientError.invalidPayload,
                    failedBatchStart: date,
                    failedBatchEnd: date,
                    undeliveredRecordDates: [date],
                    notAttemptedDates: Array(normalizedDates.dropFirst(index + 1)),
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }

            datesProcessed += 1
            onProgress?(datesProcessed, normalizedDates.count)
            if Task.isCancelled { return cancelledResult() }

            var candidate = currentBatch ?? AccumulatingBatch()
            candidate.append(outcome)
            let preparedCandidate: PreparedBatch
            do {
                preparedCandidate = try candidate.prepared(settings: settings)
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: candidate.requestedDates.first ?? date,
                    failedBatchEnd: candidate.requestedDates.last ?? date,
                    undeliveredRecordDates: candidate.records.map(\.date),
                    notAttemptedDates: Array(normalizedDates.dropFirst(index + 1)),
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }

            let exceedsDayLimit = candidate.requestedDates.count > dayLimit
            let exceedsByteLimit = preparedCandidate.body.count > byteLimit
            if currentBatch != nil, exceedsDayLimit || exceedsByteLimit {
                do {
                    let preparedCurrent = try currentBatch!.prepared(settings: settings)
                    let futureDates = Array(normalizedDates.dropFirst(index))
                    if let failure = await commit(preparedCurrent, futureDates: futureDates) {
                        return failure
                    }
                } catch {
                    let dates = currentBatch?.requestedDates ?? [date]
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: dates.first ?? date,
                        failedBatchEnd: dates.last ?? date,
                        undeliveredRecordDates: currentBatch?.records.map(\.date) ?? [],
                        notAttemptedDates: Array(normalizedDates.dropFirst(index)),
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
                var singleton = AccumulatingBatch()
                singleton.append(outcome)
                currentBatch = singleton
            } else {
                currentBatch = candidate
            }

            allPartialFailures.append(contentsOf: outcome.partialFailures)
            if let failure = outcome.failure {
                allFailedDateDetails.append(failure)
            }
        }

        if let currentBatch {
            do {
                if let failure = await commit(
                    try currentBatch.prepared(settings: settings),
                    futureDates: []
                ) {
                    return failure
                }
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: currentBatch.requestedDates.first ?? dateRangeStart,
                    failedBatchEnd: currentBatch.requestedDates.last ?? dateRangeStart,
                    undeliveredRecordDates: currentBatch.records.map(\.date),
                    notAttemptedDates: [],
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

    private static func rangeDescription(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: start)) to \(formatter.string(from: end))"
    }
}
