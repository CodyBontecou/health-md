import Foundation
import HealthMdCoreRust
import XCTest

final class ProtocolFoundationTests: XCTestCase {
    private let service = HealthMdCoreService()

    func testCanonicalV1V2FixturesAndProtocolInfoCrossPackagedBoundary() throws {
        let info = try service.directProtocolInfo()
        XCTAssertEqual(info.protocolApiRevision, 1)
        XCTAssertEqual(info.directPairingProtocolVersion, 1)
        XCTAssertEqual(info.supportedPairingProtocolVersions, [1, 2])
        XCTAssertEqual(info.appleApplicationProtocolVersion, 1)
        XCTAssertEqual(info.androidApplicationProtocolVersion, 2)
        XCTAssertEqual(info.manualIpPort, 17_647)
        XCTAssertEqual(info.maximumControlJsonBytes, 2 * 1_024 * 1_024)
        XCTAssertEqual(info.maximumChunkBytes, 512 * 1_024)
        XCTAssertEqual(info.maximumTransferFrameBytes, 512 * 1_024 + 66)

        let v1Request = try XCTUnwrap(Data(base64Encoded: Self.v1RequestBase64))
        XCTAssertEqual(
            try service.appleV1RequestFingerprint(canonicalRequest: v1Request),
            "b5e762d7e2c4533909c2416814a816347c3624b8254bbbe8dd906cf34b48493a"
        )
        let v1Message = try XCTUnwrap(Data(base64Encoded: Self.v1MessageBase64))
        XCTAssertEqual(try service.canonicalAppleV1Message(v1Message), v1Message)

        let v2Request = try XCTUnwrap(Data(base64Encoded: Self.v2RequestBase64))
        XCTAssertEqual(
            try service.androidV2RequestFingerprint(canonicalRequest: v2Request),
            "04be99c9a9aa5ee13c49063032109dafd9c864386f9890809b0111dd6ddfed33"
        )
        let v2Envelope = try XCTUnwrap(Data(base64Encoded: Self.v2EnvelopeBase64))
        XCTAssertEqual(try service.canonicalAndroidV2Envelope(v2Envelope), v2Envelope)
    }

    func testTransferFrameAndNegotiationUseOnlyOpaqueFixtureBytes() throws {
        let frame = try XCTUnwrap(Data(base64Encoded: Self.binaryFrameBase64))
        let chunk = try service.decodeTransferChunk(frame)
        XCTAssertEqual(chunk.transferId, "11111111-2222-4333-8444-555555555555")
        XCTAssertEqual(chunk.sequence, 1)
        XCTAssertEqual(chunk.chunkBytes, Data(repeating: 0xab, count: 32))
        XCTAssertEqual(try service.encodeTransferChunk(chunk), frame)

        let capabilities = try service.defaultTransferCapabilities()
        let negotiated = try service.negotiateTransfer(local: capabilities, peer: capabilities)
        XCTAssertEqual(negotiated.protocolVersion, 1)
        XCTAssertEqual(negotiated.binaryFrameVersion, 1)
        XCTAssertEqual(negotiated.partitionTargetBytes, 48 * 1_024 * 1_024)
        XCTAssertEqual(negotiated.maximumInFlightChunks, 4)
    }

    func testReviewedStatelessCryptoVectorsAndStableHealthFreeErrors() throws {
        var request = CoreDirectPairingVerifierRequest(
            profile: .appleV1,
            pairingCodeBytes: Data("123456".utf8),
            clientInstallationId: "abcdefab-cdef-4abc-8def-abcdefabcdef",
            clientPublicKey: Data(hex: "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f"),
            clientNonce: Data((0x40 ... 0x5f).map(UInt8.init)),
            expectedVerifier: Data(hex: "9dadfaf54d6729b004aa0a6344f7df42b4de0093cbf5cca6fe62376acbad00df")
        )
        defer {
            request.pairingCodeBytes.resetBytes(in: request.pairingCodeBytes.indices)
        }
        XCTAssertTrue(try service.verifyPairingClientTranscript(request))

        var keyRequest = CoreDirectSessionKeyRequest(
            sharedSecret: Data(hex: "9663aa1da97e848a914a436d04163dfbb89178f107f1b5b77ed3854203382854"),
            clientNonce: Data((0x40 ... 0x5f).map(UInt8.init)),
            serverNonce: Data((0x60 ... 0x7f).map(UInt8.init))
        )
        defer {
            keyRequest.sharedSecret.resetBytes(in: keyRequest.sharedSecret.indices)
        }
        var sessionKey = try service.deriveSessionKey(keyRequest)
        XCTAssertEqual(
            sessionKey,
            Data(hex: "47cea6b163b799c16e44a750893eab311521060a7266a59ec054d53f71b698e9")
        )
        sessionKey.resetBytes(in: sessionKey.indices)

        var noncanonical = Data(" ".utf8)
        noncanonical.append(try XCTUnwrap(Data(base64Encoded: Self.v1RequestBase64)))
        XCTAssertThrowsError(
            try service.appleV1RequestFingerprint(canonicalRequest: noncanonical)
        ) { error in
            let protocolError = error as? HealthMdProtocolServiceError
            XCTAssertEqual(protocolError, .nonCanonicalJSON)
            XCTAssertEqual(protocolError?.code, "non_canonical_protocol_json")
            XCTAssertEqual(protocolError?.message, "protocol JSON is not canonical")
            XCTAssertFalse(error.localizedDescription.contains("sleep_total"))
        }
    }

