import XCTest
@testable import HealthMd

final class ConnectedCorpusTransferProtocolTests: XCTestCase {
    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)
    private let digestC = String(repeating: "c", count: 64)

    func testProtocolMessagesAndJournalRoundTrip() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceDates = [
            createdAt,
            createdAt.addingTimeInterval(86_400)
        ]
        let fingerprint = ConnectedCorpusRequestFingerprint(sha256: digestC)
        let session = ConnectedCorpusTransferSession(
            sessionID: sessionID,
            jobID: jobID,
            requestFingerprint: fingerprint,
            partitionTargetBytes: ConnectedCorpusTransferConstants.defaultPartitionTargetBytes,
            createdAt: createdAt
        )
        let first = ConnectedCorpusPartitionDescriptor(
            sessionID: sessionID,
            jobID: jobID,
            index: 0,
            sourceDates: [sourceDates[0]],
            byteCount: 40_000_000,
            sha256: digestA,
            previousSHA256: nil
        )
        let second = ConnectedCorpusPartitionDescriptor(
            sessionID: sessionID,
            jobID: jobID,
            index: 1,
            sourceDates: [sourceDates[1]],
            byteCount: 20_000_000,
            sha256: digestB,
            previousSHA256: digestA
        )

        try assertRoundTrip(.connectedCorpusTransferOpen(.init(session: session, partition: first))) { message in
            guard case .connectedCorpusTransferOpen(let open) = message else {
                return XCTFail("Expected corpus open")
            }
            XCTAssertEqual(open.session, session)
            XCTAssertEqual(open.partition.exactSourceDates, [sourceDates[0]])
            XCTAssertEqual(open.partition.partitionIndex, 0)
        }
        try assertRoundTrip(.connectedCorpusTransferDisposition(.init(
            sessionID: sessionID,
            jobID: jobID,
            partitionIndex: 0,
            partitionSHA256: digestA,
            disposition: .accept,
            nextPartitionIndex: 0
        ))) { message in
            guard case .connectedCorpusTransferDisposition(let disposition) = message else {
                return XCTFail("Expected corpus disposition")
            }
            XCTAssertEqual(disposition.disposition, .accept)
        }
        try assertRoundTrip(.connectedCorpusTransferFinalize(.init(
            sessionID: sessionID,
            jobID: jobID,
            requestFingerprint: fingerprint,
            partitionCount: 2,
            totalByteCount: 60_000_000,
            finalPartitionSHA256: digestB
        ))) { message in
            guard case .connectedCorpusTransferFinalize(let finalize) = message else {
                return XCTFail("Expected corpus finalize")
            }
            XCTAssertEqual(finalize.partitionCount, 2)
        }
        try assertRoundTrip(.connectedCorpusTransferFinalAck(.init(
            sessionID: sessionID,
            jobID: jobID,
            accepted: true,
            requestFingerprint: fingerprint,
            finalPartitionSHA256: digestB,
            message: nil
        ))) { message in
            guard case .connectedCorpusTransferFinalAck(let acknowledgement) = message else {
                return XCTFail("Expected corpus final acknowledgement")
            }
            XCTAssertTrue(acknowledgement.accepted)
        }
        try assertRoundTrip(.connectedCorpusTransferCancel(.init(
            sessionID: sessionID,
            jobID: jobID,
            reason: .userRequested,
            message: "Cancelled by user.",
            requestedAt: createdAt
        ))) { message in
            guard case .connectedCorpusTransferCancel(let cancel) = message else {
                return XCTFail("Expected corpus cancellation")
            }
            XCTAssertEqual(cancel.reason, .userRequested)
        }
        try assertRoundTrip(.connectedCorpusTransferCancelAck(.init(
            sessionID: sessionID,
            jobID: jobID,
            accepted: true,
            acknowledgedAt: createdAt,
            message: nil
        ))) { message in
            guard case .connectedCorpusTransferCancelAck(let acknowledgement) = message else {
                return XCTFail("Expected corpus cancellation acknowledgement")
            }
            XCTAssertTrue(acknowledgement.accepted)
        }

        let journal = ConnectedCorpusTransferJournal(
            session: session,
            state: .open,
            partitions: [
                ConnectedCorpusPartitionJournal(descriptor: first, state: .committed, updatedAt: createdAt),
                ConnectedCorpusPartitionJournal(descriptor: second, state: .pending, updatedAt: createdAt)
            ],
            updatedAt: createdAt
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ConnectedCorpusTransferJournal.self,
                from: JSONEncoder().encode(journal)
            ),
            journal
        )

        requireSendable(session)
        requireSendable(first)
        requireSendable(journal)
    }

    func testLegacyCapabilityPayloadDefaultsPartitionedCorpusSupportOff() throws {
        let legacyJSON = """
        {
          "protocolVersion": 2,
          "appVersion": "2.0",
          "buildNumber": "200",
          "platform": "macOS",
          "supportsMacExportJobs": true,
          "supportsMacDestinationStatus": true,
          "supportsJobCancellation": true,
          "supportsGranularPayloads": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SyncPeerCapabilities.self, from: legacyJSON)

        XCTAssertFalse(decoded.supportsPartitionedConnectedExports)
        XCTAssertFalse(decoded.supportsPartitionedConnectedTransfers)
        XCTAssertNil(decoded.connectedCorpusTransferCapabilities)
        XCTAssertNil(decoded.negotiateConnectedCorpusTransfer(with: .current(platform: .iOS)))
    }

    func testCapabilityNegotiationUses48MiBDefaultAndSharedBounds() {
        let currentIOS = SyncPeerCapabilities.current(platform: .iOS)
        let currentMac = SyncPeerCapabilities.current(platform: .macOS)
        XCTAssertEqual(
            currentIOS.negotiateConnectedCorpusTransfer(with: currentMac),
            ConnectedCorpusTransferNegotiation(
                protocolVersion: ConnectedCorpusTransferCapabilities.currentProtocolVersion,
                partitionTargetBytes: 48 * 1_024 * 1_024
            )
        )

        let smallerPreference = makePeer(capabilities: ConnectedCorpusTransferCapabilities(
            protocolVersions: [1],
            partitionTargetBounds: ConnectedCorpusPartitionTargetBounds(
                minimumBytes: 32 * 1_024 * 1_024,
                preferredBytes: 40 * 1_024 * 1_024,
                maximumBytes: 40 * 1_024 * 1_024
            )
        ))
        XCTAssertEqual(
            currentIOS.negotiateConnectedCorpusTransfer(with: smallerPreference)?.partitionTargetBytes,
            40 * 1_024 * 1_024
        )

        let sixtyFourOnly = makePeer(capabilities: ConnectedCorpusTransferCapabilities(
            protocolVersions: [1],
            partitionTargetBounds: ConnectedCorpusPartitionTargetBounds(
                minimumBytes: 64 * 1_024 * 1_024,
                preferredBytes: 64 * 1_024 * 1_024,
                maximumBytes: 64 * 1_024 * 1_024
            )
        ))
        XCTAssertNil(sixtyFourOnly.negotiateConnectedCorpusTransfer(with: smallerPreference))

        let noSharedVersion = makePeer(capabilities: ConnectedCorpusTransferCapabilities(
            protocolVersions: [2],
            partitionTargetBounds: .default
        ))
        XCTAssertNil(currentIOS.negotiateConnectedCorpusTransfer(with: noSharedVersion))
    }

    func testMalformedPartitionBoundsAndDescriptorAreRejectedDuringDecode() throws {
        let malformedBounds = [
            (31, 48, 64),
            (32, 65, 64),
            (32, 48, 65),
            (48, 40, 64)
        ]
        for (minimum, preferred, maximum) in malformedBounds {
            let json = """
            {
              "minimumBytes": \(minimum * 1024 * 1024),
              "preferredBytes": \(preferred * 1024 * 1024),
              "maximumBytes": \(maximum * 1024 * 1024)
            }
            """.data(using: .utf8)!
            XCTAssertThrowsError(try JSONDecoder().decode(
                ConnectedCorpusPartitionTargetBounds.self,
                from: json
            ))
        }

        let sessionID = UUID()
        let jobID = UUID()
        let malformedDescriptor = ConnectedCorpusPartitionDescriptor(
            sessionID: sessionID,
            jobID: jobID,
            index: 1,
            sourceDates: [Date(timeIntervalSince1970: 1_800_000_000)],
            byteCount: 1,
            sha256: digestA,
            previousSHA256: nil
        )
        XCTAssertThrowsError(try JSONDecoder().decode(
            ConnectedCorpusPartitionDescriptor.self,
            from: JSONEncoder().encode(malformedDescriptor)
        ))
    }

    private func makePeer(
        capabilities: ConnectedCorpusTransferCapabilities
    ) -> SyncPeerCapabilities {
        SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "test",
            buildNumber: "1",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsPartitionedConnectedExports: true,
            connectedCorpusTransferCapabilities: capabilities
        )
    }

    private func assertRoundTrip(
        _ message: SyncMessage,
        assert: (SyncMessage) -> Void
    ) throws {
        assert(try JSONDecoder().decode(SyncMessage.self, from: JSONEncoder().encode(message)))
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
