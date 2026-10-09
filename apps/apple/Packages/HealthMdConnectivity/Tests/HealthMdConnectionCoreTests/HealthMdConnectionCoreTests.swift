import CryptoKit
import Foundation
@testable import HealthMdConnectionCore
import Network
import MultipeerConnectivity
import XCTest

final class HealthMdConnectionCoreTests: XCTestCase {
    func testDesktopDestinationLabelsRemainOpaqueAndPortableOnIPhone() {
        XCTAssertTrue(HealthMdDirectProtocol.isValidDesktopDestinationLabel("/Users/example/Health"))
        XCTAssertTrue(HealthMdDirectProtocol.isValidDesktopDestinationLabel(#"C:\Users\example\Health"#))
        XCTAssertTrue(HealthMdDirectProtocol.isValidDesktopDestinationLabel(#"\\server\share\Health"#))
        XCTAssertFalse(HealthMdDirectProtocol.isValidDesktopDestinationLabel(""))
        XCTAssertFalse(HealthMdDirectProtocol.isValidDesktopDestinationLabel("/tmp/health\nsecret"))
        XCTAssertFalse(HealthMdDirectProtocol.isValidDesktopDestinationLabel(
            String(repeating: "a", count: 4_097)
        ))
    }

    func testManualIPPairingProofAndEncryptionRemainCompatible() throws {
        let code = "123 456"
        let clientKey = Curve25519.KeyAgreement.PrivateKey()
        let serverKey = Curve25519.KeyAgreement.PrivateKey()
        let clientNonce = ManualIPSyncSecurity.randomNonce()
        let serverNonce = ManualIPSyncSecurity.randomNonce()
        let clientPublicKey = clientKey.publicKey.rawRepresentation
        let verifier = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: code,
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        )
        XCTAssertTrue(ManualIPSyncSecurity.pairingVerifierIsValid(
            verifier,
            pairingCode: "123456",
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        ))
        XCTAssertFalse(ManualIPSyncSecurity.pairingVerifierIsValid(
            verifier,
            pairingCode: "000000",
            clientPublicKey: clientPublicKey,
            clientNonce: clientNonce
        ))

        let sharedSecret = try clientKey.sharedSecretFromKeyAgreement(with: serverKey.publicKey)
        let sessionKey = ManualIPSyncSecurity.sessionKey(
            sharedSecret: sharedSecret,
            clientNonce: clientNonce,
            serverNonce: serverNonce
        )
        let plaintext = Data("healthmd-direct".utf8)
        XCTAssertEqual(
            try ManualIPSyncSecurity.open(
                ManualIPSyncSecurity.seal(plaintext, using: sessionKey),
                using: sessionKey
            ),
            plaintext
        )
    }

    func testDirectPairingProofIsDomainSeparatedFromClassicManualIP() {
        let installationID = UUID()
        let publicKey = Data(repeating: 7, count: 32)
        let nonce = Data(repeating: 9, count: 32)
        let code = "123456"
        let direct = DirectPairingSecurity.pairingVerifier(
            pairingCode: code,
            clientInstallationID: installationID,
            clientPublicKey: publicKey,
            clientNonce: nonce
        )
        let classic = ManualIPSyncSecurity.pairingVerifier(
            pairingCode: code,
            clientPublicKey: publicKey,
            clientNonce: nonce
        )
        XCTAssertNotEqual(direct, classic)
        XCTAssertTrue(DirectPairingSecurity.pairingVerifierIsValid(
            direct,
            pairingCode: code,
            clientInstallationID: installationID,
            clientPublicKey: publicKey,
            clientNonce: nonce
        ))
        XCTAssertFalse(DirectPairingSecurity.pairingVerifierIsValid(
            classic,
            pairingCode: code,
            clientInstallationID: installationID,
            clientPublicKey: publicKey,
            clientNonce: nonce
        ))
    }

    func testSharedPairingV3MatchesCanonicalCrossPlatformFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "packages/contracts/direct-protocol/pairing-v3/fixtures/shared-pairing-v3.json"
            )
        let fixture = try JSONDecoder().decode(
            SharedPairingV3Fixture.self,
            from: Data(contentsOf: fixtureURL)
        )
        XCTAssertEqual(fixture.pairingProtocolVersion, DirectPairingSecurity.sharedProtocolVersion)
        let clientID = try XCTUnwrap(UUID(uuidString: fixture.clientInstallationID))
        let serverID = try XCTUnwrap(UUID(uuidString: fixture.serverInstallationID))
        let clientPublicKey = try Data(strictHex: fixture.clientPublicKeyHex)
        let clientNonce = try Data(strictHex: fixture.clientNonceHex)
        let serverPublicKey = try Data(strictHex: fixture.serverPublicKeyHex)
        let serverNonce = try Data(strictHex: fixture.serverNonceHex)
        let sealed = ManualIPEncryptedFrame(
            nonce: try Data(strictHex: fixture.sealedNonceHex),
            ciphertext: try Data(strictHex: fixture.sealedCiphertextHex),
            tag: try Data(strictHex: fixture.sealedTagHex)
        )

        XCTAssertEqual(
            DirectPairingSecurity.sharedPairingVerifier(
                pairingCode: fixture.pairingCode,
                clientInstallationID: clientID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce
            ),
            try Data(strictHex: fixture.pairingClientVerifierHex)
        )
        XCTAssertEqual(
            DirectPairingSecurity.sharedPairingServerVerifier(
                pairingCode: fixture.pairingCode,
                clientInstallationID: clientID,
                clientPublicKey: clientPublicKey,
                clientNonce: clientNonce,
                serverInstallationID: serverID,
                serverPublicKey: serverPublicKey,
                serverNonce: serverNonce,
                sealedReconnectSecret: sealed
            ),
            try Data(strictHex: fixture.pairingServerVerifierHex)
        )
        XCTAssertEqual(
            fixture.qrPayload,
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=12345678901234567890"
        )
    }

    func testDirectMessageRoundTripsAndFingerprintIsDeterministic() throws {
        let request = DirectExportRequest(
            jobID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.987),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-07"),
            responseMode: .rawJSON,
            rawProfile: .healthDataProjection,
            canonicalSelection: DirectCanonicalSelection(
                metricIDs: ["sleep_total"],
                categories: ["Sleep"],
                objectPaths: ["/sleep"]
            )
        )
        let message = DirectMessage.exportRequest(request)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(message)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedMessage = try decoder.decode(DirectMessage.self, from: encoded)
        XCTAssertEqual(decodedMessage, message)
        XCTAssertEqual(request.createdAt.timeIntervalSince1970, 1_700_000_000)
        guard case .exportRequest(let decodedRequest) = decodedMessage else {
            return XCTFail("Expected export request")
        }
        XCTAssertEqual(
            try DirectRequestFingerprint.make(for: request),
            try DirectRequestFingerprint.make(for: decodedRequest)
        )
    }

