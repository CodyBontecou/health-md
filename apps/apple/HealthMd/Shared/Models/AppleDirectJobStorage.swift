import Foundation
import HealthMdConnectionCore
import CryptoKit
import Darwin

/// Private storage identities; these never enter a journal or protocol payload.
nonisolated enum AppleExportJobNamespace: CaseIterable, Hashable, Sendable {
    case historical
    case wakeDate

    @MainActor
    static func resolve(_ snapshot: ExportSettingsSnapshot) throws -> Self {
        let context = snapshot.sleepCaptureContext
        if context?.sleepDayAttribution == .morningEnds
            || context?.exportProfileID == "apple-v11" || snapshot.appleExportEnginePin?.isWakeDate == true {
            let validated = try snapshot.validatedSleepCaptureContext()
            guard validated.sleepDayAttribution == .morningEnds else { throw POSIXError(.EAGAIN) }
            return .wakeDate
        }
        return .historical
    }
}

nonisolated enum AppleDirectJobKind: Equatable, Sendable {
    case raw
    case files
}

@MainActor
struct AppleDirectJobStorage {
    let support: URL
    let fileManager: FileManager

    func namespace(for snapshot: ExportSettingsSnapshot) throws -> AppleExportJobNamespace {
        try AppleExportJobNamespace.resolve(snapshot)
    }

    func root(_ namespace: AppleExportJobNamespace) -> URL {
        support.appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent(namespace == .historical ? "DirectCLIOutbound" : "DirectCLIOutboundSleepAttribution", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    func lock(_ namespace: AppleExportJobNamespace) -> URL {
        root(namespace).deletingLastPathComponent().appendingPathComponent(".v1.journal.lock")
    }

    func job(_ jobID: UUID, namespace: AppleExportJobNamespace, kind: AppleDirectJobKind) -> URL {
        let directory = root(namespace).appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        return kind == .files ? directory.appendingPathComponent("files", isDirectory: true) : directory
    }

    /// Includes partial/unknown job directories. Ambiguity is never fresh work.
    func existingNamespace(jobID: UUID) throws -> AppleExportJobNamespace? {
        var result: AppleExportJobNamespace?
        for namespace in AppleExportJobNamespace.allCases {
            if try AppleExportJournalRecovery.hasExistingJobDirectory(
                at: job(jobID, namespace: namespace, kind: .raw), fileManager: fileManager) {
                guard result == nil else { throw AppleExportJournalRecovery.RecoveryError.unreadableJournal }
                result = namespace
            }
        }
        return result
    }

    func existingDirectory(jobID: UUID, kind: AppleDirectJobKind) throws -> (AppleExportJobNamespace, URL)? {
        guard let namespace = try existingNamespace(jobID: jobID) else { return nil }
        let directory = job(jobID, namespace: namespace, kind: kind)
        guard try AppleExportJournalRecovery.hasExistingJobDirectory(at: directory, fileManager: fileManager) else { return nil }
        return (namespace, directory)
    }

    /// One recovery path for the iPhone producer and native storage qualification.
    func loadGeneratedJournal(jobID: UUID) throws -> IPhoneDirectFileJournal? {
        guard let (namespace, directory) = try existingDirectory(jobID: jobID, kind: .files) else { return nil }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        let saved: (journal: IPhoneDirectFileJournal, checkpoint: AppleExportJournalCheckpoint)? =
            try AppleExportJournalRecovery.loadOwned(
                at: directory.appendingPathComponent("journal.json"),
                lockURL: lock(namespace), durabilityRoot: support, fileManager: fileManager,
                decoder: decoder, attributes: attributes, legacyCompletionIdentity: { $0.request.jobID },
                isSupported: { journal in
                    guard journal.request.jobID == jobID,
                          IPhoneDirectFileJournal.isSupportedVersion(journal.version),
                          (try? self.namespace(for: journal.settingsSnapshot)) == namespace else { return false }
                    if namespace == .wakeDate {
                        guard journal.appleExportEnginePin == journal.settingsSnapshot.appleExportEnginePin else { return false }
                        do { try self.validateGeneratedArtifacts(journal, in: directory) }
                        catch { return false }
                    }
                    return true
                })
        guard var saved else { return nil }
        saved.journal.checkpoint = saved.checkpoint
        return saved.journal
    }

    /// Validate retained successor bytes under the caller's journal ownership transaction.
    /// Historical callers keep their existing admission; no journal grammar is upgraded here.
    func validateGeneratedArtifacts(_ journal: IPhoneDirectFileJournal, in directory: URL) throws {
        let files = journal.generatedFiles
        let partitions = journal.partitions
        guard journal.generationCompleted else {
            guard files.isEmpty, partitions.isEmpty, journal.committedPartitionCount == 0,
                  journal.committedBytes == 0 else { throw POSIXError(.EINVAL) }
            return
        }
        guard journal.session.partitionTargetBytes >= DirectTransferLimits.minimumPartitionBytes,
              journal.session.partitionTargetBytes <= DirectTransferLimits.maximumPartitionBytes,
              Set(files.map(\.manifest.fileID)).count == files.count,
              Set(files.map(\.relativePath)).count == files.count,
              Set(partitions.map(\.transferID)).count == partitions.count,
              journal.committedPartitionCount >= 0, journal.committedPartitionCount <= partitions.count else {
            throw POSIXError(.EINVAL)
        }
        let pendingPartitionBuild = partitions.isEmpty && files.contains { $0.manifest.byteCount > 0 }
        if pendingPartitionBuild {
            guard journal.state == "preparing", journal.committedPartitionCount == 0,
                  journal.committedBytes == 0 else { throw POSIXError(.EINVAL) }
        }
        let fileIDs = Set(files.map { $0.manifest.fileID.uuidString.lowercased() })
        var previous: String?
        var committedBytes: Int64 = 0
        for (index, partition) in partitions.enumerated() {
            guard partition.index == index, partition.previousSHA256 == previous,
                  partition.byteCount > 0, partition.byteCount <= journal.session.partitionTargetBytes,
                  partition.chunkCount == Int((partition.byteCount + Int64(DirectTransferLimits.chunkBytes) - 1)
                    / Int64(DirectTransferLimits.chunkBytes)),
                  let segment = partition.itemSegment, fileIDs.contains(segment.itemID),
                  partition.sourceDates == [segment.itemID] else { throw POSIXError(.EINVAL) }
            previous = partition.sha256
            if index < journal.committedPartitionCount {
                let sum = committedBytes.addingReportingOverflow(partition.byteCount)
                guard !sum.overflow else { throw POSIXError(.EINVAL) }
                committedBytes = sum.partialValue
            }
        }
        guard committedBytes == journal.committedBytes else { throw POSIXError(.EINVAL) }
        let staging = directory.appendingPathComponent("generated", isDirectory: true)
        for file in files {
            let manifest = file.manifest
            let components = file.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard manifest.jobID == journal.request.jobID, manifest.byteCount >= 0,
                  manifest.relativePath == file.relativePath, !file.relativePath.isEmpty,
                  file.relativePath.utf8.count <= 4096, !file.relativePath.contains("\0"),
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw POSIXError(.EINVAL) }
            var url = staging
            guard try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw POSIXError(.EINVAL)
            }
            for (index, component) in components.enumerated() {
                url.appendPathComponent(String(component))
                let kind = try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
                guard kind == (index == components.count - 1 ? .typeRegular : .typeDirectory) else { throw POSIXError(.EINVAL) }
            }
            let itemID = manifest.fileID.uuidString.lowercased()
            let segments = partitions.filter { $0.itemSegment?.itemID == itemID }
            var offset: Int64 = 0
            for part in segments {
                guard let segment = part.itemSegment, segment.offset == offset,
                      segment.itemByteCount == manifest.byteCount,
                      part.byteCount <= manifest.byteCount - offset else { throw POSIXError(.EINVAL) }
                offset += part.byteCount
                guard segment.isFinalSegment == (offset == manifest.byteCount) else { throw POSIXError(.EINVAL) }
            }
            guard pendingPartitionBuild || offset == manifest.byteCount else { throw POSIXError(.EINVAL) }
            try validateDigests(at: url, manifest: manifest, partitions: pendingPartitionBuild ? nil : segments)
        }
    }

