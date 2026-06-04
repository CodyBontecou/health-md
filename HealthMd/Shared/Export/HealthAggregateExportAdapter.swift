import Foundation
import ExportKit

/// Health.md aggregate-export adapter that bridges app-owned settings/records into
/// ExportKit's generic renderer, path planning, and file writer APIs.
///
/// This adapter intentionally remains Health.md-specific: it can reference
/// `HealthData`, `AdvancedExportSettings`, and Health.md format settings while
/// keeping those concepts out of `HealthMd/Shared/ExportKit`.
enum HealthAggregateExportAdapter {
    struct Plan {
        var files: [PlannedExportFile]
        var displayFilenames: [String]

        init(files: [PlannedExportFile], displayFilenames: [String]) {
            self.files = files
            self.displayFilenames = displayFilenames
        }
    }

    struct WriteSummary {
        var plan: Plan
        var writeResults: [ExportFileWriteResult]

        var filesWritten: Int { writeResults.count }
        var displayFilenames: [String] { plan.displayFilenames }
        var leadingAction: ExportFileWriteAction { writeResults.first?.action ?? .exported }
    }

    static func selectedFormatIDs(settings: AdvancedExportSettings) -> [String] {
        settings.sortedExportFormats.map(\.exportKitFormatID)
    }

    static func planAggregateFiles(
        record: HealthExportRecord,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        renderContext: ExportRenderContext = .default,
        safetyPolicy: ExportPathSafetyPolicy = .rejectTraversalAndAbsolutePaths
    ) throws -> Plan {
        let registry = HealthExportRendererAdapter.registry(settings: settings)
        let descriptors = try registry.descriptors(for: selectedFormatIDs(settings: settings))
        let filenameByFormatID = try resolvedFilenamesByFormatID(
            registry: registry,
            settings: settings,
            date: record.exportDate
        )

        var files: [PlannedExportFile] = []
        var displayFilenames: [String] = []

        for descriptor in descriptors {
            let rendered = try registry.render(
                record: record,
                formatID: descriptor.id,
                context: renderContext
            )
            let displayFilename = filenameByFormatID[descriptor.id] ?? fallbackFilename(
                settings: settings,
                date: record.exportDate,
                descriptor: descriptor
            )
            let relativePath = try aggregateRelativePath(
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: record.exportDate,
                descriptor: descriptor,
                resolvedFilename: displayFilename,
                safetyPolicy: safetyPolicy
            )

            files.append(PlannedExportFile(
                id: "\(record.exportDate.timeIntervalSince1970)-aggregate-\(descriptor.id)",
                role: .aggregate(formatID: descriptor.id),
                relativePath: relativePath,
                content: rendered.content,
                format: descriptor,
                contentType: rendered.contentType,
                displayName: descriptor.displayName,
                estimatedByteCount: rendered.content.utf8.count
            ))
            displayFilenames.append(displayFilename)
        }

        return Plan(files: files, displayFilenames: displayFilenames)
    }

    static func aggregateFiles(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        safetyPolicy: ExportPathSafetyPolicy = .preserveCurrentBehavior
    ) throws -> [PlannedExportFile] {
        let registry = HealthExportRendererAdapter.registry(settings: settings)
        let descriptors = try registry.descriptors(for: selectedFormatIDs(settings: settings))
        let filenameByFormatID = try resolvedFilenamesByFormatID(
            registry: registry,
            settings: settings,
            date: date
        )

        return try descriptors.map { descriptor in
            let displayFilename = filenameByFormatID[descriptor.id] ?? fallbackFilename(
                settings: settings,
                date: date,
                descriptor: descriptor
            )
            let relativePath = try aggregateRelativePath(
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: date,
                descriptor: descriptor,
                resolvedFilename: displayFilename,
                safetyPolicy: safetyPolicy
            )
            return PlannedExportFile(
                id: "\(date.timeIntervalSince1970)-aggregate-\(descriptor.id)",
                role: .aggregate(formatID: descriptor.id),
                relativePath: relativePath,
                format: descriptor,
                contentType: descriptor.contentType,
                displayName: descriptor.displayName
            )
        }
    }

