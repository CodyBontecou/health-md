import Foundation

// MARK: - Sync Message Protocol

/// Messages exchanged between iOS and macOS over Multipeer Connectivity.
enum SyncMessage: Codable {
    /// macOS → iOS: Request health data for specific dates.
    /// Legacy cache sync; kept for mixed-version compatibility.
    case requestData(dates: [Date])

    /// macOS → iOS: Request ALL available health data (all time).
    /// Legacy cache sync; kept for mixed-version compatibility.
    case requestAllData

    /// iOS → macOS: Health data payload.
    /// Legacy cache sync; kept for mixed-version compatibility.
    case healthData(SyncPayload)

    /// iOS → macOS: Progress update during a large sync (e.g., all-time).
    /// Legacy cache sync; kept for mixed-version compatibility.
    case syncProgress(SyncProgressInfo)

    /// Both directions: protocol/capability announcement for v2 sync.
    case hello(SyncPeerCapabilities)

    /// macOS → iOS: current destination-folder/readiness status.
    case macStatus(MacDestinationStatus)

    /// iOS → macOS: complete export job with HealthKit records and iOS settings.
    case macExportRequest(MacExportJob)

    /// iOS → macOS: start a chunked Mac export stream.
    case macExportStreamStart(MacExportStreamStart)

    /// iOS → macOS: send one chunk of a Mac export stream.
    case macExportStreamChunk(MacExportStreamChunk)

    /// macOS → iOS: acknowledge one chunk of a Mac export stream.
    case macExportStreamChunkAck(MacExportStreamChunkAck)

    /// iOS → macOS: complete a chunked Mac export stream.
    case macExportStreamComplete(MacExportStreamComplete)

    /// iOS → macOS: abort a chunked Mac export stream.
    case macExportStreamAbort(MacExportStreamAbort)

    /// macOS → iOS: job accepted and will be processed.
    case macExportAccepted(MacExportAcknowledgement)

    /// macOS → iOS: per-job progress update.
    case macExportProgress(MacExportProgress)

    /// macOS → iOS: final structured job result.
    case macExportResult(MacExportResultPayload)

    /// iOS → macOS: cancel an active Mac export job.
    case macExportCancel(jobID: UUID)


    /// macOS → iOS: structured failure before or during job execution.
    case macExportFailed(MacExportFailure)

    /// macOS → iOS: ask an open iPhone app to prepare a Mac export for the requested dates.
    case iphoneExportRequest(IPhoneExportRequest)

    /// iOS → macOS: the iPhone accepted a Mac-initiated export request and is preparing HealthKit data.
    case iphoneExportAccepted(IPhoneExportAcknowledgement)

    /// iOS → macOS: progress while the iPhone fetches HealthKit data and builds the Mac export job.
    case iphoneExportPreparationProgress(IPhoneExportPreparationProgress)

    /// iOS → macOS: raw HealthKit records for a Mac-initiated request that should not write files.
    case iphoneExportRawData(IPhoneExportRawDataPayload)

    /// macOS → iOS: cancel an active Mac-initiated iPhone export request.
    case iphoneExportCancel(jobID: UUID)

    /// iOS → macOS: the iPhone rejected or failed a Mac-initiated export before sending a Mac export job.
    case iphoneExportRejected(IPhoneExportFailure)

    /// Keepalive / connection test.
    case ping

    /// Response to ping.
    case pong
}

extension SyncMessage {
    /// Payload-free name for operational logging. Raw health records must never
    /// be interpolated into app or control-server logs.
    var operationalName: String {
        switch self {
        case .requestData: return "requestData"
        case .requestAllData: return "requestAllData"
        case .healthData: return "healthData"
        case .syncProgress: return "syncProgress"
        case .hello: return "hello"
        case .macStatus: return "macStatus"
        case .macExportRequest: return "macExportRequest"
        case .macExportStreamStart: return "macExportStreamStart"
        case .macExportStreamChunk: return "macExportStreamChunk"
        case .macExportStreamChunkAck: return "macExportStreamChunkAck"
        case .macExportStreamComplete: return "macExportStreamComplete"
        case .macExportStreamAbort: return "macExportStreamAbort"
        case .macExportAccepted: return "macExportAccepted"
        case .macExportProgress: return "macExportProgress"
        case .macExportResult: return "macExportResult"
        case .macExportCancel: return "macExportCancel"
        case .macExportFailed: return "macExportFailed"
        case .iphoneExportRequest: return "iphoneExportRequest"
        case .iphoneExportAccepted: return "iphoneExportAccepted"
        case .iphoneExportPreparationProgress: return "iphoneExportPreparationProgress"
        case .iphoneExportRawData: return "iphoneExportRawData"
        case .iphoneExportCancel: return "iphoneExportCancel"
        case .iphoneExportRejected: return "iphoneExportRejected"
        case .ping: return "ping"
        case .pong: return "pong"
        }
    }
}

