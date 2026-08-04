import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore

public enum DirectFileReceiverError: LocalizedError, Equatable {
    case invalidDestination
    case unsafeRelativePath(String)
    case requestChanged
    case sessionChanged
    case manifestChanged
    case partitionOutOfOrder
    case invalidChunk
    case invalidPartition
    case incompleteTransfer
    case destinationConflict(String)
    case invalidFinalization

    public var errorDescription: String? {
        switch self {
        case .invalidDestination: return "The direct file destination is invalid or unavailable."
        case .unsafeRelativePath(let path): return "The iPhone proposed an unsafe export path: \(path)."
        case .requestChanged: return "The durable direct file request changed."
        case .sessionChanged: return "The durable direct file session changed."
        case .manifestChanged: return "A direct export file manifest changed during resume."
        case .partitionOutOfOrder: return "A direct file partition arrived out of order."
        case .invalidChunk: return "A direct file chunk failed validation."
        case .invalidPartition: return "A direct file partition failed validation."
        case .incompleteTransfer: return "The direct file transfer is incomplete."
        case .destinationConflict(let path):
            return "The destination changed while the direct job was committing: \(path)."
        case .invalidFinalization: return "The direct file finalization did not match the durable corpus."
        }
    }
}

public struct DirectFileExportReceipt: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let status: String
    public let destinationPath: String
    public let filesWritten: Int
    public let totalBytes: Int64
    public let relativePaths: [String]
    public let successCount: Int
    public let totalCount: Int
    public let failedDateIdentifiers: [String]
    public let responseFileURL: URL
    public let responseByteCount: Int64
    public let responseSHA256: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case destinationPath = "destination_path"
        case filesWritten = "files_written"
        case totalBytes = "total_bytes"
        case relativePaths = "relative_paths"
        case successCount = "success_count"
        case totalCount = "total_count"
        case failedDateIdentifiers = "failed_date_identifiers"
        case responseFileURL, responseByteCount, responseSHA256
    }

    public init(
        jobID: UUID,
        status: String,
        destinationPath: String,
        filesWritten: Int,
        totalBytes: Int64,
        relativePaths: [String],
        successCount: Int,
        totalCount: Int,
        failedDateIdentifiers: [String],
        responseFileURL: URL,
        responseByteCount: Int64,
        responseSHA256: String
    ) {
        self.jobID = jobID
        self.status = status
        self.destinationPath = destinationPath
        self.filesWritten = filesWritten
        self.totalBytes = totalBytes
        self.relativePaths = relativePaths
        self.successCount = successCount
        self.totalCount = totalCount
        self.failedDateIdentifiers = failedDateIdentifiers
        self.responseFileURL = responseFileURL
        self.responseByteCount = responseByteCount
        self.responseSHA256 = responseSHA256
    }
}

private struct DirectFileCommitPlan: Codable, Equatable {
    let fileID: UUID
    let destinationRelativePath: String
    let beforeSHA256: String?
    let afterSHA256: String
    let stagedRelativePath: String
    var committed: Bool
}

private struct DirectDestinationIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
}

private struct DirectFileReceiveJournal: Codable, Equatable {
    static let currentVersion = 2
    let version: Int
    let request: DirectExportRequest
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    let destinationIdentity: DirectDestinationIdentity
    var manifests: [UUID: DirectExportFileManifest]
    var committedPartitions: [DirectTransferPartition]
    var commitPlans: [UUID: DirectFileCommitPlan]
    var outcome: DirectExportOutcome?
    var updatedAt: Date
}

