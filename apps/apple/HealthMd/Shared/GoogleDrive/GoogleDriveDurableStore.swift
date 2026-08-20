import Darwin
import Foundation

nonisolated enum GoogleDriveProtectedFileStore {
    static func defaultRoot() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { throw GoogleDriveError(.folderUnavailable) }
        return applicationSupport
            .appendingPathComponent("GoogleDriveExport", isDirectory: true)
    }

    static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
        try synchronizeDirectory(url)
    }

    static func write(_ data: Data, to url: URL) throws {
        try prepareDirectory(url.deletingLastPathComponent())
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: attributes
        ) else { throw GoogleDriveError(.folderUnavailable) }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            try synchronizeDirectory(url.deletingLastPathComponent())
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw GoogleDriveError(.folderUnavailable) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw GoogleDriveError(.folderUnavailable) }
    }
}

@MainActor
final class GoogleDriveManagedObjectStore {
    private let fileURL: URL
    private var loadError: GoogleDriveError?
    private(set) var bindings: [GoogleDriveManagedObjectBinding] = []

    init(rootURL: URL? = nil) {
        do {
            let root = try rootURL ?? GoogleDriveProtectedFileStore.defaultRoot()
            fileURL = root.appendingPathComponent("managed-objects.json")
        } catch {
            fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("unavailable-managed-objects.json")
            loadError = GoogleDriveError(.folderUnavailable)
            return
        }
        load()
    }

    func binding(destinationID: UUID, relativePathHash: String) throws -> GoogleDriveManagedObjectBinding? {
        if let loadError { throw loadError }
        let matches = bindings.filter {
            $0.destinationID == destinationID && $0.relativePathHash == relativePathHash
        }
        guard matches.count <= 1 else { throw GoogleDriveError(.remoteConflict) }
        return matches.first
    }

    func upsert(_ binding: GoogleDriveManagedObjectBinding) throws {
        if let loadError { throw loadError }
        bindings.removeAll {
            $0.destinationID == binding.destinationID && $0.relativePathHash == binding.relativePathHash
        }
        bindings.append(binding)
        bindings.sort {
            if $0.destinationID == $1.destinationID { return $0.relativePathHash < $1.relativePathHash }
            return $0.destinationID.uuidString < $1.destinationID.uuidString
        }
        try persist()
    }

    func removeAll(destinationID: UUID) throws {
        if let loadError { throw loadError }
        bindings.removeAll { $0.destinationID == destinationID }
        try persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            bindings = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let values = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                throw GoogleDriveError(.remoteConflict)
            }
            let decoded = try values.map { value -> GoogleDriveManagedObjectBinding in
                guard JSONSerialization.isValidJSONObject(value) else {
                    throw GoogleDriveError(.remoteConflict)
                }
                let recordData = try JSONSerialization.data(withJSONObject: value)
                let binding = try JSONDecoder().decode(GoogleDriveManagedObjectBinding.self, from: recordData)
                guard binding.version == GoogleDriveManagedObjectBinding.currentVersion else {
                    throw GoogleDriveError(.remoteConflict)
                }
                return binding
            }
            let keys = decoded.map { "\($0.destinationID.uuidString):\($0.relativePathHash)" }
            guard Set(keys).count == keys.count else { throw GoogleDriveError(.remoteConflict) }
            bindings = decoded
        } catch let error as GoogleDriveError {
            loadError = error
            bindings = []
        } catch {
            loadError = GoogleDriveError(.remoteConflict)
            bindings = []
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let objects = try bindings.map { binding -> Any in
            try JSONSerialization.jsonObject(with: encoder.encode(binding))
        }
        try GoogleDriveProtectedFileStore.write(
            JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys]),
            to: fileURL
        )
    }
}

nonisolated enum GoogleDriveJournalArtifactPhase: String, Codable, Equatable, Sendable {
    case captured
    case baselinePersisted = "baseline_persisted"
    case finalPersisted = "final_persisted"
    case identityReserved = "identity_reserved"
    case uploadSessionStarted = "upload_session_started"
    case uploaded
    case verified
}