// MARK: - v2 Capabilities + Destination Status

enum SyncPlatform: String, Codable, Equatable {
    case iOS
    case macOS

    static var current: SyncPlatform {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }
}

struct SyncPeerCapabilities: Codable, Equatable {
    static let currentProtocolVersion = 2

    let protocolVersion: Int
    let appVersion: String?
    let buildNumber: String?
    let platform: SyncPlatform
    let supportsMacExportJobs: Bool
    let supportsMacDestinationStatus: Bool
    let supportsJobCancellation: Bool
    let supportsGranularPayloads: Bool
    /// Older Mac builds can accept v2 Mac export jobs but silently ignore roll-up
    /// settings because the executor did not write derived summaries yet.
    let supportsRollupSummaries: Bool
    /// Whether this peer understands roll-up jobs that intentionally skip daily records.
    let supportsSummaryOnlyExports: Bool
    /// Whether this peer can participate in Mac-initiated requests that ask an
    /// already-open iPhone app to prepare a Mac export job.
    let supportsIPhoneExportRequests: Bool
    /// Whether this peer understands additive chunked Mac export job streaming.
    let supportsChunkedMacExportJobs: Bool
    /// Whether this peer supports the manual IP/Tailscale sync transport in
    /// addition to Multipeer nearby discovery.
    let supportsManualIPSync: Bool
    /// Whether manual IP/Tailscale sync requires an out-of-band pairing code.
    let manualIPSyncRequiresPairing: Bool
    /// Canonical `healthmd.healthkit_records` archive schema versions this peer can produce/consume.
    let canonicalArchiveSchemaVersions: [Int]
    /// Versioned strict CLI raw-result envelope schema versions this peer can produce/consume.
    let canonicalRawResultSchemaVersions: [Int]

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case appVersion
        case buildNumber
        case platform
        case supportsMacExportJobs
        case supportsMacDestinationStatus
        case supportsJobCancellation
        case supportsGranularPayloads
        case supportsRollupSummaries
        case supportsSummaryOnlyExports
        case supportsIPhoneExportRequests
        case supportsChunkedMacExportJobs
        case supportsManualIPSync
        case manualIPSyncRequiresPairing
        case canonicalArchiveSchemaVersions
        case canonicalRawResultSchemaVersions
    }

    init(
        protocolVersion: Int,
        appVersion: String?,
        buildNumber: String?,
        platform: SyncPlatform,
        supportsMacExportJobs: Bool,
        supportsMacDestinationStatus: Bool,
        supportsJobCancellation: Bool,
        supportsGranularPayloads: Bool,
        supportsRollupSummaries: Bool = false,
        supportsSummaryOnlyExports: Bool = false,
        supportsIPhoneExportRequests: Bool = false,
        supportsChunkedMacExportJobs: Bool = false,
        supportsManualIPSync: Bool = false,
        manualIPSyncRequiresPairing: Bool = true,
        canonicalArchiveSchemaVersions: [Int] = [],
        canonicalRawResultSchemaVersions: [Int] = []
    ) {
        self.protocolVersion = protocolVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.platform = platform
        self.supportsMacExportJobs = supportsMacExportJobs
        self.supportsMacDestinationStatus = supportsMacDestinationStatus
        self.supportsJobCancellation = supportsJobCancellation
        self.supportsGranularPayloads = supportsGranularPayloads
        self.supportsRollupSummaries = supportsRollupSummaries
        self.supportsSummaryOnlyExports = supportsSummaryOnlyExports
        self.supportsIPhoneExportRequests = supportsIPhoneExportRequests
        self.supportsChunkedMacExportJobs = supportsChunkedMacExportJobs
        self.supportsManualIPSync = supportsManualIPSync
        self.manualIPSyncRequiresPairing = manualIPSyncRequiresPairing
        self.canonicalArchiveSchemaVersions = Array(Set(canonicalArchiveSchemaVersions)).sorted()
        self.canonicalRawResultSchemaVersions = Array(Set(canonicalRawResultSchemaVersions)).sorted()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber)
        platform = try container.decode(SyncPlatform.self, forKey: .platform)
        supportsMacExportJobs = try container.decode(Bool.self, forKey: .supportsMacExportJobs)
        supportsMacDestinationStatus = try container.decode(Bool.self, forKey: .supportsMacDestinationStatus)
        supportsJobCancellation = try container.decode(Bool.self, forKey: .supportsJobCancellation)
        supportsGranularPayloads = try container.decode(Bool.self, forKey: .supportsGranularPayloads)
        supportsRollupSummaries = try container.decodeIfPresent(Bool.self, forKey: .supportsRollupSummaries) ?? false
        supportsSummaryOnlyExports = try container.decodeIfPresent(Bool.self, forKey: .supportsSummaryOnlyExports) ?? false
        supportsIPhoneExportRequests = try container.decodeIfPresent(Bool.self, forKey: .supportsIPhoneExportRequests) ?? false
        supportsChunkedMacExportJobs = try container.decodeIfPresent(Bool.self, forKey: .supportsChunkedMacExportJobs) ?? false
        supportsManualIPSync = try container.decodeIfPresent(Bool.self, forKey: .supportsManualIPSync) ?? false
        manualIPSyncRequiresPairing = try container.decodeIfPresent(Bool.self, forKey: .manualIPSyncRequiresPairing) ?? true
        canonicalArchiveSchemaVersions = try container.decodeIfPresent(
            [Int].self,
            forKey: .canonicalArchiveSchemaVersions
        ) ?? []
        canonicalRawResultSchemaVersions = try container.decodeIfPresent(
            [Int].self,
            forKey: .canonicalRawResultSchemaVersions
        ) ?? []
    }

    var isCompatibleWithMacExportJobs: Bool {
        protocolVersion >= Self.currentProtocolVersion
            && supportsMacExportJobs
            && supportsMacDestinationStatus
            && supportsGranularPayloads
    }

    func supports(rawProfile: IPhoneExportRequest.RawProfile) -> Bool {
        switch rawProfile {
        case .canonicalSourceRecordsV1:
            return canonicalArchiveSchemaVersions.contains(HealthKitRecordArchive.currentRecordSchemaVersion)
                && canonicalRawResultSchemaVersions.contains(CanonicalRawResultEnvelope.currentSchemaVersion)
        }
    }

    func supportsRequestedMacExportFeatures(
        rollupSummariesEnabled: Bool,
        summaryOnlyExportEnabled: Bool = false
    ) -> Bool {
        isCompatibleWithMacExportJobs
            && (!rollupSummariesEnabled || supportsRollupSummaries)
            && (!summaryOnlyExportEnabled || supportsSummaryOnlyExports)
    }

    static func current(platform: SyncPlatform = .current) -> SyncPeerCapabilities {
        SyncPeerCapabilities(
            protocolVersion: currentProtocolVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            platform: platform,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsRollupSummaries: true,
            supportsSummaryOnlyExports: true,
            supportsIPhoneExportRequests: true,
            supportsChunkedMacExportJobs: true,
            supportsManualIPSync: true,
            manualIPSyncRequiresPairing: true,
            canonicalArchiveSchemaVersions: [HealthKitRecordArchive.currentRecordSchemaVersion],
            canonicalRawResultSchemaVersions: [CanonicalRawResultEnvelope.currentSchemaVersion]
        )
    }
}

