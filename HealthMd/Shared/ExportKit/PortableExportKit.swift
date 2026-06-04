import Foundation

// MARK: - Portable Export Core

/// Trigger/source metadata shared by manual, shortcut, background, push, and retry exports.
enum PortableExportTriggerSource: String, Codable, Equatable {
    case manual
    case scheduledBackground
    case silentPush
    case notificationTap
    case shortcut
    case retry
}

/// A format descriptor is intentionally data-agnostic. Apps can define Markdown,
/// JSON, CSV, PDF, ICS, or any custom format without changing the export engine.
struct PortableExportFormat: Codable, Hashable, Equatable {
    let id: String
    let displayName: String
    let fileExtension: String
    let collisionSuffix: String?

    init(id: String, displayName: String, fileExtension: String, collisionSuffix: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.fileExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        self.collisionSuffix = collisionSuffix
    }
}

enum PortableExportWriteMode: String, Codable, Equatable {
    case overwrite
    case append
    case update
}

/// User-configurable path templates. Placeholders are resolved from built-ins,
/// app-level `extraTemplateValues`, and each record's `exportTemplateValue(for:)`.
struct PortableExportPathTemplates: Codable, Equatable {
    var baseFolderTemplate: String
    var folderTemplate: String
    var filenameTemplate: String

    init(
        baseFolderTemplate: String = "",
        folderTemplate: String = "",
        filenameTemplate: String = "{date}"
    ) {
        self.baseFolderTemplate = baseFolderTemplate
        self.folderTemplate = folderTemplate
        self.filenameTemplate = filenameTemplate
    }
}

struct PortableExportConfiguration: Codable, Equatable {
    var formats: [PortableExportFormat]
    var templates: PortableExportPathTemplates
    var writeMode: PortableExportWriteMode
    var timezone: TimeZone
    var extraTemplateValues: [String: String]

    init(
        formats: [PortableExportFormat],
        templates: PortableExportPathTemplates = PortableExportPathTemplates(),
        writeMode: PortableExportWriteMode = .overwrite,
        timezone: TimeZone = .current,
        extraTemplateValues: [String: String] = [:]
    ) {
        self.formats = formats
        self.templates = templates
        self.writeMode = writeMode
        self.timezone = timezone
        self.extraTemplateValues = extraTemplateValues
    }
}

struct PortableExportRequest: Codable, Equatable {
    var dates: [Date]
    var trigger: PortableExportTriggerSource
    var metadata: [String: String]

    init(
        dates: [Date],
        trigger: PortableExportTriggerSource,
        metadata: [String: String] = [:]
    ) {
        self.dates = dates
        self.trigger = trigger
        self.metadata = metadata
    }
}

/// Minimal record contract for reusable export orchestration.
protocol PortableExportRecord {
    var portableExportID: String { get }
    var portableExportDate: Date { get }
    var hasPortableExportableData: Bool { get }

    /// App/domain-specific path variables such as `{project}`, `{client}`,
    /// `{category}`, `{patient}`, etc.
    func exportTemplateValue(for key: String) -> String?
}

extension PortableExportRecord {
    func exportTemplateValue(for key: String) -> String? { nil }
}

enum PortableExportPathError: LocalizedError, Equatable {
    case unsafePathSegment(String)
    case emptyFilename
    case formatNotSelected(String)

    var errorDescription: String? {
        switch self {
        case .unsafePathSegment(let segment):
            return "Unsafe export path segment: \(segment)"
        case .emptyFilename:
            return "Export filename template resolved to an empty filename"
        case .formatNotSelected(let formatID):
            return "Format is not selected in this export configuration: \(formatID)"
        }
    }
}

struct PortablePlannedExportFile: Equatable {
    let format: PortableExportFormat
    let filename: String
    let url: URL
    let relativePath: String
}

