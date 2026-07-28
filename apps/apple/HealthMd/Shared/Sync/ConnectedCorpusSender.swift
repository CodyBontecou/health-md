import Foundation

/// Shared, resumable sender for connected-corpus exports.
///
/// Callers own manifest construction and daily item production. This type owns
/// the transport state machine: partition assembly, open/resume validation,
/// bounded retries, durable partition accounting, finalization, and cancellation.
@MainActor
enum ConnectedCorpusSender {
    struct Configuration {
        let jobID: UUID
        let manifest: ConnectedCorpusExportManifest
        let negotiation: ConnectedCorpusTransferNegotiation
        let partitionRetryTimeout: TimeInterval
        let finalizationRetryTimeout: TimeInterval
        let finalizationAttemptTimeout: TimeInterval
        let retryDelayNanoseconds: UInt64

        init(
            jobID: UUID,
            manifest: ConnectedCorpusExportManifest,
            negotiation: ConnectedCorpusTransferNegotiation,
            partitionRetryTimeout: TimeInterval = 15 * 60,
            finalizationRetryTimeout: TimeInterval = 45 * 60,
            finalizationAttemptTimeout: TimeInterval = 60,
            retryDelayNanoseconds: UInt64 = 1_000_000_000
        ) {
            self.jobID = jobID
            self.manifest = manifest
            self.negotiation = negotiation
            self.partitionRetryTimeout = partitionRetryTimeout
            self.finalizationRetryTimeout = finalizationRetryTimeout
            self.finalizationAttemptTimeout = finalizationAttemptTimeout
            self.retryDelayNanoseconds = retryDelayNanoseconds
        }
    }

    struct Result {
        let sessionID: UUID
        let acknowledgement: ConnectedCorpusTransferFinalAck
    }

    enum State {
        case sessionStarted(UUID)
        case partitionStarted(transferID: UUID, descriptor: ConnectedCorpusPartitionDescriptor)
        case partitionFinished(transferID: UUID, descriptor: ConnectedCorpusPartitionDescriptor)
        case finished(UUID)
    }