struct MacDestinationStatus: Codable, Equatable {
    let isConnected: Bool
    let isReadyForExports: Bool
    let destinationFolderSelected: Bool
    let folderAccessHealthy: Bool
    let destinationDisplayName: String?
    let destinationPathForDisplay: String?
    let lastError: String?
    let activeJobID: UUID?
    let capabilities: SyncPeerCapabilities?

    var isBusy: Bool { activeJobID != nil }

    var canReceiveExports: Bool {
        isConnected
            && isReadyForExports
            && destinationFolderSelected
            && folderAccessHealthy
            && activeJobID == nil
            && (capabilities?.isCompatibleWithMacExportJobs ?? true)
    }

    var notReadyReason: String? {
        if !isConnected { return "Mac is not connected" }
        if let capabilities, !capabilities.isCompatibleWithMacExportJobs { return "Update Health.md on Mac" }
        if !destinationFolderSelected { return "Choose a folder on Mac" }
        if !folderAccessHealthy { return "Mac folder access denied" }
        if activeJobID != nil { return "Mac is exporting…" }
        if !isReadyForExports { return lastError ?? "Mac destination not ready" }
        return lastError
    }
}

// MARK: - Mac Export Jobs

struct ExportTargetSnapshot: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case iPhoneFolder
        case connectedMac
        case both
    }

    let kind: Kind
    let displayName: String?
    let destinationDisplayName: String?
}

