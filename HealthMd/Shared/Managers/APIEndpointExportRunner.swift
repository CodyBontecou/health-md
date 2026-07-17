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

    /// Called after each requested date has been fetched (successfully or not),
    /// with the running count of dates processed so far and the total. Callers
    /// (for example the manual export UI) can use this to drive a progress bar
    /// across a potentially multi-batch export.
    typealias ProgressHandler = (_ datesProcessed: Int, _ totalDates: Int) -> Void

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
            },
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
        var datesProcessed = 0
        // Failed-date details from a batch that had no deliverable records of
        // its own. These are carried forward and attached to the next batch
        // that does upload successfully, so the endpoint still learns about
        // them (mirroring the pre-batching behavior where every failed date
        // in the range rode along in the single envelope). If no later batch
        // succeeds, they are flushed in a dedicated failure-only request at
        // the end (but only once at least one upload has actually happened —
        // if the whole range never has anything to upload, no request is
        // sent at all, matching prior behavior for entirely-empty ranges).
        var pendingUnsentFailedDateDetails: [FailedDateDetail] = []

        for (batchIndex, batch) in batches.enumerated() {
            guard let batchStart = batch.first, let batchEnd = batch.last else { continue }

            var batchRecords: [HealthData] = []
            var batchExternalRecords: [ExternalDailyRecord] = []
            var batchFailedDateDetails: [FailedDateDetail] = []

            for date in batch {
                if Task.isCancelled {
                    return ExportOrchestrator.ExportResult(
                        successCount: totalSuccessCount + batchRecords.count,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails + pendingUnsentFailedDateDetails + batchFailedDateDetails,
                        partialFailures: allPartialFailures,
                        formatsPerDate: 0,
                        externalRecordFileCount: totalExternalRecordCount,
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

                datesProcessed += 1
                onProgress?(datesProcessed, normalizedDates.count)
            }

            let combinedFailedDateDetailsForUpload = pendingUnsentFailedDateDetails + batchFailedDateDetails

            guard !batchRecords.isEmpty else {
                // Nothing new to upload for this batch. Keep its failed dates
                // pending so they still reach the endpoint alongside the next
                // batch that does have records (or a trailing flush below).
                allFailedDateDetails.append(contentsOf: batchFailedDateDetails)
                pendingUnsentFailedDateDetails = combinedFailedDateDetailsForUpload
                continue
            }

            do {
                _ = try await upload(
                    batchRecords,
                    combinedFailedDateDetailsForUpload,
                    batchExternalRecords,
                    settings,
                    apiSettings,
                    batchStart,
                    batchEnd
                )
                totalSuccessCount += batchRecords.count
                totalExternalRecordCount += batchExternalRecords.count
                allFailedDateDetails.append(contentsOf: batchFailedDateDetails)
                pendingUnsentFailedDateDetails = []
            } catch {
                allFailedDateDetails.append(contentsOf: batchFailedDateDetails)

                // Every date whose record was part of this failed upload is
                // itself undelivered — report each one, not just the batch
                // start, so consumers (e.g. retry UI) can see exactly which
                // dates need to be re-sent.
                let failureMessage = "Batch upload failed for \(rangeDescription(start: batchStart, end: batchEnd)): \(error.localizedDescription)"
                allFailedDateDetails.append(contentsOf: batchRecords.map {
                    FailedDateDetail(date: $0.date, reason: .fileWriteError, errorDetails: failureMessage)
                })

                // Every date in every batch after this one was never even
                // attempted because the run stops here — report those too.
                for remainingBatch in batches[(batchIndex + 1)...] {
                    allFailedDateDetails.append(contentsOf: remainingBatch.map {
                        FailedDateDetail(
                            date: $0,
                            reason: .unknown,
                            errorDetails: "Not attempted: an earlier batch upload failed for \(rangeDescription(start: batchStart, end: batchEnd))."
                        )
                    })
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
        }

        if !pendingUnsentFailedDateDetails.isEmpty {
            if totalSuccessCount > 0 {
                // At least one batch uploaded successfully, so it's meaningful
                // to tell the endpoint about the remaining failed dates too:
                // send them as a dedicated failure-only request rather than
                // silently dropping them.
                let flushStart = pendingUnsentFailedDateDetails.map(\.date).min() ?? dateRangeStart
                let flushEnd = pendingUnsentFailedDateDetails.map(\.date).max() ?? dateRangeEnd
                do {
                    _ = try await upload([], pendingUnsentFailedDateDetails, [], settings, apiSettings, flushStart, flushEnd)
                } catch {
                    // Reporting the already-known failed dates didn't go
                    // through either; note that without discarding the
                    // success already accounted for above.
                    allFailedDateDetails.append(FailedDateDetail(
                        date: flushStart,
                        reason: .fileWriteError,
                        errorDetails: "Failed to report failed dates for \(rangeDescription(start: flushStart, end: flushEnd)): \(error.localizedDescription)"
                    ))
                }
            }
            allFailedDateDetails.append(contentsOf: pendingUnsentFailedDateDetails)
            pendingUnsentFailedDateDetails = []
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
