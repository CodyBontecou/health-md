//
//  MarkdownMergerTests.swift
//  HealthMdTests
//
//  Tests for MarkdownMerger - critical for "Update" write mode
//

import XCTest
@testable import HealthMd

final class MarkdownMergerTests: XCTestCase {
    
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
}
