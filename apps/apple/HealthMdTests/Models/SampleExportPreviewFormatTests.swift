import Foundation
import XCTest
@testable import HealthMd

final class SampleExportPreviewFormatTests: XCTestCase {
    func testStructuredExamplesPreserveQuotesInWorkoutPace() throws {
        let json = try JSONSerialization.jsonObject(with: Data(SampleExportPreviewFormat.json.content.utf8))
        let root = try XCTUnwrap(json as? [String: Any])
        let workouts = try XCTUnwrap(root["workouts"] as? [[String: Any]])
        let pace = try XCTUnwrap(workouts.first?["avgPacePerMiFormatted"] as? String)
        XCTAssertEqual(pace, "11'00\" /mi")

        // This YAML double-quoted scalar uses JSON-compatible escapes. Parsing it
        // independently catches a quote that prematurely closes the pace value.
        let line = try XCTUnwrap(SampleExportPreviewFormat.obsidianBases.content
            .split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("avg_pace_per_mi:") })
        let scalar = String(line.split(separator: ":", maxSplits: 1)[1])
            .trimmingCharacters(in: .whitespaces)
        let decoded = try JSONSerialization.jsonObject(with: Data(scalar.utf8), options: .fragmentsAllowed)
        XCTAssertEqual(decoded as? String, pace)
    }
}
