import Darwin
import XCTest
@testable import HealthMd

final class ZipArchiveWriterTests: XCTestCase {
    func testStreamsDataAndFileEntriesIntoReadableZIP64Archive() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.bin")
        let sourceBytes = Data((0..<20_000).map { UInt8($0 % 251) })
        try sourceBytes.write(to: sourceURL)
        let destinationURL = directory.appendingPathComponent("export.zip")
        try Data("old archive".utf8).write(to: destinationURL)

        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: directory.appendingPathComponent("stream.checkpoint"),
            chunkSize: 17
        )
        try writer.append(path: "notes/today.md", data: Data("hello health".utf8))
        try writer.appendFile(at: sourceURL, path: "records/source.bin")
        try writer.finish()

        let archive = try Data(contentsOf: destinationURL)
        let entries = try ZIP64TestReader.entries(in: archive)
        XCTAssertEqual(entries["notes/today.md"], Data("hello health".utf8))
        XCTAssertEqual(entries["records/source.bin"], sourceBytes)
        XCTAssertEqual(try ZIP64TestReader.entryCount(in: archive), 2)
        XCTAssertTrue(archive.containsSignature([0x50, 0x4b, 0x06, 0x06]))
        XCTAssertTrue(archive.containsSignature([0x50, 0x4b, 0x06, 0x07]))

        let legacyEndOffset = archive.count - 22
        XCTAssertEqual(archive.uint16LE(at: legacyEndOffset + 8), UInt16.max)
        XCTAssertEqual(archive.uint32LE(at: legacyEndOffset + 12), UInt32.max)
    }

    func testSecurePublicationStreamsLargeFileSourceInBoundedChunks() throws {
        let root = try temporaryDirectory()
        let work = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        let sourceURL = work.appendingPathComponent("large-source.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: nil))
        let sourceHandle = try FileHandle(forWritingTo: sourceURL)
        let sourceChunk = Data(repeating: 0xa5, count: 64 * 1024)
        for _ in 0..<256 { try sourceHandle.write(contentsOf: sourceChunk) }
        try sourceHandle.close()

        let destinationURL = root.appendingPathComponent("Health/export.zip")
        let coordinator = RecordingFileCoordinator()
        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: work.appendingPathComponent("large.checkpoint"),
            workingDirectoryURL: work,
            fileCoordinator: coordinator,
            chunkSize: 32 * 1024,
            securePublication: .init(
                rootURL: root,
                relativePath: "Health/export.zip",
                binding: try destinationBinding(for: root)
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationURL.deletingLastPathComponent().path),
            "Bound ZIP setup must not create the destination parent through its pathname"
        )
        try writer.appendFile(at: sourceURL, path: "records/large-source.bin")
        try writer.finish()

        XCTAssertGreaterThan(fileSize(destinationURL), fileSize(sourceURL))
        XCTAssertEqual(coordinator.calls, [.init(url: destinationURL, intent: .replace)])
    }

    func testZIP64EntryCountExceedsLegacyLimit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("many.zip")
        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: directory.appendingPathComponent("many.checkpoint")
        )

        for index in 0...Int(UInt16.max) {
            try writer.append(path: "empty/\(index)", data: Data())
        }
        try writer.finish()

        let archive = try Data(contentsOf: destinationURL)
        XCTAssertEqual(try ZIP64TestReader.entryCount(in: archive), UInt64(UInt16.max) + 1)
        let legacyEndOffset = archive.count - 22
        XCTAssertEqual(archive.uint16LE(at: legacyEndOffset + 8), UInt16.max)
    }

    func testRejectsUnsafeAndDuplicateNormalizedPaths() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = try ZipArchiveWriter.begin(
            to: directory.appendingPathComponent("export.zip"),
            checkpointURL: directory.appendingPathComponent("stream.checkpoint")
        )
        defer { writer.abandon() }

        try writer.append(path: "folder//./note.md", data: Data())
        XCTAssertThrowsError(try writer.append(path: "folder/note.md", data: Data())) { error in
            XCTAssertEqual(error as? ZipArchiveWriter.ArchiveError, .duplicatePath("folder/note.md"))
        }

        for unsafePath in ["", "../secret", "safe/../secret", "/absolute", "\\server\\share", "C:\\secret"] {
            XCTAssertThrowsError(try writer.append(path: unsafePath, data: Data()), unsafePath) { error in
                guard case .unsafePath = error as? ZipArchiveWriter.ArchiveError else {
                    return XCTFail("Expected unsafePath for \(unsafePath), got \(error)")
                }
            }
        }
    }

    func testCheckpointRecoveryTruncatesPartialWorkAndContinues() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("export.zip")
        let checkpointURL = directory.appendingPathComponent("partition.checkpoint")

        let firstWriter = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: checkpointURL,
            chunkSize: 11
        )
        try firstWriter.append(path: "part-1.json", data: Data("first".utf8))
        let checkpoint = try firstWriter.suspend()

        try appendGarbage(to: checkpoint.temporaryArchiveURL)
        try appendGarbage(to: checkpoint.centralDirectoryURL)
        XCTAssertGreaterThan(fileSize(checkpoint.temporaryArchiveURL), checkpoint.archiveByteCount)
        XCTAssertGreaterThan(fileSize(checkpoint.centralDirectoryURL), checkpoint.centralDirectoryByteCount)

        let recovered = try ZipArchiveWriter.recover(from: checkpointURL)
        XCTAssertEqual(fileSize(checkpoint.temporaryArchiveURL), checkpoint.archiveByteCount)
        XCTAssertEqual(fileSize(checkpoint.centralDirectoryURL), checkpoint.centralDirectoryByteCount)
        XCTAssertEqual(recovered.writtenEntryCount, 1)
        try recovered.append(path: "part-2.json", data: Data("second".utf8))
        try recovered.finish()

        let entries = try ZIP64TestReader.entries(in: Data(contentsOf: destinationURL))
        XCTAssertEqual(entries["part-1.json"], Data("first".utf8))
        XCTAssertEqual(entries["part-2.json"], Data("second".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.centralDirectoryURL.path))
    }

    func testRecoveryRejectsCheckpointWorkFileOutsideProtectedDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workDirectory = directory.appendingPathComponent("private-work", isDirectory: true)
        let destinationURL = directory.appendingPathComponent("export.zip")
        let checkpointURL = workDirectory.appendingPathComponent("checkpoint.json")
        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: checkpointURL,
            workingDirectoryURL: workDirectory
        )
        try writer.append(path: "safe.json", data: Data("safe".utf8))
        _ = try writer.suspend()

        let victimURL = directory.appendingPathComponent("victim.txt")
        let victim = Data("must not be truncated".utf8)
        try victim.write(to: victimURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: checkpointURL)) as? [String: Any]
        )
        object["temporaryArchiveURL"] = victimURL.absoluteString
        try JSONSerialization.data(withJSONObject: object).write(to: checkpointURL, options: .atomic)

        XCTAssertThrowsError(try ZipArchiveWriter.recover(from: checkpointURL))
        XCTAssertEqual(try Data(contentsOf: victimURL), victim)
    }

    func testFinishCoordinatesOnlyFinalDestinationPublication() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("coordinated.zip")
        let coordinator = RecordingFileCoordinator()
        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: directory.appendingPathComponent("coordinated.checkpoint"),
            fileCoordinator: coordinator
        )
        try writer.append(path: "entry.json", data: Data("{}".utf8))
        XCTAssertTrue(coordinator.calls.isEmpty)

        try writer.finish()

        XCTAssertEqual(
            coordinator.calls,
            [.init(url: destinationURL, intent: .replace)]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testFinishCoordinationFailurePreservesExistingDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("existing.zip")
        let original = Data("existing archive".utf8)
        try original.write(to: destinationURL)
        let coordinator = RecordingFileCoordinator()
        coordinator.injectedError = CocoaError(.fileWriteNoPermission)
        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: directory.appendingPathComponent("denied.checkpoint"),
            fileCoordinator: coordinator
        )
        try writer.append(path: "entry.json", data: Data("{}".utf8))

        XCTAssertThrowsError(try writer.finish())

        XCTAssertEqual(try Data(contentsOf: destinationURL), original)
        XCTAssertEqual(coordinator.calls.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: writer.temporaryArchiveURL.path))
    }

    func testCancellationRemovesWorkFilesAndPreservesExistingDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("export.zip")
        let original = Data("existing archive".utf8)
        try original.write(to: destinationURL)

        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: directory.appendingPathComponent("stream.checkpoint"),
            chunkSize: 8
        )
        let temporaryArchiveURL = writer.temporaryArchiveURL
        let centralDirectoryURL = writer.centralDirectoryURL
        let checkpointURL = writer.checkpointURL
        var checks = 0

        XCTAssertThrowsError(
            try writer.append(
                path: "large.bin",
                data: Data(repeating: 0xaa, count: 1_024),
                cancellationCheck: {
                    checks += 1
                    return checks > 3
                }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryArchiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: centralDirectoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipArchiveWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func destinationBinding(for root: URL) throws -> AppleVaultDestinationBinding {
        guard let pointer = Darwin.realpath(root.standardizedFileURL.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.free(pointer) }
        let resolvedPath = String(cString: pointer)
        var metadata = stat()
        guard Darwin.lstat(resolvedPath, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return AppleVaultDestinationBinding(
            standardizedPath: root.standardizedFileURL.path,
            resolvedPath: resolvedPath,
            deviceID: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino)
        )
    }

    private func appendGarbage(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0xee, count: 31))
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}

