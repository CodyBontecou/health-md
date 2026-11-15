import Foundation
@testable import HealthMdConnectionCore
import XCTest

final class AgentBridgeV4VectorTests: XCTestCase {
    func testCanonicalJSONIsLosslessScalarOrderedAndNotNormalized() throws {
        let input = Data(#"{"😀":9223372036854775807,"é":"e\u0301/","e\u0301":true,"\ue000":-0}"#.utf8)
        let expected = Data("{\"e\u{301}\":true,\"é\":\"e\u{301}/\",\"\u{e000}\":0,\"😀\":9223372036854775807}".utf8)
        XCTAssertEqual(try AgentBridgeV4Codec.canonicalize(input), expected)
    }

    func testSupplementaryKeyFollowsFFFFAndEquivalentKeysStayDistinct() throws {
        let raw = Data(#"{"\ud800\udc00":1,"\uffff":2,"é":3,"e\u0301":4}"#.utf8)
        let expected = Data("{\"e\u{301}\":4,\"é\":3,\"\u{ffff}\":2,\"\u{10000}\":1}".utf8)
        XCTAssertEqual(try AgentBridgeV4Codec.canonicalize(raw), expected)
    }

    func testDiscoveryConstructorAndClosedDTOCodec() throws {
        let peer = AgentBridgePeer(sourceInstallationID: try id(1), hostInstallationID: try id(2), platform: .android)
        let request = AgentBridgeDiscoveryRequest(requestID: try id(100), peer: peer)
        let expected = Data(#"{"peer":{"host_installation_id":"00000000-0000-4000-8000-000000000002","platform":"android","source_installation_id":"00000000-0000-4000-8000-000000000001"},"request_id":"00000000-0000-4000-8000-000000000064","schema":"healthmd.agent_discovery_request","schema_version":1}"#.utf8)
        XCTAssertEqual(try AgentBridgeV4Codec.encode(request), expected)
        XCTAssertEqual(try AgentBridgeV4Codec.decode(AgentBridgeDiscoveryRequest.self, from: expected), request)
        for raw in [
            #"{"schema":"healthmd.agent_discovery_request","schema_version":true,"request_id":"00000000-0000-4000-8000-000000000064","peer":{}}"#,
            String(decoding: expected, as: UTF8.self).replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":1,\"unknown\":null"),
            String(decoding: expected, as: UTF8.self).replacingOccurrences(of: "\"platform\":\"android\"", with: "\"platform\":\"android\",\"e\\u0301\":1,\"é\":2"),
            String(decoding: expected, as: UTF8.self).replacingOccurrences(of: "\"platform\":\"android\"", with: "\"platform\":null")
        ] { XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeDiscoveryRequest.self, from: Data(raw.utf8))) }
    }

