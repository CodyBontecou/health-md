import Compression
import Darwin
import HealthKit
import Testing
import XCTest
import zlib
@testable import HealthMd

final class ZipArchiveWriterTests: XCTestCase {
    func testChecksumOracleMatchesKnownVectorsAndBitwiseReference() {
        XCTAssertEqual(ZIP64TestReader.crc32(Data()), 0)
        XCTAssertEqual(ZIP64TestReader.crc32(Data("123456789".utf8)), 0xcbf43926)
        XCTAssertEqual(ZIP64TestReader.crc32(Data((0...255).map { UInt8($0) })), 0x29058c73)

        // Keep the slow, independent reference confined to small inputs. The
        // archive reader must validate large entries without eight steps per byte.
        func bitwiseReference(_ data: Data) -> UInt32 {
            var value: UInt32 = 0xffff_ffff
            for byte in data {
                value ^= UInt32(byte)
                for _ in 0..<8 {
                    value = (value & 1) == 1 ? (0xedb88320 ^ (value >> 1)) : (value >> 1)
                }
            }
            return value ^ 0xffff_ffff
        }
        let source = deterministicIncompressibleBytes(count: 4_096)
        let fixtures = [
            Data(), Data([0]), Data([0xff]), Data("今日 é العربية".utf8),
            source, source[37..<293]
        ]
        for data in fixtures {
            XCTAssertEqual(ZIP64TestReader.crc32(data), bitwiseReference(data))
        }
    }

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

@MainActor
struct MorningArchiveTests {
    // STATIC RETENTION JUSTIFICATION: Isolated synthetic observation fixtures;
    // see docs/testing/lifecycle-audit.md for the nested-observation teardown issue.
    private static var retained: [AnyObject] = []

    @Test(arguments: ["daily", "range", "summary"], [false, true])
    func productionMorningArchiveKeepsAcceptedProfileAndWholeSession(mode: String, recovered: Bool) async throws {
        let f = try fixture(mode: mode)
        defer { f.cleanup() }
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        #expect(try #require(snapshot.appleExportEnginePin).isWakeDate)
        let progress: (Int, Int, String) -> Void = { _, _, _ in
            f.settings.archiveExportFiles = false
            f.settings.exportFormats = [.json]
            f.settings.metricSelection.enabledMetrics = ["steps"]
            f.settings.exportTimeZoneOverride = .gmt
            f.manager.setSleepDayAttribution(.nightBegins)
            f.vault.healthSubfolder = "Changed"
        }
        let result: ExportOrchestrator.ExportResult
        if recovered {
            result = await ExportOrchestrator.exportDatesBackground(f.dates, healthKitManager: f.manager,
                vaultManager: f.vault, settings: f.settings, frozenSettingsSnapshot: snapshot,
                operationSurface: .localVaultRangeWithoutSideEffects, onProgress: progress)
        } else {
            result = await ExportOrchestrator.exportDates(f.dates, healthKitManager: f.manager,
                vaultManager: f.vault, settings: f.settings, onProgress: progress)
        }
        #expect(result.didCompleteAllRequestedDates, "\(result.failedDateDetails) / \(result.partialFailures)")
        #expect(result.archiveCount == 1)
        #expect(result.totalFilesWritten == 1)
        let zip = f.root.appendingPathComponent("Health/Health.md Export 2026-03-07_to_2026-03-08.zip")
        let entries = try ZIP64TestReader.entries(in: Data(contentsOf: zip))
        #expect(entries[HealthMdExportSchema.dataDictionaryFilename] != nil)
        let daily = entries.filter { !$0.key.contains("/") && $0.key != HealthMdExportSchema.dataDictionaryFilename }
        #expect(daily.count == (mode == "summary" ? 0 : 8))
        #expect(entries.keys.filter { $0.contains("Rollups/Range/") }.count == (mode == "daily" ? 0 : 4))
        if mode != "summary" {
            let wakeBytes = try #require(entries["2026-03-08.json"]?.data)
            let wake = try #require(JSONSerialization.jsonObject(with: wakeBytes) as? [String: Any])
            #expect(wake["schema_version"] as? Int == 11)
            #expect(wake["schema_profile"] as? String == "apple-v11")
            let context = try #require(wake["time_context"] as? [String: Any])
            #expect(context["calendar_timezone"] as? String == "America/New_York")
            #expect(context["sleep_day_attribution"] as? String == "morning_ends")
            let sleep = try #require(wake["sleep"] as? [String: Any])
            #expect(sleep["totalDuration"] as? Double == 26 * 3600 + 0.5)
            let first = try #require(entries["2026-03-07.json"]?.data)
            let previous = try #require(JSONSerialization.jsonObject(with: first) as? [String: Any])
            #expect((previous["sleep"] as? [String: Any])?["totalDuration"] as? Double != 26 * 3600 + 0.5)
        }
        let files = try #require(FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: [.isRegularFileKey]))
            .allObjects.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        #expect(files.map { $0.resolvingSymlinksInPath().path } == [zip.resolvingSymlinksInPath().path])
    }