    private static let v1RequestBase64 = "eyJjYW5vbmljYWxTZWxlY3Rpb24iOnsiYWxsTWV0cmljcyI6ZmFsc2UsImNhdGVnb3JpZXMiOlsiU2xlZXAiXSwiZGV0YWlsTGV2ZWwiOiJzdW1tYXJ5IiwiZmllbGRQb2ludGVycyI6W10sIm1ldHJpY0lEcyI6WyJzbGVlcF90b3RhbCJdLCJvYmplY3RQYXRocyI6WyIvc2xlZXAiXSwic291cmNlSURzIjpbImFwcGxlX2hlYWx0aCJdfSwiY3JlYXRlZEF0IjoiMjAyMy0xMS0xNFQyMjoxMzoyMFoiLCJkYXRlU2VsZWN0aW9uIjp7ImV4YWN0Ijp7ImVuZCI6IjIwMjYtMDctMDciLCJzdGFydCI6IjIwMjYtMDctMDEifX0sImpvYklEIjoiMDAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxIiwicHJvdG9jb2xWZXJzaW9uIjoxLCJyYXdQcm9maWxlIjoiaGVhbHRoX2RhdGFfcHJvamVjdGlvbiIsInJlc3BvbnNlTW9kZSI6InJhd19qc29uIiwic2V0dGluZ3NQb2xpY3kiOiJyZXF1ZXN0ZWRfZGF0ZXNfb25seSJ9"
    private static let v1MessageBase64 = "eyJleHBvcnRSZXF1ZXN0Ijp7Il8wIjp7ImNhbm9uaWNhbFNlbGVjdGlvbiI6eyJhbGxNZXRyaWNzIjpmYWxzZSwiY2F0ZWdvcmllcyI6WyJTbGVlcCJdLCJkZXRhaWxMZXZlbCI6InN1bW1hcnkiLCJmaWVsZFBvaW50ZXJzIjpbXSwibWV0cmljSURzIjpbInNsZWVwX3RvdGFsIl0sIm9iamVjdFBhdGhzIjpbIi9zbGVlcCJdLCJzb3VyY2VJRHMiOlsiYXBwbGVfaGVhbHRoIl19LCJjcmVhdGVkQXQiOiIyMDIzLTExLTE0VDIyOjEzOjIwWiIsImRhdGVTZWxlY3Rpb24iOnsiZXhhY3QiOnsiZW5kIjoiMjAyNi0wNy0wNyIsInN0YXJ0IjoiMjAyNi0wNy0wMSJ9fSwiam9iSUQiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJwcm90b2NvbFZlcnNpb24iOjEsInJhd1Byb2ZpbGUiOiJoZWFsdGhfZGF0YV9wcm9qZWN0aW9uIiwicmVzcG9uc2VNb2RlIjoicmF3X2pzb24iLCJzZXR0aW5nc1BvbGljeSI6InJlcXVlc3RlZF9kYXRlc19vbmx5In19fQ=="
    private static let v2RequestBase64 = "eyJjcmVhdGVkX2F0IjoiMjAyNi0wNy0yNFQxMDoxMToxMloiLCJkYXRlX3NlbGVjdGlvbiI6eyJlbmRfZGF0ZSI6IjIwMjYtMDctMDIiLCJzdGFydF9kYXRlIjoiMjAyNi0wNy0wMSIsInR5cGUiOiJleGFjdCJ9LCJleHBpcmVzX2F0IjoiMjAyNi0wNy0zMVQxMDoxMToxMloiLCJqb2JfaWQiOiJhYWFhYWFhYS1iYmJiLTRjY2MtOGRkZC1lZWVlZWVlZWVlZWUiLCJwcm9kdWN0Ijp7ImZvcm1hdCI6Im5kanNvbiIsImluY2x1ZGVfZXhlcmNpc2Vfcm91dGVzIjpmYWxzZSwicHJvZHVjdF9pZCI6ImFuZHJvaWRfcHJvdmlkZXJfbmF0aXZlX3NuYXBzaG90X3YxIiwicHJvdmlkZXJfaWQiOiJoZWFsdGhfY29ubmVjdCIsInNjb3BlIjp7InNlbGVjdGVkX21ldHJpY19pZHMiOlsic2xlZXAiLCJzdGVwcyJdLCJ0eXBlIjoic2VsZWN0ZWRfcmVjb3JkX3R5cGVzIn19LCJzb3VyY2VfaW5zdGFsbGF0aW9uX2lkIjoiMTExMTExMTEtMjIyMi00MzMzLTg0NDQtNTU1NTU1NTU1NTU1In0="
    private static let v2EnvelopeBase64 = "eyJwYXlsb2FkIjp7InJlcXVlc3RlZF9hdCI6IjIwMjYtMDctMjRUMTA6MTE6MTJaIn0sInByb3RvY29sX3ZlcnNpb24iOjIsInR5cGUiOiJzdGF0dXNfcmVxdWVzdCJ9"
    private static let binaryFrameBase64 = "SE1ERElSQ1QAAREREREiIkMzhERVVVVVVVUAAAABAAAAIJotsuI/FQTNBWYGVTrAScXnGOj5zpIzh23xp6GCGviFq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s="
}

private extension Data {
    init(hex: String) {
        self.init(
            stride(from: 0, to: hex.count, by: 2).map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return UInt8(hex[start ..< end], radix: 16)!
            }
        )
    }
}
