import Foundation

nonisolated struct GoogleDriveRunResult: Equatable, Sendable {
    let operationID: UUID
    let verifiedArtifactCount: Int
    let totalArtifactCount: Int
    let skippedArtifactCount: Int
    let errorID: GoogleDriveErrorID?

    var isComplete: Bool {
        verifiedArtifactCount + skippedArtifactCount == totalArtifactCount && errorID == nil
    }

    var isPartial: Bool { verifiedArtifactCount > 0 && !isComplete }
}

private actor GoogleDriveDestinationRunGate {
    static let shared = GoogleDriveDestinationRunGate()
    private var active: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ destinationID: UUID) async {
        if active.insert(destinationID).inserted { return }
        await withCheckedContinuation { continuation in
            waiters[destinationID, default: []].append(continuation)
        }
    }

    func release(_ destinationID: UUID) {
        guard var queued = waiters[destinationID], !queued.isEmpty else {
            active.remove(destinationID)
            waiters[destinationID] = nil
            return
        }
        let next = queued.removeFirst()
        waiters[destinationID] = queued.isEmpty ? nil : queued
        next.resume()
    }
}

/// One runner for manual, scheduled and recovery execution. It consumes frozen renderer bytes,
/// stages final files exactly once, preflights the complete bundle, commits in deterministic path
/// order, and checkpoints every transition.
@MainActor
final class GoogleDriveDestinationRunner {
    nonisolated deinit {}

    private struct FolderPlan {
        let relativePath: String
        let pathHash: String
        let id: String
        let parentID: String
        let name: String
        let resourceKey: String?
        let isNew: Bool
    }

    private let api: any GoogleDriveAPIClientProtocol
    private let managedStore: GoogleDriveManagedObjectStore
    private let journalStore: GoogleDriveJournalStore

    init(
        api: any GoogleDriveAPIClientProtocol = GoogleDriveAPIClient(),
        managedStore: GoogleDriveManagedObjectStore? = nil,
        journalStore: GoogleDriveJournalStore? = nil
    ) throws {
        self.api = api
        self.managedStore = managedStore ?? GoogleDriveManagedObjectStore()
        self.journalStore = try journalStore ?? GoogleDriveJournalStore()
    }

    func run(
        bundle: GoogleDriveGeneratedArtifactBundle,
        destination: GoogleDriveDestination,
        accessToken: String
    ) async -> GoogleDriveRunResult {
        await GoogleDriveDestinationRunGate.shared.acquire(destination.id)
        defer { Task { await GoogleDriveDestinationRunGate.shared.release(destination.id) } }

        do {
            try await journalStore.prune()
            guard !(await journalStore.isAbandoned(operationID: bundle.operationID)) else {
                throw GoogleDriveError(.ambiguousCommit)
            }
            var journal: GoogleDriveOperationJournal
            if await journalStore.contains(operationID: bundle.operationID) {
                let existing = try await journalStore.load(operationID: bundle.operationID)
                guard existing.bundleDigest == bundle.digest,
                      existing.destinationSnapshot == GoogleDriveDestinationSnapshot(destination: destination) else {
                    throw GoogleDriveError(.remoteConflict)
                }
                journal = existing
            } else {
                journal = try await journalStore.create(bundle: bundle, destination: destination)
            }
            return try await execute(
                journal: &journal,
                destination: destination,
                accessToken: accessToken
            )
        } catch let error as GoogleDriveError {
            return GoogleDriveRunResult(
                operationID: bundle.operationID,
                verifiedArtifactCount: 0,
                totalArtifactCount: bundle.artifacts.count,
                skippedArtifactCount: 0,
                errorID: error.id
            )
        } catch is CancellationError {
            return GoogleDriveRunResult(
                operationID: bundle.operationID,
                verifiedArtifactCount: 0,
                totalArtifactCount: bundle.artifacts.count,
                skippedArtifactCount: 0,
                errorID: .partialCompletion
            )
        } catch {
            return GoogleDriveRunResult(
                operationID: bundle.operationID,
                verifiedArtifactCount: 0,
                totalArtifactCount: bundle.artifacts.count,
                skippedArtifactCount: 0,
                errorID: .ambiguousCommit
            )
        }
    }

