import Foundation

public struct ExportDestination: Codable, Equatable, Sendable {
    public var rootURL: URL
    public var displayName: String
    public var baseRelativePath: String

    public init(
        rootURL: URL,
        displayName: String? = nil,
        baseRelativePath: String = ""
    ) {
        self.rootURL = rootURL
        self.displayName = displayName ?? rootURL.lastPathComponent
        self.baseRelativePath = baseRelativePath
    }

    public func resolvedBaseURL(
        safetyPolicy: ExportPathSafetyPolicy = .rejectTraversalAndAbsolutePaths
    ) throws -> URL {
        try safetyPolicy.appending(baseRelativePath, to: rootURL, isDirectory: true)
    }
}

public struct ExportBookmarkResolution: Equatable, Sendable {
    public var url: URL
    public var isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public protocol ExportBookmarkAccessing {
    func resolveDestinationBookmark(data: Data) throws -> ExportBookmarkResolution
    func createDestinationBookmarkData(for url: URL) throws -> Data
    func startAccessingDestination(_ url: URL) -> Bool
    func stopAccessingDestination(_ url: URL)
}

public protocol ExportDestinationDataStoring {
    func destinationString(forKey key: String) -> String?
    func destinationBookmarkData(forKey key: String) -> Data?
    func setDestinationString(_ value: String?, forKey key: String)
    func setDestinationBookmarkData(_ value: Data?, forKey key: String)
    func removeDestinationValue(forKey key: String)
}

public struct ExportDestinationStoreKeys: Equatable, Sendable {
    public var bookmarkKey: String
    public var baseRelativePathKey: String

    public init(bookmarkKey: String, baseRelativePathKey: String) {
        self.bookmarkKey = bookmarkKey
        self.baseRelativePathKey = baseRelativePathKey
    }
}

public struct ExportDestinationBookmarkStore {
    private let storage: any ExportDestinationDataStoring
    private let bookmarkAccess: any ExportBookmarkAccessing
    private let keys: ExportDestinationStoreKeys
    private let defaultBaseRelativePath: String

    public init(
        storage: any ExportDestinationDataStoring,
        bookmarkAccess: any ExportBookmarkAccessing,
        keys: ExportDestinationStoreKeys,
        defaultBaseRelativePath: String = ""
    ) {
        self.storage = storage
        self.bookmarkAccess = bookmarkAccess
        self.keys = keys
        self.defaultBaseRelativePath = defaultBaseRelativePath
    }

    public func loadBaseRelativePath() -> String {
        storage.destinationString(forKey: keys.baseRelativePathKey) ?? defaultBaseRelativePath
    }

    public func saveBaseRelativePath(_ path: String) {
        storage.setDestinationString(path, forKey: keys.baseRelativePathKey)
    }

    public func loadDestination() throws -> ExportDestination? {
        guard let bookmarkData = storage.destinationBookmarkData(forKey: keys.bookmarkKey) else {
            return nil
        }

        do {
            let resolution = try bookmarkAccess.resolveDestinationBookmark(data: bookmarkData)
            if resolution.isStale, bookmarkAccess.startAccessingDestination(resolution.url) {
                defer { bookmarkAccess.stopAccessingDestination(resolution.url) }
                try saveBookmark(for: resolution.url)
            }

            return ExportDestination(
                rootURL: resolution.url,
                displayName: resolution.url.lastPathComponent,
                baseRelativePath: loadBaseRelativePath()
            )
        } catch {
            storage.removeDestinationValue(forKey: keys.bookmarkKey)
            throw error
        }
    }

    public func saveBookmark(for rootURL: URL) throws {
        let bookmarkData = try bookmarkAccess.createDestinationBookmarkData(for: rootURL)
        storage.setDestinationBookmarkData(bookmarkData, forKey: keys.bookmarkKey)
    }

    public func clearBookmark() {
        storage.removeDestinationValue(forKey: keys.bookmarkKey)
    }
}

public enum ExportDestinationAccessError: Error, Equatable, LocalizedError {
    case accessDenied(URL)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access the selected export destination. Please re-select it."
        }
    }
}

