import Darwin
import Foundation

/// Shared path construction for aggregate exports and Daily Note Injection.
///
/// Aggregate exports live under the configured Health.md export subfolder.
/// Daily Note Injection targets are resolved from the selected vault/root
/// destination so users can export generated files to `Health/` while merging
/// into existing notes like `Daily/YYYY-MM-DD.md` at the vault root.
enum ExportPathPlanner {
    struct AggregateOutputTarget {
        let format: ExportFormat
        let filename: String
        let url: URL
        let relativePath: String
    }

    struct DailyNoteCollision {
        let dailyNoteURL: URL
        let dailyNoteRelativePath: String
        let exportTarget: AggregateOutputTarget

        var message: String {
            "Daily Note Injection target conflicts with export output: \(dailyNoteRelativePath). Change Output folder/filename or Daily Note Injection folder/filename."
        }
    }

    struct DataDictionaryCollision: Equatable {
        let dataDictionaryRelativePath: String
        let artifactRelativePath: String
    }

    enum PathValidationError: Error, Equatable {
        case invalidRelativePath(String)
        case destinationUnavailable(String)
        case destinationOutsideVault(String)
    }

    private struct ResolvedDestinationTarget {
        struct Identity: Equatable {
            let device: UInt64
            let inode: UInt64
        }

        let path: String
        let identity: Identity?
    }

    static func normalizedRelativePath(_ rawPath: String) -> String {
        relativePath([rawPath])
    }

    static func healthSubfolderURL(vaultURL: URL, healthSubfolder: String) -> URL {
        appendingRelativePath(healthSubfolder, to: vaultURL, isDirectory: true)
    }

    static func aggregateFolderURL(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        format: ExportFormat? = nil
    ) -> URL {
        var url = healthSubfolderURL(vaultURL: vaultURL, healthSubfolder: healthSubfolder)
        if let folderPath = settings.formatFolderPath(for: date, format: format) {
            url = appendingRelativePath(folderPath, to: url, isDirectory: true)
        }
        return url
    }

