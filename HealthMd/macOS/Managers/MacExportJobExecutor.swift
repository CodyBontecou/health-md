import Foundation

#if os(macOS)

/// Executes iOS-originated Mac export jobs without consulting the legacy Mac
/// health-data cache. The job's records and `ExportSettingsSnapshot` are the
/// complete source of truth.
@MainActor
final class MacExportJobExecutor {
    typealias ProgressHandler = (MacExportProgress) -> Void

    private var activeJobID: UUID?
    private var cancelledJobIDs: Set<UUID> = []
    private var streamSession: StreamSession?

    /// Streaming chunks are accepted in strict 1-based order. The first
    /// `MacExportStreamChunk.sequence` for a stream must be `1`; out-of-order
    /// chunks are rejected with `accepted == false` and do not mutate session
    /// state, so the iPhone can retry the expected sequence.
    private struct StreamSession {
        let start: MacExportStreamStart
        let requestedDates: [Date]
        let formatsPerDate: Int
        var expectedSequence: Int = 1
        var successCount: Int = 0
        var failedDateDetails: [FailedDateDetail] = []
        var successfulRecords: [HealthData] = []
        var retainedExternalDailyRecords: [ExternalDailyRecord] = []
        var totalFilesWritten: Int = 0
        var externalRecordFileCount: Int = 0
        var dailyNoteUpdateCount: Int = 0
        var dailyNoteSkipCount: Int = 0
        var processedDays: Int = 0
        var receivedRecordsByDate: [Date: HealthData] = [:]
        var lastChunkDigest: String?
        var lastChunkAcknowledgement: MacExportStreamChunkAck?
    }

    init() {}

    var isBusy: Bool { activeJobID != nil }
    var currentJobID: UUID? { activeJobID }

    @discardableResult
    func cancel(
        jobID: UUID,
        message: String = "Mac export cancelled.",
        progress: ProgressHandler? = nil
    ) -> MacExportFailure? {
        cancelledJobIDs.insert(jobID)

        // A non-streamed job is already executing on the Mac and will observe
        // `cancelledJobIDs` at its next cancellation checkpoint. A streamed job,
        // however, can be orphaned if iOS backgrounds/disconnects before sending
        // the next chunk or final completion message. Clear streamed state
        // immediately so the Mac destination does not stay busy forever.
        guard activeJobID == jobID, streamSession != nil else { return nil }

        sendProgress(
            jobID: jobID,
            phase: .cancelled,
            processedDays: streamSession?.processedDays ?? 0,
            totalDays: streamSession?.start.totalTransferDays ?? 0,
            currentDate: nil,
            filesWritten: streamSession?.totalFilesWritten ?? 0,
            message: message,
            progress: progress
        )

        streamSession = nil
        activeJobID = nil
        cancelledJobIDs.remove(jobID)
        return MacExportFailure(
            jobID: jobID,
            reason: .cancelled,
            message: message
        )
    }

