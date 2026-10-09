import Foundation
import CryptoKit
import HealthMdConnectionCore
import HealthMdCoreRust
@testable import HealthMd
import XCTest

final class AppleDirectProtocolAuthorityTests: XCTestCase {
    func testLegacyNeverCallsRustAndReturnsNativeValues() throws {
        let core = FakeAppleDirectProtocolRustCore()
        core.failEveryCall = true
        let authority = AppleDirectProtocolAuthority(defaultMode: .legacy, rustCore: core)
        try authority.assertCompatible()

        let request = fixtureRequest()
        XCTAssertEqual(
            try authority.requestFingerprint(request),
            try DirectRequestFingerprint.make(for: request)
        )
        let bytes = Data("native".utf8)
        XCTAssertEqual(try authority.canonicalizeDirectMessage(bytes), bytes)
        XCTAssertTrue(authority.comparisonSnapshot().comparisons.isEmpty)
    }

    func testShadowReturnsNativeAndRecordsOnlyHealthFreeCounts() throws {
        let core = FakeAppleDirectProtocolRustCore()
        core.fingerprint = String(repeating: "f", count: 64)
        core.canonicalMessage = Data("rust".utf8)
        core.frame = Data("rust-frame".utf8)
        let authority = AppleDirectProtocolAuthority(defaultMode: .shadow, rustCore: core)

        try authority.assertCompatible()
        let request = fixtureRequest()
        XCTAssertEqual(
            try authority.requestFingerprint(request),
            try DirectRequestFingerprint.make(for: request)
        )
        let bytes = Data("native".utf8)
        XCTAssertEqual(try authority.canonicalizeDirectMessage(bytes), bytes)
        let chunk = try fixtureChunk()
        XCTAssertEqual(
            try authority.encodeTransferChunk(chunk),
            try DirectTransferBinaryFrame.encode(chunk)
        )

        let evidence = authority.comparisonSnapshot()
        XCTAssertEqual(evidence.comparisons[.compatibility], 1)
        XCTAssertNil(evidence.mismatches[.compatibility])
        XCTAssertEqual(evidence.mismatches[.requestFingerprint], 1)
        XCTAssertEqual(evidence.mismatches[.directMessage], 1)
        XCTAssertEqual(evidence.mismatches[.transferFrame], 1)
    }

    func testRustIsAuthoritativeAndNeverFallsBack() throws {
        let core = FakeAppleDirectProtocolRustCore()
        core.fingerprint = String(repeating: "a", count: 64)
        core.canonicalMessage = Data("rust".utf8)
        let authority = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        try authority.assertCompatible()

        XCTAssertEqual(try authority.requestFingerprint(fixtureRequest()).sha256, core.fingerprint)
        XCTAssertEqual(
            try authority.canonicalizeDirectMessage(Data("native".utf8)),
            core.canonicalMessage
        )

        core.failCanonicalization = true
        XCTAssertThrowsError(
            try authority.canonicalizeDirectMessage(Data("private-health-value".utf8))
        ) { error in
            XCTAssertEqual(
                error as? AppleDirectProtocolAuthorityError,
                AppleDirectProtocolAuthorityError(stage: .directMessage)
            )
            XCTAssertFalse(error.localizedDescription.contains("private-health-value"))
        }
    }

    func testOperationPinsRestoreLegacyAndIgnoreSourceRevisionForCompatibility() throws {
        let core = FakeAppleDirectProtocolRustCore()
        let authority = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        let pin = try XCTUnwrap(authority.pinForNewOperation())
        XCTAssertEqual(pin.engine, .rust)

        authority.beginBootstrap()
        core.failEveryCall = true
        XCTAssertEqual(
            try authority.requestFingerprint(fixtureRequest()),
            try DirectRequestFingerprint.make(for: fixtureRequest())
        )
        core.failEveryCall = false

        let rebuiltPin = try AppleDirectProtocolPin(
            engine: pin.engine,
            coreAPIVersion: pin.coreAPIVersion,
            protocolAPIRevision: pin.protocolAPIRevision,
            appleApplicationProtocolVersion: pin.appleApplicationProtocolVersion,
            transferProtocolVersion: pin.transferProtocolVersion,
            coreCrateVersion: pin.coreCrateVersion,
            coreSourceRevision: "different-compatible-build"
        )
        try authority.beginOperation(pin: rebuiltPin)
        XCTAssertEqual(try authority.requestFingerprint(fixtureRequest()).sha256, core.fingerprint)
        authority.endOperation()
    }