    static func aggregateFileURL(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        format: ExportFormat
    ) -> URL {
        let folderURL = aggregateFolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date,
            format: format
        )
        return fileURL(in: folderURL, filename: settings.filename(for: date, format: format))
    }

    static func aggregateOutputTargets(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> [AggregateOutputTarget] {
        settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }).map { format in
            let filename = settings.filename(for: date, format: format)
            return AggregateOutputTarget(
                format: format,
                filename: filename,
                url: aggregateFileURL(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                ),
                relativePath: aggregateRelativePath(
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                )
            )
        }
    }

    static func aggregateFolderRelativePath(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        format: ExportFormat? = nil
    ) -> String {
        relativePath([
            healthSubfolder,
            settings.formatFolderPath(for: date, format: format) ?? ""
        ])
    }

    static func aggregateRelativePath(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date,
        format: ExportFormat
    ) -> String {
        relativePath([
            healthSubfolder,
            settings.formatFolderPath(for: date, format: format) ?? "",
            settings.filename(for: date, format: format)
        ])
    }

    static func dailyNoteURL(
        vaultURL: URL,
        settings: DailyNoteInjectionSettings,
        date: Date
    ) -> URL {
        var url = appendingRelativePath(settings.folderPath, to: vaultURL, isDirectory: true)
        url = fileURL(in: url, filename: settings.formatFilename(for: date) + ".md")
        return url
    }

    static func dailyNoteRelativePath(
        settings: DailyNoteInjectionSettings,
        date: Date
    ) -> String {
        relativePath([
            settings.folderPath,
            settings.formatFilename(for: date) + ".md"
        ])
    }

    static func dailyNoteFolderRelativePath(
        settings: DailyNoteInjectionSettings,
        date: Date
    ) -> String {
        let relativePath = dailyNoteRelativePath(settings: settings, date: date)
        return Self.relativePath(relativePath.split(separator: "/").dropLast().map(String.init))
    }

    static func dailyNoteExportCollision(
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> DailyNoteCollision? {
        guard settings.dailyNoteInjection.enabled else { return nil }

        let dailyNoteURL = dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: date
        )
        let dailyNoteRelativePath = dailyNoteRelativePath(
            settings: settings.dailyNoteInjection,
            date: date
        )

        guard let exportTarget = aggregateOutputTargets(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        ).first(where: { sameFile($0.url, dailyNoteURL) }) else {
            return nil
        }

        return DailyNoteCollision(
            dailyNoteURL: dailyNoteURL,
            dailyNoteRelativePath: dailyNoteRelativePath,
            exportTarget: exportTarget
        )
    }

    /// Relative-path collision check for previews that may not have a local vault URL.
    static func dailyNoteExportCollision(
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        date: Date
    ) -> DailyNoteCollision? {
        dailyNoteExportCollision(
            vaultURL: URL(fileURLWithPath: "/__HealthMdVaultRoot__", isDirectory: true),
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        )
    }

    static func dataDictionaryRelativePath(healthSubfolder: String) -> String {
        relativePath([healthSubfolder, HealthMdExportSchema.dataDictionaryFilename])
    }

    /// Produces the portable spelling used by ZIP entries and lexical collision checks. ZIP has
    /// historically accepted slash aliases, so collision admission must interpret backslashes,
    /// repeated separators, and `.` components exactly the same way. Traversal and absolute paths
    /// are never normalized into something safe.
    nonisolated static func normalizedPortableRelativePath(_ relativePath: String) throws -> String {
        let bytes = Array(relativePath.utf8)
        let windowsAbsolute = bytes.count >= 2
            && bytes[1] == 58
            && ((65...90).contains(bytes[0]) || (97...122).contains(bytes[0]))
        guard !relativePath.isEmpty,
              bytes.count <= 4_096,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !windowsAbsolute,
              !relativePath.contains("\0"),
              !relativePath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw PathValidationError.invalidRelativePath(relativePath)
        }

        let slashPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = slashPath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !rawComponents.contains(where: { $0 == ".." }) else {
            throw PathValidationError.invalidRelativePath(relativePath)
        }
        let normalized = rawComponents
            .filter { !$0.isEmpty && $0 != "." }
            .map(String.init)
            .joined(separator: "/")
        guard !normalized.isEmpty else {
            throw PathValidationError.invalidRelativePath(relativePath)
        }
        return normalized
    }

    /// Requires a canonical portable spelling for direct destination and artifact-plan paths.
    /// Unlike ZIP entry names, destination paths must not depend on platform-specific alias rules.
    nonisolated static func validatedPortableRelativePath(_ relativePath: String) throws -> String {
        let normalized = try normalizedPortableRelativePath(relativePath)
        guard normalized == relativePath else {
            throw PathValidationError.invalidRelativePath(relativePath)
        }
        return normalized
    }

    /// Detects future/nonexistent aliases on case-insensitive, width-insensitive, or
    /// Unicode-normalizing destinations. Invalid paths throw so callers cannot interpret an
    /// unsafe path as "no collision."
    static func dataDictionaryArtifactCollision(
        healthSubfolder: String,
        artifactRelativePaths: [String]
    ) throws -> DataDictionaryCollision? {
        let dictionaryPath = dataDictionaryRelativePath(healthSubfolder: healthSubfolder)
        let dictionaryKey = try canonicalPortablePathKey(dictionaryPath)
        for artifactPath in artifactRelativePaths {
            let artifactKey = try canonicalPortablePathKey(artifactPath)
            if artifactKey == dictionaryKey {
                return DataDictionaryCollision(
                    dataDictionaryRelativePath: dictionaryPath,
                    artifactRelativePath: artifactPath
                )
            }
        }
        return nil
    }

    /// Resolves every existing component under the standardized, resolved vault root. This
    /// catches directory-symlink and hard-link aliases even when the final file does not yet
    /// exist, while rejecting any target that leaves the selected vault.
    static func destinationDataDictionaryArtifactCollision(
        vaultURL: URL,
        healthSubfolder: String,
        artifactRelativePaths: [String]
    ) throws -> DataDictionaryCollision? {
        if let lexical = try dataDictionaryArtifactCollision(
            healthSubfolder: healthSubfolder,
            artifactRelativePaths: artifactRelativePaths
        ) {
            return lexical
        }
        let dictionaryPath = dataDictionaryRelativePath(healthSubfolder: healthSubfolder)
        let dictionaryTarget = try resolvedDestinationTarget(
            vaultURL: vaultURL,
            relativePath: dictionaryPath
        )
        for artifactPath in artifactRelativePaths {
            let artifactTarget = try resolvedDestinationTarget(
                vaultURL: vaultURL,
                relativePath: artifactPath
            )
            let sameResolvedPath = artifactTarget.path == dictionaryTarget.path
            let sameExistingIdentity = artifactTarget.identity != nil
                && artifactTarget.identity == dictionaryTarget.identity
            if sameResolvedPath || sameExistingIdentity {
                return DataDictionaryCollision(
                    dataDictionaryRelativePath: dictionaryPath,
                    artifactRelativePath: artifactPath
                )
            }
        }
        return nil
    }

    static func canonicalPortablePathKey(_ relativePath: String) throws -> String {
        try normalizedPortableRelativePath(relativePath)
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCompatibilityMapping
    }

    /// Verifies every canonical destination path against the resolved selected root, even when no
    /// data dictionary is requested. Existing symlink parents may resolve within the vault, but
    /// no target may resolve outside it.
    static func validateDestinationArtifactPaths(
        vaultURL: URL,
        artifactRelativePaths: [String]
    ) throws {
        for relativePath in artifactRelativePaths {
            _ = try resolvedDestinationTarget(
                vaultURL: vaultURL,
                relativePath: relativePath
            )
        }
    }

    private static func resolvedDestinationTarget(
        vaultURL: URL,
        relativePath: String
    ) throws -> ResolvedDestinationTarget {
        let portablePath = try validatedPortableRelativePath(relativePath)
        let standardizedRoot = vaultURL.standardizedFileURL
        guard standardizedRoot.isFileURL,
              let rootPointer = Darwin.realpath(standardizedRoot.path, nil) else {
            throw PathValidationError.destinationUnavailable(relativePath)
        }
        defer { Darwin.free(rootPointer) }
        let resolvedRootPath = String(cString: rootPointer)
        var rootMetadata = stat()
        guard Darwin.lstat(resolvedRootPath, &rootMetadata) == 0,
              rootMetadata.st_mode & S_IFMT == S_IFDIR else {
            throw PathValidationError.destinationUnavailable(relativePath)
        }
        let resolvedRoot = URL(
            fileURLWithPath: resolvedRootPath,
            isDirectory: true
        ).standardizedFileURL
        let components = portablePath.split(separator: "/").map(String.init)
        var current = resolvedRoot

        for index in components.indices {
            let component = components[index]
            let candidate = current.appendingPathComponent(
                component,
                isDirectory: index < components.index(before: components.endIndex)
            )
            var linkMetadata = stat()
            if Darwin.lstat(candidate.path, &linkMetadata) != 0 {
                guard errno == ENOENT else {
                    throw PathValidationError.destinationUnavailable(relativePath)
                }
                for remaining in components[index...] {
                    current.appendPathComponent(remaining)
                }
                current = current.standardizedFileURL
                guard contains(current.path, inResolvedRoot: resolvedRoot.path) else {
                    throw PathValidationError.destinationOutsideVault(relativePath)
                }
                return ResolvedDestinationTarget(path: current.path, identity: nil)
            }

            guard let resolvedPointer = Darwin.realpath(candidate.path, nil) else {
                throw PathValidationError.destinationUnavailable(relativePath)
            }
            let resolvedPath = String(cString: resolvedPointer)
            Darwin.free(resolvedPointer)
            current = URL(
                fileURLWithPath: resolvedPath,
                isDirectory: index < components.index(before: components.endIndex)
            ).standardizedFileURL
            guard contains(current.path, inResolvedRoot: resolvedRoot.path) else {
                throw PathValidationError.destinationOutsideVault(relativePath)
            }

            var resolvedMetadata = stat()
            guard Darwin.lstat(current.path, &resolvedMetadata) == 0 else {
                throw PathValidationError.destinationUnavailable(relativePath)
            }
            if index < components.index(before: components.endIndex) {
                guard resolvedMetadata.st_mode & S_IFMT == S_IFDIR else {
                    throw PathValidationError.destinationUnavailable(relativePath)
                }
            } else {
                return ResolvedDestinationTarget(
                    path: current.path,
                    identity: ResolvedDestinationTarget.Identity(
                        device: UInt64(bitPattern: Int64(resolvedMetadata.st_dev)),
                        inode: UInt64(resolvedMetadata.st_ino)
                    )
                )
            }
        }
        throw PathValidationError.invalidRelativePath(relativePath)
    }

    private static func contains(_ path: String, inResolvedRoot rootPath: String) -> Bool {
        if path == rootPath { return true }
        let prefix = rootPath == "/" || rootPath.hasSuffix("/")
            ? rootPath
            : rootPath + "/"
        return path.hasPrefix(prefix)
    }

    static func fileURL(in folderURL: URL, filename: String) -> URL {
        appendingRelativePath(filename, to: folderURL, isDirectory: false)
    }

    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    static func appendingRelativePath(_ relativePath: String, to baseURL: URL, isDirectory: Bool) -> URL {
        let segments = pathSegments(relativePath)
        guard !segments.isEmpty else { return baseURL }

        var url = baseURL
        for (index, segment) in segments.enumerated() {
            let segmentIsDirectory = isDirectory || index < segments.count - 1
            url = url.appendingPathComponent(segment, isDirectory: segmentIsDirectory)
        }
        return url
    }

    private static func relativePath(_ rawComponents: [String]) -> String {
        rawComponents.flatMap { pathSegments($0) }.joined(separator: "/")
    }

    private static func pathSegments(_ rawPath: String) -> [String] {
        rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