    func hasJournal(operationID: UUID) async -> Bool {
        await journalStore.contains(operationID: operationID)
    }

    func recoveryJournal(operationID: UUID) async throws -> GoogleDriveOperationJournal {
        try await journalStore.prune()
        guard !(await journalStore.isAbandoned(operationID: operationID)) else {
            throw GoogleDriveError(.ambiguousCommit)
        }
        return try await journalStore.load(operationID: operationID)
    }

    func hasRecoverableJournal(operationID: UUID) async throws -> Bool {
        try await journalStore.prune()
        guard !(await journalStore.isAbandoned(operationID: operationID)) else {
            throw GoogleDriveError(.ambiguousCommit)
        }
        return await journalStore.contains(operationID: operationID)
    }

    func acknowledge(operationID: UUID) async throws {
        let journal = try await journalStore.load(operationID: operationID)
        guard journal.terminalErrorID == nil,
              journal.artifacts.allSatisfy({ $0.phase == .verified }) else {
            throw GoogleDriveError(.partialCompletion)
        }
        try await journalStore.markAcknowledged(operationID: operationID)
        try await journalStore.prune()
    }

    func resume(
        operationID: UUID,
        destination: GoogleDriveDestination,
        accessToken: String
    ) async -> GoogleDriveRunResult {
        await GoogleDriveDestinationRunGate.shared.acquire(destination.id)
        defer { Task { await GoogleDriveDestinationRunGate.shared.release(destination.id) } }
        do {
            var journal = try await journalStore.load(operationID: operationID)
            guard journal.destinationSnapshot == GoogleDriveDestinationSnapshot(destination: destination) else {
                throw GoogleDriveError(.remoteConflict)
            }
            return try await execute(
                journal: &journal,
                destination: destination,
                accessToken: accessToken
            )
        } catch let error as GoogleDriveError {
            return GoogleDriveRunResult(
                operationID: operationID,
                verifiedArtifactCount: 0,
                totalArtifactCount: 0,
                skippedArtifactCount: 0,
                errorID: error.id
            )
        } catch {
            return GoogleDriveRunResult(
                operationID: operationID,
                verifiedArtifactCount: 0,
                totalArtifactCount: 0,
                skippedArtifactCount: 0,
                errorID: .ambiguousCommit
            )
        }
    }