    func testReconnectBootstrapAndOldCleanupKeepIndependentSessionModes() throws {
        let core = FakeAppleDirectProtocolRustCore()
        core.fingerprint = String(repeating: "a", count: 64)
        core.canonicalMessage = Data("rust-session".utf8)
        let configuration = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        let oldSession = configuration.makeSessionAuthority()
        let pin = try XCTUnwrap(oldSession.pinForNewOperation())
        try oldSession.beginOperation(pin: pin)
        let replacement = configuration.makeSessionAuthority()
        replacement.beginBootstrap()

        XCTAssertFalse(oldSession === replacement)
        XCTAssertEqual(try oldSession.requestFingerprint(fixtureRequest()).sha256, core.fingerprint,
            "Reconnect bootstrap cannot downgrade the old session's pinned engine")
        XCTAssertEqual(try replacement.requestFingerprint(fixtureRequest()),
            try DirectRequestFingerprint.make(for: fixtureRequest()))
        oldSession.endOperation()
        configuration.endOperation()
        let native = Data("native-bootstrap".utf8)
        XCTAssertEqual(try replacement.canonicalizeDirectMessage(native), native,
            "Old session/configuration teardown cannot end replacement bootstrap")
        XCTAssertTrue(replacement.comparisonSnapshot().comparisons.isEmpty)
        try replacement.beginOperation(pin: pin)
        oldSession.beginBootstrap()
        XCTAssertEqual(try replacement.canonicalizeDirectMessage(native), core.canonicalMessage,
            "A stale bootstrap cannot replace the admitted replacement engine")
    }

    func testRetainedOperationAuthorityCannotBeChangedByBootstrapOrTeardown() throws {
        let core = FakeAppleDirectProtocolRustCore()
        core.fingerprint = String(repeating: "a", count: 64)
        core.canonicalMessage = Data("retained-operation".utf8)
        core.frame = Data("retained-frame".utf8)
        let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        let pin = try XCTUnwrap(session.pinForNewOperation())
        try session.beginOperation(pin: pin)
        let operation = session.frozenForCurrentOperation()
        session.beginBootstrap()
        XCTAssertFalse(operation === session)
        XCTAssertEqual(try operation.requestFingerprint(fixtureRequest()).sha256, core.fingerprint)
        XCTAssertEqual(try operation.canonicalizeDirectMessage(Data("native".utf8)), core.canonicalMessage)
        XCTAssertEqual(try operation.encodeTransferChunk(fixtureChunk()), core.frame)
        operation.beginBootstrap()
        operation.endOperation()
        XCTAssertEqual(try operation.requestFingerprint(fixtureRequest()).sha256, core.fingerprint)
        XCTAssertThrowsError(try operation.beginOperation(pin: nil),
            "A retained nonlegacy operation cannot be replaced by historical legacy authority")
        session.endOperation()
        session.beginBootstrap()
        let legacy = session.frozenForCurrentOperation()
        try session.beginOperation(pin: pin)
        XCTAssertEqual(try legacy.requestFingerprint(fixtureRequest()),
            try DirectRequestFingerprint.make(for: fixtureRequest()))
        XCTAssertEqual(try legacy.canonicalizeDirectMessage(Data("native".utf8)), Data("native".utf8))
    }

#if os(iOS)
    @MainActor
    func testActualPreparationFailurePreservesReplacementSameIDActivityAdmission() async throws {
        for (files, replacementSource) in [(false, CLIExportActivityTracker.Source.macApp),
            (true, .macApp), (false, .direct), (true, .direct)] {
            let jobID = UUID()
            let published = try publishInactiveCancellationFixture(jobID: jobID, files: files,
                version: files ? 6 : 3, requestCreatedAt: Date())
            defer {
                try? FileManager.default.removeItem(at: published.directory)
                CLIExportActivityTracker.shared.clear(jobID: jobID)
            }
            let bytes = try Data(contentsOf: published.journal)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(DirectExportRequest.self,
                from: JSONSerialization.data(withJSONObject: try XCTUnwrap(object["request"])))
            let model = try IPhoneDirectFileJournalTests.makeJournal(jobID: jobID)
            let negotiation = try XCTUnwrap(DirectTransferCapabilities.current.negotiated(with: .current))
            let core = FakeAppleDirectProtocolRustCore()
            core.returnNativeCanonicalMessage = true
            let replacement = ActivityAdmissionCapture()
            core.onFingerprint = {
                MainActor.assumeIsolated {
                    let tracker = CLIExportActivityTracker.shared
                    let original = tracker.snapshot
                    tracker.begin(jobID: jobID, source: replacementSource,
                        totalDays: original?.totalDays ?? 0,
                        targetLabel: replacementSource == .direct ? original?.targetLabel : nil,
                        message: replacementSource == .direct ? original?.message ?? "Replacement preparation" : "Replacement preparation")
                    replacement.snapshot = tracker.snapshot
                }
            }
            defer { core.onFingerprint = nil }
            let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
            let transport = OperationProtocolPacketTransport()
            let channel = DirectSecureChannel(packetConnection: transport,
                sessionKey: SymmetricKey(data: Data(repeating: 0x46, count: 32)),
                peerInstallationID: model.session.peerBinding.destinationInstallationID,
                peerDisplayName: "synthetic", messageCanonicalizer: session)
            let suite = "synthetic-preparation-activity-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FakeHealthStore()
            let healthKit = HealthKitManager(store: store, userDefaults: defaults)
            let coordinator = IPhoneDirectExportCoordinator()
            await coordinator.handle(request, peerBinding: model.session.peerBinding,
                negotiation: negotiation, channel: IPhoneDirectExportConnection(channel: channel),
                protocolAuthority: session, healthKitManager: healthKit)
            XCTAssertEqual(core.fingerprintCalls, 1)
            let tracker = CLIExportActivityTracker.shared
            XCTAssertNotNil(replacement.snapshot)
            XCTAssertEqual(tracker.snapshot, replacement.snapshot,
                "A new admission must survive even when its entire visible snapshot is identical")
            XCTAssertEqual(tracker.snapshot?.phase, .preparing)
            XCTAssertTrue(tracker.keepsScreenAwake)
            XCTAssertEqual(tracker.snapshot?.source, replacementSource)
            XCTAssertEqual(try Data(contentsOf: published.journal), bytes)
            try published.ownership.validateGeneration()
            XCTAssertFalse(store.authRequested)
            XCTAssertTrue(store.requestedReadTypes.isEmpty)
            XCTAssertTrue(store.completedCanonicalQueryIdentifiers.isEmpty)
        }
    }

