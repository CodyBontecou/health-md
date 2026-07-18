#if os(iOS)
import Foundation
import UIKit

/// Corpus producer used by iPhone-initiated interactive and scheduled Mac
/// exports. It spools one HealthKit day at a time and transfers only bounded
/// checksum partitions.
@MainActor
enum IPhoneConnectedCorpusProducer {
    struct Result {
        let sessionID: UUID
        let acknowledgement: ConnectedCorpusTransferFinalAck
    }

    enum ProducerError: Error, LocalizedError {
        case peerRejected(String)
        case partitionFailed(String)
        case finalizationFailed

        var errorDescription: String? {
            switch self {
            case .peerRejected(let message), .partitionFailed(let message): return message
            case .finalizationFailed: return "Mac did not finalize the partitioned corpus export."
            }
        }
    }

    static func sendFileExport(
        jobID: UUID,
        startDate: Date,
        endDate: Date,
        requestedDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        destinationDisplayName: String?,
        negotiation: ConnectedCorpusTransferNegotiation,
        healthKitManager: HealthKitManager,
        externalRecordFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?,
        syncService: SyncService,
        progress: ((_ processedDays: Int, _ totalDays: Int, _ date: Date, _ message: String) -> Void)? = nil
    ) async throws -> Result {
        let metadata = MacExportStreamingJobBuilder.metadata(
            startDate: startDate,
            endDate: endDate,
            requestedDates: requestedDates,
            settings: settings,
            healthSubfolder: healthSubfolder,
            destinationDisplayName: destinationDisplayName
        )
        let createdAt = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let exportManifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: createdAt,
            sourceDeviceName: UIDevice.current.name,
            sourceTimeZoneIdentifier: TimeZone.current.identifier,
            dateRangeStart: metadata.dateRangeStart,
            dateRangeEnd: metadata.dateRangeEnd,
            requestedDates: metadata.requestedDates,
            requestedDateIdentifiers: metadata.requestedDates.map { dateFormatter.string(from: $0) },
            transferDates: metadata.transferDates,
            settingsSnapshot: metadata.settingsSnapshot,
            requestedTarget: metadata.requestedTarget
        )
        try exportManifest.validate()
        let fingerprint = try ConnectedCorpusRequestFingerprint.make(for: exportManifest)
        let session = ConnectedCorpusTransferSession(
            sessionID: UUID(),
            jobID: jobID,
            requestFingerprint: fingerprint,
            protocolVersion: negotiation.protocolVersion,
            partitionTargetBytes: negotiation.partitionTargetBytes,
            createdAt: createdAt
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: session.sessionID,
            jobID: jobID,
            targetBytes: negotiation.partitionTargetBytes
        )
        var partitionCount = 0
        var totalPartitionBytes: Int64 = 0
        var finalPartitionSHA256: String?

