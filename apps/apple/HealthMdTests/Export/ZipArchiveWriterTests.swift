import Compression
import Darwin
import XCTest
@testable import HealthMd

final class ZipArchiveWriterTests: XCTestCase {
    func testStreamsDeflatedDataAndFileEntriesIntoReadableZIP64Archive() throws {
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
        let noteBytes = Data("hello health".utf8)
        try writer.append(path: "notes/今日.md", data: noteBytes)
        try writer.appendFile(at: sourceURL, path: "records/source.bin")
        try writer.finish()

        let archive = try Data(contentsOf: destinationURL)
        let entries = try ZIP64TestReader.entries(in: archive)
        let note = try XCTUnwrap(entries["notes/今日.md"])
        XCTAssertEqual(note.data, noteBytes)
        XCTAssertEqual(note.method, 8)
        XCTAssertEqual(note.uncompressedSize, UInt64(noteBytes.count))
        XCTAssertEqual(note.crc32, ZIP64TestReader.crc32(noteBytes))
        let source = try XCTUnwrap(entries["records/source.bin"])
        XCTAssertEqual(source.data, sourceBytes)
        XCTAssertEqual(source.method, 8)
        XCTAssertEqual(source.uncompressedSize, UInt64(sourceBytes.count))
        XCTAssertLessThan(source.compressedSize, source.uncompressedSize)
        XCTAssertEqual(source.crc32, ZIP64TestReader.crc32(sourceBytes))
        XCTAssertEqual(try ZIP64TestReader.entryCount(in: archive), 2)
        XCTAssertTrue(archive.containsSignature([0x50, 0x4b, 0x06, 0x06]))
        XCTAssertTrue(archive.containsSignature([0x50, 0x4b, 0x06, 0x07]))

        let legacyEndOffset = archive.count - 22
        XCTAssertEqual(archive.uint16LE(at: legacyEndOffset + 8), UInt16.max)
        XCTAssertEqual(archive.uint32LE(at: legacyEndOffset + 12), UInt32.max)

        #if os(macOS)
        try assertSystemUnzipCanRead(destinationURL)
        #endif
    }

