import Foundation
import XCTest
@testable import HealthMd

final class ConnectedCorpusPartitionFileTests: XCTestCase {
    func testAssemblerSplitsOversizedItemIntoBoundedDigestChainedPartitions() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let sourceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let itemURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "large-corpus-item-test")
        let output = try FileHandle(forWritingTo: itemURL)
        let block = Data(repeating: 0x5a, count: 1_048_576)
        for _ in 0..<35 { try output.write(contentsOf: block) }
        try output.synchronize()
        try output.close()
        let inspected = try ConnectedTransferFile.inspect(itemURL)

        let item = ConnectedCorpusSpoolItem(
            itemID: UUID(),
            kind: .strictRawDay,
            sourceDate: sourceDate,
            isRequestedDate: true,
            file: inspected
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: sessionID,
            jobID: jobID,
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        assembler.append(item)
        let first = try XCTUnwrap(assembler.makeNextPartition())
        let second = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer {
            first.remove()
            second.remove()
        }

        XCTAssertEqual(first.descriptor.index, 0)
        XCTAssertNil(first.descriptor.previousSHA256)
        XCTAssertEqual(second.descriptor.index, 1)
        XCTAssertEqual(second.descriptor.previousSHA256, first.descriptor.sha256)
        XCTAssertLessThanOrEqual(first.file.totalBytes, ConnectedCorpusTransferConstants.maximumPartitionTargetBytes)
        XCTAssertLessThanOrEqual(second.file.totalBytes, ConnectedCorpusTransferConstants.maximumPartitionTargetBytes)
        XCTAssertEqual(first.descriptor.sourceDates, [sourceDate])
        XCTAssertEqual(second.descriptor.sourceDates, [sourceDate])
        XCTAssertFalse(assembler.hasPendingItems)

        let assemblyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-assembly-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: assemblyDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: assemblyDirectory) }
        let assembledURL = assemblyDirectory.appendingPathComponent("item")
        var completedCount = 0
        for partition in [first, second] {
            let parsed = try ConnectedCorpusPartitionReader.parseManifest(
                at: partition.file.url,
                expected: partition.descriptor
            )
            try ConnectedCorpusPartitionReader.applySegments(
                from: partition.file.url,
                parsed: parsed,
                destinationURL: { _ in assembledURL },
                completedItem: { _, _ in completedCount += 1 }
            )
        }
        let assembled = try ConnectedTransferFile.inspect(assembledURL)
        XCTAssertEqual(assembled.totalBytes, inspected.totalBytes)
        XCTAssertEqual(assembled.sha256, inspected.sha256)
        XCTAssertEqual(completedCount, 1)
    }

    func testThousandsOfTinyItemsFlushBeforeManifestLimit() throws {
        let sourceURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "tiny-corpus-item")
        try Data([0x41]).write(to: sourceURL)
        let inspected = try ConnectedTransferFile.inspect(sourceURL)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: UUID(),
            jobID: UUID(),
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        for offset in 0..<1_025 {
            assembler.append(ConnectedCorpusSpoolItem(
                itemID: UUID(),
                kind: .strictRawDay,
                sourceDate: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset * 86_400)),
                isRequestedDate: true,
                file: inspected
            ))
        }
        let partition = try XCTUnwrap(assembler.makeNextPartition())
        defer { partition.remove(); assembler.abandon() }
        XCTAssertEqual(partition.manifest.segments.count, 1_024)
        XCTAssertLessThan(partition.descriptor.byteCount, ConnectedCorpusTransferConstants.minimumPartitionTargetBytes)
    }

    func testPhysicalAggregateBeyondTwoGiBWhenLargeFixtureEnabled() throws {
        guard ProcessInfo.processInfo.environment["HEALTHMD_RUN_LARGE_CORPUS_TESTS"] == "1" else {
            throw XCTSkip("Set HEALTHMD_RUN_LARGE_CORPUS_TESTS=1 for the physical >2 GiB boundary test")
        }
        let sourceURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "over-2gib-corpus-test")
        var itemURLs = [sourceURL]
        defer { itemURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(63 * 1_024 * 1_024))
        try handle.close()
        let inspected = try ConnectedTransferFile.inspect(sourceURL)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: UUID(),
            jobID: UUID(),
            targetBytes: ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
        )
        for offset in 0..<35 {
            let itemURL: URL
            if offset == 0 {
                itemURL = sourceURL
            } else {
                itemURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("over-2gib-corpus-item-\(UUID().uuidString)")
                try FileManager.default.linkItem(at: sourceURL, to: itemURL)
                itemURLs.append(itemURL)
            }
            assembler.append(ConnectedCorpusSpoolItem(
                itemID: UUID(),
                kind: .strictRawDay,
                sourceDate: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset * 86_400)),
                isRequestedDate: true,
                file: ConnectedTransferPreparedFile(
                    url: itemURL,
                    totalBytes: inspected.totalBytes,
                    sha256: inspected.sha256
                )
            ))
        }
        var total: Int64 = 0
        var count = 0
        var previous: String?
        while let partition = try assembler.makeNextPartition(force: true) {
            XCTAssertEqual(partition.descriptor.previousSHA256, previous)
            XCTAssertLessThanOrEqual(
                partition.descriptor.byteCount,
                ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
            )
            total += partition.descriptor.byteCount
            count += 1
            previous = partition.descriptor.sha256
            partition.remove()
        }
        XCTAssertGreaterThan(total, 2 * 1_024 * 1_024 * 1_024)
        XCTAssertGreaterThan(count, 32)
    }

    func testAssemblerRejectsApplicationItemAboveHardMemoryBound() throws {
        let sourceURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "oversized-corpus-item")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(ConnectedCorpusTransferConstants.maximumItemBytes + 1))
        try handle.close()
        let inspected = try ConnectedTransferFile.inspect(sourceURL)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: UUID(),
            jobID: UUID(),
            targetBytes: ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
        )
        assembler.append(ConnectedCorpusSpoolItem(
            itemID: UUID(),
            kind: .strictRawDay,
            sourceDate: Date(timeIntervalSince1970: 1_800_000_000),
            isRequestedDate: true,
            file: inspected
        ))
        XCTAssertThrowsError(try assembler.makeNextPartition(force: true)) { error in
            XCTAssertEqual(error as? ConnectedCorpusTransferModelError, .invalidItemByteCount)
        }
    }

    func testReaderRejectsSparseItemOffsetJump() throws {
        let partitionURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "corpus-gap-partition")
        try Data([0x41]).write(to: partitionURL)
        defer { try? FileManager.default.removeItem(at: partitionURL) }
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-gap-target-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: targetURL) }
        let segment = ConnectedCorpusItemSegment(
            itemID: UUID(),
            kind: .strictRawDay,
            sourceDate: Date(timeIntervalSince1970: 1_800_000_000),
            isRequestedDate: true,
            totalItemBytes: 101,
            itemSHA256: String(repeating: "0", count: 64),
            itemOffset: 100,
            segmentBytes: 1,
            isFinalSegment: true
        )
        let parsed = ConnectedCorpusPartitionReader.ParsedManifest(
            manifest: ConnectedCorpusPartitionFileManifest(
                version: ConnectedCorpusPartitionFileManifest.currentVersion,
                sessionID: UUID(),
                jobID: UUID(),
                partitionIndex: 0,
                previousPartitionSHA256: nil,
                segments: [segment]
            ),
            payloadOffset: 0
        )
        XCTAssertThrowsError(try ConnectedCorpusPartitionReader.applySegments(
            from: partitionURL,
            parsed: parsed,
            destinationURL: { _ in targetURL },
            completedItem: { _, _ in }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
    }

    func testReaderRejectsDescriptorDigestMismatchBeforeApplyingBytes() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusRawDayPayload(sourceDate: date, day: .missing(date: "2023-11-14")),
            kind: .strictRawDay,
            sourceDate: date,
            isRequestedDate: true
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: UUID(),
            jobID: UUID(),
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let wrong = ConnectedCorpusPartitionDescriptor(
            sessionID: partition.descriptor.sessionID,
            jobID: partition.descriptor.jobID,
            index: partition.descriptor.index,
            sourceDates: partition.descriptor.sourceDates,
            byteCount: partition.descriptor.byteCount,
            sha256: String(repeating: "0", count: 64),
            previousSHA256: nil
        )
        XCTAssertThrowsError(
            try ConnectedCorpusPartitionReader.parseManifest(at: partition.file.url, expected: wrong)
        )
    }
}