    @MainActor
    func testPreparationRejectionRejectsFinishedInvocationBeforeCanonicalization() async throws {
        let jobID = UUID()
        let core = FakeAppleDirectProtocolRustCore()
        let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        try session.beginOperation(pin: session.pinForNewOperation())
        let selected = session.frozenForCurrentOperation()
        let old = IPhoneDirectCancellationInvocation(jobID: jobID, protocolAuthority: selected)
        old.finish()
        let current = IPhoneDirectCancellationInvocation(jobID: jobID, protocolAuthority: selected)
        defer { current.finish() }
        let transport = OperationProtocolPacketTransport()
        let key = SymmetricKey(data: Data(repeating: 0x45, count: 32))
        let channel = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic", messageCanonicalizer: session)
        let connection = IPhoneDirectExportConnection(channel: channel).retainingProtocolAuthority(selected)
        let message = DirectMessage.exportRejected(DirectExportFailure(jobID: jobID,
            reason: .invalidRequest, message: "synthetic terminal response"))
        let receiver = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic")
        session.beginBootstrap()
        core.failCanonicalization = true
        do {
            try await connection.send(message, authorization: old.preparationResponseAuthorization)
            XCTFail("A finished invocation cannot authorize a preparation response")
        } catch {
            XCTAssertEqual(error as? DirectChannelError,
                .authenticationFailed("The direct preparation is no longer active."))
        }
        XCTAssertEqual(core.canonicalMessageCalls, 0)
        XCTAssertEqual(transport.packetCount, 0)
        core.failCanonicalization = false
        core.returnNativeCanonicalMessage = true
        current.cancel()
        try await connection.send(message, authorization: current.preparationResponseAuthorization)
        let first = try await receiver.receive()
        XCTAssertEqual(first, .message(message), "An active cancelled invocation can report its terminal rejection")
        XCTAssertEqual(core.canonicalMessageCalls, 1)
        core.failCanonicalization = true
        do {
            try await connection.send(message, authorization: old.preparationResponseAuthorization)
            XCTFail("An old same-ID invocation cannot inherit the new invocation's authority")
        } catch {
            XCTAssertEqual(error as? DirectChannelError,
                .authenticationFailed("The direct preparation is no longer active."))
        }
        XCTAssertEqual(core.canonicalMessageCalls, 1)
        XCTAssertEqual(transport.packetCount, 0)
        core.failCanonicalization = false
        try await connection.send(message, authorization: current.preparationResponseAuthorization)
        let second = try await receiver.receive()
        XCTAssertEqual(second, .message(message), "Rejected old authority must consume no secure sequence")
        XCTAssertEqual(core.canonicalMessageCalls, 2)
    }