    enum SenderError: Error, LocalizedError {
        case rejected(String)
        case transferFailed(String)
        case finalizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .rejected(let message), .transferFailed(let message), .finalizationFailed(let message):
                return message
            }
        }
    }

    typealias ValidatedProgressHandler = (_ acceptedChunks: Int, _ totalChunks: Int) -> Void

    struct Transport {
        let open: (_ request: ConnectedCorpusTransferOpen) async -> ConnectedCorpusTransferDisposition?
        let sendPartition: (
            _ file: ConnectedTransferPreparedFile,
            _ manifest: ConnectedTransferManifest,
            _ transferID: UUID,
            _ onValidatedProgress: @escaping ValidatedProgressHandler
        ) async -> ConnectedTransferSendResult
        let finalize: (
            _ request: ConnectedCorpusTransferFinalize,
            _ timeoutSeconds: TimeInterval
        ) async -> ConnectedCorpusTransferFinalAck?
        let cancel: (_ request: ConnectedCorpusTransferCancel) async -> ConnectedCorpusTransferCancelAck?

        init(
            open: @escaping (_ request: ConnectedCorpusTransferOpen) async -> ConnectedCorpusTransferDisposition?,
            sendPartition: @escaping (
                _ file: ConnectedTransferPreparedFile,
                _ manifest: ConnectedTransferManifest,
                _ transferID: UUID,
                _ onValidatedProgress: @escaping ValidatedProgressHandler
            ) async -> ConnectedTransferSendResult,
            finalize: @escaping (
                _ request: ConnectedCorpusTransferFinalize,
                _ timeoutSeconds: TimeInterval
            ) async -> ConnectedCorpusTransferFinalAck?,
            cancel: @escaping (_ request: ConnectedCorpusTransferCancel) async -> ConnectedCorpusTransferCancelAck?
        ) {
            self.open = open
            self.sendPartition = sendPartition
            self.finalize = finalize
            self.cancel = cancel
        }

        static func syncService(_ syncService: SyncService) -> Self {
            Self(
                open: { request in
                    await syncService.sendConnectedCorpusOpenAndWait(request)
                },
                sendPartition: { file, manifest, transferID, onValidatedProgress in
                    await syncService.sendConnectedTransfer(
                        file,
                        manifest: manifest,
                        transferID: transferID,
                        protocolVersion: ConnectedTransferStart.corpusPartitionProtocolVersion,
                        onValidatedProgress: onValidatedProgress
                    )
                },
                finalize: { request, timeoutSeconds in
                    await syncService.sendConnectedCorpusFinalizeAndWait(
                        request,
                        timeoutSeconds: timeoutSeconds,
                        maximumAttempts: 1
                    )
                },
                cancel: { request in
                    await syncService.sendConnectedCorpusCancelAndWait(request)
                }
            )
        }
    }

    typealias ItemAppender = (_ item: ConnectedCorpusSpoolItem) async throws -> Void
    typealias ItemProducer = (_ append: @escaping ItemAppender) async throws -> Void

    static func send(
        configuration: Configuration,
        transport: Transport,
        checkCancellation: @escaping () throws -> Void = { try Task.checkCancellation() },
        onStateChange: ((State) -> Void)? = nil,
        onValidatedPartitionProgress: ((
            _ descriptor: ConnectedCorpusPartitionDescriptor,
            _ acceptedChunks: Int,
            _ totalChunks: Int
        ) -> Void)? = nil,
        produceItems: ItemProducer
    ) async throws -> Result {
        try configuration.manifest.validate()
        guard configuration.manifest.createdAt.isFiniteDate,
              configuration.partitionRetryTimeout > 0,
              configuration.finalizationRetryTimeout > 0,
              configuration.finalizationAttemptTimeout > 0 else {
            throw ConnectedCorpusTransferModelError.invalidFinalization
        }

        let fingerprint = try ConnectedCorpusRequestFingerprint.make(for: configuration.manifest)
        let session = ConnectedCorpusTransferSession(
            sessionID: UUID(),
            jobID: configuration.jobID,
            requestFingerprint: fingerprint,
            protocolVersion: configuration.negotiation.protocolVersion,
            partitionTargetBytes: configuration.negotiation.partitionTargetBytes,
            createdAt: configuration.manifest.createdAt
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: session.sessionID,
            jobID: configuration.jobID,
            targetBytes: configuration.negotiation.partitionTargetBytes
        )
        var partitionCount = 0
        var totalPartitionBytes: Int64 = 0
        var finalPartitionSHA256: String?

        onStateChange?(.sessionStarted(session.sessionID))

        func checkStillActive() throws {
            try Task.checkCancellation()
            try checkCancellation()
        }

        func retryPause() async throws {
            try checkStillActive()
            if configuration.retryDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: configuration.retryDelayNanoseconds)
            }
        }

        func sendReadyPartitions(force: Bool) async throws {
            while let partition = try assembler.makeNextPartition(force: force) {
                defer { partition.remove() }
                onStateChange?(.partitionStarted(
                    transferID: partition.transferID,
                    descriptor: partition.descriptor
                ))

                let retryDeadline = Date().addingTimeInterval(configuration.partitionRetryTimeout)
                var accepted = false
                var lastMessage = "Corpus partition transfer retries were exhausted."
                while !accepted {
                    try checkStillActive()
                    guard Date() < retryDeadline else {
                        throw SenderError.transferFailed(lastMessage)
                    }

                    let open = ConnectedCorpusTransferOpen(
                        session: session,
                        partition: partition.descriptor,
                        exportManifest: configuration.manifest
                    )
                    guard let disposition = await transport.open(open) else {
                        lastMessage = "Waiting for the Mac to reconnect and resume timed out."
                        try await retryPause()
                        continue
                    }
                    guard disposition.sessionID == session.sessionID,
                          disposition.jobID == configuration.jobID,
                          disposition.partitionIndex == partition.descriptor.index,
                          disposition.partitionSHA256 == partition.descriptor.sha256 else {
                        throw SenderError.rejected("Mac returned mismatched corpus-session metadata.")
                    }

                    switch disposition.disposition {
                    case .reject:
                        throw SenderError.rejected(
                            disposition.message ?? "Mac rejected the corpus partition."
                        )
                    case .alreadyCommitted:
                        guard disposition.nextPartitionIndex > partition.descriptor.index else {
                            throw SenderError.rejected(
                                "Mac returned an inconsistent durable resume position."
                            )
                        }
                        accepted = true
                    case .accept, .resume:
                        guard disposition.nextPartitionIndex == partition.descriptor.index else {
                            throw SenderError.rejected(
                                "Mac requested a different partition sequence."
                            )
                        }
                        let transferResult = await transport.sendPartition(
                            partition.file,
                            ConnectedTransferManifest(
                                kind: .connectedCorpusPartitionV1,
                                jobID: configuration.jobID,
                                payloadSchemaVersion: ConnectedCorpusPartitionFileManifest.currentVersion,
                                corpusPartition: partition.descriptor
                            ),
                            partition.transferID,
                            { acceptedChunks, totalChunks in
                                onValidatedPartitionProgress?(
                                    partition.descriptor,
                                    acceptedChunks,
                                    totalChunks
                                )
                            }
                        )
                        switch transferResult {
                        case .success:
                            accepted = true
                        case .failure(let abort):
                            lastMessage = abort.message
                            if abort.reason == .cancelled {
                                throw CancellationError()
                            }
                            if Self.isFatal(abort.reason) {
                                throw SenderError.transferFailed(abort.message)
                            }
                            try await retryPause()
                        }
                    }
                }

                partitionCount = partition.descriptor.index + 1
                let newTotal = totalPartitionBytes.addingReportingOverflow(
                    partition.descriptor.byteCount
                )
                guard !newTotal.overflow else {
                    throw SenderError.transferFailed("Corpus byte counters overflowed.")
                }
                totalPartitionBytes = newTotal.partialValue
                finalPartitionSHA256 = partition.descriptor.sha256
                onStateChange?(.partitionFinished(
                    transferID: partition.transferID,
                    descriptor: partition.descriptor
                ))
            }
        }

        do {
            try await produceItems { item in
                // The caller has already encoded a restricted spool file. If
                // cancellation wins before the assembler takes ownership, the
                // append boundary must remove that file explicitly.
                do {
                    try checkStillActive()
                } catch {
                    item.remove()
                    throw error
                }
                assembler.append(item)
                try await sendReadyPartitions(force: false)
            }
            try checkStillActive()
            try await sendReadyPartitions(force: true)

            let finalize = ConnectedCorpusTransferFinalize(
                sessionID: session.sessionID,
                jobID: configuration.jobID,
                requestFingerprint: fingerprint,
                partitionCount: partitionCount,
                totalByteCount: totalPartitionBytes,
                finalPartitionSHA256: finalPartitionSHA256
            )
            let finalizationDeadline = Date().addingTimeInterval(
                configuration.finalizationRetryTimeout
            )
            var finalAcknowledgement: ConnectedCorpusTransferFinalAck?
            while finalAcknowledgement == nil && Date() < finalizationDeadline {
                try checkStillActive()
                finalAcknowledgement = await transport.finalize(
                    finalize,
                    configuration.finalizationAttemptTimeout
                )
                if finalAcknowledgement == nil {
                    try await retryPause()
                }
            }
            guard let acknowledgement = finalAcknowledgement,
                  acknowledgement.accepted,
                  acknowledgement.sessionID == session.sessionID,
                  acknowledgement.jobID == configuration.jobID,
                  acknowledgement.requestFingerprint == fingerprint,
                  acknowledgement.finalPartitionSHA256 == finalPartitionSHA256 else {
                throw SenderError.finalizationFailed(
                    "Mac did not durably finalize the corpus export."
                )
            }

            onStateChange?(.finished(session.sessionID))
            return Result(
                sessionID: session.sessionID,
                acknowledgement: acknowledgement
            )
        } catch {
            assembler.abandon()
            _ = await transport.cancel(ConnectedCorpusTransferCancel(
                sessionID: session.sessionID,
                jobID: configuration.jobID,
                reason: error is CancellationError ? .userRequested : .protocolError,
                message: "iPhone stopped the corpus producer before finalization.",
                requestedAt: Date()
            ))
            throw error
        }
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
}

private extension Date {
    var isFiniteDate: Bool { timeIntervalSinceReferenceDate.isFinite }
}