struct MacExportJob: Codable {
    let jobID: UUID
    let createdAt: Date
    let sourceDeviceName: String
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let records: [HealthData]
    let externalDailyRecords: [ExternalDailyRecord]
    let settingsSnapshot: ExportSettingsSnapshot
    let requestedTarget: ExportTargetSnapshot?

    enum CodingKeys: String, CodingKey {
        case jobID
        case createdAt
        case sourceDeviceName
        case dateRangeStart
        case dateRangeEnd
        case records
        case externalDailyRecords
        case settingsSnapshot
        case requestedTarget
    }

    init(
        jobID: UUID,
        createdAt: Date,
        sourceDeviceName: String,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        records: [HealthData],
        externalDailyRecords: [ExternalDailyRecord] = [],
        settingsSnapshot: ExportSettingsSnapshot,
        requestedTarget: ExportTargetSnapshot?
    ) {
        self.jobID = jobID
        self.createdAt = createdAt
        self.sourceDeviceName = sourceDeviceName
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.records = records
        self.externalDailyRecords = externalDailyRecords
        self.settingsSnapshot = settingsSnapshot
        self.requestedTarget = requestedTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobID = try container.decode(UUID.self, forKey: .jobID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceDeviceName = try container.decode(String.self, forKey: .sourceDeviceName)
        dateRangeStart = try container.decode(Date.self, forKey: .dateRangeStart)
        dateRangeEnd = try container.decode(Date.self, forKey: .dateRangeEnd)
        records = try container.decode([HealthData].self, forKey: .records)
        externalDailyRecords = try container.decodeIfPresent([ExternalDailyRecord].self, forKey: .externalDailyRecords) ?? []
        settingsSnapshot = try container.decode(ExportSettingsSnapshot.self, forKey: .settingsSnapshot)
        requestedTarget = try container.decodeIfPresent(ExportTargetSnapshot.self, forKey: .requestedTarget)
    }
}

struct MacExportStreamStart: Codable, Equatable {
    let jobID: UUID
    let createdAt: Date
    let sourceDeviceName: String
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let totalRequestedDays: Int
    let totalTransferDays: Int
    let settingsSnapshot: ExportSettingsSnapshot
    let requestedTarget: ExportTargetSnapshot?
    let chunkStrategyVersion: Int
}

struct MacExportStreamChunk: Codable, Equatable {
    let jobID: UUID
    let sequence: Int
    let records: [HealthData]
    let externalDailyRecords: [ExternalDailyRecord]
    let processedTransferDays: Int
    let totalTransferDays: Int

    static func == (lhs: MacExportStreamChunk, rhs: MacExportStreamChunk) -> Bool {
        lhs.jobID == rhs.jobID
            && lhs.sequence == rhs.sequence
            && encodedValuesEqual(lhs.records, rhs.records)
            && lhs.externalDailyRecords == rhs.externalDailyRecords
            && lhs.processedTransferDays == rhs.processedTransferDays
            && lhs.totalTransferDays == rhs.totalTransferDays
    }
}

struct MacExportStreamChunkAck: Codable, Equatable {
    let jobID: UUID
    let sequence: Int
    let accepted: Bool
    let message: String?
    let processedDays: Int
    let filesWritten: Int
}

struct MacExportStreamComplete: Codable, Equatable {
    let jobID: UUID
    let totalChunks: Int
    let iphoneFailedDateDetails: [FailedDateDetail]

