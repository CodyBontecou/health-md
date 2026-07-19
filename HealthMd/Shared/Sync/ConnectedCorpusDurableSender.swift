import Foundation

/// Crash-safe corpus sender. Unlike the protocol-v1 in-memory sender, every
/// byte-producing decision is journaled before it crosses the wire and every
/// local frontier advances only after receiver durability is proven.
@MainActor
enum ConnectedCorpusDurableSender {
    struct Configuration {
        let jobID: UUID
        let retryDelayNanoseconds: UInt64
        let maximumImmediateAttempts: Int
        let finalizationAttemptTimeout: TimeInterval

        init(
            jobID: UUID,
            retryDelayNanoseconds: UInt64 = 500_000_000,
            maximumImmediateAttempts: Int = 2,
            finalizationAttemptTimeout: TimeInterval = 30
        ) {
            self.jobID = jobID
            self.retryDelayNanoseconds = retryDelayNanoseconds
            self.maximumImmediateAttempts = max(maximumImmediateAttempts, 1)
            self.finalizationAttemptTimeout = finalizationAttemptTimeout
        }
    }

    struct Result {
        let sessionID: UUID
        let acknowledgement: ConnectedCorpusTransferFinalAck
    }

    enum DurableSenderError: Error, LocalizedError, Equatable {
        case paused(String)
        case rejected(String)
        case corruptCheckpoint(String)

        var errorDescription: String? {
            switch self {
            case .paused(let message), .rejected(let message), .corruptCheckpoint(let message):
                return message
            }
        }
    }

    typealias ItemProducer = (
        _ itemIndex: Int,
        _ sourceDate: Date
    ) async throws -> ConnectedCorpusSpoolItem