enum PortableExportPathPlanner {
    static func planFile<Record: PortableExportRecord>(
        rootURL: URL,
        record: Record,
        format: PortableExportFormat,
        configuration: PortableExportConfiguration
    ) throws -> PortablePlannedExportFile {
        guard configuration.formats.contains(format) else {
            throw PortableExportPathError.formatNotSelected(format.id)
        }

        let base = try pathSegments(
            renderTemplate(configuration.templates.baseFolderTemplate, record: record, format: format, configuration: configuration)
        )
        let folder = try pathSegments(
            renderTemplate(configuration.templates.folderTemplate, record: record, format: format, configuration: configuration)
        )
        var filenameSegments = try pathSegments(
            renderTemplate(configuration.templates.filenameTemplate, record: record, format: format, configuration: configuration)
        )

        guard !filenameSegments.isEmpty else {
            throw PortableExportPathError.emptyFilename
        }

        let suffix = collisionSuffix(for: format, in: configuration)
        let lastIndex = filenameSegments.index(before: filenameSegments.endIndex)
        filenameSegments[lastIndex] = filenameSegments[lastIndex] + suffix + "." + format.fileExtension

        let allSegments = base + folder + filenameSegments
        let relativePath = allSegments.joined(separator: "/")
        let url = append(segments: allSegments, to: rootURL)
        return PortablePlannedExportFile(
            format: format,
            filename: filenameSegments[lastIndex],
            url: url,
            relativePath: relativePath
        )
    }

    static func renderedRelativePath<Record: PortableExportRecord>(
        _ template: String,
        rootURL: URL,
        record: Record,
        configuration: PortableExportConfiguration
    ) throws -> (relativePath: String, url: URL) {
        let rendered = renderTemplate(template, record: record, format: nil, configuration: configuration)
        let segments = try pathSegments(rendered)
        let relativePath = segments.joined(separator: "/")
        return (relativePath, append(segments: segments, to: rootURL))
    }

    static func renderTemplate<Record: PortableExportRecord>(
        _ template: String,
        record: Record,
        format: PortableExportFormat?,
        configuration: PortableExportConfiguration
    ) -> String {
        guard !template.isEmpty else { return "" }

        let regex = try? NSRegularExpression(pattern: #"\{([A-Za-z0-9_\-]+)\}"#)
        guard let regex else { return template }

        let nsTemplate = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length))
        var result = template

        for match in matches.reversed() {
            guard match.numberOfRanges == 2 else { continue }
            let placeholder = nsTemplate.substring(with: match.range(at: 1))
            guard let value = templateValue(
                for: placeholder,
                record: record,
                format: format,
                configuration: configuration
            ) else { continue }

            if let range = Range(match.range(at: 0), in: result) {
                result.replaceSubrange(range, with: value)
            }
        }

        return result
    }

    private static func templateValue<Record: PortableExportRecord>(
        for key: String,
        record: Record,
        format: PortableExportFormat?,
        configuration: PortableExportConfiguration
    ) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = configuration.timezone
        let date = record.portableExportDate

        switch key {
        case "date":
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case "year":
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        case "month":
            formatter.dateFormat = "MM"
            return formatter.string(from: date)
        case "day":
            formatter.dateFormat = "dd"
            return formatter.string(from: date)
        case "weekday":
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        case "monthName":
            formatter.dateFormat = "MMMM"
            return formatter.string(from: date)
        case "quarter":
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = configuration.timezone
            let month = calendar.component(.month, from: date)
            return "Q\((month - 1) / 3 + 1)"
        case "id":
            return record.portableExportID
        case "format":
            return format?.id
        case "formatName":
            return format?.displayName
        case "extension":
            return format?.fileExtension
        default:
            return configuration.extraTemplateValues[key] ?? record.exportTemplateValue(for: key)
        }
    }

    private static func pathSegments(_ rawPath: String) throws -> [String] {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return [] }
        guard !trimmedPath.hasPrefix("/") else {
            throw PortableExportPathError.unsafePathSegment("/")
        }

        return try trimmedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { rawSegment in
                let segment = String(rawSegment).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !segment.isEmpty, segment != ".", segment != ".." else {
                    throw PortableExportPathError.unsafePathSegment(segment.isEmpty ? "" : segment)
                }
                return segment
            }
    }

    private static func append(segments: [String], to rootURL: URL) -> URL {
        var url = rootURL
        for (index, segment) in segments.enumerated() {
            url = url.appendingPathComponent(segment, isDirectory: index < segments.count - 1)
        }
        return url
    }

    private static func collisionSuffix(
        for format: PortableExportFormat,
        in configuration: PortableExportConfiguration
    ) -> String {
        let sameExtension = configuration.formats.filter { $0.fileExtension == format.fileExtension }
        guard sameExtension.count > 1 else { return "" }
        if let explicit = format.collisionSuffix { return explicit }
        if sameExtension.first == format { return "" }
        return "-\(format.id)"
    }
}