/// Receives generated export files into durable partition spools and applies
/// them to an explicit destination through restart-safe, digest-bound writes.
public actor DirectFileReceiver {
    private struct PendingPartition {
        let descriptor: DirectTransferPartition
        let temporaryURL: URL
        var nextSequence: Int
        var receivedBytes: Int64
    }

    private let layout: DirectClientStorageLayout
    private let jobStore: DirectJobStore
    private let fileManager: FileManager
    private var journal: DirectFileReceiveJournal?
    private var pending: PendingPartition?

    public init(
        layout: DirectClientStorageLayout,
        jobStore: DirectJobStore,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.jobStore = jobStore
        self.fileManager = fileManager
    }

    public func prepare(
        request: DirectExportRequest,
        accepted: DirectExportAccepted,
        session: DirectTransferSession
    ) async throws {
        guard request.responseMode == .writeFiles,
              request.rawProfile == nil,
              let destination = request.destination,
              request.jobID == accepted.jobID,
              request.jobID == session.jobID,
              session.peerBinding == accepted.peerBinding,
              try DirectRequestFingerprint.make(for: request) == session.requestFingerprint else {
            throw DirectFileReceiverError.sessionChanged
        }
        let destinationURL = try validatedDestinationURL(destination.rootPath)
        let currentDestinationIdentity = try destinationIdentity(destinationURL)
        let url = try sessionDirectory(jobID: request.jobID).appendingPathComponent("file-journal.json")
        if fileManager.fileExists(atPath: url.path) {
            let persisted = try decoder().decode(
                DirectFileReceiveJournal.self,
                from: Data(contentsOf: url)
            )
            guard persisted.version == DirectFileReceiveJournal.currentVersion,
                  persisted.request == request,
                  persisted.destinationIdentity == currentDestinationIdentity else {
                throw DirectFileReceiverError.requestChanged
            }
            guard persisted.session == session,
                  persisted.accepted.peerBinding == accepted.peerBinding,
                  persisted.accepted.resolvedDateIdentifiers == accepted.resolvedDateIdentifiers else {
                throw DirectFileReceiverError.sessionChanged
            }
            journal = persisted
        } else {
            let created = DirectFileReceiveJournal(
                version: DirectFileReceiveJournal.currentVersion,
                request: request,
                accepted: accepted,
                session: session,
                destinationIdentity: currentDestinationIdentity,
                manifests: [:],
                committedPartitions: [],
                commitPlans: [:],
                outcome: nil,
                updatedAt: Date()
            )
            journal = created
            try saveJournal(created)
        }
        let pendingURL = try sessionDirectory(jobID: request.jobID).appendingPathComponent("file-pending.partition")
        try? fileManager.removeItem(at: pendingURL)
        pending = nil

        var record = try await jobStore.load(jobID: request.jobID)
        record.state = .preparing
        record.updatedAt = Date()
        record.peerBinding = session.peerBinding
        record.sessionID = session.sessionID
        record.requestFingerprint = session.requestFingerprint
        record.totalDays = accepted.resolvedDateIdentifiers.count
        record.message = "iPhone accepted the direct file export."
        try await jobStore.save(record)
    }

    public func store(manifest: DirectExportFileManifest) throws {
        guard var journal else { throw DirectFileReceiverError.incompleteTransfer }
        _ = try DirectExportFileManifest(
            jobID: manifest.jobID,
            fileID: manifest.fileID,
            relativePath: manifest.relativePath,
            byteCount: manifest.byteCount,
            sha256: manifest.sha256,
            writeMode: manifest.writeMode
        )
        guard manifest.jobID == journal.request.jobID else {
            throw DirectFileReceiverError.manifestChanged
        }
        let pathKey = try portablePathKey(manifest.relativePath)
        if let existing = journal.manifests[manifest.fileID], existing != manifest {
            throw DirectFileReceiverError.manifestChanged
        }
        for existing in journal.manifests.values where existing.fileID != manifest.fileID {
            guard try portablePathKey(existing.relativePath) != pathKey else {
                throw DirectFileReceiverError.manifestChanged
            }
        }
        journal.manifests[manifest.fileID] = manifest
        journal.updatedAt = Date()
        self.journal = journal
        try saveJournal(journal)
    }

    public func disposition(for open: DirectTransferOpen) throws -> DirectTransferDisposition {
        guard let journal else { throw DirectFileReceiverError.incompleteTransfer }
        try validate(open: open, journal: journal)
        let descriptor = open.partition
        if descriptor.index < journal.committedPartitions.count {
            guard journal.committedPartitions[descriptor.index] == descriptor else {
                throw DirectFileReceiverError.invalidPartition
            }
            return try DirectTransferDisposition(
                sessionID: open.session.sessionID,
                jobID: open.session.jobID,
                partitionIndex: descriptor.index,
                partitionSHA256: descriptor.sha256,
                disposition: .alreadyCommitted
            )
        }
        guard descriptor.index == journal.committedPartitions.count else {
            throw DirectFileReceiverError.partitionOutOfOrder
        }
        let temporary = try sessionDirectory(jobID: open.session.jobID)
            .appendingPathComponent("file-pending.partition")
        fileManager.createFile(atPath: temporary.path, contents: nil)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        pending = PendingPartition(
            descriptor: descriptor,
            temporaryURL: temporary,
            nextSequence: 1,
            receivedBytes: 0
        )
        return try DirectTransferDisposition(
            sessionID: open.session.sessionID,
            jobID: open.session.jobID,
            partitionIndex: descriptor.index,
            partitionSHA256: descriptor.sha256,
            disposition: .needed
        )
    }

    public func receive(_ chunk: DirectTransferChunk) throws -> DirectTransferChunkAcknowledgement {
        guard var pending,
              chunk.transferID == pending.descriptor.transferID,
              chunk.sequence == pending.nextSequence,
              DirectTransferFile.sha256Hex(chunk.data) == chunk.sha256,
              pending.receivedBytes + Int64(chunk.data.count) <= pending.descriptor.byteCount else {
            throw DirectFileReceiverError.invalidChunk
        }
        let handle = try FileHandle(forWritingTo: pending.temporaryURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: chunk.data)
        try handle.synchronize()
        pending.nextSequence += 1
        pending.receivedBytes += Int64(chunk.data.count)
        self.pending = pending
        return try DirectTransferChunkAcknowledgement(
            transferID: chunk.transferID,
            sequence: chunk.sequence,
            accepted: true,
            sha256: chunk.sha256
        )
    }

    public func commit(
        _ complete: DirectTransferPartitionComplete
    ) async throws -> DirectTransferPartitionAcknowledgement {
        guard var journal, let pending,
              complete.sessionID == journal.session.sessionID,
              complete.jobID == journal.request.jobID,
              complete.partitionIndex == pending.descriptor.index,
              complete.transferID == pending.descriptor.transferID,
              complete.partitionSHA256 == pending.descriptor.sha256,
              pending.nextSequence - 1 == pending.descriptor.chunkCount,
              pending.receivedBytes == pending.descriptor.byteCount else {
            throw DirectFileReceiverError.invalidPartition
        }
        let inspected = try DirectTransferFile.inspect(pending.temporaryURL)
        guard inspected.totalBytes == pending.descriptor.byteCount,
              inspected.sha256 == pending.descriptor.sha256 else {
            throw DirectFileReceiverError.invalidPartition
        }
        let destination = try partitionURL(
            jobID: journal.request.jobID,
            index: pending.descriptor.index
        )
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: pending.temporaryURL, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        journal.committedPartitions.append(pending.descriptor)
        journal.updatedAt = Date()
        self.journal = journal
        self.pending = nil
        try saveJournal(journal)

        var record = try await jobStore.load(jobID: journal.request.jobID)
        record.state = .transferring
        record.updatedAt = Date()
        record.committedPartitions = journal.committedPartitions.count
        record.committedBytes = journal.committedPartitions.reduce(0) { $0 + $1.byteCount }
        record.message = "Committed direct file partition \(pending.descriptor.index + 1)."
        try await jobStore.save(record)
        return try DirectTransferPartitionAcknowledgement(
            sessionID: complete.sessionID,
            jobID: complete.jobID,
            partitionIndex: complete.partitionIndex,
            transferID: complete.transferID,
            partitionSHA256: complete.partitionSHA256,
            accepted: true
        )
    }

    public func finalize(_ finalize: DirectTransferFinalize) async throws -> DirectFileExportReceipt {
        guard var journal,
              finalize.sessionID == journal.session.sessionID,
              finalize.jobID == journal.request.jobID,
              finalize.requestFingerprint == journal.session.requestFingerprint,
              finalize.totalPartitions == journal.committedPartitions.count,
              finalize.totalBytes == journal.committedPartitions.reduce(0, { $0 + $1.byteCount }),
              finalize.finalPartitionSHA256 == journal.committedPartitions.last?.sha256 else {
            throw DirectFileReceiverError.invalidFinalization
        }
        if let outcome = finalize.outcome {
            journal.outcome = outcome
        } else {
            journal.outcome = try DirectExportOutcome(
                status: "success",
                successCount: journal.accepted.resolvedDateIdentifiers.count,
                totalCount: journal.accepted.resolvedDateIdentifiers.count
            )
        }
        self.journal = journal
        try saveJournal(journal)
        try validateCompleteCorpus(journal)
        for manifest in journal.manifests.values.sorted(by: { $0.relativePath < $1.relativePath }) {
            try commitFile(manifest, journal: &journal)
        }
        self.journal = journal
        let receipt = try makeReceipt(journal)

        var record = try await jobStore.load(jobID: journal.request.jobID)
        record.state = .awaitingPeerAcknowledgement
        record.updatedAt = Date()
        record.committedPartitions = journal.committedPartitions.count
        record.committedBytes = finalize.totalBytes
        record.processedDays = journal.outcome?.successCount ?? 0
        record.totalDays = journal.outcome?.totalCount
        record.message = "Direct files committed; awaiting iPhone acknowledgement."
        record.responseArtifact = try DirectResponseArtifact(
            relativePath: receipt.responseFileURL.lastPathComponent,
            byteCount: receipt.responseByteCount,
            sha256: receipt.responseSHA256,
            dateRangeStart: journal.accepted.resolvedDateIdentifiers.first ?? "",
            dateRangeEnd: journal.accepted.resolvedDateIdentifiers.last ?? "",
            totalDays: journal.accepted.resolvedDateIdentifiers.count
        )
        try await jobStore.save(record)
        return receipt
    }

    public func acknowledgePeerCompletion(jobID: UUID) async throws {
        var record = try await jobStore.load(jobID: jobID)
        guard record.state == .awaitingPeerAcknowledgement,
              record.responseArtifact != nil else {
            throw DirectFileReceiverError.invalidFinalization
        }
        record.state = .completed
        record.updatedAt = Date()
        record.message = "Direct file export completed and acknowledged by iPhone."
        try await jobStore.save(record)
    }

    public func receipt(jobID: UUID) async throws -> DirectFileExportReceipt {
        let record = try await jobStore.load(jobID: jobID)
        guard let artifact = record.responseArtifact else {
            throw DirectFileReceiverError.incompleteTransfer
        }
        let url = layout.responseSpoolsURL
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(artifact.relativePath)
        let inspected = try DirectTransferFile.inspect(url)
        guard inspected.totalBytes == artifact.byteCount,
              inspected.sha256 == artifact.sha256 else {
            throw DirectFileReceiverError.invalidFinalization
        }
        let stored = try decoder().decode(DirectFileReceiptPayload.self, from: Data(contentsOf: url))
        return DirectFileExportReceipt(
            jobID: stored.jobID,
            status: stored.status,
            destinationPath: stored.destinationPath,
            filesWritten: stored.filesWritten,
            totalBytes: stored.totalBytes,
            relativePaths: stored.relativePaths,
            successCount: stored.successCount,
            totalCount: stored.totalCount,
            failedDateIdentifiers: stored.failedDateIdentifiers,
            responseFileURL: url,
            responseByteCount: inspected.totalBytes,
            responseSHA256: inspected.sha256
        )
    }

    public func cancel(jobID: UUID, message: String = "Direct export cancelled by the CLI.") async throws {
        var record = try await jobStore.load(jobID: jobID)
        record.state = .cancelled
        record.updatedAt = Date()
        record.message = message
        try await jobStore.save(record)
        pending = nil
    }

    private func validate(open: DirectTransferOpen, journal: DirectFileReceiveJournal) throws {
        _ = try DirectTransferPartition(
            index: open.partition.index,
            transferID: open.partition.transferID,
            sourceDates: open.partition.sourceDates,
            byteCount: open.partition.byteCount,
            chunkCount: open.partition.chunkCount,
            sha256: open.partition.sha256,
            previousSHA256: open.partition.previousSHA256,
            itemSegment: open.partition.itemSegment
        )
        guard open.session == journal.session,
              let segment = open.partition.itemSegment,
              let fileID = UUID(uuidString: segment.itemID),
              let manifest = journal.manifests[fileID],
              manifest.byteCount == segment.itemByteCount else {
            throw DirectFileReceiverError.invalidPartition
        }
        if open.partition.index < journal.committedPartitions.count {
            guard journal.committedPartitions[open.partition.index] == open.partition else {
                throw DirectFileReceiverError.invalidPartition
            }
        } else if open.partition.index == journal.committedPartitions.count {
            guard open.partition.previousSHA256 == journal.committedPartitions.last?.sha256 else {
                throw DirectFileReceiverError.invalidPartition
            }
        }
    }

    private func validateCompleteCorpus(_ journal: DirectFileReceiveJournal) throws {
        var grouped: [UUID: [DirectTransferPartition]] = [:]
        for descriptor in journal.committedPartitions {
            guard let value = descriptor.itemSegment?.itemID,
                  let fileID = UUID(uuidString: value),
                  journal.manifests[fileID] != nil else {
                throw DirectFileReceiverError.invalidPartition
            }
            grouped[fileID, default: []].append(descriptor)
        }
        for manifest in journal.manifests.values {
            let descriptors = grouped[manifest.fileID, default: []].sorted { $0.index < $1.index }
            if manifest.byteCount == 0 {
                guard descriptors.isEmpty,
                      manifest.sha256 == DirectTransferFile.sha256Hex(Data()) else {
                    throw DirectFileReceiverError.invalidPartition
                }
                continue
            }
            var offset: Int64 = 0
            var hasher = SHA256()
            for descriptor in descriptors {
                guard let segment = descriptor.itemSegment,
                      segment.offset == offset,
                      segment.itemByteCount == manifest.byteCount else {
                    throw DirectFileReceiverError.invalidPartition
                }
                let handle = try FileHandle(forReadingFrom: partitionURL(
                    jobID: journal.request.jobID,
                    index: descriptor.index
                ))
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    hasher.update(data: data)
                }
                try handle.close()
                offset += descriptor.byteCount
            }
            guard offset == manifest.byteCount,
                  descriptors.last?.itemSegment?.isFinalSegment == true,
                  hex(Data(hasher.finalize())) == manifest.sha256 else {
                throw DirectFileReceiverError.invalidPartition
            }
        }
    }

    private func commitFile(
        _ manifest: DirectExportFileManifest,
        journal: inout DirectFileReceiveJournal
    ) throws {
        let root = try validatedDestinationURL(journal.request.destination?.rootPath ?? "")
        guard try destinationIdentity(root) == journal.destinationIdentity else {
            throw DirectFileReceiverError.invalidDestination
        }
        _ = try destinationURL(root: root, relativePath: manifest.relativePath)
        try ensureSafeParent(
            root: root,
            relativePath: manifest.relativePath,
            expectedRootIdentity: journal.destinationIdentity
        )
        if let existingPlan = journal.commitPlans[manifest.fileID] {
            let current = try digestIfRegularFile(
                root: root,
                relativePath: manifest.relativePath,
                expectedRootIdentity: journal.destinationIdentity
            )
            if current == existingPlan.afterSHA256 {
                if !existingPlan.committed {
                    var committed = existingPlan
                    committed.committed = true
                    journal.commitPlans[manifest.fileID] = committed
                    try saveJournal(journal)
                }
                return
            }
            guard current == existingPlan.beforeSHA256 else {
                throw DirectFileReceiverError.destinationConflict(manifest.relativePath)
            }
            let stage = try sessionDirectory(jobID: journal.request.jobID)
                .appendingPathComponent(existingPlan.stagedRelativePath)
            guard try destinationIdentity(root) == journal.destinationIdentity else {
                throw DirectFileReceiverError.invalidDestination
            }
            try atomicInstall(
                stage: stage,
                root: root,
                relativePath: manifest.relativePath,
                expectedBeforeSHA256: existingPlan.beforeSHA256,
                expectedRootIdentity: journal.destinationIdentity
            )
            guard try destinationIdentity(root) == journal.destinationIdentity,
                  try digestIfRegularFile(
                    root: root,
                    relativePath: manifest.relativePath,
                    expectedRootIdentity: journal.destinationIdentity
                  ) == existingPlan.afterSHA256 else {
                throw DirectFileReceiverError.destinationConflict(manifest.relativePath)
            }
            var committed = existingPlan
            committed.committed = true
            journal.commitPlans[manifest.fileID] = committed
            try saveJournal(journal)
            return
        }

        let before = try digestIfRegularFile(
            root: root,
            relativePath: manifest.relativePath,
            expectedRootIdentity: journal.destinationIdentity
        )
        let source = try assembleSource(manifest, journal: journal)
        let stageName = "file-output-\(manifest.fileID.uuidString.lowercased()).stage"
        let stage = try sessionDirectory(jobID: journal.request.jobID).appendingPathComponent(stageName)
        try? fileManager.removeItem(at: stage)
        switch manifest.writeMode {
        case .overwrite:
            try fileManager.copyItem(at: source, to: stage)
        case .append:
            try buildAppendStage(
                root: root,
                relativePath: manifest.relativePath,
                source: source,
                destination: stage,
                expectedRootIdentity: journal.destinationIdentity
            )
        case .mergeMarkdown, .mergeMarkdownPreservingPreamble:
            try buildMarkdownMergeStage(
                root: root,
                relativePath: manifest.relativePath,
                source: source,
                destination: stage,
                preservesPreamble: manifest.writeMode == .mergeMarkdownPreservingPreamble,
                expectedRootIdentity: journal.destinationIdentity
            )
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.path)
        let after = try DirectTransferFile.inspect(stage).sha256
        let plan = DirectFileCommitPlan(
            fileID: manifest.fileID,
            destinationRelativePath: manifest.relativePath,
            beforeSHA256: before,
            afterSHA256: after,
            stagedRelativePath: stageName,
            committed: false
        )
        journal.commitPlans[manifest.fileID] = plan
        journal.updatedAt = Date()
        try saveJournal(journal)
        guard try destinationIdentity(root) == journal.destinationIdentity else {
            throw DirectFileReceiverError.invalidDestination
        }
        try atomicInstall(
            stage: stage,
            root: root,
            relativePath: manifest.relativePath,
            expectedBeforeSHA256: before,
            expectedRootIdentity: journal.destinationIdentity
        )
        guard try destinationIdentity(root) == journal.destinationIdentity,
              try digestIfRegularFile(
                root: root,
                relativePath: manifest.relativePath,
                expectedRootIdentity: journal.destinationIdentity
              ) == after else {
            throw DirectFileReceiverError.destinationConflict(manifest.relativePath)
        }
        var committed = plan
        committed.committed = true
        journal.commitPlans[manifest.fileID] = committed
        journal.updatedAt = Date()
        try saveJournal(journal)
    }

    private func assembleSource(
        _ manifest: DirectExportFileManifest,
        journal: DirectFileReceiveJournal
    ) throws -> URL {
        let url = try sessionDirectory(jobID: journal.request.jobID)
            .appendingPathComponent("file-source-\(manifest.fileID.uuidString.lowercased()).bin")
        if fileManager.fileExists(atPath: url.path),
           let inspected = try? DirectTransferFile.inspect(url),
           inspected.totalBytes == manifest.byteCount,
           inspected.sha256 == manifest.sha256 {
            return url
        }
        fileManager.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        for descriptor in journal.committedPartitions where
            descriptor.itemSegment?.itemID == manifest.fileID.uuidString.lowercased() {
            let input = try FileHandle(forReadingFrom: partitionURL(
                jobID: journal.request.jobID,
                index: descriptor.index
            ))
            while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                try output.write(contentsOf: data)
            }
            try input.close()
        }
        try output.synchronize()
        try output.close()
        let inspected = try DirectTransferFile.inspect(url)
        guard inspected.totalBytes == manifest.byteCount,
              inspected.sha256 == manifest.sha256 else {
            throw DirectFileReceiverError.invalidPartition
        }
        return url
    }

    private func buildAppendStage(
        root: URL,
        relativePath: String,
        source: URL,
        destination: URL,
        expectedRootIdentity: DirectDestinationIdentity
    ) throws {
        fileManager.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        if let existingDescriptor = try openExistingFile(
            root: root,
            relativePath: relativePath,
            expectedRootIdentity: expectedRootIdentity
        ) {
            defer { close(existingDescriptor) }
            try copy(descriptor: existingDescriptor, to: output)
            try output.write(contentsOf: Data("\n\n".utf8))
        }
        try copy(source, to: output)
        try output.synchronize()
        try output.close()
    }

    private func buildMarkdownMergeStage(
        root: URL,
        relativePath: String,
        source: URL,
        destination: URL,
        preservesPreamble: Bool,
        expectedRootIdentity: DirectDestinationIdentity
    ) throws {
        let maximumMergeBytes: Int64 = 64 * 1_024 * 1_024
        let sourceInfo = try DirectTransferFile.inspect(source)
        guard sourceInfo.totalBytes <= maximumMergeBytes,
              let new = String(data: try Data(contentsOf: source), encoding: .utf8) else {
            throw DirectFileReceiverError.destinationConflict(relativePath)
        }
        let result: String
        if let existingDescriptor = try openExistingFile(
            root: root,
            relativePath: relativePath,
            expectedRootIdentity: expectedRootIdentity
        ) {
            defer { close(existingDescriptor) }
            var information = stat()
            guard fstat(existingDescriptor, &information) == 0,
                  information.st_size <= maximumMergeBytes,
                  let old = String(
                    data: try data(from: existingDescriptor, maximumBytes: maximumMergeBytes),
                    encoding: .utf8
                  ) else {
                throw DirectFileReceiverError.destinationConflict(relativePath)
            }
            result = preservesPreamble
                ? MarkdownMerger.mergePreservingPreamble(existing: old, new: new)
                : MarkdownMerger.merge(existing: old, new: new)
        } else {
            result = new
        }
        try Data(result.utf8).write(to: destination, options: .atomic)
    }

    private func makeReceipt(_ journal: DirectFileReceiveJournal) throws -> DirectFileExportReceipt {
        guard let destination = journal.request.destination,
              let outcome = journal.outcome else {
            throw DirectFileReceiverError.invalidFinalization
        }
        let payload = DirectFileReceiptPayload(
            jobID: journal.request.jobID,
            status: outcome.status,
            destinationPath: destination.rootPath,
            filesWritten: journal.manifests.count,
            totalBytes: journal.manifests.values.reduce(0) { $0 + $1.byteCount },
            relativePaths: journal.manifests.values.map(\.relativePath).sorted(),
            successCount: outcome.successCount,
            totalCount: outcome.totalCount,
            failedDateIdentifiers: outcome.failedDateIdentifiers
        )
        let directory = layout.responseSpoolsURL
            .appendingPathComponent(journal.request.jobID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("file-receipt.json")
        var object = try JSONSerialization.jsonObject(with: encoder().encode(payload)) as! [String: Any]
        object["backend"] = "direct"
        object["message"] = "iPhone export files were committed to the explicit destination."
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try restrictedAtomicWrite(data, to: url)
        let inspected = try DirectTransferFile.inspect(url)
        return DirectFileExportReceipt(
            jobID: payload.jobID,
            status: payload.status,
            destinationPath: payload.destinationPath,
            filesWritten: payload.filesWritten,
            totalBytes: payload.totalBytes,
            relativePaths: payload.relativePaths,
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            failedDateIdentifiers: payload.failedDateIdentifiers,
            responseFileURL: url,
            responseByteCount: inspected.totalBytes,
            responseSHA256: inspected.sha256
        )
    }

    private func validatedDestinationURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4_096 else {
            throw DirectFileReceiverError.invalidDestination
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !isSymbolicLink(url) else {
            throw DirectFileReceiverError.invalidDestination
        }
        return url
    }

    private func destinationIdentity(_ url: URL) throws -> DirectDestinationIdentity {
        var information = stat()
        guard lstat(url.path, &information) == 0,
              information.st_mode & S_IFMT == S_IFDIR else {
            throw DirectFileReceiverError.invalidDestination
        }
        return DirectDestinationIdentity(
            device: UInt64(bitPattern: Int64(information.st_dev)),
            inode: UInt64(information.st_ino)
        )
    }

    private func safeRelativeComponents(_ path: String) throws -> [String] {
        let bytes = Array(path.utf8)
        let windowsAbsolute = bytes.count >= 2
            && bytes[1] == 58
            && ((65...90).contains(bytes[0]) || (97...122).contains(bytes[0]))
        guard !path.isEmpty,
              bytes.count <= 4_096,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !windowsAbsolute,
              !path.contains("\\"),
              !path.contains("\0"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw DirectFileReceiverError.unsafeRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DirectFileReceiverError.unsafeRelativePath(path)
        }
        return components
    }

    private func portablePathKey(_ path: String) throws -> String {
        try safeRelativeComponents(path)
            .joined(separator: "/")
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCompatibilityMapping
    }

    private func destinationURL(root: URL, relativePath: String) throws -> URL {
        let components = try safeRelativeComponents(relativePath)
        let destination = components.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard destination.path.hasPrefix(root.path + "/") else {
            throw DirectFileReceiverError.unsafeRelativePath(relativePath)
        }
        return destination
    }

    private func ensureSafeParent(
        root: URL,
        relativePath: String,
        expectedRootIdentity: DirectDestinationIdentity
    ) throws {
        let (descriptor, _) = try openDestinationParent(
            root: root,
            relativePath: relativePath,
            createDirectories: true,
            expectedRootIdentity: expectedRootIdentity
        )
        close(descriptor)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func digestIfRegularFile(
        root: URL,
        relativePath: String,
        expectedRootIdentity: DirectDestinationIdentity
    ) throws -> String? {
        guard let descriptor = try openExistingFile(
            root: root,
            relativePath: relativePath,
            expectedRootIdentity: expectedRootIdentity
        ) else { return nil }
        defer { close(descriptor) }
        return try digest(descriptor: descriptor)
    }

    private func atomicInstall(
        stage: URL,
        root: URL,
        relativePath: String,
        expectedBeforeSHA256: String?,
        expectedRootIdentity: DirectDestinationIdentity
    ) throws {
        let (parentDescriptor, fileName) = try openDestinationParent(
            root: root,
            relativePath: relativePath,
            createDirectories: true,
            expectedRootIdentity: expectedRootIdentity
        )
        defer { close(parentDescriptor) }

        let openedExisting = fileName.withCString {
            openat(parentDescriptor, $0, O_RDONLY | O_NOFOLLOW)
        }
        let existingDescriptor: Int32?
        if openedExisting >= 0 {
            var information = stat()
            guard expectedBeforeSHA256 != nil,
                  fstat(openedExisting, &information) == 0,
                  information.st_mode & S_IFMT == S_IFREG,
                  try digest(descriptor: openedExisting) == expectedBeforeSHA256 else {
                close(openedExisting)
                throw DirectFileReceiverError.destinationConflict(relativePath)
            }
            existingDescriptor = openedExisting
        } else {
            guard errno == ENOENT, expectedBeforeSHA256 == nil else {
                throw DirectFileReceiverError.destinationConflict(relativePath)
            }
            existingDescriptor = nil
        }
        defer {
            if let existingDescriptor { close(existingDescriptor) }
        }

        let temporaryName = ".\(fileName).healthmd-\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryName.withCString {
            openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw DirectFileReceiverError.destinationConflict(relativePath)
        }
        var shouldRemoveTemporary = true
        defer {
            close(temporaryDescriptor)
            if shouldRemoveTemporary {
                temporaryName.withCString { _ = unlinkat(parentDescriptor, $0, 0) }
            }
        }

        let input = try FileHandle(forReadingFrom: stage)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < rawBuffer.count {
                    let written = Darwin.write(
                        temporaryDescriptor,
                        baseAddress.advanced(by: offset),
                        rawBuffer.count - offset
                    )
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else {
                        throw DirectFileReceiverError.destinationConflict(relativePath)
                    }
                    offset += written
                }
            }
        }
        guard fsync(temporaryDescriptor) == 0 else {
            throw DirectFileReceiverError.destinationConflict(relativePath)
        }

        if let existingDescriptor {
            let swapResult = temporaryName.withCString { temporaryPointer in
                fileName.withCString { destinationPointer in
                    renameatx_np(
                        parentDescriptor,
                        temporaryPointer,
                        parentDescriptor,
                        destinationPointer,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard swapResult == 0 else {
                throw DirectFileReceiverError.destinationConflict(relativePath)
            }

            // The swap is the compare-and-swap point. The displaced path must
            // still be the exact inode opened and hashed before the exchange,
            // and its content must still match the persisted preimage.
            var openedInformation = stat()
            var displacedInformation = stat()
            let displacedResult = temporaryName.withCString {
                fstatat(parentDescriptor, $0, &displacedInformation, AT_SYMLINK_NOFOLLOW)
            }
            let displacedDigest = try digest(descriptor: existingDescriptor)
            let preimageStillMatches = fstat(existingDescriptor, &openedInformation) == 0
                && displacedResult == 0
                && openedInformation.st_dev == displacedInformation.st_dev
                && openedInformation.st_ino == displacedInformation.st_ino
                && displacedDigest == expectedBeforeSHA256
            guard preimageStillMatches else {
                let rollbackResult = temporaryName.withCString { temporaryPointer in
                    fileName.withCString { destinationPointer in
                        renameatx_np(
                            parentDescriptor,
                            temporaryPointer,
                            parentDescriptor,
                            destinationPointer,
                            UInt32(RENAME_SWAP)
                        )
                    }
                }
                if rollbackResult == 0 {
                    temporaryName.withCString { _ = unlinkat(parentDescriptor, $0, 0) }
                }
                // If another process also mutated the directory during rollback,
                // do not unlink a path whose identity is no longer ours.
                shouldRemoveTemporary = false
                throw DirectFileReceiverError.destinationConflict(relativePath)
            }
            temporaryName.withCString { _ = unlinkat(parentDescriptor, $0, 0) }
            shouldRemoveTemporary = false
        } else {
            let renameResult = temporaryName.withCString { temporaryPointer in
                fileName.withCString { destinationPointer in
                    renameatx_np(
                        parentDescriptor,
                        temporaryPointer,
                        parentDescriptor,
                        destinationPointer,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard renameResult == 0 else {
                throw DirectFileReceiverError.destinationConflict(relativePath)
            }
            shouldRemoveTemporary = false
        }
        _ = fsync(parentDescriptor)
    }

    private func openDestinationParent(
        root: URL,
        relativePath: String,
        createDirectories: Bool,
        expectedRootIdentity: DirectDestinationIdentity? = nil
    ) throws -> (descriptor: Int32, fileName: String) {
        let components = try safeRelativeComponents(relativePath)
        guard let fileName = components.last else {
            throw DirectFileReceiverError.unsafeRelativePath(relativePath)
        }
        var currentDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard currentDescriptor >= 0 else {
            throw DirectFileReceiverError.invalidDestination
        }
        if let expectedRootIdentity {
            var rootInformation = stat()
            guard fstat(currentDescriptor, &rootInformation) == 0,
                  DirectDestinationIdentity(
                    device: UInt64(bitPattern: Int64(rootInformation.st_dev)),
                    inode: UInt64(rootInformation.st_ino)
                  ) == expectedRootIdentity else {
                close(currentDescriptor)
                throw DirectFileReceiverError.invalidDestination
            }
        }
        do {
            for component in components.dropLast() {
                var nextDescriptor = component.withCString {
                    openat(currentDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                }
                if nextDescriptor < 0, errno == ENOENT, createDirectories {
                    let created = component.withCString {
                        mkdirat(currentDescriptor, $0, S_IRWXU)
                    }
                    guard created == 0 || errno == EEXIST else {
                        throw DirectFileReceiverError.destinationConflict(relativePath)
                    }
                    nextDescriptor = component.withCString {
                        openat(currentDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    }
                }
                guard nextDescriptor >= 0 else {
                    throw DirectFileReceiverError.unsafeRelativePath(relativePath)
                }
                close(currentDescriptor)
                currentDescriptor = nextDescriptor
            }
            return (currentDescriptor, fileName)
        } catch {
            close(currentDescriptor)
            throw error
        }
    }

    private func openExistingFile(
        root: URL,
        relativePath: String,
        expectedRootIdentity: DirectDestinationIdentity
    ) throws -> Int32? {
        let (parentDescriptor, fileName) = try openDestinationParent(
            root: root,
            relativePath: relativePath,
            createDirectories: false,
            expectedRootIdentity: expectedRootIdentity
        )
        defer { close(parentDescriptor) }
        let descriptor = fileName.withCString {
            openat(parentDescriptor, $0, O_RDONLY | O_NOFOLLOW)
        }
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw DirectFileReceiverError.destinationConflict(relativePath)
        }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw DirectFileReceiverError.destinationConflict(relativePath)
        }
        return descriptor
    }

    private func digest(descriptor: Int32) throws -> String {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw DirectFileReceiverError.invalidDestination
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw DirectFileReceiverError.invalidDestination }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    private func data(
        from descriptor: Int32,
        maximumBytes: Int64
    ) throws -> Data {
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              information.st_size <= maximumBytes,
              lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw DirectFileReceiverError.invalidDestination
        }
        var result = Data()
        result.reserveCapacity(Int(information.st_size))
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw DirectFileReceiverError.invalidDestination }
            if count == 0 { break }
            result.append(contentsOf: buffer[0..<count])
        }
        return result
    }

    private func copy(descriptor: Int32, to output: FileHandle) throws {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw DirectFileReceiverError.invalidDestination
        }
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw DirectFileReceiverError.invalidDestination }
            if count == 0 { break }
            try output.write(contentsOf: Data(buffer[0..<count]))
        }
    }

    private func copy(_ url: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: url)
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        try input.close()
    }

    private func sessionDirectory(jobID: UUID) throws -> URL {
        try layout.prepare(fileManager: fileManager)
        let directory = layout.corpusSessionsURL
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func partitionURL(jobID: UUID, index: Int) throws -> URL {
        try sessionDirectory(jobID: jobID)
            .appendingPathComponent(String(format: "file-partition-%08d.bin", index))
    }

    private func saveJournal(_ journal: DirectFileReceiveJournal) throws {
        let url = try sessionDirectory(jobID: journal.request.jobID)
            .appendingPathComponent("file-journal.json")
        try restrictedAtomicWrite(encoder().encode(journal), to: url)
    }

    private func restrictedAtomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    private func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

private struct DirectFileReceiptPayload: Codable {
    let jobID: UUID
    let status: String
    let destinationPath: String
    let filesWritten: Int
    let totalBytes: Int64
    let relativePaths: [String]
    let successCount: Int
    let totalCount: Int
    let failedDateIdentifiers: [String]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case destinationPath = "destination_path"
        case filesWritten = "files_written"
        case totalBytes = "total_bytes"
        case relativePaths = "relative_paths"
        case successCount = "success_count"
        case totalCount = "total_count"
        case failedDateIdentifiers = "failed_date_identifiers"
    }
}
