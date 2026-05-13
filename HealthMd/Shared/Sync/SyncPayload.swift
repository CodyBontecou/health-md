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

    /// Keepalive / connection test.
    case ping

    /// Response to ping.
    case pong
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

    var isCompatibleWithMacExportJobs: Bool {
        protocolVersion >= Self.currentProtocolVersion
            && supportsMacExportJobs
            && supportsMacDestinationStatus
            && supportsGranularPayloads
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
            supportsGranularPayloads: true
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
    let settingsSnapshot: ExportSettingsSnapshot
    let requestedTarget: ExportTargetSnapshot?
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
    let failedDateDetails: [FailedDateDetail]
    let destinationDisplayName: String?
    let destinationPathForDisplay: String?
    let completedAt: Date
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