    func testDeflatesEmptyTinyAndIncompressibleEntriesWithExactMetadata() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("edge-cases.zip")
        let writer = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: directory.appendingPathComponent("edge-cases.checkpoint"),
            chunkSize: 7
        )
        let empty = Data()
        let tiny = Data("x".utf8)
        let incompressible = deterministicIncompressibleBytes(count: 32 * 1_024)

        try writer.append(path: "empty.json", data: empty)
        try writer.append(path: "tiny.md", data: tiny)
        try writer.append(path: "random.csv", data: incompressible)
        try writer.finish()

        let entries = try ZIP64TestReader.entries(in: Data(contentsOf: destinationURL))
        let emptyEntry = try XCTUnwrap(entries["empty.json"])
        XCTAssertEqual(emptyEntry.method, 8)
        XCTAssertEqual(emptyEntry.data, empty)
        XCTAssertEqual(emptyEntry.uncompressedSize, 0)
        XCTAssertGreaterThan(emptyEntry.compressedSize, 0)
        XCTAssertEqual(emptyEntry.crc32, 0)

        let tinyEntry = try XCTUnwrap(entries["tiny.md"])
        XCTAssertEqual(tinyEntry.method, 8)
        XCTAssertEqual(tinyEntry.data, tiny)
        XCTAssertEqual(tinyEntry.uncompressedSize, UInt64(tiny.count))
        XCTAssertGreaterThan(tinyEntry.compressedSize, tinyEntry.uncompressedSize)
        XCTAssertEqual(tinyEntry.crc32, ZIP64TestReader.crc32(tiny))

        let incompressibleEntry = try XCTUnwrap(entries["random.csv"])
        XCTAssertEqual(incompressibleEntry.method, 8)
        XCTAssertEqual(incompressibleEntry.data, incompressible)
        XCTAssertEqual(incompressibleEntry.uncompressedSize, UInt64(incompressible.count))
        XCTAssertGreaterThan(
            incompressibleEntry.compressedSize,
            incompressibleEntry.uncompressedSize,
            "Always-DEFLATE avoids staging or replay solely to store an incompressible entry"
        )
        XCTAssertEqual(incompressibleEntry.crc32, ZIP64TestReader.crc32(incompressible))

        #if os(macOS)
        try assertSystemUnzipCanRead(destinationURL)
        #endif
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
        for _ in 0..<128 { try sourceHandle.write(contentsOf: sourceChunk) }
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

        let archive = try Data(contentsOf: destinationURL)
        let entry = try XCTUnwrap(
            ZIP64TestReader.entries(in: archive)["records/large-source.bin"]
        )
        XCTAssertEqual(entry.method, 8)
        XCTAssertEqual(UInt64(entry.data.count), fileSize(sourceURL))
        XCTAssertTrue(entry.data.allSatisfy { $0 == 0xa5 })
        XCTAssertEqual(entry.uncompressedSize, fileSize(sourceURL))
        XCTAssertLessThan(entry.compressedSize, entry.uncompressedSize)
        XCTAssertLessThan(fileSize(destinationURL), fileSize(sourceURL))
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

    func testCheckpointRecoveryTruncatesPartialCompressedOutputAndContinues() throws {
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

        try appendPartialDeflatedEntry(to: checkpoint.temporaryArchiveURL)
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
        let first = try XCTUnwrap(entries["part-1.json"])
        let second = try XCTUnwrap(entries["part-2.json"])
        XCTAssertEqual(first.data, Data("first".utf8))
        XCTAssertEqual(second.data, Data("second".utf8))
        XCTAssertEqual(first.method, 8)
        XCTAssertEqual(second.method, 8)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.centralDirectoryURL.path))
    }

    func testRecoversLegacyStoreCheckpointAndMigratesItsCompressionPolicy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationURL = directory.appendingPathComponent("legacy.zip")
        let checkpointURL = directory.appendingPathComponent("legacy.checkpoint")
        let legacyWriter = try ZipArchiveWriter.begin(
            to: destinationURL,
            checkpointURL: checkpointURL,
            chunkSize: 9,
            compressionMethod: .store
        )
        try legacyWriter.append(path: "old.json", data: Data("old".utf8))
        _ = try legacyWriter.suspend()

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: checkpointURL)) as? [String: Any]
        )
        legacyObject["formatVersion"] = 1
        legacyObject.removeValue(forKey: "compressionMethod")
        try JSONSerialization.data(withJSONObject: legacyObject).write(
            to: checkpointURL,
            options: .atomic
        )

        let recovered = try ZipArchiveWriter.recover(from: checkpointURL)
        try recovered.append(path: "new.json", data: Data("new".utf8))
        _ = try recovered.checkpoint()

        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: checkpointURL)) as? [String: Any]
        )
        XCTAssertEqual((migratedObject["formatVersion"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((migratedObject["compressionMethod"] as? NSNumber)?.uint16Value, 0)
        try recovered.finish()

        let entries = try ZIP64TestReader.entries(in: Data(contentsOf: destinationURL))
        let old = try XCTUnwrap(entries["old.json"])
        let new = try XCTUnwrap(entries["new.json"])
        XCTAssertEqual(old.data, Data("old".utf8))
        XCTAssertEqual(new.data, Data("new".utf8))
        XCTAssertEqual(old.method, 0)
        XCTAssertEqual(new.method, 0)
        XCTAssertEqual(old.compressedSize, old.uncompressedSize)
        XCTAssertEqual(new.compressedSize, new.uncompressedSize)
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

    private func appendPartialDeflatedEntry(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var partialEntry = Data([
            0x50, 0x4b, 0x03, 0x04, // Local header
            0x2d, 0x00,             // ZIP64 version
            0x08, 0x08,             // UTF-8 + descriptor
            0x08, 0x00              // DEFLATE method
        ])
        partialEntry.append(Data(repeating: 0, count: 20))
        partialEntry.append(Data([0xcb, 0x48, 0xcd])) // Incomplete raw-DEFLATE output
        try handle.write(contentsOf: partialEntry)
    }

    private func appendGarbage(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0xee, count: 31))
    }

    private func deterministicIncompressibleBytes(count: Int) -> Data {
        var state: UInt64 = 0x9e37_79b9_7f4a_7c15
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0..<count {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            bytes.append(UInt8(truncatingIfNeeded: state >> 24))
        }
        return Data(bytes)
    }

    #if os(macOS)
    private func assertSystemUnzipCanRead(_ archiveURL: URL) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", archiveURL.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let diagnostic = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(data: diagnostic, encoding: .utf8) ?? "unzip failed"
        )
    }
    #endif

    private func fileSize(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}

