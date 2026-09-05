import CryptoKit
import Foundation

// MARK: - Agent Data ingestion protocol v1 client truth
//
// Normative sources (frozen):
// - `packages/contracts/agent-data/v1/contract.md` — "## Ingestion",
//   "### Non-destructive v1", "### HTTPS transport (gateways)".
// - `packages/contracts/agent-data/v1/agent-data-ingest.schema.json`
// - `packages/contracts/agent-data/v1/agent-ingest-response.schema.json`
// - the eight registered `fixtures/ingest-*.json` conformance shapes
// - `apps/cli/docs/agent-data.md` ("Local ingestion",
//   "Self-hosted ingestion gateway") and
//   `apps/cli/crates/healthmd-cli/src/mcp/ingest_http.rs` (read-only server
//   truth: framing, bounds, Host/Origin posture).
//
// The phone uploads exact existing Health.md artifacts; the gateway validates
// and stores them unchanged. One artifact per request; the request body is
// one `\n`-terminated JSON manifest line followed immediately by exactly
// `byte_count` artifact bytes; no compression, no multipart, no chunked
// upload sessions. Receipts are health-free.

/// Standalone artifact families recognized by Agent Data ingestion v1.
nonisolated enum AgentDataIngestArtifactKind: String, Codable, Equatable, Sendable, CaseIterable {
    case healthDataDaily = "health_data_daily"
    case externalProviderDaily = "external_provider_daily"
    case rawSnapshot = "raw_snapshot"
    case rawChanges = "raw_changes"
}

/// Physical format of one uploaded artifact.
nonisolated enum AgentDataIngestPhysicalFormat: String, Codable, Equatable, Sendable {
    case json
    case ndjson
}

/// Capture completeness of one uploaded artifact. The phone only uploads
/// finalized artifacts, so a partial is always `finalized: true` with its
/// covered owner dates; `finalized: false` is never emitted.
nonisolated enum AgentDataIngestCompleteness: Codable, Equatable, Sendable {
    case complete
    case partial(finalized: Bool, coveredOwnerDates: [String])

    private enum CodingKeys: String, CodingKey {
        case type
        case finalized
        case coveredOwnerDates = "covered_owner_dates"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "complete":
            self = .complete
        case "partial":
            let finalized = try container.decode(Bool.self, forKey: .finalized)
            let covered = try container.decode([String].self, forKey: .coveredOwnerDates)
            self = .partial(finalized: finalized, coveredOwnerDates: covered)
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown completeness type \(other)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .complete:
            try container.encode("complete", forKey: .type)
        case .partial(let finalized, let coveredOwnerDates):
            try container.encode("partial", forKey: .type)
            try container.encode(finalized, forKey: .finalized)
            try container.encode(coveredOwnerDates, forKey: .coveredOwnerDates)
        }
    }
}