    private func validateDigests(at url: URL, manifest: DirectExportFileManifest,
                                 partitions: [DirectTransferPartition]?) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              status.st_size == manifest.byteCount else { throw POSIXError(.EINVAL) }
        var whole = SHA256()
        func digest(_ byteCount: Int64) throws -> String {
            var part = SHA256()
            var remaining = byteCount
            while remaining > 0 {
                guard let data = try input.read(upToCount: Int(min(128 * 1024, remaining))), !data.isEmpty else {
                    throw POSIXError(.EIO)
                }
                whole.update(data: data)
                part.update(data: data)
                remaining -= Int64(data.count)
            }
            return part.finalize().map { String(format: "%02x", $0) }.joined()
        }
        if let partitions {
            for partition in partitions {
                guard try digest(partition.byteCount) == partition.sha256 else { throw POSIXError(.EINVAL) }
            }
        } else {
            _ = try digest(manifest.byteCount)
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty,
              whole.finalize().map({ String(format: "%02x", $0) }).joined() == manifest.sha256 else {
            throw POSIXError(.EINVAL)
        }
    }

    /// Serializes fresh admission across namespaces. It is outside historical purge roots.
    func beginAdmission() throws -> AtomicFileWriter.PublicationLease {
        let directory = support.appendingPathComponent("Health.md", isDirectory: true)
        try createProtectedDirectory(directory)
        return try AtomicFileWriter.beginPublicationTransaction(at: directory.appendingPathComponent(".direct-job-namespaces.lock"))
    }