    @Test func acceptedMaterializationIsPackagedByteForByte() async throws {
        let f = try fixture(mode: "daily")
        defer { f.cleanup() }
        f.settings.executionExternalProviderCaptureAuthority = .init(connections: ["whoop": UUID()])
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        var records: [HealthData] = []
        for date in f.dates {
            records.append(try await f.manager.fetchHealthData(for: date, detailPolicy: .detailedTimeSeries,
                metricSelection: f.settings.metricSelection, timeZone: f.context.timeZone, captureContext: f.context))
        }
        let provider = ExternalDailyRecord(provider: .whoop, date: "2026-03-08", fetchedAt: f.dates[1],
            payloads: [.init(name: "cycles", endpoint: "https://synthetic.invalid", statusCode: 200,
                data: .object(["synthetic": .string("accepted-provider-bytes")]))])
        let materialized = try #require(try await f.vault.materializeHealthDataRange(records,
            settingsSnapshot: snapshot, operationSurface: .localVaultRangeWithoutSideEffects))
            .addingProviderSidecars(try f.vault.materializeExternalDailyRecords([provider], healthSubfolder: "Health"))
        var expected: [String: Data] = [:]
        for file in materialized.operation.artifacts {
            expected[String(file.artifact.relativePath.dropFirst("Health/".count))] = try file.artifact.content.materializedData()
        }
        if let dictionary = materialized.dataDictionary {
            expected[String(dictionary.relativePath.dropFirst("Health/".count))] = dictionary.data
        }
        for file in materialized.providerSidecars {
            expected[String(file.relativePath.dropFirst("Health/".count))] = try file.artifact.materializedData()
        }
        let archive = try #require(try await f.vault.commitHealthDataRangeArchive(materialized,
            destination: f.vault.freezeHealthDataRangeDestination(), settingsSnapshot: snapshot,
            startDate: f.dates[0], endDate: f.dates[1]))
        let actual = try ZIP64TestReader.entries(in: Data(contentsOf: archive)).mapValues(\.data)
        #expect(actual == expected)
        #expect(expected.count == 10)
    }

    @Test(arguments: ["same", "swap", "truncate", "symlink", "cancel"])
    func zipConsumesExactAcceptedFileDescriptor(mode: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MorningZipIntegrity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 0x41, count: 100_003)
        let file = try ExportArtifactIO.renderTemporary(in: root, prefix: "accepted", mediaType: "application/json") {
            try $0.write(bytes)
        }
        let zip = root.appendingPathComponent("export.zip")
        let old = Data("old committed archive".utf8)
        try old.write(to: zip)
        let writer = try ZipArchiveWriter.begin(to: zip, checkpointURL: root.appendingPathComponent("checkpoint"), chunkSize: 8192)
        if mode == "swap" { try Data(repeating: 0x42, count: bytes.count).write(to: file.url) }
        if mode == "truncate" { try Data("short".utf8).write(to: file.url) }
        if mode == "symlink" {
            let other = root.appendingPathComponent("other")
            try bytes.write(to: other)
            try FileManager.default.removeItem(at: file.url)
            try FileManager.default.createSymbolicLink(at: file.url, withDestinationURL: other)
        }
        if mode == "same" {
            try writer.append(path: "accepted.json", artifact: file)
            try writer.finish()
            #expect(try ZIP64TestReader.entries(in: Data(contentsOf: zip))["accepted.json"]?.data == bytes)
        } else {
            #expect(throws: (any Error).self) {
                try writer.append(path: "accepted.json", artifact: file, cancellationCheck: { mode == "cancel" })
            }
            writer.abandon()
            #expect(try Data(contentsOf: zip) == old)
        }
    }

    @Test(arguments: ["cancel", "destination", "corrupt", "duplicate"])
    func failedAcceptedArchivePreservesPreviousZip(mode: String) async throws {
        let f = try fixture(mode: "daily")
        defer { f.cleanup() }
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        var records: [HealthData] = []
        for date in f.dates {
            records.append(try await f.manager.fetchHealthData(for: date, detailPolicy: .detailedTimeSeries,
                metricSelection: f.settings.metricSelection, timeZone: f.context.timeZone, captureContext: f.context))
        }
        var materialized = try #require(try await f.vault.materializeHealthDataRange(records,
            settingsSnapshot: snapshot, operationSurface: .localVaultRangeWithoutSideEffects))
        let destination = try f.vault.freezeHealthDataRangeDestination()
        let zip = f.root.appendingPathComponent("Health/Health.md Export 2026-03-07_to_2026-03-08.zip")
        try FileManager.default.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = Data("previous committed archive".utf8)
        try old.write(to: zip)
        if mode == "destination" {
            let other = f.root.appendingPathComponent("Rebound")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            f.vault.vaultURL = other
        }
        if mode == "corrupt" {
            let file = try #require(materialized.operation.artifacts.compactMap { planned -> ExportArtifactFile? in
                if case .file(let file) = planned.artifact.content { return file }; return nil
            }.first)
            try Data(repeating: 0x5a, count: Int(file.descriptor.byteCount)).write(to: file.url)
        }
        if mode == "duplicate" {
            let file = try ExportArtifactIO.renderTemporary(in: f.root.appendingPathComponent("private"),
                prefix: "duplicate", mediaType: "application/json") { try $0.write(Data("{}".utf8)) }
            materialized = materialized.addingProviderSidecars([
                .init(relativePath: try #require(materialized.operation.artifacts.first?.artifact.relativePath), artifact: file)])
        }
        let accepted = materialized
        let task = Task {
            if mode == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            return try await f.vault.commitHealthDataRangeArchive(accepted, destination: destination,
                settingsSnapshot: snapshot, startDate: f.dates[0], endDate: f.dates[1])
        }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try Data(contentsOf: zip) == old)
    }

    fileprivate struct Fixture {
        let root: URL
        let suite: String
        let defaults: UserDefaults
        let settings: AdvancedExportSettings
        let manager: HealthKitManager
        let store: FakeHealthStore
        let vault: VaultManager
        let context: AppleSleepCaptureContext
        let dates: [Date]
        func cleanup() { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
    }
    fileprivate func fixture(mode: String) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MorningArchive-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "MorningArchive-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = Set(ExportFormat.allCases); settings.archiveExportFiles = true
        settings.includeDataDictionary = true; settings.generateRangeSummary = mode != "daily"
        settings.summaryOnlyExport = mode == "summary"; settings.detailPolicy = .detailedTimeSeries
        settings.dailyNoteInjection.enabled = false; settings.individualTracking.globalEnabled = false
        settings.filenameFormat = "{date}"; settings.folderStructure = ""; settings.organizeFormatsIntoFolders = false
        settings.metricSelection.enabledMetrics = ["steps", "sleep_total", "sleep_core", "sleep_bedtime", "sleep_wake"]
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.exportTimeZoneOverride = zone; settings.executionSleepCaptureContext = context
        settings.executionExternalProviderCaptureAuthority = .init(connections: [:])
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let wake = try #require(calendar.date(byAdding: .day, value: 1, to: first))
        let start = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: first))
        let end = try #require(calendar.date(bySettingHour: 13, minute: 0, second: 0, of: wake)).addingTimeInterval(0.5)
        let store = FakeHealthStore(); store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 42
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = [
            .init(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, startDate: start, endDate: end)]
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        manager.setSleepDayAttribution(.morningEnds)
        let bookmarks = FakeBookmarkResolver(); bookmarks.accessGranted = true
        let vault = VaultManager(defaults: FakeUserDefaults(), fileSystem: SystemFileSystem(), bookmarkResolver: bookmarks)
        vault.healthSubfolder = "Health"; vault.setVaultFolder(root)
        Self.retained += [settings, manager, vault]
        return Fixture(root: root, suite: suite, defaults: defaults, settings: settings, manager: manager, store: store,
            vault: vault, context: context, dates: [first, wake])
    }
}

