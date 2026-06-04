import Foundation
import ExportKit

enum HealthExportPluginIDs {
    static let dailyNoteInjection = "healthmd.daily-note-injection"
    static let individualEntry = "healthmd.individual-entry"
}

enum HealthExportPluginError: LocalizedError, Equatable {
    case dailyNotePathConflict(path: String)
    case missingDestination(pluginID: String)

    var errorDescription: String? {
        switch self {
        case .dailyNotePathConflict(let path):
            return "Daily Note Injection target conflicts with export output: \(path). Change Output folder/filename or Daily Note Injection folder/filename."
        case .missingDestination(let pluginID):
            return "Plugin '\(pluginID)' requires an export destination."
        }
    }
}

enum HealthDailyNoteInjectionStatus: Equatable {
    case updated(path: String)
    case skipped(reason: String)
    case failed(description: String)
}

struct HealthExportPluginSideEffectSummary: Equatable {
    var individualEntriesCount: Int = 0
    var dailyNoteStatus: HealthDailyNoteInjectionStatus?

    static func make(from results: [ExportPluginRunResult]) -> HealthExportPluginSideEffectSummary {
        var summary = HealthExportPluginSideEffectSummary()
        for result in results {
            switch result.pluginID {
            case HealthExportPluginIDs.individualEntry:
                if let count = result.metadata[HealthIndividualEntryExportPlugin.metadataCountKey].flatMap(Int.init) {
                    summary.individualEntriesCount += count
                } else {
                    summary.individualEntriesCount += result.filesWritten
                }
            case HealthExportPluginIDs.dailyNoteInjection:
                summary.dailyNoteStatus = HealthDailyNoteInjectionPlugin.status(from: result.metadata)
            default:
                break
            }
        }
        return summary
    }
}

enum HealthDailyNotePreviewBaseResolution {
    case resolved(DailyNoteInjector.InjectionPreviewBase)
    case missing
    case unreadable(Error)
}

struct HealthDailyNoteInjectionPlugin: ExportPlugin {
    typealias Record = HealthExportRecord

    static let statusKey = "healthmd.daily-note.status"
    static let pathKey = "healthmd.daily-note.path"
    static let reasonKey = "healthmd.daily-note.reason"
    static let errorDescriptionKey = "healthmd.daily-note.errorDescription"

    let id = HealthExportPluginIDs.dailyNoteInjection
    let settings: DailyNoteInjectionSettings
    let customization: FormatCustomization
    let metricSelection: MetricSelectionState
    let previewBaseResolver: ((Date) -> HealthDailyNotePreviewBaseResolution)?

    init(
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization,
        metricSelection: MetricSelectionState,
        previewBaseResolver: ((Date) -> HealthDailyNotePreviewBaseResolution)? = nil
    ) {
        self.settings = settings
        self.customization = customization
        self.metricSelection = metricSelection
        self.previewBaseResolver = previewBaseResolver
    }

    func validate(record: HealthExportRecord, context: ExportPluginContext<HealthExportRecord>) throws -> [ExportWarning] {
        guard settings.enabled else { return [] }

        try ExportPathPlanner.validateDailyNotePath(
            settings: settings,
            date: record.exportDate
        )

        let mutationTarget = try mutationTarget(for: record.exportDate, safe: true)
        if let collision = ExportPluginCollisionDetector.mutationCollisions(
            pluginFiles: [mutationTarget],
            aggregateFiles: context.aggregateFiles
        ).first {
            throw HealthExportPluginError.dailyNotePathConflict(path: collision.mutationRelativePath)
        }

        return []
    }

    func planFiles(record: HealthExportRecord, context: ExportPluginContext<HealthExportRecord>) throws -> ExportPluginPlan {
        guard settings.enabled else { return ExportPluginPlan() }

        var warnings = collisionWarnings(for: record.healthData.date, aggregateFiles: context.aggregateFiles)

        let previewBase: DailyNoteInjector.InjectionPreviewBase
        switch previewBaseResolver?(record.healthData.date) ?? .resolved(.emptyDocument) {
        case .resolved(let base):
            previewBase = base
        case .missing:
            warnings.append(warning(
                for: record.healthData.date,
                message: "Daily note not found and Create note if missing is off: \(settings.previewPath(for: record.healthData.date))"
            ))
            return ExportPluginPlan(warnings: warnings)
        case .unreadable(let error):
            warnings.append(warning(
                for: record.healthData.date,
                message: "Could not read the existing daily note for preview: \(error.localizedDescription)"
            ))
            return ExportPluginPlan(warnings: warnings)
        }

        let result = DailyNoteInjector.preview(
            healthData: record.healthData,
            base: previewBase,
            settings: settings,
            customization: customization,
            metricSelection: metricSelection
        )

        switch result {
        case .preview(let preview):
            return ExportPluginPlan(
                files: [PlannedExportFile(
                    id: "\(record.healthData.date.timeIntervalSince1970)-daily-note-injection",
                    role: .mutation(pluginID: id),
                    relativePath: preview.path,
                    content: preview.content,
                    contentType: "text/markdown",
                    displayName: "Daily Note Injection"
                )],
                warnings: warnings
            )
        case .skipped(let reason):
            warnings.append(warning(for: record.healthData.date, message: reason))
            return ExportPluginPlan(warnings: warnings)
        }
    }

