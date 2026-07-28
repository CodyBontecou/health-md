import Foundation

public enum HealthMdDirectProtocol {
    public static let currentVersion = 1
    public static let queryVersion = 3
    public static let serviceType = "healthmd-cli"
    public static let defaultManualIPPort: UInt16 = 17_647
    public static let jobLifetime: TimeInterval = 7 * 24 * 60 * 60
    /// Pairing/control packets and a base64-wrapped 512 KiB transfer frame fit
    /// below this direct-only pre-authentication allocation ceiling.
    public static let maximumPacketBytes = 2 * 1_024 * 1_024

    /// iPhone treats the receiving desktop path as a bounded opaque label. The desktop client is
    /// responsible for native absolute-path, symlink, and filesystem-identity validation.
    public static func isValidDesktopDestinationLabel(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 4_096
            && value.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 0x20 && scalar.value != 0x7f
            }
    }
}

public enum DirectTransportKind: String, Codable, CaseIterable, Equatable, Sendable {
    case manualIP = "manual-ip"
    case nearby
}

public enum DirectPeerPlatform: String, Codable, Equatable, Sendable {
    case iOS = "ios"
    case macOSCLI = "macos_cli"
}

public enum DirectJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([DirectJSONValue])
    case object([String: DirectJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Non-finite JSON number")
            }
            self = .number(value)
        } else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([DirectJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: DirectJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Non-finite JSON number"))
            }
            try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public enum DirectQueryDetailLevel: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case summary
    case lossless
}

public struct DirectQueryCapabilities: Codable, Equatable, Sendable {
    public let schemaVersions: [Int]
    public let operations: [String]
    public let detailLevels: [DirectQueryDetailLevel]
    public let maximumPageItems: Int
    public let maximumPageBytes: Int
    public let supportsEvidenceValues: Bool

    public static let current = Self(
        schemaVersions: [1],
        operations: [
            "metric_series", "period_comparison", "workout_listing",
            "sleep_session_listing", "workout_sleep_alignment",
            "source_record_listing", "coverage", "derive_packet"
        ],
        detailLevels: DirectQueryDetailLevel.allCases,
        maximumPageItems: 1_000,
        maximumPageBytes: 1 * 1_024 * 1_024,
        supportsEvidenceValues: true
    )

    public init(
        schemaVersions: [Int],
        operations: [String],
        detailLevels: [DirectQueryDetailLevel],
        maximumPageItems: Int,
        maximumPageBytes: Int,
        supportsEvidenceValues: Bool
    ) {
        self.schemaVersions = Array(Set(schemaVersions)).sorted()
        self.operations = Array(Set(operations)).sorted()
        self.detailLevels = Array(Set(detailLevels)).sorted { $0.rawValue < $1.rawValue }
        self.maximumPageItems = maximumPageItems
        self.maximumPageBytes = maximumPageBytes
        self.supportsEvidenceValues = supportsEvidenceValues
    }
}

public struct DirectPeerCapabilities: Codable, Equatable, Sendable {
    public let protocolVersions: [Int]
    public let platform: DirectPeerPlatform
    public let installationID: UUID
    public let supportedRawProfiles: [DirectRawProfile]
    public let supportsDurableJobs: Bool
    public let supportsCanonicalExtraction: Bool
    public let transfer: DirectTransferCapabilities
    public let query: DirectQueryCapabilities?

    public init(
        protocolVersions: [Int] = [HealthMdDirectProtocol.currentVersion],
        platform: DirectPeerPlatform,
        installationID: UUID,
        supportedRawProfiles: [DirectRawProfile] = DirectRawProfile.allCases,
        supportsDurableJobs: Bool = true,
        supportsCanonicalExtraction: Bool = true,
        transfer: DirectTransferCapabilities = .current,
        query: DirectQueryCapabilities? = nil
    ) {
        self.protocolVersions = Array(Set(protocolVersions)).sorted()
        self.platform = platform
        self.installationID = installationID
        self.supportedRawProfiles = Array(Set(supportedRawProfiles)).sorted { $0.rawValue < $1.rawValue }
        self.supportsDurableJobs = supportsDurableJobs
        self.supportsCanonicalExtraction = supportsCanonicalExtraction
        self.transfer = transfer
        self.query = query
    }

    public func negotiatedProtocolVersion(with peer: Self) -> Int? {
        Set(protocolVersions).intersection(peer.protocolVersions).max()
    }
}

public struct DirectPeerBinding: Codable, Equatable, Hashable, Sendable {
    public let sourceInstallationID: UUID
    public let destinationInstallationID: UUID

