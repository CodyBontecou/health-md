import Foundation
import HealthMdConnectionCore

/// Health-free checkpoint for one captured source day in a generated-file direct export.
struct IPhoneDirectCapturedDay: Codable, Equatable {
    let sourceDate: Date
    let sourceDateIdentifier: String
    let isRequestedDate: Bool
    let relativePath: String
    let succeeded: Bool
    /// Nil identifies a checkpoint written before granular-capture history was tracked.
    let includedGranularData: Bool?
    let sampleCount: Int
    let recordCount: Int
    let externalRecordCount: Int
    let partialFailureCount: Int
    let integrityWarningCount: Int
    let hadWarnings: Bool
    /// Warnings that reduce capture completeness. Nil identifies a checkpoint
    /// written before the informational/degrading split was tracked; consumers
    /// fall back to `partialFailureCount` so legacy checkpoints keep the
    /// behavior they were written with.
    let degradingFailureCount: Int?
    /// Same contract as `hadWarnings`, excluding informational omissions (for
    /// example a WorkoutKit plan this device cannot decode) that do not reduce
    /// the export below full success. Nil falls back to `hadWarnings`.
    let hadDegradingWarnings: Bool?
    /// Informational-only warnings surfaced so Export History can show them as
    /// export notes without degrading the entry's status. Nil or empty means
    /// the day had none (or predates note tracking).
    let informationalFailures: [ExportPartialFailure]?
    let failureReason: ExportFailureReason?
    /// False only for checkpoints written before these health-free facts were persisted.
    let historyFactsRecorded: Bool

    init(
        sourceDate: Date,
        sourceDateIdentifier: String,
        isRequestedDate: Bool,
        relativePath: String,
        succeeded: Bool,
        includedGranularData: Bool? = nil,
        sampleCount: Int = 0,
        recordCount: Int = 0,
        externalRecordCount: Int = 0,
        partialFailureCount: Int = 0,
        integrityWarningCount: Int = 0,
        hadWarnings: Bool = false,
        degradingFailureCount: Int? = nil,
        hadDegradingWarnings: Bool? = nil,
        informationalFailures: [ExportPartialFailure]? = nil,
        failureReason: ExportFailureReason? = nil,
        historyFactsRecorded: Bool = false
    ) {
        self.sourceDate = sourceDate
        self.sourceDateIdentifier = sourceDateIdentifier
        self.isRequestedDate = isRequestedDate
        self.relativePath = relativePath
        self.succeeded = succeeded
        self.includedGranularData = includedGranularData
        self.sampleCount = max(sampleCount, 0)
        self.recordCount = max(recordCount, 0)
        self.externalRecordCount = max(externalRecordCount, 0)
        self.partialFailureCount = max(partialFailureCount, 0)
        self.integrityWarningCount = max(integrityWarningCount, 0)
        self.hadWarnings = hadWarnings
        self.degradingFailureCount = degradingFailureCount.map { max($0, 0) }
        self.hadDegradingWarnings = hadDegradingWarnings
        self.informationalFailures = informationalFailures
        self.failureReason = failureReason
        self.historyFactsRecorded = historyFactsRecorded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceDate = try container.decode(Date.self, forKey: .sourceDate)
        sourceDateIdentifier = try container.decode(String.self, forKey: .sourceDateIdentifier)
        isRequestedDate = try container.decode(Bool.self, forKey: .isRequestedDate)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        succeeded = try container.decode(Bool.self, forKey: .succeeded)
        includedGranularData = try container.decodeIfPresent(Bool.self, forKey: .includedGranularData)
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        recordCount = try container.decodeIfPresent(Int.self, forKey: .recordCount) ?? 0
        externalRecordCount = try container.decodeIfPresent(Int.self, forKey: .externalRecordCount) ?? 0
        partialFailureCount = try container.decodeIfPresent(Int.self, forKey: .partialFailureCount) ?? 0
        integrityWarningCount = try container.decodeIfPresent(Int.self, forKey: .integrityWarningCount) ?? 0
        hadWarnings = try container.decodeIfPresent(Bool.self, forKey: .hadWarnings) ?? false
        degradingFailureCount = try container.decodeIfPresent(Int.self, forKey: .degradingFailureCount)
        hadDegradingWarnings = try container.decodeIfPresent(Bool.self, forKey: .hadDegradingWarnings)
        informationalFailures = try container.decodeIfPresent([ExportPartialFailure].self, forKey: .informationalFailures)
        failureReason = try container.decodeIfPresent(ExportFailureReason.self, forKey: .failureReason)
        historyFactsRecorded = try container.decodeIfPresent(Bool.self, forKey: .historyFactsRecorded) ?? false
    }