// MARK: - Rendering + Writing

protocol PortableExportMergeStrategy {
    func merge(existing: String, new: String) throws -> String
}

struct PortableRenderedExportFile {
    let url: URL
    let relativePath: String
    let content: String
    let mergeStrategy: (any PortableExportMergeStrategy)?

    init(
        url: URL,
        relativePath: String,
        content: String,
        mergeStrategy: (any PortableExportMergeStrategy)? = nil
    ) {
        self.url = url
        self.relativePath = relativePath
        self.content = content
        self.mergeStrategy = mergeStrategy
    }
}

enum PortableExportWriteAction: String, Codable, Equatable {
    case created
    case overwritten
    case appended
    case updated
}

struct PortableExportWriteResult: Equatable {
    let url: URL
    let relativePath: String
    let action: PortableExportWriteAction
}

struct PortableExportFileWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func write(_ file: PortableRenderedExportFile, mode: PortableExportWriteMode) throws -> PortableExportWriteResult {
        let parent = file.url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let exists = fileManager.fileExists(atPath: file.url.path)
        let finalContent: String
        let action: PortableExportWriteAction

        if exists {
            switch mode {
            case .overwrite:
                finalContent = file.content
                action = .overwritten
            case .append:
                let existing = try String(contentsOf: file.url, encoding: .utf8)
                finalContent = existing + "\n\n" + file.content
                action = .appended
            case .update:
                if let mergeStrategy = file.mergeStrategy {
                    let existing = try String(contentsOf: file.url, encoding: .utf8)
                    finalContent = try mergeStrategy.merge(existing: existing, new: file.content)
                    action = .updated
                } else {
                    finalContent = file.content
                    action = .overwritten
                }
            }
        } else {
            finalContent = file.content
            action = .created
        }

        try finalContent.write(to: file.url, atomically: true, encoding: .utf8)
        return PortableExportWriteResult(url: file.url, relativePath: file.relativePath, action: action)
    }
}

struct PortableExportRenderContext<Record: PortableExportRecord> {
    let record: Record
    let request: PortableExportRequest
    let configuration: PortableExportConfiguration
    let format: PortableExportFormat
    let relativePath: String
    let url: URL
}

struct AnyPortableExportRenderer<Record: PortableExportRecord> {
    let format: PortableExportFormat
    let mergeStrategy: (any PortableExportMergeStrategy)?
    private let renderBlock: (Record, PortableExportRenderContext<Record>) async throws -> String

    init(
        format: PortableExportFormat,
        mergeStrategy: (any PortableExportMergeStrategy)? = nil,
        render: @escaping (Record, PortableExportRenderContext<Record>) async throws -> String
    ) {
        self.format = format
        self.mergeStrategy = mergeStrategy
        self.renderBlock = render
    }

    func render(record: Record, context: PortableExportRenderContext<Record>) async throws -> String {
        try await renderBlock(record, context)
    }
}

