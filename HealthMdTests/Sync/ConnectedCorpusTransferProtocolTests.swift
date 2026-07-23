import XCTest
@testable import HealthMd

final class ConnectedCorpusTransferProtocolTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; retain this fixture to avoid
    // the platform-specific iOS Simulator deinit crash during test teardown.
    private static var retainedSettings: [AdvancedExportSettings] = []

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
        let peerBinding = ConnectedCorpusPeerBinding(
            sourceInstallationID: UUID(),
            destinationInstallationID: UUID()
        )
        let session = ConnectedCorpusTransferSession(
            sessionID: sessionID,
            jobID: jobID,
            requestFingerprint: fingerprint,
            partitionTargetBytes: ConnectedCorpusTransferConstants.defaultPartitionTargetBytes,
            createdAt: createdAt,
            peerBinding: peerBinding
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
            XCTAssertEqual(open.session.peerBinding, peerBinding)
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

        let status = ConnectedCorpusProgressSnapshot(
            jobID: jobID,
            sessionID: sessionID,
            requestFingerprint: fingerprint,
            state: .transferring,
            processedDays: 1,
            totalDays: 2,
            committedPartitionCount: 1,
            committedBytes: 40_000_000,
            currentDate: sourceDates[1],
            message: "Waiting for the next partition.",
            updatedAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(86_400)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ConnectedCorpusProgressSnapshot.self,
                from: JSONEncoder().encode(status)
            ),
            status
        )
        let allStates: [ConnectedCorpusJobState] = [
            .preparing, .transferring, .paused, .finalizing, .completed,
            .partialSuccess, .failed, .cancelled, .expired
        ]
        for state in allStates {
            XCTAssertEqual(
                try JSONDecoder().decode(
                    ConnectedCorpusJobState.self,
                    from: JSONEncoder().encode(state)
                ),
                state
            )
        }
        try assertRoundTrip(.connectedCorpusStatus(status)) { message in
            guard case .connectedCorpusStatus(let snapshot) = message else {
                return XCTFail("Expected durable corpus status")
            }
            XCTAssertEqual(snapshot, status)
            XCTAssertEqual(message.operationalName, "connectedCorpusStatus")
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
        requireSendable(status)
        requireSendable(journal)
    }

    @MainActor
    func testRequestFingerprintIsStableAcrossManifestCodableRoundTrip() throws {
        let suiteName = "ConnectedCorpusFingerprintTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.markdown, .json, .csv]
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let manifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: date,
            sourceDeviceName: "iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            transferDates: [date],
            settingsSnapshot: .from(settings),
            requestedTarget: nil
        )
        let decoded = try JSONDecoder().decode(
            ConnectedCorpusExportManifest.self,
            from: JSONEncoder().encode(manifest)
        )
        XCTAssertEqual(
            try ConnectedCorpusRequestFingerprint.make(for: manifest),
            try ConnectedCorpusRequestFingerprint.make(for: decoded)
        )

        var unsafeSettings = manifest.settingsSnapshot
        unsafeSettings.folderStructure = "../../outside"
        let unsafeManifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: date,
            sourceDeviceName: "iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            transferDates: [date],
            settingsSnapshot: unsafeSettings,
            requestedTarget: nil
        )
        XCTAssertThrowsError(try unsafeManifest.validate())

        let unscopedContextManifest = ConnectedCorpusExportManifest(
            mode: .encryptedContext,
            createdAt: date,
            sourceDeviceName: "iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            transferDates: [date],
            settingsSnapshot: manifest.settingsSnapshot,
            requestedTarget: nil
        )
        XCTAssertThrowsError(
            try unscopedContextManifest.validate(),
            "Recovered context jobs must never fall back to saved or Apple-only scope."
        )

        let selection = CanonicalHealthDataSelection(
            metricIDs: ["sleep_total"],
            sourceIDs: ["apple_health"]
        )
        let scopedContextManifest = ConnectedCorpusExportManifest(
            mode: .encryptedContext,
            createdAt: date,
            sourceDeviceName: "iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            transferDates: [date],
            settingsSnapshot: manifest.settingsSnapshot,
            canonicalSelection: selection,
            selectedSourceIDs: selection.sourceIDs,
            requestedTarget: nil
        )
        XCTAssertNoThrow(try scopedContextManifest.validate())
    }

    func testFinalizationAllowsAggregateCorpusBeyondTwoGiB() throws {
        let fingerprint = ConnectedCorpusRequestFingerprint(sha256: digestA)
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: UUID(),
            jobID: UUID(),
            requestFingerprint: fingerprint,
            partitionCount: 49,
            totalByteCount: 3 * 1_024 * 1_024 * 1_024,
            finalPartitionSHA256: digestB
        )
        let decoded = try JSONDecoder().decode(
            ConnectedCorpusTransferFinalize.self,
            from: JSONEncoder().encode(finalize)
        )
        XCTAssertEqual(decoded.totalByteCount, 3_221_225_472)
        XCTAssertEqual(decoded.partitionCount, 49)
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
        XCTAssertNil(decoded.installationID)
        XCTAssertFalse(decoded.supportsDurableConnectedExportRecovery)
        XCTAssertNil(decoded.negotiateConnectedCorpusTransfer(with: .current(platform: .iOS)))
        XCTAssertNil(decoded.negotiateDurableConnectedCorpusTransfer(with: .current(platform: .iOS)))
    }

    func testResumableCorpusDisconnectWaitsForReconnectAfterTransferStarts() {
        XCTAssertEqual(
            ConnectedMacExportLifecyclePolicy.disconnectDisposition(
                payloadSent: true,
                usesResumableCorpus: true
            ),
            .awaitReconnect
        )
        XCTAssertEqual(
            ConnectedMacExportLifecyclePolicy.disconnectDisposition(
                payloadSent: true,
                usesResumableCorpus: false
            ),
            .failAfterPayload
        )
        XCTAssertEqual(
            ConnectedMacExportLifecyclePolicy.disconnectDisposition(
                payloadSent: false,
                usesResumableCorpus: true
            ),
            .failBeforePayload
        )
        XCTAssertEqual(
            ConnectedMacExportLifecyclePolicy.disconnectDisposition(
                payloadSent: true,
                usesResumableCorpus: true,
                userInitiated: true
            ),
            .cancel
        )
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
            protocolVersions: [3],
            partitionTargetBounds: .default
        ))
        XCTAssertNil(currentIOS.negotiateConnectedCorpusTransfer(with: noSharedVersion))
    }

    func testDurableNegotiationRequiresBothCapabilitiesIdentitiesAndProtocolV2() {
        let sourceInstallationID = UUID()
        let destinationInstallationID = UUID()
        let v2Capabilities = ConnectedCorpusTransferCapabilities(
            protocolVersions: [1, 2],
            partitionTargetBounds: .default
        )
        let source = makePeer(
            capabilities: v2Capabilities,
            installationID: sourceInstallationID,
            supportsDurableRecovery: true
        )
        let destination = makePeer(
            capabilities: v2Capabilities,
            installationID: destinationInstallationID,
            supportsDurableRecovery: true
        )

        let durable = source.negotiateDurableConnectedCorpusTransfer(with: destination)
        XCTAssertEqual(durable?.protocolVersion, 2)
        XCTAssertEqual(durable?.partitionTargetBytes, 48 * 1_024 * 1_024)
        XCTAssertEqual(
            durable?.peerBinding,
            ConnectedCorpusPeerBinding(
                sourceInstallationID: sourceInstallationID,
                destinationInstallationID: destinationInstallationID
            )
        )
        XCTAssertEqual(
            source.durableConnectedCorpusPeerBinding(with: destination),
            durable?.peerBinding
        )
        XCTAssertTrue(source.canExchangeConnectedCorpusStatus(with: destination))

        let missingIdentity = makePeer(
            capabilities: v2Capabilities,
            installationID: nil,
            supportsDurableRecovery: true
        )
        let missingCapability = makePeer(
            capabilities: v2Capabilities,
            installationID: destinationInstallationID,
            supportsDurableRecovery: false
        )
        let protocolOneOnly = makePeer(
            capabilities: ConnectedCorpusTransferCapabilities(
                protocolVersions: [1],
                partitionTargetBounds: .default
            ),
            installationID: destinationInstallationID,
            supportsDurableRecovery: true
        )
        for incompatible in [missingIdentity, missingCapability, protocolOneOnly] {
            XCTAssertNil(source.negotiateDurableConnectedCorpusTransfer(with: incompatible))
            XCTAssertFalse(source.canExchangeConnectedCorpusStatus(with: incompatible))
        }
    }

    func testProtocolOneSessionFixtureDecodesWithoutPeerBinding() throws {
        let sessionID = UUID()
        let jobID = UUID()
        let fixture = """
        {
          "sessionID": "\(sessionID.uuidString)",
          "jobID": "\(jobID.uuidString)",
          "requestFingerprint": {
            "version": 1,
            "sha256": "\(digestA)"
          },
          "protocolVersion": 1,
          "partitionTargetBytes": \(ConnectedCorpusTransferConstants.defaultPartitionTargetBytes),
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ConnectedCorpusTransferSession.self, from: fixture)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertNil(decoded.peerBinding)
        XCTAssertEqual(
            try JSONDecoder().decode(
                ConnectedCorpusTransferSession.self,
                from: JSONEncoder().encode(decoded)
            ),
            decoded
        )
    }

    func testProtocolOneSessionRejectsPeerBinding() throws {
        let session = ConnectedCorpusTransferSession(
            sessionID: UUID(),
            jobID: UUID(),
            requestFingerprint: ConnectedCorpusRequestFingerprint(sha256: digestA),
            protocolVersion: 1,
            createdAt: Date(),
            peerBinding: ConnectedCorpusPeerBinding(
                sourceInstallationID: UUID(),
                destinationInstallationID: UUID()
            )
        )
        XCTAssertThrowsError(try JSONDecoder().decode(
            ConnectedCorpusTransferSession.self,
            from: JSONEncoder().encode(session)
        )) { error in
            XCTAssertEqual(error as? ConnectedCorpusTransferModelError, .invalidPeerBinding)
        }
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
        capabilities: ConnectedCorpusTransferCapabilities,
        installationID: UUID? = nil,
        supportsDurableRecovery: Bool = false
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
            connectedCorpusTransferCapabilities: capabilities,
            installationID: installationID,
            supportsDurableConnectedExportRecovery: supportsDurableRecovery
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