    func testDirectQueryV3RoundTripsWithoutChangingV1Defaults() throws {
        let request = DirectQueryRequest(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.987),
            detailLevel: .summary,
            query: .object([
                "schema": .string("healthmd.query_request"),
                "schema_version": .integer(1),
                "operation": .object(["type": .string("coverage")])
            ])
        )
        let message = DirectMessage.queryRequest(request)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(message)
        let decodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let boxed = try XCTUnwrap(decodedObject["queryRequest"] as? [String: Any])
        let payload = try XCTUnwrap(boxed["_0"] as? [String: Any])
        XCTAssertEqual(payload["protocolVersion"] as? Int, 3)
        XCTAssertEqual(payload["detailLevel"] as? String, "summary")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(DirectMessage.self, from: encoded), message)

        let v1 = DirectPeerCapabilities(
            platform: .macOSCLI,
            installationID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        )
        XCTAssertEqual(v1.protocolVersions, [1])
        XCTAssertNil(v1.query)
        let queryPeer = DirectPeerCapabilities(
            protocolVersions: [1, 3],
            platform: .iOS,
            installationID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            query: .current
        )
        XCTAssertEqual(v1.negotiatedProtocolVersion(with: queryPeer), 1)
        XCTAssertEqual(DirectQueryCapabilities.current.maximumPageBytes, 1 * 1_024 * 1_024)
    }

    func testDirectQueryV3MatchesSwiftReferenceFixture() throws {
        let peer = DirectPeerCapabilities(
            protocolVersions: [1, 3],
            platform: .iOS,
            installationID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            query: .current
        )
        let requestID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        let request = DirectMessage.queryRequest(DirectQueryRequest(
            requestID: requestID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            detailLevel: .summary,
            query: .object([
                "schema": .string("healthmd.query_request"),
                "schema_version": .integer(1),
                "metrics": .object(["type": .string("all_available")]),
                "sources": .object(["type": .string("all_available")]),
                "dates": .object(["type": .string("all_available")]),
                "operation": .object(["type": .string("coverage")]),
                "page": .object([
                    "max_items": .integer(250),
                    "max_bytes": .integer(262_144),
                    "cursor": .null
                ])
            ])
        ))
        let response = DirectMessage.queryResponse(DirectQueryResponse(
            requestID: requestID,
            response: .object([
                "schema": .string("healthmd.query_response"),
                "schema_version": .integer(1),
                "items": .array([]),
                "packet": .null,
                "coverage": .object([
                    "status": .string("complete_empty"),
                    "days_considered": .integer(0),
                    "days_with_values": .integer(0),
                    "missing": .array([])
                ]),
                "sources": .array([]),
                "evidence": .array([]),
                "next_cursor": .null,
                "limitations": .array([]),
                "metadata": .object([:])
            ])
        ))
        let rejected = DirectMessage.queryRejected(DirectQueryFailure(
            requestID: requestID,
            code: "query_unavailable",
            message: "The iPhone could not complete the direct query.",
            retryable: true
        ))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func object<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        let fixture: [String: Any] = [
            "schema": "healthmd.direct_query_swift_reference",
            "schema_version": 1,
            "hello": try object(DirectMessage.hello(peer)),
            "query_request": try object(request),
            "query_response": try object(response),
            "query_rejected": try object(rejected)
        ]
        let fixtureData = try JSONSerialization.data(
            withJSONObject: fixture,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("packages/contracts/direct-protocol/v3/fixtures/swift-reference.json")
        if ProcessInfo.processInfo.environment["HEALTHMD_UPDATE_DIRECT_QUERY_FIXTURE"] == "1" {
            try FileManager.default.createDirectory(
                at: fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fixtureData.write(to: fixtureURL, options: .atomic)
        }
        let committed = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: committed) as? NSDictionary,
            try JSONSerialization.jsonObject(with: fixtureData) as? NSDictionary
        )
    }

    func testWakeEnrollmentAndCapabilityUseExactWireShapes() throws {
        let key = Data(repeating: 7, count: 32)
        let enrollment = DirectWakeEnrollment(
            wakeID: "wake-opaque-one",
            wakeKey: key.base64EncodedString()
        )
        XCTAssertTrue(enrollment.isValid)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let message = try JSONSerialization.jsonObject(
            with: encoder.encode(DirectMessage.wakeEnrollment(enrollment))
        ) as? [String: Any]
        let wrapped = message?["wakeEnrollment"] as? [String: Any]
        let payload = wrapped?["_0"] as? [String: Any]
        XCTAssertEqual(payload?.count, 2)
        XCTAssertEqual(payload?["wakeID"] as? String, "wake-opaque-one")
        XCTAssertEqual(payload?["wakeKey"] as? String, key.base64EncodedString())

        let capabilities = DirectPeerCapabilities(
            platform: .iOS,
            installationID: UUID(),
            wake: DirectWakeCapabilities(supported: true)
        )
        let capabilitiesData = try encoder.encode(capabilities)
        let decoded = try JSONDecoder().decode(DirectPeerCapabilities.self, from: capabilitiesData)
        XCTAssertEqual(decoded.wake, DirectWakeCapabilities(supported: true))
        // A hello without the wake field decodes as unsupported — older peers stay compatible.
        var legacy = try JSONSerialization.jsonObject(with: capabilitiesData) as! [String: Any]
        legacy.removeValue(forKey: "wake")
        let legacyDecoded = try JSONDecoder().decode(
            DirectPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(legacyDecoded.wake)
    }

    func testWakeEnrollmentValidityFailsClosed() {
        let validKey = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertFalse(DirectWakeEnrollment(wakeID: "", wakeKey: validKey).isValid)
        XCTAssertFalse(
            DirectWakeEnrollment(
                wakeID: String(repeating: "a", count: 129), wakeKey: validKey
            ).isValid
        )
        XCTAssertFalse(DirectWakeEnrollment(wakeID: "bad\nkey", wakeKey: validKey).isValid)
        XCTAssertFalse(
            DirectWakeEnrollment(
                wakeID: "ok", wakeKey: Data(repeating: 1, count: 31).base64EncodedString()
            ).isValid
        )
        XCTAssertFalse(DirectWakeEnrollment(wakeID: "ok", wakeKey: "not base64 !!").isValid)
    }

    func testProfilePolicyMatchesSwiftReferenceFixture() throws {
        // Export-profiles decision 10: byte-exact reference vectors for the
        // additive settings_policy=profile request shape. Values deliberately
        // interlock with the Rust healthmd-protocol profile_policy vectors so
        // both suites prove the same wire bytes.
        let request = DirectExportRequest(
            jobID: UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.987),
            dateSelection: .exact(start: "2026-08-01", end: "2026-08-07"),
            settingsPolicy: .profile,
            profileReference: DirectProfileReference(
                profileID: "11111111-2222-4333-8444-555555555555",
                name: "Weekly Sleep"
            ),
            responseMode: .writeFiles
        )
        let unnamedReferenceRequest = DirectExportRequest(
            jobID: request.jobID,
            createdAt: request.createdAt,
            dateSelection: request.dateSelection,
            settingsPolicy: .profile,
            profileReference: DirectProfileReference(
                profileID: "11111111-2222-4333-8444-555555555555"
            ),
            responseMode: .writeFiles
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let requestBytes = try encoder.encode(request)
        let messageBytes = try encoder.encode(DirectMessage.exportRequest(request))
        let unnamedReferenceBytes = try encoder.encode(unnamedReferenceRequest)

        // The profile policy survives a wire round trip with the reference
        // still pinned to the profile UUID (and the name still optional).
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(DirectExportRequest.self, from: requestBytes), request)
        XCTAssertEqual(
            try decoder.decode(DirectExportRequest.self, from: unnamedReferenceBytes),
            unnamedReferenceRequest
        )
        XCTAssertEqual(request.createdAt, Date(timeIntervalSince1970: 1_700_000_000))

        let fingerprint = try DirectRequestFingerprint.make(for: request)
        let fixture: [String: Any] = [
            "schema": "healthmd.direct_profile_policy_swift_reference",
            "schema_version": 1,
            "profile_request_json_base64": requestBytes.base64EncodedString(),
            "profile_request_message_json_base64": messageBytes.base64EncodedString(),
            "profile_request_fingerprint": fingerprint.sha256,
            "profile_request_unnamed_reference_json_base64": unnamedReferenceBytes.base64EncodedString()
        ]
        let fixtureData = try JSONSerialization.data(
            withJSONObject: fixture,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("packages/contracts/direct-protocol/v1/fixtures/profile-policy-swift-reference.json")
        if ProcessInfo.processInfo.environment["HEALTHMD_UPDATE_PROFILE_POLICY_FIXTURE"] == "1" {
            try FileManager.default.createDirectory(
                at: fixtureURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fixtureData.write(to: fixtureURL, options: .atomic)
        }
        let committed = try Data(contentsOf: fixtureURL)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: committed) as? NSDictionary,
            try JSONSerialization.jsonObject(with: fixtureData) as? NSDictionary
        )
    }

    func testLegacyPeerFailsClosedOnProfileSettingsPolicy() throws {
        // Export-profiles decision 10, new-CLI/old-phone combination: a
        // pre-profile Swift peer's decoder has no "profile" variant and must
        // reject the unknown value instead of defaulting or misinterpreting
        // the request. Mirrors the Rust old-peer combination test.
        struct LegacyRequest: Decodable {
            let settingsPolicy: LegacySettingsPolicy
        }
        enum LegacySettingsPolicy: String, Decodable {
            case requestedDatesOnly = "requested_dates_only"
            case currentIPhoneSettings = "current_iphone_settings"
        }

        let payload = #"{"settingsPolicy":"profile"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(LegacyRequest.self, from: payload))
    }

    func testLegacyPeerIgnoresUnknownProfileReferenceField() throws {
        // Additive struct field: a legacy decoder that knows only the old
        // request fields skips profileReference instead of failing the whole
        // decode. Mirrors the Rust old-peer field-ignore test.
        struct LegacyRequest: Decodable {
            let responseMode: String
        }

        let payload =
            #"{"responseMode":"write_files","profileReference":{"profileID":"11111111-2222-4333-8444-555555555555"}}"#
        let legacy = try JSONDecoder().decode(
            LegacyRequest.self,
            from: payload.data(using: .utf8)!
        )
        XCTAssertEqual(legacy.responseMode, "write_files")
    }

    func testReadyPacketConnectionSurvivesItsStartupTimeout() async throws {
        let listenerReady = expectation(description: "listener ready")
        let serverReceivedPacket = expectation(description: "server received packet")
        let queue = DispatchQueue(label: "healthmd.connection-timeout-test")
        let listener = try NWListener(using: .tcp)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                listenerReady.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) {
                data, _, _, _ in
                if data?.isEmpty == false {
                    serverReceivedPacket.fulfill()
                }
            }
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        await fulfillment(of: [listenerReady], timeout: 1)

        let port = try XCTUnwrap(listener.port)
        let networkConnection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: port,
            using: .tcp
        )
        let packetConnection = DirectPacketConnection(
            connection: networkConnection,
            queue: queue
        )
        defer { packetConnection.cancel() }

        try await packetConnection.start(timeout: 0.05)
        try await Task.sleep(nanoseconds: 150_000_000)
        try await packetConnection.send(.pairingRejected(
            ManualIPPairingRejected(reason: "still connected")
        ))
        await fulfillment(of: [serverReceivedPacket], timeout: 1)
    }

    func testMultipeerAuthorizedEnqueueHoldsLeaseThroughSDKSubmissionAndClosesOnError() async throws {
        let state = EnqueueAuthorizationState()
        let peer = MCPeerID(displayName: "synthetic-remote")
        let session = EnqueueProbeMCSession(remotePeer: peer, state: state)
        let connection: any DirectPacketTransport = DirectMultipeerPacketConnection(session: session, remotePeer: peer)
        defer { connection.cancel() }
        let authorization = DirectPacketSendAuthorization { try state.acquire() }
        let packet = ManualIPSyncPacket.pairingRejected(ManualIPPairingRejected(reason: "synthetic"))
        state.revoke()
        do {
            try await connection.send(authorizedBy: authorization) {
                XCTFail("Revocation must reject before the packet factory")
                return packet
            }
            XCTFail("Expected revocation")
        } catch { XCTAssertEqual(error as? EnqueueAuthorizationState.Failure, .revoked) }
        XCTAssertEqual(session.submissionCount, 0)
        state.restore()
        try await connection.send(authorizedBy: authorization) {
            XCTAssertTrue(state.held)
            return packet
        }
        XCTAssertFalse(state.held)
        XCTAssertEqual(session.submissionCount, 1)
        XCTAssertTrue(session.ownerHeldAtSubmission)
        let data = try XCTUnwrap(session.lastData)
        XCTAssertEqual(try JSONDecoder().decode(ManualIPSyncPacket.self, from: data), packet)
        session.failNextSubmission()
        do {
            try await connection.send(authorizedBy: authorization) { packet }
            XCTFail("SDK failure must propagate")
        } catch {
            guard case .connectionFailed = error as? DirectChannelError else {
                return XCTFail("Expected the bounded SDK send error, got \(error)")
            }
        }
        XCTAssertFalse(state.held)
        XCTAssertEqual(session.submissionCount, 2)
        XCTAssertTrue(session.ownerHeldAtSubmission)
        // Pairing's existing ordinary path uses the same encoder/submission.
        try await connection.send(packet)
        XCTAssertEqual(session.submissionCount, 3)
        XCTAssertFalse(session.ownerHeldAtSubmission)
    }

    func testNativePacketEnqueueAcquiresAndClosesAuthorizationLease() async throws {
        let ready = expectation(description: "owned listener ready")
        let received = expectation(description: "owned packet received")
        let queue = DispatchQueue(label: "healthmd.owned-enqueue-test")
        let listener = try NWListener(using: .tcp)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { data, _, _, _ in
                if data?.isEmpty == false { received.fulfill() }
            }
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        await fulfillment(of: [ready], timeout: 2)
        let connection = DirectPacketConnection(connection: NWConnection(
            host: NWEndpoint.Host("127.0.0.1"), port: try XCTUnwrap(listener.port), using: .tcp), queue: queue)
        defer { connection.cancel() }
        try await connection.start()
        let state = EnqueueAuthorizationState()
        let authorization = DirectPacketSendAuthorization { try state.acquire() }
        state.revoke()
        do {
            try await connection.send(authorizedBy: authorization) {
                XCTFail("Revoked ownership must reject before producing packet bytes")
                return .pairingRejected(ManualIPPairingRejected(reason: "synthetic"))
            }
            XCTFail("Expected revocation")
        } catch { XCTAssertEqual(error as? EnqueueAuthorizationState.Failure, .revoked) }
        state.restore()
        try await connection.send(authorizedBy: authorization) {
            XCTAssertTrue(state.held)
            return .pairingRejected(ManualIPPairingRejected(reason: "synthetic authorized enqueue"))
        }
        XCTAssertFalse(state.held)
        await fulfillment(of: [received], timeout: 2)
    }

    func testQueuedOwnedSendRejectsRevocationBeforeSequenceAllocation() async throws {
        let state = EnqueueAuthorizationState()
        let transport = OwnedQueuePacketTransport(state: state)
        let channel = DirectSecureChannel(packetConnection: transport,
            sessionKey: SymmetricKey(data: Data(repeating: 0x42, count: 32)),
            peerInstallationID: UUID(), peerDisplayName: "synthetic")
        let first = Task { try await channel.send(.ping) }
        await transport.blocker.waitUntilBlocked()
        let authorization = DirectPacketSendAuthorization { try state.acquire() }
        let queued = Task { try await channel.send(.ping, authorization: authorization) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await channel.pendingSendCount() == 0, clock.now < deadline { await Task.yield() }
        let pending = await channel.pendingSendCount()
        XCTAssertEqual(pending, 1)
        XCTAssertEqual(state.attempts, 0)
        state.revoke()
        await transport.blocker.release()
        try await first.value
        do {
            try await queued.value
            XCTFail("A queued send must acquire current ownership before its packet factory runs")
        } catch { XCTAssertEqual(error as? EnqueueAuthorizationState.Failure, .revoked) }
        XCTAssertEqual(transport.packetCount, 1)
        state.restore()
        try await channel.send(.ping, authorization: authorization)
        XCTAssertEqual(transport.leaseObservations, [true])
        XCTAssertFalse(state.held)
        // Rejection consumed no sequence: the next packet is authenticated as sequence one.
        for _ in 0..<2 {
            guard case .message(.ping) = try await channel.receive() else {
                return XCTFail("Expected consecutive authenticated ping packets")
            }
        }
    }

    func testUnadaptedTransportRejectsAuthorizationWithoutConsumingSequence() async throws {
        let transport = ReplayPacketTransport()
        let state = EnqueueAuthorizationState()
        let channel = DirectSecureChannel(packetConnection: transport,
            sessionKey: SymmetricKey(data: Data(repeating: 0x42, count: 32)),
            peerInstallationID: UUID(), peerDisplayName: "synthetic")
        do {
            try await channel.send(.ping, authorization: DirectPacketSendAuthorization { try state.acquire() })
            XCTFail("Ordinary asynchronous transport cannot bypass enqueue authorization")
        } catch {
            guard case DirectChannelError.authenticationFailed = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(state.attempts, 0)
        let legacySend: (DirectMessage) async throws -> Void = channel.send
        let legacyBinarySend: (Data) async throws -> Void = channel.sendBinaryTransferFrame
        _ = legacyBinarySend
        try await legacySend(.ping)
        guard case .message(.ping) = try await channel.receive() else { return XCTFail("Expected sequence zero") }
    }

    func testDirectSecureChannelRejectsReplayedPacket() async throws {
        let transport = ReplayPacketTransport()
        let channel = DirectSecureChannel(
            packetConnection: transport,
            sessionKey: SymmetricKey(data: Data(repeating: 0x42, count: 32)),
            peerInstallationID: UUID(),
            peerDisplayName: "test"
        )
        try await channel.send(.ping)
        transport.duplicateLastPacket()
        guard case .message(.ping) = try await channel.receive() else {
            return XCTFail("Expected the first authenticated packet")
        }
        do {
            _ = try await channel.receive()
            XCTFail("Expected replay rejection")
        } catch let error as DirectChannelError {
            XCTAssertEqual(error, .replayedPacket)
        }
    }

    func testDirectClientCanRestoreThePrePairingTrustSnapshot() throws {
        let installationID = UUID()
        let original = ManualIPTrustedMac(
            installationID: UUID(),
            displayName: "original CLI",
            host: "192.168.1.10",
            port: 17_647,
            reconnectSecret: Data(repeating: 0x4a, count: 32),
            pairedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let replacement = ManualIPTrustedMac(
            installationID: UUID(),
            displayName: "replacement CLI",
            host: "192.168.1.11",
            port: 17_648,
            reconnectSecret: Data(repeating: 0x5b, count: 32),
            pairedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let trustStore = InMemoryDirectTrustStore(state: ManualIPTrustState(
            ownerInstallationID: installationID,
            trustedMac: original
        ))
        let client = DirectManualIPClient(
            installationID: installationID,
            displayName: "test iPhone",
            trustStore: trustStore
        )

        try client.restoreSavedServer(replacement)
        XCTAssertEqual(client.savedServer(), replacement)
        try client.restoreSavedServer(original)
        XCTAssertEqual(client.savedServer(), original)
        try client.restoreSavedServer(nil)
        XCTAssertNil(client.savedServer())
    }

    func testLegacyTrustStateDecodesWithoutAProvisionalCredential() throws {
        let owner = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "ownerInstallationID": owner.uuidString,
            "trustedClients": []
        ])
        let state = try JSONDecoder().decode(ManualIPTrustState.self, from: data)
        XCTAssertEqual(state.ownerInstallationID, owner)
        XCTAssertNil(state.trustedMac)
        XCTAssertNil(state.provisionalTrustedMac)
    }

    func testProvisionalDirectTrustIsIgnoredUntilPeerHelloCommitsIt() throws {
        let installationID = UUID()
        let provisional = ManualIPTrustedMac(
            installationID: UUID(),
            displayName: "provisional CLI",
            host: "192.168.1.12",
            port: 17_647,
            reconnectSecret: Data(repeating: 0x6c, count: 32),
            pairedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let trustStore = InMemoryDirectTrustStore(state: ManualIPTrustState(
            ownerInstallationID: installationID,
            provisionalTrustedMac: provisional
        ))
        let client = DirectManualIPClient(
            installationID: installationID,
            displayName: "test iPhone",
            trustStore: trustStore
        )

        XCTAssertNil(client.savedServer())
        try client.commitProvisionalServer()
        XCTAssertEqual(client.savedServer(), provisional)
        try client.restoreSavedServer(nil)
    }

    func testNearbyContinuousWaitIsCancelledWithoutWaitingForATimeout() async throws {
        let installationID = UUID()
        let state = ManualIPTrustState(
            ownerInstallationID: installationID,
            trustedMac: ManualIPTrustedMac(
                installationID: UUID(),
                displayName: "paired healthmd CLI",
                host: "nearby",
                port: 0,
                reconnectSecret: Data(repeating: 0x5a, count: 32),
                pairedAt: Date()
            )
        )
        let client = DirectNearbyClient(
            installationID: installationID,
            displayName: "test iPhone",
            trustStore: InMemoryDirectTrustStore(state: state)
        )
        let wait = Task {
            try await client.connectWaitingForServer()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        wait.cancel()

        do {
            _ = try await wait.value
            XCTFail("Expected the continuous nearby wait to stop on cancellation")
        } catch let error as DirectChannelError {
            XCTAssertEqual(error, .connectionClosed)
        }
    }

    func testDirectTransferNegotiationAndBinaryFrameAreBounded() throws {
        let negotiation = try XCTUnwrap(
            DirectTransferCapabilities.current.negotiated(with: .current)
        )
        XCTAssertEqual(negotiation.partitionTargetBytes, DirectTransferLimits.preferredPartitionBytes)
        XCTAssertEqual(negotiation.maximumInFlightChunks, 4)

        let payload = Data(repeating: 0xab, count: 4_096)
        let digest = DirectTransferFile.sha256Hex(payload)
        let chunk = try DirectTransferChunk(
            transferID: UUID(),
            sequence: 1,
            data: payload,
            sha256: digest
        )
        let frame = try DirectTransferBinaryFrame.encode(chunk)
        XCTAssertTrue(DirectTransferBinaryFrame.isBinaryFrame(frame))
        let decoded = try DirectTransferBinaryFrame.decode(frame)
        XCTAssertEqual(decoded.version, DirectTransferBinaryFrame.currentVersion)
        XCTAssertEqual(decoded.chunk, chunk)

        XCTAssertThrowsError(try DirectTransferChunk(
            transferID: UUID(),
            sequence: 1,
            data: Data(repeating: 0, count: DirectTransferLimits.chunkBytes + 1),
            sha256: digest
        ))

        let logicalItemBytes = 160 * 1_024 * 1_024 as Int64
        let firstSegment = try DirectTransferItemSegment(
            itemID: "2026-07-01",
            offset: 0,
            itemByteCount: logicalItemBytes,
            isFinalSegment: false
        )
        XCTAssertNoThrow(try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: ["2026-07-01"],
            byteCount: DirectTransferLimits.preferredPartitionBytes,
            chunkCount: 96,
            sha256: String(repeating: "a", count: 64),
            previousSHA256: nil,
            itemSegment: firstSegment
        ))
        XCTAssertThrowsError(try DirectTransferItemSegment(
            itemID: "2026-07-01",
            offset: logicalItemBytes + 1,
            itemByteCount: logicalItemBytes,
            isFinalSegment: true
        ))
    }

    func testDirectTransferFileInspectionHashesLargeFileExactly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "healthmd-direct-inspect-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("artifact.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        let chunk = Data((0..<(256 * 1_024)).map { UInt8(truncatingIfNeeded: $0) })
        var expectedHasher = SHA256()
        for _ in 0..<64 {
            try handle.write(contentsOf: chunk)
            expectedHasher.update(data: chunk)
        }
        try handle.close()

        let inspected = try DirectTransferFile.inspect(file)

        XCTAssertEqual(inspected.totalBytes, 16 * 1_024 * 1_024)
        XCTAssertEqual(
            inspected.sha256,
            Data(expectedHasher.finalize()).map { String(format: "%02x", $0) }.joined()
        )
        let symbolicLink = directory.appendingPathComponent("artifact-link.bin")
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: file)
        XCTAssertThrowsError(try DirectTransferFile.inspect(symbolicLink))
        XCTAssertThrowsError(try DirectTransferFile.inspect(directory))
    }
}