public protocol DestinationAccess {
    func withAccess<T>(to destination: ExportDestination, _ operation: () throws -> T) throws -> T
}

public struct PassthroughDestinationAccess: DestinationAccess {
    public init() {}

    public func withAccess<T>(to destination: ExportDestination, _ operation: () throws -> T) throws -> T {
        try operation()
    }
}

public struct SecurityScopedDestinationAccess: DestinationAccess {
    private let bookmarkAccess: any ExportBookmarkAccessing

    public init(bookmarkAccess: any ExportBookmarkAccessing) {
        self.bookmarkAccess = bookmarkAccess
    }

    public func withAccess<T>(to destination: ExportDestination, _ operation: () throws -> T) throws -> T {
        guard bookmarkAccess.startAccessingDestination(destination.rootURL) else {
            throw ExportDestinationAccessError.accessDenied(destination.rootURL)
        }

        defer { bookmarkAccess.stopAccessingDestination(destination.rootURL) }
        return try operation()
    }
}

public protocol ExportFileSystem {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func readString(at url: URL) throws -> String
    func writeString(_ value: String, to url: URL, atomically: Bool) throws
}

public final class FileManagerExportFileSystem: ExportFileSystem, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func readString(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func writeString(_ value: String, to url: URL, atomically: Bool) throws {
        try value.write(to: url, atomically: atomically, encoding: .utf8)
    }
}

public enum ExportWriteMode: String, Codable, Equatable, Sendable {
    case overwrite
    case append
    case update
}

public protocol ExportMergeStrategy: Sendable {
    func merge(existing: String, new: String, file: PlannedExportFile) throws -> String
}

public enum ExportFileWriteAction: String, Codable, Equatable, Sendable {
    case exported
    case appended
    case updated
}

public struct ExportFileWriteResult: Equatable, Sendable {
    public var fileID: String
    public var relativePath: String
    public var url: URL
    public var bytesWritten: Int
    public var createdParentDirectory: Bool
    public var writeMode: ExportWriteMode
    public var action: ExportFileWriteAction

    public init(
        fileID: String,
        relativePath: String,
        url: URL,
        bytesWritten: Int,
        createdParentDirectory: Bool,
        writeMode: ExportWriteMode = .overwrite,
        action: ExportFileWriteAction = .exported
    ) {
        self.fileID = fileID
        self.relativePath = relativePath
        self.url = url
        self.bytesWritten = bytesWritten
        self.createdParentDirectory = createdParentDirectory
        self.writeMode = writeMode
        self.action = action
    }
}

public enum ExportFileWriterError: Error, Equatable, LocalizedError {
    case emptyRelativePath(fileID: String)

    public var errorDescription: String? {
        switch self {
        case .emptyRelativePath:
            return "Planned export files must provide a destination-relative path."
        }
    }
}

public struct ExportFileWriter {
    public var fileSystem: any ExportFileSystem
    public var destinationAccess: (any DestinationAccess)?
    public var safetyPolicy: ExportPathSafetyPolicy

    public init(
        fileSystem: any ExportFileSystem,
        destinationAccess: (any DestinationAccess)? = nil,
        safetyPolicy: ExportPathSafetyPolicy = .rejectTraversalAndAbsolutePaths
    ) {
        self.fileSystem = fileSystem
        self.destinationAccess = destinationAccess
        self.safetyPolicy = safetyPolicy
    }

    public func write(
        _ file: PlannedExportFile,
        to destination: ExportDestination,
        atomically: Bool = true
    ) throws -> ExportFileWriteResult {
        try write(file, to: destination, mode: .overwrite, atomically: atomically)
    }

    public func write(
        _ file: PlannedExportFile,
        to destination: ExportDestination,
        mode: ExportWriteMode,
        mergeStrategy: (any ExportMergeStrategy)? = nil,
        atomically: Bool = true
    ) throws -> ExportFileWriteResult {
        var mergeStrategies: [String: any ExportMergeStrategy] = [:]
        if let mergeStrategy {
            mergeStrategies[file.id] = mergeStrategy
        }

        guard let result = try write(
            [file],
            to: destination,
            mode: mode,
            mergeStrategies: mergeStrategies,
            atomically: atomically
        ).first else {
            throw ExportFileWriterError.emptyRelativePath(fileID: file.id)
        }
        return result
    }

