import CryptoKit
import Foundation
import HealthMdCoreRust

/// Privacy-safe error identifiers shared with Android. Error details from Google are never
/// persisted or emitted to analytics.
nonisolated enum GoogleDriveErrorID: String, Codable, CaseIterable, Sendable {
    case configurationMissing = "configuration_missing"
    case reauthorizationRequired = "reauthorization_required"
    case accountMismatch = "account_mismatch"
    case folderUnavailable = "folder_unavailable"
    case permissionDenied = "permission_denied"
    case remoteConflict = "remote_conflict"
    case ambiguousCommit = "ambiguous_commit"
    case quotaExceeded = "quota_exceeded"
    case rateLimited = "rate_limited"
    case checksumMismatch = "checksum_mismatch"
    case partialCompletion = "partial_completion"
}

nonisolated struct GoogleDriveError: LocalizedError, Equatable, Sendable {
    let id: GoogleDriveErrorID
    let isRetryable: Bool

    init(_ id: GoogleDriveErrorID, isRetryable: Bool = false) {
        self.id = id
        self.isRetryable = isRetryable
    }

    var errorDescription: String? {
        switch id {
        case .configurationMissing: "Google Drive is unavailable in this build (configuration_missing)."
        case .reauthorizationRequired: "Reconnect Google Drive to continue (reauthorization_required)."
        case .accountMismatch: "The connected Google account does not match this destination (account_mismatch)."
        case .folderUnavailable: "The selected Google Drive folder is unavailable or no longer writable (folder_unavailable)."
        case .permissionDenied: "Google Drive denied this operation (permission_denied)."
        case .remoteConflict: "A Google Drive item changed outside Health.md. No files were replaced (remote_conflict)."
        case .ambiguousCommit: "Google Drive did not confirm whether the upload completed (ambiguous_commit)."
        case .quotaExceeded: "Google Drive storage or API quota was exceeded (quota_exceeded)."
        case .rateLimited: "Google Drive temporarily rate-limited this export (rate_limited)."
        case .checksumMismatch: "Google Drive returned different bytes than Health.md uploaded (checksum_mismatch)."
        case .partialCompletion: "Some files were uploaded before the export stopped (partial_completion)."
        }
    }
}

/// Public-client configuration. No client secret is accepted or shipped.
nonisolated struct GoogleDriveConfiguration: Equatable, Sendable {
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"
    static let clientIDInfoKey = "GOOGLE_DRIVE_IOS_CLIENT_ID"
    static let redirectURIInfoKey = "GOOGLE_DRIVE_REDIRECT_URI"

    let clientID: String
    let redirectURI: URL

    init?(clientID: String?, redirectURI: String?) {
        let clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let redirectURI = redirectURI?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clientID.isEmpty,
              !clientID.contains("$("),
              let url = URL(string: redirectURI),
              let scheme = url.scheme,
              !scheme.isEmpty,
              scheme.lowercased() != "http",
              scheme.lowercased() != "https" else { return nil }
        self.clientID = clientID
        self.redirectURI = url
    }

    static func from(bundle: Bundle = .main) -> GoogleDriveConfiguration? {
        GoogleDriveConfiguration(
            clientID: bundle.object(forInfoDictionaryKey: clientIDInfoKey) as? String,
            redirectURI: bundle.object(forInfoDictionaryKey: redirectURIInfoKey) as? String
        )
    }
}

nonisolated enum GoogleDriveReadiness: Equatable, Sendable {
    case ready
    case configurationMissing
    case destinationMissing
    case reauthorizationRequired
    case folderUnavailable

    var errorID: GoogleDriveErrorID? {
        switch self {
        case .ready: nil
        case .configurationMissing: .configurationMissing
        case .destinationMissing, .folderUnavailable: .folderUnavailable
        case .reauthorizationRequired: .reauthorizationRequired
        }
    }
}