private enum ZIP64TestReader {
    enum ReaderError: Error {
        case malformedArchive
    }

    static func entryCount(in archive: Data) throws -> UInt64 {
        let endOffset = try zip64EndOffset(in: archive)
        return archive.uint64LE(at: endOffset + 32)
    }

    static func entries(in archive: Data) throws -> [String: Data] {
        let endOffset = try zip64EndOffset(in: archive)
        let count = archive.uint64LE(at: endOffset + 32)
        let centralOffsetValue = archive.uint64LE(at: endOffset + 48)
        guard count <= UInt64(Int.max), centralOffsetValue <= UInt64(Int.max) else {
            throw ReaderError.malformedArchive
        }

        var result: [String: Data] = [:]
        var centralOffset = Int(centralOffsetValue)
        for _ in 0..<Int(count) {
            guard archive.uint32LE(at: centralOffset) == 0x02014b50 else {
                throw ReaderError.malformedArchive
            }
            let expectedCRC = archive.uint32LE(at: centralOffset + 16)
            let nameLength = Int(archive.uint16LE(at: centralOffset + 28))
            let extraLength = Int(archive.uint16LE(at: centralOffset + 30))
            let commentLength = Int(archive.uint16LE(at: centralOffset + 32))
            let nameStart = centralOffset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= archive.count,
                  let name = String(data: archive[nameStart..<nameEnd], encoding: .utf8) else {
                throw ReaderError.malformedArchive
            }

            let extraOffset = nameEnd
            guard archive.uint16LE(at: extraOffset) == 0x0001,
                  archive.uint16LE(at: extraOffset + 2) >= 24 else {
                throw ReaderError.malformedArchive
            }
            let sizeValue = archive.uint64LE(at: extraOffset + 4)
            let localOffsetValue = archive.uint64LE(at: extraOffset + 20)
            guard sizeValue <= UInt64(Int.max), localOffsetValue <= UInt64(Int.max) else {
                throw ReaderError.malformedArchive
            }

            let localOffset = Int(localOffsetValue)
            guard archive.uint32LE(at: localOffset) == 0x04034b50 else {
                throw ReaderError.malformedArchive
            }
            let localNameLength = Int(archive.uint16LE(at: localOffset + 26))
            let localExtraLength = Int(archive.uint16LE(at: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            let dataEnd = dataStart + Int(sizeValue)
            guard dataEnd <= archive.count else { throw ReaderError.malformedArchive }
            let bytes = Data(archive[dataStart..<dataEnd])
            guard crc32(bytes) == expectedCRC else { throw ReaderError.malformedArchive }
            result[name] = bytes

            centralOffset = nameEnd + extraLength + commentLength
        }
        return result
    }

    private static func zip64EndOffset(in archive: Data) throws -> Int {
        let signature = Data([0x50, 0x4b, 0x06, 0x06])
        guard let range = archive.range(of: signature, options: .backwards) else {
            throw ReaderError.malformedArchive
        }
        return range.lowerBound
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffff_ffff
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xedb88320 ^ (value >> 1)) : (value >> 1)
            }
        }
        return value ^ 0xffff_ffff
    }
}

private extension Data {
    func containsSignature(_ bytes: [UInt8]) -> Bool {
        range(of: Data(bytes)) != nil
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    func uint64LE(at offset: Int) -> UInt64 {
        UInt64(uint32LE(at: offset)) | (UInt64(uint32LE(at: offset + 4)) << 32)
    }
}