    @MainActor
    func testActualRawAndFileRejectionRetainsProtocolSelectedBeforeFingerprintFailure() async throws {
        for files in [false, true] {
            let jobID = UUID()
            let published = try publishInactiveCancellationFixture(jobID: jobID, files: files,
                version: files ? 6 : 3, requestCreatedAt: Date())
            defer {
                try? FileManager.default.removeItem(at: published.directory)
                CLIExportActivityTracker.shared.clear(jobID: jobID)
            }
            let bytes = try Data(contentsOf: published.journal)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(DirectExportRequest.self,
                from: JSONSerialization.data(withJSONObject: try XCTUnwrap(object["request"])))
            let model = try IPhoneDirectFileJournalTests.makeJournal(jobID: jobID)
            let negotiation = try XCTUnwrap(DirectTransferCapabilities.current.negotiated(with: .current))
            let core = FakeAppleDirectProtocolRustCore()
            let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
            core.onFingerprint = { session.beginBootstrap() }
            defer { core.onFingerprint = nil }
            core.failCanonicalization = true
            let transport = OperationProtocolPacketTransport()
            let key = SymmetricKey(data: Data(repeating: 0x44, count: 32))
            let channel = DirectSecureChannel(packetConnection: transport, sessionKey: key,
                peerInstallationID: model.session.peerBinding.destinationInstallationID,
                peerDisplayName: "synthetic", messageCanonicalizer: session)
            let connection = IPhoneDirectExportConnection(channel: channel)
            let suite = "synthetic-rejection-protocol-" + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FakeHealthStore()
            let healthKit = HealthKitManager(store: store, userDefaults: defaults)
            let coordinator = IPhoneDirectExportCoordinator()
            await coordinator.handle(request, peerBinding: model.session.peerBinding,
                negotiation: negotiation, channel: connection, protocolAuthority: session,
                healthKitManager: healthKit)
            XCTAssertEqual(core.fingerprintCalls, 1, "The actual producer must reach its restored protocol selection")
            XCTAssertEqual(transport.packetCount, 0, "Bootstrap cannot bypass selected Rust rejection canonicalization")
            XCTAssertEqual(try Data(contentsOf: published.journal), bytes)
            try published.ownership.validateGeneration()
            core.failCanonicalization = false
            core.returnNativeCanonicalMessage = true
            await coordinator.handle(request, peerBinding: model.session.peerBinding,
                negotiation: negotiation, channel: connection, protocolAuthority: session,
                healthKitManager: healthKit)
            XCTAssertEqual(core.fingerprintCalls, 2)
            XCTAssertEqual(transport.authorizedSendCount, 2,
                "Both actual pre-acceptance rejections must use invocation-owned packet creation")
            let receiver = DirectSecureChannel(packetConnection: transport, sessionKey: key,
                peerInstallationID: UUID(), peerDisplayName: "synthetic")
            guard case .message(.exportRejected(let failure)) = try await receiver.receive() else {
                return XCTFail("The actual coordinator must send the rejection after canonicalization recovers")
            }
            XCTAssertEqual(failure.jobID, jobID)
            XCTAssertEqual(failure.reason, .invalidRequest)
            XCTAssertEqual(transport.packetCount, 0)
            XCTAssertEqual(try Data(contentsOf: published.journal), bytes)
            try published.ownership.validateGeneration()
            XCTAssertFalse(store.authRequested)
            XCTAssertTrue(store.requestedReadTypes.isEmpty)
            XCTAssertTrue(store.queriedSumIdentifiers.isEmpty)
            XCTAssertTrue(store.queriedCategoryIdentifiers.isEmpty)
            XCTAssertTrue(store.quantitySampleQueries.isEmpty)
            XCTAssertTrue(store.completedCanonicalQueryIdentifiers.isEmpty)
        }
    }

    @MainActor
    func testIncomingProtocolSelectionIsRetainedAfterPendingReceiveAndOwnedCleanup() async throws {
        let core = FakeAppleDirectProtocolRustCore()
        let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        session.beginBootstrap()
        let transport = PendingIncomingProtocolTransport()
        let key = SymmetricKey(data: Data(repeating: 0x43, count: 32))
        let sender = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic")
        let receiver = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic", messageCanonicalizer: session)
        let connection = IPhoneDirectExportConnection(channel: receiver)
        let pending = Task {
            try await receiver.receive(messageCanonicalizer: {
                connection.incomingMessageCanonicalizer(fallback: session)
            })
        }
        await transport.waitForReceiver()
        try session.beginOperation(pin: session.pinForNewOperation())
        let first = connection.retainIncomingProtocolAuthority(session)
        defer { first.close() }
        session.beginBootstrap()
        core.failCanonicalization = true
        try await sender.send(.ping)
        do {
            _ = try await pending.value
            XCTFail("Incoming bytes must use the pin selected while receive was pending, despite later bootstrap")
        } catch {
            XCTAssertEqual(error as? DirectChannelError, .decodeFailed)
        }
        core.failCanonicalization = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        core.canonicalMessage = try encoder.encode(DirectMessage.ping)
        try await sender.send(.ping)
        let valid = try await receiver.receive(messageCanonicalizer: {
            connection.incomingMessageCanonicalizer(fallback: session)
        })
        XCTAssertEqual(valid, .message(.ping))

        // A replacement's historical authority must survive old close/deinit.
        let replacement = connection.retainIncomingProtocolAuthority(session)
        defer { replacement.close() }
        first.close()
        try session.beginOperation(pin: session.pinForNewOperation())
        core.failCanonicalization = true
        try await sender.send(.ping)
        let historical = try await receiver.receive(messageCanonicalizer: {
            connection.incomingMessageCanonicalizer(fallback: session)
        })
        XCTAssertEqual(historical, .message(.ping))
        replacement.close()
        try await sender.send(.ping)
        do {
            _ = try await receiver.receive(messageCanonicalizer: {
                connection.incomingMessageCanonicalizer(fallback: session)
            })
            XCTFail("Closing the current selection must restore the connection authority")
        } catch {
            XCTAssertEqual(error as? DirectChannelError, .decodeFailed)
        }
    }

