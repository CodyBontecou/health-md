import Foundation

/// Origin of a durable iPhone corpus export. The value is persisted so an app
/// relaunch can restore the right product behavior without retaining closures.
enum ConnectedCorpusOutboundOrigin: String, Codable, Equatable, Sendable {
    case macInitiated = "mac_initiated"
    case interactiveIPhone = "interactive_iphone"
    case scheduledIPhone = "scheduled_iphone"
}

enum ConnectedCorpusOutboundState: String, Codable, Equatable, Sendable {
    case preparing
    case transferring
    case paused
    case finalizing
    case completed
    case failed
    case cancelled
    case expired

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .expired: return true
        case .preparing, .transferring, .paused, .finalizing: return false
        }
    }
}

/// Durable sender-side checkpoint. It intentionally retains only bounded source
/// items and one unacknowledged partition. Acknowledged corpus bytes live on the
/// Mac and are represented here by their digest-chain frontier.
struct ConnectedCorpusOutboundJournal: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Item: Codable, Equatable, Sendable {
        let itemID: UUID
        let kind: ConnectedCorpusItemKind
        let sourceDate: Date
        let isRequestedDate: Bool
        let relativePath: String
        let totalBytes: Int64
        let sha256: String
        var nextOffset: Int64
    }

    struct PendingPartition: Codable, Equatable, Sendable {
        let transferID: UUID
        let relativePath: String
        let descriptor: ConnectedCorpusPartitionDescriptor
        let manifest: ConnectedCorpusPartitionFileManifest
    }

    var version = currentVersion
    let origin: ConnectedCorpusOutboundOrigin
    let session: ConnectedCorpusTransferSession
    let exportManifest: ConnectedCorpusExportManifest
    let macRequest: IPhoneExportRequest?
    let createdAt: Date
    let expiresAt: Date
    var state: ConnectedCorpusOutboundState
    var nextItemIndex: Int
    var completedItemCount: Int
    var items: [Item]
    var pendingPartition: PendingPartition?
    var committedPartitionCount: Int
    var committedByteCount: Int64
    var lastCommittedPartitionSHA256: String?
    var currentDate: Date?
    var statusMessage: String?
    var terminalAcknowledgement: ConnectedCorpusTransferFinalAck?
    var completionRecorded: Bool
    var updatedAt: Date

    var jobID: UUID { session.jobID }
    var sessionID: UUID { session.sessionID }
    var totalItemCount: Int { exportManifest.transferDates.count }
    var fractionComplete: Double {
        guard totalItemCount > 0 else { return state == .completed ? 1 : 0 }
        return min(max(Double(completedItemCount) / Double(totalItemCount), 0), 1)
    }

    /// Progress remains recoverable after the Mac result has been consumed, but
    /// it must no longer reactivate the iPhone's export UI while the final ACK is
    /// still being journaled.
    var unrecordedProgressSnapshot: ConnectedCorpusProgressSnapshot? {
        completionRecorded ? nil : progressSnapshot
    }

    var progressSnapshot: ConnectedCorpusProgressSnapshot {
        let wireState: ConnectedCorpusJobState
        switch state {
        case .preparing: wireState = .preparing
        case .transferring: wireState = .transferring
        case .paused: wireState = .paused
        case .finalizing: wireState = .finalizing
        case .completed:
            if let acknowledgement = terminalAcknowledgement,
               let successCount = acknowledgement.successCount,
               let totalCount = acknowledgement.totalCount,
               successCount < totalCount {
                wireState = .partialSuccess
            } else {
                wireState = .completed
            }
        case .failed: wireState = .failed
        case .cancelled: wireState = .cancelled
        case .expired: wireState = .expired
        }
        return ConnectedCorpusProgressSnapshot(
            jobID: jobID,
            sessionID: sessionID,
            requestFingerprint: session.requestFingerprint,
            state: wireState,
            processedDays: completedItemCount,
            totalDays: totalItemCount,
            committedPartitionCount: committedPartitionCount,
            committedBytes: committedByteCount,
            currentDate: currentDate,
            message: statusMessage,
            updatedAt: updatedAt,
            expiresAt: expiresAt
        )
    }

    func isBound(sourceInstallationID: UUID, destinationInstallationID: UUID) -> Bool {
        session.peerBinding == ConnectedCorpusPeerBinding(
            sourceInstallationID: sourceInstallationID,
            destinationInstallationID: destinationInstallationID
        )
    }
}

