import Foundation

public struct ExportPreviewDisplayContent: Equatable, Sendable {
    public static let defaultMaximumRenderedBytes = 64 * 1024
    public static let defaultHeadBytes = 48 * 1024
    public static let defaultTailBytes = 16 * 1024

    public let text: String
    public let originalByteCount: Int
    public let omittedByteCount: Int

    public init(text: String, originalByteCount: Int, omittedByteCount: Int) {
        self.text = text
        self.originalByteCount = originalByteCount
        self.omittedByteCount = omittedByteCount
    }

    public var isTruncated: Bool { omittedByteCount > 0 }
    public var originalSizeLabel: String { Self.sizeLabel(for: originalByteCount) }
    public var omittedSizeLabel: String { Self.sizeLabel(for: omittedByteCount) }

    public static func make(
        from content: String,
        maximumRenderedBytes: Int = defaultMaximumRenderedBytes,
        headBytes: Int = defaultHeadBytes,
        tailBytes: Int = defaultTailBytes
    ) -> ExportPreviewDisplayContent {
        guard !content.isEmpty else {
            return ExportPreviewDisplayContent(
                text: "(empty file)",
                originalByteCount: 0,
                omittedByteCount: 0
            )
        }

        let originalByteCount = content.utf8.count
        guard originalByteCount > maximumRenderedBytes else {
            return ExportPreviewDisplayContent(
                text: content,
                originalByteCount: originalByteCount,
                omittedByteCount: 0
            )
        }

        let safeMaximumRenderedBytes = max(1, maximumRenderedBytes)
        let safeHeadBytes = min(max(0, headBytes), safeMaximumRenderedBytes)
        let safeTailBytes = min(max(0, tailBytes), max(0, safeMaximumRenderedBytes - safeHeadBytes))

        let head = prefix(of: content, maxUTF8Bytes: safeHeadBytes)
        let tail = suffix(of: content, maxUTF8Bytes: safeTailBytes)
        let renderedContentBytes = head.utf8.count + tail.utf8.count
        let omittedByteCount = max(0, originalByteCount - renderedContentBytes)
        let marker = "\n\n… Preview truncated: \(sizeLabel(for: omittedByteCount)) omitted from the middle of this \(sizeLabel(for: originalByteCount)) file. …\n\n"

        return ExportPreviewDisplayContent(
            text: head + marker + tail,
            originalByteCount: originalByteCount,
            omittedByteCount: omittedByteCount
        )
    }

    public static func sizeLabel(for bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    private static func prefix(of content: String, maxUTF8Bytes: Int) -> String {
        guard maxUTF8Bytes > 0 else { return "" }
        guard content.utf8.count > maxUTF8Bytes else { return content }

        var boundary = content.utf8.index(content.utf8.startIndex, offsetBy: maxUTF8Bytes)
        while boundary > content.utf8.startIndex {
            if let stringIndex = String.Index(boundary, within: content) {
                return String(content[..<stringIndex])
            }
            boundary = content.utf8.index(before: boundary)
        }
        return ""
    }

    private static func suffix(of content: String, maxUTF8Bytes: Int) -> String {
        guard maxUTF8Bytes > 0 else { return "" }
        guard content.utf8.count > maxUTF8Bytes else { return content }

        var boundary = content.utf8.index(content.utf8.endIndex, offsetBy: -maxUTF8Bytes)
        while boundary < content.utf8.endIndex {
            if let stringIndex = String.Index(boundary, within: content) {
                return String(content[stringIndex...])
            }
            boundary = content.utf8.index(after: boundary)
        }
        return ""
    }
}

public struct ExportPreviewSupplementalPlan: Equatable {
    public var files: [PlannedExportFile]
    public var warnings: [ExportWarning]

    public init(files: [PlannedExportFile] = [], warnings: [ExportWarning] = []) {
        self.files = files
        self.warnings = warnings
    }
}

public struct ExportPreviewRecord: Equatable, Identifiable {
    public var id: String { reference.id }
    public var reference: ExportRecordReference
    public var files: [PlannedExportFile]

    public init(reference: ExportRecordReference, files: [PlannedExportFile]) {
        self.reference = reference
        self.files = files
    }
}

public struct ExportPreview: Equatable {
    public var records: [ExportPreviewRecord]
    public var warnings: [ExportWarning]
    public var totalRecordCount: Int
    public var renderedRecordCount: Int
    public var fetchAttemptCount: Int
    public var maxRenderedRecords: Int
    public var maxFetchAttempts: Int

    public init(
        records: [ExportPreviewRecord] = [],
        warnings: [ExportWarning] = [],
        totalRecordCount: Int,
        renderedRecordCount: Int? = nil,
        fetchAttemptCount: Int = 0,
        maxRenderedRecords: Int,
        maxFetchAttempts: Int
    ) {
        self.records = records
        self.warnings = warnings
        self.totalRecordCount = totalRecordCount
        self.renderedRecordCount = renderedRecordCount ?? records.count
        self.fetchAttemptCount = fetchAttemptCount
        self.maxRenderedRecords = maxRenderedRecords
        self.maxFetchAttempts = maxFetchAttempts
    }

