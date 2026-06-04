import Foundation

public enum ExportPluginOperation: String, Codable, Equatable {
    case preview
    case validation
    case write
}

public struct ExportPluginContext<Record: ExportRecord> {
    public var record: Record
    public var operation: ExportPluginOperation
    public var destination: ExportDestination?
    public var aggregateFiles: [PlannedExportFile]
    public var writeMode: ExportWriteMode
    public var userInfo: [String: String]

    public init(
        record: Record,
        operation: ExportPluginOperation,
        destination: ExportDestination? = nil,
        aggregateFiles: [PlannedExportFile] = [],
        writeMode: ExportWriteMode = .overwrite,
        userInfo: [String: String] = [:]
    ) {
        self.record = record
        self.operation = operation
        self.destination = destination
        self.aggregateFiles = aggregateFiles
        self.writeMode = writeMode
        self.userInfo = userInfo
    }
}

public struct ExportPluginPlan: Equatable {
    public var files: [PlannedExportFile]
    public var warnings: [ExportWarning]

    public init(files: [PlannedExportFile] = [], warnings: [ExportWarning] = []) {
        self.files = files
        self.warnings = warnings
    }
}

public struct ExportPluginRunResult: Equatable {
    public var pluginID: String
    public var filesWritten: Int
    public var warnings: [ExportWarning]
    public var metadata: [String: String]

    public init(
        pluginID: String,
        filesWritten: Int = 0,
        warnings: [ExportWarning] = [],
        metadata: [String: String] = [:]
    ) {
        self.pluginID = pluginID
        self.filesWritten = filesWritten
        self.warnings = warnings
        self.metadata = metadata
    }
}

public protocol ExportPlugin {
    associatedtype Record: ExportRecord

    var id: String { get }

    /// Validate plugin targets before aggregate files are written. Plugins can
    /// use this to reject mutations that would collide with aggregate outputs.
    func validate(record: Record, context: ExportPluginContext<Record>) throws -> [ExportWarning]