@MainActor
struct MorningIndividualEntryTests {
    @Test func stagedNotesAndRoutesMatchWriterAndRestoreBorrowedCalendar() throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        let settings = f.settings.individualTracking
        settings.globalEnabled = true; settings.setTrackIndividually("workouts", enabled: true)
        let instant = f.dates[1].addingTimeInterval(12 * 3600)
        let route = [RoutePoint(timestamp: instant, latitude: 1, longitude: 2, altitudeMeters: nil,
            speedMps: nil, courseDegrees: nil, horizontalAccuracyMeters: nil)]
        let workout = WorkoutData(workoutType: .running, startTime: instant, duration: 1800,
            calories: 100, distance: 1000, route: route)
        let sample = IndividualHealthSample(metricId: "workouts", metricName: "Workouts", category: .workouts,
            timestamp: instant, value: 1800.0, unit: "seconds", workout: workout)
        let fileSystem = FakeFileSystem()
        let exporter = IndividualEntryExporter(fileSystem: fileSystem)
        let legacyPreview = exporter.previewEntryContent(for: sample, formatSettings: f.settings.formatCustomization)
        let root = URL(fileURLWithPath: "/__individual_planner_control__")
        var planned: [String: String] = [:]
        let logicalCount = try exporter.planIndividualEntries(samples: [sample], to: root, settings: settings,
            formatSettings: f.settings.formatCustomization, calendarTimeZone: f.context.timeZone) { url, content, _ in
            planned[url.path] = content
        }
        #expect(logicalCount == 1)
        #expect(planned.count == 2)
        #expect(fileSystem.files.isEmpty)
        #expect(planned.keys.contains { $0.hasSuffix("2026_03_08_1300_workouts.md") })
        #expect(try exporter.exportIndividualEntries(samples: [sample], to: root, settings: settings,
            formatSettings: f.settings.formatCustomization, calendarTimeZone: f.context.timeZone) == logicalCount)
        #expect(fileSystem.files == planned)
        #expect(exporter.previewEntryContent(for: sample, formatSettings: f.settings.formatCustomization) == legacyPreview)
        #expect(exporter.previewEntryContent(for: sample, formatSettings: f.settings.formatCustomization,
            calendarTimeZone: f.context.timeZone).contains("time: \"13:00\""))
    }

    @Test(arguments: ["folder", "filename"])
    func unsafeIndividualPathsFailBeforeDestinationEffects(mode: String) throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        let settings = f.settings.individualTracking
        settings.globalEnabled = true; settings.setTrackIndividually("steps", enabled: true)
        if mode == "folder" { settings.entriesFolder = "../../escape" }
        else { settings.filenameTemplate = "../escape" }
        let sample = IndividualHealthSample(metricId: "steps", metricName: "Steps", category: .activity,
            timestamp: f.dates[1], value: 42, unit: "steps")
        let files = FakeFileSystem()
        let exporter = IndividualEntryExporter(fileSystem: files)
        #expect(throws: (any Error).self) {
            try exporter.exportIndividualEntries(samples: [sample], to: URL(fileURLWithPath: "/__unsafe_individual_control__"),
                settings: settings, formatSettings: f.settings.formatCustomization, calendarTimeZone: f.context.timeZone)
        }
        #expect(files.files.isEmpty)
        #expect(files.directories.isEmpty)
    }

    @Test(arguments: ["daily", "range", "zip", "summary", "workout"], [false, true])
    func productionIndividualEntriesKeepAcceptedClockAndWholeSleep(mode: String, recovered: Bool) async throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        f.settings.archiveExportFiles = mode == "zip"
        f.settings.generateRangeSummary = mode == "range" || mode == "summary"
        f.settings.summaryOnlyExport = mode == "summary"
        f.settings.individualTracking.globalEnabled = true
        f.settings.individualTracking.setTrackIndividually("sleep_total", enabled: true)
        f.settings.individualTracking.setTrackIndividually("steps", enabled: true)
        if mode == "workout" {
            f.settings.metricSelection.enabledMetrics.insert("workouts")
            f.settings.individualTracking.setTrackIndividually("workouts", enabled: true)
            let start = f.dates[1].addingTimeInterval(12 * 3600)
            f.store.workoutResults = [.init(activityType: HKWorkoutActivityType.running.rawValue, duration: 1800,
                startDate: start, endDate: start.addingTimeInterval(1800), totalEnergyBurned: 100, totalDistance: 1000)]
        }
        let requestedDates = mode == "workout" ? [f.dates[1]] : f.dates
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        #expect(try #require(snapshot.appleExportEnginePin).isWakeDate)
        let progress: (Int, Int, String) -> Void = { _, _, _ in
            f.settings.individualTracking.globalEnabled = false
            f.settings.individualTracking.entriesFolder = "Changed"
            f.settings.exportTimeZoneOverride = .gmt
            f.manager.setSleepDayAttribution(.nightBegins)
        }
        let result: ExportOrchestrator.ExportResult
        if recovered {
            result = await ExportOrchestrator.exportDatesBackground(requestedDates, healthKitManager: f.manager,
                vaultManager: f.vault, settings: f.settings, frozenSettingsSnapshot: snapshot,
                operationSurface: .localVaultRangeWithoutSideEffects, onProgress: progress)
        } else {
            result = await ExportOrchestrator.exportDates(requestedDates, healthKitManager: f.manager,
                vaultManager: f.vault, settings: f.settings, onProgress: progress)
        }
        #expect(result.didCompleteAllRequestedDates, "\(result.failedDateDetails) / \(result.partialFailures)")
        let files: [String: Data]
        if mode == "zip" {
            let url = f.root.appendingPathComponent("Health/Health.md Export 2026-03-07_to_2026-03-08.zip")
            files = try ZIP64TestReader.entries(in: Data(contentsOf: url)).mapValues(\.data)
            #expect(result.totalFilesWritten == 1)
        } else {
            let all = try #require(FileManager.default.enumerator(at: f.root, includingPropertiesForKeys: [.isRegularFileKey]))
                .allObjects.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            files = try Dictionary(uniqueKeysWithValues: all.map { ($0.path, try Data(contentsOf: $0)) })
            #expect(result.totalFilesWritten == files.count)
        }
        let entries = files.filter { $0.key.contains("entries/") }
        if ["daily", "workout"].contains(mode), !recovered,
           let directory = ProcessInfo.processInfo.environment["HEALTHMD_INDIVIDUAL_ENTRY_FIXTURE_DIR"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(mode == "workout" ? "workouts" : "basic", isDirectory: true)
            let root = f.root.resolvingSymlinksInPath().path + "/"
            for (path, bytes) in files {
                let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                guard resolved.hasPrefix(root) else { throw CocoaError(.fileReadInvalidFileName) }
                let target = output.appendingPathComponent(String(resolved.dropFirst(root.count)))
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target)
            }
        }
        #expect(!files.keys.contains { $0.contains("Changed") })
        if mode == "summary" {
            #expect(entries.isEmpty)
            #expect(result.individualEntryFileCount == 0)
        } else {
            #expect(!entries.isEmpty)
            if mode != "zip" { #expect(result.individualEntryFileCount == entries.count) }
            let wake = try #require(entries.first { $0.key.hasSuffix("2026_03_08_0000_sleep_total.md") })
            let text = try #require(String(data: wake.value, encoding: .utf8))
            #expect(text.contains("date: 2026-03-08\n"))
            let valueLine = try #require(text.components(separatedBy: "\n").first { $0.hasPrefix("value: ") })
            #expect(try #require(Double(valueLine.dropFirst(7).replacingOccurrences(of: "\"", with: ""))) >= 26)
            let line = try #require(text.components(separatedBy: "\n").first { $0.hasPrefix("healthmd_capture_context_json: ") })
            let quoted = Data(line.dropFirst("healthmd_capture_context_json: ".count).utf8)
            let json = try #require(JSONSerialization.jsonObject(with: quoted, options: [.fragmentsAllowed]) as? String)
            let context = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
            #expect(context["schema_profile"] == "apple-v11")
            #expect(context["calendar_timezone"] == "America/New_York")
            #expect(context["sleep_owner_date"] == "2026-03-08")
            #expect(context["sleep_interval_clipping"] == "none")
        }
    }

    @Test func identicalIndividualSourcesDeduplicateAndConflictsReject() async throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        let record = try await f.manager.fetchHealthData(for: f.dates[1], detailPolicy: .summary,
            metricSelection: f.settings.metricSelection, timeZone: f.context.timeZone, captureContext: f.context)
        let materialized = try #require(try await f.vault.materializeHealthDataRange([record],
            settingsSnapshot: snapshot, operationSurface: .localVaultRangeWithoutSideEffects))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IndividualDedup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ExportArtifactIO.renderTemporary(in: root, prefix: "first", mediaType: "text/markdown") {
            try $0.write(Data("accepted".utf8))
        }
        let same = try ExportArtifactIO.renderTemporary(in: root, prefix: "same", mediaType: "text/markdown") {
            try $0.write(Data("accepted".utf8))
        }
        let different = try ExportArtifactIO.renderTemporary(in: root, prefix: "different", mediaType: "text/markdown") {
            try $0.write(Data("conflict".utf8))
        }
        let path = "Health/entries/accepted.md"
        let accepted = try materialized.addingIndividualEntries([
            .init(relativePath: path, artifact: first), .init(relativePath: path, artifact: same)])
        #expect(accepted.individualEntries.count == 1)
        #expect(accepted.result.individualEntryFileCount == 1)
        #expect(throws: AppleExactDestinationError.self) {
            try accepted.addingIndividualEntries([.init(relativePath: path, artifact: different)])
        }
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
        // Use an independent system oracle, not the archive writer's CRC code.
        data.withUnsafeBytes { bytes in
            UInt32(zlib.crc32_z(
                0,
                bytes.bindMemory(to: Bytef.self).baseAddress,
                z_size_t(bytes.count)
            ))
        }
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