enum ConnectedCorpusOutboundStoreError: Error, Equatable {
    case invalidJournal
    case requestChanged
    case peerChanged
    case expired
    case missingFile
    case corruptFile
    case invalidCommit
    case jobNotFound
}

/// Protected, atomically journaled storage for resumable iPhone corpus senders.
/// The type is shared so recovery invariants can be tested on macOS, while the
/// production root is the iPhone Application Support container.
@MainActor
final class ConnectedCorpusOutboundStore {
    nonisolated static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60

    private let rootURL: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.now = now
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            self.rootURL = support
                .appendingPathComponent("Health.md", isDirectory: true)
                .appendingPathComponent("ConnectedCorpusOutbound", isDirectory: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    var storageRootURL: URL { rootURL }

    @discardableResult
    func createOrRestore(
        origin: ConnectedCorpusOutboundOrigin,
        session: ConnectedCorpusTransferSession,
        manifest: ConnectedCorpusExportManifest,
        macRequest: IPhoneExportRequest? = nil,
        expiresAt: Date? = nil
    ) throws -> ConnectedCorpusOutboundJournal {
        try manifest.validate()
        guard macRequest.map({ $0.jobID == session.jobID }) ?? true,
              session.protocolVersion >= 2,
              session.peerBinding != nil,
              session.requestFingerprint == (try ConnectedCorpusRequestFingerprint.make(for: manifest)) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        if let existing = try load(jobID: session.jobID, allowExpired: true) {
            guard existing.session == session,
                  existing.exportManifest == manifest,
                  existing.macRequest == macRequest,
                  existing.origin == origin else {
                throw ConnectedCorpusOutboundStoreError.requestChanged
            }
            guard existing.expiresAt > now() else {
                throw ConnectedCorpusOutboundStoreError.expired
            }
            return existing
        }

        try prepareDirectories(jobID: session.jobID)
        let timestamp = now()
        var journal = ConnectedCorpusOutboundJournal(
            origin: origin,
            session: session,
            exportManifest: manifest,
            macRequest: macRequest,
            createdAt: timestamp,
            expiresAt: expiresAt ?? timestamp.addingTimeInterval(Self.retentionInterval),
            state: .preparing,
            nextItemIndex: 0,
            completedItemCount: 0,
            items: [],
            pendingPartition: nil,
            committedPartitionCount: 0,
            committedByteCount: 0,
            lastCommittedPartitionSHA256: nil,
            currentDate: manifest.transferDates.first,
            statusMessage: "Preparing durable connected export…",
            terminalAcknowledgement: nil,
            completionRecorded: false,
            updatedAt: timestamp
        )
        try validate(journal)
        try persist(&journal)
        return journal
    }

    func load(jobID: UUID, allowExpired: Bool = false) throws -> ConnectedCorpusOutboundJournal? {
        let url = journalURL(jobID: jobID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let journal: ConnectedCorpusOutboundJournal
        do {
            journal = try decoder.decode(ConnectedCorpusOutboundJournal.self, from: data)
            try validate(journal)
            try validateFiles(journal)
        } catch let error as ConnectedCorpusOutboundStoreError {
            throw error
        } catch {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        if !allowExpired, journal.expiresAt <= now(), !journal.state.isTerminal {
            throw ConnectedCorpusOutboundStoreError.expired
        }
        cleanupOrphanFiles(for: journal)
        return journal
    }

    func resumableJournals() -> [ConnectedCorpusOutboundJournal] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { directory in
            guard let jobID = UUID(uuidString: directory.lastPathComponent),
                  let journal = try? load(jobID: jobID),
                  !journal.state.isTerminal else { return nil }
            return journal
        }.sorted { $0.updatedAt < $1.updatedAt }
    }

    func adoptItem(
        _ item: ConnectedCorpusSpoolItem,
        expectedIndex: Int,
        jobID: UUID
    ) throws -> ConnectedCorpusOutboundJournal {
        var journal = try requiredJournal(jobID: jobID)
        guard journal.pendingPartition == nil,
              expectedIndex == journal.nextItemIndex,
              expectedIndex < journal.exportManifest.transferDates.count,
              item.sourceDate == journal.exportManifest.transferDates[expectedIndex],
              !journal.items.contains(where: { $0.itemID == item.itemID }) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        let destination = itemDirectoryURL(jobID: jobID)
            .appendingPathComponent("\(item.itemID.uuidString).item")
        try moveProtectedFile(from: item.file.url, to: destination)
        let inspected = try ConnectedTransferFile.inspect(destination)
        guard inspected.totalBytes == item.file.totalBytes,
              inspected.sha256 == item.file.sha256,
              inspected.totalBytes > 0,
              inspected.totalBytes <= ConnectedCorpusTransferConstants.maximumItemBytes else {
            try? fileManager.removeItem(at: destination)
            throw ConnectedCorpusOutboundStoreError.corruptFile
        }
        journal.items.append(ConnectedCorpusOutboundJournal.Item(
            itemID: item.itemID,
            kind: item.kind,
            sourceDate: item.sourceDate,
            isRequestedDate: item.isRequestedDate,
            relativePath: relativePath(destination, jobID: jobID),
            totalBytes: inspected.totalBytes,
            sha256: inspected.sha256,
            nextOffset: 0
        ))
        journal.nextItemIndex += 1
        journal.currentDate = item.sourceDate
        journal.state = .preparing
        journal.statusMessage = "Prepared \(journal.nextItemIndex) of \(journal.totalItemCount) days."
        do {
            try persist(&journal)
            return journal
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func spoolItems(for journal: ConnectedCorpusOutboundJournal) throws -> [ConnectedCorpusDurablePartitionBuilder.Source] {
        try journal.items.map { metadata in
            let url = try containedURL(relativePath: metadata.relativePath, jobID: journal.jobID)
            let inspected = try ConnectedTransferFile.inspect(url)
            guard inspected.totalBytes == metadata.totalBytes,
                  inspected.sha256 == metadata.sha256 else {
                throw ConnectedCorpusOutboundStoreError.corruptFile
            }
            return ConnectedCorpusDurablePartitionBuilder.Source(
                item: ConnectedCorpusSpoolItem(
                    itemID: metadata.itemID,
                    kind: metadata.kind,
                    sourceDate: metadata.sourceDate,
                    isRequestedDate: metadata.isRequestedDate,
                    file: inspected
                ),
                offset: metadata.nextOffset
            )
        }
    }

    func adoptPendingPartition(
        _ partition: ConnectedCorpusPreparedPartition,
        jobID: UUID
    ) throws -> ConnectedCorpusOutboundJournal {
        var journal = try requiredJournal(jobID: jobID)
        guard journal.pendingPartition == nil,
              partition.descriptor.sessionID == journal.sessionID,
              partition.descriptor.jobID == jobID,
              partition.descriptor.index == journal.committedPartitionCount,
              partition.descriptor.previousSHA256 == journal.lastCommittedPartitionSHA256,
              partition.manifest.segments.allSatisfy({ segment in
                  journal.items.contains(where: {
                      $0.itemID == segment.itemID
                          && $0.nextOffset == segment.itemOffset
                          && $0.sha256 == segment.itemSHA256
                  })
              }) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        let destination = partitionDirectoryURL(jobID: jobID)
            .appendingPathComponent("partition-\(partition.descriptor.index).bin")
        try moveProtectedFile(from: partition.file.url, to: destination)
        let inspected = try ConnectedTransferFile.inspect(destination)
        guard inspected.totalBytes == partition.descriptor.byteCount,
              inspected.sha256 == partition.descriptor.sha256 else {
            try? fileManager.removeItem(at: destination)
            throw ConnectedCorpusOutboundStoreError.corruptFile
        }
        journal.pendingPartition = ConnectedCorpusOutboundJournal.PendingPartition(
            transferID: partition.transferID,
            relativePath: relativePath(destination, jobID: jobID),
            descriptor: partition.descriptor,
            manifest: partition.manifest
        )
        journal.state = .transferring
        journal.currentDate = partition.descriptor.sourceDates.last
        journal.statusMessage = "Transferring durable partition \(partition.descriptor.index + 1)…"
        do {
            try persist(&journal)
            return journal
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func preparedPendingPartition(
        for journal: ConnectedCorpusOutboundJournal
    ) throws -> ConnectedCorpusPreparedPartition? {
        guard let pending = journal.pendingPartition else { return nil }
        let url = try containedURL(relativePath: pending.relativePath, jobID: journal.jobID)
        let inspected = try ConnectedTransferFile.inspect(url)
        guard inspected.totalBytes == pending.descriptor.byteCount,
              inspected.sha256 == pending.descriptor.sha256 else {
            throw ConnectedCorpusOutboundStoreError.corruptFile
        }
        return ConnectedCorpusPreparedPartition(
            transferID: pending.transferID,
            descriptor: pending.descriptor,
            file: inspected,
            manifest: pending.manifest
        )
    }

    /// Advances the digest and item frontier only after the receiver has
    /// durably accepted the pending partition. Journal replacement precedes
    /// removal of obsolete bytes, making every crash boundary replay-safe.
    func commitPendingPartition(jobID: UUID) throws -> ConnectedCorpusOutboundJournal {
        var journal = try requiredJournal(jobID: jobID)
        guard let pending = journal.pendingPartition,
              pending.descriptor.index == journal.committedPartitionCount,
              pending.descriptor.previousSHA256 == journal.lastCommittedPartitionSHA256 else {
            throw ConnectedCorpusOutboundStoreError.invalidCommit
        }
        var updatedItems = journal.items
        var completedPaths: [String] = []
        var completedCount = 0
        for segment in pending.manifest.segments {
            guard let index = updatedItems.firstIndex(where: { $0.itemID == segment.itemID }),
                  updatedItems[index].nextOffset == segment.itemOffset,
                  updatedItems[index].totalBytes == segment.totalItemBytes,
                  updatedItems[index].sha256 == segment.itemSHA256 else {
                throw ConnectedCorpusOutboundStoreError.invalidCommit
            }
            let next = segment.itemOffset.addingReportingOverflow(segment.segmentBytes)
            guard !next.overflow, next.partialValue <= updatedItems[index].totalBytes else {
                throw ConnectedCorpusOutboundStoreError.invalidCommit
            }
            updatedItems[index].nextOffset = next.partialValue
            if segment.isFinalSegment {
                guard next.partialValue == updatedItems[index].totalBytes else {
                    throw ConnectedCorpusOutboundStoreError.invalidCommit
                }
                completedPaths.append(updatedItems[index].relativePath)
                completedCount += 1
            }
        }
        let completedIDs = Set(pending.manifest.segments.filter(\.isFinalSegment).map(\.itemID))
        updatedItems.removeAll { completedIDs.contains($0.itemID) }
        let byteTotal = journal.committedByteCount.addingReportingOverflow(
            pending.descriptor.byteCount
        )
        guard !byteTotal.overflow else { throw ConnectedCorpusOutboundStoreError.invalidCommit }

        let partitionPath = pending.relativePath
        journal.items = updatedItems
        journal.pendingPartition = nil
        journal.committedPartitionCount += 1
        journal.committedByteCount = byteTotal.partialValue
        journal.lastCommittedPartitionSHA256 = pending.descriptor.sha256
        journal.completedItemCount += completedCount
        journal.state = .preparing
        journal.statusMessage = "Committed \(journal.completedItemCount) of \(journal.totalItemCount) days."
        try persist(&journal)

        for path in completedPaths + [partitionPath] {
            if let url = try? containedURL(relativePath: path, jobID: jobID) {
                try? fileManager.removeItem(at: url)
            }
        }
        return journal
    }

    func updateState(
        jobID: UUID,
        state: ConnectedCorpusOutboundState,
        message: String?,
        currentDate: Date? = nil
    ) throws -> ConnectedCorpusOutboundJournal {
        var journal = try requiredJournal(jobID: jobID)
        guard !journal.state.isTerminal || journal.state == state else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        journal.state = state
        journal.statusMessage = message
        if let currentDate { journal.currentDate = currentDate }
        try persist(&journal)
        return journal
    }

    func complete(
        jobID: UUID,
        acknowledgement: ConnectedCorpusTransferFinalAck
    ) throws -> ConnectedCorpusOutboundJournal {
        var journal = try requiredJournal(jobID: jobID)
        guard journal.items.isEmpty,
              journal.pendingPartition == nil,
              journal.nextItemIndex == journal.totalItemCount,
              journal.completedItemCount == journal.totalItemCount,
              acknowledgement.accepted,
              acknowledgement.jobID == jobID,
              acknowledgement.sessionID == journal.sessionID,
              acknowledgement.requestFingerprint == journal.session.requestFingerprint,
              acknowledgement.finalPartitionSHA256 == journal.lastCommittedPartitionSHA256 else {
            throw ConnectedCorpusOutboundStoreError.invalidCommit
        }
        journal.state = .completed
        journal.statusMessage = acknowledgement.message ?? "Connected export completed."
        journal.terminalAcknowledgement = acknowledgement
        try persist(&journal)
        return journal
    }

    @discardableResult
    func markCompletionRecorded(jobID: UUID) throws -> Bool {
        var journal = try requiredJournal(jobID: jobID)
        guard !journal.completionRecorded else { return false }
        journal.completionRecorded = true
        try persist(&journal)
        return true
    }

    func cancel(jobID: UUID, expired: Bool = false) throws {
        guard var journal = try load(jobID: jobID, allowExpired: true) else {
            throw ConnectedCorpusOutboundStoreError.jobNotFound
        }
        journal.state = expired ? .expired : .cancelled
        journal.statusMessage = expired
            ? "Durable connected export expired before completion."
            : "Durable connected export was cancelled."
        journal.items = []
        journal.pendingPartition = nil
        try persist(&journal)
        try removeInternalFiles(jobID: jobID, preservingJournal: true)
    }

    func remove(jobID: UUID) throws {
        let directory = jobDirectoryURL(jobID: jobID)
        guard contained(directory, by: rootURL) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    @discardableResult
    func cleanupExpired(now timestamp: Date? = nil) -> [UUID] {
        let timestamp = timestamp ?? now()
        guard let directories = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var expired: [UUID] = []
        for directory in directories {
            guard let jobID = UUID(uuidString: directory.lastPathComponent),
                  var journal = try? load(jobID: jobID, allowExpired: true),
                  journal.expiresAt <= timestamp else { continue }
            if journal.state == .expired {
                if timestamp >= journal.expiresAt.addingTimeInterval(24 * 60 * 60) {
                    try? remove(jobID: jobID)
                }
                continue
            }
            if journal.state.isTerminal {
                try? remove(jobID: jobID)
                expired.append(jobID)
                continue
            }
            journal.state = .expired
            journal.statusMessage = "Durable connected export expired before completion."
            journal.items = []
            journal.pendingPartition = nil
            try? persist(&journal)
            try? removeInternalFiles(jobID: jobID, preservingJournal: true)
            expired.append(jobID)
        }
        return expired
    }

    func totalInternalSpoolBytes(jobID: UUID) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: jobDirectoryURL(jobID: jobID),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func requiredJournal(jobID: UUID) throws -> ConnectedCorpusOutboundJournal {
        guard let journal = try load(jobID: jobID) else {
            throw ConnectedCorpusOutboundStoreError.jobNotFound
        }
        return journal
    }

    private func validate(_ journal: ConnectedCorpusOutboundJournal) throws {
        guard journal.version == ConnectedCorpusOutboundJournal.currentVersion,
              journal.macRequest.map({ $0.jobID == journal.session.jobID }) ?? true,
              journal.session.protocolVersion >= 2,
              journal.session.peerBinding != nil,
              journal.session.requestFingerprint == (try ConnectedCorpusRequestFingerprint.make(
                  for: journal.exportManifest
              )),
              journal.expiresAt > journal.createdAt,
              journal.nextItemIndex >= 0,
              journal.nextItemIndex <= journal.totalItemCount,
              journal.completedItemCount >= 0,
              journal.completedItemCount <= journal.nextItemIndex,
              journal.items.count <= journal.nextItemIndex,
              journal.committedPartitionCount >= 0,
              journal.committedByteCount >= 0,
              (journal.committedPartitionCount == 0)
                  == (journal.lastCommittedPartitionSHA256 == nil),
              journal.lastCommittedPartitionSHA256.map(\.isConnectedCorpusSHA256) ?? true,
              Set(journal.items.map(\.itemID)).count == journal.items.count,
              journal.items.allSatisfy({ item in
                  item.totalBytes > 0
                      && item.totalBytes <= ConnectedCorpusTransferConstants.maximumItemBytes
                      && item.sha256.isConnectedCorpusSHA256
                      && item.nextOffset >= 0
                      && item.nextOffset < item.totalBytes
                      && safeRelativePath(item.relativePath)
              }),
              journal.pendingPartition.map({ pending in
                  safeRelativePath(pending.relativePath)
                      && pending.descriptor.sessionID == journal.sessionID
                      && pending.descriptor.jobID == journal.jobID
                      && pending.descriptor.index == journal.committedPartitionCount
                      && pending.descriptor.previousSHA256 == journal.lastCommittedPartitionSHA256
                      && pending.manifest.partitionIndex == pending.descriptor.index
              }) ?? true else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        try journal.exportManifest.validate()
        if journal.state == .completed {
            guard journal.items.isEmpty,
                  journal.pendingPartition == nil,
                  journal.nextItemIndex == journal.totalItemCount,
                  journal.completedItemCount == journal.totalItemCount,
                  journal.terminalAcknowledgement?.accepted == true else {
                throw ConnectedCorpusOutboundStoreError.invalidJournal
            }
        }
    }

    private func validateFiles(_ journal: ConnectedCorpusOutboundJournal) throws {
        for item in journal.items {
            let url = try containedURL(relativePath: item.relativePath, jobID: journal.jobID)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ConnectedCorpusOutboundStoreError.missingFile
            }
            let inspected = try ConnectedTransferFile.inspect(url)
            guard inspected.totalBytes == item.totalBytes, inspected.sha256 == item.sha256 else {
                throw ConnectedCorpusOutboundStoreError.corruptFile
            }
        }
        if let pending = journal.pendingPartition {
            let url = try containedURL(relativePath: pending.relativePath, jobID: journal.jobID)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ConnectedCorpusOutboundStoreError.missingFile
            }
            let inspected = try ConnectedTransferFile.inspect(url)
            guard inspected.totalBytes == pending.descriptor.byteCount,
                  inspected.sha256 == pending.descriptor.sha256 else {
                throw ConnectedCorpusOutboundStoreError.corruptFile
            }
        }
    }

    private func persist(_ journal: inout ConnectedCorpusOutboundJournal) throws {
        journal.updatedAt = now()
        try validate(journal)
        try prepareDirectories(jobID: journal.jobID)
        let data = try encoder.encode(journal)
        let destination = journalURL(jobID: journal.jobID)
        let temporary = jobDirectoryURL(jobID: journal.jobID)
            .appendingPathComponent("journal-\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: protectedAttributes(permissions: 0o600)
        ) else { throw CocoaError(.fileWriteUnknown) }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
            try? fileManager.setAttributes(
                protectedAttributes(permissions: 0o600),
                ofItemAtPath: destination.path
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func prepareDirectories(jobID: UUID) throws {
        for directory in [
            rootURL,
            jobDirectoryURL(jobID: jobID),
            itemDirectoryURL(jobID: jobID),
            partitionDirectoryURL(jobID: jobID)
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: protectedAttributes(permissions: 0o700)
            )
            try? fileManager.setAttributes(
                protectedAttributes(permissions: 0o700),
                ofItemAtPath: directory.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = directory
            try? mutable.setResourceValues(values)
        }
    }

    private func moveProtectedFile(from source: URL, to destination: URL) throws {
        guard contained(destination, by: rootURL) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            try fileManager.copyItem(at: source, to: destination)
            try fileManager.removeItem(at: source)
        }
        try? fileManager.setAttributes(
            protectedAttributes(permissions: 0o600),
            ofItemAtPath: destination.path
        )
    }

    private func protectedAttributes(permissions: Int) -> [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        return attributes
    }

    private func cleanupOrphanFiles(for journal: ConnectedCorpusOutboundJournal) {
        let referenced = Set(
            journal.items.map(\.relativePath)
                + [journal.pendingPartition?.relativePath].compactMap { $0 }
                + ["journal.json"]
        )
        guard let enumerator = fileManager.enumerator(
            at: jobDirectoryURL(jobID: journal.jobID),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let relative = relativePath(url, jobID: journal.jobID)
            if !referenced.contains(relative) { try? fileManager.removeItem(at: url) }
        }
    }

    private func removeInternalFiles(jobID: UUID, preservingJournal: Bool) throws {
        let directory = jobDirectoryURL(jobID: jobID)
        guard contained(directory, by: rootURL) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        for child in [itemDirectoryURL(jobID: jobID), partitionDirectoryURL(jobID: jobID)] {
            if fileManager.fileExists(atPath: child.path) { try fileManager.removeItem(at: child) }
        }
        if !preservingJournal { try remove(jobID: jobID) }
    }

    private func jobDirectoryURL(jobID: UUID) -> URL {
        rootURL.appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
    }

    private func itemDirectoryURL(jobID: UUID) -> URL {
        jobDirectoryURL(jobID: jobID).appendingPathComponent("items", isDirectory: true)
    }

    private func partitionDirectoryURL(jobID: UUID) -> URL {
        jobDirectoryURL(jobID: jobID).appendingPathComponent("partitions", isDirectory: true)
    }

    private func journalURL(jobID: UUID) -> URL {
        jobDirectoryURL(jobID: jobID).appendingPathComponent("journal.json")
    }

    private func relativePath(_ url: URL, jobID: UUID) -> String {
        let rootPath = jobDirectoryURL(jobID: jobID).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return "" }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func containedURL(relativePath: String, jobID: UUID) throws -> URL {
        guard safeRelativePath(relativePath) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        let url = jobDirectoryURL(jobID: jobID).appendingPathComponent(relativePath)
        guard contained(url, by: jobDirectoryURL(jobID: jobID)) else {
            throw ConnectedCorpusOutboundStoreError.invalidJournal
        }
        return url
    }

    private func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && path.utf8.count <= 4_096
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private func contained(_ child: URL, by parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.resolvingSymlinksInPath().path
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }
}
