import Foundation
import HealthMdConnectionCore

/// Health-free checkpoint for one captured source day in a generated-file direct export.
struct IPhoneDirectCapturedDay: Codable, Equatable {
    let sourceDate: Date
    let sourceDateIdentifier: String
    let isRequestedDate: Bool
    let relativePath: String
    let succeeded: Bool
    /// Nil identifies a checkpoint written before granular-capture history was tracked.
    let includedGranularData: Bool?
    let sampleCount: Int
    let recordCount: Int
    let externalRecordCount: Int
    let partialFailureCount: Int
    let integrityWarningCount: Int
    let hadWarnings: Bool
    /// Warnings that reduce capture completeness. Nil identifies a checkpoint
    /// written before the informational/degrading split was tracked; consumers
    /// fall back to `partialFailureCount` so legacy checkpoints keep the
    /// behavior they were written with.
    let degradingFailureCount: Int?
    /// Same contract as `hadWarnings`, excluding informational omissions (for
    /// example a WorkoutKit plan this device cannot decode) that do not reduce
    /// the export below full success. Nil falls back to `hadWarnings`.
    let hadDegradingWarnings: Bool?
    /// Informational-only warnings surfaced so Export History can show them as
    /// export notes without degrading the entry's status. Nil or empty means
    /// the day had none (or predates note tracking).
    let informationalFailures: [ExportPartialFailure]?
    let failureReason: ExportFailureReason?
    /// False only for checkpoints written before these health-free facts were persisted.
    let historyFactsRecorded: Bool

    init(
        sourceDate: Date,
        sourceDateIdentifier: String,
        isRequestedDate: Bool,
        relativePath: String,
        succeeded: Bool,
        includedGranularData: Bool? = nil,
        sampleCount: Int = 0,
        recordCount: Int = 0,
        externalRecordCount: Int = 0,
        partialFailureCount: Int = 0,
        integrityWarningCount: Int = 0,
        hadWarnings: Bool = false,
        degradingFailureCount: Int? = nil,
        hadDegradingWarnings: Bool? = nil,
        informationalFailures: [ExportPartialFailure]? = nil,
        failureReason: ExportFailureReason? = nil,
        historyFactsRecorded: Bool = false
    ) {
        self.sourceDate = sourceDate
        self.sourceDateIdentifier = sourceDateIdentifier
        self.isRequestedDate = isRequestedDate
        self.relativePath = relativePath
        self.succeeded = succeeded
        self.includedGranularData = includedGranularData
        self.sampleCount = max(sampleCount, 0)
        self.recordCount = max(recordCount, 0)
        self.externalRecordCount = max(externalRecordCount, 0)
        self.partialFailureCount = max(partialFailureCount, 0)
        self.integrityWarningCount = max(integrityWarningCount, 0)
        self.hadWarnings = hadWarnings
        self.degradingFailureCount = degradingFailureCount.map { max($0, 0) }
        self.hadDegradingWarnings = hadDegradingWarnings
        self.informationalFailures = informationalFailures
        self.failureReason = failureReason
        self.historyFactsRecorded = historyFactsRecorded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceDate = try container.decode(Date.self, forKey: .sourceDate)
        sourceDateIdentifier = try container.decode(String.self, forKey: .sourceDateIdentifier)
        isRequestedDate = try container.decode(Bool.self, forKey: .isRequestedDate)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        succeeded = try container.decode(Bool.self, forKey: .succeeded)
        includedGranularData = try container.decodeIfPresent(Bool.self, forKey: .includedGranularData)
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        recordCount = try container.decodeIfPresent(Int.self, forKey: .recordCount) ?? 0
        externalRecordCount = try container.decodeIfPresent(Int.self, forKey: .externalRecordCount) ?? 0
        partialFailureCount = try container.decodeIfPresent(Int.self, forKey: .partialFailureCount) ?? 0
        integrityWarningCount = try container.decodeIfPresent(Int.self, forKey: .integrityWarningCount) ?? 0
        hadWarnings = try container.decodeIfPresent(Bool.self, forKey: .hadWarnings) ?? false
        degradingFailureCount = try container.decodeIfPresent(Int.self, forKey: .degradingFailureCount)
        hadDegradingWarnings = try container.decodeIfPresent(Bool.self, forKey: .hadDegradingWarnings)
        informationalFailures = try container.decodeIfPresent([ExportPartialFailure].self, forKey: .informationalFailures)
        failureReason = try container.decodeIfPresent(ExportFailureReason.self, forKey: .failureReason)
        historyFactsRecorded = try container.decodeIfPresent(Bool.self, forKey: .historyFactsRecorded) ?? false
    }

