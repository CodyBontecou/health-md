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
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try writeFile(
            to: destinationURL,
            fileManager: fileManager,
            attributes: attributes
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
        beforeCommit: () throws -> Void = {},
        producer: (URL) throws -> Result
    ) throws -> Result {
        let directoryURL = destinationURL.deletingLastPathComponent()
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
            try renameReplacingItem(at: temporaryURL, withItemAt: destinationURL)
            temporaryFileCreated = false
            fsyncDirectoryIfPossible(directoryURL)
            return result
        } catch {
            if temporaryFileCreated {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
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

    private static func fsyncDirectoryIfPossible(_ directoryURL: URL) {
        directoryURL.withUnsafeFileSystemRepresentation { directoryPath in
            guard let directoryPath else { return }
            let descriptor = open(directoryPath, O_RDONLY)
            guard descriptor >= 0 else { return }
            _ = fsync(descriptor)
            _ = close(descriptor)
        }
    }
}