private enum ZIP64TestReader {
    struct Entry: Equatable {
        let method: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let crc32: UInt32
        let data: Data
    }

    enum ReaderError: Error {
        case malformedArchive
        case unsupportedCompressionMethod(UInt16)
    }

    static func entryCount(in archive: Data) throws -> UInt64 {
        let endOffset = try zip64EndOffset(in: archive)
        guard endOffset + 56 <= archive.count else { throw ReaderError.malformedArchive }
        return archive.uint64LE(at: endOffset + 32)
    }

    static func entries(in archive: Data) throws -> [String: Entry] {
        let endOffset = try zip64EndOffset(in: archive)
        guard endOffset + 56 <= archive.count else { throw ReaderError.malformedArchive }
        let count = archive.uint64LE(at: endOffset + 32)
        let centralOffsetValue = archive.uint64LE(at: endOffset + 48)
        guard count <= UInt64(Int.max), centralOffsetValue <= UInt64(Int.max) else {
            throw ReaderError.malformedArchive
        }

        var result: [String: Entry] = [:]
        var centralOffset = Int(centralOffsetValue)
        for _ in 0..<Int(count) {
            guard centralOffset <= archive.count - 46,
                  archive.uint32LE(at: centralOffset) == 0x02014b50,
                  archive.uint16LE(at: centralOffset + 8) == 0x0808,
                  archive.uint32LE(at: centralOffset + 20) == UInt32.max,
                  archive.uint32LE(at: centralOffset + 24) == UInt32.max,
                  archive.uint32LE(at: centralOffset + 42) == UInt32.max else {
                throw ReaderError.malformedArchive
            }
            let method = archive.uint16LE(at: centralOffset + 10)
            let expectedCRC = archive.uint32LE(at: centralOffset + 16)
            let nameLength = Int(archive.uint16LE(at: centralOffset + 28))
            let extraLength = Int(archive.uint16LE(at: centralOffset + 30))
            let commentLength = Int(archive.uint16LE(at: centralOffset + 32))
            let nameStart = centralOffset + 46
            let nameEnd = nameStart + nameLength
            let extraOffset = nameEnd
            guard nameEnd <= archive.count,
                  extraLength >= 28,
                  extraOffset <= archive.count - 28,
                  let name = String(data: archive[nameStart..<nameEnd], encoding: .utf8),
                  result[name] == nil,
                  archive.uint16LE(at: extraOffset) == 0x0001,
                  archive.uint16LE(at: extraOffset + 2) >= 24 else {
                throw ReaderError.malformedArchive
            }
            let uncompressedSizeValue = archive.uint64LE(at: extraOffset + 4)
            let compressedSizeValue = archive.uint64LE(at: extraOffset + 12)
            let localOffsetValue = archive.uint64LE(at: extraOffset + 20)
            guard uncompressedSizeValue <= UInt64(Int.max),
                  compressedSizeValue <= UInt64(Int.max),
                  localOffsetValue <= UInt64(Int.max) else {
                throw ReaderError.malformedArchive
            }

            let localOffset = Int(localOffsetValue)
            guard localOffset <= archive.count - 30,
                  archive.uint32LE(at: localOffset) == 0x04034b50,
                  archive.uint16LE(at: localOffset + 6) == 0x0808,
                  archive.uint16LE(at: localOffset + 8) == method,
                  archive.uint32LE(at: localOffset + 18) == UInt32.max,
                  archive.uint32LE(at: localOffset + 22) == UInt32.max else {
                throw ReaderError.malformedArchive
            }
            let localNameLength = Int(archive.uint16LE(at: localOffset + 26))
            let localExtraLength = Int(archive.uint16LE(at: localOffset + 28))
            let localNameStart = localOffset + 30
            let localNameEnd = localNameStart + localNameLength
            let localExtraOffset = localNameEnd
            let dataStart = localExtraOffset + localExtraLength
            let dataEnd = dataStart + Int(compressedSizeValue)
            let descriptorEnd = dataEnd + 24
            guard localNameEnd <= archive.count,
                  Data(archive[localNameStart..<localNameEnd]) == Data(name.utf8),
                  localExtraLength >= 20,
                  localExtraOffset <= archive.count - 20,
                  archive.uint16LE(at: localExtraOffset) == 0x0001,
                  archive.uint16LE(at: localExtraOffset + 2) >= 16,
                  archive.uint64LE(at: localExtraOffset + 4) == 0,
                  archive.uint64LE(at: localExtraOffset + 12) == 0,
                  descriptorEnd <= archive.count,
                  archive.uint32LE(at: dataEnd) == 0x08074b50,
                  archive.uint32LE(at: dataEnd + 4) == expectedCRC,
                  archive.uint64LE(at: dataEnd + 8) == compressedSizeValue,
                  archive.uint64LE(at: dataEnd + 16) == uncompressedSizeValue else {
                throw ReaderError.malformedArchive
            }

            let compressedBytes = Data(archive[dataStart..<dataEnd])
            let bytes: Data
            switch method {
            case 0:
                guard compressedSizeValue == uncompressedSizeValue else {
                    throw ReaderError.malformedArchive
                }
                bytes = compressedBytes
            case 8:
                bytes = try inflateRawDeflate(
                    compressedBytes,
                    expectedByteCount: Int(uncompressedSizeValue)
                )
            default:
                throw ReaderError.unsupportedCompressionMethod(method)
            }
            guard bytes.count == Int(uncompressedSizeValue),
                  crc32(bytes) == expectedCRC else {
                throw ReaderError.malformedArchive
            }
            result[name] = Entry(
                method: method,
                compressedSize: compressedSizeValue,
                uncompressedSize: uncompressedSizeValue,
                crc32: expectedCRC,
                data: bytes
            )

            centralOffset = nameEnd + extraLength + commentLength
        }
        return result
    }