    func execute(
        _ job: MacExportJob,
        vaultManager: VaultManager,
        progress: ProgressHandler? = nil
    ) async -> Result<MacExportResultPayload, MacExportFailure> {
        guard activeJobID == nil else {
            return .failure(MacExportFailure(
                jobID: job.jobID,
                reason: .macBusy,
                message: "This Mac is already exporting another job."
            ))
        }

        activeJobID = job.jobID
        defer {
            activeJobID = nil
            cancelledJobIDs.remove(job.jobID)
        }

        guard let requestedDates = Self.validatedRequestedDates(
            explicitDates: job.requestedDates,
            dateRangeStart: job.dateRangeStart,
            dateRangeEnd: job.dateRangeEnd
        ) else {
            return .failure(MacExportFailure(
                jobID: job.jobID,
                reason: .payloadDecodeFailure,
                message: "Mac export requested dates were malformed or inconsistent with the declared range."
            ))
        }
        let totalDays = requestedDates.count
        let formatsPerDate = Self.looseFormatsPerDate(for: job.settingsSnapshot)

        sendProgress(
            jobID: job.jobID,
            phase: .receiving,
            processedDays: 0,
            totalDays: totalDays,
            currentDate: nil,
            filesWritten: 0,
            message: "Received export job from \(job.sourceDeviceName)",
            progress: progress
        )

        if cancelledJobIDs.contains(job.jobID) || Task.isCancelled {
            return .success(cancelledResult(for: job, totalDays: totalDays, formatsPerDate: formatsPerDate, vaultManager: vaultManager))
        }

        sendProgress(
            jobID: job.jobID,
            phase: .validating,
            processedDays: 0,
            totalDays: totalDays,
            currentDate: nil,
            filesWritten: 0,
            message: "Validating Mac destination…",
            progress: progress
        )

        if let validationFailure = validate(job, vaultManager: vaultManager) {
            return .failure(validationFailure)
        }

        let settings = job.settingsSnapshot.makeAdvancedExportSettings()
        let recordsByDate = Self.recordsByStartOfDay(job.records)
        let externalRecordsByDate = Self.externalRecordsByDate(job.externalDailyRecords)
        var successCount = 0
        var failedDateDetails: [FailedDateDetail] = []
        var successfulRecords: [HealthData] = []
        var totalFilesWritten = 0
        var externalRecordFileCount = 0
        var dailyNoteUpdateCount = 0
        var dailyNoteSkipCount = 0
        var processedDays = 0

        for date in requestedDates {
            if cancelledJobIDs.contains(job.jobID) || Task.isCancelled {
                let result = MacExportResultPayload(
                    jobID: job.jobID,
                    status: .cancelled,
                    successCount: successCount,
                    totalCount: totalDays,
                    formatsPerDate: formatsPerDate,
                    totalFilesWritten: totalFilesWritten,
                    externalRecordFileCount: externalRecordFileCount,
                    dailyNoteUpdateCount: dailyNoteUpdateCount,
                    dailyNoteSkipCount: dailyNoteSkipCount,
                    failedDateDetails: failedDateDetails,
                    completedDates: Self.completedDates(
                        successfulRecords: successfulRecords,
                        failedDateDetails: failedDateDetails,
                        requestedDates: requestedDates,
                        includeSuccessfulRecords: !settings.archiveModeEnabled
                            && !settings.summaryOnlyModeEnabled
                    ),
                    destinationDisplayName: vaultManager.vaultName,
                    destinationPathForDisplay: vaultManager.vaultURL?.path,
                    completedAt: Date()
                )
                sendProgress(
                    jobID: job.jobID,
                    phase: .cancelled,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: date,
                    filesWritten: totalFilesWritten,
                    message: "Mac export cancelled.",
                    progress: progress
                )
                return .success(result)
            }

            processedDays += 1
            guard let record = recordsByDate[Calendar.current.startOfDay(for: date)] else {
                failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
                sendProgress(
                    jobID: job.jobID,
                    phase: .exporting,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: date,
                    filesWritten: totalFilesWritten,
                    message: "No health data for \(Self.displayDate(date))",
                    progress: progress
                )
                continue
            }

            sendProgress(
                jobID: job.jobID,
                phase: .writing,
                processedDays: processedDays - 1,
                totalDays: totalDays,
                currentDate: record.date,
                filesWritten: totalFilesWritten,
                message: settings.summaryOnlyModeEnabled
                    ? "Preparing \(Self.displayDate(record.date)) for summaries…"
                    : (settings.dailyNotesOnlyModeEnabled
                       ? "Updating daily note \(Self.displayDate(record.date))…"
                       : "Writing \(Self.displayDate(record.date))…"),
                progress: progress
            )

            if settings.summaryOnlyModeEnabled {
                successCount += 1
                successfulRecords.append(record)
                sendProgress(
                    jobID: job.jobID,
                    phase: .writing,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: record.date,
                    filesWritten: totalFilesWritten,
                    message: "Prepared \(Self.displayDate(record.date)) for summaries",
                    progress: progress
                )
                continue
            }

            do {
                let writeResult = try await vaultManager.exportHealthData(
                    record,
                    settings: settings,
                    healthSubfolder: job.settingsSnapshot.healthSubfolder
                )
                dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                dailyNoteSkipCount += writeResult.dailyNoteSkippedCount
                if settings.dailyNotesOnlyModeEnabled {
                    switch writeResult.dailyNoteResult {
                    case .updated:
                        break
                    case .skipped(let reason):
                        failedDateDetails.append(FailedDateDetail(
                            date: record.date,
                            reason: .noHealthData,
                            errorDetails: reason
                        ))
                        continue
                    case .failed(let error):
                        failedDateDetails.append(FailedDateDetail(
                            date: record.date,
                            reason: .fileWriteError,
                            errorDetails: error.localizedDescription
                        ))
                        continue
                    case .none:
                        failedDateDetails.append(FailedDateDetail(
                            date: record.date,
                            reason: .fileWriteError,
                            errorDetails: "Daily note update was not performed."
                        ))
                        continue
                    }
                }
                successCount += 1
                successfulRecords.append(record)
                totalFilesWritten += formatsPerDate

                let dateKey = Self.displayDate(record.date)
                var writtenSidecarsForDate = 0
                if settings.writesExternalProviderSidecars,
                   let externalRecords = externalRecordsByDate[dateKey],
                   !externalRecords.isEmpty {
                    do {
                        writtenSidecarsForDate = try await vaultManager.exportExternalDailyRecords(
                            externalRecords,
                            healthSubfolder: job.settingsSnapshot.healthSubfolder
                        )
                        externalRecordFileCount += writtenSidecarsForDate
                        totalFilesWritten += writtenSidecarsForDate
                    } catch {
                        failedDateDetails.append(FailedDateDetail(
                            date: record.date,
                            reason: .fileWriteError,
                            errorDetails: "External provider sidecar export failed: \(error.localizedDescription)"
                        ))
                    }
                }

                sendProgress(
                    jobID: job.jobID,
                    phase: .writing,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: record.date,
                    filesWritten: totalFilesWritten,
                    message: settings.dailyNotesOnlyModeEnabled
                        ? "Updated daily note \(Self.displayDate(record.date))"
                        : (writtenSidecarsForDate > 0
                           ? "Wrote \(Self.displayDate(record.date)) and provider sidecars"
                           : "Wrote \(Self.displayDate(record.date))"),
                    progress: progress
                )
            } catch {
                failedDateDetails.append(Self.failedDateDetail(for: record.date, error: error))
                sendProgress(
                    jobID: job.jobID,
                    phase: .failed,
                    processedDays: processedDays,
                    totalDays: totalDays,
                    currentDate: record.date,
                    filesWritten: totalFilesWritten,
                    message: error.localizedDescription,
                    progress: progress
                )
            }
        }

        let rollupRecords = Self.rollupRecords(
            for: requestedDates,
            recordsByDate: recordsByDate,
            settings: settings
        )
        if !settings.archiveModeEnabled,
           !rollupRecords.isEmpty,
           HealthRollupExporter.isEnabled(settings: settings) {
            sendProgress(
                jobID: job.jobID,
                phase: .writing,
                processedDays: processedDays,
                totalDays: totalDays,
                currentDate: nil,
                filesWritten: totalFilesWritten,
                message: "Writing roll-up summaries…",
                progress: progress
            )

            do {
                let rollupResults = try vaultManager.exportRollupSummaries(
                    from: rollupRecords,
                    settings: settings,
                    healthSubfolder: job.settingsSnapshot.healthSubfolder
                )
                totalFilesWritten += rollupResults.count
            } catch {
                let sortedDates = rollupRecords.map(\.date).sorted()
                failedDateDetails.append(FailedDateDetail(
                    date: sortedDates.first ?? Date(),
                    reason: .fileWriteError,
                    errorDetails: "Roll-up summary export failed: \(error.localizedDescription)"
                ))
            }
        }

        var archiveFileCount = 0
        if settings.archiveModeEnabled && !successfulRecords.isEmpty {
            sendProgress(
                jobID: job.jobID,
                phase: .writing,
                processedDays: processedDays,
                totalDays: totalDays,
                currentDate: nil,
                filesWritten: totalFilesWritten,
                message: "Writing ZIP archive…",
                progress: progress
            )
            archiveFileCount = Self.writeArchive(
                from: successfulRecords,
                rollupHealthData: rollupRecords,
                selectedDates: requestedDates,
                vaultManager: vaultManager,
                settings: settings,
                healthSubfolder: job.settingsSnapshot.healthSubfolder,
                failedDateDetails: &failedDateDetails
            )
            totalFilesWritten += archiveFileCount
        }

        if settings.summaryOnlyModeEnabled && totalFilesWritten == 0 && failedDateDetails.isEmpty {
            successCount = 0
            failedDateDetails.append(FailedDateDetail(
                date: requestedDates.first ?? Date(),
                reason: .noHealthData,
                errorDetails: "No roll-up summary data was available for the selected period."
            ))
        }

        let status: MacExportResultStatus
        if successCount == totalDays && failedDateDetails.isEmpty {
            status = .success
        } else if successCount > 0 || dailyNoteSkipCount > 0 {
            status = .partialSuccess
        } else {
            status = .failure
        }

        let result = MacExportResultPayload(
            jobID: job.jobID,
            status: status,
            successCount: successCount,
            totalCount: totalDays,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: totalFilesWritten,
            externalRecordFileCount: externalRecordFileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            failedDateDetails: failedDateDetails,
            completedDates: Self.completedDates(
                successfulRecords: successfulRecords,
                failedDateDetails: failedDateDetails,
                requestedDates: requestedDates,
                includeSuccessfulRecords: settings.archiveModeEnabled
                    ? archiveFileCount > 0
                    : (!settings.summaryOnlyModeEnabled || totalFilesWritten > 0),
                summaryOnlyModeEnabled: settings.summaryOnlyModeEnabled
            ),
            destinationDisplayName: vaultManager.vaultName,
            destinationPathForDisplay: vaultManager.vaultURL?.path,
            completedAt: Date()
        )

        sendProgress(
            jobID: job.jobID,
            phase: status == .failure ? .failed : .completed,
            processedDays: processedDays,
            totalDays: totalDays,
            currentDate: nil,
            filesWritten: totalFilesWritten,
            message: Self.completionMessage(for: result),
            progress: progress
        )

        return .success(result)
    }

