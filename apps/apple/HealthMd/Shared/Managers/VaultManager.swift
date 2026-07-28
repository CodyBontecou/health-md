import Combine
import Darwin
import Foundation
import HealthMdCoreRust
import SwiftUI

nonisolated struct RenderedHealthDataArchiveEntryFile: Sendable {
    let date: Date
    let archivePath: String
    let order: Int
    let url: URL
}

nonisolated private enum HealthDataArchiveSource: Sendable {
    case inMemory(HealthData)
    case file(RenderedHealthDataArchiveEntryFile)

    var date: Date {
        switch self {
        case .inMemory(let record): return record.date
        case .file(let file): return file.date
        }
    }

    var order: Int {
        switch self {
        case .inMemory: return 0
        case .file(let file): return file.order
        }
    }
}

nonisolated private enum AggregateFileWriteBehavior: Sendable {
    case overwrite
    case append
    case mergeMarkdown
}

nonisolated private struct AggregateFileWriteRequest: Sendable {
    let fileURL: URL
    let filename: String
    let newContent: String
    let behavior: AggregateFileWriteBehavior
}

nonisolated private struct AggregateFileWriteOutcome: Sendable {
    let fileURL: URL
    let filename: String
    let action: String
}

nonisolated private struct WrittenAggregateFile: Sendable {
    let fileURL: URL
    let filename: String
    let relativePath: String
    let format: ExportFormat
}

