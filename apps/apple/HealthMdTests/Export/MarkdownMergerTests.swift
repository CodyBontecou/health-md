//
//  MarkdownMergerTests.swift
//  HealthMdTests
//
//  Tests for MarkdownMerger - critical for "Update" write mode
//

import Foundation
import XCTest
@testable import HealthMd

final class MarkdownMergerTests: XCTestCase {
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
        guard let fixtureURL = Bundle(for: Self.self).url(
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
    
    // MARK: - headingLevel Tests
    
    func testHeadingLevel_validH1() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "# Title"), 1)
    }
    
    func testHeadingLevel_validH2() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "## Section"), 2)
    }
    
    func testHeadingLevel_validH3() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "### Subsection"), 3)
    }
    
    func testHeadingLevel_validH6() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "###### Deep heading"), 6)
    }
    
    func testHeadingLevel_withLeadingWhitespace() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "  ## Indented"), 2)
    }
    
    func testHeadingLevel_notAHeading_noSpace() {
        // Must have space after #
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "##NoSpace"), 0)
    }
    
    func testHeadingLevel_notAHeading_plainText() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "Just some text"), 0)
    }
    
    func testHeadingLevel_notAHeading_emptyLine() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: ""), 0)
    }
    
    func testHeadingLevel_notAHeading_onlyHashes() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "##"), 0)
    }
    
    func testHeadingLevel_withEmoji() {
        XCTAssertEqual(MarkdownMerger.headingLevel(of: "## 😴 Sleep"), 2)
    }
    
    // MARK: - normalizeHeadingText Tests
    
    func testNormalizeHeadingText_simpleHeading() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## Sleep"), "sleep")
    }
    
    func testNormalizeHeadingText_withEmoji() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## 😴 Sleep"), "sleep")
    }
    
    func testNormalizeHeadingText_multipleWords() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## My Custom Notes"), "my custom notes")
    }
    
    func testNormalizeHeadingText_withMultipleEmoji() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("### 🏃‍♂️ Activity 💪"), "activity")
    }
    
    func testNormalizeHeadingText_mixedCase() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## HeArT"), "heart")
    }
    
    func testNormalizeHeadingText_h1() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("# Title"), "title")
    }
    
    func testNormalizeHeadingText_h3() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("### Subsection"), "subsection")
    }
    
    func testNormalizeHeadingText_withNumbers() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## Section 2"), "section 2")
    }
    
    func testNormalizeHeadingText_extraSpaces() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("##   Extra   Spaces  "), "extra spaces")
    }
    
    // MARK: - detectSectionLevel Tests
    
    func testDetectSectionLevel_defaultsToTwo() {
        let content = """
        # Title
        Some content without known sections
        """
        XCTAssertEqual(MarkdownMerger.detectSectionLevel(in: content), 2)
    }
    
    func testDetectSectionLevel_detectsH2Sleep() {
        let content = """
        # Health Data
        ## 😴 Sleep
        - Total: 7h
        """
        XCTAssertEqual(MarkdownMerger.detectSectionLevel(in: content), 2)
    }
    
    func testDetectSectionLevel_detectsH3Activity() {
        let content = """
        # Health Data
        ### 🏃 Activity
        - Steps: 10000
        """
        XCTAssertEqual(MarkdownMerger.detectSectionLevel(in: content), 3)
    }
    
    func testDetectSectionLevel_detectsHeart() {
        let content = """
        ## Heart
        - Resting: 60 bpm
        """
        XCTAssertEqual(MarkdownMerger.detectSectionLevel(in: content), 2)
    }
    
    func testDetectSectionLevel_detectsWorkouts() {
        let content = """
        ## Workouts
        - Running: 30 min
        """
        XCTAssertEqual(MarkdownMerger.detectSectionLevel(in: content), 2)
    }
    
    // MARK: - parse Tests
    
    func testParse_extractsFrontmatter() {
        let content = """
        ---
        date: 2026-01-15
        type: health-data
        ---
        # Title
        Content
        """
        
        let doc = MarkdownMerger.parse(content, sectionLevel: 2)
        
        XCTAssertTrue(doc.frontmatter.contains("date: 2026-01-15"))
        XCTAssertTrue(doc.frontmatter.contains("type: health-data"))
        XCTAssertTrue(doc.frontmatter.hasPrefix("---"))
    }
    
    func testParse_noFrontmatter() {
        let content = """
        # Title
        Content here
        """
        
        let doc = MarkdownMerger.parse(content, sectionLevel: 2)
        
        XCTAssertEqual(doc.frontmatter, "")
    }
    
    func testParse_extractsPreamble() {
        let content = """
        ---
        date: 2026-01-15
        ---
        # Health Data — January 15, 2026
        
        Summary of the day.
        
        ## Sleep
        - Total: 7h
        """
        
        let doc = MarkdownMerger.parse(content, sectionLevel: 2)
        
        XCTAssertTrue(doc.preamble.contains("Health Data"))
        XCTAssertTrue(doc.preamble.contains("Summary of the day"))
    }
    
    func testParse_extractsSections() {
        let content = """
        # Title
        
        ## Sleep
        - Total: 7h
        
        ## Activity
        - Steps: 10000
        """
        
        let doc = MarkdownMerger.parse(content, sectionLevel: 2)
        
        XCTAssertEqual(doc.sections.count, 2)
        XCTAssertEqual(doc.sections[0].normalizedName, "sleep")
        XCTAssertEqual(doc.sections[1].normalizedName, "activity")
    }
    
    func testParse_preservesSectionBody() {
        let content = """
        # Title
        
        ## Sleep
        - Total: 7h
        - Deep: 2h
        - REM: 1.5h
        
        ## Activity
        - Steps: 10000
        """
        
        let doc = MarkdownMerger.parse(content, sectionLevel: 2)
        
        XCTAssertTrue(doc.sections[0].body.contains("Total: 7h"))
        XCTAssertTrue(doc.sections[0].body.contains("Deep: 2h"))
        XCTAssertTrue(doc.sections[0].body.contains("REM: 1.5h"))
    }
    
    func testParse_subsectionsRemainInParent() {
        let content = """
        ## Sleep
        - Total: 7h
        ### Sleep Quality Notes
        My notes about sleep quality
        """
        
        let doc = MarkdownMerger.parse(content, sectionLevel: 2)
        
        // Should be one section (Sleep) containing the subsection
        XCTAssertEqual(doc.sections.count, 1)
        XCTAssertEqual(doc.sections[0].normalizedName, "sleep")
        XCTAssertTrue(doc.sections[0].body.contains("Sleep Quality Notes"))
        XCTAssertTrue(doc.sections[0].body.contains("My notes about sleep quality"))
    }
    
    func testParse_respectsSectionLevel() {
        let content = """
        # Main
        ## Sub1
        Content1
        ## Sub2
        Content2
        """
        
        // Parse at level 1 - only # headings are sections
        let doc1 = MarkdownMerger.parse(content, sectionLevel: 1)
        XCTAssertEqual(doc1.sections.count, 1)
        XCTAssertEqual(doc1.sections[0].normalizedName, "main")
        
        // Parse at level 2 - ## headings are sections
        let doc2 = MarkdownMerger.parse(content, sectionLevel: 2)
        XCTAssertEqual(doc2.sections.count, 2)
        XCTAssertEqual(doc2.sections[0].normalizedName, "sub1")
        XCTAssertEqual(doc2.sections[1].normalizedName, "sub2")
    }
    
    // MARK: - merge Tests
    
    func testMerge_replacesSectionContent() {
        let existing = """
        ---
        date: 2026-01-15
        ---
        # Health Data
        
        ## Sleep
        - Total: 6h
        
        """
        
        let new = """
        ---
        date: 2026-01-15
        ---
        # Health Data
        
        ## Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        XCTAssertTrue(result.contains("Total: 8h"))
        XCTAssertFalse(result.contains("Total: 6h"))
    }
    
    func testMerge_preservesUserSections() {
        let existing = """
        ---
        date: 2026-01-15
        ---
        # Health Data
        
        ## Sleep
        - Total: 6h
        
        ## My Personal Notes
        This is my custom section that should be preserved.
        
        """
        
        let new = """
        ---
        date: 2026-01-15
        ---
        # Health Data
        
        ## Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // New sleep data
        XCTAssertTrue(result.contains("Total: 8h"))
        // User section preserved
        XCTAssertTrue(result.contains("## My Personal Notes"))
        XCTAssertTrue(result.contains("This is my custom section that should be preserved."))
    }
    
    func testMerge_preservesSectionOrder() {
        let existing = """
        ## Activity
        - Steps: 5000
        
        ## My Notes
        User notes here
        
        ## Sleep
        - Total: 6h
        
        """
        
        let new = """
        ## Sleep
        - Total: 8h
        
        ## Activity
        - Steps: 10000
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // Verify order: Activity, My Notes, Sleep (preserving existing order)
        let activityPos = result.range(of: "## Activity")!.lowerBound
        let notesPos = result.range(of: "## My Notes")!.lowerBound
        let sleepPos = result.range(of: "## Sleep")!.lowerBound
        
        XCTAssertTrue(activityPos < notesPos)
        XCTAssertTrue(notesPos < sleepPos)
    }
    
    func testMerge_addsNewSections() {
        let existing = """
        ## Sleep
        - Total: 6h
        
        """
        
        let new = """
        ## Sleep
        - Total: 8h
        
        ## Activity
        - Steps: 10000
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // Both sections present
        XCTAssertTrue(result.contains("## Sleep"))
        XCTAssertTrue(result.contains("## Activity"))
        XCTAssertTrue(result.contains("Steps: 10000"))
    }
    
    func testMerge_updatesFrontmatter() {
        let existing = """
        ---
        date: 2026-01-15
        steps: 5000
        ---
        # Old Title
        
        ## Sleep
        - Total: 6h
        
        """
        
        let new = """
        ---
        date: 2026-01-15
        steps: 10000
        ---
        # New Title
        
        ## Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // New frontmatter values used (overwrite existing)
        XCTAssertTrue(result.contains("steps: 10000"))
        XCTAssertFalse(result.contains("steps: 5000"))
        // New title used
        XCTAssertTrue(result.contains("# New Title"))
    }
    
    func testMerge_preservesMultilineFrontmatterValues() {
        let existing = """
        ---
        date: 2026-01-15
        medication_dose_events:
          - name: "Old"
            status: skipped
        ---
        # Old Title
        """

        let new = """
        ---
        date: 2026-01-15
        medication_dose_events:
          - name: "D3 Vitamin"
            status: taken
        ---
        # New Title
        """

        let result = MarkdownMerger.merge(existing: existing, new: new)

        XCTAssertTrue(result.contains("medication_dose_events:\n  - name: \"D3 Vitamin\"\n    status: taken"), result)
        XCTAssertFalse(result.contains("medication_dose_events:   -"), result)
        XCTAssertFalse(result.contains("name: \"Old\""), result)
    }

    func testMergeFrontmatter_preservesOneItemListAndUnrelatedPhysicalBlocksExactly() {
        let existing = "---\ndate: 2026-08-03\ntags:\n  - daily-notes\naliases:\n  - Health\n  - Journal\n# User-owned settings stay where they are.\n\npreferences:\n  dashboard:\n    visible: true\n---\n"
        let incoming = "---\ndate: 2026-07-30\nsteps: 2119\n---\n"
        let expected = "---\ndate: 2026-07-30\ntags:\n  - daily-notes\naliases:\n  - Health\n  - Journal\n# User-owned settings stay where they are.\n\npreferences:\n  dashboard:\n    visible: true\nsteps: 2119\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatter_replacesCompleteNestedBlockAtItsFirstPosition() {
        let existing = "---\nmetadata:\n  source: old\n  labels:\n    - stale\nkeep: unchanged\n---\n"
        let incoming = "---\nmetadata:\n  source: healthmd\n  labels:\n    - first\n    - second\n---\n"
        let expected = "---\nmetadata:\n  source: healthmd\n  labels:\n    - first\n    - second\nkeep: unchanged\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatter_removesCollidingDuplicatesButPreservesUnrelatedDuplicates() {
        let existing = "---\nsteps: 100\ncustom: first\n# Keep this comment.\nsteps: 200\ncustom: second\n---\n"
        let incoming = "---\nsteps: 300\n---\n"
        let expected = "---\nsteps: 300\ncustom: first\n# Keep this comment.\ncustom: second\n---\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergeFrontmatter_preservesCRLFAndUsesItForIncomingBlocks() {
        let existing = "---\r\ntags:\r\n  - daily-notes\r\ncustom: keep\r\n---\r\n"
        let incoming = "---\ntags:\n  - healthmd\n  - synced\nsteps: 42\n---\n"
        let expected = "---\r\ntags:\r\n  - healthmd\r\n  - synced\r\ncustom: keep\r\nsteps: 42\r\n---\r\n"

        XCTAssertEqual(MarkdownMerger.mergeFrontmatter(existing: existing, new: incoming), expected)
    }

    func testMergePreservingPreamble_keepsBlockScalarsIndentedDelimiterAndBodyExact() {
        let frontmatter = "---\nsummary: |-\n  first line\n  ---\n  last line\n\nfolded: >+\n  one folded\n  paragraph\n---\n"
        let body = "# My Daily Note\n\nUser prose with no final newline"
        let incoming = "---\nsteps: 42\n---\n"
        let expectedFrontmatter = "---\nsummary: |-\n  first line\n  ---\n  last line\n\nfolded: >+\n  one folded\n  paragraph\nsteps: 42\n---\n"

        let result = MarkdownMerger.mergePreservingPreamble(
            existing: frontmatter + body,
            new: incoming
        )

        XCTAssertEqual(result, expectedFrontmatter + body)
    }

    func testMerge_preservesUserFrontmatterProperties() {
        let existing = """
        ---
        date: 2026-01-15
        tags: [daily, journal]
        mood: great
        breakfast: oatmeal
        ---
        # Daily Note
        
        ## Sleep
        - Total: 6h
        
        """
        
        let new = """
        ---
        date: 2026-01-15
        type: health-data
        sleep_total_hours: 7.50
        steps: 10000
        ---
        # Health — January 15, 2026
        
        ## Sleep
        - Total: 7.5h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // User properties preserved
        XCTAssertTrue(result.contains("tags: [daily, journal]"))
        XCTAssertTrue(result.contains("mood: great"))
        XCTAssertTrue(result.contains("breakfast: oatmeal"))
        
        // New health properties added
        XCTAssertTrue(result.contains("type: health-data"))
        XCTAssertTrue(result.contains("sleep_total_hours: 7.50"))
        XCTAssertTrue(result.contains("steps: 10000"))
        
        // Date preserved (same in both)
        XCTAssertTrue(result.contains("date: 2026-01-15"))
    }
    
    func testMerge_overwritesCommonFrontmatterKeys() {
        let existing = """
        ---
        date: 2026-01-15
        steps: 5000
        custom_field: my value
        ---
        # Note
        
        """
        
        let new = """
        ---
        date: 2026-01-15
        steps: 12000
        sleep_hours: 8
        ---
        # Note
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // Common key overwritten with new value
        XCTAssertTrue(result.contains("steps: 12000"))
        XCTAssertFalse(result.contains("steps: 5000"))
        
        // Existing-only key preserved
        XCTAssertTrue(result.contains("custom_field: my value"))
        
        // New-only key added
        XCTAssertTrue(result.contains("sleep_hours: 8"))
    }
    
    func testMerge_handlesEmptyExisting() {
        let existing = ""
        
        let new = """
        ---
        date: 2026-01-15
        ---
        # Health Data
        
        ## Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        XCTAssertTrue(result.contains("## Sleep"))
        XCTAssertTrue(result.contains("Total: 8h"))
    }
    
    func testMerge_preservesMultipleUserSections() {
        let existing = """
        ## Sleep
        - Total: 6h
        
        ## Journal
        My daily journal entry
        
        ## Activity
        - Steps: 5000
        
        ## Reflections
        End of day thoughts
        
        """
        
        let new = """
        ## Sleep
        - Total: 8h
        
        ## Activity
        - Steps: 10000
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // User sections preserved
        XCTAssertTrue(result.contains("## Journal"))
        XCTAssertTrue(result.contains("My daily journal entry"))
        XCTAssertTrue(result.contains("## Reflections"))
        XCTAssertTrue(result.contains("End of day thoughts"))
    }
    
    func testMerge_matchesSectionsWithEmoji() {
        let existing = """
        ## 😴 Sleep
        - Total: 6h
        
        ## My Notes
        User content
        
        """
        
        let new = """
        ## 😴 Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // Sleep section updated
        XCTAssertTrue(result.contains("Total: 8h"))
        XCTAssertFalse(result.contains("Total: 6h"))
        // User section preserved
        XCTAssertTrue(result.contains("## My Notes"))
    }
    
    func testMerge_matchesSectionsDifferentEmojiStyle() {
        // Existing has emoji, new doesn't (or vice versa)
        let existing = """
        ## 😴 Sleep
        - Total: 6h
        
        """
        
        let new = """
        ## Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // Should match and replace
        XCTAssertTrue(result.contains("Total: 8h"))
        XCTAssertFalse(result.contains("Total: 6h"))
    }
    
    func testMerge_preservesSubsectionsInUserContent() {
        let existing = """
        ## Sleep
        - Total: 6h
        
        ## My Analysis
        ### Sleep Trends
        Looking at the past week...
        ### Improvement Ideas
        - Go to bed earlier
        
        """
        
        let new = """
        ## Sleep
        - Total: 8h
        
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        
        // User section with subsections preserved
        XCTAssertTrue(result.contains("## My Analysis"))
        XCTAssertTrue(result.contains("### Sleep Trends"))
        XCTAssertTrue(result.contains("Looking at the past week"))
        XCTAssertTrue(result.contains("### Improvement Ideas"))
    }
    
    // MARK: - Edge Cases
    
    func testMerge_handlesWindowsLineEndings() {
        let existing = "## Sleep\r\n- Total: 6h\r\n"
        let new = "## Sleep\n- Total: 8h\n"
        
        // Should not crash
        let result = MarkdownMerger.merge(existing: existing, new: new)
        XCTAssertFalse(result.isEmpty)
    }
    
    func testMerge_handlesNoSections() {
        let existing = """
        ---
        date: 2026-01-15
        ---
        Just some notes without sections
        """
        
        let new = """
        ---
        date: 2026-01-15
        ---
        ## Sleep
        - Total: 8h
        """
        
        let result = MarkdownMerger.merge(existing: existing, new: new)
        XCTAssertTrue(result.contains("## Sleep"))
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