    /// Degrading warning count, falling back to the total for checkpoints
    /// written before the split was tracked.
    var resolvedDegradingFailureCount: Int {
        degradingFailureCount ?? partialFailureCount
    }

    /// Whether the day carries warnings that reduce capture completeness,
    /// falling back to `hadWarnings` for legacy checkpoints.
    var resolvedHadDegradingWarnings: Bool {
        hadDegradingWarnings ?? hadWarnings
    }
}

/// Health-free generated-file descriptor persisted before bounded direct transfer.
struct IPhoneDirectGeneratedFile: Codable, Equatable {
    let manifest: DirectExportFileManifest
    let relativePath: String
}

/// Durable state for generated-file direct exports only. Raw and canonical direct journals retain
/// their independent models. V1 is fully legacy, v2 may carry an export-engine pin, v3 may
/// carry a direct-protocol pin, v4 stores captured days as bounded application-item streams, v5
/// freezes original range authority, and v6 persists terminal derived-output reconciliation.
struct IPhoneDirectFileJournal: Codable {
    static let legacyVersion = 1
    static let exportEnginePinVersion = 2
    static let directProtocolPinVersion = 3
    static let fileBackedCaptureVersion = 4
    static let immutableRangeRequestVersion = 5
    static let derivedOutputReconciliationVersion = 6
    static let currentVersion = derivedOutputReconciliationVersion

    var checkpoint = AppleExportJournalCheckpoint()

    private enum CodingKeys: String, CodingKey {
        case version, request, accepted, session, settingsSnapshot
        case appleExportEnginePin, appleDirectProtocolPin, healthSubfolder, requestedDates, originalRequestedDates
        case originalCalendarTimeZoneIdentifier, transferDates, capturedDays, generatedFiles, partitions
        case committedPartitionCount, committedBytes, derivedOutputPartialFailures, terminalNoDataDateIdentifiers, generationCompleted
        case state, completionRecorded, updatedAt
    }

    let version: Int
    let request: DirectExportRequest
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    let settingsSnapshot: ExportSettingsSnapshot
    let appleExportEnginePin: AppleExportEnginePin?
    let appleDirectProtocolPin: AppleDirectProtocolPin?
    let healthSubfolder: String
    let requestedDates: [Date]
    /// Original requested owner dates remain stable while capture resumes residual transfer work.
    let originalRequestedDates: [Date]
    /// Original timezone authority used to regenerate/overwrite the same range path.
    let originalCalendarTimeZoneIdentifier: String?
    let transferDates: [Date]
    var capturedDays: [IPhoneDirectCapturedDay]
    var generatedFiles: [IPhoneDirectGeneratedFile]
    var partitions: [DirectTransferPartition]
    var committedPartitionCount: Int
    var committedBytes: Int64
    var derivedOutputPartialFailures: [ExportPartialFailure]
    var terminalNoDataDateIdentifiers: [String]
    var generationCompleted: Bool
    var state: String
    var completionRecorded: Bool
    var updatedAt: Date

    static func isSupportedVersion(_ version: Int) -> Bool {
        version >= legacyVersion && version <= currentVersion
    }