    static func == (lhs: MacExportStreamComplete, rhs: MacExportStreamComplete) -> Bool {
        lhs.jobID == rhs.jobID
            && lhs.totalChunks == rhs.totalChunks
            && encodedValuesEqual(lhs.iphoneFailedDateDetails, rhs.iphoneFailedDateDetails)
    }
}

struct MacExportStreamAbort: Codable, Equatable {
    let jobID: UUID
    let reason: MacExportFailureReason
    let message: String
}

private func encodedValuesEqual<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        return try encoder.encode(lhs) == encoder.encode(rhs)
    } catch {
        return false
    }
}

struct MacExportAcknowledgement: Codable, Equatable {
    let jobID: UUID
    let acceptedAt: Date
    let message: String?
}


enum MacExportPhase: String, Codable, Equatable {
    case receiving
    case validating
    case exporting
    case writing
    case completed
    case failed
    case cancelled
}

struct MacExportProgress: Codable, Equatable {
    let jobID: UUID
    let phase: MacExportPhase
    let processedDays: Int
    let totalDays: Int
    let currentDate: Date?
    let filesWritten: Int
    let message: String

    var fractionComplete: Double {
        guard totalDays > 0 else { return 0 }
        return Double(processedDays) / Double(totalDays)
    }
}

enum MacExportResultStatus: String, Codable, Equatable {
    case success
    case partialSuccess
    case failure
    case cancelled
}

struct MacExportResultPayload: Codable {
    let jobID: UUID
    let status: MacExportResultStatus
    let successCount: Int
    let totalCount: Int
    let formatsPerDate: Int
    let totalFilesWritten: Int
    let externalRecordFileCount: Int
    let failedDateDetails: [FailedDateDetail]
    let destinationDisplayName: String?
    let destinationPathForDisplay: String?
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case jobID
        case status
        case successCount
        case totalCount
        case formatsPerDate
        case totalFilesWritten
        case externalRecordFileCount
        case failedDateDetails
        case destinationDisplayName
        case destinationPathForDisplay
        case completedAt
    }

    init(
        jobID: UUID,
        status: MacExportResultStatus,
        successCount: Int,
        totalCount: Int,
        formatsPerDate: Int,
        totalFilesWritten: Int,
        externalRecordFileCount: Int = 0,
        failedDateDetails: [FailedDateDetail],
        destinationDisplayName: String?,
        destinationPathForDisplay: String?,
        completedAt: Date
    ) {
        self.jobID = jobID
        self.status = status
        self.successCount = successCount
        self.totalCount = totalCount
        self.formatsPerDate = formatsPerDate
        self.totalFilesWritten = totalFilesWritten
        self.externalRecordFileCount = externalRecordFileCount
        self.failedDateDetails = failedDateDetails
        self.destinationDisplayName = destinationDisplayName
        self.destinationPathForDisplay = destinationPathForDisplay
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobID = try container.decode(UUID.self, forKey: .jobID)
        status = try container.decode(MacExportResultStatus.self, forKey: .status)
        successCount = try container.decode(Int.self, forKey: .successCount)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        formatsPerDate = try container.decode(Int.self, forKey: .formatsPerDate)
        totalFilesWritten = try container.decode(Int.self, forKey: .totalFilesWritten)
        externalRecordFileCount = try container.decodeIfPresent(Int.self, forKey: .externalRecordFileCount) ?? 0
        failedDateDetails = try container.decode([FailedDateDetail].self, forKey: .failedDateDetails)
        destinationDisplayName = try container.decodeIfPresent(String.self, forKey: .destinationDisplayName)
        destinationPathForDisplay = try container.decodeIfPresent(String.self, forKey: .destinationPathForDisplay)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
    }
}

enum MacExportFailureReason: String, Codable, Equatable {
    case incompatibleProtocol
    case noMacFolderSelected
    case macFolderAccessDenied
    case noFormatsSelected
    case noHealthRecordsReceived
    case payloadDecodeFailure
    case exportWriteFailure
    case macBusy
    case cancelled
}

