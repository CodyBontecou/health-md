import Foundation

/// Data-agnostic metadata describing an export format.
///
/// This is intentionally independent of app-specific models so future adopters
/// can register formats without editing a shared enum.
public struct ExportFormatDescriptor: Hashable, Codable, Sendable {
    public var id: String
    public var displayName: String
    public var fileExtension: String
    public var collisionSuffix: String?
    public var contentType: String
    public var defaultSortKey: String

    public init(
        id: String,
        displayName: String,
        fileExtension: String,
        collisionSuffix: String? = nil,
        contentType: String,
        defaultSortKey: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.collisionSuffix = collisionSuffix
        self.contentType = contentType
        self.defaultSortKey = defaultSortKey ?? displayName
    }
}

/// Minimal record contract for renderers. ExportKit core deliberately knows
/// nothing about the record's domain beyond identity and date.
public protocol ExportRecord {
    var exportRecordID: String { get }
    var exportDate: Date { get }
}

/// Context supplied to renderers for future package extraction.
public struct ExportRenderContext: Equatable {
    public var locale: Locale
    public var calendar: Calendar
    public var userInfo: [String: String]

    public init(
        locale: Locale = .current,
        calendar: Calendar = .current,
        userInfo: [String: String] = [:]
    ) {
        self.locale = locale
        self.calendar = calendar
        self.userInfo = userInfo
    }

    public static let `default` = ExportRenderContext()
}

/// Rendered text plus MIME-style metadata from the selected descriptor.
public struct RenderedExport: Equatable {
    public var content: String
    public var contentType: String

    public init(content: String, contentType: String) {
        self.content = content
        self.contentType = contentType
    }
}

public protocol ExportRenderer {
    associatedtype Record: ExportRecord

    var descriptor: ExportFormatDescriptor { get }
    func render(record: Record, context: ExportRenderContext) throws -> RenderedExport
}

/// Type-erased renderer so registries can hold heterogeneous concrete renderers.
public struct AnyExportRenderer<Record: ExportRecord> {
    public var descriptor: ExportFormatDescriptor
    private let renderClosure: (Record, ExportRenderContext) throws -> RenderedExport

    public init(
        descriptor: ExportFormatDescriptor,
        render: @escaping (Record, ExportRenderContext) throws -> RenderedExport
    ) {
        self.descriptor = descriptor
        self.renderClosure = render
    }

    public init<Renderer: ExportRenderer>(_ renderer: Renderer) where Renderer.Record == Record {
        self.descriptor = renderer.descriptor
        self.renderClosure = renderer.render
    }

    public func render(record: Record, context: ExportRenderContext = .default) throws -> RenderedExport {
        try renderClosure(record, context)
    }
}

public enum ExportRendererRegistryError: Error, Equatable, LocalizedError {
    case duplicateFormatID(String)
    case missingFormatID(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateFormatID(let id):
            return "Duplicate export renderer registered for format id '\(id)'."
        case .missingFormatID(let id):
            return "No export renderer registered for format id '\(id)'."
        }
    }
}

public struct ResolvedExportFormat: Equatable {
    public var descriptor: ExportFormatDescriptor
    public var filename: String

    public init(descriptor: ExportFormatDescriptor, filename: String) {
        self.descriptor = descriptor
        self.filename = filename
    }
}

/// Registry for arbitrary record renderers keyed by format descriptor id.
public struct ExportRendererRegistry<Record: ExportRecord> {
    private var renderersByFormatID: [String: AnyExportRenderer<Record>]

    public init(renderers: [AnyExportRenderer<Record>] = []) throws {
        self.renderersByFormatID = [:]
        for renderer in renderers {
            try register(renderer)
        }
    }

    public var registeredFormatIDs: [String] {
        sortedDescriptors().map(\.id)
    }

    public mutating func register(_ renderer: AnyExportRenderer<Record>) throws {
        let id = renderer.descriptor.id
        guard renderersByFormatID[id] == nil else {
            throw ExportRendererRegistryError.duplicateFormatID(id)
        }
        renderersByFormatID[id] = renderer
    }

    public func renderer(for formatID: String) throws -> AnyExportRenderer<Record> {
        guard let renderer = renderersByFormatID[formatID] else {
            throw ExportRendererRegistryError.missingFormatID(formatID)
        }
        return renderer
    }

    public func render(
        record: Record,
        formatID: String,
        context: ExportRenderContext = .default
    ) throws -> RenderedExport {
        try renderer(for: formatID).render(record: record, context: context)
    }

    public func descriptors(for selectedFormatIDs: [String]? = nil) throws -> [ExportFormatDescriptor] {
        guard let selectedFormatIDs else {
            return sortedDescriptors()
        }

        let selectedIDSet = Set(selectedFormatIDs)
        for id in selectedIDSet where renderersByFormatID[id] == nil {
            throw ExportRendererRegistryError.missingFormatID(id)
        }

        return sortedDescriptors().filter { selectedIDSet.contains($0.id) }
    }

    /// Resolves deterministic filenames for the selected formats.
    ///
    /// Formats are sorted by descriptor sort key first. If multiple selected
    /// descriptors share an extension, their collision suffix is applied. If a
    /// descriptor has no collision suffix and would still collide, a stable id
    /// based fallback suffix is used for all but the first colliding file.
    public func resolvedFilenames(
        baseName: String,
        selectedFormatIDs: [String]? = nil
    ) throws -> [ResolvedExportFormat] {
        let descriptors = try descriptors(for: selectedFormatIDs)
        let extensionCounts = Dictionary(grouping: descriptors, by: { normalizedExtension($0.fileExtension) })
            .mapValues(\.count)
        var usedFilenames: Set<String> = []

        return descriptors.map { descriptor in
            let extensionKey = normalizedExtension(descriptor.fileExtension)
            let hasExtensionCollision = (extensionCounts[extensionKey] ?? 0) > 1
            var suffix = hasExtensionCollision ? (descriptor.collisionSuffix ?? "") : ""
            var filename = makeFilename(baseName: baseName, suffix: suffix, fileExtension: descriptor.fileExtension)

            if usedFilenames.contains(filename) {
                var fallbackIndex = 1
                repeat {
                    suffix = "-\(stableSuffix(from: descriptor.id))"
                    if fallbackIndex > 1 {
                        suffix += "-\(fallbackIndex)"
                    }
                    filename = makeFilename(baseName: baseName, suffix: suffix, fileExtension: descriptor.fileExtension)
                    fallbackIndex += 1
                } while usedFilenames.contains(filename)
            }

            usedFilenames.insert(filename)
            return ResolvedExportFormat(descriptor: descriptor, filename: filename)
        }
    }

    private func sortedDescriptors() -> [ExportFormatDescriptor] {
        renderersByFormatID.values
            .map(\.descriptor)
            .sorted { lhs, rhs in
                if lhs.defaultSortKey == rhs.defaultSortKey {
                    return lhs.id < rhs.id
                }
                return lhs.defaultSortKey < rhs.defaultSortKey
            }
    }

    private func normalizedExtension(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }

    private func makeFilename(baseName: String, suffix: String, fileExtension: String) -> String {
        "\(baseName)\(suffix).\(normalizedExtension(fileExtension))"
    }

    private func stableSuffix(from id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "format" : value
    }
}
