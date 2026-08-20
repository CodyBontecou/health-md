import CryptoKit
import Foundation
import XCTest
@testable import HealthMd

/// Guards the independently frozen pre-v8 Swift renderer evidence. The live
/// exporter intentionally advances to v8; this historical fixture must never be
/// regenerated from the current renderer.
final class NativeRendererGoldenFixtureTests: XCTestCase {
    func testNativeAppleV7RendererFrozenFixtureRemainsSelfConsistent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Contracts
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // apps/apple
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repository
            .appendingPathComponent("packages/contracts/render-input/v1/fixtures/native-apple-v7.json")
        let bytes = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])

        XCTAssertEqual(fixture["schema"] as? String, "healthmd.native_renderer_goldens")
        XCTAssertEqual(fixture["schema_version"] as? Int, 1)
        XCTAssertEqual(fixture["profile"] as? String, "apple-v7")
        XCTAssertEqual(fixture["public_schema"] as? String, "healthmd.health_data")
        XCTAssertEqual(fixture["public_schema_version"] as? Int, 7)

        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for renderCase in cases {
            let outputs = try XCTUnwrap(renderCase["outputs"] as? [[String: Any]])
            XCTAssertEqual(Set(outputs.compactMap { $0["format"] as? String }), ["markdown", "obsidian_bases", "json", "csv"])
            for output in outputs {
                let encoded = try XCTUnwrap(output["bytes_base64"] as? String)
                let outputBytes = try XCTUnwrap(Data(base64Encoded: encoded))
                XCTAssertEqual(output["byte_count"] as? Int, outputBytes.count)
                XCTAssertEqual(
                    output["sha256"] as? String,
                    SHA256.hash(data: outputBytes).map { String(format: "%02x", $0) }.joined()
                )
            }
        }
    }
}