    private func execute(
        journal: inout GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
        accessToken: String
    ) async throws -> GoogleDriveRunResult {
        _ = try await api.validateFolder(destination, accessToken: accessToken)
        try Task.checkCancellation()

        // Planning performs every exact-ID check, baseline download, merge and final-byte spool
        // before the first create/update mutation.
        let folders = try await planFolders(
            journal: &journal,
            destination: destination,
            accessToken: accessToken
        )
        try await prepareArtifacts(
            journal: &journal,
            destination: destination,
            folders: folders,
            accessToken: accessToken
        )
        try await preflightAll(journal: journal, accessToken: accessToken)

        // New folders are committed parent-first. Reserved IDs were checkpointed during planning.
        for folder in folders.filter(\.isNew).sorted(by: { lhs, rhs in
            let leftDepth = lhs.relativePath.split(separator: "/").count
            let rightDepth = rhs.relativePath.split(separator: "/").count
            return leftDepth == rightDepth ? lhs.relativePath < rhs.relativePath : leftDepth < rightDepth
        }) {
            try Task.checkCancellation()
            let metadata: GoogleDriveFileMetadata
            do {
                metadata = try await api.metadata(
                    id: folder.id,
                    resourceKey: folder.resourceKey,
                    accessToken: accessToken
                )
            } catch let lookupError as GoogleDriveError where lookupError.id == .folderUnavailable {
                do {
                    metadata = try await api.createFolder(
                        id: folder.id,
                        name: folder.name,
                        parentID: folder.parentID,
                        pathHash: folder.pathHash,
                        operationID: journal.id,
                        resourceKeys: resourceKeys(destination: destination, journal: journal),
                        accessToken: accessToken
                    )
                } catch let error as GoogleDriveError where error.id == .ambiguousCommit {
                    metadata = try await api.metadata(id: folder.id, resourceKey: nil, accessToken: accessToken)
                }
            }
            guard metadata.id == folder.id,
                  metadata.name == folder.name,
                  metadata.parents == [folder.parentID],
                  metadata.mimeType == GoogleDriveFileMetadata.folderMIMEType,
                  !metadata.trashed else { throw GoogleDriveError(.remoteConflict) }
            try managedStore.upsert(GoogleDriveManagedObjectBinding(
                destinationID: destination.id,
                relativePathHash: folder.pathHash,
                objectID: folder.id,
                parentID: folder.parentID,
                expectedName: folder.name,
                mimeType: GoogleDriveFileMetadata.folderMIMEType,
                resourceKey: metadata.resourceKey,
                lastVerifiedVersion: metadata.version
            ))
        }

        var verified = journal.artifacts.filter { $0.phase == .verified && $0.finalFilename != nil }.count
        var skipped = journal.artifacts.filter { $0.phase == .verified && $0.finalFilename == nil }.count
        for index in journal.artifacts.indices.sorted(by: {
            journal.artifacts[$0].relativePath < journal.artifacts[$1].relativePath
        }) where journal.artifacts[index].phase != .verified {
            try Task.checkCancellation()
            do {
                if journal.artifacts[index].finalFilename == nil {
                    journal.artifacts[index].phase = .verified
                    skipped += 1
                    try await journalStore.save(journal)
                    continue
                }
                try await commitArtifact(
                    index: index,
                    journal: &journal,
                    destination: destination,
                    accessToken: accessToken
                )
                verified += 1
            } catch let error as GoogleDriveError {
                journal.terminalErrorID = verified > 0 ? .partialCompletion : error.id
                try? await journalStore.save(journal)
                return GoogleDriveRunResult(
                    operationID: journal.id,
                    verifiedArtifactCount: verified,
                    totalArtifactCount: journal.artifacts.count,
                    skippedArtifactCount: skipped,
                    errorID: verified > 0 ? .partialCompletion : error.id
                )
            }
        }

        journal.terminalErrorID = nil
        try await journalStore.save(journal)
        return GoogleDriveRunResult(
            operationID: journal.id,
            verifiedArtifactCount: verified,
            totalArtifactCount: journal.artifacts.count,
            skippedArtifactCount: skipped,
            errorID: nil
        )
    }