/// One `healthmd.agent_data_ingest` v1 manifest describing exactly the
/// artifact bytes uploaded in the same request.
///
/// `record_count` is intentionally absent: it is optional and informational
/// in v1, and omitting it is always valid. All other schema-required fields
/// are non-optional.
nonisolated struct AgentDataIngestManifest: Codable, Equatable, Sendable {
    static let schema = "healthmd.agent_data_ingest"
    static let schemaVersion = 1

    let schema: String
    let schemaVersion: Int
    let artifactKind: AgentDataIngestArtifactKind
    let platform: String
    let artifactSchema: String
    let artifactSchemaVersion: Int
    let ownerDate: String
    let physicalFormat: AgentDataIngestPhysicalFormat
    let mediaType: String
    let byteCount: Int
    let sha256: String
    let completeness: AgentDataIngestCompleteness

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case artifactKind = "artifact_kind"
        case platform
        case artifactSchema = "artifact_schema"
        case artifactSchemaVersion = "artifact_schema_version"
        case ownerDate = "owner_date"
        case physicalFormat = "physical_format"
        case mediaType = "media_type"
        case byteCount = "byte_count"
        case sha256
        case completeness
    }

    enum ValidationError: String, Error, Equatable {
        case wrongSchema
        case wrongSchemaVersion
        case wrongPlatform
        case emptyArtifactSchema
        case emptyOwnerDate
        case emptyMediaType
        case emptyByteCount
        case oversizedByteCount
        case invalidDigest
        case unfinalizedPartial
        case partialRawArtifact
        case emptyCoveredOwnerDates
        case tooManyCoveredOwnerDates
        case duplicateCoveredOwnerDates
        case invalidOwnerDateFormat
    }

    /// The contract's whole-artifact bound (64 MiB).
    static let maximumByteCount = 67_108_864
    static let maximumCoveredOwnerDates = 400

    init(
        artifactKind: AgentDataIngestArtifactKind,
        platform: String,
        artifactSchema: String,
        artifactSchemaVersion: Int,
        ownerDate: String,
        physicalFormat: AgentDataIngestPhysicalFormat,
        mediaType: String,
        byteCount: Int,
        sha256: String,
        completeness: AgentDataIngestCompleteness
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.artifactKind = artifactKind
        self.platform = platform
        self.artifactSchema = artifactSchema
        self.artifactSchemaVersion = artifactSchemaVersion
        self.ownerDate = ownerDate
        self.physicalFormat = physicalFormat
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.completeness = completeness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        artifactKind = try container.decode(AgentDataIngestArtifactKind.self, forKey: .artifactKind)
        platform = try container.decode(String.self, forKey: .platform)
        artifactSchema = try container.decode(String.self, forKey: .artifactSchema)
        artifactSchemaVersion = try container.decode(Int.self, forKey: .artifactSchemaVersion)
        ownerDate = try container.decode(String.self, forKey: .ownerDate)
        physicalFormat = try container.decode(AgentDataIngestPhysicalFormat.self, forKey: .physicalFormat)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
        completeness = try container.decode(AgentDataIngestCompleteness.self, forKey: .completeness)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(artifactKind, forKey: .artifactKind)
        try container.encode(platform, forKey: .platform)
        try container.encode(artifactSchema, forKey: .artifactSchema)
        try container.encode(artifactSchemaVersion, forKey: .artifactSchemaVersion)
        try container.encode(ownerDate, forKey: .ownerDate)
        try container.encode(physicalFormat, forKey: .physicalFormat)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(sha256, forKey: .sha256)
        try container.encode(completeness, forKey: .completeness)
    }

    /// Strict grammar validation mirroring the JSON schema semantics the
    /// gateway applies: unknown fields are impossible by construction, so
    /// this checks values, bounds, and cross-field rules only.
    func validate() throws {
        guard schema == Self.schema else { throw ValidationError.wrongSchema }
        guard schemaVersion == Self.schemaVersion else { throw ValidationError.wrongSchemaVersion }
        guard platform == "apple" || platform == "android" else { throw ValidationError.wrongPlatform }
        guard !artifactSchema.isEmpty, artifactSchema.utf8.count <= 128 else {
            throw ValidationError.emptyArtifactSchema
        }
        guard artifactSchemaVersion >= 1 else { throw ValidationError.emptyArtifactSchema }
        guard !ownerDate.isEmpty, Self.isISODate(ownerDate) else { throw ValidationError.invalidOwnerDateFormat }
        guard !mediaType.isEmpty, mediaType.utf8.count <= 128 else { throw ValidationError.emptyMediaType }
        guard byteCount >= 1 else { throw ValidationError.emptyByteCount }
        guard byteCount <= Self.maximumByteCount else { throw ValidationError.oversizedByteCount }
        guard Self.isLowercaseSHA256(sha256) else { throw ValidationError.invalidDigest }
        switch completeness {
        case .complete:
            break
        case .partial(let finalized, let coveredOwnerDates):
            guard finalized else { throw ValidationError.unfinalizedPartial }
            guard !coveredOwnerDates.isEmpty else { throw ValidationError.emptyCoveredOwnerDates }
            guard coveredOwnerDates.count <= Self.maximumCoveredOwnerDates else {
                throw ValidationError.tooManyCoveredOwnerDates
            }
            guard coveredOwnerDates.allSatisfy(Self.isISODate) else {
                throw ValidationError.invalidOwnerDateFormat
            }
            guard Set(coveredOwnerDates).count == coveredOwnerDates.count else {
                throw ValidationError.duplicateCoveredOwnerDates
            }
        }
        switch artifactKind {
        case .rawSnapshot, .rawChanges:
            // Structurally incomplete raw artifacts are rejected by the contract.
            guard case .complete = completeness else { throw ValidationError.partialRawArtifact }
        case .healthDataDaily, .externalProviderDaily:
            break
        }
    }

    /// Encodes the exact one-line manifest document. Compact JSON with sorted
    /// keys; never contains a raw newline, so the framing separator stays
    /// unambiguous.
    func encodedLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        precondition(!data.contains(0x0A), "manifest encoding must stay on one line")
        return data
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }

    static func isISODate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return false }
        let digits = bytes.enumerated().filter { $0.offset != 4 && $0.offset != 7 }.map(\.element)
        guard digits.allSatisfy({ (48...57).contains($0) }) else { return false }
        var components = DateComponents()
        components.year = Int(String(decoding: bytes[0...3], as: UTF8.self))
        components.month = Int(String(decoding: bytes[5...6], as: UTF8.self))
        components.day = Int(String(decoding: bytes[8...9], as: UTF8.self))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components) != nil
            && (1...12).contains(components.month ?? 0)
            && (1...31).contains(components.day ?? 0)
    }
}

