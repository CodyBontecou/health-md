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
    var fingerprint = String(repeating: "0", count: 64)
    var canonicalMessage = Data()
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
        return fingerprint
    }

    func canonicalAppleV1Message(_ bytes: Data) throws -> Data {
        try checkFailure()
        if failCanonicalization { throw FakeError.failed }
        return canonicalMessage
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
nonisolated private final class OperationProtocolPacketTransport: DirectPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [ManualIPSyncPacket] = []
    var packetCount: Int { lock.withLock { packets.count } }
    func send(_ packet: ManualIPSyncPacket) async throws { lock.withLock { packets.append(packet) } }
    func receive() async throws -> ManualIPSyncPacket {
        try lock.withLock {
            guard !packets.isEmpty else { throw DirectChannelError.connectionClosed }
            return packets.removeFirst()
        }
    }
    func cancel() {}
}
#endif
