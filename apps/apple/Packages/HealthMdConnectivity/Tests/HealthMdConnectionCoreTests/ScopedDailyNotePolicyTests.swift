import Foundation
import XCTest
@testable import HealthMdConnectionCore

final class ScopedDailyNotePolicyTests: XCTestCase {
    private func policy() throws -> DirectScopedDailyNotePolicy {
        try DirectScopedDailyNotePolicy(recordProfile: "apple-v11", ownerDate: "2026-03-08",
            calendarTimezone: "America/New_York", createIfMissing: false, injectSections: true)
    }

    func testPolicyMatchesCanonicalFixtureAndRejectsInvalidAuthority() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(policy())
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let fixture = root.appendingPathComponent("packages/contracts/direct-protocol/scoped-notes-v1/fixtures/policy.json")
        if ProcessInfo.processInfo.environment["HEALTHMD_UPDATE_DIRECT_NOTE_POLICY"] == "1" {
            try encoded.write(to: fixture, options: .atomic)
        }
        XCTAssertEqual(encoded, try Data(contentsOf: fixture))
        XCTAssertEqual(try JSONDecoder().decode(DirectScopedDailyNotePolicy.self, from: encoded), try policy())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (field, value) in [("version", 2), ("record_profile", "unverified"),
            ("owner_date", "2026-02-30"), ("owner_date", "0000-01-01"),
            ("owner_date", "2026-3-8"), ("calendar_timezone", "Invalid/Zone"),
            ("inject_sections", "true"), ("create_if_missing", NSNull()), ("unknown", true)] as [(String, Any)] {
            var changed = original
            changed[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(DirectScopedDailyNotePolicy.self,
                from: JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testOwnerDatesUseProlepticGregorianLeapRulesOnBothSidesOfTheHistoricalCutover() throws {
        for date in ["0001-01-01", "1500-02-28", "1582-10-10", "1600-02-29", "2000-02-29", "9999-12-31"] {
            XCTAssertNoThrow(try DirectScopedDailyNotePolicy(recordProfile: "apple-v11", ownerDate: date,
                calendarTimezone: "UTC", createIfMissing: false, injectSections: false))
        }
        for date in ["1500-02-29", "1700-02-29", "1900-02-29", "2100-02-29", "2026-00-01", "2026-13-01"] {
            XCTAssertThrowsError(try DirectScopedDailyNotePolicy(recordProfile: "apple-v11", ownerDate: date,
                calendarTimezone: "UTC", createIfMissing: false, injectSections: false))
        }
    }

    func testHelloRequiresBothPeersAndManifestPolicyIsOmittedForLegacy() throws {
        func capabilities(_ versions: [Int]?) -> DirectPeerCapabilities {
            DirectPeerCapabilities(platform: .iOS, installationID: UUID(), scopedDailyNoteVersions: versions)
        }
        for local in [nil, [], [1], [2], [1, 2]] as [[Int]?] {
            for peer in [nil, [], [1], [2], [1, 2]] as [[Int]?] {
                let expected: Int? = local?.contains(1) == true && peer?.contains(1) == true ? 1 : nil
                XCTAssertEqual(capabilities(local).negotiatedScopedDailyNoteVersion(with: capabilities(peer)), expected)
            }
        }
        let encoder = JSONEncoder()
        let legacyHello = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(capabilities(nil))) as? [String: Any])
        XCTAssertNil(legacyHello["scopedDailyNoteVersions"])
        let fileID = UUID()
        let jobID = UUID()
        func manifest(_ policy: DirectScopedDailyNotePolicy?) throws -> DirectExportFileManifest {
            try DirectExportFileManifest(jobID: jobID, fileID: fileID, relativePath: "Daily/2026-03-08.md",
                byteCount: 42, sha256: String(repeating: "a", count: 64),
                writeMode: .mergeMarkdownPreservingPreamble, scopedNotePolicy: policy)
        }
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(manifest(nil))) as? [String: Any])
        XCTAssertNil(legacy["scopedNotePolicy"])
        let current = try manifest(policy())
        XCTAssertEqual(try JSONDecoder().decode(DirectExportFileManifest.self, from: encoder.encode(current)), current)
    }
}