    init(
        version: Int = currentVersion,
        request: DirectExportRequest,
        accepted: DirectExportAccepted,
        session: DirectTransferSession,
        settingsSnapshot: ExportSettingsSnapshot,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        appleDirectProtocolPin: AppleDirectProtocolPin? = nil,
        healthSubfolder: String,
        requestedDates: [Date],
        originalRequestedDates: [Date]? = nil,
        originalCalendarTimeZoneIdentifier: String? = nil,
        transferDates: [Date],
        capturedDays: [IPhoneDirectCapturedDay],
        generatedFiles: [IPhoneDirectGeneratedFile],
        partitions: [DirectTransferPartition],
        committedPartitionCount: Int,
        committedBytes: Int64,
        derivedOutputPartialFailures: [ExportPartialFailure] = [],
        terminalNoDataDateIdentifiers: [String] = [],
        generationCompleted: Bool = false,
        state: String,
        completionRecorded: Bool,
        updatedAt: Date
    ) {
        self.version = version
        self.request = request
        self.accepted = accepted
        self.session = session
        self.settingsSnapshot = settingsSnapshot
        self.appleExportEnginePin = version >= Self.exportEnginePinVersion
            ? (appleExportEnginePin ?? settingsSnapshot.appleExportEnginePin)
            : nil
        self.appleDirectProtocolPin = version >= Self.directProtocolPinVersion
            ? appleDirectProtocolPin
            : nil
        self.healthSubfolder = healthSubfolder
        self.requestedDates = requestedDates
        self.originalRequestedDates = originalRequestedDates ?? requestedDates
        self.originalCalendarTimeZoneIdentifier = originalCalendarTimeZoneIdentifier
            ?? settingsSnapshot.calendarTimeZoneIdentifier
            ?? accepted.sourceTimeZoneIdentifier
        self.transferDates = transferDates
        self.capturedDays = capturedDays
        self.generatedFiles = generatedFiles
        self.partitions = partitions
        self.committedPartitionCount = committedPartitionCount
        self.committedBytes = committedBytes
        self.derivedOutputPartialFailures = derivedOutputPartialFailures
        self.terminalNoDataDateIdentifiers = terminalNoDataDateIdentifiers
        self.generationCompleted = generationCompleted
        self.state = state
        self.completionRecorded = completionRecorded
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        request = try container.decode(DirectExportRequest.self, forKey: .request)
        accepted = try container.decode(DirectExportAccepted.self, forKey: .accepted)
        session = try container.decode(DirectTransferSession.self, forKey: .session)
        settingsSnapshot = try container.decode(ExportSettingsSnapshot.self, forKey: .settingsSnapshot)
        // A v1 checkpoint remains legacy even if an unexpected future writer added this key.
        appleExportEnginePin = version >= Self.exportEnginePinVersion
            ? (try container.decodeIfPresent(AppleExportEnginePin.self, forKey: .appleExportEnginePin)
                ?? settingsSnapshot.appleExportEnginePin)
            : nil
        appleDirectProtocolPin = version >= Self.directProtocolPinVersion
            ? try container.decodeIfPresent(
                AppleDirectProtocolPin.self,
                forKey: .appleDirectProtocolPin
            )
            : nil
        healthSubfolder = try container.decode(String.self, forKey: .healthSubfolder)
        requestedDates = try container.decode([Date].self, forKey: .requestedDates)
        originalRequestedDates = try container.decodeIfPresent(
            [Date].self,
            forKey: .originalRequestedDates
        ) ?? requestedDates
        originalCalendarTimeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .originalCalendarTimeZoneIdentifier
        ) ?? settingsSnapshot.calendarTimeZoneIdentifier ?? accepted.sourceTimeZoneIdentifier
        transferDates = try container.decode([Date].self, forKey: .transferDates)
        capturedDays = try container.decode([IPhoneDirectCapturedDay].self, forKey: .capturedDays)
        generatedFiles = try container.decode([IPhoneDirectGeneratedFile].self, forKey: .generatedFiles)
        partitions = try container.decode([DirectTransferPartition].self, forKey: .partitions)
        committedPartitionCount = try container.decode(Int.self, forKey: .committedPartitionCount)
        committedBytes = try container.decode(Int64.self, forKey: .committedBytes)
        derivedOutputPartialFailures = try container.decodeIfPresent(
            [ExportPartialFailure].self,
            forKey: .derivedOutputPartialFailures
        ) ?? []
        terminalNoDataDateIdentifiers = try container.decodeIfPresent(
            [String].self,
            forKey: .terminalNoDataDateIdentifiers
        ) ?? []
        generationCompleted = try container.decodeIfPresent(
            Bool.self,
            forKey: .generationCompleted
        ) ?? false
        state = try container.decode(String.self, forKey: .state)
        completionRecorded = try container.decodeIfPresent(Bool.self, forKey: .completionRecorded) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

/// A value-owned read image and private direct-job generation. Neither enters journal JSON.
/// A retained journal cannot silently become a fresh operation or a replacement generation.
nonisolated struct AppleExportJournalCheckpoint {
    var bytes: Data?
    var generation: UUID?
    var journalURL: URL?
    var publicationLockURL: URL?

    /// A bounded continuation check: checkpoint progress may advance within this generation.
    /// Never creates a missing job directory or refreshes this value's ownership.
    func validateGeneration(fileManager: FileManager = .default) throws {
        guard bytes != nil, let generation, let journalURL, let publicationLockURL else {
            throw POSIXError(.EAGAIN)
        }
        let transaction = try AtomicFileWriter.beginPublicationTransaction(at: publicationLockURL)
        defer { transaction.close() }
        guard (try? fileManager.attributesOfItem(atPath: journalURL.path)[.type] as? FileAttributeType) == .typeRegular,
              try Self.readGeneration(for: journalURL, fileManager: fileManager) == generation else {
            throw POSIXError(.EAGAIN)
        }
    }

    enum ContinuationError: Error, Equatable { case superseded }

    @MainActor
    func receiveWhileOwned<Result>(operation: @MainActor () async throws -> Result) async throws -> Result {
        do { try validateGeneration() } catch { throw ContinuationError.superseded }
        let result: Result
        do { result = try await operation() }
        catch {
            let operationError = error
            do { try validateGeneration() } catch { throw ContinuationError.superseded }
            throw operationError
        }
        do { try validateGeneration() } catch { throw ContinuationError.superseded }
        return result
    }

    fileprivate static func generationURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(".journal-generation")
    }

