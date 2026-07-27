import CryptoKit
import Foundation
import XCTest
@testable import HealthMd

/// Freezes exact production-renderer bytes before the M5 Rust renderer becomes authoritative.
/// The fixture is an independent oracle: it is generated only by the legacy Swift exporters.
final class NativeRendererGoldenFixtureTests: XCTestCase {
    private static let defaultCustomization = FormatCustomization()
    private static let imperialCustomization: FormatCustomization = {
        let value = FormatCustomization()
        value.unitPreference = .imperial
        return value
    }()
    private static let customCustomization: FormatCustomization = {
        let value = FormatCustomization()
        value.frontmatterConfig.customFields = ["reviewed": "false", "project": "health-md"]
        value.frontmatterConfig.placeholderFields = ["notes", "mood_override"]
        value.markdownTemplate.useEmoji = false
        value.markdownTemplate.sectionHeaderLevel = 3
        return value
    }()

    func testNativeAppleV7RendererBytesMatchFrozenFixture() throws {
        let current = try makeFixture()
        let url = fixtureURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Missing immutable Apple v7 renderer golden")
            return
        }

        let expected = try Data(contentsOf: url)
        let actual = try canonicalBytes(current)
        if actual != expected {
            let expectedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: expected) as? [String: Any])
            XCTFail("Apple v7 renderer bytes drifted; expected hashes \(outputHashes(expectedObject)); actual hashes \(outputHashes(current))")
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Contracts
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // apps/apple
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repository
            .appendingPathComponent("packages/contracts/render-input/v1/fixtures/native-apple-v7.json")
    }

    private func makeFixture() throws -> [String: Any] {
        let cases: [(String, HealthData, FormatCustomization)] = [
            ("partial-default", ExportFixtures.partialDay, Self.defaultCustomization),
            ("full-imperial", ExportFixtures.fullDay, Self.imperialCustomization),
            ("lossless-custom", ExportFixtures.losslessDay, Self.customCustomization),
        ]
        return [
            "schema": "healthmd.native_renderer_goldens",
            "schema_version": 1,
            "profile": "apple-v7",
            "public_schema": "healthmd.health_data",
            "public_schema_version": 7,
            "cases": try cases.map { identifier, data, customization in
                [
                    "id": identifier,
                    "outputs": try [
                        output("markdown", "text/markdown; charset=utf-8", data.toMarkdown(customization: customization)),
                        output("obsidian_bases", "text/markdown; charset=utf-8", data.toObsidianBases(customization: customization)),
                        output("json", "application/json", data.toJSONThrowing(customization: customization)),
                        output("csv", "text/csv; charset=utf-8", data.toCSVThrowing(customization: customization)),
                    ],
                ]
            },
        ]
    }

    private func output(_ format: String, _ mediaType: String, _ text: String) -> [String: Any] {
        let bytes = Data(text.utf8)
        return [
            "format": format,
            "media_type": mediaType,
            "byte_count": bytes.count,
            "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "bytes_base64": bytes.base64EncodedString(),
        ]
    }

    private func outputHashes(_ fixture: [String: Any]) -> [String] {
        (fixture["cases"] as? [[String: Any]] ?? []).flatMap { renderCase in
            let identifier = renderCase["id"] as? String ?? "unknown"
            return (renderCase["outputs"] as? [[String: Any]] ?? []).map { output in
                "\(identifier)/\(output["format"] as? String ?? "unknown")=\(output["sha256"] as? String ?? "missing")"
            }
        }
    }

    private func canonicalBytes(_ object: Any) throws -> Data {
        var bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        bytes.append(0x0A)
        return bytes
    }
}
