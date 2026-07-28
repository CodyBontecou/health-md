import Foundation
import HealthMdConnectionCore

public enum DirectClientStorageError: LocalizedError, Equatable {
    case invalidIdentity
    case invalidJob
    case identityWriteFailed
    case jobNotFound
    case jobExpired

    public var errorDescription: String? {
        switch self {
        case .invalidIdentity: return "The direct CLI installation identity is invalid."
        case .invalidJob: return "The direct CLI durable job record is invalid."
        case .identityWriteFailed: return "The direct CLI installation identity could not be persisted."
        case .jobNotFound: return "The direct CLI durable job does not exist."
        case .jobExpired: return "The direct CLI durable job expired after seven days."
        }
    }
}

public struct DirectClientIdentity: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let installationID: UUID
    public let createdAt: Date

    public init(
        version: Int = currentVersion,
        installationID: UUID,
        createdAt: Date
    ) throws {
        guard version == Self.currentVersion else {
            throw DirectClientStorageError.invalidIdentity
        }
        self.version = version
        self.installationID = installationID
        self.createdAt = createdAt
    }
}

public struct DirectClientStorageLayout: Sendable {
    public let rootURL: URL

    public init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = applicationSupport
                .appendingPathComponent("Health.md", isDirectory: true)
                .appendingPathComponent("CLI", isDirectory: true)
                .appendingPathComponent("Direct", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        }
    }

    public var identityURL: URL { rootURL.appendingPathComponent("identity.json") }
    public var jobsURL: URL { rootURL.appendingPathComponent("jobs", isDirectory: true) }
    public var corpusSessionsURL: URL { rootURL.appendingPathComponent("corpus-sessions", isDirectory: true) }
    public var responseSpoolsURL: URL { rootURL.appendingPathComponent("response-spools", isDirectory: true) }

    public func prepare(fileManager: FileManager = .default) throws {
        for directory in [rootURL, jobsURL, corpusSessionsURL, responseSpoolsURL] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(resourceValues)
        }
    }
}

public struct DirectClientIdentityStore {
    public let layout: DirectClientStorageLayout
    private let fileManager: FileManager

    public init(layout: DirectClientStorageLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func loadOrCreate(now: Date = Date()) throws -> DirectClientIdentity {
        try layout.prepare(fileManager: fileManager)
        if fileManager.fileExists(atPath: layout.identityURL.path) {
            let data = try Data(contentsOf: layout.identityURL)
            let identity = try JSONDecoder.healthMdDirect.decode(DirectClientIdentity.self, from: data)
            guard identity.version == DirectClientIdentity.currentVersion else {
                throw DirectClientStorageError.invalidIdentity
            }
            return identity
        }
        let identity = try DirectClientIdentity(installationID: UUID(), createdAt: now)
        let data = try JSONEncoder.healthMdDirect.encode(identity)
        try atomicRestrictedWrite(data, to: layout.identityURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: layout.identityURL.path) else {
            throw DirectClientStorageError.identityWriteFailed
        }
        return identity
    }
}

public enum DirectJobState: String, Codable, Equatable, Sendable {
    case queued
    case connecting
    case sent
    case accepted
    case preparing
    case transferring
    case paused
    case awaitingPeerAcknowledgement = "awaiting_peer_acknowledgement"
    case cancellationPending = "cancellation_pending"
    case completed
    case failed
    case cancelled

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

public struct DirectResponseArtifact: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public let dateRangeStart: String
    public let dateRangeEnd: String
    public let totalDays: Int

    public init(
        relativePath: String,
        byteCount: Int64,
        sha256: String,
        dateRangeStart: String,
        dateRangeEnd: String,
        totalDays: Int
    ) throws {
        guard !relativePath.isEmpty,
              !relativePath.contains("/"),
              byteCount >= 0,
              sha256.isHealthMdSHA256,
              totalDays >= 0 else {
            throw DirectClientStorageError.invalidJob
        }
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.totalDays = totalDays
    }
}

public struct DirectJobRecord: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let request: DirectExportRequest
    public let createdAt: Date
    public let expiresAt: Date
    public var updatedAt: Date
    public var state: DirectJobState
    public var peerBinding: DirectPeerBinding?
    public var sessionID: UUID?
    public var requestFingerprint: DirectRequestFingerprint?
    public var committedPartitions: Int
    public var committedBytes: Int64
    public var processedDays: Int
    public var totalDays: Int?
    public var message: String?
    public var failure: DirectExportFailure?
    public var responseArtifact: DirectResponseArtifact?