    static func plannedAggregateFile(
        record: HealthExportRecord,
        descriptor: ExportFormatDescriptor,
        rendered: RenderedExport,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        safetyPolicy: ExportPathSafetyPolicy = .preserveCurrentBehavior
    ) throws -> PlannedExportFile {
        let registry = HealthExportRendererAdapter.registry(settings: settings)
        let filenameByFormatID = try resolvedFilenamesByFormatID(
            registry: registry,
            settings: settings,
            date: record.exportDate
        )
        let displayFilename = filenameByFormatID[descriptor.id] ?? fallbackFilename(
            settings: settings,
            date: record.exportDate,
            descriptor: descriptor
        )
        let relativePath = try aggregateRelativePath(
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: record.exportDate,
            descriptor: descriptor,
            resolvedFilename: displayFilename,
            safetyPolicy: safetyPolicy
        )

        return PlannedExportFile(
            id: "\(record.exportRecordID)-aggregate-\(descriptor.id)",
            role: .aggregate(formatID: descriptor.id),
            relativePath: relativePath,
            content: rendered.content,
            format: descriptor,
            contentType: rendered.contentType,
            displayName: descriptor.displayName,
            estimatedByteCount: rendered.content.utf8.count
        )
    }

    static func write(
        plan: Plan,
        to destination: ExportDestination,
        settings: AdvancedExportSettings,
        fileWriter: ExportFileWriter
    ) throws -> WriteSummary {
        let results = try fileWriter.write(
            plan.files,
            to: destination,
            mode: exportKitWriteMode(for: settings.writeMode),
            mergeStrategies: aggregateMergeStrategies(),
            atomically: true
        )
        return WriteSummary(plan: plan, writeResults: results)
    }

    private static func aggregateRelativePath(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        descriptor: ExportFormatDescriptor,
        resolvedFilename: String,
        safetyPolicy: ExportPathSafetyPolicy
    ) throws -> String {
        let folderPath = try safetyPolicy.relativePath(from: [
            healthSubfolder,
            settings.formatFolderPath(for: date) ?? ""
        ])
        let filenameTemplate = filenameTemplate(
            fromResolvedFilename: resolvedFilename,
            fileExtension: descriptor.fileExtension
        )
        let template = ExportPathTemplate(
            folderTemplate: folderPath,
            filenameTemplate: filenameTemplate,
            fileExtension: descriptor.fileExtension
        )
        return try template.plannedRelativePath(
            variables: ExportPathVariables(date: date),
            safetyPolicy: safetyPolicy
        )
    }

    private static func resolvedFilenamesByFormatID(
        registry: ExportRendererRegistry<HealthExportRecord>,
        settings: AdvancedExportSettings,
        date: Date
    ) throws -> [String: String] {
        let selectedFormatIDs = selectedFormatIDs(settings: settings)
        let resolved = try registry.resolvedFilenames(
            baseName: settings.formatFilename(for: date),
            selectedFormatIDs: selectedFormatIDs
        )
        return Dictionary(uniqueKeysWithValues: resolved.map { ($0.descriptor.id, $0.filename) })
    }

    private static func filenameTemplate(fromResolvedFilename filename: String, fileExtension: String) -> String {
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalizedExtension.isEmpty else { return filename }

        let suffix = ".\(normalizedExtension)"
        guard filename.lowercased().hasSuffix(suffix.lowercased()) else {
            return filename
        }

        return String(filename.dropLast(suffix.count))
    }

    private static func fallbackFilename(
        settings: AdvancedExportSettings,
        date: Date,
        descriptor: ExportFormatDescriptor
    ) -> String {
        guard let format = ExportFormat(exportKitFormatID: descriptor.id) else {
            let base = settings.formatFilename(for: date)
            let ext = descriptor.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return ext.isEmpty ? base : "\(base).\(ext)"
        }
        return settings.filename(for: date, format: format)
    }

    private static func exportKitWriteMode(for writeMode: WriteMode) -> ExportWriteMode {
        switch writeMode {
        case .overwrite:
            return .overwrite
        case .append:
            return .append
        case .update:
            return .update
        }
    }

    private static func aggregateMergeStrategies() -> [String: any ExportMergeStrategy] {
        [
            ExportFormat.markdown.exportKitFormatID: MarkdownMergeStrategy(
                managedSectionNames: MarkdownMerger.managedSectionNames
            )
        ]
    }
}
