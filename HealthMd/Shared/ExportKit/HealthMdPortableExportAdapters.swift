import Foundation

// MARK: - Health.md Portable Export Adapters

/// A Health.md daily export record adapted to the reusable PortableExportKit
/// contract. The adapter keeps app-specific filtering/rendering decisions in
/// Health.md by carrying `AdvancedExportSettings` alongside `HealthData`.
struct HealthMdPortableExportRecord: PortableExportRecord {
    let healthData: HealthData
    let settings: AdvancedExportSettings

    init(healthData: HealthData, settings: AdvancedExportSettings) {
        self.healthData = healthData
        self.settings = settings
    }

    var portableExportID: String {
        Self.dateID(for: healthData.date)
    }

    var portableExportDate: Date {
        healthData.date
    }

    var hasPortableExportableData: Bool {
        healthData.filtered(by: settings.metricSelection).hasAnyData
    }

    private static func dateID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Bridges Health.md's section-aware markdown update behavior into the generic
/// PortableExportKit update merge hook.
struct HealthMdMarkdownMergeStrategy: PortableExportMergeStrategy {
    func merge(existing: String, new: String) throws -> String {
        MarkdownMerger.merge(existing: existing, new: new)
    }
}

/// Namespace for converting Health.md export models into PortableExportKit
/// primitives without replacing the existing VaultManager/ExportOrchestrator
/// runtime path yet.
enum HealthMdPortableExportAdapter {
    static func portableFormat(for format: ExportFormat) -> PortableExportFormat {
        switch format {
        case .markdown:
            return PortableExportFormat(
                id: "markdown",
                displayName: format.rawValue,
                fileExtension: format.fileExtension
            )
        case .obsidianBases:
            return PortableExportFormat(
                id: "obsidianBases",
                displayName: format.rawValue,
                fileExtension: format.fileExtension,
                collisionSuffix: "-bases"
            )
        case .json:
            return PortableExportFormat(
                id: "json",
                displayName: format.rawValue,
                fileExtension: format.fileExtension
            )
        case .csv:
            return PortableExportFormat(
                id: "csv",
                displayName: format.rawValue,
                fileExtension: format.fileExtension
            )
        }
    }

    static func exportFormat(for portableFormat: PortableExportFormat) -> ExportFormat? {
        switch portableFormat.id {
        case "markdown":
            return .markdown
        case "obsidianBases":
            return .obsidianBases
        case "json":
            return .json
        case "csv":
            return .csv
        default:
            return ExportFormat.allCases.first {
                $0.rawValue == portableFormat.displayName && $0.fileExtension == portableFormat.fileExtension
            }
        }
    }

    static func portableFormats(for settings: AdvancedExportSettings) -> [PortableExportFormat] {
        settings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { format in portableFormat(for: format) }
    }

    static func portableWriteMode(for writeMode: WriteMode) -> PortableExportWriteMode {
        switch writeMode {
        case .overwrite:
            return .overwrite
        case .append:
            return .append
        case .update:
            return .update
        }
    }

    static func configuration(
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        timezone: TimeZone = .current
    ) -> PortableExportConfiguration {
        PortableExportConfiguration(
            formats: portableFormats(for: settings),
            templates: PortableExportPathTemplates(
                baseFolderTemplate: healthSubfolder,
                folderTemplate: settings.folderStructure,
                filenameTemplate: settings.filenameFormat
            ),
            writeMode: portableWriteMode(for: settings.writeMode),
            timezone: timezone
        )
    }

    static func planAggregateFile(
        vaultURL: URL,
        healthSubfolder: String,
        healthData: HealthData,
        settings: AdvancedExportSettings,
        format: ExportFormat,
        timezone: TimeZone = .current
    ) throws -> PortablePlannedExportFile {
        try PortableExportPathPlanner.planFile(
            rootURL: vaultURL,
            record: HealthMdPortableExportRecord(healthData: healthData, settings: settings),
            format: portableFormat(for: format),
            configuration: configuration(settings: settings, healthSubfolder: healthSubfolder, timezone: timezone)
        )
    }

    static func renderer(for format: ExportFormat) -> AnyPortableExportRenderer<HealthMdPortableExportRecord> {
        AnyPortableExportRenderer(
            format: portableFormat(for: format),
            mergeStrategy: format == .markdown ? HealthMdMarkdownMergeStrategy() : nil,
            render: { record, _ in
                record.healthData.export(format: format, settings: record.settings)
            }
        )
    }

    static func renderers(for settings: AdvancedExportSettings) -> [AnyPortableExportRenderer<HealthMdPortableExportRecord>] {
        settings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { format in renderer(for: format) }
    }

    static func dataSource(
        records: [HealthMdPortableExportRecord],
        calendar: Calendar = .current
    ) -> AnyPortableExportDataSource<HealthMdPortableExportRecord> {
        AnyPortableExportDataSource { request in
            guard !request.dates.isEmpty else { return records }
            return records.filter { record in
                request.dates.contains { requestedDate in
                    calendar.isDate(record.portableExportDate, inSameDayAs: requestedDate)
                }
            }
        }
    }
}
