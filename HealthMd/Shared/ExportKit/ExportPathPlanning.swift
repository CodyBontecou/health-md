import Foundation

/// Date and app-specific values used when expanding export path templates.
///
/// ExportKit owns the generic placeholder mechanics. Apps can pass extra values
/// such as `project`, `client`, `recordID`, or `format` without teaching the
/// reusable core about their domain models.
public struct ExportPathVariables: Codable, Equatable, Sendable {
    public var date: Date
    public var values: [String: String]

    public init(date: Date, values: [String: String] = [:]) {
        self.date = date
        self.values = values
    }

    public var resolvedValues: [String: String] {
        var resolved = Self.datePlaceholderValues(for: date)
        for (key, value) in values {
            resolved[key] = value
        }
        return resolved
    }

    public func applying(to template: String) -> String {
        var result = template
        for key in resolvedValues.keys.sorted() {
            guard let value = resolvedValues[key] else { continue }
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    public static func datePlaceholderValues(for date: Date) -> [String: String] {
        let month = Calendar.current.component(.month, from: date)
        return [
            "date": formatted(date, as: "yyyy-MM-dd"),
            "year": formatted(date, as: "yyyy"),
            "month": formatted(date, as: "MM"),
            "day": formatted(date, as: "dd"),
            "weekday": formatted(date, as: "EEEE"),
            "monthName": formatted(date, as: "MMMM"),
            "quarter": "Q\((month - 1) / 3 + 1)"
        ]
    }

    private static func formatted(_ date: Date, as dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }
}

public struct ExportPathTemplate: Codable, Equatable, Sendable {
    public var folderTemplate: String
    public var filenameTemplate: String
    public var fileExtension: String

    public init(
        folderTemplate: String = "",
        filenameTemplate: String,
        fileExtension: String
    ) {
        self.folderTemplate = folderTemplate
        self.filenameTemplate = filenameTemplate
        self.fileExtension = fileExtension
    }

    public func expandedFolderPath(variables: ExportPathVariables) -> String {
        variables.applying(to: folderTemplate)
    }

    public func expandedFilename(variables: ExportPathVariables) -> String {
        let baseName = variables.applying(to: filenameTemplate)
        let normalizedExtension = Self.normalizedExtension(fileExtension)
        guard !normalizedExtension.isEmpty else { return baseName }
        return "\(baseName).\(normalizedExtension)"
    }

    public func plan(
        variables: ExportPathVariables,
        safetyPolicy: ExportPathSafetyPolicy = .rejectTraversalAndAbsolutePaths
    ) throws -> ExportPathPlan {
        let folderPath = expandedFolderPath(variables: variables)
        let filename = expandedFilename(variables: variables)
        let folderComponents = try safetyPolicy.pathSegments(from: folderPath)
        let filenameComponents = try safetyPolicy.pathSegments(from: filename)
        let components = folderComponents + filenameComponents
        return ExportPathPlan(
            folderPath: folderComponents.joined(separator: "/"),
            filename: filenameComponents.joined(separator: "/"),
            relativePath: components.joined(separator: "/"),
            components: components
        )
    }

    public func plannedRelativePath(
        variables: ExportPathVariables,
        safetyPolicy: ExportPathSafetyPolicy = .rejectTraversalAndAbsolutePaths
    ) throws -> String {
        try plan(variables: variables, safetyPolicy: safetyPolicy).relativePath
    }

    private static func normalizedExtension(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

public struct ExportPathPlan: Codable, Equatable, Sendable {
    public var folderPath: String
    public var filename: String
    public var relativePath: String
    public var components: [String]

    public init(folderPath: String, filename: String, relativePath: String, components: [String]) {
        self.folderPath = folderPath
        self.filename = filename
        self.relativePath = relativePath
        self.components = components
    }
}

public enum ExportPathSafetyPolicy: String, Codable, Equatable, Sendable {
    /// Compatibility mode for legacy display/preview behavior:
    /// trim the full string, split on `/`, and drop empty segments.
    case preserveCurrentBehavior

    /// Compatibility slash handling plus hard failures for paths that could
    /// escape the selected destination.
    case rejectTraversalAndAbsolutePaths

    /// Rewrites unsafe components so a path stays destination-relative. Apps that
    /// require strict safety can choose rejection instead of silent rewriting.
    case sanitizePathComponents

    public func pathSegments(from rawPath: String) throws -> [String] {
        switch self {
        case .preserveCurrentBehavior:
            return Self.compatibilitySegments(from: rawPath)

        case .rejectTraversalAndAbsolutePaths:
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAbsolutePath(trimmed) {
                throw ExportPathTemplateError.absolutePathNotAllowed(rawPath)
            }

            let segments = Self.compatibilitySegments(from: rawPath)
            for segment in segments {
                if segment == ".." {
                    throw ExportPathTemplateError.pathTraversalNotAllowed(rawPath)
                }
                if Self.containsInvalidFilenameCharacter(segment) {
                    throw ExportPathTemplateError.invalidPathComponent(segment, reason: "contains a NUL character")
                }
            }
            return segments

        case .sanitizePathComponents:
            return Self.compatibilitySegments(from: Self.removingAbsolutePrefix(from: rawPath))
                .compactMap { segment in
                    guard segment != ".", segment != ".." else { return nil }
                    let sanitized = Self.sanitizedComponent(segment)
                    return sanitized.isEmpty ? nil : sanitized
                }
        }
    }

    public func relativePath(from rawComponents: [String]) throws -> String {
        try rawComponents.flatMap { try pathSegments(from: $0) }.joined(separator: "/")
    }

    public func appending(_ rawPath: String, to baseURL: URL, isDirectory: Bool) throws -> URL {
        let segments = try pathSegments(from: rawPath)
        guard !segments.isEmpty else { return baseURL }

        var url = baseURL
        for (index, segment) in segments.enumerated() {
            let segmentIsDirectory = isDirectory || index < segments.count - 1
            url = url.appendingPathComponent(segment, isDirectory: segmentIsDirectory)
        }
        return url
    }

    private static func compatibilitySegments(from rawPath: String) -> [String] {
        rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\") { return true }
        return path.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }

    private static func removingAbsolutePrefix(from rawPath: String) -> String {
        var result = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("/") || result.hasPrefix("\\") {
            result.removeFirst()
        }
        if let driveRange = result.range(of: #"^[A-Za-z]:[\\/]*"#, options: .regularExpression) {
            result.removeSubrange(driveRange)
        }
        return result
    }

    private static func containsInvalidFilenameCharacter(_ component: String) -> Bool {
        component.unicodeScalars.contains { $0.value == 0 }
    }

    private static func sanitizedComponent(_ component: String) -> String {
        let invalid = CharacterSet(charactersIn: "\u{0}<>:\"|?*")
        let scalars = component.unicodeScalars.map { scalar -> Character in
            invalid.contains(scalar) ? "_" : Character(scalar)
        }
        return String(scalars)
    }
}

public enum ExportPathTemplateError: Error, Equatable, LocalizedError, Sendable {
    case absolutePathNotAllowed(String)
    case pathTraversalNotAllowed(String)
    case invalidPathComponent(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .absolutePathNotAllowed:
            return "Export path templates must be relative to the selected destination. Absolute paths are not allowed."
        case .pathTraversalNotAllowed:
            return "Export path templates cannot contain '..' because traversal could write outside the selected destination."
        case .invalidPathComponent(let component, let reason):
            return "Export path component '\(component)' is invalid: \(reason)."
        }
    }
}

public struct ExportWarning: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var message: String

    public init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

public struct PlannedExportFile: Codable, Equatable, Identifiable, Sendable {
    public enum Role: Codable, Equatable, Sendable {
        case aggregate(formatID: String)
        case supplemental(pluginID: String)
        case mutation(pluginID: String)
    }

    public var id: String
    public var role: Role
    public var relativePath: String
    public var destinationURL: URL?
    public var content: String
    public var warnings: [ExportWarning]
    public var format: ExportFormatDescriptor?
    public var contentType: String?
    public var displayName: String?
    public var estimatedByteCount: Int?

    public init(
        id: String,
        role: Role,
        relativePath: String,
        destinationURL: URL? = nil,
        content: String = "",
        warnings: [ExportWarning] = [],
        format: ExportFormatDescriptor? = nil,
        contentType: String? = nil,
        displayName: String? = nil,
        estimatedByteCount: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.relativePath = relativePath
        self.destinationURL = destinationURL
        self.content = content
        self.warnings = warnings
        self.format = format
        self.contentType = contentType
        self.displayName = displayName
        self.estimatedByteCount = estimatedByteCount
    }

    public var filename: String {
        pathComponents.last ?? relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var relativeFolderPath: String {
        let folderComponents = pathComponents.dropLast()
        return folderComponents.joined(separator: "/")
    }

    public var renderedByteCount: Int { content.utf8.count }
    public var previewByteCount: Int { estimatedByteCount ?? renderedByteCount }
    public var sizeLabel: String { ExportPreviewDisplayContent.sizeLabel(for: previewByteCount) }

    public func displayContent(
        maximumRenderedBytes: Int = ExportPreviewDisplayContent.defaultMaximumRenderedBytes,
        headBytes: Int = ExportPreviewDisplayContent.defaultHeadBytes,
        tailBytes: Int = ExportPreviewDisplayContent.defaultTailBytes
    ) -> ExportPreviewDisplayContent {
        ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: maximumRenderedBytes,
            headBytes: headBytes,
            tailBytes: tailBytes
        )
    }

    private var pathComponents: [String] {
        relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