/// Manifest construction over exact artifact bytes: byte_count and sha256 are
/// always computed over the exact uploaded bytes, never declared separately.
nonisolated enum AgentDataIngestManifestBuilder {
    /// Builds a manifest for a complete artifact already materialized as bytes.
    static func manifest(
        kind: AgentDataIngestArtifactKind,
        platform: String,
        artifactSchema: String,
        artifactSchemaVersion: Int,
        ownerDate: String,
        physicalFormat: AgentDataIngestPhysicalFormat,
        mediaType: String,
        artifactBytes: Data,
        completeness: AgentDataIngestCompleteness = .complete
    ) throws -> AgentDataIngestManifest {
        let manifest = AgentDataIngestManifest(
            artifactKind: kind,
            platform: platform,
            artifactSchema: artifactSchema,
            artifactSchemaVersion: artifactSchemaVersion,
            ownerDate: ownerDate,
            physicalFormat: physicalFormat,
            mediaType: mediaType,
            byteCount: artifactBytes.count,
            sha256: AgentDataIngestManifest.sha256(of: artifactBytes),
            completeness: completeness
        )
        try manifest.validate()
        return manifest
    }

    /// Builds a manifest for an artifact on disk, streaming the digest so a
    /// 64 MiB artifact is never held in memory just to describe it.
    static func manifest(
        kind: AgentDataIngestArtifactKind,
        platform: String,
        artifactSchema: String,
        artifactSchemaVersion: Int,
        ownerDate: String,
        physicalFormat: AgentDataIngestPhysicalFormat,
        mediaType: String,
        artifactFileURL: URL,
        completeness: AgentDataIngestCompleteness = .complete
    ) throws -> AgentDataIngestManifest {
        let (byteCount, sha256) = try AgentDataIngestManifest.digestFile(at: artifactFileURL)
        let manifest = AgentDataIngestManifest(
            artifactKind: kind,
            platform: platform,
            artifactSchema: artifactSchema,
            artifactSchemaVersion: artifactSchemaVersion,
            ownerDate: ownerDate,
            physicalFormat: physicalFormat,
            mediaType: mediaType,
            byteCount: byteCount,
            sha256: sha256,
            completeness: completeness
        )
        try manifest.validate()
        return manifest
    }
}