    func startStream(
        _ start: MacExportStreamStart,
        vaultManager: VaultManager,
        progress: ProgressHandler? = nil
    ) -> Result<MacExportStreamChunkAck, MacExportFailure> {
        guard activeJobID == nil else {
            return .failure(MacExportFailure(
                jobID: start.jobID,
                reason: .macBusy,
                message: "This Mac is already exporting another job."
            ))
        }

        activeJobID = start.jobID

        sendProgress(
            jobID: start.jobID,
            phase: .receiving,
            processedDays: 0,
            totalDays: start.totalTransferDays,
            currentDate: nil,
            filesWritten: 0,
            message: "Started streamed export from \(start.sourceDeviceName)",
            progress: progress
        )

        if let validationFailure = validateDestinationAndFormats(
            jobID: start.jobID,
            settingsSnapshot: start.settingsSnapshot,
            vaultManager: vaultManager
        ) {
            activeJobID = nil
            return .failure(validationFailure)
        }

        guard start.totalRequestedDays > 0,
              start.totalTransferDays >= start.totalRequestedDays,
              let requestedDates = Self.validatedRequestedDates(
                explicitDates: start.requestedDates,
                dateRangeStart: start.dateRangeStart,
                dateRangeEnd: start.dateRangeEnd,
                expectedCount: start.totalRequestedDays
              ) else {
            activeJobID = nil
            return .failure(MacExportFailure(
                jobID: start.jobID,
                reason: .payloadDecodeFailure,
                message: "Mac export stream dates or counters were malformed or inconsistent."
            ))
        }
        streamSession = StreamSession(
            start: start,
            requestedDates: requestedDates,
            formatsPerDate: Self.looseFormatsPerDate(for: start.settingsSnapshot)
        )

        sendProgress(
            jobID: start.jobID,
            phase: .validating,
            processedDays: 0,
            totalDays: start.totalTransferDays,
            currentDate: nil,
            filesWritten: 0,
            message: "Mac destination ready for streamed export.",
            progress: progress
        )

        return .success(MacExportStreamChunkAck(
            jobID: start.jobID,
            sequence: -1,
            accepted: true,
            message: "Stream accepted. Send chunk sequence 1 next.",
            processedDays: 0,
            filesWritten: 0
        ))
    }