nonisolated struct GoogleDriveJournalArtifact: Codable, Equatable, Sendable {
    let artifactID: String
    let relativePath: String
    let relativePathHash: String
    let mediaType: String
    let writeIntent: GoogleDriveArtifactWriteIntent
    let createIfMissing: Bool
    let fragmentFilename: String
    let fragmentByteCount: UInt64
    let fragmentSHA256: String
    var baselineFilename: String?
    var baselineMetadata: GoogleDriveFileMetadata?
    var finalFilename: String?
    var finalByteCount: UInt64?
    var finalSHA256: String?
    var parentID: String?
    var objectID: String?
    var objectResourceKey: String?
    var uploadSessionURL: URL?
    var acknowledgedByteOffset: UInt64
    var phase: GoogleDriveJournalArtifactPhase
}

nonisolated struct GoogleDriveOperationJournal: Codable, Equatable, Identifiable, Sendable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let profileID: UUID?
    let sourceDates: [Date]
    let destinationSnapshot: GoogleDriveDestinationSnapshot
    let bundleDigest: String
    let rendererIdentity: String
    let createdAt: Date
    var artifacts: [GoogleDriveJournalArtifact]
    /// Relative folder-path hash to generated Drive ID, persisted before create.
    var reservedFolderIDs: [String: String]
    var historyAcknowledged: Bool
    var terminalErrorID: GoogleDriveErrorID?

    init(
        id: UUID,
        profileID: UUID?,
        sourceDates: [Date],
        destinationSnapshot: GoogleDriveDestinationSnapshot,
        bundleDigest: String,
        rendererIdentity: String,
        createdAt: Date,
        artifacts: [GoogleDriveJournalArtifact]
    ) {
        version = Self.currentVersion
        self.id = id
        self.profileID = profileID
        self.sourceDates = sourceDates
        self.destinationSnapshot = destinationSnapshot
        self.bundleDigest = bundleDigest
        self.rendererIdentity = rendererIdentity
        self.createdAt = createdAt
        self.artifacts = artifacts
        reservedFolderIDs = [:]
        historyAcknowledged = false
        terminalErrorID = nil
    }
}