@MainActor
struct MorningDailyNoteTests {
    @Test(arguments: [false, true])
    func preparedInjectionScopesAuthorityAndPreservesPersonalContent(sections: Bool) async throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        f.settings.archiveExportFiles = false
        var snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        snapshot.dailyNoteInjection.enabled = true
        snapshot.dailyNoteInjection.folderPath = "Journal"
        snapshot.dailyNoteInjection.createIfMissing = true
        snapshot.dailyNoteInjection.injectMarkdownSections = sections
        snapshot.detailPolicy = .lossless
        snapshot.formatCustomization.frontmatterConfig.keyStyle = .camelCase
        snapshot.formatCustomization.frontmatterConfig.customFields = ["Daily steps": "incorrect custom value"]
        // This custom field is disabled in full-note frontmatter. Injection is
        // governed by metric selection and must still honor its accepted alias.
        if let index = snapshot.formatCustomization.frontmatterConfig.fields.firstIndex(where: { $0.originalKey == "steps" }) {
            snapshot.formatCustomization.frontmatterConfig.fields[index].customKey = "Daily steps"
            snapshot.formatCustomization.frontmatterConfig.fields[index].isEnabled = false
        }
        let settings = snapshot.makeAdvancedExportSettings()
        let record = try await f.manager.fetchHealthData(for: f.dates[1], detailPolicy: .detailedTimeSeries,
            metricSelection: f.settings.metricSelection, timeZone: f.context.timeZone, captureContext: f.context)
        let prepared = try await f.vault.prepareWakeDateDailyNote(record, settingsSnapshot: snapshot)
        let personal = "---\ntitle: My journal\nsleep_deep_hours: 9 # historical field\n---\n# Personal title\nKeep my introduction.\n\n## Thoughts\nMy own section.\n"
        let base = f.root.appendingPathComponent("Journal/2026-03-08.md")
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        try personal.write(to: base, atomically: true, encoding: .utf8)
        let destination = try f.vault.freezeHealthDataRangeDestination()
        let result = DailyNoteInjector.inject(healthData: record, into: f.root,
            settings: settings.dailyNoteInjection, customization: settings.formatCustomization,
            metricSelection: settings.metricSelection, calendarTimeZone: f.context.timeZone,
            preparedContent: prepared, destinationBinding: destination.binding)
        guard case .updated = result else { Issue.record("Expected prepared injection: \(result)"); return }
        let note = try String(contentsOf: base, encoding: .utf8)
        #expect(note.contains("title: My journal\n"))
        #expect(note.contains("sleep_deep_hours: 9 # historical field\n"))
        #expect(note.contains("# Personal title\nKeep my introduction."))
        #expect(note.contains("## Thoughts\nMy own section."))
        #expect(note.contains("Daily steps: 42"))
        #expect(!note.contains("schema_profile: apple-v11"))
        let properties = try #require(MarkdownMerger.frontmatterProperties(named: ["healthmd_daily_injection_v1"], in: note))
        #expect(properties.count == 1)
        let value = try #require(properties.first?.split(separator: ":", maxSplits: 1).last)
        let decoded = try JSONDecoder().decode(String.self, from: Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any])
        let nativeJSON = try #require(envelope["record_json"] as? String)
        let native = try #require(JSONSerialization.jsonObject(with: Data(nativeJSON.utf8)) as? [String: Any])
        #expect(native["schema_profile"] as? String == "apple-v11")
        #expect(native["healthkit_record_archive"] == nil)
        let sleep = try #require(native["sleep"] as? [String: Any])
        #expect(sleep["totalDuration"] as? Double == 93600.5)
        #expect(sleep["deepSleep"] == nil)
        #expect(note.contains("##") && (!sections || note.contains("Sleep")))
        guard case .preview(let preview) = DailyNoteInjector.preview(healthData: record, base: .existingContent(personal),
            settings: settings.dailyNoteInjection, customization: settings.formatCustomization,
            metricSelection: settings.metricSelection, calendarTimeZone: f.context.timeZone, preparedContent: prepared) else {
            Issue.record("Expected exact prepared preview"); return
        }
        #expect(preview.content == note)
        if let directory = ProcessInfo.processInfo.environment["HEALTHMD_DAILY_NOTE_FIXTURE_DIR"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data(note.utf8).write(to: output.appendingPathComponent(sections ? "sections.md" : "frontmatter.md"))
            try Data(nativeJSON.utf8).write(to: output.appendingPathComponent(sections ? "sections.json" : "frontmatter.json"))
        }
        // Changing the captured clock or injection settings cannot retarget a
        // previously prepared patch or create an empty destination file.
        let wrongRoot = f.root.appendingPathComponent("Rejected")
        let wrong = DailyNoteInjector.inject(healthData: record, into: wrongRoot,
            settings: settings.dailyNoteInjection, customization: settings.formatCustomization,
            metricSelection: settings.metricSelection, calendarTimeZone: .gmt, preparedContent: prepared)
        guard case .failed = wrong else { Issue.record("Expected clock mismatch"); return }
        #expect(!FileManager.default.fileExists(atPath: wrongRoot.path))
        if !sections {
            let nightContext = AppleSleepCaptureContext(timeZone: f.context.timeZone, sleepDayAttribution: .nightBegins)
            let night = try await f.manager.fetchHealthData(for: f.dates[1], detailPolicy: .summary,
                metricSelection: settings.metricSelection, timeZone: f.context.timeZone, captureContext: nightContext)
            let replaced = DailyNoteInjector.inject(healthData: night, into: f.root,
                settings: settings.dailyNoteInjection, customization: settings.formatCustomization,
                metricSelection: settings.metricSelection, calendarTimeZone: f.context.timeZone,
                destinationBinding: destination.binding)
            guard case .updated = replaced else { Issue.record("Expected Night begins replacement"); return }
            let updated = try String(contentsOf: base, encoding: .utf8)
            #expect(updated.contains("healthmd_injection_kind: daily_capture_v1\n"))
            #expect(!updated.contains("healthmd_daily_injection_v1: null\n"))
            #expect(updated.contains("sleep_deep_hours: 9 # historical field\n"))
            #expect(updated.contains("healthmd_daily_capture"))
            if let directory = ProcessInfo.processInfo.environment["HEALTHMD_DAILY_NOTE_FIXTURE_DIR"] {
                try Data(updated.utf8).write(to: URL(fileURLWithPath: directory).appendingPathComponent("night-replacement.md"))
            }
        }
    }

    @Test func morningInjectionWithoutAcceptedPlanFailsBeforeCreatingFile() async throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        let record = try await f.manager.fetchHealthData(for: f.dates[1], detailPolicy: .summary,
            metricSelection: f.settings.metricSelection, timeZone: f.context.timeZone, captureContext: f.context)
        f.settings.dailyNoteInjection.enabled = true
        f.settings.dailyNoteInjection.createIfMissing = true
        let result = DailyNoteInjector.inject(healthData: record, into: f.root,
            settings: f.settings.dailyNoteInjection, customization: f.settings.formatCustomization,
            metricSelection: f.settings.metricSelection, calendarTimeZone: f.context.timeZone)
        guard case .failed = result else { Issue.record("Expected missing-plan failure"); return }
        #expect((try FileManager.default.contentsOfDirectory(atPath: f.root.path)).isEmpty)
    }
}

