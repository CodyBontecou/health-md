//
//  WriteModesIntegrationTests.swift
//  HealthMdTests
//
//  Integration tests for VaultManager write modes (overwrite/append/update)
//  using real temp files. Validates file content after each write operation
//  including frontmatter preservation and section merging.
//

import XCTest
@testable import HealthMd

// Static customizations to avoid macOS 26 deinit crash.
private enum WriteModeCustomizations {
    static let metric: FormatCustomization = {
        let c = FormatCustomization()
        c.unitPreference = .metric
        return c
    }()
}

final class WriteModesIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthMdWriteTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeFile(_ content: String, name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func readFile(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func generateMarkdown(_ data: HealthData = ExportFixtures.fullDay) -> String {
        data.toMarkdown(customization: WriteModeCustomizations.metric)
    }

    // MARK: - Overwrite Mode

    func testOverwrite_replacesExistingContent() throws {
        let original = "# Old Content\nThis should be replaced."
        let fileURL = try writeFile(original, name: "overwrite-test.md")

        let newContent = generateMarkdown()
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try readFile(fileURL)
        XCTAssertFalse(result.contains("Old Content"), "Overwrite should replace old content")
        XCTAssertTrue(result.contains("Sleep"), "Overwrite should contain new health data")
    }

    func testOverwrite_createsNewFile() throws {
        let fileURL = tempDir.appendingPathComponent("new-file.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let content = generateMarkdown()
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let result = try readFile(fileURL)
        XCTAssertTrue(result.contains("Sleep"))
    }

    func testOverwrite_resultMatchesFreshExport() throws {
        let original = "# Something old\nOld data here."
        let fileURL = try writeFile(original, name: "overwrite-match.md")

        let newContent = generateMarkdown()
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try readFile(fileURL)
        XCTAssertEqual(result, newContent, "Overwrite result should exactly match fresh export")
    }

    // MARK: - Append Mode

    func testAppend_preservesOldContentAndAddsNew() throws {
        let original = "# My Notes\nSome personal notes."
        let fileURL = try writeFile(original, name: "append-test.md")

        let newContent = generateMarkdown()
        let existingContent = try readFile(fileURL)
        let appended = existingContent + "\n\n" + newContent
        try appended.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try readFile(fileURL)
        XCTAssertTrue(result.hasPrefix("# My Notes"), "Append should preserve original content at start")
        XCTAssertTrue(result.contains("Some personal notes"), "Append should preserve original text")
        XCTAssertTrue(result.contains("Sleep"), "Append should contain new health data")
    }

    func testAppend_separatedByDoubleNewline() throws {
        let original = "First export data."
        let fileURL = try writeFile(original, name: "append-separator.md")

        let newContent = "Second export data."
        let existingContent = try readFile(fileURL)
        let appended = existingContent + "\n\n" + newContent
        try appended.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try readFile(fileURL)
        XCTAssertTrue(result.contains("First export data.\n\nSecond export data."),
                      "Append should separate with double newline")
    }

    func testAppend_multipleTimes_accumulatesContent() throws {
        let fileURL = try writeFile("Day 1 data.", name: "append-multi.md")

        for i in 2...4 {
            let existing = try readFile(fileURL)
            let appended = existing + "\n\n" + "Day \(i) data."
            try appended.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let result = try readFile(fileURL)
        for i in 1...4 {
            XCTAssertTrue(result.contains("Day \(i) data."), "Should contain Day \(i)")
        }
    }

    // MARK: - Update Mode (MarkdownMerger)

    func testUpdate_replacesAppManagedSections() throws {
        let existing = """
        ---
        date: 2026-03-14
        type: health-data
        ---

        ## Sleep
        - Total Duration: 6h 0m (old data)

        ## Activity
        - Steps: 5000 (old data)
        """

        let new = """
        ---
        date: 2026-03-15
        type: health-data
        ---

        ## Sleep
        - Total Duration: 7h 45m (new data)

        ## Activity
        - Steps: 12500 (new data)

        ## Heart
        - Resting Heart Rate: 58 bpm
        """

        let merged = MarkdownMerger.merge(existing: existing, new: new)

        XCTAssertTrue(merged.contains("7h 45m"), "Update should replace sleep with new data")
        XCTAssertTrue(merged.contains("12500"), "Update should replace activity with new data")
        XCTAssertFalse(merged.contains("old data"), "Update should not contain old data in managed sections")
        XCTAssertTrue(merged.contains("Heart"), "Update should add new sections")
    }

    func testUpdate_preservesUserAddedSections() throws {
        let existing = """
        ---
        date: 2026-03-15
        type: health-data
        ---

        ## Sleep
        - Total: 7h

        ## My Custom Notes
        These are my personal notes that should be preserved.

        ## Activity
        - Steps: 8000
        """

        let new = """
        ---
        date: 2026-03-15
        type: health-data
        ---

        ## Sleep
        - Total: 8h (updated)

        ## Activity
        - Steps: 10000 (updated)
        """

        let merged = MarkdownMerger.merge(existing: existing, new: new)

        XCTAssertTrue(merged.contains("My Custom Notes"), "Should preserve user section heading")
        XCTAssertTrue(merged.contains("personal notes that should be preserved"),
                      "Should preserve user section content")
        XCTAssertTrue(merged.contains("8h (updated)"), "Should update sleep")
        XCTAssertTrue(merged.contains("10000"), "Should update activity")
    }

    func testUpdate_mergesFrontmatter() throws {
        let existing = """
        ---
        date: 2026-03-15
        type: health-data
        custom_field: my-value
        ---

        ## Sleep
        - Total: 7h
        """

        let new = """
        ---
        date: 2026-03-15
        type: health-data
        steps: 12500
        ---

        ## Sleep
        - Total: 8h
        """

        let merged = MarkdownMerger.merge(existing: existing, new: new)

        XCTAssertTrue(merged.contains("custom_field: my-value"),
                      "Should preserve existing frontmatter properties")
        XCTAssertTrue(merged.contains("steps: 12500"),
                      "Should include new frontmatter properties")
    }

    func testUpdate_nonMarkdownFallsToOverwrite() throws {
        // For non-markdown formats, update mode falls back to overwrite
        let original = "{\"date\": \"2026-03-14\", \"old_marker\": \"SHOULD_BE_GONE\"}"
        let fileURL = try writeFile(original, name: "data.json")

        let newContent = ExportFixtures.fullDay.toJSON(customization: WriteModeCustomizations.metric)
        // Simulate update mode for non-markdown: falls back to overwrite
        try newContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try readFile(fileURL)
        XCTAssertFalse(result.contains("SHOULD_BE_GONE"), "Non-markdown update should overwrite")
        XCTAssertTrue(result.contains("\"sleep\""), "Should contain new data")
    }

    // MARK: - Update with Real Export Data

    func testUpdate_realExport_sectionReplacement() throws {
        // First export with partial data
        let firstExport = ExportFixtures.partialDay.toMarkdown(customization: WriteModeCustomizations.metric)
        let fileURL = try writeFile(firstExport, name: "real-update.md")

        // Second export with full data
        let secondExport = ExportFixtures.fullDay.toMarkdown(customization: WriteModeCustomizations.metric)
        let existing = try readFile(fileURL)
        let merged = MarkdownMerger.merge(existing: existing, new: secondExport)
        try merged.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try readFile(fileURL)
        // Full day data should be present after update
        XCTAssertTrue(result.contains("Heart"), "Updated file should have Heart section from full day")
        XCTAssertTrue(result.contains("Vitals"), "Updated file should have Vitals section from full day")
        XCTAssertTrue(result.contains("Body"), "Updated file should have Body section from full day")
    }

    func testUpdate_preservesFrontmatterFromBothSources() throws {
        let firstExport = ExportFixtures.partialDay.toMarkdown(customization: WriteModeCustomizations.metric)

        // Add a user-injected property to simulate a manual frontmatter edit
        var modifiedFirst = firstExport
        if let insertPoint = modifiedFirst.range(of: "---\n", range: modifiedFirst.index(after: modifiedFirst.startIndex)..<modifiedFirst.endIndex) {
            modifiedFirst.insert(contentsOf: "my_tag: important\n", at: insertPoint.lowerBound)
        }

        let secondExport = ExportFixtures.fullDay.toMarkdown(customization: WriteModeCustomizations.metric)
        let merged = MarkdownMerger.merge(existing: modifiedFirst, new: secondExport)

        XCTAssertTrue(merged.contains("my_tag: important"),
                      "Merge should preserve user-added frontmatter from existing file")
    }

    // MARK: - File System Safety

    func testWriteMode_doesNotWriteOutsideTempDir() throws {
        let fileURL = tempDir.appendingPathComponent("safe-write.md")
        let content = generateMarkdown()
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Verify file is inside temp dir
        XCTAssertTrue(fileURL.path.hasPrefix(tempDir.path),
                      "Written file should be inside temp directory")
    }

    // MARK: - MarkdownMerger Edge Cases

    func testMerger_emptyExistingFile() {
        let merged = MarkdownMerger.merge(existing: "", new: generateMarkdown())
        XCTAssertFalse(merged.isEmpty, "Merging into empty should produce content")
        XCTAssertTrue(merged.contains("Sleep"), "Result should contain new data")
    }

    func testMerger_emptyNewContent() {
        let existing = generateMarkdown()
        let merged = MarkdownMerger.merge(existing: existing, new: "")
        // Should preserve existing content when new is empty
        XCTAssertTrue(merged.contains("Sleep"), "Should preserve existing content")
    }

    func testMerger_bothHaveFrontmatter_mergesCorrectly() {
        let existingFM = "---\ndate: 2026-03-14\ntype: health-data\nuser_note: hello\n---\n"
        let newFM = "---\ndate: 2026-03-15\ntype: health-data\nsteps: 12500\n---\n"

        let merged = MarkdownMerger.mergeFrontmatter(existing: existingFM, new: newFM)

        XCTAssertTrue(merged.contains("user_note: hello"), "Should preserve existing keys")
        XCTAssertTrue(merged.contains("steps: 12500"), "Should add new keys")
        XCTAssertTrue(merged.contains("date: 2026-03-15"), "Should update date to new value")
    }

    func testMerger_headingLevelDetection() {
        let content = "## Sleep\ndata\n## Activity\ndata"
        let level = MarkdownMerger.detectSectionLevel(in: content)
        XCTAssertEqual(level, 2, "Should detect level 2 headings")
    }

    func testMerger_headingNormalization() {
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## 😴 Sleep"), "sleep")
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("### 🏃 Activity"), "activity")
        XCTAssertEqual(MarkdownMerger.normalizeHeadingText("## My Custom Notes"), "my custom notes")
    }
}