    func performSideEffects(record: HealthExportRecord, context: ExportPluginContext<HealthExportRecord>) throws -> ExportPluginRunResult {
        guard settings.enabled else { return ExportPluginRunResult(pluginID: id) }
        guard let destination = context.destination else {
            throw HealthExportPluginError.missingDestination(pluginID: id)
        }

        let result = DailyNoteInjector.inject(
            healthData: record.healthData,
            into: destination.rootURL,
            settings: settings,
            customization: customization,
            metricSelection: metricSelection
        )

        return ExportPluginRunResult(
            pluginID: id,
            metadata: metadata(for: result)
        )
    }

    static func status(from metadata: [String: String]) -> HealthDailyNoteInjectionStatus? {
        switch metadata[statusKey] {
        case "updated":
            return .updated(path: metadata[pathKey] ?? "")
        case "skipped":
            return .skipped(reason: metadata[reasonKey] ?? "")
        case "failed":
            return .failed(description: metadata[errorDescriptionKey] ?? "Unknown error")
        default:
            return nil
        }
    }

    private func mutationTarget(for date: Date, safe: Bool) throws -> PlannedExportFile {
        let relativePath: String
        if safe {
            relativePath = try ExportPathPlanner.safeDailyNoteRelativePath(settings: settings, date: date)
        } else {
            relativePath = ExportPathPlanner.dailyNoteRelativePath(settings: settings, date: date)
        }
        return PlannedExportFile(
            id: "\(date.timeIntervalSince1970)-daily-note-target",
            role: .mutation(pluginID: id),
            relativePath: relativePath,
            contentType: "text/markdown",
            displayName: "Daily Note Injection"
        )
    }

    private func collisionWarnings(for date: Date, aggregateFiles: [PlannedExportFile]) -> [ExportWarning] {
        let target: PlannedExportFile
        do {
            target = try mutationTarget(for: date, safe: false)
        } catch {
            return [warning(for: date, message: error.localizedDescription)]
        }

        return ExportPluginCollisionDetector.mutationCollisions(
            pluginFiles: [target],
            aggregateFiles: aggregateFiles
        ).map { collision in
            warning(
                for: date,
                message: "Daily Note Injection target conflicts with export output: \(collision.mutationRelativePath). Change Output folder/filename or Daily Note Injection folder/filename."
            )
        }
    }

    private func metadata(for result: DailyNoteInjector.InjectionResult) -> [String: String] {
        switch result {
        case .updated(let path):
            return [Self.statusKey: "updated", Self.pathKey: path]
        case .skipped(let reason):
            return [Self.statusKey: "skipped", Self.reasonKey: reason]
        case .failed(let error):
            return [Self.statusKey: "failed", Self.errorDescriptionKey: error.localizedDescription]
        }
    }

    private func warning(for date: Date, message: String) -> ExportWarning {
        let failure = ExportPartialFailure(
            date: date,
            dataType: "Daily Note",
            dateRangeDescription: Self.dateLabelFormatter.string(from: date),
            errorDescription: message
        )
        return ExportWarning(
            id: "healthmd.preview.daily-note.\(date.timeIntervalSince1970).\(message)",
            message: failure.summary
        )
    }

    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()
}

struct HealthIndividualEntryExportPlugin: ExportPlugin {
    typealias Record = HealthExportRecord

    static let metadataCountKey = "healthmd.individual-entry.count"

    let id = HealthExportPluginIDs.individualEntry
    let settings: IndividualTrackingSettings
    let advancedSettings: AdvancedExportSettings
    let formatSettings: FormatCustomization
    let healthSubfolder: String
    let fileWriter: ExportFileWriter?

    init(
        settings: IndividualTrackingSettings,
        advancedSettings: AdvancedExportSettings,
        formatSettings: FormatCustomization,
        healthSubfolder: String,
        fileWriter: ExportFileWriter? = nil
    ) {
        self.settings = settings
        self.advancedSettings = advancedSettings
        self.formatSettings = formatSettings
        self.healthSubfolder = healthSubfolder
        self.fileWriter = fileWriter
    }