@MainActor
struct DailyNoteAttributionTransitionTests {
    @Test(arguments: ["0-0-steps", "0-1-steps", "1-0-steps", "1-1-steps",
        "0-0-sleep", "0-1-sleep", "1-0-sleep", "1-1-sleep",
        "0-0-both", "0-1-both", "1-0-both", "1-1-both"])
    func attributionAndSectionChangesKeepOnlyTheNewCaptureAuthoritative(mode: String) async throws {
        let f = try MorningArchiveTests().fixture(mode: "daily")
        defer { f.cleanup() }
        let parts = mode.split(separator: "-")
        f.settings.archiveExportFiles = false
        var snapshot = await ExportSettingsSnapshot.forNewAppleOperation(f.settings, healthSubfolder: "Health",
            calendarTimeZone: f.context.timeZone, surface: .localVaultRangeWithoutSideEffects)
        snapshot.dailyNoteInjection.enabled = true
        snapshot.dailyNoteInjection.folderPath = "Journal"
        snapshot.dailyNoteInjection.createIfMissing = true
        snapshot.dailyNoteInjection.injectMarkdownSections = parts[0] == "1"
        let settings = snapshot.makeAdvancedExportSettings()
        let morning = try await f.manager.fetchHealthData(for: f.dates[1], detailPolicy: .detailedTimeSeries,
            metricSelection: settings.metricSelection, timeZone: f.context.timeZone, captureContext: f.context)
        let prepared = try await f.vault.prepareWakeDateDailyNote(morning, settingsSnapshot: snapshot)
        let path = f.root.appendingPathComponent("Journal/2026-03-08.md")
        let personal = "---\ndate: 2026-03-08\ntitle: Personal\nsleep_deep_hours: 9 # unselected history\n---\nMy introduction.\n\n## Thoughts\nPreserve this text.\n"
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(personal.utf8).write(to: path)
        let destination = try f.vault.freezeHealthDataRangeDestination()
        let first = DailyNoteInjector.inject(healthData: morning, into: f.root, settings: settings.dailyNoteInjection,
            customization: settings.formatCustomization, metricSelection: settings.metricSelection,
            calendarTimeZone: f.context.timeZone, preparedContent: prepared, destinationBinding: destination.binding)
        guard case .updated = first else { Issue.record("Expected Morning injection"); return }
        let firstContent = try String(contentsOf: path, encoding: .utf8)

        let nightSettings = snapshot.makeAdvancedExportSettings()
        nightSettings.dailyNoteInjection.injectMarkdownSections = parts[1] == "1"
        nightSettings.metricSelection.enabledMetrics = parts[2] == "steps" ? ["steps"]
            : parts[2] == "sleep" ? ["sleep_total", "sleep_core"] : ["steps", "sleep_total", "sleep_core"]
        let nightContext = AppleSleepCaptureContext(timeZone: f.context.timeZone, sleepDayAttribution: .nightBegins)
        let night = try await f.manager.fetchHealthData(for: f.dates[1], detailPolicy: .detailedTimeSeries,
            metricSelection: nightSettings.metricSelection, timeZone: f.context.timeZone, captureContext: nightContext)
        let result = DailyNoteInjector.inject(healthData: night, into: f.root, settings: nightSettings.dailyNoteInjection,
            customization: nightSettings.formatCustomization, metricSelection: nightSettings.metricSelection,
            calendarTimeZone: f.context.timeZone, destinationBinding: destination.binding)
        guard case .updated = result else { Issue.record("Expected scoped Night injection"); return }
        let nightContent = try String(contentsOf: path, encoding: .utf8)
        let nightJSON = try captureJSON(nightContent)
        let nightRecord = try #require(JSONSerialization.jsonObject(with: Data(nightJSON.utf8)) as? [String: Any])
        #expect(nightRecord["schema_version"] as? Int == 8)
        #expect(nightRecord["schema_profile"] == nil)
        #expect(nightRecord["healthkit_record_archive"] == nil)
        #expect((nightRecord["time_context"] as? [String: String])?["calendar_timezone"] == f.context.calendarTimeZoneIdentifier)
        let sleep = nightRecord["sleep"] as? [String: Any]
        let activity = nightRecord["activity"] as? [String: Any]
        #expect(sleep?["deepSleep"] == nil)
        if parts[2] == "steps" {
            #expect((sleep?["totalDuration"] as? Double ?? 0) == 0)
            #expect(nightContent.contains("sleep_total_hours:"), "The old personal property remains outside the new capture")
        } else {
            #expect(sleep?["totalDuration"] as? Double == 3600.5)
        }
        if parts[2] == "sleep" { #expect(activity?["steps"] == nil) }
        else { #expect(activity?["steps"] as? Int == 42) }
        let stages = sleep?["sleepStages"] as? [[String: Any]] ?? []
        if parts[1] == "1", parts[2] != "steps" {
            #expect(stages.count == 1, "Selected current Night details must stay in the scoped record")
            #expect(stages.first?["durationSeconds"] as? Double == 3600.5)
        } else { #expect(stages.isEmpty) }
        if parts[0] == "1", parts[1] == "0" {
            #expect(nightContent.contains("## Sleep Stage Details"), "Sections disabled: preserve the user's existing body")
        }
        #expect(nightContent.contains("sleep_deep_hours: 9 # unselected history"))
        #expect(nightContent.contains("## Thoughts\nPreserve this text."))
        guard case .preview(let preview) = DailyNoteInjector.preview(healthData: night, base: .existingContent(firstContent),
            settings: nightSettings.dailyNoteInjection, customization: nightSettings.formatCustomization,
            metricSelection: nightSettings.metricSelection, calendarTimeZone: f.context.timeZone) else {
            Issue.record("Expected scoped Night preview"); return
        }
        #expect(preview.content == nightContent)

        // The reverse transition restores whole-session ownership, including
        // its fractional source duration, without adopting retained old facts.
        let restored = DailyNoteInjector.inject(healthData: morning, into: f.root, settings: settings.dailyNoteInjection,
            customization: settings.formatCustomization, metricSelection: settings.metricSelection,
            calendarTimeZone: f.context.timeZone, preparedContent: prepared, destinationBinding: destination.binding)
        guard case .updated = restored else { Issue.record("Expected Morning restoration"); return }
        let restoredContent = try String(contentsOf: path, encoding: .utf8)
        let restoredJSON = try captureJSON(restoredContent)
        let restoredRecord = try #require(JSONSerialization.jsonObject(with: Data(restoredJSON.utf8)) as? [String: Any])
        #expect(restoredRecord["schema_profile"] as? String == "apple-v11")
        #expect((restoredRecord["sleep"] as? [String: Any])?["totalDuration"] as? Double == 93600.5)
        #expect(restoredContent.contains("sleep_deep_hours: 9 # unselected history"))
        if let directory = ProcessInfo.processInfo.environment["HEALTHMD_DAILY_NOTE_TRANSITION_FIXTURE_DIR"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (name, content) in ["night-\(mode).md": nightContent, "night-\(mode).json": nightJSON,
                "restored-\(mode).md": restoredContent, "restored-\(mode).json": restoredJSON] {
                try Data(content.utf8).write(to: output.appendingPathComponent(name))
            }
        }
    }

    private func captureJSON(_ note: String) throws -> String {
        let properties = try #require(MarkdownMerger.frontmatterProperties(named: ["healthmd_daily_injection_v1"], in: note))
        #expect(properties.count == 1)
        let value = try #require(properties.first?.split(separator: ":", maxSplits: 1).last)
        let string = try JSONDecoder().decode(String.self, from: Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
        return try #require(envelope["record_json"] as? String)
    }
}