private struct SharedPairingV3Fixture: Decodable {
    let pairingProtocolVersion: Int
    let pairingCode: String
    let clientInstallationID: String
    let clientPublicKeyHex: String
    let clientNonceHex: String
    let serverInstallationID: String
    let serverPublicKeyHex: String
    let serverNonceHex: String
    let sealedNonceHex: String
    let sealedCiphertextHex: String
    let sealedTagHex: String
    let pairingClientVerifierHex: String
    let pairingServerVerifierHex: String
    let qrPayload: String

    enum CodingKeys: String, CodingKey {
        case pairingProtocolVersion = "pairing_protocol_version"
        case pairingCode = "pairing_code"
        case clientInstallationID = "client_installation_id"
        case clientPublicKeyHex = "client_public_key_hex"
        case clientNonceHex = "client_nonce_hex"
        case serverInstallationID = "server_installation_id"
        case serverPublicKeyHex = "server_public_key_hex"
        case serverNonceHex = "server_nonce_hex"
        case sealedNonceHex = "sealed_nonce_hex"
        case sealedCiphertextHex = "sealed_ciphertext_hex"
        case sealedTagHex = "sealed_tag_hex"
        case pairingClientVerifierHex = "pairing_client_verifier_hex"
        case pairingServerVerifierHex = "pairing_server_verifier_hex"
        case qrPayload = "qr_payload"
    }
}

