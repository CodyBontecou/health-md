import Foundation

nonisolated struct HealthContextProfileStoreDocument: Codable, Equatable, Sendable {
    static let schemaIdentifier = "healthmd.health_context_profile_store"
    static let schemaVersion = 1

    let schemaIdentifier: String
    let schemaVersion: Int
    let profiles: [HealthContextProfile]

    init(
        schemaIdentifier: String = Self.schemaIdentifier,
        schemaVersion: Int = Self.schemaVersion,
        profiles: [HealthContextProfile]
    ) {
        self.schemaIdentifier = schemaIdentifier
        self.schemaVersion = schemaVersion
        self.profiles = profiles
    }
}

nonisolated enum HealthContextProfileStoreError: Error, Equatable, LocalizedError, Sendable {
    case corruptStore
    case unsupportedStoreSchema
    case storeTooLarge
    case invalidProfile(HealthContextProfileValidationError)
    case duplicateProfileID
    case revisionNotAdvanced
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .corruptStore: return "health_context_profile_store_corrupt"
        case .unsupportedStoreSchema: return "health_context_profile_store_unsupported_schema"
        case .storeTooLarge: return "health_context_profile_store_too_large"
        case .invalidProfile(let error): return "health_context_profile_\(error.rawValue)"
        case .duplicateProfileID: return "health_context_profile_store_duplicate_id"
        case .revisionNotAdvanced: return "health_context_profile_revision_not_advanced"
        case .persistenceFailed: return "health_context_profile_store_persistence_failed"
        }
    }
}

/// Concurrency-safe, atomically replaced JSON persistence for access profiles.
/// Expiration is evaluated only by the resolver; loading never removes an
/// expired profile. Corrupt or unsupported documents are never reset or
/// overwritten implicitly.
actor HealthContextProfileStore {
    static let fileName = "health-context-profiles.json"
    /// A bounded document is a filesystem safety measure, not a metric or date
    /// policy limit. No profile count, metric count, source count, or date span
    /// limit is imposed.
    static let maximumDocumentBytes = 64 * 1_024 * 1_024

    nonisolated let rootURL: URL
    nonisolated let storageURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        let resolvedRootURL: URL
        if let rootURL {
            resolvedRootURL = rootURL
        } else {
            let applicationSupport = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            resolvedRootURL = applicationSupport
                .appendingPathComponent("Health.md", isDirectory: true)
                .appendingPathComponent("HealthContextProfiles", isDirectory: true)
        }
        self.rootURL = resolvedRootURL
        self.storageURL = resolvedRootURL.appendingPathComponent(Self.fileName, isDirectory: false)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.decoder = decoder
    }

    func loadProfiles() throws -> [HealthContextProfile] {
        try loadDocument().profiles
    }

    func profile(id: UUID) throws -> HealthContextProfile? {
        try loadDocument().profiles.first { $0.id == id }
    }

    /// Adds a profile or atomically advances an existing profile's revision.
    /// Re-saving an identical profile is idempotent; changing policy or metadata
    /// at the same revision fails closed.
    func upsert(_ profile: HealthContextProfile) throws {
        try validate(profile)
        var profiles = try loadDocument().profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            let existing = profiles[index]
            if profile.revision == existing.revision {
                guard profile == existing else {
                    throw HealthContextProfileStoreError.revisionNotAdvanced
                }
                return
            }
            guard profile.revision > existing.revision else {
                throw HealthContextProfileStoreError.revisionNotAdvanced
            }
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        try persist(profiles)
    }

    func remove(profileID: UUID) throws {
        let existing = try loadDocument().profiles
        let remaining = existing.filter { $0.id != profileID }
        guard remaining.count != existing.count else { return }
        try persist(remaining)
    }

    /// Replaces the complete document atomically. Intended for import and
    /// migration paths that have already assembled exact revisions.
    func replaceAll(with profiles: [HealthContextProfile]) throws {
        // Load first so corrupt/unsupported durable state cannot be silently
        // replaced by an apparently valid write.
        _ = try loadDocument()
        try persist(profiles)
    }

    private func loadDocument() throws -> HealthContextProfileStoreDocument {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return HealthContextProfileStoreDocument(profiles: [])
        }

        if let size = try? storageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > Self.maximumDocumentBytes {
            throw HealthContextProfileStoreError.storeTooLarge
        }

        let data: Data
        do {
            data = try Data(contentsOf: storageURL, options: [.mappedIfSafe])
        } catch {
            throw HealthContextProfileStoreError.corruptStore
        }
        guard data.count <= Self.maximumDocumentBytes else {
            throw HealthContextProfileStoreError.storeTooLarge
        }

        let document: HealthContextProfileStoreDocument
        do {
            document = try decoder.decode(HealthContextProfileStoreDocument.self, from: data)
        } catch {
            throw HealthContextProfileStoreError.corruptStore
        }
        guard document.schemaIdentifier == HealthContextProfileStoreDocument.schemaIdentifier,
              document.schemaVersion == HealthContextProfileStoreDocument.schemaVersion else {
            throw HealthContextProfileStoreError.unsupportedStoreSchema
        }
        try validate(document.profiles)
        return HealthContextProfileStoreDocument(profiles: sorted(document.profiles))
    }

    private func persist(_ profiles: [HealthContextProfile]) throws {
        try validate(profiles)
        let document = HealthContextProfileStoreDocument(profiles: sorted(profiles))
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw HealthContextProfileStoreError.persistenceFailed
        }
        guard data.count <= Self.maximumDocumentBytes else {
            throw HealthContextProfileStoreError.storeTooLarge
        }

        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try AtomicFileWriter.writeData(data, to: storageURL, fileManager: fileManager)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storageURL.path
            )
        } catch let error as HealthContextProfileStoreError {
            throw error
        } catch {
            throw HealthContextProfileStoreError.persistenceFailed
        }
    }

    private func validate(_ profiles: [HealthContextProfile]) throws {
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw HealthContextProfileStoreError.duplicateProfileID
        }
        for profile in profiles {
            try validate(profile)
        }
    }

    private func validate(_ profile: HealthContextProfile) throws {
        do {
            try profile.validate()
        } catch let error as HealthContextProfileValidationError {
            throw HealthContextProfileStoreError.invalidProfile(error)
        } catch {
            throw HealthContextProfileStoreError.corruptStore
        }
    }

    private func sorted(_ profiles: [HealthContextProfile]) -> [HealthContextProfile] {
        profiles.sorted { lhs, rhs in
            lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
        }
    }
}