    static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffff_ffff
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xedb88320 ^ (value >> 1)) : (value >> 1)
            }
        }
        return value ^ 0xffff_ffff
    }

    private static func inflateRawDeflate(
        _ compressedData: Data,
        expectedByteCount: Int
    ) throws -> Data {
        guard !compressedData.isEmpty else { throw ReaderError.malformedArchive }
        let placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        var stream = compression_stream(
            dst_ptr: placeholder,
            dst_size: 0,
            src_ptr: UnsafePointer(placeholder),
            src_size: 0,
            state: nil
        )
        let initializationStatus = compression_stream_init(
            &stream,
            COMPRESSION_STREAM_DECODE,
            COMPRESSION_ZLIB
        )
        placeholder.deallocate()
        guard initializationStatus == COMPRESSION_STATUS_OK else {
            throw ReaderError.malformedArchive
        }
        defer { _ = compression_stream_destroy(&stream) }

        var output = Data()
        output.reserveCapacity(expectedByteCount)
        var outputBuffer = [UInt8](
            repeating: 0,
            count: max(1, min(64 * 1_024, max(expectedByteCount, 1)))
        )
        return try compressedData.withUnsafeBytes { rawSource in
            let source = rawSource.bindMemory(to: UInt8.self)
            guard let sourceAddress = source.baseAddress else {
                throw ReaderError.malformedArchive
            }
            stream.src_ptr = sourceAddress
            stream.src_size = source.count

            while true {
                let sourceSizeBefore = stream.src_size
                var status = COMPRESSION_STATUS_ERROR
                var producedByteCount = 0
                try outputBuffer.withUnsafeMutableBufferPointer { destination in
                    guard let destinationAddress = destination.baseAddress else {
                        throw ReaderError.malformedArchive
                    }
                    stream.dst_ptr = destinationAddress
                    stream.dst_size = destination.count
                    status = compression_stream_process(
                        &stream,
                        Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    )
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw ReaderError.malformedArchive
                    }
                    producedByteCount = destination.count - stream.dst_size
                    guard output.count <= expectedByteCount - producedByteCount else {
                        throw ReaderError.malformedArchive
                    }
                    if producedByteCount > 0 {
                        output.append(destinationAddress, count: producedByteCount)
                    }
                }

                if status == COMPRESSION_STATUS_END {
                    guard stream.src_size == 0, output.count == expectedByteCount else {
                        throw ReaderError.malformedArchive
                    }
                    return output
                }
                guard status == COMPRESSION_STATUS_OK,
                      stream.src_size < sourceSizeBefore || producedByteCount > 0 else {
                    throw ReaderError.malformedArchive
                }
            }
        }
    }

    private static func zip64EndOffset(in archive: Data) throws -> Int {
        let signature = Data([0x50, 0x4b, 0x06, 0x06])
        guard let range = archive.range(of: signature, options: .backwards) else {
            throw ReaderError.malformedArchive
        }
        return range.lowerBound
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