    fileprivate static func readGeneration(for destination: URL, fileManager: FileManager) throws -> UUID? {
        let url = generationURL(for: destination)
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fileManager.attributesOfItem(atPath: url.path) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain, failure.code == NSFileReadNoSuchFileError { return nil }
            throw POSIXError(.EAGAIN)
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.uint64Value == 36 else { throw POSIXError(.EAGAIN) }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let read = try handle.read(upToCount: 37) else { throw POSIXError(.EAGAIN) }
            data = read
        } catch { throw POSIXError(.EAGAIN) }
        guard data.count == 36, let text = String(data: data, encoding: .utf8),
              let generation = UUID(uuidString: text), generation.uuidString.lowercased() == text else {
            throw POSIXError(.EAGAIN)
        }
        return generation
    }

    fileprivate static func createGeneration(
        for destination: URL, lockURL: URL, durabilityRoot: URL,
        fileManager: FileManager, attributes: [FileAttributeKey: Any]?,
        directorySync: (URL) throws -> Void
    ) throws -> UUID {
        let generation = UUID()
        try AtomicFileWriter.writeData(Data(generation.uuidString.lowercased().utf8),
            to: generationURL(for: destination), fileManager: fileManager,
            attributes: attributes ?? [.posixPermissions: 0o600], commitPolicy: .requireAbsent,
            transactionLockURL: lockURL, directoryDurability: .required(upTo: durabilityRoot),
            directorySync: directorySync)
        return generation
    }

    mutating func publish(
        _ data: Data, to destination: URL,
        freshAdmission: Bool,
        lockURL: URL,
        durabilityRoot: URL,
        fileManager: FileManager = .default,
        attributes: [FileAttributeKey: Any]? = nil,
        directorySync: (URL) throws -> Void = AtomicFileWriter.synchronizeDirectory
    ) throws {
        let transaction = try AtomicFileWriter.beginPublicationTransaction(at: lockURL)
        defer { transaction.close() }
        let policy: AtomicFileWriter.CommitPolicy
        let acceptedGeneration: UUID
        if freshAdmission {
            do {
                _ = try fileManager.attributesOfItem(atPath: destination.path)
                throw POSIXError(.EEXIST)
            } catch {
                let failure = error as NSError
                guard failure.domain == NSCocoaErrorDomain, failure.code == NSFileReadNoSuchFileError else { throw error }
            }
            // A partial admission retains its sidecar; it cannot silently become fresh work.
            acceptedGeneration = try Self.createGeneration(for: destination, lockURL: lockURL,
                durabilityRoot: durabilityRoot, fileManager: fileManager,
                attributes: attributes, directorySync: directorySync)
            policy = .requireAbsent
        } else {
            guard let bytes, let generation,
                  try Self.readGeneration(for: destination, fileManager: fileManager) == generation else {
                throw POSIXError(.EAGAIN)
            }
            acceptedGeneration = generation
            policy = .replaceIfUnchanged(bytes)
        }
        try AtomicFileWriter.writeData(data, to: destination, fileManager: fileManager,
            attributes: attributes, commitPolicy: policy, transactionLockURL: lockURL,
            directoryDurability: .required(upTo: durabilityRoot), directorySync: directorySync)
        bytes = data
        generation = acceptedGeneration
        journalURL = destination
        publicationLockURL = lockURL
    }
}