    /// Degrading warning count, falling back to the total for checkpoints
    /// written before the split was tracked.
    var resolvedDegradingFailureCount: Int {
        degradingFailureCount ?? partialFailureCount
    }

    /// Whether the day carries warnings that reduce capture completeness,
    /// falling back to `hadWarnings` for legacy checkpoints.
    var resolvedHadDegradingWarnings: Bool {
        hadDegradingWarnings ?? hadWarnings
    }
}

/// Health-free generated-file descriptor persisted before bounded direct transfer.
struct IPhoneDirectGeneratedFile: Codable, Equatable {
    let manifest: DirectExportFileManifest
    let relativePath: String
}

/// Durable state for generated-file direct exports only. Raw and canonical direct journals retain
/// their independent models. V1 is fully legacy, v2 may carry an export-engine pin, v3 may
/// carry a direct-protocol pin, v4 stores captured days as bounded application-item streams, v5
/// freezes original range authority, and v6 persists terminal derived-output reconciliation.
struct IPhoneDirectFileJournal: Codable {
    static let legacyVersion = 1
    static let exportEnginePinVersion = 2
    static let directProtocolPinVersion = 3
    static let fileBackedCaptureVersion = 4
    static let immutableRangeRequestVersion = 5
    static let derivedOutputReconciliationVersion = 6
    static let currentVersion = derivedOutputReconciliationVersion

    let version: Int
    let request: DirectExportRequest
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    let settingsSnapshot: ExportSettingsSnapshot
    let appleExportEnginePin: AppleExportEnginePin?
    let appleDirectProtocolPin: AppleDirectProtocolPin?
    let healthSubfolder: String
    let requestedDates: [Date]
    /// Original requested owner dates remain stable while capture resumes residual transfer work.
    let originalRequestedDates: [Date]
    /// Original timezone authority used to regenerate/overwrite the same range path.
    let originalCalendarTimeZoneIdentifier: String?
    let transferDates: [Date]
    var capturedDays: [IPhoneDirectCapturedDay]
    var generatedFiles: [IPhoneDirectGeneratedFile]
    var partitions: [DirectTransferPartition]
    var committedPartitionCount: Int
    var committedBytes: Int64
    var derivedOutputPartialFailures: [ExportPartialFailure]
    var terminalNoDataDateIdentifiers: [String]
    var generationCompleted: Bool
    var state: String
    var completionRecorded: Bool
    var updatedAt: Date

    static func isSupportedVersion(_ version: Int) -> Bool {
        version >= legacyVersion && version <= currentVersion
    }