private enum StrictHexError: Error {
    case invalid
}

private extension Data {
    init(strictHex value: String) throws {
        guard value.utf8.count.isMultiple(of: 2),
              value.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else { throw StrictHexError.invalid }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw StrictHexError.invalid
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

private final class InMemoryDirectTrustStore: ManualIPTrustStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ManualIPTrustState

    init(state: ManualIPTrustState) {
        self.state = state
    }

    func loadState(ownerInstallationID: UUID) -> ManualIPTrustState {
        lock.withLock {
            state.ownerInstallationID == ownerInstallationID
                ? state
                : ManualIPTrustState(ownerInstallationID: ownerInstallationID)
        }
    }

    func saveState(_ state: ManualIPTrustState) throws {
        lock.withLock { self.state = state }
    }
}

private final class ReplayPacketTransport: DirectPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [ManualIPSyncPacket] = []

    func send(_ packet: ManualIPSyncPacket) async throws {
        lock.withLock { packets.append(packet) }
    }

    func receive() async throws -> ManualIPSyncPacket {
        try lock.withLock {
            guard !packets.isEmpty else { throw DirectChannelError.connectionClosed }
            return packets.removeFirst()
        }
    }

    func cancel() {}

    func duplicateLastPacket() {
        lock.lock()
        if let packet = packets.last { packets.append(packet) }
        lock.unlock()
    }
}

