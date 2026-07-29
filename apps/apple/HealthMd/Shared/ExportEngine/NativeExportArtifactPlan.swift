import CryptoKit
import Foundation
import HealthMdCoreRust

/// Destination class for a rendered artifact. The role is derived from the write mode so UniFFI
/// plans cannot smuggle an inconsistent destination operation.
nonisolated enum NativeExportArtifactRole: String, Codable, Equatable, Sendable {
    case file
    case apiRequest = "api_request"

    init(writeMode: CoreArtifactWriteMode) {
        self = writeMode == .apiPost ? .apiRequest : .file
    }
}

/// One immutable, destination-neutral artifact. Construction verifies all byte-integrity fields
/// without reading a destination or performing any other side effect.
nonisolated struct NativeExportArtifact: Equatable, Sendable {
    enum ValidationError: String, Error, Equatable, Sendable {
        case invalidRole
        case invalidArtifactID
        case invalidRelativePath
        case invalidMediaType
        case invalidByteCount
        case invalidSHA256
        case contentDigestMismatch
    }

    let role: NativeExportArtifactRole
    let id: String
    let relativePath: String
    let mediaType: String
    let writeMode: CoreArtifactWriteMode
    let inlineData: Data
    let byteCount: UInt64
    let sha256: String

    init(
        role: NativeExportArtifactRole,
        id: String,
        relativePath: String,
        mediaType: String,
        writeMode: CoreArtifactWriteMode,
        inlineData: Data,
        byteCount: UInt64,
        sha256: String
    ) throws {
        guard role == NativeExportArtifactRole(writeMode: writeMode) else {
            throw ValidationError.invalidRole
        }
        guard AppleExportEnginePin.isLowercaseSHA256(id) else {
            throw ValidationError.invalidArtifactID
        }
        guard Self.isValidRelativePath(relativePath) else {
            throw ValidationError.invalidRelativePath
        }
        guard Self.isValidMediaType(mediaType) else {
            throw ValidationError.invalidMediaType
        }
        guard let actualByteCount = UInt64(exactly: inlineData.count),
              byteCount == actualByteCount else {
            throw ValidationError.invalidByteCount
        }
        guard AppleExportEnginePin.isLowercaseSHA256(sha256) else {
            throw ValidationError.invalidSHA256
        }
        guard sha256 == Self.sha256(of: inlineData) else {
            throw ValidationError.contentDigestMismatch
        }

        self.role = role
        self.id = id
        self.relativePath = relativePath
        self.mediaType = mediaType
        self.writeMode = writeMode
        self.inlineData = inlineData
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isValidRelativePath(_ path: String) -> Bool {
        let bytes = path.utf8
        let windowsAbsolute = bytes.count >= 2
            && bytes[bytes.index(after: bytes.startIndex)] == 58
            && bytes.first.map { (65...90).contains($0) || (97...122).contains($0) } == true
        guard !path.isEmpty,
              bytes.count <= 4_096,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !windowsAbsolute,
              !path.contains("\\"),
              !path.contains("\0"),
              !path.contains("{"),
              !path.contains("}"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains {
            $0.isEmpty || $0 == "." || $0 == ".."
        }
    }

    private static func isValidMediaType(_ value: String) -> Bool {
        let bytes = value.utf8
        guard !value.isEmpty, bytes.count <= 128, value.contains("/") else { return false }
        return bytes.allSatisfy { byte in
            (65...90).contains(byte)
                || (97...122).contains(byte)
                || (48...57).contains(byte)
                || [47, 43, 45, 46, 59, 61, 32].contains(byte)
        }
    }
}

/// Complete ordered artifact plan produced before any destination is opened.
nonisolated struct NativeExportArtifactPlan: Equatable, Sendable {
    static let schema = "healthmd.artifact_plan"

    enum ValidationError: String, Error, Equatable, Sendable {
        case invalidSchema
        case incompatibleArtifactPlanVersion
        case invalidRequestID
        case invalidSessionID
        case invalidProfile
        case tooManyArtifacts
        case duplicateArtifactID
        case artifactIDMismatch
        case pathCollision
        case artifactTooLarge
        case inlineOutputTooLarge
        case invalidTotalByteCount
    }

    let artifactPlanVersion: UInt32
    let requestID: String
    let sessionID: String
    let profile: CoreMetricRegistryProfile
    /// Array order is authoritative and is never normalized by this model.
    let artifacts: [NativeExportArtifact]
    let totalByteCount: UInt64

    init(
        schema: String = Self.schema,
        artifactPlanVersion: UInt32,
        requestID: String,
        sessionID: String,
        profile: CoreMetricRegistryProfile,
        artifacts: [NativeExportArtifact],
        totalByteCount: UInt64,
        pin: AppleExportEnginePin
    ) throws {
        guard schema == Self.schema else { throw ValidationError.invalidSchema }
        guard artifactPlanVersion == pin.artifactPlanVersion else {
            throw ValidationError.incompatibleArtifactPlanVersion
        }
        guard Self.isValidOperationID(requestID) else { throw ValidationError.invalidRequestID }
        guard Self.isValidOperationID(sessionID) else { throw ValidationError.invalidSessionID }
        guard profile == .appleHealthDataV7,
              pin.profile == AppleExportEnginePin.profileID else {
            throw ValidationError.invalidProfile
        }
        guard artifacts.count <= 4_096 else { throw ValidationError.tooManyArtifacts }
        guard Set(artifacts.map(\.id)).count == artifacts.count else {
            throw ValidationError.duplicateArtifactID
        }

        var portablePaths = Set<String>()
        var calculatedTotal: UInt64 = 0
        for artifact in artifacts {
            guard artifact.id == Self.artifactID(
                requestID: requestID,
                sessionID: sessionID,
                profile: profile,
                relativePath: artifact.relativePath,
                mediaType: artifact.mediaType,
                writeMode: artifact.writeMode,
                contentSHA256: artifact.sha256
            ) else {
                throw ValidationError.artifactIDMismatch
            }
            let collisionKey = Self.portableCollisionKey(artifact.relativePath)
            guard portablePaths.insert(collisionKey).inserted else {
                throw ValidationError.pathCollision
            }
            let perArtifactLimit: UInt64 = artifact.writeMode == .apiPost
                ? 32 * 1_024 * 1_024
                : 8 * 1_024 * 1_024
            guard artifact.byteCount <= perArtifactLimit else {
                throw ValidationError.artifactTooLarge
            }
            let (nextTotal, overflow) = calculatedTotal.addingReportingOverflow(artifact.byteCount)
            guard !overflow, nextTotal <= 32 * 1_024 * 1_024 else {
                throw ValidationError.inlineOutputTooLarge
            }
            calculatedTotal = nextTotal
        }
        guard totalByteCount == calculatedTotal else {
            throw ValidationError.invalidTotalByteCount
        }

        self.artifactPlanVersion = artifactPlanVersion
        self.requestID = requestID
        self.sessionID = sessionID
        self.profile = profile
        self.artifacts = artifacts
        self.totalByteCount = totalByteCount
    }

    static func artifactID(
        requestID: String,
        sessionID: String,
        profile: CoreMetricRegistryProfile,
        relativePath: String,
        mediaType: String,
        writeMode: CoreArtifactWriteMode,
        contentSHA256: String
    ) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("healthmd.artifact_id.v1\0".utf8))
        for value in [
            requestID,
            sessionID,
            profileIdentifier(profile),
            relativePath,
            mediaType,
            writeModeIdentifier(writeMode),
            contentSHA256,
        ] {
            var length = UInt64(value.utf8.count).bigEndian
            hasher.update(data: withUnsafeBytes(of: &length) { Data($0) })
            hasher.update(data: Data(value.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func profileIdentifier(_ profile: CoreMetricRegistryProfile) -> String {
        switch profile {
        case .appleHealthDataV7: "apple_health_data_v7"
        case .androidFrozenV4: "android_frozen_v4"
        case .androidAnalyticalV5: "android_analytical_v5"
        }
    }

    private static func writeModeIdentifier(_ writeMode: CoreArtifactWriteMode) -> String {
        switch writeMode {
        case .overwrite: "overwrite"
        case .append: "append"
        case .markdownMerge: "markdown_merge"
        case .apiPost: "api_post"
        }
    }

    private static func isValidOperationID(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func portableCollisionKey(_ path: String) -> String {
        path.precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCompatibilityMapping
    }
}

/// Pure conversion boundary from generated UniFFI values to the native immutable model.
nonisolated enum CoreArtifactPlanConverter {
    static func convert(
        _ corePlan: CoreArtifactPlan,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let artifacts = try corePlan.items.map { item in
            try NativeExportArtifact(
                role: NativeExportArtifactRole(writeMode: item.writeMode),
                id: item.artifactId,
                relativePath: item.relativePath,
                mediaType: item.mediaType,
                writeMode: item.writeMode,
                inlineData: item.content,
                byteCount: item.byteCount,
                sha256: item.sha256
            )
        }
        return try NativeExportArtifactPlan(
            schema: corePlan.schema,
            artifactPlanVersion: corePlan.artifactPlanVersion,
            requestID: corePlan.requestId,
            sessionID: corePlan.sessionId,
            profile: corePlan.profile,
            artifacts: artifacts,
            totalByteCount: corePlan.totalByteCount,
            pin: pin
        )
    }
}