    private func planFolders(
        journal: inout GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
        accessToken: String
    ) async throws -> [FolderPlan] {
        let paths = Set(journal.artifacts.compactMap { artifact -> String? in
            let components = artifact.relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else { return nil }
            return components.dropLast().joined(separator: "/")
        })
        let everyPath = Set(paths.flatMap { path -> [String] in
            let parts = path.split(separator: "/").map(String.init)
            return parts.indices.map { parts[...$0].joined(separator: "/") }
        }).sorted {
            let lhsDepth = $0.split(separator: "/").count
            let rhsDepth = $1.split(separator: "/").count
            return lhsDepth == rhsDepth ? $0 < $1 : lhsDepth < rhsDepth
        }

        var plans: [FolderPlan] = []
        var idByPath: [String: String] = ["": destination.folderID]
        var ancestorIsNew: [String: Bool] = ["": false]
        for path in everyPath {
            let parts = path.split(separator: "/").map(String.init)
            let parentPath = parts.dropLast().joined(separator: "/")
            guard let parentID = idByPath[parentPath] else { throw GoogleDriveError(.remoteConflict) }
            let pathHash = GoogleDrivePath.hash(path)
            let name = parts.last!
            if ancestorIsNew[parentPath] == true {
                let id = try await reserveFolderID(pathHash: pathHash, journal: &journal, accessToken: accessToken)
                plans.append(FolderPlan(relativePath: path, pathHash: pathHash, id: id, parentID: parentID, name: name, resourceKey: nil, isNew: true))
                idByPath[path] = id
                ancestorIsNew[path] = true
                continue
            }

            if let binding = try managedStore.binding(destinationID: destination.id, relativePathHash: pathHash) {
                let metadata = try await api.metadata(id: binding.objectID, resourceKey: binding.resourceKey, accessToken: accessToken)
                try validateManaged(metadata, binding: binding, parentID: parentID)
                plans.append(FolderPlan(relativePath: path, pathHash: pathHash, id: metadata.id, parentID: parentID, name: name, resourceKey: metadata.resourceKey, isNew: false))
                idByPath[path] = metadata.id
                ancestorIsNew[path] = false
                continue
            }

            let matches = try await api.findManagedObjects(
                parentID: parentID,
                name: name,
                pathHash: pathHash,
                resourceKeys: resourceKeys(destination: destination, journal: journal),
                accessToken: accessToken
            )
            guard matches.count <= 1,
                  matches.allSatisfy({ $0.isOwned(relativePathHash: pathHash) }) else {
                throw GoogleDriveError(.remoteConflict)
            }
            if let metadata = matches.first {
                guard metadata.mimeType == GoogleDriveFileMetadata.folderMIMEType,
                      metadata.parents == [parentID], !metadata.trashed else {
                    throw GoogleDriveError(.remoteConflict)
                }
                try managedStore.upsert(GoogleDriveManagedObjectBinding(
                    destinationID: destination.id,
                    relativePathHash: pathHash,
                    objectID: metadata.id,
                    parentID: parentID,
                    expectedName: name,
                    mimeType: GoogleDriveFileMetadata.folderMIMEType,
                    resourceKey: metadata.resourceKey,
                    lastVerifiedVersion: metadata.version
                ))
                plans.append(FolderPlan(relativePath: path, pathHash: pathHash, id: metadata.id, parentID: parentID, name: name, resourceKey: metadata.resourceKey, isNew: false))
                idByPath[path] = metadata.id
                ancestorIsNew[path] = false
            } else {
                let id = try await reserveFolderID(pathHash: pathHash, journal: &journal, accessToken: accessToken)
                plans.append(FolderPlan(relativePath: path, pathHash: pathHash, id: id, parentID: parentID, name: name, resourceKey: nil, isNew: true))
                idByPath[path] = id
                ancestorIsNew[path] = true
            }
        }
        return plans
    }

    private func reserveFolderID(
        pathHash: String,
        journal: inout GoogleDriveOperationJournal,
        accessToken: String
    ) async throws -> String {
        if let id = journal.reservedFolderIDs[pathHash] { return id }
        guard let id = try await api.generateIDs(count: 1, accessToken: accessToken).first else {
            throw GoogleDriveError(.ambiguousCommit)
        }
        journal.reservedFolderIDs[pathHash] = id
        try await journalStore.save(journal)
        return id
    }

