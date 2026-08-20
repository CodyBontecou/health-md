import Foundation
import XCTest

final class PluginVisualizationResourceTests: XCTestCase {
    private let pinnedPluginRevision = "7d8fdee95b1bdec064d66687fc61d08032fe773d"

    func testOnboardingResourcesMatchPinnedWebsitePluginAndSamples() throws {
        let root = try repositoryRoot()
        let website = root.appendingPathComponent("apps/website")
        let resources = root.appendingPathComponent(
            "apps/apple/HealthMd/iOS/Resources/PluginVisualization"
        )

        let sourceData = try Data(contentsOf: website.appendingPathComponent("external-sources.json"))
        let sources = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        )
        let plugin = try XCTUnwrap(sources["obsidian_plugin"] as? [String: Any])
        XCTAssertEqual(plugin["revision"] as? String, pinnedPluginRevision)

        let websiteBundle = try Data(
            contentsOf: website.appendingPathComponent("assets/healthmd-plugin-visualizations.js")
        )
        let appleBundle = try Data(
            contentsOf: resources.appendingPathComponent("healthmd-plugin-visualizations.js")
        )
        XCTAssertEqual(appleBundle, websiteBundle)

        try assertWrappedResource(
            resources.appendingPathComponent("health-sample.js"),
            prefix: "window.HealthMdSampleData = ",
            matches: website.appendingPathComponent("assets/visualizations-data/health-sample.json")
        )
        try assertWrappedResource(
            resources.appendingPathComponent("health-rollups.js"),
            prefix: "window.HealthMdRollupSampleData = ",
            matches: website.appendingPathComponent("assets/visualizations-data/health-rollups.json")
        )
    }

    func testOnboardingSamplesUseCurrentArchiveFreeDailyV8AndRangeV9() throws {
        let root = try repositoryRoot()
        let resources = root.appendingPathComponent(
            "apps/apple/HealthMd/iOS/Resources/PluginVisualization"
        )
        let days = try jsonArray(
            in: resources.appendingPathComponent("health-sample.js"),
            prefix: "window.HealthMdSampleData = "
        )
        XCTAssertEqual(days.count, 30)
        for day in days {
            XCTAssertEqual(day["schema"] as? String, "healthmd.health_data")
            XCTAssertEqual(day["schema_version"] as? Int, 8)
            XCTAssertEqual(day["raw_capture_status"] as? String, "not_requested")
            XCTAssertNil(day["healthkit_record_archive"])
        }

        let rollups = try jsonArray(
            in: resources.appendingPathComponent("health-rollups.js"),
            prefix: "window.HealthMdRollupSampleData = "
        )
        let range = try XCTUnwrap(
            rollups.first { $0["rollup_period"] as? String == "range" }
        )
        XCTAssertEqual(range["schema"] as? String, "healthmd.rollup_summary")
        XCTAssertEqual(range["schema_version"] as? Int, 9)
        XCTAssertEqual(range["source_schema"] as? String, "healthmd.health_data")
        XCTAssertEqual(range["source_schema_version"] as? Int, 8)

        let preview = try String(
            contentsOf: resources.appendingPathComponent("plugin-activity-rings-preview.html"),
            encoding: .utf8
        )
        XCTAssertTrue(preview.contains("<script src=\"health-sample.js\"></script>"))
        XCTAssertTrue(preview.contains("<script src=\"health-rollups.js\"></script>"))
    }

    private func assertWrappedResource(_ resource: URL, prefix: String, matches jsonFile: URL) throws {
        let wrapped = try String(contentsOf: resource, encoding: .utf8)
        let json = try String(contentsOf: jsonFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(wrapped, "\(prefix)\(json);\n")
    }

    private func jsonArray(in resource: URL, prefix: String) throws -> [[String: Any]] {
        let wrapped = try String(contentsOf: resource, encoding: .utf8)
        guard wrapped.hasPrefix(prefix), wrapped.hasSuffix(";\n") else {
            XCTFail("Unexpected generated wrapper in \(resource.path)")
            return []
        }
        let json = String(wrapped.dropFirst(prefix.count).dropLast(2))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )
    }

    private func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("apps/website/external-sources.json").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