/// Versioned non-secret authority binding. Labels are intentionally optional and privacy-safe.
nonisolated struct GoogleDriveDestination: Codable, Identifiable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    var credentialReferenceID: UUID
    var accountPermissionID: String
    var folderID: String
    var sharedDriveID: String?
    var resourceKey: String?
    var accountLabel: String?
    var folderLabel: String?
    var canAddChildren: Bool
    var lastValidatedAt: Date

    init(
        version: Int = Self.currentVersion,
        id: UUID = UUID(),
        credentialReferenceID: UUID,
        accountPermissionID: String,
        folderID: String,
        sharedDriveID: String? = nil,
        resourceKey: String? = nil,
        accountLabel: String? = nil,
        folderLabel: String? = nil,
        canAddChildren: Bool,
        lastValidatedAt: Date = Date()
    ) {
        self.version = version
        self.id = id
        self.credentialReferenceID = credentialReferenceID
        self.accountPermissionID = accountPermissionID
        self.folderID = folderID
        self.sharedDriveID = sharedDriveID
        self.resourceKey = resourceKey
        self.accountLabel = accountLabel
        self.folderLabel = folderLabel
        self.canAddChildren = canAddChildren
        self.lastValidatedAt = lastValidatedAt
    }

    var fingerprint: String {
        GoogleDriveDigest.framedSHA256([
            String(version), id.uuidString.lowercased(), credentialReferenceID.uuidString.lowercased(),
            accountPermissionID, folderID, sharedDriveID ?? "", resourceKey ?? ""
        ])
    }
}

/// Pending work stores only this frozen reference. It never embeds Drive IDs, labels or credentials.
nonisolated struct GoogleDriveDestinationSnapshot: Codable, Equatable, Sendable {
    let destinationID: UUID
    let fingerprint: String

    init(destination: GoogleDriveDestination) {
        destinationID = destination.id
        fingerprint = destination.fingerprint
    }
}

nonisolated struct GoogleDriveTokenCredential: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let grantedScopes: [String]

    var isDriveFileOnly: Bool {
        Set(grantedScopes) == [GoogleDriveConfiguration.driveFileScope]
    }
}

nonisolated struct GoogleDriveFileMetadata: Codable, Equatable, Sendable {
    static let folderMIMEType = "application/vnd.google-apps.folder"

    let id: String
    let name: String
    let mimeType: String
    let parents: [String]
    let driveID: String?
    let resourceKey: String?
    let version: String?
    let size: UInt64?
    let md5Checksum: String?
    let sha1Checksum: String?
    let sha256Checksum: String?
    let trashed: Bool
    let canAddChildren: Bool?

    var strongestChecksum: String? { sha256Checksum ?? sha1Checksum ?? md5Checksum }
}

nonisolated struct GoogleDriveManagedObjectBinding: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let destinationID: UUID
    let relativePathHash: String
    let objectID: String
    let parentID: String
    let expectedName: String
    let mimeType: String
    let resourceKey: String?
    var lastVerifiedVersion: String?
    var byteCount: UInt64?
    var checksum: String?

    init(
        version: Int = Self.currentVersion,
        destinationID: UUID,
        relativePathHash: String,
        objectID: String,
        parentID: String,
        expectedName: String,
        mimeType: String,
        resourceKey: String? = nil,
        lastVerifiedVersion: String? = nil,
        byteCount: UInt64? = nil,
        checksum: String? = nil
    ) {
        self.version = version
        self.destinationID = destinationID
        self.relativePathHash = relativePathHash
        self.objectID = objectID
        self.parentID = parentID
        self.expectedName = expectedName
        self.mimeType = mimeType
        self.resourceKey = resourceKey
        self.lastVerifiedVersion = lastVerifiedVersion
        self.byteCount = byteCount
        self.checksum = checksum
    }
}

/// Existing renderer intent. The fragment bytes are immutable; read/modify/write happens once in
/// the Drive runner after it has downloaded and persisted the exact baseline.
nonisolated enum GoogleDriveArtifactWriteIntent: String, Codable, Equatable, Sendable {
    case overwrite
    case append
    case markdownUpdate = "markdown_update"
    case dailyNoteMerge = "daily_note_merge"
}