    private func prepareArtifacts(
        journal: inout GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
        folders: [FolderPlan],
        accessToken: String
    ) async throws {
        let folderIDs = Dictionary(uniqueKeysWithValues: folders.map { ($0.relativePath, $0.id) })
        let newFolderPaths = Set(folders.filter(\.isNew).map(\.relativePath))
        for index in journal.artifacts.indices where journal.artifacts[index].phase != .verified {
            var artifact = journal.artifacts[index]
            if artifact.finalFilename != nil, artifact.finalSHA256 != nil,
               artifact.finalByteCount != nil, artifact.objectID != nil, artifact.parentID != nil {
                continue
            }
            let components = artifact.relativePath.split(separator: "/").map(String.init)
            let name = components.last!
            let parentPath = components.dropLast().joined(separator: "/")
            let parentID = parentPath.isEmpty ? destination.folderID : folderIDs[parentPath]
            guard let parentID else { throw GoogleDriveError(.remoteConflict) }
            artifact.parentID = parentID

            var baseline: GoogleDriveFileMetadata?
            if artifact.objectID == nil, !newFolderPaths.contains(parentPath) {
                if let binding = try managedStore.binding(destinationID: destination.id, relativePathHash: artifact.relativePathHash) {
                    let metadata = try await api.metadata(id: binding.objectID, resourceKey: binding.resourceKey, accessToken: accessToken)
                    try validateManaged(metadata, binding: binding, parentID: parentID)
                    artifact.objectID = metadata.id
                    artifact.objectResourceKey = metadata.resourceKey
                    baseline = metadata
                } else {
                    let matches = try await api.findManagedObjects(
                        parentID: parentID,
                        name: name,
                        pathHash: artifact.relativePathHash,
                        resourceKeys: resourceKeys(destination: destination, journal: journal),
                        accessToken: accessToken
                    )
                    guard matches.count <= 1,
                          matches.allSatisfy({ $0.isOwned(relativePathHash: artifact.relativePathHash) }) else {
                        throw GoogleDriveError(.remoteConflict)
                    }
                    if let metadata = matches.first {
                        guard metadata.name == name, metadata.parents == [parentID], !metadata.trashed else {
                            throw GoogleDriveError(.remoteConflict)
                        }
                        artifact.objectID = metadata.id
                        artifact.objectResourceKey = metadata.resourceKey
                        baseline = metadata
                    }
                }
            } else if let objectID = artifact.objectID {
                baseline = try await api.metadata(id: objectID, resourceKey: artifact.objectResourceKey, accessToken: accessToken)
            }

            if artifact.objectID == nil {
                if artifact.writeIntent == .dailyNoteMerge && !artifact.createIfMissing {
                    artifact.finalFilename = nil
                    artifact.phase = .finalPersisted
                    journal.artifacts[index] = artifact
                    try await journalStore.save(journal)
                    continue
                }
                guard let generatedID = try await api.generateIDs(count: 1, accessToken: accessToken).first else {
                    throw GoogleDriveError(.ambiguousCommit)
                }
                artifact.objectID = generatedID
                artifact.phase = .identityReserved
                journal.artifacts[index] = artifact
                try await journalStore.save(journal)
            }

            let fragment = try await journalStore.readSpool(
                operationID: journal.id,
                filename: artifact.fragmentFilename,
                expectedSHA256: artifact.fragmentSHA256
            )
            let finalBytes: Data
            if artifact.writeIntent == .overwrite || baseline == nil {
                finalBytes = fragment
            } else {
                let baseline = baseline!
                let baselineBytes = try await api.download(
                    id: baseline.id,
                    resourceKey: baseline.resourceKey,
                    accessToken: accessToken
                )
                let afterDownload = try await api.metadata(
                    id: baseline.id,
                    resourceKey: baseline.resourceKey,
                    accessToken: accessToken
                )
                guard sameRevision(baseline, afterDownload),
                      baseline.size == nil || baseline.size == UInt64(baselineBytes.count) else {
                    throw GoogleDriveError(.remoteConflict)
                }
                let baselineFilename = "\(index)-baseline.bin"
                try await journalStore.writeSpool(operationID: journal.id, filename: baselineFilename, data: baselineBytes)
                artifact.baselineFilename = baselineFilename
                artifact.baselineMetadata = baseline
                artifact.phase = .baselinePersisted
                journal.artifacts[index] = artifact
                try await journalStore.save(journal)
                finalBytes = try GoogleDriveFinalByteMerger.merge(
                    baseline: baselineBytes,
                    fragment: fragment,
                    intent: artifact.writeIntent
                )
            }
            let finalFilename = "\(index)-final.bin"
            let finalSHA256 = GoogleDriveDigest.sha256(finalBytes)
            try await journalStore.writeSpool(operationID: journal.id, filename: finalFilename, data: finalBytes)
            artifact.finalFilename = finalFilename
            artifact.finalByteCount = UInt64(finalBytes.count)
            artifact.finalSHA256 = finalSHA256
            artifact.baselineMetadata = artifact.baselineMetadata ?? baseline
            artifact.phase = artifact.objectID == baseline?.id ? .finalPersisted : .identityReserved
            journal.artifacts[index] = artifact
            try await journalStore.save(journal)
        }
    }