    public var plannedFilesByRecord: [Date: [PlannedExportFile]] {
        records.reduce(into: [:]) { result, previewRecord in
            guard let date = previewRecord.reference.date else { return }
            result[date] = previewRecord.files
        }
    }
}

public struct ExportPreviewRequest<Input, Record: ExportRecord> {
    public var recordInputs: [Input]
    public var selectedFormatIDs: [String]
    public var dataSource: AnyExportRecordDataSource<Input, Record>
    public var rendererRegistry: ExportRendererRegistry<Record>
    public var renderContext: ExportRenderContext
    public var requiresFormats: Bool
    public var recordReference: (Input) -> ExportRecordReference
    public var planAggregateFile: (Record, ExportFormatDescriptor, RenderedExport) throws -> PlannedExportFile
    public var supplementalFilePlanner: (Record, [PlannedExportFile]) async throws -> ExportPreviewSupplementalPlan

    public init(
        recordInputs: [Input],
        selectedFormatIDs: [String],
        dataSource: AnyExportRecordDataSource<Input, Record>,
        rendererRegistry: ExportRendererRegistry<Record>,
        renderContext: ExportRenderContext = .default,
        requiresFormats: Bool = true,
        recordReference: @escaping (Input) -> ExportRecordReference,
        planAggregateFile: @escaping (Record, ExportFormatDescriptor, RenderedExport) throws -> PlannedExportFile,
        supplementalFilePlanner: @escaping (Record) async throws -> ExportPreviewSupplementalPlan = { _ in ExportPreviewSupplementalPlan() }
    ) {
        self.recordInputs = recordInputs
        self.selectedFormatIDs = selectedFormatIDs
        self.dataSource = dataSource
        self.rendererRegistry = rendererRegistry
        self.renderContext = renderContext
        self.requiresFormats = requiresFormats
        self.recordReference = recordReference
        self.planAggregateFile = planAggregateFile
        self.supplementalFilePlanner = { record, _ in try await supplementalFilePlanner(record) }
    }

    public init(
        recordInputs: [Input],
        selectedFormatIDs: [String],
        dataSource: AnyExportRecordDataSource<Input, Record>,
        rendererRegistry: ExportRendererRegistry<Record>,
        renderContext: ExportRenderContext = .default,
        requiresFormats: Bool = true,
        recordReference: @escaping (Input) -> ExportRecordReference,
        planAggregateFile: @escaping (Record, ExportFormatDescriptor, RenderedExport) throws -> PlannedExportFile,
        supplementalFilePlanner: @escaping (Record, [PlannedExportFile]) async throws -> ExportPreviewSupplementalPlan
    ) {
        self.recordInputs = recordInputs
        self.selectedFormatIDs = selectedFormatIDs
        self.dataSource = dataSource
        self.rendererRegistry = rendererRegistry
        self.renderContext = renderContext
        self.requiresFormats = requiresFormats
        self.recordReference = recordReference
        self.planAggregateFile = planAggregateFile
        self.supplementalFilePlanner = supplementalFilePlanner
    }
}

public struct ExportPreviewBuilder<Input, Record: ExportRecord> {
    public static var defaultMaxRenderedRecords: Int { 5 }
    public static var defaultMaxFetchAttempts: Int { 14 }

    public var maxRenderedRecords: Int
    public var maxFetchAttempts: Int

    public init(
        maxRenderedRecords: Int = Self.defaultMaxRenderedRecords,
        maxFetchAttempts: Int = Self.defaultMaxFetchAttempts
    ) {
        self.maxRenderedRecords = max(0, maxRenderedRecords)
        self.maxFetchAttempts = max(0, maxFetchAttempts)
    }

    public func buildPreview(_ request: ExportPreviewRequest<Input, Record>) async throws -> ExportPreview {
        let totalRecordCount = request.recordInputs.count
        guard !request.requiresFormats || !request.selectedFormatIDs.isEmpty else {
            return ExportPreview(
                totalRecordCount: totalRecordCount,
                fetchAttemptCount: 0,
                maxRenderedRecords: maxRenderedRecords,
                maxFetchAttempts: maxFetchAttempts
            )
        }

        var records: [ExportPreviewRecord] = []
        var warnings: [ExportWarning] = []
        var attempts = 0
        let descriptors = try request.rendererRegistry.descriptors(for: request.selectedFormatIDs)

        for input in request.recordInputs.reversed() {
            if records.count >= maxRenderedRecords { break }
            if attempts >= maxFetchAttempts { break }
            attempts += 1

            let fetched = try await request.dataSource.fetchRecord(for: input)
            warnings.append(contentsOf: fetched.warnings)
            guard let record = fetched.record else { continue }

            var files: [PlannedExportFile] = []
            for descriptor in descriptors {
                let rendered = try request.rendererRegistry.render(
                    record: record,
                    formatID: descriptor.id,
                    context: request.renderContext
                )
                var file = try request.planAggregateFile(record, descriptor, rendered)
                if file.format == nil {
                    file.format = descriptor
                }
                if file.contentType == nil {
                    file.contentType = rendered.contentType
                }
                files.append(file)
                warnings.append(contentsOf: file.warnings)
            }

            let supplementalPlan = try await request.supplementalFilePlanner(record, files)
            files.append(contentsOf: supplementalPlan.files)
            warnings.append(contentsOf: supplementalPlan.warnings)
            warnings.append(contentsOf: supplementalPlan.files.flatMap(\.warnings))

            records.append(ExportPreviewRecord(
                reference: ExportRecordReference(
                    id: record.exportRecordID,
                    date: record.exportDate
                ),
                files: files
            ))
        }

        return ExportPreview(
            records: records,
            warnings: warnings,
            totalRecordCount: totalRecordCount,
            fetchAttemptCount: attempts,
            maxRenderedRecords: maxRenderedRecords,
            maxFetchAttempts: maxFetchAttempts
        )
    }
}
