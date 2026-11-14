import Foundation
import XCTest
@testable import HealthMdConnectionCore

final class AgentBridgeTransferFrontierTests: XCTestCase {
    private struct Fixture: Decodable { let cases: [Candidate] }
    private struct Candidate: Decodable {
        let id: String
        let seed: [String: String]
        let partitions: [BridgeJSON]
        let expected: String
        let prefix_sha256: [String]?
        let canonical_base64: [String]?
        let raw_partitions_base64: [String]?
    }
    private func fixture() throws -> Fixture {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("packages/contracts/agent-bridge/v1/fixtures/transfer-frontier-v1.json")))
    }
    private func start(_ seed: [String: String]) throws -> AgentBridgeTransferFrontier {
        try .init(jobID: AgentBridgeUUID(XCTUnwrap(seed["job_id"])), requestSHA256: AgentBridgeDigest(XCTUnwrap(seed["request_sha256"])),
            manifestSHA256: AgentBridgeDigest(XCTUnwrap(seed["manifest_sha256"])), sessionID: AgentBridgeUUID(XCTUnwrap(seed["session_id"])))
    }
    func testIndependentFrontierVectorsAndRawNegatives() throws {
        let candidates = try fixture().cases
        XCTAssertGreaterThan(candidates.count, 30)
        for candidate in candidates {
            do {
                var frontier = try start(candidate.seed)
                var actual = [frontier.sha256.rawValue]
                let raw = try candidate.raw_partitions_base64.map { try $0.map { try XCTUnwrap(Data(base64Encoded: $0)) } }
                    ?? candidate.partitions.map { try $0.canonicalBytes() }
                for bytes in raw {
                    frontier = try frontier.appending(AgentBridgeV4Codec.decode(AgentBridgeTransferFrontierPartition.self, from: bytes))
                    actual.append(frontier.sha256.rawValue)
                }
                XCTAssertEqual(candidate.expected, "valid", candidate.id)
                XCTAssertEqual(actual, candidate.prefix_sha256, candidate.id)
                XCTAssertEqual(frontier.committedPartitionCount, Int64(raw.count), candidate.id)
                for (encoded, digest) in zip(candidate.canonical_base64 ?? [], actual) {
                    XCTAssertEqual(AgentBridgeV4Codec.sha256(try XCTUnwrap(Data(base64Encoded: encoded))), digest)
                }
            } catch let error as AgentBridgeValidationError {
                XCTAssertEqual(error.rawValue, candidate.expected, candidate.id)
            }
        }
    }
    func testComputedPrefixIsImmutableAndRejectsDuplicateOrSkippedIndex() throws {
        let candidate = try XCTUnwrap(fixture().cases.first { $0.id == "two-artifacts" })
        let original = try start(candidate.seed)
        let row = try AgentBridgeV4Codec.decode(AgentBridgeTransferFrontierPartition.self, from: candidate.partitions[0].canonicalBytes())
        let next = try original.appending(row)
        XCTAssertEqual(original.committedPartitionCount, 0)
        XCTAssertEqual(original.sha256.rawValue, candidate.prefix_sha256?[0])
        XCTAssertEqual(next.committedPartitionCount, 1)
        XCTAssertThrowsError(try next.appending(row)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        let second = try AgentBridgeV4Codec.decode(AgentBridgeTransferFrontierPartition.self, from: candidate.partitions[1].canonicalBytes())
        XCTAssertThrowsError(try original.appending(second)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertEqual(try next.appending(second).sha256.rawValue, candidate.prefix_sha256?.last)
    }
    func testInternalCounterBoundsCannotOverflowPublicReceiptCount() throws {
        let candidate = try XCTUnwrap(fixture().cases.first { $0.id == "one-partition" })
        let prefix = try start(candidate.seed)
        let row = try AgentBridgeV4Codec.decode(AgentBridgeTransferFrontierPartition.self, from: candidate.partitions[0].canonicalBytes())
        for count: Int64 in [-1, 2_147_483_647, Int64.max] {
            XCTAssertThrowsError(try AgentBridgeSemantics.transferFrontierStep(previous: prefix.sha256, committedPartitionCount: count, partition: row)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .invalidRequest)
            }
        }
    }
}
