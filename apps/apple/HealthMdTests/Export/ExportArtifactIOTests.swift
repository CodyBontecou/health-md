import Foundation
import XCTest
@testable import HealthMd

final class ExportArtifactIOTests: XCTestCase {
    private enum FixtureError: Error {
        case injected
    }

    func testCanonicalStringEscapingMatchesFoundationForScalarBoundaries() throws {
        struct Fixture: Encodable {
            let values: [String]
            let doubles: [Double]
            let float: Float
        }
        let fixture = Fixture(
            values: [
                "quote\" slash/ backslash\\",
                "controls:\u{0000}\u{0008}\t\n\u{000c}\r\u{001f}",
                "unicode:é 🫀 \u{2028} \u{2029}"
            ],
            doubles: [21.3069, -157.8583, 0.42, 0.18, 0.4, .nan],
            float: 0.1
        )
        let expectedEncoder = JSONEncoder()
        expectedEncoder.outputFormatting = [.sortedKeys]
        expectedEncoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let expected = try expectedEncoder.encode(fixture)
        let sink = MemoryExportByteSink(mediaType: "application/json")
        let encoder = try CanonicalJSONStreamEncoder(
            sink: sink,
            formatting: .compactFoundation
        )
        try encoder.encode(fixture)
        _ = try sink.finish()
        XCTAssertEqual(sink.data, expected)
    }

    func testMemorySinkTracksExactBytesAndDigest() throws {
        let sink = MemoryExportByteSink(mediaType: "application/json")
        try sink.write(Data("a".utf8))
        try sink.write(Data("bc".utf8))

        let descriptor = try sink.finish()

        XCTAssertEqual(sink.data, Data("abc".utf8))
        XCTAssertEqual(descriptor.byteCount, 3)
        XCTAssertEqual(
            descriptor.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(descriptor.mediaType, "application/json")
        XCTAssertEqual(try sink.finish(), descriptor)
        XCTAssertThrowsError(try sink.write(Data([0]))) { error in
            XCTAssertEqual(error as? ExportArtifactIOError, .alreadyFinished)
        }
    }

    func testTemporaryArtifactUsesRestrictedFileAndLeaseCleanup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        var artifact: ExportArtifactFile? = try ExportArtifactIO.renderTemporary(
            in: directory,
            prefix: "fixture",
            mediaType: "text/csv"
        ) { sink in
            try sink.write(Data("one,".utf8))
            try sink.write(Data("two\n".utf8))
        }
        let url = try XCTUnwrap(artifact?.url)

        XCTAssertEqual(try Data(contentsOf: url), Data("one,two\n".utf8))
        XCTAssertEqual(artifact?.descriptor.byteCount, 8)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
            as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        artifact = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLeaseCleanupNeverRecursivelyRemovesSiblingArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        var first: ExportArtifactFile? = try ExportArtifactIO.renderTemporary(
            in: directory,
            prefix: "first",
            mediaType: "application/json"
        ) { try $0.write(Data("first".utf8)) }
        let second = try ExportArtifactIO.renderTemporary(
            in: directory,
            prefix: "second",
            mediaType: "application/json"
        ) { try $0.write(Data("second".utf8)) }
        let secondURL = second.url

        first = nil

        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data("second".utf8))
        _ = first
    }

    func testAtomicStreamFailurePreservesDestinationAndRemovesTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("daily.json")
        try Data("existing".utf8).write(to: destination)

        XCTAssertThrowsError(try ExportArtifactIO.renderAtomically(
            to: destination,
            mediaType: "application/json"
        ) { sink in
            try sink.write(Data("partial".utf8))
            throw FixtureError.injected
        })

        XCTAssertEqual(try Data(contentsOf: destination), Data("existing".utf8))
        let siblings = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(siblings.map(\.lastPathComponent), [destination.lastPathComponent])
    }

    func testAtomicCancellationPreservesDestinationAndCleansPartialArtifact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("daily.json")
        try Data("committed".utf8).write(to: destination)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ExportArtifactIO.renderAtomically(
                to: destination,
                mediaType: "application/json"
            ) { sink in
                try sink.write(Data("partial".utf8))
            }
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: destination), Data("committed".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [destination.lastPathComponent]
        )
    }

    func testAtomicBeforeCommitCancellationCannotReplaceDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("daily.json")
        try Data("committed".utf8).write(to: destination)

        XCTAssertThrowsError(try AtomicFileWriter.writeFile(
            to: destination,
            beforeCommit: { throw CancellationError() }
        ) { temporaryURL in
            try Data("complete-but-cancelled".utf8).write(to: temporaryURL)
        }) { error in
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(try Data(contentsOf: destination), Data("committed".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [destination.lastPathComponent]
        )
    }

    func testAtomicLowDiskFailurePreservesDestinationAndCleansPartialArtifact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("daily.json")
        try Data("committed".utf8).write(to: destination)

        XCTAssertThrowsError(try ExportArtifactIO.renderAtomically(
            to: destination,
            mediaType: "application/json"
        ) { sink in
            try sink.write(Data("partial".utf8))
            throw POSIXError(.ENOSPC)
        }) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOSPC)
        }

        XCTAssertEqual(try Data(contentsOf: destination), Data("committed".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [destination.lastPathComponent]
        )
    }

    func testAtomicStreamSuccessReturnsFinalIntegrity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportArtifactIOTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("daily.json")

        let descriptor = try ExportArtifactIO.renderAtomically(
            to: destination,
            mediaType: "application/json"
        ) { sink in
            try sink.write(Data("abc".utf8))
        }

        XCTAssertEqual(try Data(contentsOf: destination), Data("abc".utf8))
        XCTAssertEqual(descriptor.byteCount, 3)
        XCTAssertEqual(
            descriptor.sha256,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