    func prepareDirectory(jobID: UUID, kind: AppleDirectJobKind, snapshot: ExportSettingsSnapshot) throws -> (AppleExportJobNamespace, URL) {
        let selected = try namespace(for: snapshot)
        if let existing = try existingNamespace(jobID: jobID), existing != selected { throw POSIXError(.EAGAIN) }
        let directory = job(jobID, namespace: selected, kind: kind)
        try createProtectedDirectory(root(selected).deletingLastPathComponent())
        try createProtectedDirectory(root(selected))
        try createProtectedDirectory(job(jobID, namespace: selected, kind: .raw))
        if kind == .files { try createProtectedDirectory(directory) }
        return (selected, directory)
    }

    /// Continuations retain their accepted location; discovery cannot redirect an old receipt.
    func boundDirectory(jobID: UUID, kind: AppleDirectJobKind, snapshot: ExportSettingsSnapshot,
                        checkpoint: AppleExportJournalCheckpoint) throws -> (AppleExportJobNamespace, URL) {
        let selected = try namespace(for: snapshot)
        guard try existingNamespace(jobID: jobID) == selected,
              let saved = checkpoint.journalURL, let savedLock = checkpoint.publicationLockURL else { throw POSIXError(.EAGAIN) }
        let directory = job(jobID, namespace: selected, kind: kind)
        guard saved.standardizedFileURL.resolvingSymlinksInPath()
                == directory.appendingPathComponent("journal.json").standardizedFileURL.resolvingSymlinksInPath(),
              savedLock.standardizedFileURL.resolvingSymlinksInPath()
                == lock(selected).standardizedFileURL.resolvingSymlinksInPath() else { throw POSIXError(.EAGAIN) }
        try checkpoint.validateGeneration(fileManager: fileManager)
        return (selected, directory)
    }

    /// Only complete, unambiguous successor jobs can expire. Unknown bytes are retained.
    func cleanupExpiredWakeDateJobs(
        now: Date, lifetime: TimeInterval,
        directorySync: (URL) throws -> Void = AtomicFileWriter.synchronizeDirectory,
        validatedCreationDate: (URL, UUID, AppleDirectJobKind) throws -> Date
    ) throws -> [UUID] {
        let directory = root(.wakeDate)
        guard now.timeIntervalSince1970.isFinite, lifetime.isFinite, lifetime >= 0,
              support.isFileURL,
              directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
                .starts(with: support.standardizedFileURL.resolvingSymlinksInPath().pathComponents) else {
            throw POSIXError(.EINVAL)
        }
        guard try AppleExportJournalRecovery.hasExistingJobDirectory(at: directory, fileManager: fileManager) else { return [] }
        let transaction = try AtomicFileWriter.beginPublicationTransaction(at: lock(.wakeDate))
        defer { transaction.close() }
        // Retry any ambiguous preceding removal before examining another job.
        try AtomicFileWriter.synchronizeDirectories(from: directory,
            durability: .required(upTo: support), directorySync: directorySync)
        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var removed: [UUID] = []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  id.uuidString.lowercased() == entry.lastPathComponent else { continue }
            do {
                guard try existingNamespace(jobID: id) == .wakeDate else { continue }
                let contents = try fileManager.contentsOfDirectory(atPath: entry.path)
                var candidates: [(AppleDirectJobKind, URL)] = []
                if contents.contains("journal.json") {
                    candidates.append((.raw, entry.appendingPathComponent("journal.json")))
                } else if contents != ["files"] {
                    // A raw spool/sidecar without its journal is incomplete work.
                    continue
                }
                if contents.contains("files") {
                    let files = job(id, namespace: .wakeDate, kind: .files)
                    guard try AppleExportJournalRecovery.hasExistingJobDirectory(at: files, fileManager: fileManager) else { continue }
                    candidates.append((.files, files.appendingPathComponent("journal.json")))
                }
                guard !candidates.isEmpty else { continue }
                var allExpired = true
                for (kind, journal) in candidates {
                    guard try fileManager.attributesOfItem(atPath: journal.path)[.type] as? FileAttributeType == .typeRegular else {
                        throw AppleExportJournalRecovery.RecoveryError.unreadableJournal
                    }
                    try AppleExportJournalRecovery.validateExistingOwnership(at: journal, fileManager: fileManager)
                    let createdAt = try validatedCreationDate(journal, id, kind)
                    guard createdAt.timeIntervalSince1970.isFinite else { throw POSIXError(.EINVAL) }
                    if createdAt.addingTimeInterval(lifetime) > now { allExpired = false }
                }
                guard allExpired else { continue }
            } catch {
                // No migration, timestamp fallback or deletion for unknown authority.
                continue
            }
            try fileManager.removeItem(at: entry)
            try AtomicFileWriter.synchronizeDirectories(from: directory,
                durability: .required(upTo: support), directorySync: directorySync)
            removed.append(id)
        }
        return removed
    }

    private func createProtectedDirectory(_ directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try? mutable.setResourceValues(values)
    }
}
