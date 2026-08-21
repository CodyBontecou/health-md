import Compression
import Foundation

/// A disk-backed ZIP64 writer for export archives.
///
/// Entries use ZIP's DEFLATE method by default. Source bytes, compressed output,
/// and central-directory records are written incrementally so the completed
/// archive is never assembled in memory.
nonisolated enum ZipArchiveWriter {
    static let defaultChunkSize = 64 * 1024
    private static let maximumChunkSize = 1024 * 1024
    private static let checkpointFormatVersion = 2
    private static let legacyCheckpointFormatVersion = 1

    enum CompressionMethod: UInt16, Codable, Sendable {
        case store = 0
        case deflate = 8
    }

    struct Entry: Sendable {
        let path: String
        let data: Data
        fileprivate let requestedPath: String

        init(path: String, data: Data) {
            requestedPath = path
            self.path = ZipArchiveWriter.normalizedEntryPath(path)
            self.data = data
        }
    }

    struct FileEntry: Sendable {
        let path: String
        let sourceURL: URL
        fileprivate let requestedPath: String

        init(path: String, sourceURL: URL) {
            requestedPath = path
            self.path = ZipArchiveWriter.normalizedEntryPath(path)
            self.sourceURL = sourceURL
        }
    }

    struct Checkpoint: Codable, Equatable, Sendable {
        fileprivate let formatVersion: Int
        let destinationURL: URL
        let temporaryArchiveURL: URL
        let centralDirectoryURL: URL
        let checkpointURL: URL
        let archiveByteCount: UInt64
        let centralDirectoryByteCount: UInt64
        let entryPaths: [String]
        fileprivate let dosDate: UInt16
        fileprivate let dosTime: UInt16
        fileprivate let chunkSize: Int
        /// Missing only in legacy v1 checkpoints, whose entries always used store.
        fileprivate let compressionMethod: CompressionMethod?

        var entryCount: UInt64 { UInt64(entryPaths.count) }
    }

    enum ArchiveError: Error, Equatable, LocalizedError {
        case unsafePath(String)
        case duplicatePath(String)
        case pathTooLong(String)
        case invalidChunkSize(Int)
        case checkpointAlreadyExists(URL)
        case invalidCheckpoint
        case missingRecoveryFile(URL)
        case recoveryFileTooShort(URL)
        case archiveNotOpen
        case sourceIsNotARegularFile(URL)
        case compressionFailed
        case integerOverflow

        var errorDescription: String? {
            switch self {
            case .unsafePath(let path):
                return "Unsafe ZIP entry path: \(path)"
            case .duplicatePath(let path):
                return "Duplicate ZIP entry path: \(path)"
            case .pathTooLong(let path):
                return "ZIP entry path is too long: \(path)"
            case .invalidChunkSize(let size):
                return "ZIP chunk size must be between 1 and \(ZipArchiveWriter.maximumChunkSize) bytes (got \(size))"
            case .checkpointAlreadyExists(let url):
                return "ZIP checkpoint already exists: \(url.path)"
            case .invalidCheckpoint:
                return "The ZIP checkpoint is invalid or unsupported"
            case .missingRecoveryFile(let url):
                return "A ZIP recovery file is missing: \(url.path)"
            case .recoveryFileTooShort(let url):
                return "A ZIP recovery file is shorter than its checkpoint: \(url.path)"
            case .archiveNotOpen:
                return "The ZIP writer is no longer open"
            case .sourceIsNotARegularFile(let url):
                return "ZIP source is not a regular file: \(url.path)"
            case .compressionFailed:
                return "ZIP entry compression failed"
            case .integerOverflow:
                return "The ZIP archive exceeded supported integer limits"
            }
        }
    }

    /// Creates an incremental writer. An initial checkpoint is persisted before
    /// this method returns so an interrupted partitioned export can be recovered.
    static func begin(
        to destinationURL: URL,
        checkpointURL requestedCheckpointURL: URL? = nil,
        workingDirectoryURL: URL? = nil,
        fileManager: FileManager = .default,
        fileCoordinator: FileCoordinating = PassthroughFileCoordinator(),
        chunkSize: Int = defaultChunkSize,
        compressionMethod: CompressionMethod = .deflate,
        securePublication: SecurePublication? = nil
    ) throws -> Writer {
        try validate(chunkSize: chunkSize)

        let parentURL = destinationURL.deletingLastPathComponent()
        if securePublication == nil {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        let defaultCheckpointParent = securePublication == nil
            ? parentURL
            : fileManager.temporaryDirectory
        let checkpointURL = requestedCheckpointURL
            ?? defaultCheckpointParent.appendingPathComponent(
                ".\(destinationURL.lastPathComponent).zip-checkpoint-\(UUID().uuidString)"
            )
        if fileManager.fileExists(atPath: checkpointURL.path) {
            throw ArchiveError.checkpointAlreadyExists(checkpointURL)
        }
        try fileManager.createDirectory(
            at: checkpointURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let workParentURL = (workingDirectoryURL ?? checkpointURL.deletingLastPathComponent()).standardizedFileURL
        try fileManager.createDirectory(
            at: workParentURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let identifier = UUID().uuidString
        let temporaryArchiveURL = workParentURL.appendingPathComponent(".\(destinationURL.lastPathComponent).zip-writing-\(identifier)")
        let centralDirectoryURL = workParentURL.appendingPathComponent(".\(destinationURL.lastPathComponent).zip-central-\(identifier)")
        guard fileManager.createFile(atPath: temporaryArchiveURL.path, contents: nil),
              fileManager.createFile(atPath: centralDirectoryURL.path, contents: nil) else {
            try? fileManager.removeItem(at: temporaryArchiveURL)
            try? fileManager.removeItem(at: centralDirectoryURL)
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let timestamp = dosTimestampComponents(for: Date())
            let writer = try Writer(
                destinationURL: destinationURL,
                temporaryArchiveURL: temporaryArchiveURL,
                centralDirectoryURL: centralDirectoryURL,
                checkpointURL: checkpointURL,
                archiveByteCount: 0,
                centralDirectoryByteCount: 0,
                entryPaths: [],
                dosDate: timestamp.date,
                dosTime: timestamp.time,
                chunkSize: chunkSize,
                compressionMethod: compressionMethod,
                fileManager: fileManager,
                fileCoordinator: fileCoordinator,
                securePublication: securePublication
            )
            _ = try writer.checkpoint()
            return writer
        } catch {
            try? fileManager.removeItem(at: temporaryArchiveURL)
            try? fileManager.removeItem(at: centralDirectoryURL)
            try? fileManager.removeItem(at: checkpointURL)
            throw error
        }
    }

    /// Reopens a checkpoint. Any bytes written after the checkpoint (for
    /// example, a partially written entry at process termination) are truncated.
    static func recover(
        from checkpointURL: URL,
        fileManager: FileManager = .default,
        fileCoordinator: FileCoordinating = PassthroughFileCoordinator(),
        chunkSize: Int? = nil,
        securePublication: SecurePublication? = nil
    ) throws -> Writer {
        let checkpoint = try loadCheckpoint(from: checkpointURL)
        let checkpointParent = checkpointURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let temporaryParent = checkpoint.temporaryArchiveURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let centralParent = checkpoint.centralDirectoryURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let protectedURLs = [
            checkpoint.checkpointURL.standardizedFileURL,
            checkpoint.temporaryArchiveURL.standardizedFileURL,
            checkpoint.centralDirectoryURL.standardizedFileURL,
            checkpoint.destinationURL.standardizedFileURL
        ]
        let compressionMethod: CompressionMethod
        switch checkpoint.formatVersion {
        case legacyCheckpointFormatVersion:
            guard checkpoint.compressionMethod == nil else {
                throw ArchiveError.invalidCheckpoint
            }
            compressionMethod = .store
        case checkpointFormatVersion:
            guard let savedCompressionMethod = checkpoint.compressionMethod else {
                throw ArchiveError.invalidCheckpoint
            }
            compressionMethod = savedCompressionMethod
        default:
            throw ArchiveError.invalidCheckpoint
        }

        guard checkpoint.checkpointURL.standardizedFileURL == checkpointURL.standardizedFileURL,
              UInt64(checkpoint.entryPaths.count) == checkpoint.entryCount,
              temporaryParent == checkpointParent,
              centralParent == checkpointParent,
              Set(protectedURLs).count == protectedURLs.count,
              !isSymbolicLink(checkpointURL),
              !isSymbolicLink(checkpoint.temporaryArchiveURL),
              !isSymbolicLink(checkpoint.centralDirectoryURL) else {
            throw ArchiveError.invalidCheckpoint
        }

        let effectiveChunkSize = chunkSize ?? checkpoint.chunkSize
        try validate(chunkSize: effectiveChunkSize)
        try validateRecoveryFile(
            checkpoint.temporaryArchiveURL,
            minimumSize: checkpoint.archiveByteCount,
            fileManager: fileManager
        )
        try validateRecoveryFile(
            checkpoint.centralDirectoryURL,
            minimumSize: checkpoint.centralDirectoryByteCount,
            fileManager: fileManager
        )

        let normalizedPaths = try checkpoint.entryPaths.map { try validatedEntryPath($0) }
        var maximumCentralDirectoryBytes: UInt64 = 0
        for path in normalizedPaths {
            let entryBound = UInt64(path.utf8.count).addingReportingOverflow(128)
            let totalBound = maximumCentralDirectoryBytes.addingReportingOverflow(entryBound.partialValue)
            guard !entryBound.overflow, !totalBound.overflow else {
                throw ArchiveError.invalidCheckpoint
            }
            maximumCentralDirectoryBytes = totalBound.partialValue
        }
        guard Set(normalizedPaths).count == normalizedPaths.count,
              normalizedPaths == checkpoint.entryPaths,
              checkpoint.centralDirectoryByteCount <= maximumCentralDirectoryBytes else {
            throw ArchiveError.invalidCheckpoint
        }

        return try Writer(
            destinationURL: checkpoint.destinationURL,
            temporaryArchiveURL: checkpoint.temporaryArchiveURL,
            centralDirectoryURL: checkpoint.centralDirectoryURL,
            checkpointURL: checkpointURL,
            archiveByteCount: checkpoint.archiveByteCount,
            centralDirectoryByteCount: checkpoint.centralDirectoryByteCount,
            entryPaths: checkpoint.entryPaths,
            dosDate: checkpoint.dosDate,
            dosTime: checkpoint.dosTime,
            chunkSize: effectiveChunkSize,
            compressionMethod: compressionMethod,
            fileManager: fileManager,
            fileCoordinator: fileCoordinator,
            securePublication: securePublication,
            truncateToCheckpoint: true
        )
    }

    static func loadCheckpoint(from checkpointURL: URL) throws -> Checkpoint {
        do {
            let values = try checkpointURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= 16 * 1_024 * 1_024 else {
                throw ArchiveError.invalidCheckpoint
            }
            return try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: checkpointURL))
        } catch {
            throw ArchiveError.invalidCheckpoint
        }
    }

    /// Compatibility API used by existing exporters.
    static func write(
        entries: [Entry],
        to destinationURL: URL,
        fileManager: FileManager = .default,
        cancellationCheck: @escaping () -> Bool = { false }
    ) throws {
        let checkpointURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).zip-checkpoint-\(UUID().uuidString)")
        let writer = try begin(
            to: destinationURL,
            checkpointURL: checkpointURL,
            fileManager: fileManager
        )
        do {
            for entry in entries {
                try writer.append(entry, cancellationCheck: cancellationCheck)
            }
            try writer.finish(cancellationCheck: cancellationCheck)
        } catch {
            writer.abandon()
            throw error
        }
    }

    /// Convenience API for archives whose entries already exist as files.
    static func write(
        fileEntries: [FileEntry],
        to destinationURL: URL,
        fileManager: FileManager = .default,
        cancellationCheck: @escaping () -> Bool = { false }
    ) throws {
        let checkpointURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).zip-checkpoint-\(UUID().uuidString)")
        let writer = try begin(
            to: destinationURL,
            checkpointURL: checkpointURL,
            fileManager: fileManager
        )
        do {
            for entry in fileEntries {
                try writer.append(entry, cancellationCheck: cancellationCheck)
            }
            try writer.finish(cancellationCheck: cancellationCheck)
        } catch {
            writer.abandon()
            throw error
        }
    }

    struct SecurePublication: Sendable {
        let rootURL: URL
        let relativePath: String
        let binding: AppleVaultDestinationBinding
        let beforeCommit: (@Sendable () throws -> Void)?
        let afterValidationBeforeRename: (@Sendable () throws -> Void)?

        init(
            rootURL: URL,
            relativePath: String,
            binding: AppleVaultDestinationBinding,
            beforeCommit: (@Sendable () throws -> Void)? = nil,
            afterValidationBeforeRename: (@Sendable () throws -> Void)? = nil
        ) {
            self.rootURL = rootURL
            self.relativePath = relativePath
            self.binding = binding
            self.beforeCommit = beforeCommit
            self.afterValidationBeforeRename = afterValidationBeforeRename
        }
    }

    nonisolated final class Writer: @unchecked Sendable {
        let destinationURL: URL
        let temporaryArchiveURL: URL
        let centralDirectoryURL: URL
        let checkpointURL: URL
        let chunkSize: Int

        private let compressionMethod: CompressionMethod
        private let fileManager: FileManager
        private let fileCoordinator: FileCoordinating
        private let securePublication: SecurePublication?
        private var archiveHandle: FileHandle?
        private var centralDirectoryHandle: FileHandle?
        private var archiveByteCount: UInt64
        private var centralDirectoryByteCount: UInt64
        private var entryPaths: [String]
        private var entryPathSet: Set<String>
        private let dosDate: UInt16
        private let dosTime: UInt16
        private var preserveForRecovery = false

        fileprivate init(
            destinationURL: URL,
            temporaryArchiveURL: URL,
            centralDirectoryURL: URL,
            checkpointURL: URL,
            archiveByteCount: UInt64,
            centralDirectoryByteCount: UInt64,
            entryPaths: [String],
            dosDate: UInt16,
            dosTime: UInt16,
            chunkSize: Int,
            compressionMethod: CompressionMethod,
            fileManager: FileManager,
            fileCoordinator: FileCoordinating,
            securePublication: SecurePublication? = nil,
            truncateToCheckpoint: Bool = false
        ) throws {
            self.destinationURL = destinationURL
            self.temporaryArchiveURL = temporaryArchiveURL
            self.centralDirectoryURL = centralDirectoryURL
            self.checkpointURL = checkpointURL
            self.archiveByteCount = archiveByteCount
            self.centralDirectoryByteCount = centralDirectoryByteCount
            self.entryPaths = entryPaths
            entryPathSet = Set(entryPaths)
            self.dosDate = dosDate
            self.dosTime = dosTime
            self.chunkSize = chunkSize
            self.compressionMethod = compressionMethod
            self.fileManager = fileManager
            self.fileCoordinator = fileCoordinator
            self.securePublication = securePublication

            let archiveHandle = try FileHandle(forUpdating: temporaryArchiveURL)
            do {
                let centralDirectoryHandle = try FileHandle(forUpdating: centralDirectoryURL)
                do {
                    if truncateToCheckpoint {
                        try archiveHandle.truncate(atOffset: archiveByteCount)
                        try centralDirectoryHandle.truncate(atOffset: centralDirectoryByteCount)
                    }
                    try archiveHandle.seek(toOffset: archiveByteCount)
                    try centralDirectoryHandle.seek(toOffset: centralDirectoryByteCount)
                    self.archiveHandle = archiveHandle
                    self.centralDirectoryHandle = centralDirectoryHandle
                } catch {
                    try? centralDirectoryHandle.close()
                    throw error
                }
            } catch {
                try? archiveHandle.close()
                throw error
            }
        }

        deinit {
            closeHandles()
            if !preserveForRecovery {
                removeWorkingFiles()
            }
        }

        var writtenEntryCount: UInt64 { UInt64(entryPaths.count) }

        func append(_ entry: Entry, cancellationCheck: @escaping () -> Bool = { false }) throws {
            try append(path: entry.requestedPath, data: entry.data, cancellationCheck: cancellationCheck)
        }

        func append(_ entry: FileEntry, cancellationCheck: @escaping () -> Bool = { false }) throws {
            try append(path: entry.requestedPath, contentsOf: entry.sourceURL, cancellationCheck: cancellationCheck)
        }

        func append(
            path: String,
            data: Data,
            cancellationCheck: @escaping () -> Bool = { false }
        ) throws {
            try appendStream(path: path, cancellationCheck: cancellationCheck) { consume in
                var offset = 0
                while offset < data.count {
                    try Self.throwIfCancelled(cancellationCheck)
                    let end = min(offset + self.chunkSize, data.count)
                    try consume(data.subdata(in: offset..<end))
                    offset = end
                }
            }
        }

        func append(
            path: String,
            contentsOf sourceURL: URL,
            cancellationCheck: @escaping () -> Bool = { false }
        ) throws {
            let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw ArchiveError.sourceIsNotARegularFile(sourceURL)
            }

            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? sourceHandle.close() }
            try appendStream(path: path, cancellationCheck: cancellationCheck) { consume in
                while true {
                    try Self.throwIfCancelled(cancellationCheck)
                    guard let bytes = try sourceHandle.read(upToCount: self.chunkSize), !bytes.isEmpty else {
                        break
                    }
                    try consume(bytes)
                }
            }
        }

        func appendFile(
            at sourceURL: URL,
            path: String,
            cancellationCheck: @escaping () -> Bool = { false }
        ) throws {
            try append(path: path, contentsOf: sourceURL, cancellationCheck: cancellationCheck)
        }

        /// Flushes both work files and atomically replaces the checkpoint.
        @discardableResult
        func checkpoint() throws -> Checkpoint {
            let (archiveHandle, centralDirectoryHandle) = try openHandles()
            try archiveHandle.synchronize()
            try centralDirectoryHandle.synchronize()

            let checkpoint = Checkpoint(
                formatVersion: ZipArchiveWriter.checkpointFormatVersion,
                destinationURL: destinationURL,
                temporaryArchiveURL: temporaryArchiveURL,
                centralDirectoryURL: centralDirectoryURL,
                checkpointURL: checkpointURL,
                archiveByteCount: archiveByteCount,
                centralDirectoryByteCount: centralDirectoryByteCount,
                entryPaths: entryPaths,
                dosDate: dosDate,
                dosTime: dosTime,
                chunkSize: chunkSize,
                compressionMethod: compressionMethod
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(checkpoint).write(to: checkpointURL, options: .atomic)
            return checkpoint
        }

        /// Persists a checkpoint, closes file descriptors, and leaves work files
        /// on disk for a later call to `recover(from:)`.
        @discardableResult
        func suspend() throws -> Checkpoint {
            let saved = try checkpoint()
            preserveForRecovery = true
            closeHandles()
            return saved
        }

        /// Writes the central directory and ZIP64 end records, then atomically
        /// renames the completed work file over the destination.
        func finish(cancellationCheck: () -> Bool = { false }) throws {
            let (archiveHandle, centralDirectoryHandle) = try openHandles()
            do {
                try Self.throwIfCancelled(cancellationCheck)
                try centralDirectoryHandle.synchronize()
                try centralDirectoryHandle.seek(toOffset: 0)

                let centralDirectoryOffset = archiveByteCount
                var copiedCentralDirectoryBytes: UInt64 = 0
                while true {
                    try Self.throwIfCancelled(cancellationCheck)
                    guard let bytes = try centralDirectoryHandle.read(upToCount: chunkSize), !bytes.isEmpty else {
                        break
                    }
                    try archiveHandle.write(contentsOf: bytes)
                    copiedCentralDirectoryBytes = try Self.adding(copiedCentralDirectoryBytes, UInt64(bytes.count))
                    archiveByteCount = try Self.adding(archiveByteCount, UInt64(bytes.count))
                }
                guard copiedCentralDirectoryBytes == centralDirectoryByteCount else {
                    throw ArchiveError.invalidCheckpoint
                }

                let zip64EndOffset = archiveByteCount
                let endRecords = Self.endRecords(
                    entryCount: UInt64(entryPaths.count),
                    centralDirectorySize: centralDirectoryByteCount,
                    centralDirectoryOffset: centralDirectoryOffset,
                    zip64EndOffset: zip64EndOffset
                )
                try archiveHandle.write(contentsOf: endRecords)
                archiveByteCount = try Self.adding(archiveByteCount, UInt64(endRecords.count))
                try archiveHandle.synchronize()
                closeHandles()

                if let securePublication {
                    try fileCoordinator.coordinateWriting(
                        at: destinationURL,
                        intent: .replace,
                        cancellationCheck: { try Self.throwIfCancelled(cancellationCheck) }
                    ) { coordinatedURL in
                        let coordinatedRootURL = try SecureExactArtifactIO.coordinatedRootURL(
                            for: coordinatedURL,
                            rootURL: securePublication.rootURL,
                            relativePath: securePublication.relativePath,
                            binding: securePublication.binding
                        )
                        try SecureExactArtifactIO.overwrite(
                            rootURL: coordinatedRootURL,
                            relativePath: securePublication.relativePath,
                            sourceFileURL: temporaryArchiveURL,
                            binding: securePublication.binding,
                            expectedByteCount: archiveByteCount,
                            chunkSize: chunkSize,
                            beforeCommit: securePublication.beforeCommit,
                            afterValidationBeforeRename: securePublication.afterValidationBeforeRename,
                            cancellationCheck: { try Self.throwIfCancelled(cancellationCheck) }
                        )
                    }
                } else {
                    try fileCoordinator.coordinateWriting(
                        at: destinationURL,
                        intent: .replace,
                        cancellationCheck: { try Self.throwIfCancelled(cancellationCheck) }
                    ) { coordinatedURL in
                        try publishArchive(
                            to: coordinatedURL,
                            cancellationCheck: cancellationCheck
                        )
                    }
                }
                try? fileManager.removeItem(at: temporaryArchiveURL)
                try? fileManager.removeItem(at: centralDirectoryURL)
                try? fileManager.removeItem(at: checkpointURL)
                preserveForRecovery = false // Retry cleanup at deinit if either removal failed.
            } catch {
                abandon()
                throw error
            }
        }

        /// Cancels the writer and removes its archive, central-directory spool,
        /// and checkpoint. An existing destination archive is not changed.
        func cancel() {
            abandon()
        }

        func abandon() {
            preserveForRecovery = false
            closeHandles()
            removeWorkingFiles()
        }

        private func appendStream(
            path requestedPath: String,
            cancellationCheck: @escaping () -> Bool,
            produce: (_ consume: (Data) throws -> Void) throws -> Void
        ) throws {
            let path = try ZipArchiveWriter.validatedEntryPath(requestedPath)
            guard !entryPathSet.contains(path) else {
                throw ArchiveError.duplicatePath(path)
            }
            guard let nameData = path.data(using: .utf8) else {
                throw ArchiveError.unsafePath(requestedPath)
            }
            guard nameData.count <= Int(UInt16.max) else {
                throw ArchiveError.pathTooLong(path)
            }
            let (archiveHandle, centralDirectoryHandle) = try openHandles()
            let startingArchiveByteCount = archiveByteCount
            let startingCentralDirectoryByteCount = centralDirectoryByteCount

            do {
                try Self.throwIfCancelled(cancellationCheck)
                let localHeader = Self.localHeader(
                    nameData: nameData,
                    compressionMethod: compressionMethod,
                    dosDate: dosDate,
                    dosTime: dosTime
                )
                try archiveHandle.write(contentsOf: localHeader)
                archiveByteCount = try Self.adding(archiveByteCount, UInt64(localHeader.count))

                var crc = CRC32()
                var compressedSize: UInt64 = 0
                var uncompressedSize: UInt64 = 0

                func writeArchiveChunk(_ chunk: Data) throws {
                    guard !chunk.isEmpty else { return }
                    try Self.throwIfCancelled(cancellationCheck)
                    try archiveHandle.write(contentsOf: chunk)
                    compressedSize = try Self.adding(compressedSize, UInt64(chunk.count))
                    self.archiveByteCount = try Self.adding(
                        self.archiveByteCount,
                        UInt64(chunk.count)
                    )
                }

                func recordSourceChunk(_ chunk: Data) throws {
                    guard !chunk.isEmpty else { return }
                    try Self.throwIfCancelled(cancellationCheck)
                    crc.update(chunk)
                    uncompressedSize = try Self.adding(
                        uncompressedSize,
                        UInt64(chunk.count)
                    )
                }

                switch compressionMethod {
                case .store:
                    try produce { bytes in
                        guard !bytes.isEmpty else { return }
                        if bytes.count <= self.chunkSize {
                            try recordSourceChunk(bytes)
                            try writeArchiveChunk(bytes)
                        } else {
                            var offset = 0
                            while offset < bytes.count {
                                let end = min(offset + self.chunkSize, bytes.count)
                                let chunk = bytes.subdata(in: offset..<end)
                                try recordSourceChunk(chunk)
                                try writeArchiveChunk(chunk)
                                offset = end
                            }
                        }
                    }
                case .deflate:
                    let compressor = try DeflateEncoder(outputBufferSize: chunkSize)
                    try produce { bytes in
                        guard !bytes.isEmpty else { return }

                        func compress(_ chunk: Data) throws {
                            try recordSourceChunk(chunk)
                            try compressor.write(chunk, emit: writeArchiveChunk)
                        }

                        // Current producers already yield at most one chunk. Keep a
                        // defensive split for future oversized producers while each
                        // compressor input and output buffer remains bounded.
                        if bytes.count <= self.chunkSize {
                            try compress(bytes)
                        } else {
                            var offset = 0
                            while offset < bytes.count {
                                let end = min(offset + self.chunkSize, bytes.count)
                                try compress(bytes.subdata(in: offset..<end))
                                offset = end
                            }
                        }
                    }
                    try Self.throwIfCancelled(cancellationCheck)
                    try compressor.finish(emit: writeArchiveChunk)
                }

                // A complete DEFLATE end marker must be durable in the archive
                // spool before the descriptor, central record, or checkpoint can
                // make this entry visible as committed.
                try Self.throwIfCancelled(cancellationCheck)
                let checksum = crc.finalize()
                let descriptor = Self.dataDescriptor(
                    crc32: checksum,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
                try archiveHandle.write(contentsOf: descriptor)
                archiveByteCount = try Self.adding(archiveByteCount, UInt64(descriptor.count))

                let centralRecord = Self.centralDirectoryRecord(
                    nameData: nameData,
                    crc32: checksum,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: startingArchiveByteCount,
                    compressionMethod: compressionMethod,
                    dosDate: dosDate,
                    dosTime: dosTime
                )
                try centralDirectoryHandle.write(contentsOf: centralRecord)
                centralDirectoryByteCount = try Self.adding(
                    centralDirectoryByteCount,
                    UInt64(centralRecord.count)
                )
                entryPaths.append(path)
                entryPathSet.insert(path)
            } catch {
                do {
                    try archiveHandle.truncate(atOffset: startingArchiveByteCount)
                    try archiveHandle.seek(toOffset: startingArchiveByteCount)
                    try centralDirectoryHandle.truncate(atOffset: startingCentralDirectoryByteCount)
                    try centralDirectoryHandle.seek(toOffset: startingCentralDirectoryByteCount)
                    archiveByteCount = startingArchiveByteCount
                    centralDirectoryByteCount = startingCentralDirectoryByteCount
                } catch {
                    abandon()
                }
                if error is CancellationError {
                    abandon()
                }
                throw error
            }
        }

        /// Compression framework's COMPRESSION_ZLIB encoder emits raw RFC 1951
        /// DEFLATE (equivalent to zlib's deflateInit2 windowBits -15), which is
        /// the payload framing required by ZIP compression method 8.
        private final class DeflateEncoder {
            private var stream: compression_stream
            private var outputBuffer: [UInt8]
            private var isInitialized: Bool

            init(outputBufferSize: Int) throws {
                outputBuffer = [UInt8](repeating: 0, count: outputBufferSize)
                isInitialized = false

                // compression_stream_init replaces all user-managed pointers, but
                // Swift imports the C struct fields as non-optional. Supply one
                // valid placeholder for the duration of initialization.
                let placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
                stream = compression_stream(
                    dst_ptr: placeholder,
                    dst_size: 0,
                    src_ptr: UnsafePointer(placeholder),
                    src_size: 0,
                    state: nil
                )
                let status = compression_stream_init(
                    &stream,
                    COMPRESSION_STREAM_ENCODE,
                    COMPRESSION_ZLIB
                )
                placeholder.deallocate()
                guard status == COMPRESSION_STATUS_OK else {
                    throw ArchiveError.compressionFailed
                }
                isInitialized = true
            }

            deinit {
                if isInitialized {
                    _ = compression_stream_destroy(&stream)
                }
            }

            func write(_ data: Data, emit: (Data) throws -> Void) throws {
                guard !data.isEmpty else { return }
                try data.withUnsafeBytes { rawBuffer in
                    let source = rawBuffer.bindMemory(to: UInt8.self)
                    guard let baseAddress = source.baseAddress else {
                        throw ArchiveError.compressionFailed
                    }
                    stream.src_ptr = baseAddress
                    stream.src_size = source.count

                    while stream.src_size > 0 {
                        let sourceSizeBefore = stream.src_size
                        let (status, producedByteCount) = try process(
                            flags: 0,
                            emit: emit
                        )
                        guard status == COMPRESSION_STATUS_OK,
                              stream.src_size < sourceSizeBefore || producedByteCount > 0 else {
                            throw ArchiveError.compressionFailed
                        }
                    }
                }
            }

            func finish(emit: (Data) throws -> Void) throws {
                while true {
                    let (status, producedByteCount) = try process(
                        flags: Int32(COMPRESSION_STREAM_FINALIZE.rawValue),
                        emit: emit
                    )
                    if status == COMPRESSION_STATUS_END { return }
                    guard status == COMPRESSION_STATUS_OK, producedByteCount > 0 else {
                        throw ArchiveError.compressionFailed
                    }
                }
            }

            private func process(
                flags: Int32,
                emit: (Data) throws -> Void
            ) throws -> (compression_status, Int) {
                try outputBuffer.withUnsafeMutableBufferPointer { destination in
                    guard let baseAddress = destination.baseAddress else {
                        throw ArchiveError.compressionFailed
                    }
                    stream.dst_ptr = baseAddress
                    stream.dst_size = destination.count
                    if stream.src_size == 0 {
                        stream.src_ptr = UnsafePointer(baseAddress)
                    }

                    let status = compression_stream_process(&stream, flags)
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw ArchiveError.compressionFailed
                    }
                    let producedByteCount = destination.count - stream.dst_size
                    if producedByteCount > 0 {
                        try emit(Data(bytes: baseAddress, count: producedByteCount))
                    }
                    return (status, producedByteCount)
                }
            }
        }

        private func openHandles() throws -> (FileHandle, FileHandle) {
            guard let archiveHandle, let centralDirectoryHandle else {
                throw ArchiveError.archiveNotOpen
            }
            return (archiveHandle, centralDirectoryHandle)
        }

        private func closeHandles() {
            try? archiveHandle?.close()
            try? centralDirectoryHandle?.close()
            archiveHandle = nil
            centralDirectoryHandle = nil
        }

        private func removeWorkingFiles() {
            try? fileManager.removeItem(at: temporaryArchiveURL)
            try? fileManager.removeItem(at: centralDirectoryURL)
            try? fileManager.removeItem(at: checkpointURL)
        }

        private static func throwIfCancelled(_ cancellationCheck: () -> Bool) throws {
            if cancellationCheck() {
                throw CancellationError()
            }
        }

        private static func adding(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
            let result = lhs.addingReportingOverflow(rhs)
            guard !result.overflow else { throw ArchiveError.integerOverflow }
            return result.partialValue
        }

        private static func localHeader(
            nameData: Data,
            compressionMethod: CompressionMethod,
            dosDate: UInt16,
            dosTime: UInt16
        ) -> Data {
            var header = Data()
            header.reserveCapacity(30 + nameData.count + 20)
            header.appendUInt32LE(0x04034b50)
            header.appendUInt16LE(45) // ZIP 4.5 / ZIP64
            header.appendUInt16LE(0x0808) // UTF-8 + data descriptor
            header.appendUInt16LE(compressionMethod.rawValue)
            header.appendUInt16LE(dosTime)
            header.appendUInt16LE(dosDate)
            header.appendUInt32LE(0) // CRC follows in descriptor
            header.appendUInt32LE(UInt32.max)
            header.appendUInt32LE(UInt32.max)
            header.appendUInt16LE(UInt16(nameData.count))
            header.appendUInt16LE(20) // ZIP64 extra header + two sizes
            header.append(nameData)
            header.appendUInt16LE(0x0001) // ZIP64 extended information
            header.appendUInt16LE(16)
            header.appendUInt64LE(0) // Unknown until descriptor
            header.appendUInt64LE(0)
            return header
        }

        private static func dataDescriptor(
            crc32: UInt32,
            compressedSize: UInt64,
            uncompressedSize: UInt64
        ) -> Data {
            var descriptor = Data()
            descriptor.reserveCapacity(24)
            descriptor.appendUInt32LE(0x08074b50)
            descriptor.appendUInt32LE(crc32)
            descriptor.appendUInt64LE(compressedSize)
            descriptor.appendUInt64LE(uncompressedSize)
            return descriptor
        }

        private static func centralDirectoryRecord(
            nameData: Data,
            crc32: UInt32,
            compressedSize: UInt64,
            uncompressedSize: UInt64,
            localHeaderOffset: UInt64,
            compressionMethod: CompressionMethod,
            dosDate: UInt16,
            dosTime: UInt16
        ) -> Data {
            var record = Data()
            record.reserveCapacity(46 + nameData.count + 28)
            record.appendUInt32LE(0x02014b50)
            record.appendUInt16LE(45)
            record.appendUInt16LE(45)
            record.appendUInt16LE(0x0808)
            record.appendUInt16LE(compressionMethod.rawValue)
            record.appendUInt16LE(dosTime)
            record.appendUInt16LE(dosDate)
            record.appendUInt32LE(crc32)
            record.appendUInt32LE(UInt32.max)
            record.appendUInt32LE(UInt32.max)
            record.appendUInt16LE(UInt16(nameData.count))
            record.appendUInt16LE(28) // ZIP64 header + sizes + offset
            record.appendUInt16LE(0) // Comment length
            record.appendUInt16LE(0) // Disk number start
            record.appendUInt16LE(0) // Internal attributes
            record.appendUInt32LE(0) // External attributes
            record.appendUInt32LE(UInt32.max)
            record.append(nameData)
            record.appendUInt16LE(0x0001)
            record.appendUInt16LE(24)
            record.appendUInt64LE(uncompressedSize)
            record.appendUInt64LE(compressedSize)
            record.appendUInt64LE(localHeaderOffset)
            return record
        }

        private static func endRecords(
            entryCount: UInt64,
            centralDirectorySize: UInt64,
            centralDirectoryOffset: UInt64,
            zip64EndOffset: UInt64
        ) -> Data {
            var records = Data()
            records.reserveCapacity(98)
            records.appendUInt32LE(0x06064b50) // ZIP64 EOCD
            records.appendUInt64LE(44)
            records.appendUInt16LE(45)
            records.appendUInt16LE(45)
            records.appendUInt32LE(0)
            records.appendUInt32LE(0)
            records.appendUInt64LE(entryCount)
            records.appendUInt64LE(entryCount)
            records.appendUInt64LE(centralDirectorySize)
            records.appendUInt64LE(centralDirectoryOffset)

            records.appendUInt32LE(0x07064b50) // ZIP64 EOCD locator
            records.appendUInt32LE(0)
            records.appendUInt64LE(zip64EndOffset)
            records.appendUInt32LE(1)

            records.appendUInt32LE(0x06054b50) // Legacy EOCD sentinels
            records.appendUInt16LE(0)
            records.appendUInt16LE(0)
            records.appendUInt16LE(UInt16.max)
            records.appendUInt16LE(UInt16.max)
            records.appendUInt32LE(UInt32.max)
            records.appendUInt32LE(UInt32.max)
            records.appendUInt16LE(0)
            return records
        }

        private func publishArchive(
            to destinationURL: URL,
            cancellationCheck: () -> Bool
        ) throws {
            try AtomicFileWriter.writeFile(
                to: destinationURL,
                fileManager: fileManager,
                beforeCommit: { try Self.throwIfCancelled(cancellationCheck) }
            ) { publicationURL in
                let input = try FileHandle(forReadingFrom: temporaryArchiveURL)
                let output = try FileHandle(forWritingTo: publicationURL)
                defer {
                    try? input.close()
                    try? output.close()
                }
                var copiedBytes: UInt64 = 0
                while true {
                    try Self.throwIfCancelled(cancellationCheck)
                    guard let bytes = try input.read(upToCount: chunkSize), !bytes.isEmpty else {
                        break
                    }
                    try output.write(contentsOf: bytes)
                    copiedBytes = try Self.adding(copiedBytes, UInt64(bytes.count))
                }
                guard copiedBytes == archiveByteCount else {
                    throw ArchiveError.invalidCheckpoint
                }
                try output.synchronize()
                try output.close()
                try input.close()
            }
        }
    }

    private static func validate(chunkSize: Int) throws {
        guard (1...maximumChunkSize).contains(chunkSize) else {
            throw ArchiveError.invalidChunkSize(chunkSize)
        }
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func validateRecoveryFile(_ url: URL, minimumSize: UInt64, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ArchiveError.missingRecoveryFile(url)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber,
              number.uint64Value >= minimumSize else {
            throw ArchiveError.recoveryFileTooShort(url)
        }
    }

    private static func validatedEntryPath(_ path: String) throws -> String {
        guard !path.isEmpty,
              !path.contains("\0"),
              !path.hasPrefix("/"),
              !path.hasPrefix("\\") else {
            throw ArchiveError.unsafePath(path)
        }

        let slashPath = path.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = slashPath.split(separator: "/", omittingEmptySubsequences: false)
        guard !rawComponents.contains(where: { $0 == ".." }) else {
            throw ArchiveError.unsafePath(path)
        }
        if let first = rawComponents.first,
           first.count >= 2,
           first[first.index(after: first.startIndex)] == ":",
           first.first?.isASCII == true,
           first.first?.isLetter == true {
            throw ArchiveError.unsafePath(path)
        }

        let normalized = normalizedEntryPath(path)
        guard !normalized.isEmpty else {
            throw ArchiveError.unsafePath(path)
        }
        return normalized
    }

    private static func normalizedEntryPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }

    private static func dosTimestampComponents(for date: Date) -> (date: UInt16, time: UInt16) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        return (dosDate, dosTime)
    }
}

nonisolated private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        appendUInt32LE(UInt32(value & 0xffff_ffff))
        appendUInt32LE(UInt32(value >> 32))
    }
}

nonisolated private struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    private var value: UInt32 = 0xffff_ffff

    mutating func update(_ data: Data) {
        for byte in data {
            let index = Int((value ^ UInt32(byte)) & 0xff)
            value = Self.table[index] ^ (value >> 8)
        }
    }

    func finalize() -> UInt32 {
        value ^ 0xffff_ffff
    }
}