    /// Plan supplemental files or mutation targets for previews. Implementations
    /// should plan at record granularity, not once per aggregate format.
    func planFiles(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginPlan

    /// Run side effects after aggregate files for the record have been written.
    /// Supplemental file plugins may write files; mutation plugins may update
    /// existing files. The generic result shape reports counts, warnings, and
    /// plugin-owned metadata without teaching ExportKit app concepts.
    func performSideEffects(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginRunResult
}

public extension ExportPlugin {
    func validate(record: Record, context: ExportPluginContext<Record>) throws -> [ExportWarning] { [] }

    func planFiles(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginPlan {
        ExportPluginPlan()
    }

    func performSideEffects(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginRunResult {
        ExportPluginRunResult(pluginID: id)
    }
}

public struct AnyExportPlugin<Record: ExportRecord> {
    public let id: String

    private let validateClosure: (Record, ExportPluginContext<Record>) throws -> [ExportWarning]
    private let planFilesClosure: (Record, ExportPluginContext<Record>) throws -> ExportPluginPlan
    private let performSideEffectsClosure: (Record, ExportPluginContext<Record>) throws -> ExportPluginRunResult

    public init<Plugin: ExportPlugin>(_ plugin: Plugin) where Plugin.Record == Record {
        self.id = plugin.id
        self.validateClosure = plugin.validate
        self.planFilesClosure = plugin.planFiles
        self.performSideEffectsClosure = plugin.performSideEffects
    }

    public init(
        id: String,
        validate: @escaping (Record, ExportPluginContext<Record>) throws -> [ExportWarning] = { _, _ in [] },
        planFiles: @escaping (Record, ExportPluginContext<Record>) throws -> ExportPluginPlan = { _, _ in ExportPluginPlan() },
        performSideEffects: ((Record, ExportPluginContext<Record>) throws -> ExportPluginRunResult)? = nil
    ) {
        self.id = id
        self.validateClosure = validate
        self.planFilesClosure = planFiles
        self.performSideEffectsClosure = performSideEffects ?? { _, _ in ExportPluginRunResult(pluginID: id) }
    }

    public func validate(record: Record, context: ExportPluginContext<Record>) throws -> [ExportWarning] {
        try validateClosure(record, context)
    }

    public func planFiles(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginPlan {
        try planFilesClosure(record, context)
    }

    public func performSideEffects(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginRunResult {
        try performSideEffectsClosure(record, context)
    }
}

public struct ExportPluginCollision: Equatable, LocalizedError {
    public var pluginID: String
    public var mutationRelativePath: String
    public var aggregateRelativePath: String
    public var message: String

    public init(
        pluginID: String,
        mutationRelativePath: String,
        aggregateRelativePath: String,
        message: String? = nil
    ) {
        self.pluginID = pluginID
        self.mutationRelativePath = mutationRelativePath
        self.aggregateRelativePath = aggregateRelativePath
        self.message = message ?? "Plugin mutation target conflicts with aggregate output: \(mutationRelativePath)."
    }

    public var errorDescription: String? { message }
}

public enum ExportPluginCollisionDetector {
    public static func mutationCollisions(
        pluginFiles: [PlannedExportFile],
        aggregateFiles: [PlannedExportFile]
    ) -> [ExportPluginCollision] {
        pluginFiles.compactMap { pluginFile in
            guard case .mutation(let pluginID) = pluginFile.role else { return nil }
            guard let aggregateFile = aggregateFiles.first(where: {
                sameRelativePath(pluginFile.relativePath, $0.relativePath)
            }) else { return nil }

            return ExportPluginCollision(
                pluginID: pluginID,
                mutationRelativePath: pluginFile.relativePath,
                aggregateRelativePath: aggregateFile.relativePath
            )
        }
    }

    public static func sameRelativePath(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhsURL = normalizedURL(for: lhs), let rhsURL = normalizedURL(for: rhs) else {
            return normalizedFallback(lhs) == normalizedFallback(rhs)
        }
        return lhsURL.standardizedFileURL.path == rhsURL.standardizedFileURL.path
    }

    private static func normalizedURL(for relativePath: String) -> URL? {
        let root = URL(fileURLWithPath: "/__ExportKitPluginRoot__", isDirectory: true)
        return try? ExportPathSafetyPolicy.rejectTraversalAndAbsolutePaths.appending(
            relativePath,
            to: root,
            isDirectory: false
        )
    }

    private static func normalizedFallback(_ relativePath: String) -> String {
        relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}

public struct ExportPluginRunner<Record: ExportRecord> {
    public var plugins: [AnyExportPlugin<Record>]

    public init(plugins: [AnyExportPlugin<Record>] = []) {
        self.plugins = plugins
    }

    public func validate(record: Record, context: ExportPluginContext<Record>) throws -> [ExportWarning] {
        try plugins.flatMap { plugin in
            try plugin.validate(record: record, context: context)
        }
    }

    public func planFiles(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginPlan {
        var files: [PlannedExportFile] = []
        var warnings: [ExportWarning] = []

        for plugin in plugins {
            let plan = try plugin.planFiles(record: record, context: context)
            files.append(contentsOf: plan.files)
            warnings.append(contentsOf: plan.warnings)
        }

        return ExportPluginPlan(files: files, warnings: warnings)
    }

    public func performSideEffects(record: Record, context: ExportPluginContext<Record>) throws -> [ExportPluginRunResult] {
        try plugins.map { plugin in
            try plugin.performSideEffects(record: record, context: context)
        }
    }

    public func previewSupplementalPlan(record: Record, context: ExportPluginContext<Record>) throws -> ExportPreviewSupplementalPlan {
        let plan = try planFiles(record: record, context: context)
        return ExportPreviewSupplementalPlan(files: plan.files, warnings: plan.warnings)
    }
}