    func testAllSpecificationVectorsAgreeAtGenericCodecOnly() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.canonical_vectors.count, 58)
        for (index, vector) in fixture.canonical_vectors.enumerated() {
            let raw = try vector.value.canonicalBytes()
            let actual = try AgentBridgeV4Codec.canonicalize(raw)
            XCTAssertEqual(actual.base64EncodedString(), vector.canonical_base64, "vector \(index)")
            XCTAssertEqual(AgentBridgeV4Codec.sha256(actual), vector.sha256, "vector \(index)")
        }
    }

    func testGeneratedIntentRetainsEveryExplicitSettingAndBothCaptureAxes() throws {
        let values = try fixture().cases
        for name in ["intent-request-owned-summary", "apple-same-intent", "apple-two-detail-axes-selected_time_series-none", "apple-two-detail-axes-summary-apple_healthkit_canonical_v1", "android-archive-is-separate-product", "explicit-zip-dictionary-opt-in"] {
            let candidate = try XCTUnwrap(values.first { $0.id == name }).value
            var value = candidate
            if name == "apple-same-intent", case .object(let members) = candidate { value = try XCTUnwrap(members.first { $0.key == "intent" }).value }
            let raw = try value.canonicalBytes()
            let intent = try AgentBridgeV4Codec.decode(AgentBridgeGeneratedIntent.self, from: raw)
            XCTAssertEqual(try AgentBridgeV4Codec.encode(intent), raw, name)
        }
        for name in ["no-portable-credentials", "no-desktop-path-to-phone", "profile-no-name-fallback", "schema-bool-is-not-version", "no-healthkit-on-android", "archive-cannot-widen-selected-scope"] {
            let value = try XCTUnwrap(values.first { $0.id == name }).value
            XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeGeneratedIntent.self, from: value.canonicalBytes()), name)
        }
    }

    func testExportDiscoveryBoundaryUsesTypedDocuments() throws {
        let supported: Set<String> = ["healthmd.agent_discovery", "healthmd.agent_authority", "healthmd.agent_approval", "healthmd.agent_execute_request", "healthmd.agent_export_plan", "healthmd.agent_execution_receipt", "healthmd.agent_artifact_manifest", "healthmd.agent_resume_request", "healthmd.agent_cancel_request", "healthmd.agent_commit_receipt"]
        var count = 0
        for candidate in try fixture().cases where candidate.expected == "valid" && candidate.family == "agent" && !containsProjection(candidate.value) {
            guard case .object(let members) = candidate.value, case .string(let schema)? = members.first(where: { $0.key == "schema" })?.value, supported.contains(schema) else { continue }
            let raw = try candidate.value.canonicalBytes()
            let document = try AgentBridgeV4Codec.decode(AgentBridgeDocument.self, from: raw)
            XCTAssertEqual(try AgentBridgeV4Codec.encode(document), raw, candidate.id)
            count += 1
        }
        XCTAssertGreaterThan(count, 8)
    }

    func testExactSourceTimeRoundsDyadicBinary64WithoutDecimalConversion() throws {
        let cases: [(Double, Int64, Int64)] = [(0.0009765625, 0, 976562), (-0.0009765625, -1, 999023438), (1.0.nextDown, 1, 0), (-0.0, 0, 0), (Double.leastNonzeroMagnitude, 0, 0), (-Double.leastNonzeroMagnitude, 0, 0)]
        for (source, seconds, nanos) in cases {
            let time = try AgentBridgeExactTime.binary64(bitPattern: source.bitPattern)
            XCTAssertEqual(time.epochSecond, seconds)
            XCTAssertEqual(time.nanosecond, nanos)
            XCTAssertEqual(time.sourceBinary64Bits, String(format: "%016llx", source.bitPattern))
            let raw = try AgentBridgeV4Codec.encode(time)
            XCTAssertEqual(try AgentBridgeV4Codec.decode(AgentBridgeExactTime.self, from: raw), time)
        }
        for value in [Double.nan, .infinity, -.infinity, 253402300800, -62135596801] {
            XCTAssertThrowsError(try AgentBridgeExactTime.binary64(bitPattern: value.bitPattern))
        }
        for raw in [
            #"{"epoch_second":0,"nanosecond":1,"precision":"source_seconds","source_offset_seconds":null}"#,
            #"{"epoch_second":0,"nanosecond":1,"precision":"source_milliseconds","source_offset_seconds":0}"#,
            #"{"epoch_second":0,"nanosecond":976563,"precision":"source_binary64_seconds","source_binary64_bits":"3f50000000000000","source_offset_seconds":null}"#
        ] { XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeExactTime.self, from: Data(raw.utf8))) }
    }

    func testNativeIdentityPreservesInt64AndMetadataAbsenceRules() throws {
        let identity = try AgentBridgeNativeIdentity(recordType: AgentBridgeNativeType("androidx.health.connect.client.records.StepsRecord"), recordID: "native-1", kind: .native, source: .healthConnect, providerID: AgentBridgeID("health_connect"), metadata: .init(lastModified: .notCaptured, clientRecordID: .absent, clientRecordVersion: .available), clientRecordVersion: Int64.max)
        let raw = try AgentBridgeV4Codec.encode(identity)
        XCTAssertTrue(String(decoding: raw, as: UTF8.self).contains("9223372036854775807"))
        XCTAssertEqual(try AgentBridgeV4Codec.decode(AgentBridgeNativeIdentity.self, from: raw), identity)
        let withNull = String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "\"record_id\"", with: "\"client_record_id\":null,\"record_id\"")
        XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeNativeIdentity.self, from: Data(withNull.utf8)))
        XCTAssertThrowsError(try AgentBridgeNativeIdentity(recordType: AgentBridgeNativeType("HKQuantityTypeIdentifierStepCount"), recordID: "not-a-healthkit-uuid", kind: .native, source: .appleHealth, providerID: AgentBridgeID("apple_health"), metadata: .init(lastModified: .notExposedBySource, clientRecordID: .notExposedBySource, clientRecordVersion: .notExposedBySource)))
    }

    func testPureNegativeVectorsReturnNormativeHealthFreeCodes() throws {
        let names: Set<String> = ["stale-saved_device_settings", "stale-profile", "execute-widen-scope", "zero-health-plan-refuses-health-reads", "all-available-cannot-promise-exact-paths", "origin-required-for-every-setting", "no-hidden-format-inheritance", "local-intent-not-terminal-cancellation", "commit-content-changed", "unsupported-branch-not-complete", "discovery-content-change-requires-new-hash"]
        var seen = Set<String>()
        for candidate in try fixture().cases where names.contains(candidate.id) {
            XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeDocument.self, from: candidate.value.canonicalBytes()), candidate.id) {
                XCTAssertEqual(($0 as? AgentBridgeValidationError)?.rawValue, candidate.expected, candidate.id)
            }
            seen.insert(candidate.id)
        }
        XCTAssertEqual(seen, names)
    }

    func testPathAndCollisionVectorsAreLexicalNotNativeRootEvidence() throws {
        for candidate in try fixture().cases where ["path", "collision"].contains(candidate.family) {
            var actual = "valid"
            do {
                if candidate.family == "path", case .string(let path) = candidate.value {
                    let context = candidate.context
                    func flag(_ key: String) -> Bool { guard case .object(let fields)? = context, case .bool(let b)? = fields.first(where: { $0.key == key })?.value else { return false }; return b }
                    try AgentBridgePaths.validate(path, filename: flag("filename"), tokens: flag("templates") ? .entries : .none)
                } else if case .array(let paths) = candidate.value {
                    try AgentBridgePaths.validateCollisions(paths.map { guard case .string(let path) = $0 else { throw AgentBridgeValidationError.invalidRequest }; return path })
                } else { throw AgentBridgeValidationError.invalidRequest }
            } catch let error as AgentBridgeValidationError { actual = error.rawValue }
            XCTAssertEqual(actual, candidate.expected, candidate.id)
        }
    }

    func testNegotiationDoesNotReplaceTheDeployedBaseWithHighestExtension() throws {
        let old = try AgentBridgeNegotiation(localVersions: [1,3,4], remoteVersions: [1,3], deployedBaseVersion: 1)
        XCTAssertEqual(old.baseVersion, 1); XCTAssertTrue(old.queryV3); XCTAssertFalse(old.agentBridgeV4)
        let request = AgentBridgeDiscoveryRequest(requestID: try id(100), peer: .init(sourceInstallationID: try id(1), hostInstallationID: try id(2), platform: .apple))
        let envelope = try AgentBridgeEnvelope(payload: .discoveryRequest(request))
        XCTAssertThrowsError(try old.encode(envelope))
        let current = try AgentBridgeNegotiation(localVersions: [2,4], remoteVersions: [2,4,5], deployedBaseVersion: 2)
        XCTAssertEqual(current.baseVersion, 2); XCTAssertFalse(current.queryV3); XCTAssertTrue(current.agentBridgeV4)
        let raw = try current.encode(envelope)
        XCTAssertEqual(try current.decode(raw), envelope)
        XCTAssertThrowsError(try old.decode(raw))
        XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: Data(String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "discovery_request\"}", with: "plan_request\"}").utf8)))
        XCTAssertThrowsError(try AgentBridgeNegotiation(localVersions: [1,4], remoteVersions: [4], deployedBaseVersion: 1))
    }

    func testCivilCalendarIsProlepticGregorianNotFormatterCutover() throws {
        XCTAssertThrowsError(try AgentBridgeDate("1500-02-29"))
        XCTAssertThrowsError(try AgentBridgeDate("0000-01-01"))
        let relative = AgentBridgeDates.pastCompleteDays(days: 1, anchorDate: try AgentBridgeDate("1582-10-15"))
        XCTAssertEqual(try relative.resolved(), .exact(.init(startDate: try AgentBridgeDate("1582-10-14"), endDate: try AgentBridgeDate("1582-10-14"))))
    }

    func testStrictRawByteLimitsAtAndBeyondEachBoundary() throws {
        func canonical(_ text: String) throws -> Data { try AgentBridgeV4Codec.canonicalize(Data(text.utf8)) }
        let array = "[" + Array(repeating: "0", count: 4096).joined(separator: ",") + "]"
        XCTAssertNoThrow(try canonical(array))
        XCTAssertThrowsError(try canonical("[0," + array.dropFirst()))
        let object = "{" + (0..<512).map { "\"k\($0)\":0" }.joined(separator: ",") + "}"
        XCTAssertNoThrow(try canonical(object))
        XCTAssertThrowsError(try canonical("{\"extra\":0," + object.dropFirst()))
        XCTAssertNoThrow(try canonical(String(repeating: "[", count: 24) + "0" + String(repeating: "]", count: 24)))
        XCTAssertThrowsError(try canonical(String(repeating: "[", count: 25) + "0" + String(repeating: "]", count: 25)))
        let scalars = String(repeating: "e\u{0301}", count: 32768)
        XCTAssertNoThrow(try canonical("\"" + scalars + "\""))
        XCTAssertThrowsError(try canonical("\"" + scalars + "x\""))
        var maximal = Data(repeating: 0x20, count: AgentBridgeV4Codec.maximumBytes - 1); maximal.append(0x30)
        XCTAssertEqual(try AgentBridgeV4Codec.canonicalize(maximal), Data("0".utf8))
        maximal.append(0x20)
        XCTAssertThrowsError(try AgentBridgeV4Codec.canonicalize(maximal))
        let tooManyNodes = "[" + Array(repeating: array, count: 65).joined(separator: ",") + "]"
        XCTAssertThrowsError(try canonical(tooManyNodes))
    }

    func testSupportedWireVectorsRoundTripThroughClosedEnvelope() throws {
        let vectors = try fixture().canonical_vectors
        for index in Array(35...46) + [57] {
            let vector = vectors[index]
            let bytes = try XCTUnwrap(Data(base64Encoded: vector.canonical_base64))
            let envelope = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes)
            XCTAssertEqual(try AgentBridgeV4Codec.encode(envelope), bytes, "typed envelope \(index)")
            XCTAssertEqual(try AgentBridgeV4Codec.digest(envelope), vector.sha256, "typed envelope \(index)")
        }
    }

    func testResumeRequiresExactTrustedJournalNotCurrentPreferences() throws {
        var seen = 0
        for candidate in try fixture().cases where candidate.family == "resume" {
            guard case .object(let fields)? = candidate.context else { return XCTFail("missing synthetic journal context") }
            let journal = try XCTUnwrap(fields.first { $0.key == "journal_resume" }).value
            let stored = try AgentBridgeV4Codec.decode(AgentBridgeResume.self, from: journal.canonicalBytes())
            var result = "valid"
            do {
                let incoming = try AgentBridgeV4Codec.decode(AgentBridgeResume.self, from: candidate.value.canonicalBytes())
                try AgentBridgeSemantics.validateResume(incoming, journalResume: stored)
            }
            catch let error as AgentBridgeValidationError { result = error.rawValue }
            XCTAssertEqual(result, candidate.expected, candidate.id)
            seen += 1
        }
        XCTAssertEqual(seen, 5)
    }

    func testFoundationEncodingAlsoRejectsInvalidNativeConstructorBounds() throws {
        let destination = AgentBridgeDestination(bindingID: try id(3), identitySHA256: try AgentBridgeDigest(String(repeating: "1", count: 64)), revision: 0, hostInstallationID: try id(2))
        XCTAssertThrowsError(try AgentBridgeV4Codec.encode(destination))
        XCTAssertThrowsError(try JSONEncoder().encode(destination))
    }

    private func containsProjection(_ value: BridgeJSON) -> Bool {
        switch value {
        case .string(let text): return ["source_projection", "android-source-projection-v1"].contains(text)
        case .array(let values): return values.contains(where: containsProjection)
        case .object(let fields): return fields.contains { containsProjection($0.value) }
        default: return false
        }
    }

    private func id(_ value: Int) throws -> AgentBridgeUUID {
        try AgentBridgeUUID(String(format: "00000000-0000-4000-8000-%012x", value))
    }

    private func fixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("packages/contracts/agent-bridge/v1/fixtures/conformance.json")))
    }

    private struct Fixture: Decodable {
        let canonical_vectors: [Vector]
        let cases: [Case]
    }
    private struct Vector: Decodable {
        let value: BridgeJSON
        let canonical_base64: String
        let sha256: String
    }
    private struct Case: Decodable {
        let id: String
        let family: String
        let expected: String
        let value: BridgeJSON
        let context: BridgeJSON?
    }

    func testRawParserFailsClosedWithHealthFreeErrors() {
        let invalid = [
            #"{"x":1,"x":2}"#, #"{"x":1,"\u0078":2}"#,
            #"{"x":1.0}"#, #"{"x":1e0}"#, #"{"x":NaN}"#,
            #"{"x":"\ud800"}"#, #"{"x":"\udc00"}"#,
            #"{"x":01}"#, #"{"x":true,}"#, #"[1,]"#, #"{}{}"#
        ]
        for raw in invalid {
            XCTAssertThrowsError(try AgentBridgeV4Codec.canonicalize(Data(raw.utf8))) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .invalidRequest)
                XCTAssertEqual(String(describing: $0), "invalid_request")
            }
        }
        XCTAssertThrowsError(try AgentBridgeV4Codec.canonicalize(Data([0x22, 0xc0, 0xaf, 0x22])))
    }
}
