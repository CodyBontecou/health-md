#if os(macOS)
import CryptoKit
import Foundation

/// Errors are deliberately fail-closed: callers never receive partially decoded health context.
nonisolated enum EncryptedHealthContextStoreError: LocalizedError, Equatable {
    case missingEncryptionKey
    case invalidEncryptionKey
    case ciphertextAuthenticationFailed
    case corruptManifest
    case corruptBlob
    case unsupportedStoreContract(schema: String, version: Int)
    case unsupportedContextDay(schema: String, version: Int)
    case invalidOwnerDate(String)
    case duplicateOwnerDate(String)
    case manifestBlobMismatch(String)
    case generationCollision

    var errorDescription: String? {
        switch self {
        case .missingEncryptionKey:
            return "The encryption key for Health.md query context is unavailable."
        case .invalidEncryptionKey:
            return "The encryption key for Health.md query context is invalid."
        case .ciphertextAuthenticationFailed:
            return "Encrypted Health.md query context failed authentication."
        case .corruptManifest:
            return "The encrypted Health.md query-context index is corrupt."
        case .corruptBlob:
            return "An encrypted Health.md query-context day is corrupt."
        case .unsupportedStoreContract:
            return "This version of Health.md cannot read the query-context store contract."
        case .unsupportedContextDay:
            return "This version of Health.md cannot read the stored context-day contract."
        case .invalidOwnerDate:
            return "Stored Health.md query context contains an invalid owner date."
        case .duplicateOwnerDate:
            return "Stored Health.md query context contains a duplicate owner date."
        case .manifestBlobMismatch:
            return "The encrypted Health.md query-context index does not match its day blob."
        case .generationCollision:
            return "Health.md could not allocate an immutable query-context generation."
        }
    }
}

/// Date-based retention is explicit and opt-in. The store never applies count, size, metric,
/// result, or history limits.
nonisolated struct HealthContextRetentionPolicy: Sendable {
    private let decision: @Sendable (String) -> Bool

    init(shouldRetain: @escaping @Sendable (String) -> Bool) {
        self.decision = shouldRetain
    }

    static func delete(before ownerDate: String) -> Self {
        Self { $0 >= ownerDate }
    }

    static var keepAll: Self { Self { _ in true } }

    fileprivate func shouldRetain(_ ownerDate: String) -> Bool {
        decision(ownerDate)
    }
}

/// Immutable metadata captured from one authenticated manifest. Holding a snapshot never loads a
/// health-context day. Its revision changes on every committed manifest mutation because immutable
/// generation identities are included in the digest.
nonisolated struct HealthContextStoreSnapshot: Sendable, Equatable {
    nonisolated struct Entry: Sendable, Equatable {
        let ownerDate: String
        fileprivate let generation: String
        fileprivate let dayDigest: String
    }

    let revision: String
    let entries: [Entry]
}