    public func write(
        _ files: [PlannedExportFile],
        to destination: ExportDestination,
        atomically: Bool = true
    ) throws -> [ExportFileWriteResult] {
        try write(files, to: destination, mode: .overwrite, mergeStrategies: [:], atomically: atomically)
    }

    public func write(
        _ files: [PlannedExportFile],
        to destination: ExportDestination,
        mode: ExportWriteMode,
        mergeStrategies: [String: any ExportMergeStrategy] = [:],
        atomically: Bool = true
    ) throws -> [ExportFileWriteResult] {
        let operation = {
            try files.map { file in
                try writeWithoutAccess(
                    file,
                    to: destination,
                    mode: mode,
                    mergeStrategy: strategy(for: file, in: mergeStrategies),
                    atomically: atomically
                )
            }
        }

        if let destinationAccess {
            return try destinationAccess.withAccess(to: destination, operation)
        }

        return try operation()
    }

    private func strategy(
        for file: PlannedExportFile,
        in mergeStrategies: [String: any ExportMergeStrategy]
    ) -> (any ExportMergeStrategy)? {
        if let strategy = mergeStrategies[file.id] {
            return strategy
        }

        switch file.role {
        case .aggregate(let formatID):
            return mergeStrategies[formatID]
        case .supplemental(let pluginID), .mutation(let pluginID):
            return mergeStrategies[pluginID]
        }
    }

    private func writeWithoutAccess(
        _ file: PlannedExportFile,
        to destination: ExportDestination,
        mode: ExportWriteMode,
        mergeStrategy: (any ExportMergeStrategy)?,
        atomically: Bool
    ) throws -> ExportFileWriteResult {
        guard !file.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportFileWriterError.emptyRelativePath(fileID: file.id)
        }

        let baseURL = try destination.resolvedBaseURL(safetyPolicy: safetyPolicy)
        let fileURL = try safetyPolicy.appending(file.relativePath, to: baseURL, isDirectory: false)
        let parentURL = fileURL.deletingLastPathComponent()
        let createdParentDirectory = !fileSystem.fileExists(at: parentURL)
        if createdParentDirectory {
            try fileSystem.createDirectory(at: parentURL)
        }

        let resolvedContent = try contentToWrite(
            for: file,
            at: fileURL,
            mode: mode,
            mergeStrategy: mergeStrategy
        )
        try fileSystem.writeString(resolvedContent.value, to: fileURL, atomically: atomically)
        return ExportFileWriteResult(
            fileID: file.id,
            relativePath: file.relativePath,
            url: fileURL,
            bytesWritten: resolvedContent.value.utf8.count,
            createdParentDirectory: createdParentDirectory,
            writeMode: mode,
            action: resolvedContent.action
        )
    }

    private func contentToWrite(
        for file: PlannedExportFile,
        at fileURL: URL,
        mode: ExportWriteMode,
        mergeStrategy: (any ExportMergeStrategy)?
    ) throws -> (value: String, action: ExportFileWriteAction) {
        guard fileSystem.fileExists(at: fileURL) else {
            return (file.content, .exported)
        }

        switch mode {
        case .overwrite:
            return (file.content, .exported)
        case .append:
            let existing = try fileSystem.readString(at: fileURL)
            return (existing + "\n\n" + file.content, .appended)
        case .update:
            guard let mergeStrategy else {
                return (file.content, .exported)
            }
            let existing = try fileSystem.readString(at: fileURL)
            return (try mergeStrategy.merge(existing: existing, new: file.content, file: file), .updated)
        }
    }
}

public struct MarkdownMergeStrategy: ExportMergeStrategy, Sendable {
    public struct Section: Equatable, Sendable {
        public let headingLine: String
        public let normalizedName: String
        public var body: String