/// Serializes each aggregate read/modify/write transaction away from MainActor.
/// Awaiting callers still return only after the atomic write and directory sync.
nonisolated private final class AggregateFileWriter: Sendable {
    private static let queue = DispatchQueue(
        label: "com.healthexporter.aggregate-file-writer",
        qos: .utility
    )
    private let fileSystem: FileSystemAccessing

    init(fileSystem: FileSystemAccessing) {
        self.fileSystem = fileSystem
    }

    func writeSynchronously(
        _ request: AggregateFileWriteRequest
    ) throws -> AggregateFileWriteOutcome {
        try Self.queue.sync {
            try performWrite(request)
        }
    }

    func write(
        _ request: AggregateFileWriteRequest
    ) async throws -> AggregateFileWriteOutcome {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { [self] in
                do {
                    continuation.resume(returning: try performWrite(request))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func inspectExactArtifact(
        rootURL: URL,
        relativePath: String,
        expectedData: Data,
        binding: AppleVaultDestinationBinding,
        fallbackFileURL: URL
    ) async throws -> AppleExactDestinationState {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { [self] in
                do {
                    if fileSystem is SystemFileSystem {
                        continuation.resume(returning: try SecureExactArtifactIO.inspect(
                            rootURL: rootURL,
                            relativePath: relativePath,
                            expectedData: expectedData,
                            binding: binding
                        ))
                    } else if fileSystem.fileExists(atPath: fallbackFileURL.path) {
                        let content = try fileSystem.contentsOfFile(at: fallbackFileURL)
                        continuation.resume(
                            returning: Data(content.utf8) == expectedData ? .exact : .different
                        )
                    } else {
                        continuation.resume(returning: .missing)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func overwriteExactArtifact(
        rootURL: URL,
        relativePath: String,
        data: Data,
        binding: AppleVaultDestinationBinding,
        fallbackRequest: AggregateFileWriteRequest,
        beforeCommit: (@Sendable () throws -> Void)? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async { [self] in
                do {
                    if fileSystem is SystemFileSystem {
                        try SecureExactArtifactIO.overwrite(
                            rootURL: rootURL,
                            relativePath: relativePath,
                            data: data,
                            binding: binding,
                            beforeCommit: beforeCommit
                        )
                    } else {
                        _ = try performWrite(fallbackRequest)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performWrite(
        _ request: AggregateFileWriteRequest
    ) throws -> AggregateFileWriteOutcome {
        let parentURL = request.fileURL.deletingLastPathComponent()
        if !fileSystem.fileExists(atPath: parentURL.path) {
            try fileSystem.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        let finalContent: String
        let action: String
        if fileSystem.fileExists(atPath: request.fileURL.path) {
            switch request.behavior {
            case .append:
                let existing = try fileSystem.contentsOfFile(at: request.fileURL)
                let appendedBlock = "\n\n" + request.newContent
                if existing == request.newContent || existing.hasSuffix(appendedBlock) {
                    finalContent = existing
                    action = "Already present in"
                } else {
                    finalContent = existing + appendedBlock
                    action = "Appended to"
                }
            case .mergeMarkdown:
                let existing = try fileSystem.contentsOfFile(at: request.fileURL)
                finalContent = MarkdownMerger.merge(
                    existing: existing,
                    new: request.newContent
                )
                action = "Updated"
            case .overwrite:
                finalContent = request.newContent
                action = "Exported to"
            }
        } else {
            finalContent = request.newContent
            action = "Exported to"
        }

        try fileSystem.writeString(finalContent, to: request.fileURL, atomically: true)
        return AggregateFileWriteOutcome(
            fileURL: request.fileURL,
            filename: request.filename,
            action: action
        )
    }
}

struct ExportPresentationTarget: Equatable, Sendable {
    let fileURL: URL
    let folderURL: URL
    let securityScopedRootURL: URL?

    init(fileURL: URL, securityScopedRootURL: URL?) {
        self.fileURL = fileURL
        folderURL = fileURL.deletingLastPathComponent()
        self.securityScopedRootURL = securityScopedRootURL
    }
}

nonisolated struct AppleLooseDailyRangeWriteResult: Equatable, Sendable {
    let dailyFileCount: Int
    let rollupFileCount: Int

    var totalFileCount: Int { dailyFileCount + rollupFileCount }
}

nonisolated struct AppleLooseDailyMaterializedFile: Equatable, Sendable {
    let relativePath: String
    let mediaType: String
    let data: Data
}

nonisolated struct AppleLooseDailyRangeMaterialization: Equatable, Sendable {
    let operation: AppleLooseDailyPlannedOperation
    let dataDictionary: AppleLooseDailyMaterializedFile?
    let result: AppleLooseDailyRangeWriteResult
}

nonisolated struct AppleVaultDestinationBinding: Codable, Equatable, Sendable {
    let standardizedPath: String
    let resolvedPath: String
    let deviceID: UInt64
    let inode: UInt64
}

nonisolated enum AppleExactDestinationState: Equatable, Sendable {
    case missing
    case exact
    case different
}

nonisolated enum AppleExactDestinationError: String, Error, Equatable, Sendable {
    case destinationUnavailable = "apple_exact_destination_unavailable"
    case destinationRebound = "apple_exact_destination_rebound"
    case unsafeRelativePath = "apple_exact_destination_unsafe_relative_path"
    case invalidUTF8 = "apple_exact_destination_invalid_utf8"
}

/// Descriptor-relative exact-file I/O for production durable range commits. No path component is
/// followed as a symlink, and the opened root must retain the device/inode captured before the
/// first side effect. Atomic replacement therefore cannot escape through a rename or symlink race.
nonisolated private enum SecureExactArtifactIO {
    static func inspect(
        rootURL: URL,
        relativePath: String,
        expectedData: Data,
        binding: AppleVaultDestinationBinding
    ) throws -> AppleExactDestinationState {
        let rootDescriptor = try openBoundRoot(rootURL, binding: binding)
        defer { Darwin.close(rootDescriptor) }
        let (parentDescriptor, filename) = try openParent(
            rootDescriptor: rootDescriptor,
            relativePath: relativePath,
            createDirectories: false
        )
        guard let parentDescriptor else { return .missing }
        defer { Darwin.close(parentDescriptor) }
        try validateOpenedNamespace(
            rootURL: rootURL,
            relativePath: relativePath,
            binding: binding,
            openedParentDescriptor: parentDescriptor,
            filename: filename
        )
        let descriptor = filename.withCString {
            Darwin.openat(parentDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        if descriptor < 0 {
            if errno == ENOENT { return .missing }
            if errno == ELOOP || errno == ENOTDIR {
                throw AppleExactDestinationError.unsafeRelativePath
            }
            throw AppleExactDestinationError.destinationUnavailable
        }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        guard metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1 else {
            throw AppleExactDestinationError.unsafeRelativePath
        }
        guard metadata.st_size >= 0,
              UInt64(metadata.st_size) == UInt64(expectedData.count) else {
            return .different
        }
        let state: AppleExactDestinationState = try readAll(
            descriptor: descriptor,
            count: expectedData.count
        ) == expectedData ? .exact : .different
        var finalMetadata = stat()
        guard Darwin.fstat(descriptor, &finalMetadata) == 0,
              finalMetadata.st_dev == metadata.st_dev,
              finalMetadata.st_ino == metadata.st_ino,
              finalMetadata.st_nlink == 1,
              finalMetadata.st_size == metadata.st_size else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        guard try liveFilenameMatches(
            parentDescriptor: parentDescriptor,
            filename: filename,
            openedMetadata: finalMetadata
        ) else {
            return .different
        }
        try validateOpenedNamespace(
            rootURL: rootURL,
            relativePath: relativePath,
            binding: binding,
            openedParentDescriptor: parentDescriptor,
            filename: filename
        )
        if state == .exact {
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.fsync(parentDescriptor) == 0,
                  try liveFilenameMatches(
                    parentDescriptor: parentDescriptor,
                    filename: filename,
                    openedMetadata: finalMetadata
                  ) else {
                throw AppleExactDestinationError.destinationUnavailable
            }
        }
        return state
    }

    private static func liveFilenameMatches(
        parentDescriptor: Int32,
        filename: String,
        openedMetadata: stat
    ) throws -> Bool {
        var liveMetadata = stat()
        let result = filename.withCString {
            Darwin.fstatat(parentDescriptor, $0, &liveMetadata, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0 {
            if errno == ENOENT { return false }
            throw AppleExactDestinationError.destinationUnavailable
        }
        guard liveMetadata.st_mode & S_IFMT == S_IFREG,
              liveMetadata.st_nlink == 1 else {
            throw AppleExactDestinationError.unsafeRelativePath
        }
        return liveMetadata.st_dev == openedMetadata.st_dev
            && liveMetadata.st_ino == openedMetadata.st_ino
            && liveMetadata.st_size == openedMetadata.st_size
    }

    static func overwrite(
        rootURL: URL,
        relativePath: String,
        data: Data,
        binding: AppleVaultDestinationBinding,
        beforeCommit: (@Sendable () throws -> Void)? = nil
    ) throws {
        let rootDescriptor = try openBoundRoot(rootURL, binding: binding)
        defer { Darwin.close(rootDescriptor) }
        let (openedParent, filename) = try openParent(
            rootDescriptor: rootDescriptor,
            relativePath: relativePath,
            createDirectories: true
        )
        guard let parentDescriptor = openedParent else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        defer { Darwin.close(parentDescriptor) }
        try validateOpenedNamespace(
            rootURL: rootURL,
            relativePath: relativePath,
            binding: binding,
            openedParentDescriptor: parentDescriptor,
            filename: filename
        )

        var existing = stat()
        let existingResult = filename.withCString {
            Darwin.fstatat(parentDescriptor, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if existingResult == 0 {
            guard existing.st_mode & S_IFMT == S_IFREG else {
                throw AppleExactDestinationError.unsafeRelativePath
            }
        } else if errno != ENOENT {
            if errno == ELOOP || errno == ENOTDIR {
                throw AppleExactDestinationError.unsafeRelativePath
            }
            throw AppleExactDestinationError.destinationUnavailable
        }

        let temporaryName = ".healthmd-exact-\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryName.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        var temporaryIsPresent = true
        defer {
            Darwin.close(temporaryDescriptor)
            if temporaryIsPresent {
                _ = temporaryName.withCString {
                    Darwin.unlinkat(parentDescriptor, $0, 0)
                }
            }
        }
        try writeAll(data, descriptor: temporaryDescriptor)
        guard Darwin.fchmod(temporaryDescriptor, mode_t(0o600)) == 0,
              Darwin.fsync(temporaryDescriptor) == 0 else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        try validateOpenedNamespace(
            rootURL: rootURL,
            relativePath: relativePath,
            binding: binding,
            openedParentDescriptor: parentDescriptor,
            filename: filename
        )
        let expectedParentPath = try descriptorPath(parentDescriptor)
        try beforeCommit?()
        let temporaryPath = URL(fileURLWithPath: expectedParentPath, isDirectory: true)
            .appendingPathComponent(temporaryName).path
        let destinationPath = URL(fileURLWithPath: expectedParentPath, isDirectory: true)
            .appendingPathComponent(filename).path
        let renameResult = temporaryPath.withCString { temporaryPointer in
            destinationPath.withCString { filenamePointer in
                Darwin.renamex_np(
                    temporaryPointer,
                    filenamePointer,
                    UInt32(RENAME_NOFOLLOW_ANY)
                )
            }
        }
        guard renameResult == 0 else {
            let renameError = errno
            // Prefer a stable rebinding diagnosis when the namespace moved after the final
            // precommit check; the absolute no-follow rename has not followed the moved parent.
            try validateOpenedNamespace(
                rootURL: rootURL,
                relativePath: relativePath,
                binding: binding,
                openedParentDescriptor: parentDescriptor,
                filename: filename
            )
            if renameError == EISDIR || renameError == ENOTDIR || renameError == ELOOP {
                throw AppleExactDestinationError.unsafeRelativePath
            }
            throw AppleExactDestinationError.destinationUnavailable
        }
        temporaryIsPresent = false
        guard Darwin.fsync(parentDescriptor) == 0 else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        try validateOpenedNamespace(
            rootURL: rootURL,
            relativePath: relativePath,
            binding: binding,
            openedParentDescriptor: parentDescriptor,
            filename: filename
        )
    }

    private static func validateOpenedNamespace(
        rootURL: URL,
        relativePath: String,
        binding: AppleVaultDestinationBinding,
        openedParentDescriptor: Int32,
        filename: String
    ) throws {
        let rootDescriptor = try openBoundRoot(rootURL, binding: binding)
        defer { Darwin.close(rootDescriptor) }
        let (reopenedParent, reopenedFilename) = try openParent(
            rootDescriptor: rootDescriptor,
            relativePath: relativePath,
            createDirectories: false
        )
        guard let reopenedParent else {
            throw AppleExactDestinationError.destinationRebound
        }
        defer { Darwin.close(reopenedParent) }
        var openedMetadata = stat()
        var reopenedMetadata = stat()
        guard reopenedFilename == filename,
              Darwin.fstat(openedParentDescriptor, &openedMetadata) == 0,
              Darwin.fstat(reopenedParent, &reopenedMetadata) == 0,
              openedMetadata.st_mode & S_IFMT == S_IFDIR,
              reopenedMetadata.st_mode & S_IFMT == S_IFDIR,
              openedMetadata.st_dev == reopenedMetadata.st_dev,
              openedMetadata.st_ino == reopenedMetadata.st_ino else {
            throw AppleExactDestinationError.destinationRebound
        }

        let expectedParentPath = resolvedParentPath(
            relativePath: relativePath,
            binding: binding
        )
        let openedParentPath = try descriptorPath(openedParentDescriptor)
        let reopenedParentPath = try descriptorPath(reopenedParent)
        guard openedParentPath == expectedParentPath,
              reopenedParentPath == expectedParentPath else {
            throw AppleExactDestinationError.destinationRebound
        }
    }

    private static func resolvedParentPath(
        relativePath: String,
        binding: AppleVaultDestinationBinding
    ) -> String {
        relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .dropLast()
            .reduce(binding.resolvedPath) { path, component in
                path + "/" + String(component)
            }
    }

    private static func descriptorPath(_ descriptor: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard Darwin.fcntl(descriptor, F_GETPATH, &buffer) == 0 else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        return String(cString: buffer)
    }

    private static func openBoundRoot(
        _ rootURL: URL,
        binding: AppleVaultDestinationBinding
    ) throws -> Int32 {
        let descriptor = Darwin.open(
            rootURL.standardizedFileURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ELOOP || errno == ENOTDIR {
                throw AppleExactDestinationError.destinationRebound
            }
            throw AppleExactDestinationError.destinationUnavailable
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFDIR,
              UInt64(metadata.st_dev) == binding.deviceID,
              UInt64(metadata.st_ino) == binding.inode else {
            Darwin.close(descriptor)
            throw AppleExactDestinationError.destinationRebound
        }
        return descriptor
    }

    private static func openParent(
        rootDescriptor: Int32,
        relativePath: String,
        createDirectories: Bool
    ) throws -> (Int32?, String) {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard let filename = components.last,
              !filename.isEmpty,
              components.allSatisfy({ component in
                  !component.isEmpty && component != "." && component != ".."
              }) else {
            throw AppleExactDestinationError.unsafeRelativePath
        }
        let duplicatedRoot = Darwin.fcntl(rootDescriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicatedRoot >= 0 else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        var currentDescriptor = duplicatedRoot
        for component in components.dropLast() {
            var nextDescriptor = component.withCString {
                Darwin.openat(
                    currentDescriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            if nextDescriptor < 0, errno == ENOENT, createDirectories {
                let creationResult = component.withCString {
                    Darwin.mkdirat(currentDescriptor, $0, mode_t(0o700))
                }
                if creationResult != 0 && errno != EEXIST {
                    Darwin.close(currentDescriptor)
                    throw AppleExactDestinationError.destinationUnavailable
                }
                nextDescriptor = component.withCString {
                    Darwin.openat(
                        currentDescriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
            }
            if nextDescriptor < 0 {
                let failure = errno
                Darwin.close(currentDescriptor)
                if failure == ENOENT, !createDirectories { return (nil, filename) }
                if failure == ELOOP || failure == ENOTDIR {
                    throw AppleExactDestinationError.unsafeRelativePath
                }
                throw AppleExactDestinationError.destinationUnavailable
            }
            guard Darwin.fsync(currentDescriptor) == 0 else {
                Darwin.close(nextDescriptor)
                Darwin.close(currentDescriptor)
                throw AppleExactDestinationError.destinationUnavailable
            }
            Darwin.close(currentDescriptor)
            currentDescriptor = nextDescriptor
        }
        guard Darwin.fsync(currentDescriptor) == 0 else {
            Darwin.close(currentDescriptor)
            throw AppleExactDestinationError.destinationUnavailable
        }
        return (currentDescriptor, filename)
    }

    private static func readAll(descriptor: Int32, count: Int) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = result.withUnsafeMutableBytes { buffer -> Int in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return Darwin.read(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset
                )
            }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw AppleExactDestinationError.destinationUnavailable
            }
            guard readCount > 0 else { throw AppleExactDestinationError.destinationUnavailable }
            offset += readCount
        }
        return result
    }

    private static func writeAll(_ data: Data, descriptor: Int32) throws {
        var offset = 0
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            while offset < data.count {
                let writeCount = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if writeCount < 0 {
                    if errno == EINTR { continue }
                    throw AppleExactDestinationError.destinationUnavailable
                }
                guard writeCount > 0 else {
                    throw AppleExactDestinationError.destinationUnavailable
                }
                offset += writeCount
            }
        }
    }
}

struct DailyExportWriteResult {
    let aggregateFileCount: Int
    let individualEntryFileCount: Int
    let dailyNoteResult: DailyNoteInjector.InjectionResult?

    var dailyNoteUpdatedCount: Int {
        if case .updated = dailyNoteResult { return 1 }
        return 0
    }

    var dailyNoteSkippedCount: Int {
        if case .skipped = dailyNoteResult { return 1 }
        return 0
    }

    var dailyNoteFailure: Error? {
        if case .failed(let error) = dailyNoteResult { return error }
        return nil
    }

    static let noOutput = DailyExportWriteResult(
        aggregateFileCount: 0,
        individualEntryFileCount: 0,
        dailyNoteResult: nil
    )
}

@MainActor
final class VaultManager: ObservableObject {
    static let defaultHealthSubfolder = ""

    @Published var vaultURL: URL?
    @Published var vaultName: String = "No vault selected"
    @Published var healthSubfolder: String = VaultManager.defaultHealthSubfolder
    @Published var lastExportStatus: String?
    /// The exact file selected for post-export preview and its containing folder.
    /// This is transient UI state; the vault bookmark remains the durable access grant.
    @Published private(set) var lastExportPresentationTarget: ExportPresentationTarget?

    private let bookmarkKey = "obsidianVaultBookmark"
    private let vaultNameKey = "obsidianVaultName"
    private let vaultPathKey = "obsidianVaultPath"
    private static let subfolderKey = "healthSubfolder"

    private let defaults: UserDefaultsStoring
    private let fileSystem: FileSystemAccessing
    private let aggregateFileWriter: AggregateFileWriter
    private let bookmarkResolver: BookmarkResolving
    private let appleLooseDailyPlanner: any AppleLooseDailyExportPlanning

    #if DEBUG
    var archiveEntryWillAppendForTesting: (() -> Void)?
    var exactDestinationWillCommitForTesting: (@Sendable () throws -> Void)?
    #endif

    /// Individual entry exporter for granular tracking
    private let individualExporter = IndividualEntryExporter()

    private static let staleBookmarkRefreshStatus = "Saved folder access needs to be refreshed. Reconnect or re-select the folder."
    private static let savedFolderUnavailableStatus = "Saved folder unavailable. Reconnect the location in Files or re-select the folder."
    private static let folderAccessDeniedStatus = "Cannot access the selected folder. Reconnect the location in Files or re-select the folder."

    init(
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        fileSystem: FileSystemAccessing = SystemFileSystem(),
        bookmarkResolver: BookmarkResolving = SystemBookmarkResolver(),
        appleLooseDailyPlanner: (any AppleLooseDailyExportPlanning)? = nil
    ) {
        self.defaults = defaults
        self.fileSystem = fileSystem
        aggregateFileWriter = AggregateFileWriter(fileSystem: fileSystem)
        self.bookmarkResolver = bookmarkResolver
        self.appleLooseDailyPlanner = appleLooseDailyPlanner ?? AppleLooseDailyExportPlanner()
        loadSavedSettings()
    }

    // MARK: - Bookmark Management

    static func savedHealthSubfolder(
        defaults: UserDefaultsStoring = SystemUserDefaults()
    ) -> String {
        defaults.string(forKey: subfolderKey) ?? defaultHealthSubfolder
    }

    private func loadSavedSettings() {
        healthSubfolder = Self.savedHealthSubfolder(defaults: defaults)

        // Load bookmark
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return
        }

        do {
            let (url, isStale) = try bookmarkResolver.resolveBookmark(data: bookmarkData)

            if isStale {
                // Bookmark is stale, need to re-save it. If the refresh fails
                // (common for temporarily disconnected File Provider/network
                // locations), keep the existing bookmark instead of forgetting
                // the user's selected vault.
                if bookmarkResolver.startAccessing(url) {
                    defer { bookmarkResolver.stopAccessing(url) }
                    do {
                        try saveBookmark(for: url)
                    } catch {
                        lastExportStatus = Self.staleBookmarkRefreshStatus
                    }
                }
            }

            vaultURL = url
            vaultName = url.lastPathComponent
            saveVaultMetadata(for: url)
            clearTransientFolderStatusIfNeeded()
        } catch {
            print("Failed to resolve bookmark: \(error)")
            // Do not remove the bookmark here. Network shares and File Provider
            // locations can fail bookmark resolution transiently; preserving the
            // bookmark lets a later app launch/retry recover once Files has
            // reconnected the location.
            vaultURL = nil
            vaultName = defaults.string(forKey: vaultNameKey) ?? "Saved vault unavailable"
            lastExportStatus = Self.savedFolderUnavailableStatus
        }
    }

    private func saveBookmark(for url: URL) throws {
        let bookmarkData = try bookmarkResolver.createBookmarkData(for: url)
        defaults.set(bookmarkData, forKey: bookmarkKey)
    }

    private func saveVaultMetadata(for url: URL) {
        defaults.set(url.lastPathComponent, forKey: vaultNameKey)
        defaults.set(url.path, forKey: vaultPathKey)
    }

    private func clearTransientFolderStatusIfNeeded() {
        switch lastExportStatus {
        case Self.savedFolderUnavailableStatus,
             Self.folderAccessDeniedStatus:
            lastExportStatus = nil
        default:
            break
        }
    }

    func saveSubfolderSetting() {
        defaults.set(healthSubfolder, forKey: Self.subfolderKey)
    }

    // MARK: - Folder Selection

    func setVaultFolder(_ url: URL) {
        guard bookmarkResolver.startAccessing(url) else {
            lastExportStatus = "Failed to access folder"
            return
        }

        defer { bookmarkResolver.stopAccessing(url) }

        do {
            try saveBookmark(for: url)
            saveVaultMetadata(for: url)
            vaultURL = url
            vaultName = url.lastPathComponent
            lastExportStatus = nil
            clearLastExportPresentationTarget()
        } catch {
            lastExportStatus = "Failed to save folder access: \(error.localizedDescription)"
        }
    }

    func clearVaultFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: vaultNameKey)
        defaults.removeObject(forKey: vaultPathKey)
        vaultURL = nil
        vaultName = "No vault selected"
        clearLastExportPresentationTarget()
    }

    func recordExportPresentationTarget(
        fileURL: URL,
        securityScopedRootURL: URL?
    ) {
        lastExportPresentationTarget = ExportPresentationTarget(
            fileURL: fileURL,
            securityScopedRootURL: securityScopedRootURL
        )
    }

    func clearLastExportPresentationTarget() {
        lastExportPresentationTarget = nil
    }

    func startAccessingExportPresentationTarget(_ target: ExportPresentationTarget) -> Bool {
        guard let rootURL = target.securityScopedRootURL else { return true }
        return bookmarkResolver.startAccessing(rootURL)
    }

    func stopAccessingExportPresentationTarget(_ target: ExportPresentationTarget) {
        guard let rootURL = target.securityScopedRootURL else { return }
        bookmarkResolver.stopAccessing(rootURL)
    }

    /// Configures an app-container staging root for an authenticated direct CLI
    /// export. The root is ephemeral producer storage, never a user preference
    /// or a replacement for the normal security-scoped destination bookmark.
    func configureDirectTransportStagingRoot(
        _ url: URL,
        healthSubfolder: String
    ) throws {
        let standardized = url.standardizedFileURL
        let containerRoots = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
            FileManager.default.temporaryDirectory
        ].compactMap { $0?.standardizedFileURL.path }
        guard containerRoots.contains(where: {
            standardized.path == $0 || standardized.path.hasPrefix($0 + "/")
        }) else {
            throw ExportError.accessDenied
        }
        try FileManager.default.createDirectory(
            at: standardized,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        vaultURL = standardized
        vaultName = standardized.lastPathComponent
        self.healthSubfolder = healthSubfolder
        lastExportStatus = nil
        clearLastExportPresentationTarget()
    }

    /// Set a fake vault for UI testing — avoids real bookmark/security-scoped access.
    func setTestVault() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestVault")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        vaultURL = tempDir
        vaultName = "TestVault"
    }

    // MARK: - Background Access

    /// Check if we have a currently resolved vault URL (for background tasks).
    var hasVaultAccess: Bool {
        vaultURL != nil
    }

    /// True when the user previously selected a vault folder, even if the
    /// security-scoped bookmark cannot currently be resolved (for example, an
    /// SMB/File Provider location that Files has disconnected).
    var hasSavedVaultFolder: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    var isVaultConfigured: Bool {
        vaultURL != nil || hasSavedVaultFolder
    }

    /// Returns whether the selected vault folder can currently be accessed via
    /// its security-scoped bookmark. Used by the Mac export-agent readiness
    /// status before iOS sends an export job.
    func canAccessSelectedVaultFolder() -> Bool {
        guard let vaultURL else { return false }
        guard bookmarkResolver.startAccessing(vaultURL) else { return false }
        bookmarkResolver.stopAccessing(vaultURL)
        return true
    }

    /// Refresh vault access for background tasks
    func refreshVaultAccess() {
        loadSavedSettings()
    }

    /// Start accessing the vault (for background tasks)
    @discardableResult
    func startVaultAccess() -> Bool {
        guard let url = vaultURL else {
            if hasSavedVaultFolder {
                lastExportStatus = Self.savedFolderUnavailableStatus
            }
            return false
        }
        let didStartAccess = bookmarkResolver.startAccessing(url)
        if !didStartAccess {
            lastExportStatus = Self.folderAccessDeniedStatus
        }
        return didStartAccess
    }

    /// Stop accessing the vault (for background tasks)
    func stopVaultAccess() {
        guard let url = vaultURL else { return }
        bookmarkResolver.stopAccessing(url)
    }

    /// Export health data without automatic security scope (for background tasks).
    /// The Boolean compatibility wrapper reports whether the configured primary
    /// output completed; callers that need Daily Note outcome details should use
    /// `exportHealthDataResult`.
    func exportHealthData(_ healthData: HealthData, for date: Date, settings: AdvancedExportSettings) -> Bool {
        do {
            let result = try exportHealthDataResult(healthData, for: date, settings: settings)
            return !settings.dailyNotesOnlyModeEnabled || result.dailyNoteUpdatedCount > 0
        } catch {
            lastExportStatus = error.localizedDescription
            print("Export failed: \(error)")
            return false
        }
    }

    func exportHealthDataResult(
        _ healthData: HealthData,
        for date: Date,
        settings: AdvancedExportSettings,
        writeDataDictionary shouldWriteDataDictionary: Bool = true,
        preparedExport suppliedPreparedExport: PreparedHealthDataExport? = nil
    ) throws -> DailyExportWriteResult {
        guard let vaultURL else {
            if hasSavedVaultFolder {
                lastExportStatus = Self.savedFolderUnavailableStatus
            }
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        let preparedExport = suppliedPreparedExport
            ?? healthData.preparedExport(settings: settings)
        guard preparedExport.hasAnyData else {
            throw ExportError.noHealthData
        }
        guard settings.hasFileDestinationOutput else {
            throw ExportError.noFormatsSelected
        }
        guard !settings.summaryOnlyModeEnabled else {
            lastExportStatus = "Skipped daily files in summary-only mode"
            return .noOutput
        }

        return try writeHealthDataOutputs(
            healthData,
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            shouldWriteDataDictionary: shouldWriteDataDictionary,
            preparedExport: preparedExport
        )
    }

    // MARK: - Export

    @discardableResult
    func exportHealthData(
        _ healthData: HealthData,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        writeDataDictionary shouldWriteDataDictionary: Bool = true,
        operationSurface: AppleExportOperationSurface = .legacyOnly,
        frozenSettingsSnapshot suppliedSettingsSnapshot: ExportSettingsSnapshot? = nil
    ) async throws -> DailyExportWriteResult {
        guard let vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        let effectiveHealthSubfolder = healthSubfolder ?? self.healthSubfolder
        let settingsSnapshot = suppliedSettingsSnapshot ?? ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: effectiveHealthSubfolder,
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: settings.exportTimeZoneOverride?.identifier
                ?? healthData.timeContext.calendarTimeZoneIdentifier
        )
        let frozenSettings = settingsSnapshot.makeAdvancedExportSettings()
        frozenSettings.exportTimeZoneOverride = settings.exportTimeZoneOverride
        let preparedExport = healthData.preparedExport(settings: frozenSettings)
        guard preparedExport.hasAnyData else {
            throw ExportError.noHealthData
        }
        guard frozenSettings.hasFileDestinationOutput else {
            throw ExportError.noFormatsSelected
        }
        guard !frozenSettings.summaryOnlyModeEnabled else {
            lastExportStatus = "Skipped daily files in summary-only mode"
            return .noOutput
        }

        // Resolve and fully materialize a non-legacy plan before opening destination access. The
        // default surface is legacy-only so connected/direct/scheduled callers remain untouched.
        let planResolution = try await appleLooseDailyPlanner.plan(
            healthData: healthData,
            settingsSnapshot: settingsSnapshot,
            surface: operationSurface
        )

        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        switch planResolution {
        case .legacy:
            return try await writeHealthDataOutputsOffMain(
                healthData,
                date: healthData.date,
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                settings: frozenSettings,
                shouldWriteDataDictionary: shouldWriteDataDictionary,
                preparedExport: preparedExport
            )
        case .planned(let operation):
            return try await writePlannedLooseDailyOutputsOffMain(
                healthData,
                date: healthData.date,
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                settings: frozenSettings,
                shouldWriteDataDictionary: shouldWriteDataDictionary,
                operation: operation
            )
        }
    }

    /// Materializes a complete simple-summary range without opening or mutating the selected
    /// destination. The returned bytes are immutable and may be protected by a durable caller
    /// before any external side effect. `nil` means the frozen operation is intentionally legacy.
    func materializeHealthDataRange(
        _ healthData: [HealthData],
        settingsSnapshot: ExportSettingsSnapshot,
        operationSurface: AppleExportOperationSurface,
        dailyOutputOwnerDates: Set<String>? = nil,
        operationIdentity: AppleExportOperationIdentity? = nil,
        includeDataDictionary: Bool = true
    ) async throws -> AppleLooseDailyRangeMaterialization? {
        guard !healthData.isEmpty else { return nil }
        guard let rangePlanner = appleLooseDailyPlanner as? any AppleLooseDailyRangeExportPlanning else {
            return nil
        }
        let frozenSettings = settingsSnapshot.makeAdvancedExportSettings()
        guard frozenSettings.hasFileDestinationOutput else { throw ExportError.noFormatsSelected }
        let calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier ?? ""
        let outputDates = dailyOutputOwnerDates ?? Set(healthData.map {
            HealthKitDailyOwnershipMetadata.ownerDate(
                for: $0.date,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
        })
        let resolution = try await rangePlanner.planRange(
            healthData: healthData,
            dailyOutputOwnerDates: outputDates,
            settingsSnapshot: settingsSnapshot,
            surface: operationSurface,
            operationIdentity: operationIdentity
        )
        guard case .planned(let operation) = resolution else { return nil }

        for planned in operation.artifacts {
            guard planned.artifact.writeMode == .overwrite,
                  String(data: planned.artifact.inlineData, encoding: .utf8) != nil else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
        }
        let dictionary: AppleLooseDailyMaterializedFile?
        if includeDataDictionary {
            let materializationRoot = URL(
                fileURLWithPath: "/__healthmd_range_materialization__",
                isDirectory: true
            )
            let request = try makeDataDictionaryWriteRequest(
                vaultURL: materializationRoot,
                healthSubfolder: settingsSnapshot.healthSubfolder ?? self.healthSubfolder,
                settings: frozenSettings
            )
            if let request {
                let rootPath = materializationRoot.standardizedFileURL.path + "/"
                let targetPath = request.fileURL.standardizedFileURL.path
                guard targetPath.hasPrefix(rootPath) else {
                    throw AppleExactDestinationError.unsafeRelativePath
                }
                dictionary = AppleLooseDailyMaterializedFile(
                    relativePath: String(targetPath.dropFirst(rootPath.count)),
                    mediaType: "application/json",
                    data: Data(request.newContent.utf8)
                )
            } else {
                dictionary = nil
            }
        } else {
            dictionary = nil
        }
        let rollupFileCount = operation.artifacts.count { $0.kind == .rollup }
        return AppleLooseDailyRangeMaterialization(
            operation: operation,
            dataDictionary: dictionary,
            result: AppleLooseDailyRangeWriteResult(
                dailyFileCount: operation.artifacts.count - rollupFileCount,
                rollupFileCount: rollupFileCount
            )
        )
    }

    /// Plans a complete simple-summary range under one identity and commits only after every byte
    /// has been materialized. `nil` means the frozen operation is intentionally legacy.
    func exportHealthDataRange(
        _ healthData: [HealthData],
        settingsSnapshot: ExportSettingsSnapshot,
        operationSurface: AppleExportOperationSurface,
        dailyOutputOwnerDates: Set<String>? = nil,
        operationIdentity: AppleExportOperationIdentity? = nil,
        writeDataDictionary shouldWriteDataDictionary: Bool = true
    ) async throws -> AppleLooseDailyRangeWriteResult? {
        guard !healthData.isEmpty else {
            return AppleLooseDailyRangeWriteResult(dailyFileCount: 0, rollupFileCount: 0)
        }
        guard let vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard let materialized = try await materializeHealthDataRange(
            healthData,
            settingsSnapshot: settingsSnapshot,
            operationSurface: operationSurface,
            dailyOutputOwnerDates: dailyOutputOwnerDates,
            operationIdentity: operationIdentity,
            includeDataDictionary: shouldWriteDataDictionary
        ) else { return nil }

        let dictionaryRequest = try materialized.dataDictionary.map { file in
            guard let content = String(data: file.data, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            let fileURL = ExportPathPlanner.appendingRelativePath(
                file.relativePath,
                to: vaultURL,
                isDirectory: false
            )
            return AggregateFileWriteRequest(
                fileURL: fileURL,
                filename: fileURL.lastPathComponent,
                newContent: content,
                behavior: .overwrite
            )
        }
        let aggregateRequests: [(AppleLooseDailyPlannedArtifact, AggregateFileWriteRequest)] =
            try materialized.operation.artifacts.map { planned in
                guard let content = String(data: planned.artifact.inlineData, encoding: .utf8) else {
                    throw CocoaError(.fileWriteInapplicableStringEncoding)
                }
                let fileURL = ExportPathPlanner.appendingRelativePath(
                    planned.artifact.relativePath,
                    to: vaultURL,
                    isDirectory: false
                )
                return (planned, AggregateFileWriteRequest(
                    fileURL: fileURL,
                    filename: fileURL.lastPathComponent,
                    newContent: content,
                    behavior: .overwrite
                ))
            }

        let barrier = ExportCommitBarrier()
        try await barrier.transition(to: .materialized)
        guard bookmarkResolver.startAccessing(vaultURL) else { throw ExportError.accessDenied }
        defer { bookmarkResolver.stopAccessing(vaultURL) }
        do {
            try await barrier.transition(to: .committing)
            if let dictionaryRequest { _ = try await aggregateFileWriter.write(dictionaryRequest) }
            var writtenFiles: [WrittenAggregateFile] = []
            for (planned, request) in aggregateRequests {
                let outcome = try await aggregateFileWriter.write(request)
                writtenFiles.append(WrittenAggregateFile(
                    fileURL: outcome.fileURL,
                    filename: outcome.filename,
                    relativePath: planned.artifact.relativePath,
                    format: planned.format
                ))
            }
            try await barrier.transition(to: .completed)
            lastExportStatus = "Exported \(writtenFiles.count) files from one frozen range plan"
            if let previewFile = preferredPresentationFile(in: writtenFiles) {
                recordExportPresentationTarget(
                    fileURL: previewFile.fileURL,
                    securityScopedRootURL: vaultURL
                )
            }
            return materialized.result
        } catch {
            try? await barrier.transition(to: .failed)
            throw error
        }
    }

    /// Captures the exact selected-root identity used by durable connected finalization.
    func exactDestinationBinding() throws -> AppleVaultDestinationBinding {
        guard let vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }
        return try Self.destinationBinding(for: vaultURL)
    }

    func inspectExactUTF8Artifact(
        relativePath: String,
        expectedData: Data,
        binding: AppleVaultDestinationBinding
    ) async throws -> AppleExactDestinationState {
        guard let vaultURL else { throw AppleExactDestinationError.destinationUnavailable }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }
        let fileURL = try exactDestinationURL(
            relativePath: relativePath,
            binding: binding,
            vaultURL: vaultURL
        )
        do {
            return try await aggregateFileWriter.inspectExactArtifact(
                rootURL: vaultURL,
                relativePath: relativePath,
                expectedData: expectedData,
                binding: binding,
                fallbackFileURL: fileURL
            )
        } catch let error as AppleExactDestinationError {
            throw error
        } catch {
            throw AppleExactDestinationError.destinationUnavailable
        }
    }

    func overwriteExactUTF8Artifact(
        relativePath: String,
        data: Data,
        binding: AppleVaultDestinationBinding
    ) async throws {
        guard let content = String(data: data, encoding: .utf8) else {
            throw AppleExactDestinationError.invalidUTF8
        }
        guard let vaultURL else { throw AppleExactDestinationError.destinationUnavailable }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw AppleExactDestinationError.destinationUnavailable
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }
        let fileURL = try exactDestinationURL(
            relativePath: relativePath,
            binding: binding,
            vaultURL: vaultURL
        )
        let request = AggregateFileWriteRequest(
            fileURL: fileURL,
            filename: fileURL.lastPathComponent,
            newContent: content,
            behavior: .overwrite
        )
        #if DEBUG
        let beforeCommit = exactDestinationWillCommitForTesting
        #else
        let beforeCommit: (@Sendable () throws -> Void)? = nil
        #endif
        do {
            try await aggregateFileWriter.overwriteExactArtifact(
                rootURL: vaultURL,
                relativePath: relativePath,
                data: data,
                binding: binding,
                fallbackRequest: request,
                beforeCommit: beforeCommit
            )
        } catch let error as AppleExactDestinationError {
            throw error
        } catch {
            throw AppleExactDestinationError.destinationUnavailable
        }
    }

    private func exactDestinationURL(
        relativePath: String,
        binding: AppleVaultDestinationBinding,
        vaultURL: URL
    ) throws -> URL {
        guard try Self.destinationBinding(for: vaultURL) == binding else {
            throw AppleExactDestinationError.destinationRebound
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw AppleExactDestinationError.unsafeRelativePath
        }
        let fileURL = ExportPathPlanner.appendingRelativePath(
            relativePath,
            to: vaultURL,
            isDirectory: false
        )
        let standardizedRoot = vaultURL.standardizedFileURL.path
        let standardizedCandidate = fileURL.standardizedFileURL.path
        let standardizedPrefix = standardizedRoot.hasSuffix("/")
            ? standardizedRoot
            : standardizedRoot + "/"
        let resolvedCandidate = binding.resolvedPath + "/" + relativePath
        let resolvedPrefix = binding.resolvedPath.hasSuffix("/")
            ? binding.resolvedPath
            : binding.resolvedPath + "/"
        guard standardizedCandidate.hasPrefix(standardizedPrefix),
              resolvedCandidate.hasPrefix(resolvedPrefix) else {
            throw AppleExactDestinationError.unsafeRelativePath
        }
        return fileURL
    }

    private static func destinationBinding(for url: URL) throws -> AppleVaultDestinationBinding {
        let standardizedURL = url.standardizedFileURL
        guard let resolvedPointer = Darwin.realpath(standardizedURL.path, nil) else {
            throw AppleExactDestinationError.destinationRebound
        }
        defer { Darwin.free(resolvedPointer) }
        let resolvedPath = String(cString: resolvedPointer)
        var linkMetadata = stat()
        var resolvedMetadata = stat()
        guard Darwin.lstat(standardizedURL.path, &linkMetadata) == 0,
              linkMetadata.st_mode & S_IFMT == S_IFDIR,
              Darwin.lstat(resolvedPath, &resolvedMetadata) == 0,
              resolvedMetadata.st_mode & S_IFMT == S_IFDIR,
              linkMetadata.st_dev == resolvedMetadata.st_dev,
              linkMetadata.st_ino == resolvedMetadata.st_ino else {
            throw AppleExactDestinationError.destinationRebound
        }
        return AppleVaultDestinationBinding(
            standardizedPath: standardizedURL.path,
            resolvedPath: resolvedPath,
            deviceID: UInt64(resolvedMetadata.st_dev),
            inode: UInt64(resolvedMetadata.st_ino)
        )
    }

    private func prepareHealthDataOutputDestination(
        date: Date,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings
    ) throws {
        guard !settings.dailyNotesOnlyModeEnabled else { return }
        try ensureNoDailyNoteExportCollision(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            date: date,
            settings: settings
        )
    }

    private func completeHealthDataOutputWrite(
        _ healthData: HealthData,
        date: Date,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        writtenFiles: [WrittenAggregateFile],
        leadingAction: String
    ) throws -> DailyExportWriteResult {
        var individualEntriesCount = 0
        if settings.writesIndividualEntryFiles {
            individualEntriesCount = try exportIndividualEntries(
                from: healthData,
                to: individualEntriesBaseFolderURL(
                    vaultURL: vaultURL,
                    healthSubfolder: healthSubfolder,
                    date: date,
                    settings: settings
                ),
                settings: settings
            )
        }

        let dailyNoteResult: DailyNoteInjector.InjectionResult? = settings.dailyNoteInjection.enabled
            ? DailyNoteInjector.inject(
                healthData: healthData,
                into: vaultURL,
                settings: settings.dailyNoteInjection,
                customization: settings.formatCustomization,
                metricSelection: settings.metricSelection
            )
            : nil

        if settings.dailyNotesOnlyModeEnabled {
            switch dailyNoteResult {
            case .updated(let path):
                lastExportStatus = "Updated daily note \(path)"
            case .failed(let error):
                lastExportStatus = "Daily note update failed: \(error.localizedDescription)"
            case .skipped(let reason):
                lastExportStatus = "Daily note skipped: \(reason)"
            case .none:
                lastExportStatus = "Daily note update was not performed"
            }
        } else {
            var statusMessage: String
            if writtenFiles.isEmpty && settings.archiveModeEnabled {
                statusMessage = "Prepared files for ZIP archive"
            } else {
                statusMessage = "\(leadingAction) \(statusPathSummary(for: writtenFiles))"
            }
            if individualEntriesCount > 0 {
                statusMessage += " + \(individualEntriesCount) individual entr\(individualEntriesCount == 1 ? "y" : "ies")"
            }
            switch dailyNoteResult {
            case .updated(let path):
                statusMessage += " · injected into \(path)"
            case .failed(let error):
                statusMessage += " · daily note injection failed: \(error.localizedDescription)"
            case .skipped(let reason) where reason.contains("not found"):
                statusMessage += " · daily note not found (skipped)"
            case .skipped, .none:
                break
            }
            lastExportStatus = statusMessage
        }

        if settings.dailyNotesOnlyModeEnabled {
            if case .updated = dailyNoteResult {
                recordExportPresentationTarget(
                    fileURL: ExportPathPlanner.dailyNoteURL(
                        vaultURL: vaultURL,
                        settings: settings.dailyNoteInjection,
                        date: date
                    ),
                    securityScopedRootURL: vaultURL
                )
            }
        } else if let previewFile = preferredPresentationFile(in: writtenFiles) {
            recordExportPresentationTarget(
                fileURL: previewFile.fileURL,
                securityScopedRootURL: vaultURL
            )
        }

        return DailyExportWriteResult(
            aggregateFileCount: writtenFiles.count,
            individualEntryFileCount: individualEntriesCount,
            dailyNoteResult: dailyNoteResult
        )
    }

    private func writeHealthDataOutputs(
        _ healthData: HealthData,
        date: Date,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        shouldWriteDataDictionary: Bool,
        preparedExport: PreparedHealthDataExport
    ) throws -> DailyExportWriteResult {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        #endif
        try prepareHealthDataOutputDestination(
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings
        )
        if !settings.dailyNotesOnlyModeEnabled,
           !settings.archiveModeEnabled,
           shouldWriteDataDictionary,
           let dictionaryRequest = try makeDataDictionaryWriteRequest(
               vaultURL: vaultURL,
               healthSubfolder: healthSubfolder,
               settings: settings
           ) {
            _ = try aggregateFileWriter.writeSynchronously(dictionaryRequest)
        }

        var writtenFiles: [WrittenAggregateFile] = []
        var leadingAction = "Exported to"
        for (index, format) in looseExportFormats(in: settings).enumerated() {
            let targetFolderURL = ExportPathPlanner.aggregateFolderURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: date,
                format: format
            )
            let result = try writeOneFormat(
                preparedExport: preparedExport,
                date: date,
                format: format,
                targetFolderURL: targetFolderURL,
                settings: settings
            )
            writtenFiles.append(WrittenAggregateFile(
                fileURL: result.fileURL,
                filename: result.filename,
                relativePath: ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                ),
                format: format
            ))
            if index == 0 { leadingAction = result.action }
        }

        let result = try completeHealthDataOutputWrite(
            healthData,
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            writtenFiles: writtenFiles,
            leadingAction: leadingAction
        )
        #if DEBUG
        ExportPerformanceInstrumentation.completed(
            pipeline: "local-files",
            phase: "daily-write",
            timer: performanceTimer,
            itemCount: result.aggregateFileCount + result.individualEntryFileCount
        )
        #endif
        return result
    }

    private func writeHealthDataOutputsOffMain(
        _ healthData: HealthData,
        date: Date,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        shouldWriteDataDictionary: Bool,
        preparedExport: PreparedHealthDataExport
    ) async throws -> DailyExportWriteResult {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        #endif
        try prepareHealthDataOutputDestination(
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings
        )
        if !settings.dailyNotesOnlyModeEnabled,
           !settings.archiveModeEnabled,
           shouldWriteDataDictionary,
           let dictionaryRequest = try makeDataDictionaryWriteRequest(
               vaultURL: vaultURL,
               healthSubfolder: healthSubfolder,
               settings: settings
           ) {
            _ = try await aggregateFileWriter.write(dictionaryRequest)
        }

        var writtenFiles: [WrittenAggregateFile] = []
        var leadingAction = "Exported to"
        for (index, format) in looseExportFormats(in: settings).enumerated() {
            let targetFolderURL = ExportPathPlanner.aggregateFolderURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: date,
                format: format
            )
            let result = try await writeOneFormatOffMain(
                preparedExport: preparedExport,
                date: date,
                format: format,
                targetFolderURL: targetFolderURL,
                settings: settings
            )
            writtenFiles.append(WrittenAggregateFile(
                fileURL: result.fileURL,
                filename: result.filename,
                relativePath: ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: healthSubfolder,
                    settings: settings,
                    date: date,
                    format: format
                ),
                format: format
            ))
            if index == 0 { leadingAction = result.action }
        }

        let result = try completeHealthDataOutputWrite(
            healthData,
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            writtenFiles: writtenFiles,
            leadingAction: leadingAction
        )
        #if DEBUG
        ExportPerformanceInstrumentation.completed(
            pipeline: "local-files",
            phase: "daily-write",
            timer: performanceTimer,
            itemCount: result.aggregateFileCount + result.individualEntryFileCount
        )
        #endif
        return result
    }

    /// Commits one already-materialized authority plan. No renderer or authority resolver is
    /// reachable after the barrier enters `committing`.
    private func writePlannedLooseDailyOutputsOffMain(
        _ healthData: HealthData,
        date: Date,
        vaultURL: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        shouldWriteDataDictionary: Bool,
        operation: AppleLooseDailyPlannedOperation
    ) async throws -> DailyExportWriteResult {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        #endif
        try prepareHealthDataOutputDestination(
            date: date,
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings
        )

        let dictionaryRequest: AggregateFileWriteRequest? = if shouldWriteDataDictionary {
            try makeDataDictionaryWriteRequest(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings
            )
        } else {
            nil
        }
        let aggregateRequests: [(AppleLooseDailyPlannedArtifact, AggregateFileWriteRequest)] = try operation.artifacts.map { planned in
            guard let content = String(data: planned.artifact.inlineData, encoding: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            let fileURL = ExportPathPlanner.appendingRelativePath(
                planned.artifact.relativePath,
                to: vaultURL,
                isDirectory: false
            )
            return (planned, AggregateFileWriteRequest(
                fileURL: fileURL,
                filename: fileURL.lastPathComponent,
                newContent: content,
                behavior: .overwrite
            ))
        }

        let barrier = ExportCommitBarrier()
        try await barrier.transition(to: .materialized)
        do {
            // The authority and every output byte are locked before the first directory creation or
            // atomic write, including the native data dictionary sidecar.
            try await barrier.transition(to: .committing)
            if let dictionaryRequest {
                _ = try await aggregateFileWriter.write(dictionaryRequest)
            }

            var writtenFiles: [WrittenAggregateFile] = []
            var leadingAction = "Exported to"
            for (index, pair) in aggregateRequests.enumerated() {
                let outcome = try await aggregateFileWriter.write(pair.1)
                writtenFiles.append(WrittenAggregateFile(
                    fileURL: outcome.fileURL,
                    filename: outcome.filename,
                    relativePath: pair.0.artifact.relativePath,
                    format: pair.0.format
                ))
                if index == 0 { leadingAction = outcome.action }
            }

            let result = try completeHealthDataOutputWrite(
                healthData,
                date: date,
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings,
                writtenFiles: writtenFiles,
                leadingAction: leadingAction
            )
            try await barrier.transition(to: .completed)
            #if DEBUG
            ExportPerformanceInstrumentation.completed(
                pipeline: "local-files",
                phase: "daily-write",
                timer: performanceTimer,
                itemCount: result.aggregateFileCount
            )
            #endif
            return result
        } catch {
            try? await barrier.transition(to: .failed)
            throw error
        }
    }

    // MARK: - External Provider Sidecar Exports

    @discardableResult
    func exportExternalDailyRecords(
        _ records: [ExternalDailyRecord],
        healthSubfolder: String? = nil
    ) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }

        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder
        )
        let integrationsFolderURL = healthFolderURL.appendingPathComponent("integrations", isDirectory: true)

        var writtenCount = 0
        for record in records where record.shouldExport {
            guard record.hasValidExportDate else {
                throw ExternalProviderExportError.invalidDate(record.date)
            }
            let providerFolderURL = integrationsFolderURL.appendingPathComponent(record.provider.exportFolderName, isDirectory: true)
            if !fileSystem.fileExists(atPath: providerFolderURL.path) {
                try fileSystem.createDirectory(at: providerFolderURL, withIntermediateDirectories: true)
            }

            let data = try encoder.encode(record)
            guard let json = String(data: data, encoding: .utf8) else { continue }
            let fileURL = providerFolderURL.appendingPathComponent("\(record.date).json")
            try fileSystem.writeString(json, to: fileURL, atomically: true)
            writtenCount += 1
        }

        return writtenCount
    }

    // MARK: - ZIP Archives

    @discardableResult
    func exportArchive(
        from healthData: [HealthData],
        rollupHealthData: [HealthData] = [],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date,
        healthSubfolder: String? = nil
    ) async throws -> URL? {
        try await exportArchive(
            sources: healthData.map(HealthDataArchiveSource.inMemory),
            rollupHealthData: rollupHealthData,
            settings: settings,
            startDate: startDate,
            endDate: endDate,
            healthSubfolder: healthSubfolder
        )
    }

    @discardableResult
    func exportArchive(
        fromRenderedFiles files: [RenderedHealthDataArchiveEntryFile],
        rollupHealthData: [HealthData] = [],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date,
        healthSubfolder: String? = nil
    ) async throws -> URL? {
        try await exportArchive(
            sources: files.map(HealthDataArchiveSource.file),
            rollupHealthData: rollupHealthData,
            settings: settings,
            startDate: startDate,
            endDate: endDate,
            healthSubfolder: healthSubfolder
        )
    }

    private func exportArchive(
        sources: [HealthDataArchiveSource],
        rollupHealthData: [HealthData],
        settings: AdvancedExportSettings,
        startDate: Date,
        endDate: Date,
        healthSubfolder: String?
    ) async throws -> URL? {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "local-files",
                phase: "zip-archive",
                timer: performanceTimer,
                itemCount: sources.count
            )
        }
        #endif
        guard settings.archiveModeEnabled else { return nil }
        let archivedFormats = settings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !archivedFormats.isEmpty else { return nil }
        guard !sources.isEmpty || (settings.summaryOnlyModeEnabled && !rollupHealthData.isEmpty) else { return nil }
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let rollupEntries = rollupArchiveEntries(from: rollupHealthData, settings: settings)
        if settings.summaryOnlyModeEnabled && rollupEntries.isEmpty { return nil }

        let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder
        )
        if !fileSystem.fileExists(atPath: healthFolderURL.path) {
            try fileSystem.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
        }
        let archiveURL = healthFolderURL.appendingPathComponent(
            archiveFilename(startDate: startDate, endDate: endDate),
            isDirectory: false
        )
        let checkpointURL = healthFolderURL.appendingPathComponent(
            ".\(archiveURL.lastPathComponent).zip-checkpoint-\(UUID().uuidString)",
            isDirectory: false
        )
        let writer = try ZipArchiveWriter.begin(
            to: archiveURL,
            checkpointURL: checkpointURL
        )
        do {
            let dictionaryEntry = dataDictionaryArchiveEntry(settings: settings)
            #if DEBUG
            archiveEntryWillAppendForTesting?()
            #endif
            try await Self.performArchiveIO {
                try writer.append(
                    dictionaryEntry,
                    cancellationCheck: { Task.isCancelled }
                )
            }
            if !settings.summaryOnlyModeEnabled {
                let orderedSources = sources.sorted {
                    if $0.date != $1.date { return $0.date < $1.date }
                    return $0.order < $1.order
                }
                for source in orderedSources {
                    try Task.checkCancellation()
                    switch source {
                    case .inMemory(let data):
                        let preparedExport = data.preparedExport(settings: settings)
                        for format in archivedFormats {
                            try Task.checkCancellation()
                            let content = try preparedExport.content(format: format, settings: settings)
                            guard let bytes = content.data(using: .utf8) else {
                                throw CocoaError(.fileWriteInapplicableStringEncoding)
                            }
                            let entry = ZipArchiveWriter.Entry(
                                path: archiveEntryPath(
                                    for: data.date,
                                    format: format,
                                    settings: settings
                                ),
                                data: bytes
                            )
                            try await Self.performArchiveIO {
                                try writer.append(entry, cancellationCheck: { Task.isCancelled })
                            }
                            await Task.yield()
                        }
                    case .file(let file):
                        try await Self.performArchiveIO {
                            try writer.append(
                                ZipArchiveWriter.FileEntry(
                                    path: file.archivePath,
                                    sourceURL: file.url
                                ),
                                cancellationCheck: { Task.isCancelled }
                            )
                        }
                        await Task.yield()
                    }
                }
            }
            for entry in rollupEntries {
                try Task.checkCancellation()
                try await Self.performArchiveIO {
                    try writer.append(entry, cancellationCheck: { Task.isCancelled })
                }
                await Task.yield()
            }
            try await Self.performArchiveIO {
                try writer.finish(cancellationCheck: { Task.isCancelled })
            }
        } catch {
            try? await Self.performArchiveIO { writer.abandon() }
            throw error
        }
        recordExportPresentationTarget(
            fileURL: archiveURL,
            securityScopedRootURL: vaultURL
        )
        lastExportStatus = "Exported ZIP archive: \(archiveURL.lastPathComponent)"
        return archiveURL
    }

    private func archiveEntryPath(for date: Date, format: ExportFormat, settings: AdvancedExportSettings) -> String {
        var components: [String] = []
        if let folderPath = settings.formatFolderPath(for: date, format: format) {
            components.append(folderPath)
        }
        components.append(settings.filename(for: date, format: format))
        return components.joined(separator: "/")
    }

    private func rollupArchiveEntries(from healthData: [HealthData], settings: AdvancedExportSettings) -> [ZipArchiveWriter.Entry] {
        guard HealthRollupExporter.isEnabled(settings: settings), !healthData.isEmpty else { return [] }
        let summaries = HealthRollupExporter.makeSummaries(from: healthData, settings: settings)
        return HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: "",
            settings: settings
        ).compactMap { target in
            guard let data = target.content.data(using: .utf8) else { return nil }
            return ZipArchiveWriter.Entry(path: target.relativePath, data: data)
        }
    }

    private func dataDictionaryArchiveEntry(settings: AdvancedExportSettings) -> ZipArchiveWriter.Entry {
        let entries = HealthMetricDataDictionary.entries(using: settings.formatCustomization)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(entries)) ?? Data("[]".utf8)
        let normalizedData: Data
        if var json = String(data: data, encoding: .utf8) {
            json += "\n"
            normalizedData = Data(json.utf8)
        } else {
            normalizedData = data
        }
        return ZipArchiveWriter.Entry(
            path: HealthMdExportSchema.dataDictionaryFilename,
            data: normalizedData
        )
    }

    private func archiveFilename(
        startDate: Date,
        endDate: Date,
        timeZone: TimeZone? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        let range = start == end ? start : "\(start)_to_\(end)"
        return "Health.md Export \(range).zip"
    }

    // MARK: - Roll-up Summaries

    @discardableResult
    func exportRollupSummaries(
        from healthData: [HealthData],
        settings: AdvancedExportSettings,
        generatedAt: Date = Date(),
        healthSubfolder: String? = nil,
        writeDataDictionary shouldWriteDataDictionary: Bool = true
    ) throws -> [HealthRollupWriteResult] {
        guard let vaultURL = vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }

        guard HealthRollupExporter.isEnabled(settings: settings) else { return [] }

        guard bookmarkResolver.startAccessing(vaultURL) else {
            throw ExportError.accessDenied
        }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let summaries = HealthRollupExporter.makeSummaries(
            from: healthData,
            settings: settings,
            generatedAt: generatedAt
        )
        guard !summaries.isEmpty else { return [] }

        let effectiveHealthSubfolder = healthSubfolder ?? self.healthSubfolder
        if shouldWriteDataDictionary {
            try writeDataDictionary(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                settings: settings
            )
        }

        var results: [HealthRollupWriteResult] = []
        var writtenFiles: [WrittenAggregateFile] = []
        for target in HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: effectiveHealthSubfolder,
            settings: settings
        ) {
            let folderURL = HealthRollupExporter.folderURL(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                period: target.summary.period,
                format: target.format,
                settings: settings
            )
            if !fileSystem.fileExists(atPath: folderURL.path) {
                try fileSystem.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }

            let fileURL = ExportPathPlanner.fileURL(in: folderURL, filename: target.filename)
            try fileSystem.writeString(target.content, to: fileURL, atomically: true)
            results.append(target)
            writtenFiles.append(WrittenAggregateFile(
                fileURL: fileURL,
                filename: target.filename,
                relativePath: target.relativePath,
                format: target.format
            ))
        }

        if lastExportPresentationTarget == nil,
           let previewFile = preferredPresentationFile(in: writtenFiles) {
            recordExportPresentationTarget(
                fileURL: previewFile.fileURL,
                securityScopedRootURL: vaultURL
            )
        }
        return results
    }

    nonisolated private static func performArchiveIO<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func writeCompactRollupProjection(
        sourceURL: URL,
        destinationURL: URL,
        corpusProtocolVersion: Int
    ) async throws -> Bool {
        try Task.checkCancellation()
        let payload: ConnectedCorpusHealthDayPayload
        if ConnectedCorpusApplicationItemCodec.usesStreamableItems(
            protocolVersion: corpusProtocolVersion
        ) {
            payload = try ConnectedCorpusApplicationItemCodec.decode(
                ConnectedCorpusHealthDayPayload.self,
                from: sourceURL,
                expectedKind: .macHealthDay
            )
        } else {
            payload = try JSONDecoder().decode(
                ConnectedCorpusHealthDayPayload.self,
                from: Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            )
        }
        guard let record = payload.record else { return false }
        let projection = ConnectedExportGranularMode.sanitized(
            record,
            includesGranularData: false
        )
        try JSONEncoder().encode(projection).write(to: destinationURL, options: .atomic)
        return true
    }

    nonisolated private static func decodeHealthData(from url: URL) async throws -> HealthData {
        try Task.checkCancellation()
        return try JSONDecoder().decode(
            HealthData.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
    }

    nonisolated private static func decodeConnectedHealthData(
        from url: URL,
        corpusProtocolVersion: Int
    ) async throws -> HealthData? {
        try Task.checkCancellation()
        if ConnectedCorpusApplicationItemCodec.usesStreamableItems(
            protocolVersion: corpusProtocolVersion
        ) {
            return try ConnectedCorpusApplicationItemCodec.decode(
                ConnectedCorpusHealthDayPayload.self,
                from: url,
                expectedKind: .macHealthDay
            ).record
        }
        return try JSONDecoder().decode(
            ConnectedCorpusHealthDayPayload.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        ).record
    }

    /// Finalizes derived output for a partitioned connected export while
    /// retaining at most one roll-up window (or one archive day) in memory.
    /// Dense payloads are decoded once into compact disk-backed roll-up
    /// projections, while archive rendering still reads one source day at a time.
    func finalizeCorpusDerivedOutputs(
        recordPayloadFiles: [URL],
        recordSourceDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        requestedDates: [Date],
        startDate: Date,
        endDate: Date,
        healthSubfolder: String? = nil,
        archiveWorkDirectoryURL: URL? = nil,
        unavailableRollupDates: Set<Date> = [],
        writeDataDictionary shouldWriteDataDictionary: Bool = true,
        corpusProtocolVersion: Int = ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion,
        progress: ((_ processed: Int, _ total: Int, _ date: Date?) -> Void)? = nil,
        cancellationCheck: () -> Bool = { false }
    ) async throws -> MacCorpusDerivedOutputResult {
        func checkCancellation() throws {
            if Task.isCancelled || cancellationCheck() { throw CancellationError() }
        }
        try checkCancellation()
        guard settings.archiveModeEnabled || HealthRollupExporter.isEnabled(settings: settings) else {
            return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 0)
        }
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "connected-mac",
                phase: "derived-finalization",
                timer: performanceTimer,
                itemCount: recordPayloadFiles.count
            )
        }
        #endif
        guard let vaultURL else {
            throw hasSavedVaultFolder ? ExportError.accessDenied : ExportError.noVaultSelected
        }
        guard bookmarkResolver.startAccessing(vaultURL) else { throw ExportError.accessDenied }
        defer { bookmarkResolver.stopAccessing(vaultURL) }

        let decoder = JSONDecoder()
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = settings.exportTimeZoneOverride ?? .current
        var datedFiles: [(date: Date, url: URL)] = []
        datedFiles.reserveCapacity(recordPayloadFiles.count)
        if let recordSourceDates,
           recordSourceDates.count == recordPayloadFiles.count {
            datedFiles = Array(zip(recordSourceDates, recordPayloadFiles)).map {
                (date: $0.0, url: $0.1)
            }
        } else {
            // Backward-compatible fallback for callers that predate journal
            // source-date metadata. Current connected sessions avoid decoding
            // each dense payload merely to rediscover its date.
            for url in recordPayloadFiles {
                try checkCancellation()
                let payload: ConnectedCorpusHealthDayPayload
                if ConnectedCorpusApplicationItemCodec.usesStreamableItems(
                    protocolVersion: corpusProtocolVersion
                ) {
                    payload = try ConnectedCorpusApplicationItemCodec.decode(
                        ConnectedCorpusHealthDayPayload.self,
                        from: url,
                        expectedKind: .macHealthDay
                    )
                } else {
                    payload = try decoder.decode(
                        ConnectedCorpusHealthDayPayload.self,
                        from: Data(contentsOf: url, options: [.mappedIfSafe])
                    )
                }
                if payload.record != nil { datedFiles.append((payload.sourceDate, url)) }
                await Task.yield()
            }
        }
        datedFiles.sort { $0.date < $1.date }

        var projectionDirectoryToCleanup: URL?
        defer {
            if let projectionDirectoryToCleanup {
                try? FileManager.default.removeItem(at: projectionDirectoryToCleanup)
            }
        }
        var rollupProjectionFiles: [(date: Date, url: URL)] = []
        if HealthRollupExporter.isEnabled(settings: settings) {
            let parent = archiveWorkDirectoryURL ?? FileManager.default.temporaryDirectory
            let projectionDirectory = parent.appendingPathComponent(
                ".healthmd-rollup-projections-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: projectionDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            projectionDirectoryToCleanup = projectionDirectory
            for (index, item) in datedFiles.enumerated() {
                try checkCancellation()
                let projectionURL = projectionDirectory.appendingPathComponent(
                    "\(index).json",
                    isDirectory: false
                )
                if try await Self.writeCompactRollupProjection(
                    sourceURL: item.url,
                    destinationURL: projectionURL,
                    corpusProtocolVersion: corpusProtocolVersion
                ) {
                    rollupProjectionFiles.append((item.date, projectionURL))
                }
                await Task.yield()
            }
        }

        var summaries: [HealthRollupSummary] = []
        var finalizedUnits = 0
        let estimatedUnits = max(datedFiles.count + requestedDates.count, 1)
        if HealthRollupExporter.isEnabled(settings: settings) {
            for period in settings.enabledRollupPeriods {
                let windows = Set(requestedDates.map {
                    HealthRollupPeriodWindow.window(containing: $0, period: period, calendar: sourceCalendar)
                }).sorted { $0.startDate < $1.startDate }
                for window in windows {
                    try checkCancellation()
                    if unavailableRollupDates.contains(where: {
                        $0 >= window.startDate && $0 <= window.endDate
                    }) {
                        finalizedUnits += 1
                        progress?(finalizedUnits, estimatedUnits, window.endDate)
                        await Task.yield()
                        continue
                    }
                    var records: [HealthData] = []
                    for item in rollupProjectionFiles
                        where item.date >= window.startDate && item.date <= window.endDate {
                        records.append(try await Self.decodeHealthData(from: item.url))
                    }
                    let windowSummaries = HealthRollupExporter.makeSummaries(
                        from: records,
                        settings: settings,
                        periods: [period],
                        calendar: sourceCalendar
                    ).filter { $0.window == window }
                    summaries.append(contentsOf: windowSummaries)
                    finalizedUnits += 1
                    progress?(finalizedUnits, estimatedUnits, window.endDate)
                    await Task.yield()
                }
            }
        }

        let effectiveHealthSubfolder = healthSubfolder ?? self.healthSubfolder
        if settings.archiveModeEnabled {
            guard !datedFiles.isEmpty || (settings.summaryOnlyModeEnabled && !summaries.isEmpty) else {
                return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 0)
            }
            let healthFolderURL = ExportPathPlanner.healthSubfolderURL(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder
            )
            if !fileSystem.fileExists(atPath: healthFolderURL.path) {
                try fileSystem.createDirectory(at: healthFolderURL, withIntermediateDirectories: true)
            }
            let archiveURL = healthFolderURL.appendingPathComponent(
                archiveFilename(
                    startDate: startDate,
                    endDate: endDate,
                    timeZone: settings.exportTimeZoneOverride
                ),
                isDirectory: false
            )
            let workDirectory = archiveWorkDirectoryURL ?? healthFolderURL
            try FileManager.default.createDirectory(
                at: workDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let checkpointURL = workDirectory.appendingPathComponent(
                "archive-checkpoint.json",
                isDirectory: false
            )
            let fileManager = FileManager.default
            let writer: ZipArchiveWriter.Writer
            var committedArchivePaths: Set<String>
            if fileManager.fileExists(atPath: checkpointURL.path) {
                let checkpoint = try ZipArchiveWriter.loadCheckpoint(from: checkpointURL)
                guard checkpoint.destinationURL.standardizedFileURL == archiveURL.standardizedFileURL,
                      checkpoint.checkpointURL.standardizedFileURL == checkpointURL.standardizedFileURL else {
                    throw ZipArchiveWriter.ArchiveError.invalidCheckpoint
                }
                committedArchivePaths = Set(checkpoint.entryPaths)
                writer = try ZipArchiveWriter.recover(from: checkpointURL)
            } else {
                committedArchivePaths = []
                writer = try ZipArchiveWriter.begin(
                    to: archiveURL,
                    checkpointURL: checkpointURL,
                    workingDirectoryURL: workDirectory
                )
            }
            do {
                let dictionaryEntry = dataDictionaryArchiveEntry(settings: settings)
                if !committedArchivePaths.contains(dictionaryEntry.path) {
                    try checkCancellation()
                    try await Self.performArchiveIO {
                        try writer.append(dictionaryEntry, cancellationCheck: { Task.isCancelled })
                        _ = try writer.checkpoint()
                    }
                    committedArchivePaths.insert(dictionaryEntry.path)
                }

                if !settings.summaryOnlyModeEnabled {
                    let requestedDateSet = Set(requestedDates)
                    for item in datedFiles where requestedDateSet.contains(item.date) {
                        try checkCancellation()
                        progress?(finalizedUnits, estimatedUnits, item.date)
                        guard let record = try await Self.decodeConnectedHealthData(
                            from: item.url,
                            corpusProtocolVersion: corpusProtocolVersion
                        ) else { continue }
                        let preparedExport = record.preparedExport(settings: settings)
                        for format in settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
                            let content = try preparedExport.content(format: format, settings: settings)
                            guard let data = content.data(using: .utf8) else {
                                throw CocoaError(.fileWriteInapplicableStringEncoding)
                            }
                            let entry = ZipArchiveWriter.Entry(
                                path: archiveEntryPath(for: record.date, format: format, settings: settings),
                                data: data
                            )
                            if !committedArchivePaths.contains(entry.path) {
                                try checkCancellation()
                                try await Self.performArchiveIO {
                                    try writer.append(entry, cancellationCheck: { Task.isCancelled })
                                    _ = try writer.checkpoint()
                                }
                                committedArchivePaths.insert(entry.path)
                            }
                        }
                        finalizedUnits += 1
                        progress?(finalizedUnits, estimatedUnits, item.date)
                        await Task.yield()
                    }
                }
                for target in HealthRollupExporter.outputTargets(
                    for: summaries,
                    healthSubfolder: "",
                    settings: settings
                ) {
                    guard let data = target.content.data(using: .utf8) else { continue }
                    let entry = ZipArchiveWriter.Entry(path: target.relativePath, data: data)
                    if !committedArchivePaths.contains(entry.path) {
                        try checkCancellation()
                        try await Self.performArchiveIO {
                            try writer.append(entry, cancellationCheck: { Task.isCancelled })
                            _ = try writer.checkpoint()
                        }
                        committedArchivePaths.insert(entry.path)
                    }
                }
                try checkCancellation()
                try await Self.performArchiveIO {
                    try writer.finish(cancellationCheck: { Task.isCancelled })
                }
                recordExportPresentationTarget(
                    fileURL: archiveURL,
                    securityScopedRootURL: vaultURL
                )
                lastExportStatus = "Exported ZIP archive: \(archiveURL.lastPathComponent)"
                return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 1)
            } catch {
                try? await Self.performArchiveIO { writer.abandon() }
                throw error
            }
        }

        guard !summaries.isEmpty else {
            return MacCorpusDerivedOutputResult(rollupFileCount: 0, archiveFileCount: 0)
        }
        if shouldWriteDataDictionary {
            try writeDataDictionary(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                settings: settings
            )
        }
        let targets = HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: effectiveHealthSubfolder,
            settings: settings
        )
        for target in targets {
            try checkCancellation()
            let folderURL = HealthRollupExporter.folderURL(
                vaultURL: vaultURL,
                healthSubfolder: effectiveHealthSubfolder,
                period: target.summary.period,
                format: target.format,
                settings: settings
            )
            if !fileSystem.fileExists(atPath: folderURL.path) {
                try fileSystem.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            let fileURL = ExportPathPlanner.fileURL(in: folderURL, filename: target.filename)
            try fileSystem.writeString(target.content, to: fileURL, atomically: true)
            progress?(finalizedUnits, estimatedUnits, target.summary.window.endDate)
            await Task.yield()
        }
        try checkCancellation()
        return MacCorpusDerivedOutputResult(rollupFileCount: targets.count, archiveFileCount: 0)
    }

    // MARK: - Format Routing

    private func looseExportFormats(in settings: AdvancedExportSettings) -> [ExportFormat] {
        settings.exportFormats
            .filter { _ in settings.writesDailyAggregateFiles }
            .sorted(by: { $0.rawValue < $1.rawValue })
    }

    // MARK: - Data Dictionary

    private func makeDataDictionaryWriteRequest(
        vaultURL: URL,
        healthSubfolder: String? = nil,
        settings: AdvancedExportSettings
    ) throws -> AggregateFileWriteRequest? {
        let folderURL = ExportPathPlanner.healthSubfolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder
        )
        let entries = HealthMetricDataDictionary.entries(using: settings.formatCustomization)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        guard let json = String(data: data, encoding: .utf8) else { return nil }
        return AggregateFileWriteRequest(
            fileURL: folderURL.appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename),
            filename: HealthMdExportSchema.dataDictionaryFilename,
            newContent: json + "\n",
            behavior: .overwrite
        )
    }

    private func writeDataDictionary(
        vaultURL: URL,
        healthSubfolder: String? = nil,
        settings: AdvancedExportSettings
    ) throws {
        guard let request = try makeDataDictionaryWriteRequest(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings
        ) else { return }
        _ = try aggregateFileWriter.writeSynchronously(request)
    }

    // MARK: - Collision Safety

    private func ensureNoDailyNoteExportCollision(
        vaultURL: URL,
        healthSubfolder: String? = nil,
        date: Date,
        settings: AdvancedExportSettings
    ) throws {
        if let collision = ExportPathPlanner.dailyNoteExportCollision(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder,
            settings: settings,
            date: date
        ) {
            throw ExportError.dailyNotePathConflict(path: collision.dailyNoteRelativePath)
        }
    }

    // MARK: - Per-Format Writer

    /// Freezes mutable render settings into an immutable write request on MainActor.
    /// The serialized filesystem transaction can then run safely on its utility queue.
    private func makeAggregateFileWriteRequest(
        preparedExport: PreparedHealthDataExport,
        date: Date,
        format: ExportFormat,
        targetFolderURL: URL,
        settings: AdvancedExportSettings
    ) throws -> AggregateFileWriteRequest {
        let filename = settings.filename(for: date, format: format)
        let fileURL = ExportPathPlanner.fileURL(in: targetFolderURL, filename: filename)
        let newContent = try preparedExport.content(format: format, settings: settings)
        let behavior: AggregateFileWriteBehavior
        switch settings.writeMode {
        case .append:
            behavior = .append
        case .update where format == .markdown:
            behavior = .mergeMarkdown
        case .update, .overwrite:
            behavior = .overwrite
        }
        return AggregateFileWriteRequest(
            fileURL: fileURL,
            filename: filename,
            newContent: newContent,
            behavior: behavior
        )
    }

    private func writeOneFormat(
        preparedExport: PreparedHealthDataExport,
        date: Date,
        format: ExportFormat,
        targetFolderURL: URL,
        settings: AdvancedExportSettings
    ) throws -> AggregateFileWriteOutcome {
        let request = try makeAggregateFileWriteRequest(
            preparedExport: preparedExport,
            date: date,
            format: format,
            targetFolderURL: targetFolderURL,
            settings: settings
        )
        return try aggregateFileWriter.writeSynchronously(request)
    }

    private func writeOneFormatOffMain(
        preparedExport: PreparedHealthDataExport,
        date: Date,
        format: ExportFormat,
        targetFolderURL: URL,
        settings: AdvancedExportSettings
    ) async throws -> AggregateFileWriteOutcome {
        let request = try makeAggregateFileWriteRequest(
            preparedExport: preparedExport,
            date: date,
            format: format,
            targetFolderURL: targetFolderURL,
            settings: settings
        )
        return try await aggregateFileWriter.write(request)
    }

    private func individualEntriesBaseFolderURL(
        vaultURL: URL,
        healthSubfolder: String? = nil,
        date: Date,
        settings: AdvancedExportSettings
    ) -> URL {
        ExportPathPlanner.aggregateFolderURL(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder ?? self.healthSubfolder,
            settings: settings,
            date: date,
            format: settings.organizeFormatsIntoFolders ? .markdown : nil
        )
    }

    private func preferredPresentationFile(
        in writtenFiles: [WrittenAggregateFile]
    ) -> WrittenAggregateFile? {
        let preferredFormats: [ExportFormat] = [.markdown, .obsidianBases, .json, .csv]
        for format in preferredFormats {
            if let file = writtenFiles.first(where: { $0.format == format }) {
                return file
            }
        }
        return writtenFiles.first
    }

    private func statusPathSummary(for writtenFiles: [WrittenAggregateFile]) -> String {
        guard !writtenFiles.isEmpty else { return "" }

        let folderToFilenames = Dictionary(grouping: writtenFiles) { file in
            Self.parentPath(for: file.relativePath)
        }.mapValues { files in
            files.map { $0.filename }
        }

        if folderToFilenames.count == 1,
           let folder = folderToFilenames.keys.first,
           let filenames = folderToFilenames[folder] {
            let prefix = folder.isEmpty ? "" : folder + "/"
            return prefix + filenames.joined(separator: ", ")
        }

        return writtenFiles.map { $0.relativePath }.joined(separator: ", ")
    }

    private static func parentPath(for relativePath: String) -> String {
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }

    // MARK: - Individual Entry Export

    /// Export individual timestamped entries for configured metrics
    private func exportIndividualEntries(
        from healthData: HealthData,
        to baseURL: URL,
        settings: AdvancedExportSettings
    ) throws -> Int {
        let trackingSettings = settings.individualTracking

        // Extract samples that should be tracked individually
        let samples = individualExporter.extractIndividualSamples(
            from: healthData,
            settings: trackingSettings
        )

        guard !samples.isEmpty else { return 0 }

        // Export the samples
        return try individualExporter.exportIndividualEntries(
            samples: samples,
            to: baseURL,
            settings: trackingSettings,
            formatSettings: settings.formatCustomization
        )
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case noVaultSelected
    case noHealthData
    case accessDenied
    case noFormatsSelected
    case dailyNotePathConflict(path: String)

    var errorDescription: String? {
        switch self {
        case .noVaultSelected:
            return "Please select an Obsidian vault folder first"
        case .noHealthData:
            return "No health data available for the selected date"
        case .accessDenied:
            return "Cannot access the vault folder. Reconnect it in Files or re-select it."
        case .noFormatsSelected:
            return "At least one export format must be selected"
        case .dailyNotePathConflict(let path):
            return "Daily Note Injection target conflicts with export output: \(path). Change Output folder/filename or Daily Note Injection folder/filename."
        }
    }
}