struct AnyPortableExportDataSource<Record: PortableExportRecord> {
    private let fetchBlock: (PortableExportRequest) async throws -> [Record]

    init(fetch: @escaping (PortableExportRequest) async throws -> [Record]) {
        self.fetchBlock = fetch
    }

    func records(for request: PortableExportRequest) async throws -> [Record] {
        try await fetchBlock(request)
    }
}

struct PortableExportPluginContext<Record: PortableExportRecord> {
    let record: Record
    let request: PortableExportRequest
    let configuration: PortableExportConfiguration
    let destinationRoot: URL

    func renderedFile(
        relativePath template: String,
        content: String,
        mergeStrategy: (any PortableExportMergeStrategy)? = nil
    ) throws -> PortableRenderedExportFile {
        let resolved = try PortableExportPathPlanner.renderedRelativePath(
            template,
            rootURL: destinationRoot,
            record: record,
            configuration: configuration
        )
        return PortableRenderedExportFile(
            url: resolved.url,
            relativePath: resolved.relativePath,
            content: content,
            mergeStrategy: mergeStrategy
        )
    }
}

struct AnyPortableExportPlugin<Record: PortableExportRecord> {
    private let additionalFilesBlock: (Record, PortableExportPluginContext<Record>) async throws -> [PortableRenderedExportFile]

    init(
        additionalFiles: @escaping (Record, PortableExportPluginContext<Record>) async throws -> [PortableRenderedExportFile] = { _, _ in [] }
    ) {
        self.additionalFilesBlock = additionalFiles
    }

    func additionalFiles(record: Record, context: PortableExportPluginContext<Record>) async throws -> [PortableRenderedExportFile] {
        try await additionalFilesBlock(record, context)
    }
}

// MARK: - Result Model

enum PortableExportFailureCategory: String, Codable, Equatable {
    case noData
    case dataProtected
    case destinationUnavailable
    case quotaBlocked
    case renderFailed
    case writeFailed
    case missingRenderer
    case pluginFailed
    case cancelled
    case unknown
}

struct PortableExportFailure: Codable, Equatable {
    let recordID: String?
    let date: Date?
    let category: PortableExportFailureCategory
    let message: String

    init(recordID: String?, date: Date?, category: PortableExportFailureCategory, message: String) {
        self.recordID = recordID
        self.date = date
        self.category = category
        self.message = message
    }
}

struct PortableExportRunResult: Codable, Equatable {
    let successfulRecordCount: Int
    let totalRecordCount: Int
    let filesWritten: Int
    let failures: [PortableExportFailure]
    let trigger: PortableExportTriggerSource

    init(
        successfulRecordCount: Int,
        totalRecordCount: Int,
        filesWritten: Int,
        failures: [PortableExportFailure],
        trigger: PortableExportTriggerSource
    ) {
        self.successfulRecordCount = successfulRecordCount
        self.totalRecordCount = totalRecordCount
        self.filesWritten = filesWritten
        self.failures = failures
        self.trigger = trigger
    }

    var isFullSuccess: Bool {
        totalRecordCount > 0 && successfulRecordCount == totalRecordCount && failures.isEmpty
    }

    var isFailure: Bool {
        successfulRecordCount == 0 && totalRecordCount > 0
    }
}

// MARK: - Orchestrator

struct PortableExportOrchestrator<Record: PortableExportRecord> {
    private let dataSource: AnyPortableExportDataSource<Record>
    private let renderers: [AnyPortableExportRenderer<Record>]
    private let plugins: [AnyPortableExportPlugin<Record>]
    private let fileWriter: PortableExportFileWriter

    init(
        dataSource: AnyPortableExportDataSource<Record>,
        renderers: [AnyPortableExportRenderer<Record>],
        plugins: [AnyPortableExportPlugin<Record>] = [],
        fileWriter: PortableExportFileWriter = PortableExportFileWriter()
    ) {
        self.dataSource = dataSource
        self.renderers = renderers
        self.plugins = plugins
        self.fileWriter = fileWriter
    }

