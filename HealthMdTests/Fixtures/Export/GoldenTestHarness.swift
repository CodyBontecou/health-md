//
//  GoldenTestHarness.swift
//  HealthMdTests
//
//  Helpers for snapshot/golden comparison of exporter output.
//  Provides actionable diffs when output doesn't match expected.
//

import XCTest

/// Asserts that actual multiline output matches expected content, with actionable diff on failure.
func assertGoldenMatch(
    _ actual: String,
    expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual != expected else { return }

    let actualLines = actual.components(separatedBy: "\n")
    let expectedLines = expected.components(separatedBy: "\n")

    var diffs: [String] = []
    let maxLines = max(actualLines.count, expectedLines.count)

    for i in 0..<maxLines {
        let actualLine = i < actualLines.count ? actualLines[i] : "<missing>"
        let expectedLine = i < expectedLines.count ? expectedLines[i] : "<missing>"

        if actualLine != expectedLine {
            diffs.append("Line \(i + 1):")
            diffs.append("  expected: \(expectedLine)")
            diffs.append("  actual:   \(actualLine)")
        }
    }

    let diffSummary = diffs.prefix(30).joined(separator: "\n")
    let totalDiffCount = diffs.filter { $0.hasPrefix("Line ") }.count
    let message = "Golden mismatch (\(totalDiffCount) line\(totalDiffCount == 1 ? "" : "s") differ):\n\(diffSummary)"

    XCTFail(message, file: file, line: line)
}

/// Normalizes whitespace in export output for comparison.
/// Trims trailing whitespace per line and normalizes line endings.
func normalizeExportOutput(_ output: String) -> String {
    output
        .components(separatedBy: "\n")
        .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
