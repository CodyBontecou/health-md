import Foundation
import HealthMdConnectionCore

/// Health-free checkpoint for one captured source day in a generated-file direct export.
struct IPhoneDirectCapturedDay: Codable, Equatable {
    let sourceDate: Date
    let sourceDateIdentifier: String
    let isRequestedDate: Bool
    let relativePath: String
    let succeeded: Bool
}

/// Health-free generated-file descriptor persisted before bounded direct transfer.
struct IPhoneDirectGeneratedFile: Codable, Equatable {
    let manifest: DirectExportFileManifest
    let relativePath: String
}

/// Durable state for generated-file direct exports only. Raw and canonical direct journals retain
/// their independent models. V1 is fully legacy, v2 may carry an export-engine pin, and v3 may
/// additionally carry a direct-protocol pin.
struct IPhoneDirectFileJournal: Codable {
    static let legacyVersion = 1
    static let exportEnginePinVersion = 2
    static let currentVersion = 3

    let version: Int
    let request: DirectExportRequest
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    let settingsSnapshot: ExportSettingsSnapshot
    let appleExportEnginePin: AppleExportEnginePin?
    let appleDirectProtocolPin: AppleDirectProtocolPin?
    let healthSubfolder: String
    let requestedDates: [Date]
    let transferDates: [Date]
    var capturedDays: [IPhoneDirectCapturedDay]
    var generatedFiles: [IPhoneDirectGeneratedFile]
    var partitions: [DirectTransferPartition]
    var committedPartitionCount: Int
    var committedBytes: Int64
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
        transferDates: [Date],
        capturedDays: [IPhoneDirectCapturedDay],
        generatedFiles: [IPhoneDirectGeneratedFile],
        partitions: [DirectTransferPartition],
        committedPartitionCount: Int,
        committedBytes: Int64,
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
        self.appleDirectProtocolPin = version >= Self.currentVersion
            ? appleDirectProtocolPin
            : nil
        self.healthSubfolder = healthSubfolder
        self.requestedDates = requestedDates
        self.transferDates = transferDates
        self.capturedDays = capturedDays
        self.generatedFiles = generatedFiles
        self.partitions = partitions
        self.committedPartitionCount = committedPartitionCount
        self.committedBytes = committedBytes
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
        appleDirectProtocolPin = version >= Self.currentVersion
            ? try container.decodeIfPresent(
                AppleDirectProtocolPin.self,
                forKey: .appleDirectProtocolPin
            )
            : nil
        healthSubfolder = try container.decode(String.self, forKey: .healthSubfolder)
        requestedDates = try container.decode([Date].self, forKey: .requestedDates)
        transferDates = try container.decode([Date].self, forKey: .transferDates)
        capturedDays = try container.decode([IPhoneDirectCapturedDay].self, forKey: .capturedDays)
        generatedFiles = try container.decode([IPhoneDirectGeneratedFile].self, forKey: .generatedFiles)
        partitions = try container.decode([DirectTransferPartition].self, forKey: .partitions)
        committedPartitionCount = try container.decode(Int.self, forKey: .committedPartitionCount)
        committedBytes = try container.decode(Int64.self, forKey: .committedBytes)
        state = try container.decode(String.self, forKey: .state)
        completionRecorded = try container.decodeIfPresent(Bool.self, forKey: .completionRecorded) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