    func receiveChunk(
        _ chunk: MacExportStreamChunk,
        vaultManager: VaultManager,
        progress: ProgressHandler? = nil
    ) async -> Result<MacExportStreamChunkAck, MacExportFailure> {
        guard var session = streamSession, activeJobID == chunk.jobID else {
            return .failure(MacExportFailure(
                jobID: chunk.jobID,
                reason: .payloadDecodeFailure,
                message: "No active stream exists for this chunk."
            ))
        }

        let chunkDigest = Self.streamChunkDigest(chunk)
        if chunk.sequence == session.expectedSequence - 1,
           let priorDigest = session.lastChunkDigest,
           let priorAcknowledgement = session.lastChunkAcknowledgement {
            guard priorDigest == chunkDigest else {
                return .success(MacExportStreamChunkAck(
                    jobID: chunk.jobID,
                    sequence: chunk.sequence,
                    accepted: false,
                    message: "Duplicate chunk content changed for sequence \(chunk.sequence).",
                    processedDays: session.processedDays,
                    filesWritten: session.totalFilesWritten
                ))
            }
            return .success(priorAcknowledgement)
        }

        guard chunk.sequence == session.expectedSequence else {
            return .success(MacExportStreamChunkAck(
                jobID: chunk.jobID,
                sequence: chunk.sequence,
                accepted: false,
                message: "Expected chunk sequence \(session.expectedSequence), received \(chunk.sequence).",
                processedDays: session.processedDays,
                filesWritten: session.totalFilesWritten
            ))
        }

        if cancelledJobIDs.contains(chunk.jobID) || Task.isCancelled {
            streamSession = session
            return .failure(MacExportFailure(
                jobID: chunk.jobID,
                reason: .cancelled,
                message: "Mac export cancelled."
            ))
        }

        let settings = session.start.settingsSnapshot.makeAdvancedExportSettings()
        let shouldWriteDailyAsChunksArrive = !settings.archiveModeEnabled && !settings.summaryOnlyModeEnabled
        let externalRecordsByDate = Self.externalRecordsByDate(chunk.externalDailyRecords)
        if !shouldWriteDailyAsChunksArrive {
            session.retainedExternalDailyRecords.append(contentsOf: chunk.externalDailyRecords)
        }

        let requestedDays = Set(session.requestedDates.map { Calendar.current.startOfDay(for: $0) })
        for record in chunk.records {
            let dateKey = Calendar.current.startOfDay(for: record.date)
            let isRequestedDay = requestedDays.contains(dateKey)
            session.receivedRecordsByDate[dateKey] = record
            session.processedDays += 1

            sendProgress(
                jobID: chunk.jobID,
                phase: .writing,
                processedDays: max(session.processedDays - 1, 0),
                totalDays: session.start.totalTransferDays,
                currentDate: record.date,
                filesWritten: session.totalFilesWritten,
                message: shouldWriteDailyAsChunksArrive && isRequestedDay
                    ? (settings.dailyNotesOnlyModeEnabled
                       ? "Updating daily note \(Self.displayDate(record.date))…"
                       : "Writing \(Self.displayDate(record.date))…")
                    : "Received \(Self.displayDate(record.date)) for finalization…",
                progress: progress
            )

            if shouldWriteDailyAsChunksArrive && isRequestedDay {
                do {
                    let writeResult = try await vaultManager.exportHealthData(
                        record,
                        settings: settings,
                        healthSubfolder: session.start.settingsSnapshot.healthSubfolder
                    )
                    session.dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                    session.dailyNoteSkipCount += writeResult.dailyNoteSkippedCount
                    if settings.dailyNotesOnlyModeEnabled {
                        switch writeResult.dailyNoteResult {
                        case .updated:
                            break
                        case .skipped(let reason):
                            session.failedDateDetails.append(FailedDateDetail(
                                date: record.date,
                                reason: .noHealthData,
                                errorDetails: reason
                            ))
                            continue
                        case .failed(let error):
                            session.failedDateDetails.append(FailedDateDetail(
                                date: record.date,
                                reason: .fileWriteError,
                                errorDetails: error.localizedDescription
                            ))
                            continue
                        case .none:
                            session.failedDateDetails.append(FailedDateDetail(
                                date: record.date,
                                reason: .fileWriteError,
                                errorDetails: "Daily note update was not performed."
                            ))
                            continue
                        }
                    }
                    session.successCount += 1
                    session.successfulRecords.append(record)
                    session.totalFilesWritten += session.formatsPerDate

                    let stringDateKey = Self.displayDate(record.date)
                    if settings.writesExternalProviderSidecars,
                       let externalRecords = externalRecordsByDate[stringDateKey],
                       !externalRecords.isEmpty {
                        do {
                            let sidecarCount = try await vaultManager.exportExternalDailyRecords(
                                externalRecords,
                                healthSubfolder: session.start.settingsSnapshot.healthSubfolder
                            )
                            session.externalRecordFileCount += sidecarCount
                            session.totalFilesWritten += sidecarCount
                        } catch {
                            session.failedDateDetails.append(FailedDateDetail(
                                date: record.date,
                                reason: .fileWriteError,
                                errorDetails: "External provider sidecar export failed: \(error.localizedDescription)"
                            ))
                        }
                    }
                } catch {
                    session.failedDateDetails.append(Self.failedDateDetail(for: record.date, error: error))
                }
            } else if !shouldWriteDailyAsChunksArrive && isRequestedDay {
                session.successfulRecords.append(record)
            }

            sendProgress(
                jobID: chunk.jobID,
                phase: .writing,
                processedDays: session.processedDays,
                totalDays: session.start.totalTransferDays,
                currentDate: record.date,
                filesWritten: session.totalFilesWritten,
                message: "Accepted streamed record for \(Self.displayDate(record.date))",
                progress: progress
            )
        }

        session.expectedSequence += 1
        let acknowledgement = MacExportStreamChunkAck(
            jobID: chunk.jobID,
            sequence: chunk.sequence,
            accepted: true,
            message: "Chunk \(chunk.sequence) accepted.",
            processedDays: session.processedDays,
            filesWritten: session.totalFilesWritten
        )
        session.lastChunkDigest = chunkDigest
        session.lastChunkAcknowledgement = acknowledgement
        streamSession = session

        return .success(acknowledgement)
    }