        func sendReady(force: Bool) async throws {
            while let partition = try assembler.makeNextPartition(force: force) {
                defer { partition.remove() }
                let retryDeadline = Date().addingTimeInterval(15 * 60)
                var accepted = false
                var lastMessage = "Partition transfer retries were exhausted."
                while !accepted {
                    try Task.checkCancellation()
                    guard Date() < retryDeadline else {
                        throw ProducerError.partitionFailed(lastMessage)
                    }
                    let open = ConnectedCorpusTransferOpen(
                        session: session,
                        partition: partition.descriptor,
                        exportManifest: exportManifest
                    )
                    guard let disposition = await syncService.sendConnectedCorpusOpenAndWait(open) else {
                        lastMessage = "Waiting for the Mac to reconnect and resume timed out."
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    guard disposition.sessionID == session.sessionID,
                          disposition.jobID == jobID,
                          disposition.partitionIndex == partition.descriptor.index,
                          disposition.partitionSHA256 == partition.descriptor.sha256 else {
                        throw ProducerError.peerRejected("Mac returned mismatched corpus-session metadata.")
                    }
                    if disposition.disposition == .reject {
                        throw ProducerError.peerRejected(disposition.message ?? "Mac rejected the corpus session.")
                    }
                    if disposition.disposition == .alreadyCommitted {
                        accepted = true
                        continue
                    }
                    guard disposition.nextPartitionIndex == partition.descriptor.index else {
                        throw ProducerError.peerRejected("Mac returned an inconsistent corpus resume position.")
                    }
                    let result = await syncService.sendConnectedTransfer(
                        partition.file,
                        manifest: ConnectedTransferManifest(
                            kind: .connectedCorpusPartitionV1,
                            jobID: jobID,
                            payloadSchemaVersion: ConnectedCorpusPartitionFileManifest.currentVersion,
                            corpusPartition: partition.descriptor
                        ),
                        transferID: partition.transferID,
                        protocolVersion: ConnectedTransferStart.corpusPartitionProtocolVersion,
                        onValidatedProgress: { _, _ in
                            guard let date = partition.descriptor.sourceDates.last else { return }
                            let processed = (metadata.transferDates.firstIndex(of: date) ?? 0) + 1
                            progress?(
                                processed,
                                metadata.totalTransferDays,
                                date,
                                "Transferring partitioned corpus data…"
                            )
                        }
                    )
                    switch result {
                    case .success:
                        accepted = true
                    case .failure(let abort):
                        lastMessage = abort.message
                        if abort.reason == .cancelled { throw CancellationError() }
                        if [.unsupported, .invalidManifest, .sizeLimit, .decodeFailure, .applicationRejected]
                            .contains(abort.reason) {
                            throw ProducerError.partitionFailed(abort.message)
                        }
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
                partitionCount = partition.descriptor.index + 1
                let newTotal = totalPartitionBytes.addingReportingOverflow(partition.descriptor.byteCount)
                guard !newTotal.overflow else {
                    throw ProducerError.partitionFailed("Corpus byte counters overflowed.")
                }
                totalPartitionBytes = newTotal.partialValue
                finalPartitionSHA256 = partition.descriptor.sha256
            }
        }

        do {
            for (index, date) in metadata.transferDates.enumerated() {
                try Task.checkCancellation()
                progress?(
                    index + 1,
                    metadata.totalTransferDays,
                    date,
                    "Preparing partitioned corpus data…"
                )
                let day = Calendar.current.startOfDay(for: date)
                let isRequested = metadata.requestedDays.contains(day)
                let includesGranularData = MacExportStreamingJobBuilder.shouldIncludeGranularData(
                    for: date,
                    metadata: metadata,
                    settings: settings
                )
                let payload: ConnectedCorpusHealthDayPayload
                do {
                    let fetched = try await healthKitManager.fetchHealthData(
                        for: date,
                        includeGranularData: includesGranularData,
                        metricSelection: settings.metricSelection
                    )
                    let record = ConnectedExportGranularMode.sanitized(
                        fetched,
                        includesGranularData: includesGranularData
                    )
                    var externalRecords: [ExternalDailyRecord] = []
                    if isRequested,
                       record.hasAnyData,
                       !settings.summaryOnlyModeEnabled,
                       let externalRecordFetcher {
                        externalRecords = await externalRecordFetcher(date).filter(\.shouldExport)
                    }
                    payload = ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: isRequested,
                        record: record,
                        externalDailyRecords: externalRecords,
                        failure: nil
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as HealthKitManager.HealthKitError {
                    payload = ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: isRequested,
                        record: nil,
                        externalDailyRecords: [],
                        failure: FailedDateDetail(
                            date: date,
                            reason: failureReason(for: error),
                            errorDetails: message(for: error)
                        )
                    )
                } catch {
                    payload = ConnectedCorpusHealthDayPayload(
                        sourceDate: date,
                        isRequestedDate: isRequested,
                        record: nil,
                        externalDailyRecords: [],
                        failure: FailedDateDetail(
                            date: date,
                            reason: .healthKitError,
                            errorDetails: "HealthKit query failed for the requested day."
                        )
                    )
                }
                assembler.append(try ConnectedCorpusSpoolItem.encode(
                    payload,
                    kind: .macHealthDay,
                    sourceDate: date,
                    isRequestedDate: isRequested
                ))
                try await sendReady(force: false)
            }
            try await sendReady(force: true)
            let finalize = ConnectedCorpusTransferFinalize(
                sessionID: session.sessionID,
                jobID: jobID,
                requestFingerprint: fingerprint,
                partitionCount: partitionCount,
                totalByteCount: totalPartitionBytes,
                finalPartitionSHA256: finalPartitionSHA256
            )
            let finalizationDeadline = Date().addingTimeInterval(45 * 60)
            var finalAcknowledgement: ConnectedCorpusTransferFinalAck?
            while finalAcknowledgement == nil && Date() < finalizationDeadline {
                try Task.checkCancellation()
                finalAcknowledgement = await syncService.sendConnectedCorpusFinalizeAndWait(
                    finalize,
                    timeoutSeconds: 60,
                    maximumAttempts: 1
                )
                if finalAcknowledgement == nil {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            guard let acknowledgement = finalAcknowledgement,
                  acknowledgement.accepted,
                  acknowledgement.requestFingerprint == fingerprint,
                  acknowledgement.finalPartitionSHA256 == finalPartitionSHA256 else {
                throw ProducerError.finalizationFailed
            }
            return Result(sessionID: session.sessionID, acknowledgement: acknowledgement)
        } catch {
            assembler.abandon()
            _ = await syncService.sendConnectedCorpusCancelAndWait(ConnectedCorpusTransferCancel(
                sessionID: session.sessionID,
                jobID: jobID,
                reason: error is CancellationError ? .userRequested : .protocolError,
                message: "iPhone stopped the corpus producer before finalization.",
                requestedAt: Date()
            ))
            throw error
        }
    }

    private static func failureReason(for error: HealthKitManager.HealthKitError) -> ExportFailureReason {
        switch error {
        case .dataProtectedWhileLocked: return .deviceLocked
        case .notAuthorized: return .accessDenied
        case .dataNotAvailable, .medicationAuthorizationUnsupported, .visionAuthorizationUnsupported:
            return .healthKitError
        }
    }

    private static func message(for error: HealthKitManager.HealthKitError) -> String {
        switch error {
        case .dataProtectedWhileLocked: return "Health data is protected while the iPhone is locked."
        case .notAuthorized: return "HealthKit access has not been granted on iPhone."
        case .dataNotAvailable: return "HealthKit data is not available on this device."
        case .medicationAuthorizationUnsupported: return "Medication authorization is not supported on this device."
        case .visionAuthorizationUnsupported: return "Vision prescription authorization is not supported on this device."
        }
    }
}
#endif