struct MacExportFailure: Codable, Equatable, Error {
    let jobID: UUID?
    let reason: MacExportFailureReason
    let message: String
    let underlyingError: String?
    let occurredAt: Date

    init(
        jobID: UUID? = nil,
        reason: MacExportFailureReason,
        message: String,
        underlyingError: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.jobID = jobID
        self.reason = reason
        self.message = message
        self.underlyingError = underlyingError
        self.occurredAt = occurredAt
    }
}

// MARK: - Mac-initiated iPhone Export Requests

struct IPhoneExportRequest: Codable, Equatable {
    enum RequestSource: String, Codable, Equatable {
        case macApp
        case cli
    }

    enum SettingsPolicy: String, Codable, Equatable {
        /// Use the iPhone app's currently saved export settings exactly.
        case currentIPhoneSettings

        /// Use the iPhone app's saved formats, metrics, filenames, and write
        /// behavior, but disable derived roll-up summaries and summary-only mode
        /// so the transfer only fetches and writes the requested date range.
        case requestedDatesOnly
    }

    enum ResponseMode: String, Codable, Equatable {
        /// iPhone sends a MacExportJob and the Mac writes files to its selected destination.
        case writeFiles

        /// iPhone sends raw records back to the Mac control server; no files are written.
        /// Requests without a `rawProfile` retain the legacy internal Codable response.
        case rawJSON
    }

    enum RawProfile: String, Codable, Equatable {
        /// Lossless canonical daily JSON plus a versioned capture/outcome envelope.
        case canonicalSourceRecordsV1 = "canonical_source_records_v1"
    }

    let jobID: UUID
    let createdAt: Date
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let requestedBy: RequestSource
    let settingsPolicy: SettingsPolicy
    let responseMode: ResponseMode
    /// Nil is the legacy raw behavior used by older control and sync peers.
    let rawProfile: RawProfile?

    enum CodingKeys: String, CodingKey {
        case jobID
        case createdAt
        case dateRangeStart
        case dateRangeEnd
        case requestedBy
        case settingsPolicy
        case responseMode
        case rawProfile
    }

    init(
        jobID: UUID,
        createdAt: Date,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        requestedBy: RequestSource,
        settingsPolicy: SettingsPolicy,
        responseMode: ResponseMode = .writeFiles,
        rawProfile: RawProfile? = nil
    ) {
        self.jobID = jobID
        self.createdAt = createdAt
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.requestedBy = requestedBy
        self.settingsPolicy = settingsPolicy
        self.responseMode = responseMode
        self.rawProfile = rawProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobID = try container.decode(UUID.self, forKey: .jobID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dateRangeStart = try container.decode(Date.self, forKey: .dateRangeStart)
        dateRangeEnd = try container.decode(Date.self, forKey: .dateRangeEnd)
        requestedBy = try container.decode(RequestSource.self, forKey: .requestedBy)
        settingsPolicy = try container.decode(SettingsPolicy.self, forKey: .settingsPolicy)
        responseMode = try container.decodeIfPresent(ResponseMode.self, forKey: .responseMode) ?? .writeFiles
        rawProfile = try container.decodeIfPresent(RawProfile.self, forKey: .rawProfile)
    }
}

struct IPhoneExportAcknowledgement: Codable, Equatable {
    let jobID: UUID
    let acceptedAt: Date
    let message: String?
}

struct IPhoneExportPreparationProgress: Codable, Equatable {
    let jobID: UUID
    let processedDays: Int
    let totalDays: Int
    let currentDate: Date?
    let message: String

    var fractionComplete: Double {
        guard totalDays > 0 else { return 0 }
        return Double(processedDays) / Double(totalDays)
    }
}

struct IPhoneExportRawDataPayload: Codable {
    let jobID: UUID
    let createdAt: Date
    let sourceDeviceName: String
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let totalDays: Int
    let records: [HealthData]
    let externalDailyRecords: [ExternalDailyRecord]
    let failedDateDetails: [FailedDateDetail]
    let settingsSnapshot: ExportSettingsSnapshot
    /// Present only for a strict versioned raw profile. Legacy payloads omit it.
    let strictResult: CanonicalRawResultEnvelope?