extension AgentDataIngestManifest {
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streams the exact file bytes once, returning `(byteCount, sha256)`.
    static func digestFile(at url: URL) throws -> (byteCount: Int, sha256: String) {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        let expected = size.uint64Value

        let chunkSize = 128 * 1_024
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: chunkSize,
            alignment: MemoryLayout<UInt64>.alignment
        )
        defer { buffer.deallocate() }

        var hasher = SHA256()
        var total: UInt64 = 0
        while true {
            var count: Int
            repeat {
                count = Darwin.read(descriptor, buffer, chunkSize)
            } while count < 0 && errno == EINTR
            guard count >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            hasher.update(data: Data(bytes: buffer, count: count))
            total += UInt64(count)
        }
        guard total == expected else { throw CocoaError(.fileReadCorruptFile) }
        guard let byteCount = Int(exactly: total) else { throw CocoaError(.fileReadTooLarge) }
        return (byteCount, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

// MARK: - Receipts

/// The stable health-free rejection codes of `healthmd.agent_ingest_response`
/// v1. Exactly four exist; no new codes may be added.
nonisolated enum AgentDataIngestRejectionCode: String, Codable, Equatable, Sendable, CaseIterable {
    case truncated
    case transient
    case checksumInvalid = "checksum_invalid"
    case manifestIncomplete = "manifest_incomplete"

    /// The three fix-and-reupload classes: the client never auto-retries them.
    var isFixAndReupload: Bool {
        switch self {
        case .truncated, .checksumInvalid, .manifestIncomplete:
            return true
        case .transient:
            return false
        }
    }
}

/// The authoritative completeness view echoed back inside an accepted receipt.
nonisolated struct AgentDataIngestStoredRevision: Codable, Equatable, Sendable {
    let revisionID: String
    let byteCount: Int
    let completeness: AgentDataIngestCompleteness

    private enum CodingKeys: String, CodingKey {
        case revisionID = "revision_id"
        case byteCount = "byte_count"
        case completeness
    }
}

/// One `healthmd.agent_ingest_response` v1 receipt. Health-free: outcome,
/// stored revision identity, and the authoritative partition view only.
nonisolated struct AgentDataIngestReceipt: Equatable, Sendable {
    static let schema = "healthmd.agent_ingest_response"
    static let schemaVersion = 1

    let outcome: Outcome
    let stored: AgentDataIngestStoredRevision?
    let rejection: AgentDataIngestRejectionCode?
    /// The receipt's partition owner date, when the gateway reported one.
    let partitionOwnerDate: String?

    enum Outcome: Equatable, Sendable {
        case accepted
        case rejected(AgentDataIngestRejectionCode)
    }

    enum DecodingError: String, Error, Equatable {
        case wrongSchema
        case wrongSchemaVersion
        case invalidOutcome
        case missingRejection
        case rejectionOnAccepted
        case missingStored
        case storedOnRejected
    }

    private struct WireBody: Decodable {
        let schema: String
        let schema_version: Int
        let outcome: String
        let stored: WireStored?
        let rejection: WireRejection?
        let partition: WirePartition?

        struct WireStored: Decodable {
            let revision_id: String
            let byte_count: Int
            let completeness: AgentDataIngestCompleteness
        }

        struct WireRejection: Decodable {
            let code: String
        }

        struct WirePartition: Decodable {
            let owner_date: String?
        }
    }

    init(outcome: Outcome, stored: AgentDataIngestStoredRevision?, rejection: AgentDataIngestRejectionCode?, partitionOwnerDate: String?) {
        self.outcome = outcome
        self.stored = stored
        self.rejection = rejection
        self.partitionOwnerDate = partitionOwnerDate
    }

    init(decoding data: Data) throws {
        let body = try JSONDecoder().decode(WireBody.self, from: data)
        guard body.schema == Self.schema else { throw DecodingError.wrongSchema }
        guard body.schema_version == Self.schemaVersion else { throw DecodingError.wrongSchemaVersion }
        switch body.outcome {
        case "accepted":
            guard let stored = body.stored else { throw DecodingError.missingStored }
            guard body.rejection == nil else { throw DecodingError.rejectionOnAccepted }
            self.outcome = .accepted
            self.stored = AgentDataIngestStoredRevision(
                revisionID: stored.revision_id,
                byteCount: stored.byte_count,
                completeness: stored.completeness
            )
            self.rejection = nil
        case "rejected":
            guard let code = body.rejection?.code,
                  let rejection = AgentDataIngestRejectionCode(rawValue: code) else {
                throw DecodingError.missingRejection
            }
            guard body.stored == nil else { throw DecodingError.storedOnRejected }
            self.outcome = .rejected(rejection)
            self.stored = nil
            self.rejection = rejection
        default:
            throw DecodingError.invalidOutcome
        }
        self.partitionOwnerDate = body.partition?.owner_date
    }
}

// MARK: - Destination

/// Validation and privacy-safe display helpers for user-configured Agent
/// Data gateway endpoints. Mirrors `APIExportSettings` storage/validation/
/// redaction patterns and the Android `APIExportEndpoint` twin semantics:
/// non-empty, no CR/LF, scheme http or https, host present, no user info or
/// fragment; errors are health-free.
nonisolated enum AgentDataGatewayEndpoint {
    static func normalizedEndpointString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\r"), !trimmed.contains("\n") else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.user == nil, components.password == nil, components.fragment == nil else {
            return nil
        }
        components.scheme = scheme
        guard let normalized = components.url?.absoluteString else { return nil }
        return normalized
    }