    func planFiles(record: HealthExportRecord, context: ExportPluginContext<HealthExportRecord>) throws -> ExportPluginPlan {
        guard settings.globalEnabled else { return ExportPluginPlan() }

        let exporter = IndividualEntryExporter()
        let samples = exporter.extractIndividualSamples(
            from: record.healthData,
            settings: settings
        )
        guard !samples.isEmpty else { return ExportPluginPlan() }

        let aggregateFolderPath = ExportPathPlanner.aggregateFolderRelativePath(
            healthSubfolder: healthSubfolder,
            settings: advancedSettings,
            date: record.healthData.date
        )

        let files = try samples.compactMap { sample -> PlannedExportFile? in
            guard settings.shouldTrackIndividually(sample.metricId) else { return nil }
            let metric = metricDefinition(for: sample)
            let entryFolderPath = settings.folderPath(for: metric)
            let filename = settings.filename(for: metric, date: sample.timestamp, time: sample.timestamp)
            let content = exporter.previewEntryContent(
                for: sample,
                formatSettings: formatSettings
            )
            let relativePath = try relativePath(
                aggregateFolderPath: aggregateFolderPath,
                entryFolderPath: entryFolderPath,
                filename: filename,
                operation: context.operation
            )

            return PlannedExportFile(
                id: "\(record.healthData.date.timeIntervalSince1970)-individual-\(sample.metricId)-\(filename)",
                role: .supplemental(pluginID: id),
                relativePath: relativePath,
                content: content,
                contentType: "text/markdown",
                displayName: "Individual Entry"
            )
        }

        return ExportPluginPlan(files: files)
    }

    func performSideEffects(record: HealthExportRecord, context: ExportPluginContext<HealthExportRecord>) throws -> ExportPluginRunResult {
        guard settings.globalEnabled else { return ExportPluginRunResult(pluginID: id) }
        guard let destination = context.destination, let fileWriter else {
            throw HealthExportPluginError.missingDestination(pluginID: id)
        }

        let plan = try planFiles(record: record, context: context)
        guard !plan.files.isEmpty else { return ExportPluginRunResult(pluginID: id) }

        let writeResults = try fileWriter.write(
            plan.files,
            to: destination,
            mode: .overwrite,
            atomically: true
        )

        return ExportPluginRunResult(
            pluginID: id,
            filesWritten: writeResults.count,
            warnings: plan.warnings,
            metadata: [Self.metadataCountKey: "\(writeResults.count)"]
        )
    }


    private func metricDefinition(for sample: IndividualHealthSample) -> HealthMetricDefinition {
        HealthMetrics.all.first(where: { $0.id == sample.metricId }) ?? HealthMetricDefinition(
            id: sample.metricId,
            name: sample.metricName,
            category: sample.category,
            unit: sample.unit,
            healthKitIdentifier: nil,
            metricType: .quantity,
            aggregation: .mostRecent
        )
    }

    private func relativePath(
        aggregateFolderPath: String,
        entryFolderPath: String,
        filename: String,
        operation: ExportPluginOperation
    ) throws -> String {
        switch operation {
        case .preview:
            return (try? ExportPathSafetyPolicy.preserveCurrentBehavior.relativePath(from: [
                aggregateFolderPath,
                entryFolderPath,
                filename
            ])) ?? ""
        case .validation, .write:
            _ = try ExportPathSafetyPolicy.rejectTraversalAndAbsolutePaths.pathSegments(from: entryFolderPath)
            _ = try ExportPathSafetyPolicy.rejectTraversalAndAbsolutePaths.pathSegments(from: filename)
            return try ExportPathSafetyPolicy.rejectTraversalAndAbsolutePaths.relativePath(from: [
                aggregateFolderPath,
                entryFolderPath,
                filename
            ])
        }
    }
}

enum HealthExportPluginAdapter {
    static func makePlugins(
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        fileWriter: ExportFileWriter? = nil,
        dailyNotePreviewBaseResolver: ((Date) -> HealthDailyNotePreviewBaseResolution)? = nil
    ) -> [AnyExportPlugin<HealthExportRecord>] {
        [
            AnyExportPlugin(HealthDailyNoteInjectionPlugin(
                settings: settings.dailyNoteInjection,
                customization: settings.formatCustomization,
                metricSelection: settings.metricSelection,
                previewBaseResolver: dailyNotePreviewBaseResolver
            )),
            AnyExportPlugin(HealthIndividualEntryExportPlugin(
                settings: settings.individualTracking,
                advancedSettings: settings,
                formatSettings: settings.formatCustomization,
                healthSubfolder: healthSubfolder,
                fileWriter: fileWriter
            ))
        ]
    }

    static func aggregateFiles(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> [PlannedExportFile] {
        (try? HealthAggregateExportAdapter.aggregateFiles(
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date,
            safetyPolicy: .preserveCurrentBehavior
        )) ?? []
    }

    static func context(
        record: HealthExportRecord,
        operation: ExportPluginOperation,
        destination: ExportDestination?,
        aggregateFiles: [PlannedExportFile],
        writeMode: ExportWriteMode
    ) -> ExportPluginContext<HealthExportRecord> {
        ExportPluginContext(
            record: record,
            operation: operation,
            destination: destination,
            aggregateFiles: aggregateFiles,
            writeMode: writeMode
        )
    }
}