    enum CodingKeys: String, CodingKey {
        case jobID
        case createdAt
        case sourceDeviceName
        case dateRangeStart
        case dateRangeEnd
        case totalDays
        case records
        case externalDailyRecords
        case failedDateDetails
        case settingsSnapshot
        case strictResult
    }

    init(
        jobID: UUID,
        createdAt: Date,
        sourceDeviceName: String,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        totalDays: Int,
        records: [HealthData],
        externalDailyRecords: [ExternalDailyRecord] = [],
        failedDateDetails: [FailedDateDetail],
        settingsSnapshot: ExportSettingsSnapshot,
        strictResult: CanonicalRawResultEnvelope? = nil
    ) {
        self.jobID = jobID
        self.createdAt = createdAt
        self.sourceDeviceName = sourceDeviceName
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.totalDays = totalDays
        self.records = records
        self.externalDailyRecords = externalDailyRecords
        self.failedDateDetails = failedDateDetails
        self.settingsSnapshot = settingsSnapshot
        self.strictResult = strictResult
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobID = try container.decode(UUID.self, forKey: .jobID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceDeviceName = try container.decode(String.self, forKey: .sourceDeviceName)
        dateRangeStart = try container.decode(Date.self, forKey: .dateRangeStart)
        dateRangeEnd = try container.decode(Date.self, forKey: .dateRangeEnd)
        totalDays = try container.decode(Int.self, forKey: .totalDays)
        records = try container.decode([HealthData].self, forKey: .records)
        externalDailyRecords = try container.decodeIfPresent([ExternalDailyRecord].self, forKey: .externalDailyRecords) ?? []
        failedDateDetails = try container.decode([FailedDateDetail].self, forKey: .failedDateDetails)
        settingsSnapshot = try container.decode(ExportSettingsSnapshot.self, forKey: .settingsSnapshot)
        strictResult = try container.decodeIfPresent(CanonicalRawResultEnvelope.self, forKey: .strictResult)
    }
}

enum IPhoneExportFailureReason: String, Codable, Equatable {
    case unsupportedPeer
    case invalidDateRange
    case healthKitNotAuthorized
    case exportLimitReached
    case macDestinationUnavailable
    case healthKitFetchFailed
    case requestAlreadyInProgress
    case cancelled
    case timedOut
    case unknown
}

struct IPhoneExportFailure: Codable, Equatable, Error {
    let jobID: UUID?
    let reason: IPhoneExportFailureReason
    let message: String
    let underlyingError: String?
    let occurredAt: Date

    init(
        jobID: UUID? = nil,
        reason: IPhoneExportFailureReason,
        message: String,
        underlyingError: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.jobID = jobID
        self.reason = reason
        self.message = message
        self.underlyingError = underlyingError
        self.occurredAt = occurredAt
    }
}

// MARK: - Sync Progress Info

/// Progress information sent from iOS to macOS during large syncs.
struct SyncProgressInfo: Codable {
    /// Total number of dates being processed
    let totalDays: Int

    /// Number of dates processed so far
    let processedDays: Int

    /// Number of dates in this batch that had data
    let recordsInBatch: Int

    /// Whether this is the final progress update (sync complete)
    let isComplete: Bool

    /// Optional message for display
    let message: String?

    var fractionComplete: Double {
        guard totalDays > 0 else { return 0 }
        return Double(processedDays) / Double(totalDays)
    }
}

// MARK: - Sync Payload

/// Container for health data sent from iOS to macOS.
struct SyncPayload: Codable {
    /// Name of the source device (e.g., "Cody's iPhone")
    let deviceName: String

    /// When this sync payload was created
    let syncTimestamp: Date

    /// One HealthData record per date
    let healthRecords: [HealthData]
}

// MARK: - Sync Metadata

/// Metadata stored alongside cached health data on macOS.
struct SyncMetadata: Codable {
    /// Last successful sync timestamp
    var lastSyncDate: Date?

    /// Name of the device that sent the data
    var sourceDeviceName: String?

    /// Total number of date records stored locally
    var recordCount: Int = 0

    /// Dates that have been synced
    var syncedDates: [Date] = []
}