    func completeStream(
        _ complete: MacExportStreamComplete,
        vaultManager: VaultManager,
        progress: ProgressHandler? = nil
    ) async -> Result<MacExportResultPayload, MacExportFailure> {
        guard var session = streamSession, activeJobID == complete.jobID else {
            return .failure(MacExportFailure(
                jobID: complete.jobID,
                reason: .payloadDecodeFailure,
                message: "No active stream exists for completion."
            ))
        }
        defer {
            activeJobID = nil
            streamSession = nil
            cancelledJobIDs.remove(complete.jobID)
        }

        let acceptedChunkCount = session.expectedSequence - 1
        if complete.totalChunks != acceptedChunkCount {
            return .failure(MacExportFailure(
                jobID: complete.jobID,
                reason: .payloadDecodeFailure,
                message: "Stream completed with \(complete.totalChunks) chunk(s), but Mac accepted \(acceptedChunkCount)."
            ))
        }

        let settings = session.start.settingsSnapshot.makeAdvancedExportSettings()
        let shouldWriteDailyAsChunksArrive = !settings.archiveModeEnabled && !settings.summaryOnlyModeEnabled
        session.failedDateDetails.append(contentsOf: complete.iphoneFailedDateDetails)

        for date in session.requestedDates {
            if session.receivedRecordsByDate[Calendar.current.startOfDay(for: date)] == nil,
               !complete.iphoneFailedDateDetails.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                session.failedDateDetails.append(FailedDateDetail(date: date, reason: .noHealthData))
            }
        }