/// Protected, no-backup journal and byte spool. Every checkpoint is an atomic replacement plus
/// file and parent-directory synchronization.
actor GoogleDriveJournalStore {
    private let rootURL: URL
    private let journalsURL: URL
    private let spoolURL: URL
    private let now: @Sendable () -> Date
    private let retention: TimeInterval
    private let unresolvedRetention: TimeInterval
    private let abandonedURL: URL

    init(
        rootURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        retention: TimeInterval = 14 * 24 * 60 * 60,
        unresolvedRetention: TimeInterval = 90 * 24 * 60 * 60
    ) throws {
        let root = try rootURL ?? GoogleDriveProtectedFileStore.defaultRoot()
        self.rootURL = root
        journalsURL = root.appendingPathComponent("journals", isDirectory: true)
        spoolURL = root.appendingPathComponent("spool", isDirectory: true)
        abandonedURL = root.appendingPathComponent("abandoned-operations.json")
        self.now = now
        self.retention = retention
        self.unresolvedRetention = unresolvedRetention
        try GoogleDriveProtectedFileStore.prepareDirectory(journalsURL)
        try GoogleDriveProtectedFileStore.prepareDirectory(spoolURL)
    }

    func create(
        bundle: GoogleDriveGeneratedArtifactBundle,
        destination: GoogleDriveDestination
    ) throws -> GoogleDriveOperationJournal {
        let operationSpool = spoolDirectory(operationID: bundle.operationID)
        try GoogleDriveProtectedFileStore.prepareDirectory(operationSpool)
        var journalArtifacts: [GoogleDriveJournalArtifact] = []
        for (index, artifact) in bundle.artifacts.enumerated() {
            let fragmentFilename = "\(index)-fragment.bin"
            try GoogleDriveProtectedFileStore.write(
                artifact.fragmentBytes,
                to: operationSpool.appendingPathComponent(fragmentFilename)
            )
            journalArtifacts.append(GoogleDriveJournalArtifact(
                artifactID: artifact.id,
                relativePath: artifact.relativePath,
                relativePathHash: GoogleDrivePath.hash(artifact.relativePath),
                mediaType: artifact.mediaType,
                writeIntent: artifact.writeIntent,
                createIfMissing: artifact.createIfMissing,
                fragmentFilename: fragmentFilename,
                fragmentByteCount: artifact.byteCount,
                fragmentSHA256: artifact.sha256,
                baselineFilename: nil,
                baselineMetadata: nil,
                finalFilename: nil,
                finalByteCount: nil,
                finalSHA256: nil,
                parentID: nil,
                objectID: nil,
                objectResourceKey: nil,
                uploadSessionURL: nil,
                acknowledgedByteOffset: 0,
                phase: .captured
            ))
        }
        let journal = GoogleDriveOperationJournal(
            id: bundle.operationID,
            profileID: bundle.profileID,
            sourceDates: bundle.sourceDates,
            destinationSnapshot: GoogleDriveDestinationSnapshot(destination: destination),
            bundleDigest: bundle.digest,
            rendererIdentity: bundle.rendererIdentity,
            createdAt: now(),
            artifacts: journalArtifacts
        )
        try save(journal)
        return journal
    }

    func save(_ journal: GoogleDriveOperationJournal) throws {
        guard journal.version == GoogleDriveOperationJournal.currentVersion else {
            throw GoogleDriveError(.remoteConflict)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try GoogleDriveProtectedFileStore.write(
            encoder.encode(journal),
            to: journalURL(operationID: journal.id)
        )
    }

    func contains(operationID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: journalURL(operationID: operationID).path)
    }

    func isAbandoned(operationID: UUID) -> Bool {
        guard let data = try? Data(contentsOf: abandonedURL),
              let notices = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return notices.contains {
            ($0["operation_id"] as? String) == operationID.uuidString.lowercased()
        }
    }

    func load(operationID: UUID) throws -> GoogleDriveOperationJournal {
        do {
            let journal = try JSONDecoder().decode(
                GoogleDriveOperationJournal.self,
                from: Data(contentsOf: journalURL(operationID: operationID))
            )
            guard journal.version == GoogleDriveOperationJournal.currentVersion else {
                throw GoogleDriveError(.remoteConflict)
            }
            return journal
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            throw GoogleDriveError(.remoteConflict)
        }
    }

    func loadRecoverable() -> [GoogleDriveOperationJournal] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: journalsURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let journal = try? JSONDecoder().decode(GoogleDriveOperationJournal.self, from: data),
                  journal.version == GoogleDriveOperationJournal.currentVersion,
                  !journal.historyAcknowledged else { return nil }
            return journal
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func readSpool(operationID: UUID, filename: String, expectedSHA256: String) throws -> Data {
        guard !filename.contains("/"), !filename.contains("\\"), filename != ".", filename != ".." else {
            throw GoogleDriveError(.remoteConflict)
        }
        let data = try Data(contentsOf: spoolDirectory(operationID: operationID).appendingPathComponent(filename))
        guard GoogleDriveDigest.sha256(data) == expectedSHA256 else {
            throw GoogleDriveError(.checksumMismatch)
        }
        return data
    }

    func writeSpool(operationID: UUID, filename: String, data: Data) throws {
        guard !filename.contains("/"), !filename.contains("\\") else {
            throw GoogleDriveError(.remoteConflict)
        }
        try GoogleDriveProtectedFileStore.write(
            data,
            to: spoolDirectory(operationID: operationID).appendingPathComponent(filename)
        )
    }

    func markAcknowledged(operationID: UUID) throws {
        var journal = try load(operationID: operationID)
        journal.historyAcknowledged = true
        try save(journal)
    }

    func remove(operationID: UUID) throws {
        try? FileManager.default.removeItem(at: journalURL(operationID: operationID))
        try? FileManager.default.removeItem(at: spoolDirectory(operationID: operationID))
        try GoogleDriveProtectedFileStore.synchronizeDirectory(journalsURL)
        try GoogleDriveProtectedFileStore.synchronizeDirectory(spoolURL)
    }

    /// Disconnect is fail-closed while any operation still needs this credential for exact-ID
    /// reconciliation. Once every operation is history-acknowledged, protected journals/spools are
    /// removed together with the local authority.
    func cleanupForDisconnect(destinationID: UUID) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: journalsURL,
            includingPropertiesForKeys: nil
        )
        let journals = try urls.map { url -> GoogleDriveOperationJournal in
            do {
                let journal = try JSONDecoder().decode(
                    GoogleDriveOperationJournal.self,
                    from: Data(contentsOf: url)
                )
                guard journal.version == GoogleDriveOperationJournal.currentVersion else {
                    throw GoogleDriveError(.remoteConflict)
                }
                return journal
            } catch let error as GoogleDriveError {
                throw error
            } catch {
                // A torn journal may belong to this authority; never erase credentials while its
                // destination cannot be proven.
                throw GoogleDriveError(.remoteConflict)
            }
        }.filter {
            $0.destinationSnapshot.destinationID == destinationID
        }
        guard journals.allSatisfy(\.historyAcknowledged) else {
            throw GoogleDriveError(.partialCompletion)
        }
        for journal in journals {
            try remove(operationID: journal.id)
        }
    }

    func prune() throws {
        let current = now()
        let cutoff = current.addingTimeInterval(-retention)
        let unresolvedCutoff = current.addingTimeInterval(-unresolvedRetention)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: journalsURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let journal = try? JSONDecoder().decode(GoogleDriveOperationJournal.self, from: data),
                  journal.version == GoogleDriveOperationJournal.currentVersion else { continue }
            if journal.historyAcknowledged, journal.createdAt < cutoff {
                try remove(operationID: journal.id)
            } else if !journal.historyAcknowledged, journal.createdAt < unresolvedCutoff {
                // Bound protected health-byte retention while preserving a durable, privacy-safe
                // notice that an unresolved operation was abandoned rather than silently erased.
                try appendAbandonedNotice(journal)
                try remove(operationID: journal.id)
            }
        }
    }

    private func appendAbandonedNotice(_ journal: GoogleDriveOperationJournal) throws {
        var notices = (try? JSONSerialization.jsonObject(with: Data(contentsOf: abandonedURL)) as? [[String: Any]]) ?? []
        notices.removeAll { ($0["operation_id"] as? String) == journal.id.uuidString.lowercased() }
        notices.append([
            "operation_id": journal.id.uuidString.lowercased(),
            "destination_id": journal.destinationSnapshot.destinationID.uuidString.lowercased(),
            "created_at": journal.createdAt.timeIntervalSince1970,
            "terminal_error": journal.terminalErrorID?.rawValue ?? GoogleDriveErrorID.ambiguousCommit.rawValue,
            "abandoned_at": now().timeIntervalSince1970
        ])
        if notices.count > 256 { notices.removeFirst(notices.count - 256) }
        try GoogleDriveProtectedFileStore.write(
            JSONSerialization.data(withJSONObject: notices, options: [.sortedKeys]),
            to: abandonedURL
        )
    }

    private func journalURL(operationID: UUID) -> URL {
        journalsURL.appendingPathComponent("\(operationID.uuidString.lowercased()).json")
    }

    private func spoolDirectory(operationID: UUID) -> URL {
        spoolURL.appendingPathComponent(operationID.uuidString.lowercased(), isDirectory: true)
    }
}