enum AppleExportJournalRecovery {
    /// Bind decoded bytes and auxiliary ownership while holding one publication transaction.
    /// Legacy journals receive a sidecar without rewriting their JSON.
    static func loadOwned<Journal: Decodable>(
        at url: URL, lockURL: URL, durabilityRoot: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder? = nil,
        attributes: [FileAttributeKey: Any]? = nil,
        directorySync: (URL) throws -> Void = AtomicFileWriter.synchronizeDirectory,
        isSupported: (Journal) -> Bool
    ) throws -> (journal: Journal, checkpoint: AppleExportJournalCheckpoint)? {
        let transaction = try AtomicFileWriter.beginPublicationTransaction(at: lockURL)
        defer { transaction.close() }
        var bytes: Data?
        guard let journal: Journal = try load(at: url, fileManager: fileManager,
            decoder: decoder, directoryDurability: .required(upTo: durabilityRoot),
            directorySync: directorySync, didLoadBytes: { bytes = $0 }, isSupported: isSupported),
              let bytes else { return nil }
        do {
            let generation = try AppleExportJournalCheckpoint.readGeneration(for: url, fileManager: fileManager)
                ?? AppleExportJournalCheckpoint.createGeneration(for: url, lockURL: lockURL,
                    durabilityRoot: durabilityRoot, fileManager: fileManager,
                    attributes: attributes, directorySync: directorySync)
            return (journal, AppleExportJournalCheckpoint(bytes: bytes, generation: generation,
                journalURL: url, publicationLockURL: lockURL))
        } catch {
            throw RecoveryError.unreadableJournal
        }
    }

    private struct DirectExpiryProbe: Decodable {
        struct Request: Decodable { let createdAt: Date }
        let request: Request
    }