/// An encrypted, one-blob-per-day Mac store for compact query context.
///
/// The encrypted manifest is the commit point. Upsert always writes a fresh immutable generation,
/// atomically replaces the manifest, and only then removes the superseded generation. Therefore an
/// interrupted write can leave an unreachable orphan, but can never redirect an old manifest to
/// newly overwritten content.
actor EncryptedHealthContextStore {
    nonisolated static let storeSchema = "healthmd.encrypted_query_context_store"
    nonisolated static let storeSchemaVersion = 1

    private static let manifestFilename = "manifest.hctx"
    private static let generationPrefix = "generation-"
    private static let generationSuffix = ".hctx"
    private static let filePermissions = 0o600
    private static let directoryPermissions = 0o700
    private static let manifestAAD = Data("healthmd/query-context-store/v1/manifest".utf8)
    private static let cursorKeySalt = Data("healthmd/query-context-store/v1/cursor-key/salt".utf8)
    private static let cursorKeyInfo = Data("healthmd/query-context-store/v1/cursor-key/aes-gcm-256".utf8)

    private let rootURL: URL
    private let fileManager: FileManager
    private let keyProvider: any HealthContextEncryptionKeyProviding
    private let generationID: @Sendable () -> UUID
    private let beforeManifestCommit: @Sendable () throws -> Void

    init(
        rootURL: URL = EncryptedHealthContextStore.defaultRootURL(),
        keyProvider: any HealthContextEncryptionKeyProviding = KeychainHealthContextEncryptionKeyProvider(),
        fileManager: FileManager = .default,
        generationID: @escaping @Sendable () -> UUID = { UUID() },
        beforeManifestCommit: @escaping @Sendable () throws -> Void = {}
    ) {
        self.rootURL = rootURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
        self.generationID = generationID
        self.beforeManifestCommit = beforeManifestCommit
    }

    nonisolated static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent("EncryptedQueryContext-v1", isDirectory: true)
    }

    /// Inserts or replaces one owner day without aggregating day payloads in memory.
    func upsert(_ day: HealthMdCompactContextDay) throws {
        try upsert([day])
    }

    /// Efficient import hook for callers that already hold a batch. Every day remains an
    /// independently encrypted blob; the batch does not create an aggregate health payload.
    func upsert(_ days: [HealthMdCompactContextDay]) throws {
        guard !days.isEmpty else { return }
        try prepareRootDirectory()

        var incomingDates = Set<String>()
        for day in days {
            try validate(day: day)
            guard incomingDates.insert(day.ownerDate).inserted else {
                throw EncryptedHealthContextStoreError.duplicateOwnerDate(day.ownerDate)
            }
        }

        let manifestExists = fileManager.fileExists(atPath: manifestURL.path)
        let key = try encryptionKey(createIfMissing: !manifestExists)
        var manifest = try loadManifest(key: key)
        let replacedEntries = manifest.entries.filter { incomingDates.contains($0.ownerDate) }
        for entry in replacedEntries {
            _ = try loadDay(entry: entry, key: key)
        }

        var reservedGenerations = Set(manifest.entries.map(\.generation))
        var staged: [(entry: ManifestEntry, url: URL)] = []
        do {
            for day in days {
                let generation = try allocateGeneration(excluding: reservedGenerations)
                reservedGenerations.insert(generation)
                let canonicalDay = try HealthMdQueryCanonicalSerializer.data(for: day)
                let digest = HealthMdQueryCanonicalSerializer.sha256(data: canonicalDay)
                let blob = StoredDayBlob(
                    schema: Self.storeSchema,
                    schemaVersion: Self.storeSchemaVersion,
                    generation: generation,
                    ownerDate: day.ownerDate,
                    dayDigest: digest,
                    day: day
                )
                let ciphertext = try seal(
                    try HealthMdQueryCanonicalSerializer.data(for: blob),
                    key: key,
                    authenticating: blobAAD(generation: generation)
                )
                let url = generationURL(generation)
                try writeProtected(ciphertext, to: url)
                staged.append((
                    entry: .init(ownerDate: day.ownerDate, generation: generation, dayDigest: digest),
                    url: url
                ))
            }

            manifest.entries.removeAll { incomingDates.contains($0.ownerDate) }
            manifest.entries.append(contentsOf: staged.map(\.entry))
            manifest.entries.sort { $0.ownerDate < $1.ownerDate }
            try beforeManifestCommit()
            try writeManifest(manifest, key: key)
        } catch {
            for item in staged { try? fileManager.removeItem(at: item.url) }
            throw error
        }

        for entry in replacedEntries {
            try? fileManager.removeItem(at: generationURL(entry.generation))
        }
        try? garbageCollectOrphans(referencedBy: manifest)
    }

    /// Returns owner-date identifiers only. Day payloads remain encrypted and are not loaded.
    func listOwnerDates() throws -> [String] {
        try prepareRootDirectory()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        let key = try encryptionKey(createIfMissing: false)
        return try loadManifest(key: key).entries.map(\.ownerDate)
    }

    /// Captures authenticated immutable manifest metadata without loading any day payload.
    func snapshot() throws -> HealthContextStoreSnapshot {
        try prepareRootDirectory()
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return try makeSnapshot(from: .empty)
        }
        let key = try encryptionKey(createIfMissing: false)
        return try makeSnapshot(from: loadManifest(key: key))
    }

    /// Loads exactly one day from an immutable manifest snapshot. The caller can advance the index
    /// within a dense day, so no fixed per-day result limit is necessary.
    func loadDay(
        from snapshot: HealthContextStoreSnapshot,
        at index: Int
    ) throws -> HealthMdCompactContextDay {
        guard snapshot.entries.indices.contains(index) else {
            throw EncryptedHealthContextStoreError.corruptManifest
        }
        let key = try encryptionKey(createIfMissing: false)
        let snapshotEntry = snapshot.entries[index]
        return try loadDay(
            entry: ManifestEntry(
                ownerDate: snapshotEntry.ownerDate,
                generation: snapshotEntry.generation,
                dayDigest: snapshotEntry.dayDigest
            ),
            key: key
        )
    }

    /// Returns a cursor-only key derived with HKDF from the Keychain-backed store key. The store
    /// key itself is never returned or persisted beside ciphertext, and the domain separation
    /// prevents cursor material from being used as an AES-GCM day-encryption key.
    func cursorAuthenticationKeyData() throws -> Data {
        let key = try encryptionKey(createIfMissing: false)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Self.cursorKeySalt,
            info: Self.cursorKeyInfo,
            outputByteCount: KeychainHealthContextEncryptionKeyProvider.keyLength
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    /// Loads and authenticates exactly one day.
    func loadDay(ownerDate: String) throws -> HealthMdCompactContextDay? {
        try prepareRootDirectory()
        try validateOwnerDate(ownerDate)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let key = try encryptionKey(createIfMissing: false)
        let manifest = try loadManifest(key: key)
        guard let entry = manifest.entries.first(where: { $0.ownerDate == ownerDate }) else { return nil }
        return try loadDay(entry: entry, key: key)
    }

    /// Traverses a stable manifest snapshot in owner-date order while decrypting only the current
    /// day. This avoids repeatedly decoding the index and never constructs an aggregate day array.
    func forEachDay(_ visit: @Sendable (HealthMdCompactContextDay) throws -> Void) throws {
        try prepareRootDirectory()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        let key = try encryptionKey(createIfMissing: false)
        let manifest = try loadManifest(key: key)
        for entry in manifest.entries {
            try visit(loadDay(entry: entry, key: key))
        }
    }

    /// Removes one day. The manifest commits the deletion before the old blob is unlinked.
    @discardableResult
    func deleteDay(ownerDate: String) throws -> Bool {
        try prepareRootDirectory()
        try validateOwnerDate(ownerDate)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return false }
        let key = try encryptionKey(createIfMissing: false)
        var manifest = try loadManifest(key: key)
        guard let entry = manifest.entries.first(where: { $0.ownerDate == ownerDate }) else { return false }

        manifest.entries.removeAll { $0.ownerDate == ownerDate }
        try beforeManifestCommit()
        try writeManifest(manifest, key: key)
        try? fileManager.removeItem(at: generationURL(entry.generation))
        try? garbageCollectOrphans(referencedBy: manifest)
        return true
    }

    /// Applies an explicit retention policy. No policy runs automatically.
    @discardableResult
    func applyRetention(_ policy: HealthContextRetentionPolicy) throws -> [String] {
        try prepareRootDirectory()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        let key = try encryptionKey(createIfMissing: false)
        var manifest = try loadManifest(key: key)
        let removed = manifest.entries.filter { !policy.shouldRetain($0.ownerDate) }
        guard !removed.isEmpty else { return [] }

        manifest.entries.removeAll { !policy.shouldRetain($0.ownerDate) }
        try beforeManifestCommit()
        try writeManifest(manifest, key: key)
        for entry in removed {
            try? fileManager.removeItem(at: generationURL(entry.generation))
        }
        try? garbageCollectOrphans(referencedBy: manifest)
        return removed.map(\.ownerDate)
    }

    /// Deletes all encrypted context without needing to decrypt it. This remains available even if
    /// Keychain material or ciphertext has been lost or damaged. The dedicated key is removed after
    /// the files, providing crypto-erasure for any deleted filesystem remnants.
    func deleteAll() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try keyProvider.removeKey()
        try prepareRootDirectory()
    }

    /// Maintenance hook for crash-orphaned immutable blobs. Referenced content is never removed.
    func garbageCollectOrphanedGenerations() throws {
        try prepareRootDirectory()
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            try garbageCollectOrphans(referencedBy: Manifest.empty)
            return
        }
        let key = try encryptionKey(createIfMissing: false)
        try garbageCollectOrphans(referencedBy: loadManifest(key: key))
    }

    private var manifestURL: URL {
        rootURL.appendingPathComponent(Self.manifestFilename, isDirectory: false)
    }

    private func generationURL(_ generation: String) -> URL {
        rootURL.appendingPathComponent(generation, isDirectory: false)
    }

    private func encryptionKey(createIfMissing: Bool) throws -> SymmetricKey {
        let data: Data
        if createIfMissing {
            data = try keyProvider.existingOrCreateKeyData()
        } else {
            guard let existing = try keyProvider.existingKeyData() else {
                throw EncryptedHealthContextStoreError.missingEncryptionKey
            }
            data = existing
        }
        guard data.count == KeychainHealthContextEncryptionKeyProvider.keyLength else {
            throw EncryptedHealthContextStoreError.invalidEncryptionKey
        }
        return SymmetricKey(data: data)
    }

    private func loadManifest(key: SymmetricKey) throws -> Manifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }
        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw EncryptedHealthContextStoreError.corruptManifest
        }
        let plaintext = try open(ciphertext, key: key, authenticating: Self.manifestAAD)
        let manifest: Manifest
        do {
            manifest = try HealthMdQueryCanonicalSerializer.decode(Manifest.self, from: plaintext)
        } catch {
            throw EncryptedHealthContextStoreError.corruptManifest
        }
        try validate(manifest: manifest)
        return manifest
    }

    private func writeManifest(_ manifest: Manifest, key: SymmetricKey) throws {
        try validate(manifest: manifest)
        let plaintext = try HealthMdQueryCanonicalSerializer.data(for: manifest)
        let ciphertext = try seal(plaintext, key: key, authenticating: Self.manifestAAD)
        try writeProtected(ciphertext, to: manifestURL)
    }

    private func makeSnapshot(from manifest: Manifest) throws -> HealthContextStoreSnapshot {
        HealthContextStoreSnapshot(
            revision: HealthMdQueryCanonicalSerializer.sha256(
                data: try HealthMdQueryCanonicalSerializer.data(for: manifest)
            ),
            entries: manifest.entries.map {
                .init(ownerDate: $0.ownerDate, generation: $0.generation, dayDigest: $0.dayDigest)
            }
        )
    }

    private func loadDay(entry: ManifestEntry, key: SymmetricKey) throws -> HealthMdCompactContextDay {
        let url = generationURL(entry.generation)
        guard fileManager.fileExists(atPath: url.path) else {
            throw EncryptedHealthContextStoreError.manifestBlobMismatch(entry.ownerDate)
        }
        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw EncryptedHealthContextStoreError.corruptBlob
        }
        let plaintext = try open(ciphertext, key: key, authenticating: blobAAD(generation: entry.generation))
        let blob: StoredDayBlob
        do {
            blob = try HealthMdQueryCanonicalSerializer.decode(StoredDayBlob.self, from: plaintext)
        } catch {
            throw EncryptedHealthContextStoreError.corruptBlob
        }
        guard blob.schema == Self.storeSchema, blob.schemaVersion == Self.storeSchemaVersion else {
            throw EncryptedHealthContextStoreError.unsupportedStoreContract(
                schema: blob.schema,
                version: blob.schemaVersion
            )
        }
        try validate(day: blob.day)
        let digest = HealthMdQueryCanonicalSerializer.sha256(
            data: try HealthMdQueryCanonicalSerializer.data(for: blob.day)
        )
        guard blob.generation == entry.generation,
              blob.ownerDate == entry.ownerDate,
              blob.day.ownerDate == entry.ownerDate,
              blob.dayDigest == entry.dayDigest,
              digest == entry.dayDigest else {
            throw EncryptedHealthContextStoreError.manifestBlobMismatch(entry.ownerDate)
        }
        return blob.day
    }

    private func validate(manifest: Manifest) throws {
        guard manifest.schema == Self.storeSchema,
              manifest.schemaVersion == Self.storeSchemaVersion else {
            throw EncryptedHealthContextStoreError.unsupportedStoreContract(
                schema: manifest.schema,
                version: manifest.schemaVersion
            )
        }

        var ownerDates = Set<String>()
        var generations = Set<String>()
        var previousOwnerDate: String?
        for entry in manifest.entries {
            try validateOwnerDate(entry.ownerDate)
            guard ownerDates.insert(entry.ownerDate).inserted else {
                throw EncryptedHealthContextStoreError.duplicateOwnerDate(entry.ownerDate)
            }
            guard generations.insert(entry.generation).inserted,
                  isValidGeneration(entry.generation),
                  isSHA256(entry.dayDigest) else {
                throw EncryptedHealthContextStoreError.corruptManifest
            }
            if let previousOwnerDate, previousOwnerDate >= entry.ownerDate {
                throw EncryptedHealthContextStoreError.corruptManifest
            }
            previousOwnerDate = entry.ownerDate
            guard fileManager.fileExists(atPath: generationURL(entry.generation).path) else {
                throw EncryptedHealthContextStoreError.manifestBlobMismatch(entry.ownerDate)
            }
        }
    }

    private func validate(day: HealthMdCompactContextDay) throws {
        try validateOwnerDate(day.ownerDate)
        guard day.schema == HealthMdQuerySchemas.compactContextDay, day.schemaVersion == 1 else {
            throw EncryptedHealthContextStoreError.unsupportedContextDay(
                schema: day.schema,
                version: day.schemaVersion
            )
        }
    }

    private func validateOwnerDate(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in index == 4 || index == 7 || (48...57).contains(byte) }),
              let year = Int(value.prefix(4)),
              let month = Int(value.dropFirst(5).prefix(2)),
              let day = Int(value.suffix(2)) else {
            throw EncryptedHealthContextStoreError.invalidOwnerDate(value)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            throw EncryptedHealthContextStoreError.invalidOwnerDate(value)
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw EncryptedHealthContextStoreError.invalidOwnerDate(value)
        }
    }

    private func allocateGeneration(excluding existing: Set<String>) throws -> String {
        for _ in 0..<32 {
            let candidate = Self.generationPrefix + generationID().uuidString.lowercased() + Self.generationSuffix
            if !existing.contains(candidate), !fileManager.fileExists(atPath: generationURL(candidate).path) {
                return candidate
            }
        }
        throw EncryptedHealthContextStoreError.generationCollision
    }

    private func isValidGeneration(_ value: String) -> Bool {
        guard value.hasPrefix(Self.generationPrefix), value.hasSuffix(Self.generationSuffix) else { return false }
        let start = value.index(value.startIndex, offsetBy: Self.generationPrefix.count)
        let end = value.index(value.endIndex, offsetBy: -Self.generationSuffix.count)
        let identifier = String(value[start..<end])
        return identifier == identifier.lowercased() && UUID(uuidString: identifier) != nil
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func seal(_ plaintext: Data, key: SymmetricKey, authenticating aad: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = box.combined else {
            throw EncryptedHealthContextStoreError.corruptBlob
        }
        return combined
    }

    private func open(_ ciphertext: Data, key: SymmetricKey, authenticating aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw EncryptedHealthContextStoreError.ciphertextAuthenticationFailed
        }
    }

    private func blobAAD(generation: String) -> Data {
        Data("healthmd/query-context-store/v1/blob/\(generation)".utf8)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        // All throwable work must happen before the atomic rename returns. A post-rename
        // metadata error could otherwise make a caller remove a now-referenced staged blob.
        // Backup exclusion is applied to the containing store directory.
        try AtomicFileWriter.writeData(
            data,
            to: url,
            fileManager: fileManager,
            attributes: [.posixPermissions: Self.filePermissions]
        )
    }

    private func prepareRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try fileManager.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: rootURL.path)
        try excludeFromBackup(rootURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private func garbageCollectOrphans(referencedBy manifest: Manifest) throws {
        let referenced = Set(manifest.entries.map(\.generation))
        let contents = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix(Self.generationPrefix), name.hasSuffix(Self.generationSuffix), !referenced.contains(name) else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }
}

private extension EncryptedHealthContextStore {
    struct Manifest: Codable, Sendable {
        let schema: String
        let schemaVersion: Int
        var entries: [ManifestEntry]

        static let empty = Manifest(
            schema: EncryptedHealthContextStore.storeSchema,
            schemaVersion: EncryptedHealthContextStore.storeSchemaVersion,
            entries: []
        )

        enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case entries
        }
    }

    struct ManifestEntry: Codable, Sendable {
        let ownerDate: String
        let generation: String
        let dayDigest: String

        enum CodingKeys: String, CodingKey {
            case ownerDate = "owner_date"
            case generation
            case dayDigest = "day_digest"
        }
    }

    struct StoredDayBlob: Codable, Sendable {
        let schema: String
        let schemaVersion: Int
        let generation: String
        let ownerDate: String
        let dayDigest: String
        let day: HealthMdCompactContextDay

        enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case generation
            case ownerDate = "owner_date"
            case dayDigest = "day_digest"
            case day
        }
    }
}
#endif
