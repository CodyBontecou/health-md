import XCTest
@testable import HealthMd

@MainActor
final class SummarySizingBenchmarkTests: XCTestCase {
    private struct Sizes: Codable {
        let json: Int
        let csv: Int
        let markdown: Int
        let bases: Int

        var largest: Int { max(json, csv, markdown, bases) }
    }

    func testSyntheticSummaryProfilesRemainBoundedAndEmitMeasuredTable() throws {
        let customization = FormatCustomization()
        customization.unitPreference = .metric
        var measured: [String: Sizes] = [:]

        for fixture in DocumentationExportFixtures.summarySizingFixtures {
            let sizes = Sizes(
                json: Data(try fixture.data.toJSONThrowing(customization: customization).utf8).count,
                csv: Data(try fixture.data.toCSVThrowing(customization: customization).utf8).count,
                markdown: Data(fixture.data.toMarkdown(customization: customization).utf8).count,
                bases: Data(fixture.data.toObsidianBases(customization: customization).utf8).count
            )
            measured[fixture.name] = sizes
            XCTAssertGreaterThan(sizes.json, 0, fixture.name)
            XCTAssertGreaterThan(sizes.csv, 0, fixture.name)
            XCTAssertGreaterThan(sizes.markdown, 0, fixture.name)
            XCTAssertGreaterThan(sizes.bases, 0, fixture.name)
            XCTAssertLessThan(sizes.largest, 1_024 * 1_024, "One synthetic Summary day unexpectedly exceeded 1 MiB: \(fixture.name)")
            XCTAssertLessThan(sizes.largest * 365, 500 * 1_024 * 1_024, "365-day linear estimate unexpectedly exceeded 500 MiB: \(fixture.name)")
        }

        XCTAssertEqual(Set(measured.keys), ["sparse", "typical", "workout_heavy", "maximal"])
        XCTAssertLessThan(try XCTUnwrap(measured["sparse"]).largest, try XCTUnwrap(measured["maximal"]).largest)
        XCTAssertGreaterThan(try XCTUnwrap(measured["workout_heavy"]).largest, try XCTUnwrap(measured["typical"]).largest)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let table = try encoder.encode(measured)
        let attachment = XCTAttachment(data: table, uniformTypeIdentifier: "public.json")
        attachment.name = "synthetic-summary-sizing.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCommittedMaximalSummaryFixtureHasExpectedMeasuredSizes() throws {
        let root = try repositoryRoot()
        let directory = root.appendingPathComponent("apps/apple/docs/reference/generated/core")
        let expected: [String: Int] = [
            "summary-day.json": 27_749,
            "summary-day.csv": 17_202,
            "summary-day.md": 23_358,
            "summary-day-bases.md": 15_558,
        ]
        for (name, byteCount) in expected {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            XCTAssertEqual(data.count, byteCount, name)
        }
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path) else {
            throw NSError(domain: "SummarySizingBenchmarkTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "repository root not found"])
        }
        return url
    }
}