private final class EnqueueAuthorizationState: @unchecked Sendable {
    enum Failure: Error, Equatable { case revoked }
    private let lock = NSLock()
    private var permitted = true
    private var active = false
    private var count = 0
    var attempts: Int { lock.withLock { count } }
    var held: Bool { lock.withLock { active } }
    func revoke() { lock.withLock { permitted = false } }
    func restore() { lock.withLock { permitted = true } }
    func acquire() throws -> any DirectPacketSendLease {
        try lock.withLock {
            count += 1
            guard permitted else { throw Failure.revoked }
            active = true
            return Lease(state: self)
        }
    }
    private func release() { lock.withLock { active = false } }
    private final class Lease: DirectPacketSendLease {
        let state: EnqueueAuthorizationState
        init(state: EnqueueAuthorizationState) { self.state = state }
        func close() { state.release() }
    }
}

private actor FirstPacketBlocker {
    private var didBlock = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?
    func blockFirst() async {
        guard !didBlock else { return }
        didBlock = true
        observers.forEach { $0.resume() }
        observers.removeAll()
        await withCheckedContinuation { completion = $0 }
    }
    func waitUntilBlocked() async {
        if didBlock { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { completion?.resume(); completion = nil }
}

private final class OwnedQueuePacketTransport: DirectPacketTransport, @unchecked Sendable {
    let blocker = FirstPacketBlocker()
    let state: EnqueueAuthorizationState
    private let lock = NSLock()
    private var packets: [ManualIPSyncPacket] = []
    private var observations: [Bool] = []
    init(state: EnqueueAuthorizationState) { self.state = state }
    var packetCount: Int { lock.withLock { packets.count } }
    var leaseObservations: [Bool] { lock.withLock { observations } }
    func send(_ packet: ManualIPSyncPacket) async throws {
        lock.withLock { packets.append(packet) }
        await blocker.blockFirst()
    }
    func send(authorizedBy authorization: DirectPacketSendAuthorization,
              packet: @Sendable () throws -> ManualIPSyncPacket) async throws {
        do {
            let lease = try authorization.acquireLease()
            defer { lease.close() }
            let generated = try packet()
            lock.withLock { observations.append(state.held); packets.append(generated) }
        }
        await blocker.blockFirst()
    }
    func receive() async throws -> ManualIPSyncPacket {
        try lock.withLock {
            guard !packets.isEmpty else { throw DirectChannelError.connectionClosed }
            return packets.removeFirst()
        }
    }
    func cancel() {}
}

private final class EnqueueProbeMCSession: MCSession, @unchecked Sendable {
    private let remotePeer: MCPeerID
    private let state: EnqueueAuthorizationState
    private let probeLock = NSLock()
    private var submissions = 0
    private var heldAtSubmission = false
    private var data: Data?
    private var failNext = false
    var submissionCount: Int { probeLock.withLock { submissions } }
    var ownerHeldAtSubmission: Bool { probeLock.withLock { heldAtSubmission } }
    var lastData: Data? { probeLock.withLock { data } }
    init(remotePeer: MCPeerID, state: EnqueueAuthorizationState) {
        self.remotePeer = remotePeer
        self.state = state
        super.init(peer: MCPeerID(displayName: "synthetic-local"), securityIdentity: nil,
            encryptionPreference: .required)
    }
    override var connectedPeers: [MCPeerID] { [remotePeer] }
    func failNextSubmission() { probeLock.withLock { failNext = true } }
    override func send(_ data: Data, toPeers peerIDs: [MCPeerID], with mode: MCSessionSendDataMode) throws {
        XCTAssertEqual(peerIDs, [remotePeer])
        XCTAssertEqual(mode, .reliable)
        try probeLock.withLock {
            submissions += 1
            heldAtSubmission = state.held
            self.data = data
            if failNext {
                failNext = false
                throw ProbeFailure.sdkSend
            }
        }
    }
    private enum ProbeFailure: Error { case sdkSend }
}