    static func isConfigured(_ value: String) -> Bool {
        normalizedEndpointString(value) != nil
    }

    static func displayName(_ value: String) -> String {
        guard let normalized = normalizedEndpointString(value),
              let url = URL(string: normalized),
              let host = url.host, !host.isEmpty else {
            return String(localized: "Configure gateway", comment: "Fallback label when no Agent Data gateway endpoint is configured")
        }
        return host
    }

    /// A privacy-safe label for history and diagnostics. User info, query
    /// parameters, and fragments may contain credentials and are never copied
    /// into persisted display metadata.
    static func redactedDescription(
        _ value: String,
        fallback: String = String(localized: "No gateway configured", comment: "Fallback label when no Agent Data gateway endpoint is configured")
    ) -> String {
        guard let normalized = normalizedEndpointString(value),
              let url = URL(string: normalized),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return fallback
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? fallback
    }
}

/// Immutable request-scoped gateway destination used by every upload in one
/// gateway export. The ingest URL is the user's base URL with the frozen
/// `/v1/ingest` path appended.
nonisolated struct AgentDataGatewayDestinationSnapshot: Equatable, Sendable {
    /// The frozen single request path of the ingestion surface.
    static let ingestPath = "/v1/ingest"
    /// Required media type of the framed ingestion request body.
    static let ingestMediaType = "application/x-healthmd-agent-data-ingest"

    let endpointBaseURL: URL
    let ingestURL: URL
    let displayName: String
    let redactedEndpointDescription: String

    init?(endpointURLString: String) {
        guard let normalized = AgentDataGatewayEndpoint.normalizedEndpointString(endpointURLString),
              let base = URL(string: normalized),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let baseHasTrailingSlash = components.path.hasSuffix("/")
        components.path = baseHasTrailingSlash
            ? String(components.path.dropLast()) + Self.ingestPath
            : components.path + Self.ingestPath
        guard let ingest = components.url else { return nil }
        self.endpointBaseURL = base
        self.ingestURL = ingest
        self.displayName = AgentDataGatewayEndpoint.displayName(endpointURLString)
        self.redactedEndpointDescription = AgentDataGatewayEndpoint.redactedDescription(endpointURLString)
    }
}