    func export(
        request: PortableExportRequest,
        destinationRoot: URL,
        configuration: PortableExportConfiguration,
        onProgress: ((_ processedRecords: Int, _ totalRecords: Int, _ currentRecordID: String) -> Void)? = nil
    ) async -> PortableExportRunResult {
        let records: [Record]
        do {
            records = try await dataSource.records(for: request)
        } catch {
            return PortableExportRunResult(
                successfulRecordCount: 0,
                totalRecordCount: 0,
                filesWritten: 0,
                failures: [PortableExportFailure(recordID: nil, date: nil, category: .unknown, message: error.localizedDescription)],
                trigger: request.trigger
            )
        }

        let rendererByID = Dictionary(uniqueKeysWithValues: renderers.map { ($0.format.id, $0) })
        var successCount = 0
        var filesWritten = 0
        var failures: [PortableExportFailure] = []

        for (index, record) in records.enumerated() {
            if Task.isCancelled {
                failures.append(PortableExportFailure(
                    recordID: record.portableExportID,
                    date: record.portableExportDate,
                    category: .cancelled,
                    message: "Export cancelled"
                ))
                break
            }

            onProgress?(index + 1, records.count, record.portableExportID)

            guard record.hasPortableExportableData else {
                failures.append(PortableExportFailure(
                    recordID: record.portableExportID,
                    date: record.portableExportDate,
                    category: .noData,
                    message: "No exportable data"
                ))
                continue
            }

            var recordFailed = false

            for format in configuration.formats {
                guard let renderer = rendererByID[format.id] else {
                    recordFailed = true
                    failures.append(PortableExportFailure(
                        recordID: record.portableExportID,
                        date: record.portableExportDate,
                        category: .missingRenderer,
                        message: "No renderer registered for format \(format.id)"
                    ))
                    continue
                }

                do {
                    let plan = try PortableExportPathPlanner.planFile(
                        rootURL: destinationRoot,
                        record: record,
                        format: format,
                        configuration: configuration
                    )
                    let context = PortableExportRenderContext(
                        record: record,
                        request: request,
                        configuration: configuration,
                        format: format,
                        relativePath: plan.relativePath,
                        url: plan.url
                    )
                    let content = try await renderer.render(record: record, context: context)
                    let renderedFile = PortableRenderedExportFile(
                        url: plan.url,
                        relativePath: plan.relativePath,
                        content: content,
                        mergeStrategy: renderer.mergeStrategy
                    )
                    _ = try fileWriter.write(renderedFile, mode: configuration.writeMode)
                    filesWritten += 1
                } catch {
                    recordFailed = true
                    failures.append(PortableExportFailure(
                        recordID: record.portableExportID,
                        date: record.portableExportDate,
                        category: error is PortableExportPathError ? .writeFailed : .renderFailed,
                        message: error.localizedDescription
                    ))
                }
            }

            for plugin in plugins {
                do {
                    let context = PortableExportPluginContext(
                        record: record,
                        request: request,
                        configuration: configuration,
                        destinationRoot: destinationRoot
                    )
                    let files = try await plugin.additionalFiles(record: record, context: context)
                    for file in files {
                        _ = try fileWriter.write(file, mode: configuration.writeMode)
                        filesWritten += 1
                    }
                } catch {
                    recordFailed = true
                    failures.append(PortableExportFailure(
                        recordID: record.portableExportID,
                        date: record.portableExportDate,
                        category: .pluginFailed,
                        message: error.localizedDescription
                    ))
                }
            }

            if !recordFailed {
                successCount += 1
            }
        }

        return PortableExportRunResult(
            successfulRecordCount: successCount,
            totalRecordCount: records.count,
            filesWritten: filesWritten,
            failures: failures,
            trigger: request.trigger
        )
    }
}