    @MainActor
    func testInactiveCancellationPreservesUnownedSameIDActivity() throws {
        for (files, source) in [(false, CLIExportActivityTracker.Source.macApp),
            (true, .macApp), (false, .direct), (true, .direct)] {
            let jobID = UUID()
            let published = try publishInactiveCancellationFixture(jobID: jobID, files: files,
                version: files ? 6 : 3)
            let tracker = CLIExportActivityTracker.shared
            defer {
                tracker.clear(jobID: jobID)
                try? FileManager.default.removeItem(at: published.directory)
            }
            tracker.begin(jobID: jobID, source: source, message: "Replacement activity")
            let snapshot = try XCTUnwrap(tracker.snapshot)
            let admissionID = try XCTUnwrap(tracker.admissionID)
            let authority = AppleDirectProtocolAuthority(defaultMode: .rust,
                rustCore: FakeAppleDirectProtocolRustCore())
            let receipt = try XCTUnwrap(IPhoneDirectExportCoordinator.shared.cancelWithReceipt(
                jobID: jobID, protocolAuthority: authority))
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with:
                Data(contentsOf: published.journal)) as? [String: Any])
            XCTAssertEqual(saved["state"] as? String, "cancelled",
                "The durable cancellation must still complete")
            try XCTUnwrap(receipt.durableOwnership).validateGeneration()
            XCTAssertEqual(tracker.snapshot, snapshot,
                "A durable receipt does not grant ownership of a same-ID activity")
            XCTAssertEqual(tracker.admissionID, admissionID)
            XCTAssertTrue(tracker.keepsScreenAwake)
        }
    }

    @MainActor
    func testInactiveRawAndFileCancellationRestoreStoredProtocolSelection() async throws {
        for (files, version, legacy) in [(false, 2, true), (false, 3, false), (true, 2, true), (true, 6, false)] {
            let jobID = UUID()
            let published = try publishInactiveCancellationFixture(jobID: jobID, files: files, version: version)
            defer { try? FileManager.default.removeItem(at: published.directory) }
            let core = FakeAppleDirectProtocolRustCore()
            let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
            let receipt = try XCTUnwrap(IPhoneDirectExportCoordinator.shared.cancelWithReceipt(
                jobID: jobID, protocolAuthority: session))
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with:
                Data(contentsOf: published.journal)) as? [String: Any])
            XCTAssertEqual(saved["state"] as? String, "cancelled")
            XCTAssertFalse(receipt.durableOwnership?.generation == nil)
            let transport = OperationProtocolPacketTransport()
            let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
            session.beginBootstrap()
            let channel = DirectSecureChannel(packetConnection: transport, sessionKey: key,
                peerInstallationID: UUID(), peerDisplayName: "synthetic", messageCanonicalizer: session)
            let receiver = DirectSecureChannel(packetConnection: transport, sessionKey: key,
                peerInstallationID: UUID(), peerDisplayName: "synthetic")
            core.failCanonicalization = true
            if legacy {
                try await receipt.sendAcknowledgement(on: channel)
            } else {
                do {
                    try await receipt.sendAcknowledgement(on: channel)
                    XCTFail("An inactive current journal must restore its stored Rust pin")
                } catch {
                    XCTAssertEqual(error as? AppleDirectProtocolAuthorityError,
                        AppleDirectProtocolAuthorityError(stage: .directMessage))
                }
                XCTAssertEqual(transport.packetCount, 0)
                core.failCanonicalization = false
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                core.canonicalMessage = try encoder.encode(DirectMessage.cancelAcknowledged(jobID: jobID))
                try await receipt.sendAcknowledgement(on: channel)
            }
            let received = try await receiver.receive()
            XCTAssertEqual(received, .message(.cancelAcknowledged(jobID: jobID)))
        }
    }

    @MainActor
    func testInactiveCancellationRejectsIncompatiblePinsWithoutJournalMutation() throws {
        for files in [false, true] {
            let jobID = UUID()
            let published = try publishInactiveCancellationFixture(jobID: jobID, files: files,
                version: files ? 6 : 3, incompatible: true)
            defer { try? FileManager.default.removeItem(at: published.directory) }
            let bytes = try Data(contentsOf: published.journal)
            let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: FakeAppleDirectProtocolRustCore())
            XCTAssertNil(IPhoneDirectExportCoordinator.shared.cancelWithReceipt(
                jobID: jobID, protocolAuthority: session), "Incompatible pins cannot produce a cancellation receipt")
            XCTAssertEqual(try Data(contentsOf: published.journal), bytes)
            try published.ownership.validateGeneration()
        }
    }

    @MainActor
    func testInactiveFileCancellationDoesNotBypassRawArtifacts() throws {
        for artifact in ["journal.json", ".journal-generation", "partition.bin"] {
            let jobID = UUID()
            let published = try publishInactiveCancellationFixture(jobID: jobID, files: true, version: 6)
            defer { try? FileManager.default.removeItem(at: published.directory) }
            let rawArtifact = published.directory.appendingPathComponent(artifact)
            let retainedBytes = Data("synthetic unreadable raw ownership".utf8)
            try retainedBytes.write(to: rawArtifact)
            let fileBytes = try Data(contentsOf: published.journal)
            let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: FakeAppleDirectProtocolRustCore())
            XCTAssertNil(IPhoneDirectExportCoordinator.shared.cancelWithReceipt(
                jobID: jobID, protocolAuthority: session))
            XCTAssertEqual(try Data(contentsOf: rawArtifact), retainedBytes)
            XCTAssertEqual(try Data(contentsOf: published.journal), fileBytes)
            try published.ownership.validateGeneration()
        }
    }

    @MainActor
    private func publishInactiveCancellationFixture(jobID: UUID, files: Bool, version: Int,
                                                   incompatible: Bool = false, requestCreatedAt: Date? = nil) throws
        -> (directory: URL, journal: URL, ownership: AppleExportJournalCheckpoint) {
        let model = try IPhoneDirectFileJournalTests.makeJournal(jobID: jobID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(model)) as? [String: Any])
        object["version"] = version
        object["state"] = "paused"
        if !files {
            let request = DirectExportRequest(jobID: jobID, createdAt: model.request.createdAt,
                dateSelection: model.request.dateSelection, responseMode: .rawJSON,
                rawProfile: .healthDataProjection,
                canonicalSelection: DirectCanonicalSelection(metricIDs: ["sleep_total"]))
            let session = try DirectTransferSession(sessionID: model.session.sessionID, jobID: jobID,
                requestFingerprint: DirectRequestFingerprint.make(for: request), peerBinding: model.session.peerBinding,
                partitionTargetBytes: model.session.partitionTargetBytes, createdAt: model.session.createdAt)
            let commonKeys: Set<String> = ["version", "settingsSnapshot", "accepted", "appleDirectProtocolPin",
                "updatedAt", "state", "partitions", "committedPartitionCount", "committedBytes", "completionRecorded"]
            object = object.filter { commonKeys.contains($0.key) }
            object["request"] = try JSONSerialization.jsonObject(with: encoder.encode(request))
            object["session"] = try JSONSerialization.jsonObject(with: encoder.encode(session))
            object["days"] = []
        }
        if let requestCreatedAt {
            var request = try XCTUnwrap(object["request"] as? [String: Any])
            let dates = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode([requestCreatedAt])) as? [String])
            request["createdAt"] = try XCTUnwrap(dates.first)
            object["request"] = request
        }
        if incompatible {
            var pin = try XCTUnwrap(object["appleDirectProtocolPin"] as? [String: Any])
            pin["coreAPIVersion"] = 999
            object["appleDirectProtocolPin"] = pin
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Health.md/DirectCLIOutbound/v1/" + jobID.uuidString.lowercased())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let journal = (files ? directory.appendingPathComponent("files") : directory).appendingPathComponent("journal.json")
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ownership = AppleExportJournalCheckpoint()
        try ownership.publish(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), to: journal,
            freshAdmission: true, lockURL: support.appendingPathComponent("Health.md/DirectCLIOutbound/.v1.journal.lock"),
            durabilityRoot: support)
        return (directory, journal, ownership)
    }

    @MainActor
    func testCancellationReceiptRetainsSelectedProtocolAcrossSessionBootstrap() async throws {
        let core = FakeAppleDirectProtocolRustCore()
        let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        session.beginBootstrap()
        let invocation = IPhoneDirectCancellationInvocation(jobID: UUID(),
            protocolAuthority: session.frozenForCurrentOperation())
        try session.beginOperation(pin: session.pinForNewOperation())
        invocation.bindProtocolAuthority(session.frozenForCurrentOperation())
        invocation.cancel()
        let receipt = IPhoneDirectCancellationReceipt(invocation: invocation)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = root.appendingPathComponent("job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        var ownership = AppleExportJournalCheckpoint()
        try ownership.publish(Data("synthetic cancelled authority".utf8),
            to: job.appendingPathComponent("journal.json"), freshAdmission: true,
            lockURL: root.appendingPathComponent(".publication.lock"), durabilityRoot: root)
        let durable = IPhoneDirectCancellationReceipt(jobID: invocation.jobID, ownership: ownership,
            protocolAuthority: session.frozenForCurrentOperation())
        // A later callback cannot replace the protocol context captured by the receipt.
        session.beginBootstrap()
        invocation.bindProtocolAuthority(session.frozenForCurrentOperation())
        let transport = OperationProtocolPacketTransport()
        let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let channel = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic", messageCanonicalizer: session)
        let receiver = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic")
        for retainedReceipt in [receipt, durable] {
            core.failCanonicalization = true
            do {
                try await retainedReceipt.sendAcknowledgement(on: channel)
                XCTFail("Bootstrap must not bypass the receipt's retained Rust protocol authority")
            } catch {
                XCTAssertEqual(error as? AppleDirectProtocolAuthorityError,
                    AppleDirectProtocolAuthorityError(stage: .directMessage))
            }
            XCTAssertEqual(transport.packetCount, 0)
            core.failCanonicalization = false
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            core.canonicalMessage = try encoder.encode(DirectMessage.cancelAcknowledged(jobID: invocation.jobID))
            try await retainedReceipt.sendAcknowledgement(on: channel)
            let received = try await receiver.receive()
            XCTAssertEqual(received, .message(.cancelAcknowledged(jobID: invocation.jobID)),
                "The failed retained canonicalization must consume no secure sequence")
        }
        invocation.finish()
    }

    @MainActor
    func testNativeExportConnectionRetainsOperationEngineAndSharesSessionInbox() async throws {
        let core = FakeAppleDirectProtocolRustCore()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        core.canonicalMessage = try encoder.encode(DirectMessage.ping)
        let session = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        try session.beginOperation(pin: session.pinForNewOperation())
        let transport = OperationProtocolPacketTransport()
        let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let channel = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic", messageCanonicalizer: session)
        let original = IPhoneDirectExportConnection(channel: channel)
        let retained = original.retainingProtocolAuthority(session)
        XCTAssertTrue(retained.channel === original.channel)
        session.beginBootstrap()
        core.failCanonicalization = true
        do {
            try await retained.send(.ping)
            XCTFail("Session bootstrap must not bypass the retained Rust operation authority")
        } catch {
            XCTAssertEqual(error as? AppleDirectProtocolAuthorityError,
                AppleDirectProtocolAuthorityError(stage: .directMessage))
        }
        XCTAssertEqual(transport.packetCount, 0)
        core.failCanonicalization = false
        session.endOperation()
        session.beginBootstrap()
        try await retained.send(.ping)
        let receiver = DirectSecureChannel(packetConnection: transport, sessionKey: key,
            peerInstallationID: UUID(), peerDisplayName: "synthetic")
        let received = try await receiver.receive()
        XCTAssertEqual(received, .message(.ping), "Failed canonicalization must consume no secure sequence")
        await original.deliver(.pong)
        let delivered = try await retained.receive()
        XCTAssertEqual(delivered, .pong)
        await original.finish()
        do {
            _ = try await retained.receive()
            XCTFail("Session teardown must finish the retained wrapper's shared inbox")
        } catch { XCTAssertEqual(error as? DirectChannelError, .connectionClosed) }
    }
#endif

    func testTransferNegotiationMatchesNative() throws {
        let core = FakeAppleDirectProtocolRustCore()
        let authority = AppleDirectProtocolAuthority(defaultMode: .rust, rustCore: core)
        XCTAssertEqual(
            try authority.negotiateTransfer(peer: .current),
            DirectTransferCapabilities.current.negotiated(with: .current)
        )
    }

    private func fixtureRequest() -> DirectExportRequest {
        DirectExportRequest(
            jobID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-02"),
            responseMode: .rawJSON,
            rawProfile: .healthDataProjection,
            canonicalSelection: DirectCanonicalSelection(metricIDs: ["sleep_total"])
        )
    }

    private func fixtureChunk() throws -> DirectTransferChunk {
        let data = Data(repeating: 0xab, count: 32)
        return try DirectTransferChunk(
            transferID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            sequence: 1,
            data: data,
            sha256: DirectTransferFile.sha256Hex(data)
        )
    }
}

