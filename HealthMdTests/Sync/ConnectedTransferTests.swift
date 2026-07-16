import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class ConnectedTransferTests: XCTestCase {
    func testSyntheticPayloadOver100MiBUsesBoundedTransportFramesAndDiskSpool() throws {
        let sourceURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "100mb-test")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let handle = try FileHandle(forWritingTo: sourceURL)
        let block = Data(repeating: 0x5a, count: ConnectedTransferReceiver.maximumChunkBytes)
        let targetBytes = 100 * 1_024 * 1_024 + 1
        var remaining = targetBytes
        while remaining > 0 {
            try handle.write(contentsOf: block.prefix(min(block.count, remaining)))
            remaining -= min(block.count, remaining)
        }
        try handle.close()

        let prepared = try ConnectedTransferFile.inspect(sourceURL)
        XCTAssertGreaterThan(prepared.totalBytes, Int64(100 * 1_024 * 1_024))
        let transferID = UUID()
        let start = makeStart(prepared: prepared, transferID: transferID)
        let receiver = ConnectedTransferReceiver(inactivityTimeout: 0)
        assertAccepted(receiver.receive(start), sequence: 0)

        let reader = try FileHandle(forReadingFrom: sourceURL)
        defer { try? reader.close() }
        var maximumEncodedFrameBytes = 0
        for sequence in 1...start.totalChunks {
            let bytes = try XCTUnwrap(reader.read(upToCount: start.chunkBytes))
            let chunk = ConnectedTransferChunk(
                transferID: transferID,
                sequence: sequence,
                data: bytes,
                sha256: ConnectedTransferFile.sha256Hex(bytes)
            )
            let frameBytes = try JSONEncoder().encode(SyncMessage.connectedTransferChunk(chunk)).count
            maximumEncodedFrameBytes = max(maximumEncodedFrameBytes, frameBytes)
            XCTAssertLessThan(frameBytes, 1_000_000)
            assertAccepted(receiver.receive(chunk), sequence: sequence)
        }

        let complete = ConnectedTransferComplete(
            transferID: transferID,
            totalBytes: prepared.totalBytes,
            totalChunks: start.totalChunks,
            sha256: prepared.sha256
        )
        guard case .ready(let ready) = receiver.receive(complete) else {
            return XCTFail("Expected verified ready transfer")
        }
        let received = try ConnectedTransferFile.inspect(ready.fileURL)
        XCTAssertEqual(received.totalBytes, prepared.totalBytes)
        XCTAssertEqual(received.sha256, prepared.sha256)
        XCTAssertLessThan(maximumEncodedFrameBytes, ManualIPSyncSecurity.maxFrameSize)
        XCTAssertNotNil(receiver.finish(transferID: transferID, accepted: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ready.fileURL.path))
    }

    func testRejectsDeclaredSizeChunkCountSequenceChunkHashAndFinalHash() throws {
        let receiver = ConnectedTransferReceiver(inactivityTimeout: 0)
        let id = UUID()
        let oversized = ConnectedTransferStart(
            protocolVersion: 1,
            transferID: id,
            manifest: manifest(id),
            totalBytes: ConnectedTransferReceiver.maximumTotalBytes + 1,
            totalChunks: 1,
            chunkBytes: 1,
            sha256: String(repeating: "0", count: 64)
        )
        guard case .abort(let sizeAbort) = receiver.receive(oversized) else {
            return XCTFail("Expected size rejection")
        }
        XCTAssertEqual(sizeAbort.reason, .sizeLimit)

        let bytes = Data("abcdefghij".utf8)
        let prepared = try preparedFile(bytes)
        defer { prepared.remove() }
        var start = makeStart(prepared: prepared, transferID: id, chunkBytes: 5)
        start = ConnectedTransferStart(
            protocolVersion: start.protocolVersion,
            transferID: start.transferID,
            manifest: start.manifest,
            totalBytes: start.totalBytes,
            totalChunks: start.totalChunks + 1,
            chunkBytes: start.chunkBytes,
            sha256: start.sha256
        )
        guard case .abort = receiver.receive(start) else {
            return XCTFail("Expected chunk-count rejection")
        }

        let validStart = makeStart(prepared: prepared, transferID: id, chunkBytes: 5)
        assertAccepted(receiver.receive(validStart), sequence: 0)
        let second = Data(bytes[5..<10])
        guard case .abort(let sequenceAbort) = receiver.receive(ConnectedTransferChunk(
            transferID: id,
            sequence: 2,
            data: second,
            sha256: ConnectedTransferFile.sha256Hex(second)
        )) else { return XCTFail("Expected sequence rejection") }
        XCTAssertEqual(sequenceAbort.reason, .sequenceMismatch)
        XCTAssertTrue(receiver.activeTransferIDs.isEmpty)

        assertAccepted(receiver.receive(validStart), sequence: 0)
        let first = Data(bytes[0..<5])
        guard case .abort(let hashAbort) = receiver.receive(ConnectedTransferChunk(
            transferID: id,
            sequence: 1,
            data: first,
            sha256: String(repeating: "0", count: 64)
        )) else { return XCTFail("Expected chunk hash rejection") }
        XCTAssertEqual(hashAbort.reason, .chunkHashMismatch)

        let falseDigest = String(repeating: "f", count: 64)
        let falseDigestStart = ConnectedTransferStart(
            protocolVersion: validStart.protocolVersion,
            transferID: validStart.transferID,
            manifest: validStart.manifest,
            totalBytes: validStart.totalBytes,
            totalChunks: validStart.totalChunks,
            chunkBytes: validStart.chunkBytes,
            sha256: falseDigest
        )
        assertAccepted(receiver.receive(falseDigestStart), sequence: 0)
        assertAccepted(receiver.receive(ConnectedTransferChunk(
            transferID: id,
            sequence: 1,
            data: first,
            sha256: ConnectedTransferFile.sha256Hex(first)
        )), sequence: 1)
        assertAccepted(receiver.receive(ConnectedTransferChunk(
            transferID: id,
            sequence: 2,
            data: second,
            sha256: ConnectedTransferFile.sha256Hex(second)
        )), sequence: 2)
        guard case .abort(let finalAbort) = receiver.receive(ConnectedTransferComplete(
            transferID: id,
            totalBytes: prepared.totalBytes,
            totalChunks: 2,
            sha256: falseDigest
        )) else { return XCTFail("Expected final digest rejection") }
        XCTAssertEqual(finalAbort.reason, .finalHashMismatch)
        XCTAssertTrue(receiver.activeTransferIDs.isEmpty)
    }

    func testDuplicateChunkWithSameDigestReplaysPriorAcknowledgement() throws {
        let bytes = Data("0123456789".utf8)
        let prepared = try preparedFile(bytes)
        defer { prepared.remove() }
        let id = UUID()
        let start = makeStart(prepared: prepared, transferID: id, chunkBytes: 5)
        let receiver = ConnectedTransferReceiver(inactivityTimeout: 0)
        assertAccepted(receiver.receive(start), sequence: 0)
        assertAccepted(receiver.receive(start), sequence: 0)

        let firstBytes = Data(bytes.prefix(5))
        let first = ConnectedTransferChunk(
            transferID: id,
            sequence: 1,
            data: firstBytes,
            sha256: ConnectedTransferFile.sha256Hex(firstBytes)
        )
        let firstAck = acceptedAck(receiver.receive(first))
        let replayedAck = acceptedAck(receiver.receive(first))
        XCTAssertEqual(replayedAck, firstAck)

        let secondBytes = Data(bytes.suffix(5))
        assertAccepted(receiver.receive(ConnectedTransferChunk(
            transferID: id,
            sequence: 2,
            data: secondBytes,
            sha256: ConnectedTransferFile.sha256Hex(secondBytes)
        )), sequence: 2)
        guard case .ready = receiver.receive(ConnectedTransferComplete(
            transferID: id,
            totalBytes: prepared.totalBytes,
            totalChunks: 2,
            sha256: prepared.sha256
        )) else { return XCTFail("Expected successful reassembly after duplicate") }
    }

    func testDisconnectAndTimeoutDeleteRestrictedSpoolFiles() async throws {
        let bytes = Data("cleanup".utf8)
        let prepared = try preparedFile(bytes)
        defer { prepared.remove() }
        let firstID = UUID()
        let receiver = ConnectedTransferReceiver(inactivityTimeout: 0)
        assertAccepted(receiver.receive(makeStart(prepared: prepared, transferID: firstID)), sequence: 0)
        let firstURL = try XCTUnwrap(receiver.spooledFileURL(for: firstID))
        let permissions = try FileManager.default.attributesOfItem(atPath: firstURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        receiver.cancelAll(reason: .disconnected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))

        let timeoutExpectation = expectation(description: "timeout abort")
        let timedReceiver = ConnectedTransferReceiver(inactivityTimeout: 0.02)
        timedReceiver.onTimeout = { abort in
            XCTAssertEqual(abort.reason, .timedOut)
            timeoutExpectation.fulfill()
        }
        let secondID = UUID()
        assertAccepted(timedReceiver.receive(makeStart(prepared: prepared, transferID: secondID)), sequence: 0)
        let secondURL = try XCTUnwrap(timedReceiver.spooledFileURL(for: secondID))
        await fulfillment(of: [timeoutExpectation], timeout: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(timedReceiver.activeTransferIDs.isEmpty)
    }

    func testFinalAcceptanceAckExistsOnlyAfterDigestValidationAndApplicationAcceptance() throws {
        let bytes = Data("accepted only after decode".utf8)
        let prepared = try preparedFile(bytes)
        defer { prepared.remove() }
        let id = UUID()
        let start = makeStart(prepared: prepared, transferID: id, chunkBytes: 8)
        let receiver = ConnectedTransferReceiver(inactivityTimeout: 0)
        assertAccepted(receiver.receive(start), sequence: 0)
        try feed(prepared.url, start: start, receiver: receiver)

        XCTAssertNil(receiver.finish(transferID: id, accepted: true), "No final ACK before completion digest validation")
        let complete = ConnectedTransferComplete(
            transferID: id,
            totalBytes: prepared.totalBytes,
            totalChunks: start.totalChunks,
            sha256: prepared.sha256
        )
        guard case .ready(let ready) = receiver.receive(complete) else {
            return XCTFail("Expected ready transfer")
        }
        XCTAssertEqual(try Data(contentsOf: ready.fileURL), bytes, "Application can decode only after digest validation")
        let final = try XCTUnwrap(receiver.finish(transferID: id, accepted: true))
        XCTAssertTrue(final.accepted)
        guard case .replay(let replay) = receiver.receive(complete) else {
            return XCTFail("A retried completion must replay the final ACK")
        }
        XCTAssertEqual(replay, final)
    }

    func testLargeSingleDayMacJobReassemblesAcrossByteChunks() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var health = HealthData(date: date)
        health.activity.steps = 123
        let attachment = String(repeating: "binary-like-attachment-", count: 140_000)
        let external = ExternalDailyRecord(
            provider: .whoop,
            date: "2027-01-15",
            payloads: [ExternalProviderPayload(
                name: "large_attachment",
                endpoint: "https://example.invalid/attachment",
                statusCode: 200,
                data: .object(["content": .string(attachment)])
            )]
        )
        let jobID = UUID()
        let job = MacExportJob(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "Test iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            records: [health],
            externalDailyRecords: [external],
            settingsSnapshot: makeSettingsSnapshot(),
            requestedTarget: nil
        )
        let prepared = try ConnectedTransferFile.encode(job)
        defer { prepared.remove() }
        XCTAssertGreaterThan(prepared.totalBytes, Int64(ConnectedTransferReceiver.maximumChunkBytes))
        let start = makeStart(prepared: prepared, transferID: jobID, kind: .macExportJobV1)
        let receiver = ConnectedTransferReceiver(inactivityTimeout: 0)
        assertAccepted(receiver.receive(start), sequence: 0)
        try feed(prepared.url, start: start, receiver: receiver)
        guard case .ready(let ready) = receiver.receive(ConnectedTransferComplete(
            transferID: jobID,
            totalBytes: prepared.totalBytes,
            totalChunks: start.totalChunks,
            sha256: prepared.sha256
        )) else { return XCTFail("Expected reassembled Mac job") }
        let decoded = try JSONDecoder().decode(MacExportJob.self, from: Data(contentsOf: ready.fileURL))
        XCTAssertEqual(decoded.jobID, jobID)
        guard case .object(let object) = decoded.externalDailyRecords.first?.payloads.first?.data,
              case .string(let decodedAttachment) = object["content"] else {
            return XCTFail("Expected inline reassembled attachment")
        }
        XCTAssertEqual(decodedAttachment, attachment)
    }

    func testScheduledCapabilityRequiresNegotiatedSizeBoundedStreaming() {
        let legacy = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "legacy",
            buildNumber: "1",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsIPhoneExportRequests: true,
            supportsChunkedMacExportJobs: true
        )
        XCTAssertFalse(legacy.supportsScheduledConnectedMacExports)
        XCTAssertTrue(SyncPeerCapabilities.current(platform: .macOS).supportsScheduledConnectedMacExports)
    }

    private func feed(
        _ sourceURL: URL,
        start: ConnectedTransferStart,
        receiver: ConnectedTransferReceiver
    ) throws {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        if start.totalChunks > 0 {
            for sequence in 1...start.totalChunks {
                let data = try XCTUnwrap(handle.read(upToCount: start.chunkBytes))
                assertAccepted(receiver.receive(ConnectedTransferChunk(
                    transferID: start.transferID,
                    sequence: sequence,
                    data: data,
                    sha256: ConnectedTransferFile.sha256Hex(data)
                )), sequence: sequence)
            }
        }
    }

    private func preparedFile(_ data: Data) throws -> ConnectedTransferPreparedFile {
        let url = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "fixture")
        try data.write(to: url)
        return try ConnectedTransferFile.inspect(url)
    }

    private func makeStart(
        prepared: ConnectedTransferPreparedFile,
        transferID: UUID,
        chunkBytes: Int = ConnectedTransferReceiver.maximumChunkBytes,
        kind: ConnectedTransferKind = .canonicalRawResultV1
    ) -> ConnectedTransferStart {
        ConnectedTransferStart(
            protocolVersion: ConnectedTransferStart.currentProtocolVersion,
            transferID: transferID,
            manifest: ConnectedTransferManifest(
                kind: kind,
                jobID: transferID,
                payloadSchemaVersion: 1
            ),
            totalBytes: prepared.totalBytes,
            totalChunks: prepared.totalBytes == 0
                ? 0
                : Int((prepared.totalBytes + Int64(chunkBytes) - 1) / Int64(chunkBytes)),
            chunkBytes: chunkBytes,
            sha256: prepared.sha256
        )
    }

    private func manifest(_ id: UUID) -> ConnectedTransferManifest {
        ConnectedTransferManifest(kind: .canonicalRawResultV1, jobID: id, payloadSchemaVersion: 1)
    }

    private func acceptedAck(_ result: ConnectedTransferReceiver.ChunkResult) -> ConnectedTransferAck {
        guard case .acknowledgement(let acknowledgement) = result else {
            XCTFail("Expected accepted chunk acknowledgement")
            return ConnectedTransferAck(
                transferID: UUID(),
                sequence: -1,
                accepted: false,
                sha256: "",
                message: nil
            )
        }
        XCTAssertTrue(acknowledgement.accepted)
        return acknowledgement
    }

    private func assertAccepted(
        _ result: ConnectedTransferReceiver.StartResult,
        sequence: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .acknowledgement(let acknowledgement) = result else {
            return XCTFail("Expected accepted start", file: file, line: line)
        }
        XCTAssertTrue(acknowledgement.accepted, file: file, line: line)
        XCTAssertEqual(acknowledgement.sequence, sequence, file: file, line: line)
    }

    private func assertAccepted(
        _ result: ConnectedTransferReceiver.ChunkResult,
        sequence: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .acknowledgement(let acknowledgement) = result else {
            return XCTFail("Expected accepted chunk", file: file, line: line)
        }
        XCTAssertTrue(acknowledgement.accepted, file: file, line: line)
        XCTAssertEqual(acknowledgement.sequence, sequence, file: file, line: line)
    }

    private func makeSettingsSnapshot() -> ExportSettingsSnapshot {
        let suite = "ConnectedTransferTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.exportFormats = [.json]
        return .from(settings)
    }
}