nonisolated struct GoogleDriveGeneratedArtifact: Equatable, Sendable {
    let id: String
    let relativePath: String
    let mediaType: String
    let writeIntent: GoogleDriveArtifactWriteIntent
    /// Used only by Daily Note merge. False fails closed when no exact remote baseline exists.
    let createIfMissing: Bool
    let fragmentBytes: Data
    let byteCount: UInt64
    let sha256: String

    init(
        id: String,
        relativePath: String,
        mediaType: String,
        writeIntent: GoogleDriveArtifactWriteIntent,
        createIfMissing: Bool = true,
        fragmentBytes: Data
    ) throws {
        guard GoogleDrivePath.isSafe(relativePath) else {
            throw GoogleDriveError(.remoteConflict)
        }
        let digest = GoogleDriveDigest.sha256(fragmentBytes)
        guard id == digest || AppleExportEnginePin.isLowercaseSHA256(id) else {
            throw GoogleDriveError(.checksumMismatch)
        }
        self.id = id
        self.relativePath = relativePath
        self.mediaType = mediaType
        self.writeIntent = writeIntent
        self.createIfMissing = createIfMissing
        self.fragmentBytes = fragmentBytes
        self.byteCount = UInt64(fragmentBytes.count)
        self.sha256 = digest
    }
}

/// Destination-neutral immutable renderer output. Artifact order is authoritative.
nonisolated struct GoogleDriveGeneratedArtifactBundle: Equatable, Sendable {
    static let version = 1

    let operationID: UUID
    let profileID: UUID?
    let sourceDates: [Date]
    let settingsDigest: String
    let rendererIdentity: String
    let artifacts: [GoogleDriveGeneratedArtifact]
    let digest: String

    init(
        operationID: UUID = UUID(),
        profileID: UUID?,
        sourceDates: [Date],
        settingsDigest: String,
        rendererIdentity: String,
        artifacts: [GoogleDriveGeneratedArtifact]
    ) throws {
        guard artifacts.count <= 10_000,
              Set(artifacts.map { GoogleDrivePath.collisionKey($0.relativePath) }).count == artifacts.count else {
            throw GoogleDriveError(.remoteConflict)
        }
        self.operationID = operationID
        self.profileID = profileID
        self.sourceDates = sourceDates.sorted()
        self.settingsDigest = settingsDigest
        self.rendererIdentity = rendererIdentity
        self.artifacts = artifacts
        self.digest = GoogleDriveDigest.framedSHA256(
            [String(Self.version), operationID.uuidString.lowercased(), profileID?.uuidString.lowercased() ?? "", settingsDigest, rendererIdentity]
                + artifacts.flatMap { [$0.id, $0.relativePath, $0.mediaType, $0.writeIntent.rawValue, String($0.createIfMissing), String($0.byteCount), $0.sha256] }
        )
    }

    /// Adapts the existing destination-neutral native plan without changing one byte or write mode.
    init(nativePlan: NativeExportArtifactPlan, profileID: UUID?, sourceDates: [Date]) throws {
        let artifacts = try nativePlan.artifacts.compactMap { artifact -> GoogleDriveGeneratedArtifact? in
            guard artifact.role == .file else { return nil }
            let intent: GoogleDriveArtifactWriteIntent
            switch artifact.writeMode {
            case .overwrite: intent = .overwrite
            case .append: intent = .append
            case .markdownMerge: intent = .markdownUpdate
            case .apiPost: return nil
            }
            return try GoogleDriveGeneratedArtifact(
                id: artifact.id,
                relativePath: artifact.relativePath,
                mediaType: artifact.mediaType,
                writeIntent: intent,
                fragmentBytes: try artifact.content.materializedData()
            )
        }
        try self.init(
            operationID: UUID(uuidString: nativePlan.requestID) ?? UUID(),
            profileID: profileID,
            sourceDates: sourceDates,
            settingsDigest: nativePlan.sessionID,
            rendererIdentity: "apple_health_data_v8/artifact_plan_\(nativePlan.artifactPlanVersion)",
            artifacts: artifacts
        )
    }
}

nonisolated enum GoogleDrivePath {
    static func isSafe(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && path.utf8.count <= 4_096 && !path.hasPrefix("/") &&
            !path.contains("\\") && !path.contains("\0") &&
            !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
            !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    static func collisionKey(_ path: String) -> String {
        path.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func hash(_ path: String) -> String {
        GoogleDriveDigest.sha256(Data(path.utf8))
    }
}

nonisolated enum GoogleDriveDigest {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func framedSHA256(_ values: [String]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("healthmd.google_drive.v1\0".utf8))
        for value in values {
            var length = UInt64(value.utf8.count).bigEndian
            hasher.update(data: withUnsafeBytes(of: &length) { Data($0) })
            hasher.update(data: Data(value.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