    init(
        version: Int = currentVersion,
        request: DirectExportRequest,
        accepted: DirectExportAccepted,
        session: DirectTransferSession,
        settingsSnapshot: ExportSettingsSnapshot,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        appleDirectProtocolPin: AppleDirectProtocolPin? = nil,
        healthSubfolder: String,
        requestedDates: [Date],
        originalRequestedDates: [Date]? = nil,
        originalCalendarTimeZoneIdentifier: String? = nil,
        transferDates: [Date],
        capturedDays: [IPhoneDirectCapturedDay],
        generatedFiles: [IPhoneDirectGeneratedFile],
        partitions: [DirectTransferPartition],
        committedPartitionCount: Int,
        committedBytes: Int64,
        derivedOutputPartialFailures: [ExportPartialFailure] = [],
        terminalNoDataDateIdentifiers: [String] = [],
        generationCompleted: Bool = false,
        state: String,
        completionRecorded: Bool,
        updatedAt: Date
    ) {
        self.version = version
        self.request = request
        self.accepted = accepted
        self.session = session
        self.settingsSnapshot = settingsSnapshot
        self.appleExportEnginePin = version >= Self.exportEnginePinVersion
            ? (appleExportEnginePin ?? settingsSnapshot.appleExportEnginePin)
            : nil
        self.appleDirectProtocolPin = version >= Self.directProtocolPinVersion
            ? appleDirectProtocolPin
            : nil
        self.healthSubfolder = healthSubfolder
        self.requestedDates = requestedDates
        self.originalRequestedDates = originalRequestedDates ?? requestedDates
        self.originalCalendarTimeZoneIdentifier = originalCalendarTimeZoneIdentifier
            ?? settingsSnapshot.calendarTimeZoneIdentifier
            ?? accepted.sourceTimeZoneIdentifier
        self.transferDates = transferDates
        self.capturedDays = capturedDays
        self.generatedFiles = generatedFiles
        self.partitions = partitions
        self.committedPartitionCount = committedPartitionCount
        self.committedBytes = committedBytes
        self.derivedOutputPartialFailures = derivedOutputPartialFailures
        self.terminalNoDataDateIdentifiers = terminalNoDataDateIdentifiers
        self.generationCompleted = generationCompleted
        self.state = state
        self.completionRecorded = completionRecorded
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        request = try container.decode(DirectExportRequest.self, forKey: .request)
        accepted = try container.decode(DirectExportAccepted.self, forKey: .accepted)
        session = try container.decode(DirectTransferSession.self, forKey: .session)
        settingsSnapshot = try container.decode(ExportSettingsSnapshot.self, forKey: .settingsSnapshot)
        // A v1 checkpoint remains legacy even if an unexpected future writer added this key.
        appleExportEnginePin = version >= Self.exportEnginePinVersion
            ? (try container.decodeIfPresent(AppleExportEnginePin.self, forKey: .appleExportEnginePin)
                ?? settingsSnapshot.appleExportEnginePin)
            : nil
        appleDirectProtocolPin = version >= Self.directProtocolPinVersion
            ? try container.decodeIfPresent(
                AppleDirectProtocolPin.self,
                forKey: .appleDirectProtocolPin
            )
            : nil
        healthSubfolder = try container.decode(String.self, forKey: .healthSubfolder)
        requestedDates = try container.decode([Date].self, forKey: .requestedDates)
        originalRequestedDates = try container.decodeIfPresent(
            [Date].self,
            forKey: .originalRequestedDates
        ) ?? requestedDates
        originalCalendarTimeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .originalCalendarTimeZoneIdentifier
        ) ?? settingsSnapshot.calendarTimeZoneIdentifier ?? accepted.sourceTimeZoneIdentifier
        transferDates = try container.decode([Date].self, forKey: .transferDates)
        capturedDays = try container.decode([IPhoneDirectCapturedDay].self, forKey: .capturedDays)
        generatedFiles = try container.decode([IPhoneDirectGeneratedFile].self, forKey: .generatedFiles)
        partitions = try container.decode([DirectTransferPartition].self, forKey: .partitions)
        committedPartitionCount = try container.decode(Int.self, forKey: .committedPartitionCount)
        committedBytes = try container.decode(Int64.self, forKey: .committedBytes)
        derivedOutputPartialFailures = try container.decodeIfPresent(
            [ExportPartialFailure].self,
            forKey: .derivedOutputPartialFailures
        ) ?? []
        terminalNoDataDateIdentifiers = try container.decodeIfPresent(
            [String].self,
            forKey: .terminalNoDataDateIdentifiers
        ) ?? []
        generationCompleted = try container.decodeIfPresent(
            Bool.self,
            forKey: .generationCompleted
        ) ?? false
        state = try container.decode(String.self, forKey: .state)
        completionRecorded = try container.decodeIfPresent(Bool.self, forKey: .completionRecorded) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