private final class FakeAppleDirectProtocolRustCore: AppleDirectProtocolRustCore, @unchecked Sendable {
    var failEveryCall = false
    var failCanonicalization = false
    var canonicalMessageCalls = 0
    var fingerprint = String(repeating: "0", count: 64)
    var onFingerprint: (@Sendable () -> Void)?
    var fingerprintCalls = 0
    var canonicalMessage = Data()
    var returnNativeCanonicalMessage = false
    var frame = Data()

    func buildInfo() throws -> AppleDirectProtocolBuildInfo {
        try checkFailure()
        return AppleDirectProtocolBuildInfo(
            coreAPIVersion: 4,
            crateVersion: "0.1.0-test",
            coreSourceRevision: "test-revision"
        )
    }

    func protocolInfo() throws -> AppleDirectProtocolInfo {
        try checkFailure()
        return AppleDirectProtocolInfo(
            protocolAPIRevision: 1,
            supportedPairingProtocolVersions: [1, 2, 3],
            appleApplicationProtocolVersion: 1,
            manualIPPort: 17_647,
            maximumControlJSONBytes: 2 * 1_024 * 1_024,
            transferProtocolVersion: 1,
            transferFrameHeaderBytes: 66,
            maximumChunkBytes: 512 * 1_024,
            minimumPartitionBytes: 32 * 1_024 * 1_024,
            preferredPartitionBytes: 48 * 1_024 * 1_024,
            maximumPartitionBytes: 64 * 1_024 * 1_024,
            maximumInFlightChunks: 4,
            durableJobLifetimeSeconds: 7 * 24 * 60 * 60
        )
    }

