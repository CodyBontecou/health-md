import XCTest
@testable import HealthMdDirectClientCore

final class DirectMarkdownMergerTests: XCTestCase {
    func testMergeFrontmatterPreservesListsNestedMappingsCommentsAndBlankLinesExactly() {
        let existing = "---\ndate: 2026-08-03\ntags:\n  - daily-notes\naliases:\n  - Health\n  - Journal\n# User-owned settings stay where they are.\n\npreferences:\n  dashboard:\n    visible: true\n---\n"
        let incoming = "---\ndate: 2026-07-30\nsteps: 2119\n---\n"
        let expected = "---\ndate: 2026-07-30\ntags:\n  - daily-notes\naliases:\n  - Health\n  - Journal\n# User-owned settings stay where they are.\n\npreferences:\n  dashboard:\n    visible: true\nsteps: 2119\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterReplacesCompleteNestedBlock() {
        let existing = "---\nmetadata:\n  source: old\n  labels:\n    - stale\nkeep: unchanged\n---\n"
        let incoming = "---\nmetadata:\n  source: healthmd\n  labels:\n    - first\n    - second\n---\n"
        let expected = "---\nmetadata:\n  source: healthmd\n  labels:\n    - first\n    - second\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterRemovesCollidingDuplicatesAndKeepsUnrelatedDuplicates() {
        let existing = "---\nsteps: 100\ncustom: first\n# Keep this comment.\nsteps: 200\ncustom: second\n---\n"
        let incoming = "---\nsteps: 300\n---\n"
        let expected = "---\nsteps: 300\ncustom: first\n# Keep this comment.\ncustom: second\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergePreservingPreambleKeepsCRLFBlockScalarsIndentedDelimiterAndBodyExact() {
        let frontmatter = "---\r\nsummary: |-\r\n  first line\r\n  ---\r\n  last line\r\n\r\nfolded: >+\r\n  one folded\r\n  paragraph\r\n---\r\n"
        let body = "# My Daily Note\r\n\r\nUser prose with no final newline"
        let incoming = "---\nsteps: 42\n---\n"
        let expectedFrontmatter = "---\r\nsummary: |-\r\n  first line\r\n  ---\r\n  last line\r\n\r\nfolded: >+\r\n  one folded\r\n  paragraph\r\nsteps: 42\r\n---\r\n"

        let result = MarkdownMerger.mergePreservingPreamble(
            existing: frontmatter + body,
            new: incoming
        )

        XCTAssertEqual(result, expectedFrontmatter + body)
    }

    func testMergeAddsOnlyRequiredLineBoundaries() {
        let frontmatterOnly = "---\r\nuser: keep\r\n---"
        let userProse = "## Notes\nUser prose with no final newline"
        let appendedSection = "## Sleep\nfresh"

        XCTAssertEqual(
            MarkdownMerger.mergePreservingPreamble(existing: frontmatterOnly, new: appendedSection),
            frontmatterOnly + "\r\n" + appendedSection
        )
        XCTAssertEqual(
            MarkdownMerger.mergePreservingPreamble(existing: userProse, new: appendedSection),
            userProse + "\n" + appendedSection
        )
        XCTAssertEqual(
            MarkdownMerger.mergePreservingPreamble(existing: frontmatterOnly, new: ""),
            frontmatterOnly
        )
        XCTAssertEqual(
            MarkdownMerger.mergePreservingPreamble(existing: userProse, new: ""),
            userProse
        )
    }

    func testMergeFrontmatterOwnsCommentsAndMultilineFlowContinuations() {
        let existing = "---\nmetadata:\n  source: old\n# This comment interrupts the nested mapping.\n  labels:\n    - stale\nsteps: [\n  100,\n  200\n]\nkeep: unchanged\n---\n"
        let incoming = "---\nmetadata: refreshed\nsteps: 300\n---\n"
        let expected = "---\nmetadata: refreshed\nsteps: 300\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterCanonicalizesQuotedScalarKeys() {
        let existing = "---\n\"steps\": 100\n'steps': 200\n\"st\\u0065ps\": 250\nkeep: unchanged\n---\n"
        let incoming = "---\nsteps: 300\n---\n"
        let expected = "---\nsteps: 300\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterReplacesKeepChompedScalarBlankLines() {
        let existing = "---\nnotes: |2+\n  old\n\n\nkeep: unchanged\n---\n"
        let incoming = "---\nnotes: >+2\n  fresh\n\n---\n"
        let expected = "---\nnotes: >+2\n  fresh\n\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterFailsClosedForUnsupportedComplexKeys() {
        let existing = "---\n? \"steps\"\n: 100\nkeep: unchanged\n---\n"
        let incoming = "---\nsteps: 300\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), existing)
    }
}
