import Foundation

/// Immutable local checkpoint capability. It never enters a wire or journal payload.
@MainActor
final class ConnectedCorpusOperationReceipt {
    static let pinned = TaskLocal<ConnectedCorpusOperationReceipt?>(wrappedValue: nil)
    private let checkpoint: AppleExportJournalCheckpoint
    private let journal: ConnectedCorpusOutboundJournal
    private let now: () -> Date

    init(checkpoint: AppleExportJournalCheckpoint, journal: ConnectedCorpusOutboundJournal,
         now: @escaping () -> Date) {
        self.checkpoint = checkpoint
        self.journal = journal
        self.now = now
    }
    nonisolated deinit {}

    func withOwnership<Result>(allowExpired: Bool = false, operation: () throws -> Result) throws -> Result {
        var admitted = false
        do {
            return try checkpoint.withCheckpointOwnership {
                admitted = true
                if !allowExpired, journal.expiresAt <= now() { throw ConnectedCorpusOutboundStoreError.expired }
                return try operation()
            }
        } catch {
            if !admitted { throw ConnectedCorpusOutboundStoreError.checkpointSuperseded }
            throw error
        }
    }

    func validate() throws { try withOwnership {} }

    func continueWhileOwned<Result>(onRejectedResult: (Result) -> Void = { _ in },
                                    operation: @MainActor () async throws -> Result) async throws -> Result {
        try validate()
        let result: Result
        do { result = try await Self.pinned.withValue(self) { try await operation() } }
        catch {
            let operationError = error
            try validate()
            throw operationError
        }
        do { try validate() }
        catch { onRejectedResult(result); throw error }
        return result
    }

    static func withCurrentOwnership<Result>(operation: () throws -> Result) throws -> Result {
        if let receipt = pinned.wrappedValue { return try receipt.withOwnership(operation: operation) }
        return try operation()
    }

    static func withCurrentMessageOwnership<Result>(_ message: SyncMessage,
                                                     operation: () throws -> Result) throws -> Result {
        guard let receipt = bound(to: message) else { return try operation() }
        guard receipt.permits(message) else { throw ConnectedCorpusOutboundStoreError.checkpointSuperseded }
        return try receipt.withOwnership(operation: operation)
    }

    static func bound(to message: SyncMessage) -> ConnectedCorpusOperationReceipt? {
        switch message {
        case .connectedCorpusTransferOpen, .connectedCorpusTransferFinalize, .connectedCorpusTransferCancel, .connectedCorpusStatus,
             .connectedTransferStart, .connectedTransferChunk, .connectedTransferComplete, .connectedTransferAbort:
            return pinned.wrappedValue
        default: return nil
        }
    }

    func validatePeer(source: UUID, destination: UUID?) throws {
        guard journal.session.peerBinding?.sourceInstallationID == source,
              journal.session.peerBinding?.destinationInstallationID == destination else {
            throw ConnectedCorpusOutboundStoreError.checkpointSuperseded
        }
    }

    func validateTransfer(_ file: ConnectedTransferPreparedFile, manifest: ConnectedTransferManifest,
                          transferID: UUID) throws {
        guard let pending = journal.pendingPartition, let saved = checkpoint.journalURL,
              transferID == pending.transferID, manifest.jobID == journal.jobID,
              manifest.corpusPartition == pending.descriptor,
              file.totalBytes == pending.descriptor.byteCount, file.sha256 == pending.descriptor.sha256 else {
            throw ConnectedCorpusOutboundStoreError.checkpointSuperseded
        }
        let root = saved.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let expected = root.appendingPathComponent(pending.relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard expected.pathComponents.starts(with: root.pathComponents), expected != root,
              file.url.standardizedFileURL.resolvingSymlinksInPath() == expected,
              try FileManager.default.attributesOfItem(atPath: file.url.path)[.type] as? FileAttributeType == .typeRegular else {
            throw ConnectedCorpusOutboundStoreError.checkpointSuperseded
        }
    }

    private func permits(_ message: SyncMessage) -> Bool {
        switch message {
        case .connectedCorpusTransferOpen(let open):
            return !journal.state.isTerminal && open.session == journal.session && open.exportManifest == journal.exportManifest
                && open.partition == journal.pendingPartition?.descriptor
        case .connectedCorpusTransferFinalize(let request):
            return (journal.state == .finalizing || journal.state == .completed)
                && journal.pendingPartition == nil && request.jobID == journal.jobID
                && request.sessionID == journal.sessionID && request.requestFingerprint == journal.session.requestFingerprint
                && request.partitionCount == journal.committedPartitionCount
                && request.totalByteCount == journal.committedByteCount
                && request.finalPartitionSHA256 == journal.lastCommittedPartitionSHA256
        case .connectedCorpusStatus(let status):
            return status.jobID == journal.jobID && status.sessionID == journal.sessionID
                && status.requestFingerprint == journal.session.requestFingerprint
        case .connectedCorpusTransferCancel(let request):
            return request.jobID == journal.jobID && request.sessionID == journal.sessionID
        case .connectedTransferStart(let start):
            return !journal.state.isTerminal && start.protocolVersion == ConnectedTransferStart.corpusPartitionProtocolVersion
                && start.manifest.kind == .connectedCorpusPartitionV1
                && start.totalBytes == journal.pendingPartition?.descriptor.byteCount
                && start.sha256 == journal.pendingPartition?.descriptor.sha256
                && start.manifest.jobID == journal.jobID && start.transferID == journal.pendingPartition?.transferID
                && start.manifest.corpusPartition == journal.pendingPartition?.descriptor
        case .connectedTransferChunk(let chunk):
            return !journal.state.isTerminal && chunk.transferID == journal.pendingPartition?.transferID
        case .connectedTransferComplete(let complete):
            return !journal.state.isTerminal && complete.transferID == journal.pendingPartition?.transferID
                && complete.sha256 == journal.pendingPartition?.descriptor.sha256
        case .connectedTransferAbort(let abort):
            return abort.jobID == journal.jobID && abort.transferID == journal.pendingPartition?.transferID
        default:
            return true
        }
    }
}
