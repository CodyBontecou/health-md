//
//  AtomicFileWriter.swift
//  Health.md
//
//  Writes export files via a same-directory temporary file followed by an
//  atomic rename, so sync providers never observe partially-written content.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

nonisolated enum AtomicFileWriter {
    enum CommitPolicy { case replaceExisting, requireAbsent, replaceIfUnchanged(Data) }
    enum DirectoryDurability { case bestEffort, required(upTo: URL) }
    static func writeString(_ string: String, to destinationURL: URL, fileManager: FileManager = .default) throws {
        guard let data = string.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try writeData(data, to: destinationURL, fileManager: fileManager)
    }

    static func writeData(
        _ data: Data,
        to destinationURL: URL,
        fileManager: FileManager = .default,
        attributes: [FileAttributeKey: Any]? = nil,
        commitPolicy: CommitPolicy = .replaceExisting,
        transactionLockURL: URL? = nil,
        directoryDurability: DirectoryDurability = .bestEffort,
        directorySync: (URL) throws -> Void = synchronizeDirectory
    ) throws {
        try writeFile(
            to: destinationURL,
            fileManager: fileManager,
            attributes: attributes,
            commitPolicy: commitPolicy,
            transactionLockURL: transactionLockURL,
            directoryDurability: directoryDurability,
            directorySync: directorySync
        ) { temporaryURL in
            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    /// Runs a bounded producer against a same-directory temporary file and
    /// commits it only after the producer returns successfully. The producer
    /// owns synchronization and closure of any handles it opens.
    static func writeFile<Result>(
        to destinationURL: URL,
        fileManager: FileManager = .default,
        attributes: [FileAttributeKey: Any]? = nil,
        commitPolicy: CommitPolicy = .replaceExisting,
        transactionLockURL: URL? = nil,
        directoryDurability: DirectoryDurability = .bestEffort,
        directorySync: (URL) throws -> Void = synchronizeDirectory,
        beforeCommit: () throws -> Void = {},
        producer: (URL) throws -> Result
    ) throws -> Result {
        return try withPublicationLock(at: transactionLockURL) {
            let directoryURL = destinationURL.deletingLastPathComponent()
            _ = try requiredDirectories(for: directoryDurability, from: directoryURL)
            let temporaryURL = temporaryFileURL(for: destinationURL)
            var temporaryFileCreated = false

            do {
                guard fileManager.createFile(
                    atPath: temporaryURL.path,
                    contents: nil,
                    attributes: attributes
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                temporaryFileCreated = true
                let result = try producer(temporaryURL)
                try beforeCommit()
                switch commitPolicy {
                case .replaceExisting:
                    try renameReplacingItem(at: temporaryURL, withItemAt: destinationURL)
                case .replaceIfUnchanged(let expected):
                    guard let transactionLockURL, transactionLockURL.isFileURL else { throw POSIXError(.EINVAL) }
                    guard try fileManager.attributesOfItem(atPath: destinationURL.path)[.type] as? FileAttributeType == .typeRegular,
                          try Data(contentsOf: destinationURL) == expected else { throw POSIXError(.EAGAIN) }
                    try renameReplacingItem(at: temporaryURL, withItemAt: destinationURL)
                case .requireAbsent:
                    try linkNewItem(at: temporaryURL, to: destinationURL)
                    try? fileManager.removeItem(at: temporaryURL)
                }
                temporaryFileCreated = false
                try synchronizeDirectories(from: directoryURL, durability: directoryDurability, directorySync: directorySync)
                return result
            } catch {
                if temporaryFileCreated {
                    try? fileManager.removeItem(at: temporaryURL)
                }
                throw error
            }
        }
    }

    private static let publicationMutex = NSLock()

    /// The lock inode lives outside job cleanup and is never removed by this writer.
    private static func withPublicationLock<Result>(at url: URL?, operation: () throws -> Result) throws -> Result {
        guard let url else { return try operation() }
        guard url.isFileURL else { throw POSIXError(.EINVAL) }
        return try publicationMutex.withLock {
            let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            }
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { _ = close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { _ = flock(descriptor, LOCK_UN) }
            return try operation()
        }
    }

    static func temporaryFileURL(for destinationURL: URL, uuid: UUID = UUID()) -> URL {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let baseName = destinationURL.lastPathComponent.isEmpty ? "export" : destinationURL.lastPathComponent
        return directoryURL.appendingPathComponent(".\(baseName).\(uuid.uuidString).tmp", isDirectory: false)
    }

    private static func renameReplacingItem(at temporaryURL: URL, withItemAt destinationURL: URL) throws {
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                rename(temporaryPath, destinationPath)
            }
        }

        if result != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// link(2) publishes a fully written sibling inode only if the destination
    /// is absent at the syscall boundary. It cannot replace a competing journal.
    private static func linkNewItem(at temporaryURL: URL, to destinationURL: URL) throws {
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                link(temporaryPath, destinationPath)
            }
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func synchronizeDirectories(
        from directory: URL,
        durability: DirectoryDurability,
        directorySync: (URL) throws -> Void = synchronizeDirectory
    ) throws {
        switch durability {
        case .bestEffort:
            try? directorySync(directory)
        case .required:
            for directory in try requiredDirectories(for: durability, from: directory) {
                try directorySync(directory)
            }
        }
    }

    static func synchronizeDirectory(_ directoryURL: URL) throws {
        try directoryURL.withUnsafeFileSystemRepresentation { directoryPath in
            guard let directoryPath else { throw CocoaError(.fileWriteInvalidFileName) }
            let descriptor = open(directoryPath, O_RDONLY)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            defer { _ = close(descriptor) }
            guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }

    private static func requiredDirectories(for policy: DirectoryDurability, from directory: URL) throws -> [URL] {
        guard case .required(let requestedRoot) = policy else { return [] }
        let directory = directory.standardizedFileURL
        let root = requestedRoot.standardizedFileURL
        guard directory.isFileURL, root.isFileURL,
              directory.pathComponents.starts(with: root.pathComponents) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        var directories: [URL] = []
        var current = directory
        while true {
            directories.append(current)
            if current.path == root.path { return directories }
            current = current.deletingLastPathComponent()
        }
    }
}