    public init(sourceInstallationID: UUID, destinationInstallationID: UUID) {
        self.sourceInstallationID = sourceInstallationID
        self.destinationInstallationID = destinationInstallationID
    }
}

public enum DirectSettingsPolicy: String, Codable, Equatable, Sendable {
    case requestedDatesOnly = "requested_dates_only"
    case currentIPhoneSettings = "current_iphone_settings"
}

public enum DirectResponseMode: String, Codable, Equatable, Sendable {
    case rawJSON = "raw_json"
    case writeFiles = "write_files"
}

public enum DirectRawProfile: String, Codable, CaseIterable, Equatable, Sendable {
    case canonicalSourceRecordsV1 = "canonical_source_records_v1"
    case healthDataProjection = "health_data_projection"
}

public enum DirectDetailLevel: String, Codable, Equatable, Sendable {
    case summary
    case lossless
}

public enum DirectDateSelection: Codable, Equatable, Sendable {
    case exact(start: String, end: String)
    case allAvailable
}

public struct DirectCanonicalSelection: Codable, Equatable, Sendable {
    public let metricIDs: [String]
    public let categories: [String]
    public let sourceIDs: [String]
    public let objectPaths: [String]
    public let fieldPointers: [String]
    public let allMetrics: Bool
    public let detailLevel: DirectDetailLevel

    public init(
        metricIDs: [String] = [],
        categories: [String] = [],
        sourceIDs: [String] = ["apple_health"],
        objectPaths: [String] = [],
        fieldPointers: [String] = [],
        allMetrics: Bool = false,
        detailLevel: DirectDetailLevel = .summary
    ) {
        self.metricIDs = Array(Set(metricIDs)).sorted()
        self.categories = Array(Set(categories)).sorted()
        self.sourceIDs = Array(Set(sourceIDs)).sorted()
        self.objectPaths = objectPaths
        self.fieldPointers = fieldPointers
        self.allMetrics = allMetrics
        self.detailLevel = detailLevel
    }
}

public struct DirectExportDestination: Codable, Equatable, Sendable {
    /// Explicit Mac destination selected by the CLI caller. It is carried only
    /// inside the authenticated channel and bound into the immutable job hash.
    public let rootPath: String

    public init(rootPath: String) {
        self.rootPath = rootPath
    }
}

public struct DirectExportRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let jobID: UUID
    public let createdAt: Date
    public let dateSelection: DirectDateSelection
    public let settingsPolicy: DirectSettingsPolicy
    public let responseMode: DirectResponseMode
    public let rawProfile: DirectRawProfile?
    public let canonicalSelection: DirectCanonicalSelection?
    public let destination: DirectExportDestination?

    public init(
        protocolVersion: Int = HealthMdDirectProtocol.currentVersion,
        jobID: UUID,
        createdAt: Date,
        dateSelection: DirectDateSelection,
        settingsPolicy: DirectSettingsPolicy = .requestedDatesOnly,
        responseMode: DirectResponseMode,
        rawProfile: DirectRawProfile? = nil,
        canonicalSelection: DirectCanonicalSelection? = nil,
        destination: DirectExportDestination? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.jobID = jobID
        // JSONEncoder's ISO-8601 strategy has whole-second precision. Pin the
        // immutable request before fingerprinting so both peers hash the exact
        // same value after a wire round trip.
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
        self.dateSelection = dateSelection
        self.settingsPolicy = settingsPolicy
        self.responseMode = responseMode
        self.rawProfile = rawProfile
        self.canonicalSelection = canonicalSelection
        self.destination = destination
    }
}

public struct DirectQueryRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let createdAt: Date
    public let detailLevel: DirectQueryDetailLevel
    public let query: DirectJSONValue

    public init(
        protocolVersion: Int = HealthMdDirectProtocol.queryVersion,
        requestID: UUID,
        createdAt: Date = Date(),
        detailLevel: DirectQueryDetailLevel,
        query: DirectJSONValue
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.createdAt = Date(timeIntervalSince1970: floor(createdAt.timeIntervalSince1970))
        self.detailLevel = detailLevel
        self.query = query
    }
}

public struct DirectQueryResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let response: DirectJSONValue

    public init(requestID: UUID, response: DirectJSONValue) {
        self.requestID = requestID
        self.response = response
    }
}

