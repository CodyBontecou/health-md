import CryptoKit
import Darwin
import Foundation

/// Final integrity metadata for one exact rendered artifact.
nonisolated struct ExportArtifactDescriptor: Equatable, Sendable {
    let byteCount: UInt64
    let sha256: String
    let mediaType: String
}

nonisolated enum ExportArtifactIOError: Error, Equatable {
    case alreadyFinished
    case notFinished
    case byteCountOverflow
    case invalidChunkSize(Int)
}

/// Synchronous sink used by deterministic exporters. Renderers run this API on
/// a utility task; keeping writes synchronous avoids one suspension per row or
/// canonical value while still bounding memory.
nonisolated protocol ExportByteSink: AnyObject {
    var byteCount: UInt64 { get }
    func write(_ data: Data) throws
    func finish() throws -> ExportArtifactDescriptor
}

/// In-memory compatibility sink for previews, tests, and legacy String/Data APIs.
nonisolated final class MemoryExportByteSink: ExportByteSink, @unchecked Sendable {
    private var storage = Data()
    private var hasher = SHA256()
    private var completedDescriptor: ExportArtifactDescriptor?
    private let mediaType: String

    init(mediaType: String, reservingCapacity capacity: Int = 0) {
        self.mediaType = mediaType
        if capacity > 0 { storage.reserveCapacity(capacity) }
    }

    var byteCount: UInt64 { UInt64(storage.count) }

    var data: Data {
        storage
    }

    func write(_ data: Data) throws {
        try Task.checkCancellation()
        guard completedDescriptor == nil else {
            throw ExportArtifactIOError.alreadyFinished
        }
        storage.append(data)
        hasher.update(data: data)
    }

    func finish() throws -> ExportArtifactDescriptor {
        if let completedDescriptor { return completedDescriptor }
        let descriptor = ExportArtifactDescriptor(
            byteCount: UInt64(storage.count),
            sha256: Self.hexDigest(hasher.finalize()),
            mediaType: mediaType
        )
        completedDescriptor = descriptor
        return descriptor
    }

    private static func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Bounded file sink that hashes exactly the bytes accepted by the file handle.
nonisolated final class FileExportByteSink: ExportByteSink, @unchecked Sendable {
    let fileURL: URL

    private var handle: FileHandle?
    private var hasher = SHA256()
    private var writtenByteCount: UInt64 = 0
    private var completedDescriptor: ExportArtifactDescriptor?
    private let mediaType: String

    init(fileURL: URL, mediaType: String) throws {
        self.fileURL = fileURL
        self.mediaType = mediaType
        let handle = try FileHandle(forWritingTo: fileURL)
        _ = Darwin.fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        self.handle = handle
    }

    deinit {
        try? handle?.close()
    }

    var byteCount: UInt64 { writtenByteCount }

    func write(_ data: Data) throws {
        try Task.checkCancellation()
        guard completedDescriptor == nil, let handle else {
            throw ExportArtifactIOError.alreadyFinished
        }
        let addition = writtenByteCount.addingReportingOverflow(UInt64(data.count))
        guard !addition.overflow else { throw ExportArtifactIOError.byteCountOverflow }
        try handle.write(contentsOf: data)
        hasher.update(data: data)
        writtenByteCount = addition.partialValue
    }

    func finish() throws -> ExportArtifactDescriptor {
        if let completedDescriptor { return completedDescriptor }
        guard let handle else { throw ExportArtifactIOError.alreadyFinished }
        try handle.synchronize()
        try handle.close()
        self.handle = nil
        let descriptor = ExportArtifactDescriptor(
            byteCount: writtenByteCount,
            sha256: Self.hexDigest(hasher.finalize()),
            mediaType: mediaType
        )
        completedDescriptor = descriptor
        return descriptor
    }

    func abandon() {
        try? handle?.close()
        handle = nil
    }

    private static func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Adapter for compatibility APIs that receive an already-configured
/// Foundation OutputStream. The caller retains stream lifecycle ownership.
nonisolated final class OutputStreamExportByteSink: ExportByteSink, @unchecked Sendable {
    private let stream: OutputStream
    private let mediaType: String
    private var hasher = SHA256()
    private var writtenByteCount: UInt64 = 0
    private var completedDescriptor: ExportArtifactDescriptor?

    init(stream: OutputStream, mediaType: String) {
        self.stream = stream
        self.mediaType = mediaType
    }

    var byteCount: UInt64 { writtenByteCount }

    func write(_ data: Data) throws {
        try Task.checkCancellation()
        guard completedDescriptor == nil else {
            throw ExportArtifactIOError.alreadyFinished
        }
        let addition = writtenByteCount.addingReportingOverflow(UInt64(data.count))
        guard !addition.overflow else { throw ExportArtifactIOError.byteCountOverflow }
        var offset = 0
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            while offset < data.count {
                let count = stream.write(
                    baseAddress.advanced(by: offset),
                    maxLength: data.count - offset
                )
                guard count > 0 else {
                    throw stream.streamError ?? CocoaError(.fileWriteUnknown)
                }
                offset += count
            }
        }
        hasher.update(data: data)
        writtenByteCount = addition.partialValue
    }

    func finish() throws -> ExportArtifactDescriptor {
        if let completedDescriptor { return completedDescriptor }
        let descriptor = ExportArtifactDescriptor(
            byteCount: writtenByteCount,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            mediaType: mediaType
        )
        completedDescriptor = descriptor
        return descriptor
    }
}

/// Reference ownership prevents copied artifact values from deleting a shared
/// temporary file prematurely.
nonisolated final class RestrictedArtifactFileLease: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var removesFileOnDeinit: Bool
    private let removesParentDirectoryIfEmpty: Bool

    init(
        url: URL,
        removesFileOnDeinit: Bool = true,
        removesParentDirectoryIfEmpty: Bool = false
    ) {
        self.url = url
        self.removesFileOnDeinit = removesFileOnDeinit
        self.removesParentDirectoryIfEmpty = removesParentDirectoryIfEmpty
    }

    deinit {
        lock.lock()
        let shouldRemove = removesFileOnDeinit
        removesFileOnDeinit = false
        lock.unlock()
        if shouldRemove {
            try? FileManager.default.removeItem(at: url)
            if removesParentDirectoryIfEmpty {
                url.deletingLastPathComponent().withUnsafeFileSystemRepresentation {
                    if let path = $0 { _ = Darwin.rmdir(path) }
                }
            }
        }
    }

    func relinquishCleanupOwnership() {
        lock.lock()
        removesFileOnDeinit = false
        lock.unlock()
    }
}