    func appleV1RequestFingerprint(_ bytes: Data) throws -> String {
        try checkFailure()
        fingerprintCalls += 1
        onFingerprint?()
        return fingerprint
    }

    func canonicalAppleV1Message(_ bytes: Data) throws -> Data {
        canonicalMessageCalls += 1
        try checkFailure()
        if failCanonicalization { throw FakeError.failed }
        return returnNativeCanonicalMessage ? bytes : canonicalMessage
    }

    func encodeTransferChunk(_ chunk: CoreDirectTransferChunk) throws -> Data {
        try checkFailure()
        return frame
    }

    func negotiateTransfer(
        local: CoreDirectTransferCapabilities,
        peer: CoreDirectTransferCapabilities
    ) throws -> CoreDirectTransferNegotiation {
        try checkFailure()
        return CoreDirectTransferNegotiation(
            protocolVersion: 1,
            binaryFrameVersion: 1,
            partitionTargetBytes: 48 * 1_024 * 1_024,
            maximumInFlightChunks: 4
        )
    }

    private func checkFailure() throws {
        if failEveryCall { throw FakeError.failed }
    }

    private enum FakeError: Error { case failed }
}

#if os(iOS)
@MainActor
private final class ActivityAdmissionCapture {
    var snapshot: CLIExportActivityTracker.Snapshot?
}