    private func preflightAll(journal: GoogleDriveOperationJournal, accessToken: String) async throws {
        for artifact in journal.artifacts {
            guard let baseline = artifact.baselineMetadata else { continue }
            let current = try await api.metadata(
                id: baseline.id,
                resourceKey: artifact.objectResourceKey,
                accessToken: accessToken
            )
            let expectedName = artifact.relativePath.split(separator: "/").last.map(String.init)
            let expectedParents = artifact.parentID.map { [$0] } ?? []
            guard sameRevision(baseline, current),
                  current.name == expectedName,
                  current.parents == expectedParents else {
                throw GoogleDriveError(.remoteConflict)
            }
        }
    }

    private func commitArtifact(
        index: Int,
        journal: inout GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
        accessToken: String
    ) async throws {
        var artifact = journal.artifacts[index]
        guard let finalFilename = artifact.finalFilename,
              let finalSHA256 = artifact.finalSHA256,
              let finalByteCount = artifact.finalByteCount,
              artifact.parentID != nil,
              let objectID = artifact.objectID else {
            throw GoogleDriveError(.remoteConflict)
        }
        let finalBytes = try await journalStore.readSpool(
            operationID: journal.id,
            filename: finalFilename,
            expectedSHA256: finalSHA256
        )
        let sessionURL: URL
        if let existing = artifact.uploadSessionURL {
            do {
                switch try await api.uploadStatus(sessionURL: existing, totalByteCount: finalByteCount, accessToken: accessToken) {
                case .completed(let metadata):
                    try await verifyAndBind(metadata: metadata, artifact: artifact, destination: destination, finalBytes: finalBytes, accessToken: accessToken)
                    artifact.phase = .verified
                    journal.artifacts[index] = artifact
                    try await journalStore.save(journal)
                    return
                case .incomplete(let acknowledged):
                    artifact.acknowledgedByteOffset = acknowledged
                    sessionURL = existing
                }
            } catch {
                // The final chunk may have committed even when the session probe expired or its
                // response was lost. Reconcile the exact reserved/mapped object against intended
                // bytes before comparing it with the old baseline or starting another session.
                if let metadata = try? await api.metadata(
                    id: objectID,
                    resourceKey: artifact.objectResourceKey,
                    accessToken: accessToken
                ), (try? await verifyAndBind(
                    metadata: metadata,
                    artifact: artifact,
                    destination: destination,
                    finalBytes: finalBytes,
                    accessToken: accessToken
                )) != nil {
                    artifact.phase = .verified
                    journal.artifacts[index] = artifact
                    try await journalStore.save(journal)
                    return
                }
                artifact.uploadSessionURL = nil
                artifact.acknowledgedByteOffset = 0
                journal.artifacts[index] = artifact
                try await journalStore.save(journal)
                try await recheckBaseline(artifact, accessToken: accessToken)
                sessionURL = try await startSession(artifact: artifact, finalByteCount: finalByteCount, finalSHA256: finalSHA256, accessToken: accessToken, destination: destination, journal: journal)
            }
        } else {
            // Recheck this exact baseline immediately before initializing its update. The earlier
            // bundle-wide preflight is not sufficient when prior artifacts/folders took time.
            try await recheckBaseline(artifact, accessToken: accessToken)
            sessionURL = try await startSession(artifact: artifact, finalByteCount: finalByteCount, finalSHA256: finalSHA256, accessToken: accessToken, destination: destination, journal: journal)
        }
        artifact.uploadSessionURL = sessionURL
        artifact.phase = .uploadSessionStarted
        journal.artifacts[index] = artifact
        try await journalStore.save(journal)

        let offset = artifact.acknowledgedByteOffset
        guard offset < finalByteCount, offset <= UInt64(finalBytes.count) else {
            throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
        }
        let remainingBytes = Data(finalBytes.dropFirst(Int(offset)))
        let response: GoogleDriveUploadResponse
        do {
            response = try await api.upload(
                sessionURL: sessionURL,
                data: remainingBytes,
                offset: offset,
                totalByteCount: finalByteCount,
                accessToken: accessToken
            )
        } catch let error as GoogleDriveError where error.id == .ambiguousCommit {
            let metadata = try await api.metadata(id: objectID, resourceKey: artifact.objectResourceKey, accessToken: accessToken)
            try await verifyAndBind(metadata: metadata, artifact: artifact, destination: destination, finalBytes: finalBytes, accessToken: accessToken)
            artifact.phase = .verified
            journal.artifacts[index] = artifact
            try await journalStore.save(journal)
            return
        }
        guard case .completed(let metadata) = response else {
            throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
        }
        artifact.phase = .uploaded
        journal.artifacts[index] = artifact
        try await journalStore.save(journal)
        try await verifyAndBind(metadata: metadata, artifact: artifact, destination: destination, finalBytes: finalBytes, accessToken: accessToken)
        artifact.phase = .verified
        journal.artifacts[index] = artifact
        try await journalStore.save(journal)
    }