        if !shouldWriteDailyAsChunksArrive {
            let recordsByDate = session.receivedRecordsByDate
            let externalRecordsByDate = Self.externalRecordsByDate(session.retainedExternalDailyRecords)
            session.successCount = 0
            session.successfulRecords = []

            for date in session.requestedDates {
                guard let record = recordsByDate[Calendar.current.startOfDay(for: date)] else { continue }
                if settings.summaryOnlyModeEnabled {
                    session.successCount += 1
                    session.successfulRecords.append(record)
                    continue
                }
                do {
                    let writeResult = try await vaultManager.exportHealthData(
                        record,
                        settings: settings,
                        healthSubfolder: session.start.settingsSnapshot.healthSubfolder
                    )
                    session.dailyNoteUpdateCount += writeResult.dailyNoteUpdatedCount
                    session.dailyNoteSkipCount += writeResult.dailyNoteSkippedCount
                    session.successCount += 1
                    session.successfulRecords.append(record)
                    session.totalFilesWritten += session.formatsPerDate
                    let dateKey = Self.displayDate(record.date)
                    if settings.writesExternalProviderSidecars,
                       let externalRecords = externalRecordsByDate[dateKey],
                       !externalRecords.isEmpty {
                        let sidecarCount = try await vaultManager.exportExternalDailyRecords(
                            externalRecords,
                            healthSubfolder: session.start.settingsSnapshot.healthSubfolder
                        )
                        session.externalRecordFileCount += sidecarCount
                        session.totalFilesWritten += sidecarCount
                    }
                } catch {
                    session.failedDateDetails.append(Self.failedDateDetail(for: record.date, error: error))
                }
            }
        }

        let rollupRecords = Self.rollupRecords(
            for: session.requestedDates,
            recordsByDate: session.receivedRecordsByDate,
            settings: settings
        )
        if !settings.archiveModeEnabled,
           !rollupRecords.isEmpty,
           HealthRollupExporter.isEnabled(settings: settings) {
            do {
                let rollupResults = try vaultManager.exportRollupSummaries(
                    from: rollupRecords,
                    settings: settings,
                    healthSubfolder: session.start.settingsSnapshot.healthSubfolder
                )
                session.totalFilesWritten += rollupResults.count
            } catch {
                let sortedDates = rollupRecords.map(\.date).sorted()
                session.failedDateDetails.append(FailedDateDetail(
                    date: sortedDates.first ?? session.start.dateRangeStart,
                    reason: .fileWriteError,
                    errorDetails: "Roll-up summary export failed: \(error.localizedDescription)"
                ))
            }
        }

        var archiveFileCount = 0
        if settings.archiveModeEnabled && !session.successfulRecords.isEmpty {
            archiveFileCount = Self.writeArchive(
                from: session.successfulRecords,
                rollupHealthData: rollupRecords,
                selectedDates: session.requestedDates,
                vaultManager: vaultManager,
                settings: settings,
                healthSubfolder: session.start.settingsSnapshot.healthSubfolder,
                failedDateDetails: &session.failedDateDetails
            )
            session.totalFilesWritten += archiveFileCount
            session.successCount = session.requestedDates.filter {
                session.receivedRecordsByDate[Calendar.current.startOfDay(for: $0)] != nil
            }.count
        }

        if settings.summaryOnlyModeEnabled && session.totalFilesWritten == 0 && session.failedDateDetails.isEmpty {
            session.successCount = 0
            session.failedDateDetails.append(FailedDateDetail(
                date: session.requestedDates.first ?? session.start.dateRangeStart,
                reason: .noHealthData,
                errorDetails: "No roll-up summary data was available for the selected period."
            ))
        }

        let totalDays = session.start.totalRequestedDays
        let status: MacExportResultStatus
        if session.successCount == totalDays && session.failedDateDetails.isEmpty {
            status = .success
        } else if session.successCount > 0 || session.dailyNoteSkipCount > 0 {
            status = .partialSuccess
        } else {
            status = .failure
        }

        let result = MacExportResultPayload(
            jobID: complete.jobID,
            status: status,
            successCount: session.successCount,
            totalCount: totalDays,
            formatsPerDate: session.formatsPerDate,
            totalFilesWritten: session.totalFilesWritten,
            externalRecordFileCount: session.externalRecordFileCount,
            dailyNoteUpdateCount: session.dailyNoteUpdateCount,
            dailyNoteSkipCount: session.dailyNoteSkipCount,
            failedDateDetails: session.failedDateDetails,
            completedDates: Self.completedDates(
                successfulRecords: session.successfulRecords,
                failedDateDetails: session.failedDateDetails,
                requestedDates: session.requestedDates,
                includeSuccessfulRecords: settings.archiveModeEnabled
                    ? archiveFileCount > 0
                    : (!settings.summaryOnlyModeEnabled || session.totalFilesWritten > 0),
                summaryOnlyModeEnabled: settings.summaryOnlyModeEnabled
            ),
            destinationDisplayName: vaultManager.vaultName,
            destinationPathForDisplay: vaultManager.vaultURL?.path,
            completedAt: Date()
        )

        sendProgress(
            jobID: complete.jobID,
            phase: status == .failure ? .failed : .completed,
            processedDays: session.processedDays,
            totalDays: session.start.totalTransferDays,
            currentDate: nil,
            filesWritten: session.totalFilesWritten,
            message: Self.completionMessage(for: result),
            progress: progress
        )