        public init(headingLine: String, normalizedName: String, body: String) {
            self.headingLine = headingLine
            self.normalizedName = normalizedName
            self.body = body
        }
    }

    public struct ParsedDocument: Equatable, Sendable {
        public var frontmatter: String
        public var preamble: String
        public var sections: [Section]

        public init(frontmatter: String, preamble: String, sections: [Section]) {
            self.frontmatter = frontmatter
            self.preamble = preamble
            self.sections = sections
        }
    }

    public static let defaultManagedSectionNames: Set<String> = []

    public var managedSectionNames: Set<String>
    public var preservePreamble: Bool

    public init(
        managedSectionNames: Set<String> = Self.defaultManagedSectionNames,
        preservePreamble: Bool = false
    ) {
        self.managedSectionNames = managedSectionNames
        self.preservePreamble = preservePreamble
    }

    public func merge(existing: String, new: String, file: PlannedExportFile) throws -> String {
        Self.merge(
            existing: existing,
            new: new,
            preservingPreamble: preservePreamble,
            managedSectionNames: managedSectionNames
        )
    }

    public static func merge(existing: String, new: String) -> String {
        merge(existing: existing, new: new, managedSectionNames: defaultManagedSectionNames)
    }

    public static func merge(
        existing: String,
        new: String,
        managedSectionNames: Set<String>
    ) -> String {
        merge(
            existing: existing,
            new: new,
            preservingPreamble: false,
            managedSectionNames: managedSectionNames
        )
    }

    public static func mergePreservingPreamble(existing: String, new: String) -> String {
        mergePreservingPreamble(
            existing: existing,
            new: new,
            managedSectionNames: defaultManagedSectionNames
        )
    }

    public static func mergePreservingPreamble(
        existing: String,
        new: String,
        managedSectionNames: Set<String>
    ) -> String {
        merge(
            existing: existing,
            new: new,
            preservingPreamble: true,
            managedSectionNames: managedSectionNames
        )
    }

    private static func merge(
        existing: String,
        new: String,
        preservingPreamble: Bool,
        managedSectionNames: Set<String>
    ) -> String {
        let newLevel = detectSectionLevel(in: new, managedSectionNames: managedSectionNames)
        let existingLevel = detectSectionLevel(in: existing, managedSectionNames: managedSectionNames)

        let existingDoc = parse(existing, sectionLevel: existingLevel)
        let newDoc = parse(new, sectionLevel: newLevel)

        var newSectionMap: [String: Section] = [:]
        var newSectionOrder: [String] = []
        for section in newDoc.sections {
            let key = section.normalizedName
            newSectionMap[key] = section
            if !newSectionOrder.contains(key) {
                newSectionOrder.append(key)
            }
        }

        let mergedFrontmatter = mergeFrontmatter(existing: existingDoc.frontmatter, new: newDoc.frontmatter)
        let preamble = preservingPreamble ? existingDoc.preamble : newDoc.preamble
        var result = mergedFrontmatter + preamble
        var placed: Set<String> = []

        for section in existingDoc.sections {
            let key = section.normalizedName
            if let newSection = newSectionMap[key] {
                result += newSection.headingLine + newSection.body
                placed.insert(key)
            } else {
                result += section.headingLine + section.body
            }
        }

        for key in newSectionOrder {
            if !placed.contains(key), let section = newSectionMap[key] {
                result += section.headingLine + section.body
            }
        }

        return result
    }

    public static func mergeFrontmatter(existing: String, new: String) -> String {
        let existingProps = parseFrontmatterProperties(existing)
        let newProps = parseFrontmatterProperties(new)

        if existingProps.isEmpty && newProps.isEmpty {
            return ""
        }

        if existingProps.isEmpty {
            return new
        }

        if newProps.isEmpty {
            return existing
        }

        var mergedKeys: [String] = []
        var mergedValues: [String: String] = [:]

        for (key, value) in existingProps {
            if !mergedKeys.contains(key) {
                mergedKeys.append(key)
            }
            mergedValues[key] = value
        }

        for (key, value) in newProps {
            if !mergedKeys.contains(key) {
                mergedKeys.append(key)
            }
            mergedValues[key] = value
        }

        var result = "---\n"
        for key in mergedKeys {
            if let value = mergedValues[key] {
                result += "\(key): \(value)\n"
            }
        }
        result += "---\n"

        return result
    }

