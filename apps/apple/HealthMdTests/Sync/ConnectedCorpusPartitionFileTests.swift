import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class ConnectedCorpusPartitionFileTests: XCTestCase {
    private struct LargeStringPayload: Codable {
        let value: String
    }

    func testCorpusProtocolsOneThroughThreeRetainExactSortedJSONItemBytes() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = ConnectedCorpusRawDayPayload(
            sourceDate: date,
            day: .missing(date: "2023-11-14")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expected = try encoder.encode(payload)
        for version in 1...ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion {
            let item = try ConnectedCorpusSpoolItem.encode(
                payload,
                kind: .strictRawDay,
                sourceDate: date,
                isRequestedDate: true,
                protocolVersion: version
            )
            defer { item.remove() }
            XCTAssertEqual(try Data(contentsOf: item.file.url), expected, "protocol v\(version)")
            XCTAssertEqual(item.file.totalBytes, 334, "protocol v\(version) fixture length")
            XCTAssertEqual(
                item.file.sha256,
                "6bc3bec26eca6e246d93539ad6235a884926a7124ca1c2517055ffa44f39a80f",
                "protocol v\(version) compatibility vector"
            )
        }
    }

    func testStreamableApplicationItemV4ImmutableVectors() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let health = try ConnectedCorpusApplicationItemCodec.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: true,
                record: nil,
                externalDailyRecords: [],
                failure: nil
            ),
            kind: .macHealthDay
        )
        defer { health.remove() }
        let raw = try ConnectedCorpusApplicationItemCodec.encode(
            ConnectedCorpusRawDayPayload(
                sourceDate: date,
                day: .missing(date: "2023-11-14")
            ),
            kind: .strictRawDay
        )
        defer { raw.remove() }

        XCTAssertEqual(health.totalBytes, 150)
        XCTAssertEqual(
            health.sha256,
            "03c954a05d5b0f9eee8bb2f6a785f111969e2958fd52d12e414da2cc278f8a99"
        )
        XCTAssertEqual(raw.totalBytes, 721)
        XCTAssertEqual(
            raw.sha256,
            "fd4be6ebd2204e5efdcaa8d9c1e4e811e9958d831376c2588a4919f550422559"
        )
    }

    func testStreamableApplicationItemHealthDayRoundTripsWithoutJSONEnvelope() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: date,
            isRequestedDate: true,
            record: HealthData(
                date: date,
                timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "America/New_York"),
                heart: HeartData(
                    averageHeartRate: 72,
                    heartRateSamples: [
                        TimeSample(timestamp: date, value: 71, metadata: ["source": "watch"]),
                        TimeSample(timestamp: date.addingTimeInterval(30), value: 73)
                    ]
                )
            ),
            externalDailyRecords: [],
            failure: nil
        )
        let file = try ConnectedCorpusApplicationItemCodec.encode(payload, kind: .macHealthDay)
        defer { file.remove() }
        let repeated = try ConnectedCorpusApplicationItemCodec.encode(payload, kind: .macHealthDay)
        defer { repeated.remove() }
        XCTAssertEqual(file.sha256, repeated.sha256)
        XCTAssertEqual(try Data(contentsOf: file.url), try Data(contentsOf: repeated.url))
        XCTAssertEqual(try Data(contentsOf: file.url).prefix(8), Data("HMDCITEM".utf8))
        let decoded = try ConnectedCorpusApplicationItemCodec.decode(
            ConnectedCorpusHealthDayPayload.self,
            from: file.url,
            expectedKind: .macHealthDay
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(try encoder.encode(decoded), try encoder.encode(payload))
    }

    func testStreamableApplicationItemRawDayCopiesCanonicalStringToDisk() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let canonical = "{\n  \"schema\" : \"healthmd.health_data\",\n  \"schema_version\" : 7,\n  \"text\" : \"héalth 🫀\"\n}"
        var queryCounts = CanonicalRawQueryStatusCounts()
        queryCounts.success = 1
        let day = CanonicalRawDayResult(
            date: "2023-11-14",
            status: .complete,
            captureStatus: .complete,
            sampleCount: 2,
            recordCount: 2,
            queryStatusCounts: queryCounts,
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: nil,
            canonicalDailyJSON: canonical
        )
        let file = try ConnectedCorpusApplicationItemCodec.encode(
            ConnectedCorpusRawDayPayload(sourceDate: date, day: day),
            kind: .strictRawDay
        )
        defer { file.remove() }
        let decoded = try ConnectedCorpusApplicationItemCodec.decodeRawDay(from: file.url)
        defer { decoded.canonicalJSONFile?.remove() }
        XCTAssertEqual(decoded.sourceDate, date)
        XCTAssertNil(decoded.day.canonicalDailyJSON)
        XCTAssertEqual(decoded.day.date, day.date)
        XCTAssertEqual(decoded.day.status, day.status)
        XCTAssertEqual(
            try decoded.canonicalJSONFile.map { try String(contentsOf: $0.url, encoding: .utf8) },
            canonical
        )
    }

    func testStreamableRawApplicationItemHasBoundedCodecRSSForLargeLogicalItem() throws {
        let canonicalURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "large-canonical-production-item"
        )
        let canonicalOutput = try FileHandle(forWritingTo: canonicalURL)
        try canonicalOutput.write(contentsOf: Data("{\"padding\":\"".utf8))
        let block = Data(repeating: 0x78, count: 1 * 1_024 * 1_024)
        for _ in 0..<72 { try canonicalOutput.write(contentsOf: block) }
        try canonicalOutput.write(contentsOf: Data("\"}".utf8))
        try canonicalOutput.synchronize()
        try canonicalOutput.close()
        let canonicalFile = try ConnectedTransferFile.inspect(canonicalURL)
        defer { canonicalFile.remove() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let captured = CanonicalRawCapturedDaySpool(
            day: CanonicalRawDayResult(
                date: "2023-11-14",
                status: .complete,
                captureStatus: .complete,
                sampleCount: 1,
                recordCount: 1,
                queryStatusCounts: .init(),
                integrityWarningCount: 0,
                integrityWarningCodes: [],
                partialFailureCount: 0,
                partialFailureTypes: [],
                failureCode: nil,
                canonicalDailyJSON: nil
            ),
            canonicalJSONFile: canonicalFile
        )
        let baseline = residentBytes()
        let sampler = ResidentSampler()
        sampler.start()
        let item = try ConnectedCorpusSpoolItem.encodeRawDay(
            sourceDate: date,
            captured: captured,
            protocolVersion: ConnectedCorpusTransferCapabilities.streamableItemProtocolVersion
        )
        sampler.stop()
        defer { item.remove() }
        let encodeOverhead = sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0
        XCTAssertLessThan(
            encodeOverhead,
            40 * 1_024 * 1_024,
            "Encoding must not create an item-sized JSON Data copy"
        )
        XCTAssertGreaterThan(item.file.totalBytes, canonicalFile.totalBytes)

        let decodeBaseline = residentBytes()
        let decodeSampler = ResidentSampler()
        decodeSampler.start()
        let decoded = try ConnectedCorpusApplicationItemCodec.decodeRawDay(
            from: item.file.url,
            extractCanonicalJSON: false
        )
        decodeSampler.stop()
        let decodeOverhead = decodeSampler.peakBytes > decodeBaseline
            ? decodeSampler.peakBytes - decodeBaseline : 0
        XCTAssertTrue(decoded.hasCanonicalJSON)
        XCTAssertNil(decoded.day.canonicalDailyJSON)
        XCTAssertLessThan(
            decodeOverhead,
            32 * 1_024 * 1_024,
            "Selective decode must leave canonical JSON disk-backed"
        )

        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: UUID(),
            jobID: UUID(),
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        assembler.append(item)
        var partitions: [ConnectedCorpusPreparedPartition] = []
        while let partition = try assembler.makeNextPartition(force: true) {
            partitions.append(partition)
        }
        defer { partitions.forEach { $0.remove() } }
        XCTAssertFalse(assembler.hasPendingItems)
        XCTAssertGreaterThanOrEqual(partitions.count, 3)
        XCTAssertEqual(partitions.first?.manifest.segments.first?.isFinalSegment, false)
        XCTAssertEqual(partitions.last?.manifest.segments.first?.isFinalSegment, true)
    }

    func testStreamableDecoderMapsLargeProductionHealthDayDataWithoutItemSizedRSSCopy() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ownership = HealthKitDailyOwnershipMetadata(
            ownerDate: "2023-11-14",
            intervalStart: date,
            intervalEnd: date.addingTimeInterval(86_400),
            calendarTimeZoneIdentifier: "UTC"
        )
        var source: ConnectedCorpusHealthDayPayload? = ConnectedCorpusHealthDayPayload(
            sourceDate: date,
            isRequestedDate: true,
            record: HealthData(
                date: date,
                timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
                healthKitRecordArchive: HealthKitRecordArchive(
                    captureStatus: .complete,
                    dailyOwnership: ownership,
                    records: [HealthKitRecord(
                        originalUUID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                        objectTypeIdentifier: "HKDocumentTypeIdentifierCDA",
                        recordKind: .document,
                        selectedMetricIDs: ["clinical_records"],
                        includedBecause: .selectedMetric,
                        startDate: date,
                        endDate: date,
                        sourceRevision: HealthKitSourceRevision(
                            name: "Health",
                            bundleIdentifier: "com.apple.Health"
                        ),
                        metadata: [
                            "large_fixture": .data(Data(
                                repeating: 0x5a,
                                count: 72 * 1_024 * 1_024
                            ))
                        ],
                        payload: .unknown(kind: "document", fields: [:])
                    )]
                ),
                healthKitRecordCaptureStatus: .complete
            ),
            externalDailyRecords: [],
            failure: nil
        )
        let encodeBaseline = residentBytes()
        let encodeSampler = ResidentSampler()
        encodeSampler.start()
        let file = try ConnectedCorpusApplicationItemCodec.encode(
            try XCTUnwrap(source),
            kind: .macHealthDay
        )
        encodeSampler.stop()
        defer { file.remove() }
        let encodeOverhead = encodeSampler.peakBytes > encodeBaseline
            ? encodeSampler.peakBytes - encodeBaseline : 0
        XCTAssertLessThan(
            encodeOverhead,
            32 * 1_024 * 1_024,
            "Production HealthData encoding must not create an item-sized Data copy"
        )
        source = nil

        let baseline = residentBytes()
        let sampler = ResidentSampler()
        sampler.start()
        let decoded = try ConnectedCorpusApplicationItemCodec.decode(
            ConnectedCorpusHealthDayPayload.self,
            from: file.url,
            expectedKind: .macHealthDay
        )
        sampler.stop()
        let overhead = sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0
        guard case .data(let blob) = decoded.record?
            .healthKitRecordArchive?.records.first?.metadata["large_fixture"] else {
            return XCTFail("Expected the production HealthData metadata blob")
        }
        XCTAssertEqual(blob.count, 72 * 1_024 * 1_024)
        XCTAssertEqual(blob.first, 0x5a)
        XCTAssertLessThan(
            overhead,
            32 * 1_024 * 1_024,
            "Large production HealthData tokens must remain file-backed during decode"
        )
    }

    func testStreamableDecoderBuildsLargeStringWithOnlyBoundedTransientRSS() throws {
        let source = String(repeating: "é", count: 36 * 1_024 * 1_024)
        let file = try ConnectedCorpusApplicationItemCodec.encode(
            LargeStringPayload(value: source),
            kind: .macHealthDay
        )
        defer { file.remove() }

        let baseline = residentBytes()
        let sampler = ResidentSampler()
        sampler.start()
        let decoded = try ConnectedCorpusApplicationItemCodec.decode(
            LargeStringPayload.self,
            from: file.url,
            expectedKind: .macHealthDay
        )
        sampler.stop()
        let overhead = sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0
        XCTAssertEqual(decoded.value.utf8.count, 72 * 1_024 * 1_024)
        XCTAssertEqual(decoded.value.first, "é")
        XCTAssertLessThan(
            overhead,
            112 * 1_024 * 1_024,
            "String decode may allocate the required String, not another item-sized Data"
        )
        withExtendedLifetime(source) {}
    }

    func testStreamableApplicationItemRejectsInflatedArrayCountBeforeAllocation() throws {
        let file = try ConnectedCorpusApplicationItemCodec.encode(
            [Int](),
            kind: .macHealthDay
        )
        defer { file.remove() }
        let output = try FileHandle(forWritingTo: file.url)
        try output.seek(toOffset: 21) // 12-byte item header + 9-byte root-token header
        try output.write(contentsOf: Data(repeating: 0xff, count: 8))
        try output.close()
        XCTAssertThrowsError(try ConnectedCorpusApplicationItemCodec.decode(
            [Int].self,
            from: file.url,
            expectedKind: .macHealthDay
        ))
    }

    func testStreamableApplicationItemRejectsKindMismatchAndTrailingBytes() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let file = try ConnectedCorpusApplicationItemCodec.encode(
            ConnectedCorpusRawDayPayload(sourceDate: date, day: .missing(date: "2023-11-14")),
            kind: .strictRawDay
        )
        defer { file.remove() }
        XCTAssertThrowsError(try ConnectedCorpusApplicationItemCodec.decode(
            ConnectedCorpusRawDayPayload.self,
            from: file.url,
            expectedKind: .macHealthDay
        ))
        let handle = try FileHandle(forWritingTo: file.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        XCTAssertThrowsError(try ConnectedCorpusApplicationItemCodec.decode(
            ConnectedCorpusRawDayPayload.self,
            from: file.url,
            expectedKind: .strictRawDay
        ))
    }

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

    func testAssemblerSegmentsApplicationItemBeyondLegacySixtyFourMiBBoundary() throws {
        let sourceURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "dense-corpus-item")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(64 * ConnectedCorpusTransferConstants.mebibyte + 1))
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

        var partitions = 0
        while let partition = try assembler.makeNextPartition(force: true) {
            partitions += 1
            XCTAssertLessThanOrEqual(
                partition.descriptor.byteCount,
                ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
            )
            partition.remove()
        }
        XCTAssertEqual(partitions, 2)
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

    func testReaderRejectsSymlinkedDestinationDirectory() throws {
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
        let parsed = try ConnectedCorpusPartitionReader.parseManifest(
            at: partition.file.url,
            expected: partition.descriptor
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-reader-root-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-reader-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let linkedDirectory = root.appendingPathComponent("items", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: outside)
        let outsideItem = outside.appendingPathComponent("item")

        XCTAssertThrowsError(try ConnectedCorpusPartitionReader.applySegments(
            from: partition.file.url,
            parsed: parsed,
            destinationURL: { _ in linkedDirectory.appendingPathComponent("item") },
            completedItem: { _, _ in }
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideItem.path))
    }

    func testReaderRejectsHardLinkedDestinationFile() throws {
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
        let parsed = try ConnectedCorpusPartitionReader.parseManifest(
            at: partition.file.url,
            expected: partition.descriptor
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-reader-hardlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outside = directory.appendingPathComponent("outside")
        let target = directory.appendingPathComponent("target")
        let original = Data("outside-data".utf8)
        try original.write(to: outside)
        try FileManager.default.linkItem(at: outside, to: target)

        XCTAssertThrowsError(try ConnectedCorpusPartitionReader.applySegments(
            from: partition.file.url,
            parsed: parsed,
            destinationURL: { _ in target },
            completedItem: { _, _ in }
        ))
        XCTAssertEqual(try Data(contentsOf: outside), original)
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

    private func residentBytes() -> UInt64 {
        Self.currentResidentBytes()
    }

    nonisolated private static func currentResidentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    private final class ResidentSampler {
        private let lock = NSLock()
        private var running = false
        private var peak: UInt64 = 0
        private let group = DispatchGroup()

        var peakBytes: UInt64 {
            lock.lock(); defer { lock.unlock() }
            return peak
        }

        func start() {
            lock.lock()
            running = true
            peak = ConnectedCorpusPartitionFileTests.currentResidentBytes()
            lock.unlock()
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                defer { group.leave() }
                while true {
                    lock.lock()
                    let shouldContinue = running
                    peak = max(
                        peak,
                        ConnectedCorpusPartitionFileTests.currentResidentBytes()
                    )
                    lock.unlock()
                    if !shouldContinue { return }
                    usleep(2_000)
                }
            }
        }

        func stop() {
            lock.lock()
            running = false
            peak = max(peak, ConnectedCorpusPartitionFileTests.currentResidentBytes())
            lock.unlock()
            group.wait()
        }
    }
}