    private func startSession(
        artifact: GoogleDriveJournalArtifact,
        finalByteCount: UInt64,
        finalSHA256: String,
        accessToken: String,
        destination: GoogleDriveDestination,
        journal: GoogleDriveOperationJournal
    ) async throws -> URL {
        guard let objectID = artifact.objectID, let parentID = artifact.parentID else {
            throw GoogleDriveError(.remoteConflict)
        }
        let keys = resourceKeys(destination: destination, journal: journal)
        if artifact.baselineMetadata != nil {
            return try await api.startResumableUpdate(
                id: objectID,
                mediaType: artifact.mediaType,
                byteCount: finalByteCount,
                sha256: finalSHA256,
                pathHash: artifact.relativePathHash,
                operationID: journal.id,
                resourceKeys: keys,
                accessToken: accessToken
            )
        }
        let name = artifact.relativePath.split(separator: "/").last.map(String.init) ?? artifact.relativePath
        return try await api.startResumableCreate(
            id: objectID,
            name: name,
            parentID: parentID,
            mediaType: artifact.mediaType,
            byteCount: finalByteCount,
            sha256: finalSHA256,
            pathHash: artifact.relativePathHash,
            operationID: journal.id,
            resourceKeys: keys,
            accessToken: accessToken
        )
    }

    private func recheckBaseline(
        _ artifact: GoogleDriveJournalArtifact,
        accessToken: String
    ) async throws {
        guard let baseline = artifact.baselineMetadata else { return }
        let current = try await api.metadata(
            id: baseline.id,
            resourceKey: artifact.objectResourceKey,
            accessToken: accessToken
        )
        guard sameRevision(baseline, current) else { throw GoogleDriveError(.remoteConflict) }
    }

