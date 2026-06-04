import Foundation

/// Health.md adapter record for ExportKit renderers.
///
/// The reusable ExportKit core never sees HealthData directly; Health.md owns the
/// HealthData payload and converts it into this app-specific record wrapper.
struct HealthExportRecord: ExportRecord {
    let healthData: HealthData

    var exportRecordID: String {
        HealthExportRecord.idFormatter.string(from: healthData.date)
    }

    var exportDate: Date { healthData.date }

    private static let idFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension ExportFormat {
    var exportKitFormatID: String {
        switch self {
        case .markdown: return "markdown"
        case .obsidianBases: return "obsidianBases"
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    var exportFormatDescriptor: ExportFormatDescriptor {
        ExportFormatDescriptor(
            id: exportKitFormatID,
            displayName: rawValue,
            fileExtension: fileExtension,
            collisionSuffix: collisionSuffix,
            contentType: contentType,
            defaultSortKey: rawValue
        )
    }

    private var collisionSuffix: String? {
        switch self {
        case .obsidianBases:
            return "-bases"
        case .markdown, .json, .csv:
            return nil
        }
    }

    private var contentType: String {
        switch self {
        case .markdown, .obsidianBases:
            return "text/markdown"
        case .json:
            return "application/json"
        case .csv:
            return "text/csv"
        }
    }

    init?(exportKitFormatID: String) {
        switch exportKitFormatID {
        case ExportFormat.markdown.exportKitFormatID:
            self = .markdown
        case ExportFormat.obsidianBases.exportKitFormatID:
            self = .obsidianBases
        case ExportFormat.json.exportKitFormatID:
            self = .json
        case ExportFormat.csv.exportKitFormatID:
            self = .csv
        default:
            return nil
        }
    }
}

private struct HealthMarkdownRenderer: ExportRenderer {
    let settings: AdvancedExportSettings
    var descriptor: ExportFormatDescriptor { ExportFormat.markdown.exportFormatDescriptor }

    func render(record: HealthExportRecord, context: ExportRenderContext) throws -> RenderedExport {
        let filteredData = record.healthData.filtered(by: settings.metricSelection)
        let content = filteredData.toMarkdown(
            includeMetadata: settings.includeMetadata,
            groupByCategory: settings.groupByCategory,
            customization: settings.formatCustomization
        )
        return RenderedExport(content: content, contentType: descriptor.contentType)
    }
}

private struct HealthObsidianBasesRenderer: ExportRenderer {
    let settings: AdvancedExportSettings
    var descriptor: ExportFormatDescriptor { ExportFormat.obsidianBases.exportFormatDescriptor }

    func render(record: HealthExportRecord, context: ExportRenderContext) throws -> RenderedExport {
        let filteredData = record.healthData.filtered(by: settings.metricSelection)
        let content = filteredData.toObsidianBases(customization: settings.formatCustomization)
        return RenderedExport(content: content, contentType: descriptor.contentType)
    }
}

private struct HealthJSONRenderer: ExportRenderer {
    let settings: AdvancedExportSettings
    var descriptor: ExportFormatDescriptor { ExportFormat.json.exportFormatDescriptor }

    func render(record: HealthExportRecord, context: ExportRenderContext) throws -> RenderedExport {
        let filteredData = record.healthData.filtered(by: settings.metricSelection)
        let content = filteredData.toJSON(customization: settings.formatCustomization)
        return RenderedExport(content: content, contentType: descriptor.contentType)
    }
}

private struct HealthCSVRenderer: ExportRenderer {
    let settings: AdvancedExportSettings
    var descriptor: ExportFormatDescriptor { ExportFormat.csv.exportFormatDescriptor }

    func render(record: HealthExportRecord, context: ExportRenderContext) throws -> RenderedExport {
        let filteredData = record.healthData.filtered(by: settings.metricSelection)
        let content = filteredData.toCSV(customization: settings.formatCustomization)
        return RenderedExport(content: content, contentType: descriptor.contentType)
    }
}

enum HealthExportRendererAdapter {
    static func renderer(
        for format: ExportFormat,
        settings: AdvancedExportSettings
    ) -> AnyExportRenderer<HealthExportRecord> {
        switch format {
        case .markdown:
            return AnyExportRenderer(HealthMarkdownRenderer(settings: settings))
        case .obsidianBases:
            return AnyExportRenderer(HealthObsidianBasesRenderer(settings: settings))
        case .json:
            return AnyExportRenderer(HealthJSONRenderer(settings: settings))
        case .csv:
            return AnyExportRenderer(HealthCSVRenderer(settings: settings))
        }
    }

    static func registry(
        settings: AdvancedExportSettings,
        formats: Set<ExportFormat>? = nil
    ) -> ExportRendererRegistry<HealthExportRecord> {
        let selectedFormats = sortedFormats(formats ?? settings.exportFormats)
        let renderers = selectedFormats.map { renderer(for: $0, settings: settings) }
        do {
            return try ExportRendererRegistry(renderers: renderers)
        } catch {
            preconditionFailure("Health.md registered duplicate export renderer ids: \(error)")
        }
    }

    static func sortedFormats(_ formats: Set<ExportFormat>) -> [ExportFormat] {
        let registry = descriptorOnlyRegistry(for: formats)
        return registry.registeredFormatIDs.compactMap(ExportFormat.init(exportKitFormatID:))
    }

    static func resolvedFilenames(
        baseName: String,
        formats: Set<ExportFormat>
    ) -> [(format: ExportFormat, filename: String)] {
        let registry = descriptorOnlyRegistry(for: formats)
        do {
            return try registry.resolvedFilenames(baseName: baseName).compactMap { resolved in
                guard let format = ExportFormat(exportKitFormatID: resolved.descriptor.id) else { return nil }
                return (format: format, filename: resolved.filename)
            }
        } catch {
            preconditionFailure("Health.md failed to resolve export filenames: \(error)")
        }
    }

    private static func descriptorOnlyRegistry(
        for formats: Set<ExportFormat>
    ) -> ExportRendererRegistry<HealthExportRecord> {
        let renderers = formats.map { format in
            AnyExportRenderer<HealthExportRecord>(descriptor: format.exportFormatDescriptor) { _, _ in
                RenderedExport(content: "", contentType: format.exportFormatDescriptor.contentType)
            }
        }
        do {
            return try ExportRendererRegistry(renderers: renderers)
        } catch {
            preconditionFailure("Health.md registered duplicate export descriptor ids: \(error)")
        }
    }
}