    public static func parseFrontmatterProperties(_ frontmatter: String) -> [(key: String, value: String)] {
        let lines = frontmatter.components(separatedBy: "\n")
        guard lines.count >= 2 else { return [] }

        var properties: [(key: String, value: String)] = []
        var currentKey: String?
        var currentValue = ""
        var inMultilineValue = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "---" {
                continue
            }

            if trimmed.isEmpty && !inMultilineValue {
                continue
            }

            if let colonIndex = line.firstIndex(of: ":"), !inMultilineValue || !line.hasPrefix(" ") {
                if let key = currentKey {
                    properties.append((key: key, value: currentValue.trimmingCharacters(in: .whitespaces)))
                }

                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStart = line.index(after: colonIndex)
                let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)

                currentKey = key
                currentValue = value
                inMultilineValue = value.isEmpty || value == "|" || value == ">" || value.hasPrefix("[") && !value.hasSuffix("]")
            } else if inMultilineValue && currentKey != nil {
                if currentValue.isEmpty {
                    currentValue = line
                } else {
                    currentValue += "\n" + line
                }

                if currentValue.hasPrefix("[") && line.contains("]") {
                    inMultilineValue = false
                }
            }
        }

        if let key = currentKey {
            properties.append((key: key, value: currentValue.trimmingCharacters(in: .whitespaces)))
        }

        return properties
    }

    public static func parse(_ content: String, sectionLevel: Int) -> ParsedDocument {
        let lines = content.components(separatedBy: "\n")

        var frontmatter = ""
        var contentStartIndex = 0

        if let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" {
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    frontmatter = lines[0...i].joined(separator: "\n") + "\n"
                    contentStartIndex = i + 1
                    break
                }
            }
        }

        var preamble = ""
        var sections: [Section] = []
        var currentHeadingLine: String?
        var currentNormalizedName: String?
        var bodyLines: [String] = []

        for i in contentStartIndex..<lines.count {
            let line = lines[i]
            let level = headingLevel(of: line)

            if level == sectionLevel {
                if let heading = currentHeadingLine, let name = currentNormalizedName {
                    let body = bodyLines.map { $0 + "\n" }.joined()
                    sections.append(Section(headingLine: heading, normalizedName: name, body: body))
                    bodyLines = []
                }

                currentHeadingLine = line + "\n"
                currentNormalizedName = normalizeHeadingText(line)
            } else if currentHeadingLine == nil {
                preamble += line + "\n"
            } else {
                bodyLines.append(line)
            }
        }

        if let heading = currentHeadingLine, let name = currentNormalizedName {
            let body = bodyLines.map { $0 + "\n" }.joined()
            sections.append(Section(headingLine: heading, normalizedName: name, body: body))
        }

        return ParsedDocument(frontmatter: frontmatter, preamble: preamble, sections: sections)
    }

    public static func headingLevel(of line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return 0 }

        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 }
            else { break }
        }

        guard level < trimmed.count else { return 0 }
        let afterHashes = trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)]
        return afterHashes == " " ? level : 0
    }

    public static func normalizeHeadingText(_ heading: String) -> String {
        let stripped = heading.drop(while: { $0 == "#" || $0 == " " })

        let ascii = stripped.unicodeScalars
            .filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == UnicodeScalar(" ")) }
            .map { Character($0) }

        return String(ascii)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    public static func detectSectionLevel(in content: String) -> Int {
        detectSectionLevel(in: content, managedSectionNames: defaultManagedSectionNames)
    }

    public static func detectSectionLevel(in content: String, managedSectionNames: Set<String>) -> Int {
        for line in content.components(separatedBy: "\n") {
            let level = headingLevel(of: line)
            guard level > 0 else { continue }
            let name = normalizeHeadingText(line)
            if managedSectionNames.contains(name) {
                return level
            }
        }

        return 2
    }
}