    static func send(
        configuration: Configuration,
        store: ConnectedCorpusOutboundStore,
        transport: ConnectedCorpusSender.Transport,
        isExplicitlyCancelled: @escaping () -> Bool = { false },
        onCheckpoint: ((ConnectedCorpusOutboundJournal) -> Void)? = nil,
        afterReceiverAcceptedPartition: (() throws -> Void)? = nil,
        onValidatedPartitionProgress: ((
            _ descriptor: ConnectedCorpusPartitionDescriptor,
            _ acceptedChunks: Int,
            _ totalChunks: Int
        ) -> Void)? = nil,
        produceItem: ItemProducer
    ) async throws -> Result {
        guard configuration.maximumImmediateAttempts > 0,
              configuration.finalizationAttemptTimeout > 0,
              var journal = try store.load(jobID: configuration.jobID) else {
            throw ConnectedCorpusOutboundStoreError.jobNotFound
        }
        if journal.state == .completed, let acknowledgement = journal.terminalAcknowledgement {
            return Result(sessionID: journal.sessionID, acknowledgement: acknowledgement)
        }
        guard !journal.state.isTerminal else {
            throw DurableSenderError.rejected(
                journal.statusMessage ?? "Durable connected export is already terminal."
            )
        }

        func checkStillActive() throws {
            if isExplicitlyCancelled() { throw CancellationError() }
            try Task.checkCancellation()
        }

        func publish(_ next: ConnectedCorpusOutboundJournal) {
            onCheckpoint?(next)
        }

        func pause(_ message: String) throws -> Never {
            let paused = try store.updateState(
                jobID: configuration.jobID,
                state: .paused,
                message: message
            )
            publish(paused)
            throw DurableSenderError.paused(message)
        }

        func reject(_ message: String) throws -> Never {
            let failed = try store.updateState(
                jobID: configuration.jobID,
                state: .failed,
                message: message
            )
            publish(failed)
            throw DurableSenderError.rejected(message)
        }

        do {
            while true {
                try checkStillActive()
                guard let refreshed = try store.load(jobID: configuration.jobID) else {
                    throw ConnectedCorpusOutboundStoreError.jobNotFound
                }
                journal = refreshed

                if journal.state == .completed,
                   let acknowledgement = journal.terminalAcknowledgement {
                    return Result(sessionID: journal.sessionID, acknowledgement: acknowledgement)
                }
                guard !journal.state.isTerminal else {
                    throw DurableSenderError.rejected(
                        journal.statusMessage ?? "Durable connected export is terminal."
                    )
                }

                if let partition = try store.preparedPendingPartition(for: journal) {
                    let accepted = try await sendPendingPartition(
                        partition,
                        journal: journal,
                        configuration: configuration,
                        transport: transport,
                        checkStillActive: checkStillActive,
                        onValidatedPartitionProgress: onValidatedPartitionProgress
                    )
                    switch accepted {
                    case .accepted:
                        try afterReceiverAcceptedPartition?()
                        journal = try store.commitPendingPartition(jobID: configuration.jobID)
                        publish(journal)
                        continue
                    case .paused(let message):
                        try pause(message)
                    case .rejected(let message):
                        try reject(message)
                    case .cancelled:
                        try? store.cancel(jobID: configuration.jobID)
                        throw CancellationError()
                    }
                }

                let sources = try store.spoolItems(for: journal)
                let allItemsProduced = journal.nextItemIndex == journal.totalItemCount
                if !sources.isEmpty,
                   (allItemsProduced || ConnectedCorpusDurablePartitionBuilder.shouldFlush(
                       sources: sources,
                       targetBytes: journal.session.partitionTargetBytes
                   )) {
                    let partition = try ConnectedCorpusDurablePartitionBuilder.prepare(
                        sessionID: journal.sessionID,
                        jobID: journal.jobID,
                        targetBytes: journal.session.partitionTargetBytes,
                        partitionIndex: journal.committedPartitionCount,
                        previousPartitionSHA256: journal.lastCommittedPartitionSHA256,
                        sources: sources
                    )
                    do {
                        journal = try store.adoptPendingPartition(partition, jobID: journal.jobID)
                        publish(journal)
                    } catch {
                        partition.remove()
                        throw error
                    }
                    continue
                }

                if !allItemsProduced {
                    let itemIndex = journal.nextItemIndex
                    let sourceDate = journal.exportManifest.transferDates[itemIndex]
                    journal = try store.updateState(
                        jobID: journal.jobID,
                        state: .preparing,
                        message: "Preparing day \(itemIndex + 1) of \(journal.totalItemCount)…",
                        currentDate: sourceDate
                    )
                    publish(journal)
                    try checkStillActive()
                    let item = try await produceItem(itemIndex, sourceDate)
                    do {
                        try checkStillActive()
                    } catch {
                        item.remove()
                        throw error
                    }
                    do {
                        journal = try store.adoptItem(
                            item,
                            expectedIndex: itemIndex,
                            jobID: journal.jobID
                        )
                        publish(journal)
                    } catch {
                        item.remove()
                        throw error
                    }
                    continue
                }

                guard sources.isEmpty else {
                    throw DurableSenderError.corruptCheckpoint(
                        "Durable sender reached finalization with uncommitted item bytes."
                    )
                }
                journal = try store.updateState(
                    jobID: journal.jobID,
                    state: .finalizing,
                    message: "Finalizing durable connected export…"
                )
                publish(journal)
                let finalize = ConnectedCorpusTransferFinalize(
                    sessionID: journal.sessionID,
                    jobID: journal.jobID,
                    requestFingerprint: journal.session.requestFingerprint,
                    partitionCount: journal.committedPartitionCount,
                    totalByteCount: journal.committedByteCount,
                    finalPartitionSHA256: journal.lastCommittedPartitionSHA256
                )
                guard let acknowledgement = await transport.finalize(
                    finalize,
                    configuration.finalizationAttemptTimeout
                ) else {
                    try pause("Waiting for the Mac to reconnect and finalize the export.")
                }
                guard acknowledgement.accepted,
                      acknowledgement.sessionID == journal.sessionID,
                      acknowledgement.jobID == journal.jobID,
                      acknowledgement.requestFingerprint == journal.session.requestFingerprint,
                      acknowledgement.finalPartitionSHA256 == journal.lastCommittedPartitionSHA256 else {
                    try reject("Mac returned an invalid durable final acknowledgement.")
                }
                journal = try store.complete(
                    jobID: journal.jobID,
                    acknowledgement: acknowledgement
                )
                publish(journal)
                return Result(sessionID: journal.sessionID, acknowledgement: acknowledgement)
            }
        } catch is CancellationError {
            if isExplicitlyCancelled() {
                try? store.cancel(jobID: configuration.jobID)
                throw CancellationError()
            }
            try pause("Export paused while the iPhone app was interrupted. Reopen it to resume.")
        } catch let error as DurableSenderError {
            throw error
        } catch let error as ConnectedCorpusOutboundStoreError {
            switch error {
            case .expired:
                try? store.cancel(jobID: configuration.jobID, expired: true)
                throw DurableSenderError.rejected("The durable export checkpoint expired.")
            case .missingFile, .corruptFile, .invalidCommit, .invalidJournal:
                _ = try? store.updateState(
                    jobID: configuration.jobID,
                    state: .failed,
                    message: "Durable export checkpoint is incomplete or corrupt."
                )
                throw DurableSenderError.corruptCheckpoint(
                    "Durable export checkpoint is incomplete or corrupt."
                )
            case .requestChanged, .peerChanged:
                try reject("Durable export identity changed; refusing unsafe resume.")
            case .jobNotFound:
                throw error
            }
        } catch {
            try pause("Export paused after an interruption: \(Self.safeMessage(for: error))")
        }
    }