        return .success(result)
    }

    func abortStream(
        _ abort: MacExportStreamAbort,
        progress: ProgressHandler? = nil
    ) {
        guard activeJobID == abort.jobID else { return }
        sendProgress(
            jobID: abort.jobID,
            phase: .cancelled,
            processedDays: streamSession?.processedDays ?? 0,
            totalDays: streamSession?.start.totalTransferDays ?? 0,
            currentDate: nil,
            filesWritten: streamSession?.totalFilesWritten ?? 0,
            message: abort.message,
            progress: progress
        )
        cancelledJobIDs.remove(abort.jobID)
        streamSession = nil
        activeJobID = nil
    }

    private func validate(_ job: MacExportJob, vaultManager: VaultManager) -> MacExportFailure? {
        if let failure = validateDestinationAndFormats(
            jobID: job.jobID,
            settingsSnapshot: job.settingsSnapshot,
            vaultManager: vaultManager
        ) {
            return failure
        }

        guard !job.records.isEmpty else {
            return MacExportFailure(
                jobID: job.jobID,
                reason: .noHealthRecordsReceived,
                message: "No health records were received from iPhone."
            )
        }

        return nil
    }

    private func validateDestinationAndFormats(
        jobID: UUID,
        settingsSnapshot: ExportSettingsSnapshot,
        vaultManager: VaultManager
    ) -> MacExportFailure? {
        guard vaultManager.vaultURL != nil else {
            return MacExportFailure(
                jobID: jobID,
                reason: .noMacFolderSelected,
                message: "Choose a destination folder on this Mac before exporting."
            )
        }

        guard vaultManager.canAccessSelectedVaultFolder() else {
            return MacExportFailure(
                jobID: jobID,
                reason: .macFolderAccessDenied,
                message: "Health.md can’t access the selected Mac folder. Re-select the destination folder on this Mac and try again."
            )
        }

        guard settingsSnapshot.hasFileDestinationOutput else {
            return MacExportFailure(
                jobID: jobID,
                reason: .noFormatsSelected,
                message: "Select an export format or enable Daily Notes Only on iPhone."
            )
        }

        return nil
    }

    private func sendProgress(
        jobID: UUID,
        phase: MacExportPhase,
        processedDays: Int,
        totalDays: Int,
        currentDate: Date?,
        filesWritten: Int,
        message: String,
        progress: ProgressHandler?
    ) {
        progress?(MacExportProgress(
            jobID: jobID,
            phase: phase,
            processedDays: processedDays,
            totalDays: totalDays,
            currentDate: currentDate,
            filesWritten: filesWritten,
            message: message
        ))
    }

    private func cancelledResult(
        for job: MacExportJob,
        totalDays: Int,
        formatsPerDate: Int,
        vaultManager: VaultManager
    ) -> MacExportResultPayload {
        MacExportResultPayload(
            jobID: job.jobID,
            status: .cancelled,
            successCount: 0,
            totalCount: totalDays,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: 0,
            externalRecordFileCount: 0,
            failedDateDetails: [],
            completedDates: [],
            destinationDisplayName: vaultManager.vaultName,
            destinationPathForDisplay: vaultManager.vaultURL?.path,
            completedAt: Date()
        )
    }

    private static func streamChunkDigest(_ chunk: MacExportStreamChunk) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(chunk)).map(ConnectedTransferFile.sha256Hex) ?? ""
    }

    private static func completedDates(
        successfulRecords: [HealthData],
        failedDateDetails: [FailedDateDetail],
        requestedDates: [Date],
        includeSuccessfulRecords: Bool = true,
        summaryOnlyModeEnabled: Bool = false,
        calendar: Calendar = .current
    ) -> [Date] {
        let requestedDays = Set(requestedDates.map { calendar.startOfDay(for: $0) })
        if summaryOnlyModeEnabled,
           successfulRecords.isEmpty,
           failedDateDetails.contains(where: { $0.reason == .noHealthData }) {
            return requestedDates.sorted()
        }

        var completedDays = includeSuccessfulRecords
            ? Set(successfulRecords.map { calendar.startOfDay(for: $0.date) })
            : []
        completedDays.formIntersection(requestedDays)
        completedDays.formUnion(failedDateDetails.compactMap { detail in
            guard detail.reason == .noHealthData else { return nil }
            let day = calendar.startOfDay(for: detail.date)
            return requestedDays.contains(day) ? day : nil
        })
        let retryableFailureDays: Set<Date> = Set(failedDateDetails.compactMap { detail in
            guard detail.reason != .noHealthData else { return nil }
            return calendar.startOfDay(for: detail.date)
        })
        completedDays.subtract(retryableFailureDays)
        // Return the exact source-device instants rather than Mac-normalized
        // midnights so iPhone can reconcile the same requested calendar days.
        return requestedDates.filter {
            completedDays.contains(calendar.startOfDay(for: $0))
        }
    }

    private static func validatedRequestedDates(
        explicitDates: [Date]?,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        expectedCount: Int? = nil
    ) -> [Date]? {
        guard dateRangeStart <= dateRangeEnd else { return nil }

        let dates: [Date]
        if let explicitDates {
            guard !explicitDates.isEmpty,
                  explicitDates == explicitDates.sorted(),
                  Set(explicitDates).count == explicitDates.count,
                  explicitDates.first.map({ Calendar.current.isDate($0, inSameDayAs: dateRangeStart) }) == true,
                  explicitDates.last.map({ Calendar.current.isDate($0, inSameDayAs: dateRangeEnd) }) == true else {
                return nil
            }
            dates = explicitDates
        } else {
            dates = ExportOrchestrator.dateRange(from: dateRangeStart, to: dateRangeEnd)
        }

        guard !dates.isEmpty else { return nil }
        if let expectedCount, expectedCount != dates.count { return nil }
        return dates
    }

    private static func looseFormatsPerDate(for snapshot: ExportSettingsSnapshot) -> Int {
        snapshot.makeAdvancedExportSettings().looseFormatsPerDate
    }

    private static func recordsByStartOfDay(_ records: [HealthData]) -> [Date: HealthData] {
        var result: [Date: HealthData] = [:]
        for record in records {
            result[Calendar.current.startOfDay(for: record.date)] = record
        }
        return result
    }

    private static func externalRecordsByDate(_ records: [ExternalDailyRecord]) -> [String: [ExternalDailyRecord]] {
        Dictionary(grouping: records.filter(\.shouldExport), by: \.date)
    }

    private static func rollupRecords(
        for requestedDates: [Date],
        recordsByDate: [Date: HealthData],
        settings: AdvancedExportSettings
    ) -> [HealthData] {
        guard HealthRollupExporter.isEnabled(settings: settings) else { return [] }
        let sourceDates = ExportOrchestrator.rollupSourceDates(for: requestedDates, settings: settings)
        return sourceDates.compactMap { date in
            recordsByDate[Calendar.current.startOfDay(for: date)]
        }
    }

    private static func writeArchive(
        from successfulRecords: [HealthData],
        rollupHealthData: [HealthData],
        selectedDates: [Date],
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        healthSubfolder: String?,
        failedDateDetails: inout [FailedDateDetail]
    ) -> Int {
        guard settings.archiveModeEnabled else { return 0 }
        guard !successfulRecords.isEmpty || (settings.summaryOnlyModeEnabled && !rollupHealthData.isEmpty) else { return 0 }

        let sortedDates = selectedDates.sorted()
        let startDate = sortedDates.first ?? successfulRecords.map(\.date).min() ?? Date()
        let endDate = sortedDates.last ?? successfulRecords.map(\.date).max() ?? startDate

        do {
            return try vaultManager.exportArchive(
                from: successfulRecords,
                rollupHealthData: rollupHealthData,
                settings: settings,
                startDate: startDate,
                endDate: endDate,
                healthSubfolder: healthSubfolder
            ) == nil ? 0 : 1
        } catch {
            failedDateDetails.append(FailedDateDetail(
                date: startDate,
                reason: .fileWriteError,
                errorDetails: "ZIP archive export failed: \(error.localizedDescription)"
            ))
            return 0
        }
    }

    private static func failedDateDetail(for date: Date, error: Error) -> FailedDateDetail {
        if let exportError = error as? ExportError {
            switch exportError {
            case .noVaultSelected:
                return FailedDateDetail(date: date, reason: .noVaultSelected)
            case .noHealthData:
                return FailedDateDetail(date: date, reason: .noHealthData)
            case .accessDenied:
                return FailedDateDetail(date: date, reason: .accessDenied)
            case .noFormatsSelected, .dailyNotePathConflict:
                return FailedDateDetail(date: date, reason: .fileWriteError, errorDetails: exportError.localizedDescription)
            }
        }
        return FailedDateDetail(date: date, reason: .fileWriteError, errorDetails: error.localizedDescription)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func completionMessage(for result: MacExportResultPayload) -> String {
        switch result.status {
        case .success:
            if result.dailyNoteUpdateCount > 0 && result.totalFilesWritten == 0 {
                return "Updated \(result.dailyNoteUpdateCount) daily note\(result.dailyNoteUpdateCount == 1 ? "" : "s") on Mac."
            }
            return "Export complete on Mac."
        case .partialSuccess:
            if result.dailyNoteSkipCount > 0 && result.totalFilesWritten == 0 {
                return "Updated \(result.dailyNoteUpdateCount) and skipped \(result.dailyNoteSkipCount) daily notes on Mac."
            }
            if result.dailyNoteUpdateCount > 0 && result.totalFilesWritten == 0 {
                return "Updated \(result.dailyNoteUpdateCount)/\(result.totalCount) daily notes on Mac."
            }
            return "Mac export completed with some skipped dates."
        case .failure:
            return "Mac export failed."
        case .cancelled:
            return "Mac export cancelled."
        }
    }
}

#endif