    public init(
        version: Int = currentVersion,
        request: DirectExportRequest,
        createdAt: Date,
        expiresAt: Date? = nil,
        updatedAt: Date? = nil,
        state: DirectJobState = .queued,
        peerBinding: DirectPeerBinding? = nil,
        sessionID: UUID? = nil,
        requestFingerprint: DirectRequestFingerprint? = nil,
        committedPartitions: Int = 0,
        committedBytes: Int64 = 0,
        processedDays: Int = 0,
        totalDays: Int? = nil,
        message: String? = nil,
        failure: DirectExportFailure? = nil,
        responseArtifact: DirectResponseArtifact? = nil
    ) throws {
        let fixedExpiry = createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime)
        guard version == Self.currentVersion,
              request.jobID != sessionID,
              committedPartitions >= 0,
              committedBytes >= 0,
              processedDays >= 0,
              totalDays.map({ $0 >= processedDays }) ?? true,
              (expiresAt ?? fixedExpiry) == fixedExpiry else {
            throw DirectClientStorageError.invalidJob
        }
        self.version = version
        self.request = request
        self.createdAt = createdAt
        self.expiresAt = fixedExpiry
        self.updatedAt = updatedAt ?? createdAt
        self.state = state
        self.peerBinding = peerBinding
        self.sessionID = sessionID
        self.requestFingerprint = requestFingerprint
        self.committedPartitions = committedPartitions
        self.committedBytes = committedBytes
        self.processedDays = processedDays
        self.totalDays = totalDays
        self.message = message
        self.failure = failure
        self.responseArtifact = responseArtifact
    }
}

public actor DirectJobStore {
    public let layout: DirectClientStorageLayout
    private let fileManager: FileManager

    public init(layout: DirectClientStorageLayout, fileManager: FileManager = .default) throws {
        self.layout = layout
        self.fileManager = fileManager
        try layout.prepare(fileManager: fileManager)
    }

    public func save(_ record: DirectJobRecord) throws {
        try validate(record)
        let directory = jobDirectory(record.request.jobID)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try atomicRestrictedWrite(
            JSONEncoder.healthMdDirect.encode(record),
            to: directory.appendingPathComponent("record.json"),
            fileManager: fileManager
        )
    }

    public func load(jobID: UUID) throws -> DirectJobRecord {
        let url = jobDirectory(jobID).appendingPathComponent("record.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw DirectClientStorageError.jobNotFound
        }
        let record = try loadUnchecked(jobID: jobID)
        guard record.expiresAt > Date() else {
            cleanup(jobID: jobID)
            throw DirectClientStorageError.jobExpired
        }
        return record
    }

    public func allRecords() throws -> [DirectJobRecord] {
        guard fileManager.fileExists(atPath: layout.jobsURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: layout.jobsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).compactMap { directory in
            guard let jobID = UUID(uuidString: directory.lastPathComponent) else { return nil }
            return try? loadUnchecked(jobID: jobID)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(jobID: UUID) throws {
        let directory = jobDirectory(jobID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func requestCancellation(jobID: UUID) throws {
        _ = try load(jobID: jobID)
        try atomicRestrictedWrite(
            Data("cancel\n".utf8),
            to: cancellationRequestURL(jobID),
            fileManager: fileManager
        )
    }

    public func cancellationRequested(jobID: UUID) -> Bool {
        fileManager.fileExists(atPath: cancellationRequestURL(jobID).path)
    }

    public func clearCancellationRequest(jobID: UUID) {
        try? fileManager.removeItem(at: cancellationRequestURL(jobID))
    }

    @discardableResult
    public func removeExpired(now: Date = Date()) throws -> [UUID] {
        let expired = try allRecords().filter { $0.expiresAt <= now }
        for record in expired {
            cleanup(jobID: record.request.jobID)
        }
        return expired.map(\.request.jobID)
    }

    private func loadUnchecked(jobID: UUID) throws -> DirectJobRecord {
        let url = jobDirectory(jobID).appendingPathComponent("record.json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw DirectClientStorageError.jobNotFound
        }
        let record = try JSONDecoder.healthMdDirect.decode(
            DirectJobRecord.self,
            from: Data(contentsOf: url)
        )
        try validate(record)
        guard record.request.jobID == jobID else {
            throw DirectClientStorageError.invalidJob
        }
        return record
    }

    private func cleanup(jobID: UUID) {
        let paths = [
            jobDirectory(jobID),
            layout.corpusSessionsURL.appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true),
            layout.responseSpoolsURL.appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        ]
        for path in paths where fileManager.fileExists(atPath: path.path) {
            try? fileManager.removeItem(at: path)
        }
    }

    private func jobDirectory(_ jobID: UUID) -> URL {
        layout.jobsURL.appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
    }

    private func cancellationRequestURL(_ jobID: UUID) -> URL {
        jobDirectory(jobID).appendingPathComponent("cancellation-requested")
    }

    private func validate(_ record: DirectJobRecord) throws {
        guard record.version == DirectJobRecord.currentVersion,
              record.expiresAt == record.createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime),
              record.committedPartitions >= 0,
              record.committedBytes >= 0,
              record.processedDays >= 0,
              record.totalDays.map({ $0 >= record.processedDays }) ?? true else {
            throw DirectClientStorageError.invalidJob
        }
    }
}

public enum DirectClientTrustStore {
    public static func make() -> ManualIPTrustStore {
        ManualIPTrustStore(
            service: "com.codybontecou.obsidianhealth.direct-cli-trust",
            account: "trust-state-v1"
        )
    }
}

private func atomicRestrictedWrite(
    _ data: Data,
    to destination: URL,
    fileManager: FileManager
) throws {
    let directory = destination.deletingLastPathComponent()
    try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
    do {
        try data.write(to: temporary, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    } catch {
        try? fileManager.removeItem(at: temporary)
        throw error
    }
}

extension JSONEncoder {
    static var healthMdDirect: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var healthMdDirect: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