    private enum PartitionOutcome {
        case accepted
        case paused(String)
        case rejected(String)
        case cancelled
    }

    private static func sendPendingPartition(
        _ partition: ConnectedCorpusPreparedPartition,
        journal: ConnectedCorpusOutboundJournal,
        configuration: Configuration,
        transport: ConnectedCorpusSender.Transport,
        checkStillActive: () throws -> Void,
        onValidatedPartitionProgress: ((
            _ descriptor: ConnectedCorpusPartitionDescriptor,
            _ acceptedChunks: Int,
            _ totalChunks: Int
        ) -> Void)?
    ) async throws -> PartitionOutcome {
        var lastPauseMessage = "Waiting for the Mac to reconnect and resume."
        for attempt in 0..<configuration.maximumImmediateAttempts {
            try checkStillActive()
            let open = ConnectedCorpusTransferOpen(
                session: journal.session,
                partition: partition.descriptor,
                exportManifest: journal.exportManifest
            )
            guard let disposition = await transport.open(open) else {
                lastPauseMessage = "Waiting for the Mac to reconnect and resume partition \(partition.descriptor.index + 1)."
                if attempt + 1 < configuration.maximumImmediateAttempts {
                    try await retryPause(configuration.retryDelayNanoseconds, checkStillActive)
                }
                continue
            }
            guard disposition.sessionID == journal.sessionID,
                  disposition.jobID == journal.jobID,
                  disposition.partitionIndex == partition.descriptor.index,
                  disposition.partitionSHA256 == partition.descriptor.sha256 else {
                return .rejected("Mac returned mismatched durable session metadata.")
            }
            switch disposition.disposition {
            case .reject:
                return .paused(disposition.message ?? "Mac is not ready to resume this export.")
            case .alreadyCommitted:
                guard disposition.nextPartitionIndex > partition.descriptor.index else {
                    return .rejected("Mac returned an invalid durable partition frontier.")
                }
                return .accepted
            case .accept, .resume:
                guard disposition.nextPartitionIndex == partition.descriptor.index else {
                    return .rejected("Mac requested a different durable partition sequence.")
                }
                let transferResult = await transport.sendPartition(
                    partition.file,
                    ConnectedTransferManifest(
                        kind: .connectedCorpusPartitionV1,
                        jobID: journal.jobID,
                        payloadSchemaVersion: ConnectedCorpusPartitionFileManifest.currentVersion,
                        corpusPartition: partition.descriptor
                    ),
                    partition.transferID,
                    { accepted, total in
                        onValidatedPartitionProgress?(partition.descriptor, accepted, total)
                    }
                )
                switch transferResult {
                case .success(let acknowledgement):
                    guard acknowledgement.accepted,
                          acknowledgement.transferID == partition.transferID,
                          acknowledgement.sha256 == partition.file.sha256 else {
                        return .rejected("Mac returned an invalid partition transfer acknowledgement.")
                    }
                    return .accepted
                case .failure(let abort):
                    if abort.reason == .cancelled { return .cancelled }
                    if isFatal(abort.reason) { return .rejected(abort.message) }
                    lastPauseMessage = abort.message
                    if attempt + 1 < configuration.maximumImmediateAttempts {
                        try await retryPause(configuration.retryDelayNanoseconds, checkStillActive)
                    }
                }
            }
        }
        return .paused(lastPauseMessage)
    }

    private static func retryPause(
        _ nanoseconds: UInt64,
        _ checkStillActive: () throws -> Void
    ) async throws {
        try checkStillActive()
        if nanoseconds > 0 { try await Task.sleep(nanoseconds: nanoseconds) }
        try checkStillActive()
    }

    private static func isFatal(_ reason: ConnectedTransferAbortReason) -> Bool {
        switch reason {
        case .unsupported, .invalidManifest, .sizeLimit, .decodeFailure, .applicationRejected:
            return true
        case .sequenceMismatch, .chunkHashMismatch, .finalHashMismatch,
             .retriesExhausted, .cancelled, .disconnected, .timedOut:
            return false
        }
    }

    private static func safeMessage(for error: Error) -> String {
        switch error {
        case let error as CocoaError where error.code == .fileWriteOutOfSpace:
            return "Not enough protected iPhone storage is available."
        default:
            return "the current day could not be checkpointed."
        }
    }
}