    private func verifyAndBind(
        metadata responseMetadata: GoogleDriveFileMetadata,
        artifact: GoogleDriveJournalArtifact,
        destination: GoogleDriveDestination,
        finalBytes: Data,
        accessToken: String
    ) async throws {
        guard responseMetadata.id == artifact.objectID, let objectID = artifact.objectID else {
            throw GoogleDriveError(.remoteConflict)
        }
        // Never treat response metadata as postflight authority. Fetch the exact reserved/mapped ID
        // after the upload response and verify its current checksum or bytes.
        let metadata = try await api.metadata(
            id: objectID,
            resourceKey: artifact.objectResourceKey ?? responseMetadata.resourceKey,
            accessToken: accessToken
        )
        let expectedName = artifact.relativePath.split(separator: "/").last.map(String.init)
        let expectedParents = artifact.parentID.map { [$0] } ?? []
        guard metadata.id == artifact.objectID,
              metadata.name == expectedName,
              metadata.parents == expectedParents,
              metadata.mimeType == artifact.mediaType,
              !metadata.trashed,
              metadata.size == nil || metadata.size == UInt64(finalBytes.count) else {
            throw GoogleDriveError(.remoteConflict)
        }
        let expectedSHA = GoogleDriveDigest.sha256(finalBytes)
        if let remoteSHA = metadata.sha256Checksum {
            guard remoteSHA.lowercased() == expectedSHA else { throw GoogleDriveError(.checksumMismatch) }
        } else {
            let downloaded = try await api.download(
                id: metadata.id,
                resourceKey: metadata.resourceKey,
                accessToken: accessToken
            )
            guard downloaded == finalBytes else { throw GoogleDriveError(.checksumMismatch) }
        }
        try managedStore.upsert(GoogleDriveManagedObjectBinding(
            destinationID: destination.id,
            relativePathHash: artifact.relativePathHash,
            objectID: metadata.id,
            parentID: artifact.parentID!,
            expectedName: metadata.name,
            mimeType: metadata.mimeType,
            resourceKey: metadata.resourceKey,
            lastVerifiedVersion: metadata.version,
            byteCount: UInt64(finalBytes.count),
            checksum: metadata.strongestChecksum ?? expectedSHA
        ))
    }

    private func validateManaged(
        _ metadata: GoogleDriveFileMetadata,
        binding: GoogleDriveManagedObjectBinding,
        parentID: String
    ) throws {
        guard metadata.id == binding.objectID,
              metadata.name == binding.expectedName,
              metadata.mimeType == binding.mimeType,
              metadata.parents == [parentID],
              !metadata.trashed else { throw GoogleDriveError(.remoteConflict) }
    }

    private func sameRevision(_ lhs: GoogleDriveFileMetadata, _ rhs: GoogleDriveFileMetadata) -> Bool {
        lhs.id == rhs.id && lhs.version == rhs.version && lhs.size == rhs.size &&
            lhs.md5Checksum == rhs.md5Checksum && lhs.sha1Checksum == rhs.sha1Checksum &&
            lhs.sha256Checksum == rhs.sha256Checksum && lhs.parents == rhs.parents &&
            lhs.name == rhs.name && lhs.mimeType == rhs.mimeType && lhs.trashed == rhs.trashed
    }

    private func resourceKeys(
        destination: GoogleDriveDestination,
        journal: GoogleDriveOperationJournal
    ) -> [String: String] {
        var keys: [String: String] = [:]
        if let key = destination.resourceKey { keys[destination.folderID] = key }
        for artifact in journal.artifacts {
            if let id = artifact.objectID, let key = artifact.objectResourceKey { keys[id] = key }
        }
        return keys
    }
}

nonisolated enum GoogleDriveFinalByteMerger {
    static func merge(
        baseline: Data,
        fragment: Data,
        intent: GoogleDriveArtifactWriteIntent
    ) throws -> Data {
        switch intent {
        case .overwrite:
            return fragment
        case .append:
            guard String(data: baseline, encoding: .utf8) != nil,
                  String(data: fragment, encoding: .utf8) != nil else {
                throw GoogleDriveError(.remoteConflict)
            }
            let separator = Data("\n\n".utf8)
            let block = separator + fragment
            if baseline == fragment || baseline.suffix(block.count) == block { return baseline }
            return baseline + block
        case .markdownUpdate, .dailyNoteMerge:
            guard let existing = String(data: baseline, encoding: .utf8),
                  let generated = String(data: fragment, encoding: .utf8) else {
                throw GoogleDriveError(.remoteConflict)
            }
            let outcome = intent == .dailyNoteMerge
                ? MarkdownMerger.mergePreservingPreambleOutcome(existing: existing, new: generated)
                : MarkdownMerger.mergeOutcome(existing: existing, new: generated)
            switch outcome {
            case .merged(let content): return Data(content.utf8)
            case .rejected: throw GoogleDriveError(.remoteConflict)
            }
        }
    }
}