/// Immutable exact file produced by a completed exporter.
nonisolated struct ExportArtifactFile: Equatable, Sendable {
    let descriptor: ExportArtifactDescriptor
    let lease: RestrictedArtifactFileLease

    var url: URL { lease.url }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.descriptor == rhs.descriptor
    }

    func forEachChunk(
        chunkSize: Int = ExportArtifactIO.defaultBufferSize,
        _ consume: (Data) throws -> Void
    ) throws {
        guard chunkSize > 0 else {
            throw ExportArtifactIOError.invalidChunkSize(chunkSize)
        }
        try ExportArtifactIO.forEachFileChunk(
            at: url,
            expectedByteCount: descriptor.byteCount,
            chunkSize: chunkSize,
            consume
        )
    }

    func materializedData() throws -> Data {
        guard descriptor.byteCount <= UInt64(Int.max) else {
            throw CocoaError(.fileReadTooLarge)
        }
        var data = Data()
        data.reserveCapacity(Int(descriptor.byteCount))
        try forEachChunk { data.append($0) }
        return data
    }
}

/// Shared file transaction helpers for loose files, ZIP staging, API envelopes,
/// connected transfer, and direct-file generation.
nonisolated enum ExportArtifactIO {
    static let defaultBufferSize = 128 * 1_024

    /// Reads through one reusable POSIX buffer and passes independently owned
    /// bounded chunks. Avoiding FileHandle's autoreleased reads prevents memory
    /// growth with the source file while allowing consumers to retain a chunk.
    static func forEachFileChunk(
        at url: URL,
        expectedByteCount: UInt64,
        chunkSize: Int = defaultBufferSize,
        _ consume: (Data) throws -> Void
    ) throws {
        guard chunkSize > 0 else {
            throw ExportArtifactIOError.invalidChunkSize(chunkSize)
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: chunkSize,
            alignment: MemoryLayout<UInt64>.alignment
        )
        defer { buffer.deallocate() }
        var total: UInt64 = 0
        while true {
            try Task.checkCancellation()
            var count: Int
            repeat {
                count = Darwin.read(descriptor, buffer, chunkSize)
            } while count < 0 && errno == EINTR
            guard count >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            let addition = total.addingReportingOverflow(UInt64(count))
            guard !addition.overflow else { throw ExportArtifactIOError.byteCountOverflow }
            let chunk = Data(bytes: buffer, count: count)
            try consume(chunk)
            total = addition.partialValue
        }
        guard total == expectedByteCount else { throw CocoaError(.fileReadCorruptFile) }
    }

    static func renderTemporary(
        in directoryURL: URL = FileManager.default.temporaryDirectory,
        prefix: String,
        mediaType: String,
        fileManager: FileManager = .default,
        render: (ExportByteSink) throws -> Void
    ) throws -> ExportArtifactFile {
        let directoryAlreadyExists = fileManager.fileExists(atPath: directoryURL.path)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !directoryAlreadyExists {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
        }
        let fileURL = directoryURL.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        guard fileManager.createFile(
            atPath: fileURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let sink = try FileExportByteSink(fileURL: fileURL, mediaType: mediaType)
        do {
            try render(sink)
            let descriptor = try sink.finish()
            return ExportArtifactFile(
                descriptor: descriptor,
                lease: RestrictedArtifactFileLease(
                    url: fileURL,
                    removesParentDirectoryIfEmpty: directoryURL.standardizedFileURL
                        != FileManager.default.temporaryDirectory.standardizedFileURL
                )
            )
        } catch {
            sink.abandon()
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    @discardableResult
    static func renderAtomically(
        to destinationURL: URL,
        mediaType: String,
        fileManager: FileManager = .default,
        attributes: [FileAttributeKey: Any]? = [.posixPermissions: 0o600],
        render: (ExportByteSink) throws -> Void
    ) throws -> ExportArtifactDescriptor {
        try AtomicFileWriter.writeFile(
            to: destinationURL,
            fileManager: fileManager,
            attributes: attributes,
            beforeCommit: { try Task.checkCancellation() }
        ) { temporaryURL in
            let sink = try FileExportByteSink(fileURL: temporaryURL, mediaType: mediaType)
            do {
                try render(sink)
                return try sink.finish()
            } catch {
                sink.abandon()
                throw error
            }
        }
    }
}

/// Coalesces small scalar writes while allowing already-bounded chunks to pass
/// directly to the destination without another full-size copy.
nonisolated final class BufferedExportByteWriter {
    private let sink: ExportByteSink
    private let capacity: Int
    private var buffer: Data

    init(
        sink: ExportByteSink,
        capacity: Int = ExportArtifactIO.defaultBufferSize
    ) throws {
        guard capacity > 0 else { throw ExportArtifactIOError.invalidChunkSize(capacity) }
        self.sink = sink
        self.capacity = capacity
        self.buffer = Data()
        self.buffer.reserveCapacity(capacity)
    }

    func append(byte: UInt8) throws {
        buffer.append(byte)
        if buffer.count >= capacity { try flush() }
    }

    func append(_ string: String) throws {
        try append(Data(string.utf8))
    }

    func append(_ data: Data) throws {
        guard !data.isEmpty else { return }
        if data.count >= capacity {
            try flush()
            try sink.write(data)
            return
        }
        if buffer.count + data.count > capacity { try flush() }
        buffer.append(data)
    }

    func flush() throws {
        guard !buffer.isEmpty else { return }
        try sink.write(buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