    /// Raw and generated-file jobs share this root and its persistent publication inode.
    static func cleanupExpiredDirectJobs(
        at root: URL, lockURL: URL, durabilityRoot: URL,
        now: Date, lifetime: TimeInterval,
        fileManager: FileManager = .default,
        directorySync: (URL) throws -> Void = AtomicFileWriter.synchronizeDirectory
    ) throws -> [UUID] {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let lockPath = lockURL.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let durabilityPath = durabilityRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard root.isFileURL, lockURL.isFileURL, durabilityRoot.isFileURL,
              rootPath.starts(with: durabilityPath), lockPath.starts(with: durabilityPath),
              !lockPath.starts(with: rootPath), lifetime.isFinite, lifetime >= 0 else {
            throw POSIXError(.EINVAL)
        }
        let transaction = try AtomicFileWriter.beginPublicationTransaction(at: lockURL)
        defer { transaction.close() }
        // Re-establish any preceding ambiguous removal before inspecting retained authority.
        try AtomicFileWriter.synchronizeDirectories(from: root,
            durability: .required(upTo: durabilityRoot), directorySync: directorySync)
        let directories = try fileManager.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var removed: [UUID] = []
        for directory in directories {
            guard let jobID = UUID(uuidString: directory.lastPathComponent),
                  try fileManager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else { continue }
            let candidates = [directory.appendingPathComponent("journal.json"),
                directory.appendingPathComponent("files/journal.json")]
            let journalURL = candidates.first { fileManager.fileExists(atPath: $0.path) }
            let probe = journalURL.flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? decoder.decode(DirectExpiryProbe.self, from: $0) }
            let createdAt: Date?
            if let probe { createdAt = probe.request.createdAt }
            else {
                let values = try directory.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                createdAt = values.creationDate ?? values.contentModificationDate
            }
            guard createdAt.map({ $0.addingTimeInterval(lifetime) <= now }) ?? false else { continue }
            try fileManager.removeItem(at: directory)
            try AtomicFileWriter.synchronizeDirectories(from: root,
                durability: .required(upTo: durabilityRoot), directorySync: directorySync)
            removed.append(jobID)
        }
        return removed
    }

    enum RecoveryError: LocalizedError {
        case unreadableJournal
        var errorDescription: String? { "The saved direct export journal is unavailable. Its files were retained." }
    }

    static func load<Journal: Decodable>(
        at url: URL, fileManager manager: FileManager = .default,
        decoder suppliedDecoder: JSONDecoder? = nil,
        directoryDurability: AtomicFileWriter.DirectoryDurability = .bestEffort,
        directorySync: (URL) throws -> Void = AtomicFileWriter.synchronizeDirectory,
        didLoadBytes: (Data) -> Void = { _ in },
        isSupported: (Journal) -> Bool
    ) throws -> Journal? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch {
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain, failure.code == NSFileReadNoSuchFileError else {
                throw RecoveryError.unreadableJournal
            }
            // A missing journal beside retained spool files is incomplete work,
            // not permission to capture a replacement using today's settings.
            do {
                guard try manager.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).isEmpty else {
                    throw RecoveryError.unreadableJournal
                }
            } catch {
                let directoryFailure = error as NSError
                guard directoryFailure.domain == NSCocoaErrorDomain,
                      directoryFailure.code == NSFileReadNoSuchFileError else {
                    throw RecoveryError.unreadableJournal
                }
            }
            return nil
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RecoveryError.unreadableJournal
        }
        let decoder = suppliedDecoder ?? JSONDecoder()
        if suppliedDecoder == nil { decoder.dateDecodingStrategy = .iso8601 }
        do {
            let bytes = try Data(contentsOf: url)
            let journal = try decoder.decode(Journal.self, from: bytes)
            guard isSupported(journal) else { throw RecoveryError.unreadableJournal }
            try AtomicFileWriter.synchronizeDirectories(
                from: url.deletingLastPathComponent(), durability: directoryDurability, directorySync: directorySync)
            didLoadBytes(bytes)
            return journal
        } catch {
            // Never expose a path or decoder context containing saved values.
            throw RecoveryError.unreadableJournal
        }
    }
}