public struct DirectQueryFailure: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let code: String
    public let message: String
    public let retryable: Bool

    public init(requestID: UUID, code: String, message: String, retryable: Bool = false) {
        self.requestID = requestID
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public struct DirectStatusRequest: Codable, Equatable, Sendable {
    public let requestedAt: Date

    public init(requestedAt: Date = Date()) {
        self.requestedAt = requestedAt
    }
}

public struct DirectIPhoneStatus: Codable, Equatable, Sendable {
    public let name: String
    public let appActive: Bool
    public let protectedDataAvailable: Bool
    public let exportInProgress: Bool
    public let canTriggerRawExports: Bool
    public let canTriggerFileExports: Bool
    public let queryInProgress: Bool?
    public let canTriggerQueries: Bool?
    public let activeJobID: UUID?
    public let activeQueryRequestID: UUID?
    public let message: String?

    public init(
        name: String,
        appActive: Bool,
        protectedDataAvailable: Bool,
        exportInProgress: Bool,
        canTriggerRawExports: Bool,
        canTriggerFileExports: Bool,
        queryInProgress: Bool? = nil,
        canTriggerQueries: Bool? = nil,
        activeJobID: UUID? = nil,
        activeQueryRequestID: UUID? = nil,
        message: String? = nil
    ) {
        self.name = name
        self.appActive = appActive
        self.protectedDataAvailable = protectedDataAvailable
        self.exportInProgress = exportInProgress
        self.canTriggerRawExports = canTriggerRawExports
        self.canTriggerFileExports = canTriggerFileExports
        self.queryInProgress = queryInProgress
        self.canTriggerQueries = canTriggerQueries
        self.activeJobID = activeJobID
        self.activeQueryRequestID = activeQueryRequestID
        self.message = message
    }
}

public struct DirectExportAccepted: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let acceptedAt: Date
    public let peerBinding: DirectPeerBinding
    /// Immutable source-calendar resolution pinned before any corpus bytes are sent.
    public let resolvedDateIdentifiers: [String]
    public let sourceDeviceName: String
    public let sourceTimeZoneIdentifier: String
    /// Categories and `all_metrics` are resolved by iPhone into explicit metric IDs.
    public let resolvedCanonicalSelection: DirectCanonicalSelection?

    public init(
        jobID: UUID,
        acceptedAt: Date,
        peerBinding: DirectPeerBinding,
        resolvedDateIdentifiers: [String] = [],
        sourceDeviceName: String = "iPhone",
        sourceTimeZoneIdentifier: String = TimeZone.current.identifier,
        resolvedCanonicalSelection: DirectCanonicalSelection? = nil
    ) {
        self.jobID = jobID
        self.acceptedAt = acceptedAt
        self.peerBinding = peerBinding
        self.resolvedDateIdentifiers = resolvedDateIdentifiers
        self.sourceDeviceName = sourceDeviceName
        self.sourceTimeZoneIdentifier = sourceTimeZoneIdentifier
        self.resolvedCanonicalSelection = resolvedCanonicalSelection
    }
}

/// Small, bounded metadata for one canonical raw day. The potentially very
/// large `health_data` JSON document is transferred separately as partitioned
/// binary bytes and is inserted into the final response by the receiver.
public struct DirectRawDayManifest: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let date: String
    public let status: String
    public let captureStatus: String?
    public let sampleCount: Int
    public let recordCount: Int
    public let queryStatusCounts: [String: Int]
    public let integrityWarningCount: Int
    public let integrityWarningCodes: [String]
    public let partialFailureCount: Int
    public let partialFailureTypes: [String]
    public let failureCode: String?
    public let healthDataByteCount: Int64
    public let healthDataSHA256: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case date, status
        case captureStatus = "capture_status"
        case sampleCount = "sample_count"
        case recordCount = "record_count"
        case queryStatusCounts = "query_status_counts"
        case integrityWarningCount = "integrity_warning_count"
        case integrityWarningCodes = "integrity_warning_codes"
        case partialFailureCount = "partial_failure_count"
        case partialFailureTypes = "partial_failure_types"
        case failureCode = "failure_code"
        case healthDataByteCount = "health_data_byte_count"
        case healthDataSHA256 = "health_data_sha256"
    }

    public init(
        jobID: UUID,
        date: String,
        status: String,
        captureStatus: String? = nil,
        sampleCount: Int,
        recordCount: Int,
        queryStatusCounts: [String: Int],
        integrityWarningCount: Int,
        integrityWarningCodes: [String],
        partialFailureCount: Int,
        partialFailureTypes: [String],
        failureCode: String? = nil,
        healthDataByteCount: Int64,
        healthDataSHA256: String?
    ) throws {
        let validStatuses = Set([
            "complete", "complete_empty", "complete_with_warnings", "partial",
            "failed", "cancelled", "missing"
        ])
        guard !date.isEmpty,
              validStatuses.contains(status),
              sampleCount >= 0,
              recordCount >= 0,
              queryStatusCounts.values.allSatisfy({ $0 >= 0 }),
              integrityWarningCount >= 0,
              partialFailureCount >= 0,
              healthDataByteCount >= 0,
              healthDataSHA256.map(\.isHealthMdSHA256) ?? (healthDataByteCount == 0),
              (healthDataByteCount > 0) == (healthDataSHA256 != nil) else {
            throw DirectTransferError.invalidRawDayManifest
        }
        self.jobID = jobID
        self.date = date
        self.status = status
        self.captureStatus = captureStatus
        self.sampleCount = sampleCount
        self.recordCount = recordCount
        self.queryStatusCounts = queryStatusCounts
        self.integrityWarningCount = integrityWarningCount
        self.integrityWarningCodes = integrityWarningCodes
        self.partialFailureCount = partialFailureCount
        self.partialFailureTypes = partialFailureTypes
        self.failureCode = failureCode
        self.healthDataByteCount = healthDataByteCount
        self.healthDataSHA256 = healthDataSHA256
    }
}

