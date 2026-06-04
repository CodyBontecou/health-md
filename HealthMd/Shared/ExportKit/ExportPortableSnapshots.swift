import Foundation

/// Portable, domain-free configuration for rendering aggregate export files.
///
/// ExportKit owns the format/path/write-mode fields that affect where and how
/// files are written. Apps can wrap this snapshot with their own rendering,
/// filtering, and plugin configuration without leaking app models into the
/// reusable core.
public struct PortableExportProfileSnapshot: Codable, Equatable, Sendable {
    public var formatIDs: [String]
    public var aggregateFolderTemplate: String
    public var aggregateFilenameTemplate: String
    public var writeMode: ExportWriteMode
    public var enabledPluginIDs: [String]
    public var metadata: [String: String]

    public init(
        formatIDs: [String],
        aggregateFolderTemplate: String = "",
        aggregateFilenameTemplate: String = "{date}",
        writeMode: ExportWriteMode = .overwrite,
        enabledPluginIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.formatIDs = Self.uniqued(formatIDs)
        self.aggregateFolderTemplate = aggregateFolderTemplate
        self.aggregateFilenameTemplate = aggregateFilenameTemplate
        self.writeMode = writeMode
        self.enabledPluginIDs = Self.uniqued(enabledPluginIDs)
        self.metadata = metadata
    }

    public func aggregatePathTemplate(fileExtension: String) -> ExportPathTemplate {
        ExportPathTemplate(
            folderTemplate: aggregateFolderTemplate,
            filenameTemplate: aggregateFilenameTemplate,
            fileExtension: fileExtension
        )
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

/// Domain-free target metadata for a remote/local-peer export job.
public struct PortableExportTargetSnapshot: Codable, Equatable, Sendable {
    public var kindID: String
    public var displayName: String?
    public var destinationDisplayName: String?

    public init(
        kindID: String,
        displayName: String? = nil,
        destinationDisplayName: String? = nil
    ) {
        self.kindID = kindID
        self.displayName = displayName
        self.destinationDisplayName = destinationDisplayName
    }
}

/// Generic local-peer export job shape.
///
/// The record payload remains app-owned; ExportKit only standardizes the job
/// envelope/profile metadata used by the receiving writer.
public struct PortableRemoteExportJobSnapshot<RecordPayload: Codable>: Codable {
    public var jobID: UUID
    public var createdAt: Date
    public var sourceDeviceName: String
    public var dateRangeStart: Date
    public var dateRangeEnd: Date
    public var records: [RecordPayload]
    public var exportProfile: PortableExportProfileSnapshot
    public var requestedTarget: PortableExportTargetSnapshot?

    public init(
        jobID: UUID,
        createdAt: Date,
        sourceDeviceName: String,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        records: [RecordPayload],
        exportProfile: PortableExportProfileSnapshot,
        requestedTarget: PortableExportTargetSnapshot? = nil
    ) {
        self.jobID = jobID
        self.createdAt = createdAt
        self.sourceDeviceName = sourceDeviceName
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.records = records
        self.exportProfile = exportProfile
        self.requestedTarget = requestedTarget
    }
}
