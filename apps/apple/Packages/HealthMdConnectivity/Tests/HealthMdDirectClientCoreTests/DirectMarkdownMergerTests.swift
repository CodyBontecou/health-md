import Foundation
import XCTest
@testable import HealthMdDirectClientCore

final class DirectMarkdownMergerTests: XCTestCase {
    private struct MergeVectorFixture: Decodable {
        let renderProfileRevision: Int
        let vectors: [MergeVector]

        enum CodingKeys: String, CodingKey {
            case renderProfileRevision = "render_profile_revision"
            case vectors
        }
    }

    private struct MergeVector: Decodable {
        let id: String
        let existing: String
        let generated: String
        let preservePreamble: Bool
        let outcome: String
        let expected: String?

        enum CodingKeys: String, CodingKey {
            case id, existing, generated, outcome, expected
            case preservePreamble = "preserve_preamble"
        }
    }

    private func sharedMergeFixture() throws -> MergeVectorFixture {
        guard let fixtureURL = Bundle.module.url(
            forResource: "markdown-merge-v1",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            MergeVectorFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
    }

    func testSharedManagedMarkdownMergeVectors() throws {
        let fixture = try sharedMergeFixture()
        XCTAssertEqual(fixture.renderProfileRevision, 2)

        for vector in fixture.vectors {
            let result = vector.preservePreamble
                ? MarkdownMerger.mergePreservingPreambleOutcome(
                    existing: vector.existing,
                    new: vector.generated
                )
                : MarkdownMerger.mergeOutcome(existing: vector.existing, new: vector.generated)
            switch (vector.outcome, result) {
            case ("merged", .merged(let content)):
                XCTAssertEqual(content, vector.expected, vector.id)
            case ("rejected", .rejected):
                XCTAssertNil(vector.expected, vector.id)
            default:
                XCTFail("Unexpected merge outcome for \(vector.id): \(result)")
            }
        }
    }
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

    func testMergeFrontmatterOwnsCompleteIndentationlessSequence() {
        let existing = "---\nevents: # valid indentationless sequence\n- name: old\n  details:\n    status: stale\n# The sequence resumes after trivia.\n\n- name: second\n  values: [\n    one,\n    two\n  ]\nkeep: unchanged\n---\n"
        let incoming = "---\nevents: refreshed\n---\n"
        let expected = "---\nevents: refreshed\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterKeepsIncomingIndentationlessSequenceBoundaries() {
        let existing = "---\nevents: stale\nkeep: unchanged\n---\n"
        let incoming = "---\nevents:\n- name: fresh\n  details:\n    status: current\n- values: [\n    one,\n    two\n  ]\nsteps: 42\n---\n"
        let expected = "---\nevents:\n- name: fresh\n  details:\n    status: current\n- values: [\n    one,\n    two\n  ]\nkeep: unchanged\nsteps: 42\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterSupportsNodePropertiesOnIndentationlessSequences() {
        let existing = "---\nevents: &oldEvents !!seq\n- stale\nkeep: unchanged\n---\n"
        let incoming = "---\nevents: !!seq &freshEvents\n- current\nsteps: 42\n---\n"
        let expected = "---\nevents: !!seq &freshEvents\n- current\nkeep: unchanged\nsteps: 42\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterFindsAliasAfterNestedSequenceBlockScalar() {
        let existing = "---\nmanaged: &defaults old\nkeep:\n- notes: |2\n    *defaults is scalar text\n  alias: *defaults\n---\n"
        let incoming = "---\nmanaged: fresh\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), existing)
    }

    func testMergeFrontmatterFailsClosedForNonSpaceYAMLIndentation() {
        let existing = "---\nsettings:\n\u{00A0}child: true\nkeep: unchanged\n---\n"
        let incoming = "---\nsteps: 42\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), existing)
    }

    func testMergeFrontmatterDoesNotTreatPlainDashesOrRootSequenceAsOwnedSequence() {
        let validExisting = "---\ndash: -foo\nnegative: -42\nkeep: unchanged\n---\n"
        let validIncoming = "---\ndash: updated\n---\n"
        let validExpected = "---\ndash: updated\nnegative: -42\nkeep: unchanged\n---\n"
        XCTAssertEqual(
            MarkdownMerger.mergeFrontmatter(existing: validExisting, new: validIncoming),
            validExpected
        )

        let ambiguousRootSequence = "---\nowner: nonempty\n- root item\nkeep: unchanged\n---\n"
        let incoming = "---\nowner: replacement\n---\n"
        XCTAssertEqual(
            MarkdownMerger.mergeFrontmatter(existing: ambiguousRootSequence, new: incoming),
            ambiguousRootSequence
        )
    }

    func testMergeFrontmatterFailsClosedWhenPreservedBlockAliasesReplacedAnchor() {
        let existing = "---\nmanaged:\n  defaults: &defaults\n    unit: count\nkeep:\n  <<: *defaults\n  label: preserved\n---\n"
        let incoming = "---\nmanaged:\n  unit: milliseconds\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), existing)
    }

    func testMergeFrontmatterAnchorScanIgnoresCommentsQuotesAndBlockScalarPayload() {
        let existing = "---\nmanaged: &defaults old\nquoted: \"*defaults and &defaults\"\nsingle: '*defaults'\nliteral: |\n  *defaults\n  &defaults\nfolded: >\n  *defaults\n# *defaults is only a comment.\nkeep: unchanged\n---\n"
        let incoming = "---\nmanaged: fresh\n---\n"
        let expected = "---\nmanaged: fresh\nquoted: \"*defaults and &defaults\"\nsingle: '*defaults'\nliteral: |\n  *defaults\n  &defaults\nfolded: >\n  *defaults\n# *defaults is only a comment.\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterUsesNFCForKeyLookupWithoutRewritingPhysicalLines() {
        let decomposedKey = "cafe\u{301}"
        let existing = "---\n\(decomposedKey): old\ncafé: duplicate\nkeep: unchanged\n---\n"
        let incoming = "---\ncafé: first\n\(decomposedKey): final\n---\n"
        let expected = "---\n\(decomposedKey): final\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterAllowsTabsAfterBlockScalarSpaceIndentation() {
        let existing = "---\nnotes: |2\n  \tpayload with *literal\nkeep: unchanged\n---\n"
        let incoming = "---\nsteps: 42\n---\n"
        let expected = "---\nnotes: |2\n  \tpayload with *literal\nkeep: unchanged\nsteps: 42\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatterFailsClosedForTabsBeforeRequiredIndentation() {
        let incoming = "---\nsteps: 42\n---\n"
        let nestedTab = "---\nsettings:\n\tchild: true\nkeep: unchanged\n---\n"
        let scalarTab = "---\nnotes: |2\n \tinvalid\nkeep: unchanged\n---\n"
        let sequenceTab = "---\nitems:\n-\tinvalid\nkeep: unchanged\n---\n"
        let spacedSequenceTab = "---\nitems:\n- \tinvalid\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: nestedTab, new: incoming), nestedTab)
        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: scalarTab, new: incoming), scalarTab)
        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: sequenceTab, new: incoming), sequenceTab)
        XCTAssertEqual(
            MarkdownMerger.mergeFrontmatter(existing: spacedSequenceTab, new: incoming),
            spacedSequenceTab
        )
    }
}
