import CryptoKit
import Foundation
import XCTest
@testable import HealthMdCoreRust

final class HistoricalAuthorityTests: XCTestCase {
    func testHistoricalNativeClientsKeepExactAuthorityAndEveryResultAndArtifactByte() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let semantic = try fixture(root, "semantic-input", "shipped-v3.4.2")
        let render = try fixture(root, "render-input", "shipped-v3.4.2")
        let service = HealthMdCoreService()
        for item in try XCTUnwrap(semantic["cases"] as? [[String: Any]]) {
            let configuration = try XCTUnwrap(item["config"] as? [String: Any])
            let profile: CoreMetricRegistryProfile
            switch configuration["profile"] as? String {
            case "apple_health_data_v8": profile = .appleHealthDataV8
            case "android_frozen_v4": profile = .androidFrozenV4
            case "android_analytical_v5": profile = .androidAnalyticalV5
            default: return XCTFail("Unreviewed historical profile")
            }
            let hash = try XCTUnwrap(configuration["registry_sha256"] as? String)
            let snapshot = try service.metricRegistryAtAuthority(profile: profile, registrySHA256: hash)
            XCTAssertEqual(snapshot.registrySha256, hash)
            let session = try service.semanticSession(configuration: JSONSerialization.data(withJSONObject: configuration))
            var result = Data()
            for batch in try XCTUnwrap(item["batches"] as? [[String: Any]]) {
                result = try session.process(batch: JSONSerialization.data(withJSONObject: batch))
            }
            XCTAssertEqual(SHA256.hash(data: result).map { String(format: "%02x", $0) }.joined(), item["expected_result_sha256"] as? String)
            XCTAssertThrowsError(try service.metricRegistryAtAuthority(profile: profile, registrySHA256: String(repeating: "0", count: 64)))
        }
        for item in try XCTUnwrap(render["cases"] as? [[String: Any]]) {
            let session = try service.renderSession(
                configuration: JSONSerialization.data(withJSONObject: XCTUnwrap(item["configuration"])),
                semanticResult: JSONSerialization.data(withJSONObject: XCTUnwrap(item["semantic_result"]))
            )
            for batch in try XCTUnwrap(item["batches"] as? [[String: Any]]) {
                _ = try session.process(batch: JSONSerialization.data(withJSONObject: batch))
            }
            let plan = try session.finish()
            let expectedPlan = try XCTUnwrap(item["expected_plan"] as? [String: Any])
            let expectedItems = try XCTUnwrap(expectedPlan["items"] as? [[String: Any]])
            XCTAssertEqual(plan.items.count, expectedItems.count)
            for (actual, expected) in zip(plan.items, expectedItems) {
                XCTAssertEqual(actual.content, Data(base64Encoded: try XCTUnwrap(expected["content_base64"] as? String)))
                XCTAssertEqual(actual.sha256, expected["sha256"] as? String)
                XCTAssertEqual(actual.relativePath, expected["relative_path"] as? String)
                XCTAssertEqual(actual.byteCount, (expected["byte_count"] as? NSNumber)?.uint64Value)
            }
        }
    }

    private func fixture(_ root: URL, _ area: String, _ label: String) throws -> [String: Any] {
        let bytes = try Data(contentsOf: root.appendingPathComponent("packages/contracts/\(area)/v1/fixtures/historical-\(label).json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }
}