public enum DirectExportFileWriteMode: String, Codable, Equatable, Sendable {
    case overwrite
    case append
    case mergeMarkdown = "merge_markdown"
    case mergeMarkdownPreservingPreamble = "merge_markdown_preserving_preamble"
}

public struct DirectExportFileManifest: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let fileID: UUID
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public let writeMode: DirectExportFileWriteMode

    public init(
        jobID: UUID,
        fileID: UUID,
        relativePath: String,
        byteCount: Int64,
        sha256: String,
        writeMode: DirectExportFileWriteMode
    ) throws {
        guard !relativePath.isEmpty,
              relativePath.utf8.count <= 4_096,
              byteCount >= 0,
              sha256.isHealthMdSHA256 else {
            throw DirectTransferError.invalidFileManifest
        }
        self.jobID = jobID
        self.fileID = fileID
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.writeMode = writeMode
    }
}

public struct DirectExportProgress: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let processedDays: Int
    public let totalDays: Int
    public let currentDate: String?
    public let committedPartitions: Int
    public let committedBytes: Int64
    public let message: String

    public init(
        jobID: UUID,
        processedDays: Int,
        totalDays: Int,
        currentDate: String?,
        committedPartitions: Int,
        committedBytes: Int64,
        message: String
    ) {
        self.jobID = jobID
        self.processedDays = processedDays
        self.totalDays = totalDays
        self.currentDate = currentDate
        self.committedPartitions = committedPartitions
        self.committedBytes = committedBytes
        self.message = message
    }
}

public enum DirectExportFailureReason: String, Codable, Equatable, Sendable {
    case unsupportedPeer = "unsupported_peer"
    case invalidRequest = "invalid_request"
    case healthKitUnavailable = "healthkit_unavailable"
    case healthKitNotAuthorized = "healthkit_not_authorized"
    case protectedDataUnavailable = "protected_data_unavailable"
    case exportLimitReached = "export_limit_reached"
    case requestInProgress = "request_in_progress"
    case cancelled
    case internalFailure = "internal_failure"
}

public struct DirectExportFailure: Codable, Equatable, Sendable {
    public let jobID: UUID?
    public let reason: DirectExportFailureReason
    public let message: String

    public init(jobID: UUID?, reason: DirectExportFailureReason, message: String) {
        self.jobID = jobID
        self.reason = reason
        self.message = message
    }
}

public enum DirectMessage: Codable, Equatable, Sendable {
    case hello(DirectPeerCapabilities)
    case statusRequest(DirectStatusRequest)
    case statusResponse(DirectIPhoneStatus)
    case exportRequest(DirectExportRequest)
    case queryRequest(DirectQueryRequest)
    case queryResponse(DirectQueryResponse)
    case queryRejected(DirectQueryFailure)
    case exportAccepted(DirectExportAccepted)
    case exportProgress(DirectExportProgress)
    case exportRejected(DirectExportFailure)
    case transferSession(DirectTransferSession)
    case rawDayManifest(DirectRawDayManifest)
    case fileManifest(DirectExportFileManifest)
    case transferOpen(DirectTransferOpen)
    case transferDisposition(DirectTransferDisposition)
    case transferChunk(DirectTransferChunk)
    case transferChunkAcknowledgement(DirectTransferChunkAcknowledgement)
    case transferPartitionComplete(DirectTransferPartitionComplete)
    case transferPartitionAcknowledgement(DirectTransferPartitionAcknowledgement)
    case transferFinalize(DirectTransferFinalize)
    case transferFinalAcknowledgement(DirectTransferFinalAcknowledgement)
    case completionConfirmed(jobID: UUID)
    case cancel(jobID: UUID)
    case cancelAcknowledged(jobID: UUID)
    case ping
    case pong
}