private actor PendingIncomingProtocolTransport: DirectPacketTransport {
    private var packets: [ManualIPSyncPacket] = []
    private var waiter: CheckedContinuation<ManualIPSyncPacket, Error>?
    private var waitingObservers: [CheckedContinuation<Void, Never>] = []

    func send(_ packet: ManualIPSyncPacket) async throws {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: packet)
        } else {
            packets.append(packet)
        }
    }

    func receive() async throws -> ManualIPSyncPacket {
        if !packets.isEmpty { return packets.removeFirst() }
        guard waiter == nil else { throw DirectChannelError.malformedPacket }
        return try await withCheckedThrowingContinuation {
            waiter = $0
            let observers = waitingObservers
            waitingObservers.removeAll()
            observers.forEach { $0.resume() }
        }
    }

    func waitForReceiver() async {
        if waiter != nil { return }
        await withCheckedContinuation { waitingObservers.append($0) }
    }

    nonisolated func cancel() {}
}

nonisolated private final class OperationProtocolPacketTransport: DirectPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [ManualIPSyncPacket] = []
    private var authorizedSends = 0
    var authorizedSendCount: Int { lock.withLock { authorizedSends } }
    var packetCount: Int { lock.withLock { packets.count } }
    func send(_ packet: ManualIPSyncPacket) async throws { lock.withLock { packets.append(packet) } }
    func send(authorizedBy authorization: DirectPacketSendAuthorization,
              packet: @Sendable () throws -> ManualIPSyncPacket) async throws {
        lock.withLock { authorizedSends += 1 }
        let lease = try authorization.acquireLease()
        defer { lease.close() }
        let generated = try packet()
        lock.withLock { packets.append(generated) }
    }
    func receive() async throws -> ManualIPSyncPacket {
        try lock.withLock {
            guard !packets.isEmpty else { throw DirectChannelError.connectionClosed }
            return packets.removeFirst()
        }
    }
    func cancel() {}
}
#endif
