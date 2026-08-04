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
}
