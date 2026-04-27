//
//  DailyNoteInjectorTests.swift
//  HealthMdTests
//
//  TDD tests for DailyNoteInjector: metric mapping, frontmatter injection,
//  content merging, and file creation logic.
//
//  NOTE: MetricSelectionState and FormatCustomization are ObservableObjects.
//  Static instances avoid the macOS 26 / Swift 6 reentrant-main-actor-deinit crash.
//

import XCTest
@testable import HealthMd

final class DailyNoteInjectorTests: XCTestCase {

    // Stable test date for deterministic filenames
    private static let testDate: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 27
        return Calendar.current.date(from: comps)!
    }()

    private static let customization = FormatCustomization()

    // STATIC RETENTION JUSTIFICATION: All instances below are immutable shared
    // read-only fixtures. Per-test factories are not needed because no test
    // mutates them. Static retention avoids the macOS 26 / Swift 6 ObservableObject
    // deinit crash. See docs/testing/lifecycle-audit.md.
    private static let disabledSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.enabled = false
        return s
    }()

    private static let enabledCreateSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.enabled = true
        s.createIfMissing = true
        s.folderPath = ""
        s.filenamePattern = "{date}"
        return s
    }()

    private static let enabledNoCreateSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.enabled = true
        s.createIfMissing = false
        s.folderPath = ""
        s.filenamePattern = "{date}"
        return s
    }()

    private static let subfolderSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.enabled = true
        s.createIfMissing = true
        s.folderPath = "Daily/Journal"
        s.filenamePattern = "{date}"
        return s
    }()

    /// Same as enabledCreateSettings but with body-section injection turned on.
    private static let sectionsCreateSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.enabled = true
        s.createIfMissing = true
        s.folderPath = ""
        s.filenamePattern = "{date}"
        s.injectMarkdownSections = true
        return s
    }()

    /// Same as enabledNoCreateSettings but with body-section injection turned on.
    private static let sectionsNoCreateSettings: DailyNoteInjectionSettings = {
        let s = DailyNoteInjectionSettings()
        s.enabled = true
        s.createIfMissing = false
        s.folderPath = ""
        s.filenamePattern = "{date}"
        s.injectMarkdownSections = true
        return s
    }()

    // STATIC RETENTION JUSTIFICATION: Same rationale as above — immutable shared
    // MetricSelectionState fixtures for read-only use in inject() tests.
    private static let allDeselected: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        return s
    }()

    private static let stepsOnly: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("steps")
        return s
    }()

    private static let sleepTotalOnly: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("sleep_total")
        return s
    }()

    private static let workoutsOnly: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("workouts")
        return s
    }()

    private static let allEnabled = MetricSelectionState()

    private static let heartSelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("resting_heart_rate")
        s.enabledMetrics.insert("hrv")
        return s
    }()

    private static let nutritionSelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("dietary_energy")
        s.enabledMetrics.insert("dietary_protein")
        return s
    }()

    private static let dailyMoodSelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("daily_mood")
        return s
    }()

    private static let averageValenceSelection: MetricSelectionState = {
        let s = MetricSelectionState()
        s.deselectAll()
        s.enabledMetrics.insert("average_valence")
        return s
    }()

    // MARK: - frontmatterKeys

    func testFrontmatterKeys_allDisabled_returnsEmpty() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.allDeselected)
        XCTAssertTrue(keys.isEmpty)
    }

    func testFrontmatterKeys_sleepTotalEnabled() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.sleepTotalOnly)
        XCTAssertTrue(keys.contains("sleep_total_hours"))
    }

    func testFrontmatterKeys_stepsEnabled() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.stepsOnly)
        XCTAssertEqual(keys, ["steps"])
    }

    func testFrontmatterKeys_workoutsEnabled_returnsMultipleKeys() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.workoutsOnly)
        XCTAssertTrue(keys.contains("workout_count"))
        XCTAssertTrue(keys.contains("workout_minutes"))
        XCTAssertTrue(keys.contains("workout_calories"))
        XCTAssertTrue(keys.contains("workout_distance_km"))
        XCTAssertTrue(keys.contains("workouts"))
    }

    func testFrontmatterKeys_noDuplicates() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.allEnabled)
        XCTAssertEqual(keys.count, Set(keys).count, "frontmatterKeys should not contain duplicates")
    }

    func testFrontmatterKeys_heartMetrics() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.heartSelection)
        XCTAssertTrue(keys.contains("resting_heart_rate"))
        XCTAssertTrue(keys.contains("hrv_ms"))
    }

    func testFrontmatterKeys_nutritionMetrics() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.nutritionSelection)
        XCTAssertTrue(keys.contains("dietary_calories"))
        XCTAssertTrue(keys.contains("protein_g"))
    }

    func testFrontmatterKeys_dailyMoodEnabled_returnsDailyMoodKeys() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.dailyMoodSelection)
        XCTAssertTrue(keys.contains("daily_mood_count"))
        XCTAssertTrue(keys.contains("daily_mood_percent"))
    }

    func testFrontmatterKeys_averageValenceEnabled_returnsValenceAndPercent() {
        let keys = DailyNoteInjector.frontmatterKeys(enabledIn: Self.averageValenceSelection)
        XCTAssertTrue(keys.contains("average_mood_valence"))
        XCTAssertTrue(keys.contains("average_mood_percent"))
    }

    // MARK: - inject: disabled

    func testInject_disabledSettings_skips() {
        let result = DailyNoteInjector.inject(
            healthData: HealthData(date: Self.testDate),
            into: URL(fileURLWithPath: NSTemporaryDirectory()),
            settings: Self.disabledSettings,
            customization: Self.customization,
            metricSelection: Self.allEnabled
        )
        if case .skipped(let reason) = result {
            XCTAssertEqual(reason, "Injection disabled")
        } else {
            XCTFail("Expected .skipped when injection is disabled")
        }
    }

    // MARK: - inject: no data for enabled metrics

    func testInject_noDataForEnabledMetrics_skips() {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let result = DailyNoteInjector.inject(
            healthData: HealthData(date: Self.testDate),
            into: tmpDir,
            settings: Self.enabledCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )
        if case .skipped(let reason) = result {
            XCTAssertTrue(reason.contains("No data available"))
        } else if case .updated = result {
            XCTFail("Should skip when no data for enabled metrics")
        }
    }

    // MARK: - inject: missing file, createIfMissing = false

    func testInject_missingFile_createIfMissingFalse_skips() {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 10_000

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.enabledNoCreateSettings,
            customization: Self.customization,
            metricSelection: Self.allEnabled
        )
        if case .skipped(let reason) = result {
            XCTAssertTrue(reason.contains("not found"))
        } else {
            XCTFail("Expected .skipped when file missing and createIfMissing=false")
        }
    }

    // MARK: - inject: creates file and writes data

    func testInject_createsFileAndWritesData() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 10_432

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.enabledCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        if case .updated = result {
            let filename = Self.enabledCreateSettings.formatFilename(for: Self.testDate) + ".md"
            let fileURL = tmpDir.appendingPathComponent(filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(content.contains("steps:"))
            XCTAssertTrue(content.hasPrefix("---"))
        } else if case .failed(let error) = result {
            XCTFail("Injection failed: \(error)")
        } else if case .skipped(let reason) = result {
            XCTFail("Injection skipped: \(reason)")
        }
    }

    // MARK: - inject: merge into existing frontmatter

    func testInject_mergesIntoExistingFrontmatter() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        // Pre-create the file with existing frontmatter
        let filename = Self.enabledNoCreateSettings.formatFilename(for: Self.testDate) + ".md"
        let fileURL = tmpDir.appendingPathComponent(filename)
        let existingContent = "---\ntitle: Monday\ntags: journal\n---\n\n# My Notes\nSome content"
        try existingContent.write(to: fileURL, atomically: true, encoding: .utf8)

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 10_432

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.enabledNoCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        if case .updated = result {
            let updatedContent = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(updatedContent.contains("title: Monday"))
            XCTAssertTrue(updatedContent.contains("tags: journal"))
            XCTAssertTrue(updatedContent.contains("steps:"))
            XCTAssertTrue(updatedContent.contains("# My Notes"))
            XCTAssertTrue(updatedContent.contains("Some content"))
        } else if case .failed(let error) = result {
            XCTFail("Injection failed: \(error)")
        } else if case .skipped(let reason) = result {
            XCTFail("Injection skipped: \(reason)")
        }
    }

    // MARK: - inject: preserves body on empty file

    func testInject_emptyFile_writesFrontmatterOnly() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 8_000

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.enabledCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        if case .updated = result {
            let filename = Self.enabledCreateSettings.formatFilename(for: Self.testDate) + ".md"
            let fileURL = tmpDir.appendingPathComponent(filename)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(content.hasPrefix("---\n"))
            let separators = content.components(separatedBy: "---").count - 1
            XCTAssertEqual(separators, 2)
        } else if case .failed(let error) = result {
            XCTFail("Injection failed: \(error)")
        } else {
            XCTFail("Expected .updated")
        }
    }

    // MARK: - inject: subfolder creation

    func testInject_subfolderPath_createsNestedDirectories() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 5_000

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.subfolderSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        if case .updated = result {
            let filename = Self.subfolderSettings.formatFilename(for: Self.testDate) + ".md"
            let fileURL = tmpDir
                .appendingPathComponent("Daily/Journal")
                .appendingPathComponent(filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        } else if case .failed(let error) = result {
            XCTFail("Injection failed: \(error)")
        } else if case .skipped(let reason) = result {
            XCTFail("Injection skipped: \(reason)")
        }
    }

    // MARK: - inject: markdown sections

    func testInject_sectionsEnabled_writesBodySectionsAlongsideFrontmatter() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 9_001

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.sectionsCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        guard case .updated = result else {
            XCTFail("Expected .updated, got \(result)")
            return
        }

        let fileURL = tmpDir.appendingPathComponent(Self.sectionsCreateSettings.formatFilename(for: Self.testDate) + ".md")
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Frontmatter still gets written.
        XCTAssertTrue(content.hasPrefix("---\n"))
        XCTAssertTrue(content.contains("steps: 9001"))

        // Body now contains an Activity section with the steps line.
        XCTAssertTrue(content.contains("## "), "Expected at least one level-2 section heading in body")
        XCTAssertTrue(content.range(of: "Activity") != nil, "Expected Activity section heading in body")
        XCTAssertTrue(content.contains("**Steps:**"), "Expected steps bullet in body")
    }

    func testInject_sectionsEnabled_secondRunReplacesAppSectionsAndKeepsUserSections() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        // First run with one value.
        var data1 = HealthData(date: Self.testDate)
        data1.activity.steps = 1_000
        _ = DailyNoteInjector.inject(
            healthData: data1,
            into: tmpDir,
            settings: Self.sectionsCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        // User adds their own journal section after the app's content.
        let fileURL = tmpDir.appendingPathComponent(Self.sectionsCreateSettings.formatFilename(for: Self.testDate) + ".md")
        var afterFirst = try String(contentsOf: fileURL, encoding: .utf8)
        afterFirst += "\n## Journal\n\nFelt great today.\n"
        try afterFirst.write(to: fileURL, atomically: true, encoding: .utf8)

        // Second run with a fresh value.
        var data2 = HealthData(date: Self.testDate)
        data2.activity.steps = 7_500
        let result = DailyNoteInjector.inject(
            healthData: data2,
            into: tmpDir,
            settings: Self.sectionsCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )
        guard case .updated = result else {
            XCTFail("Expected .updated on re-run, got \(result)")
            return
        }

        let merged = try String(contentsOf: fileURL, encoding: .utf8)

        // App-managed Activity section should be replaced with the new value.
        XCTAssertTrue(merged.contains("7,500") || merged.contains("7500"),
                      "Expected updated step count in Activity section")
        XCTAssertFalse(merged.contains("1,000") || merged.contains(": 1000\n"),
                       "Old value should not survive in body")

        // Frontmatter steps should also be updated.
        XCTAssertTrue(merged.contains("steps: 7500"))

        // User's Journal section is preserved.
        XCTAssertTrue(merged.contains("## Journal"))
        XCTAssertTrue(merged.contains("Felt great today."))
    }

    func testInject_sectionsEnabled_preservesExistingPreamble() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        // Pre-create note with frontmatter, a user title, and intro prose — but no app sections yet.
        let filename = Self.sectionsNoCreateSettings.formatFilename(for: Self.testDate) + ".md"
        let fileURL = tmpDir.appendingPathComponent(filename)
        let existing = "---\ntitle: My Day\n---\n\n# Monday\n\nWoke up rested.\n"
        try existing.write(to: fileURL, atomically: true, encoding: .utf8)

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 5_000

        let result = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.sectionsNoCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )
        guard case .updated = result else {
            XCTFail("Expected .updated, got \(result)")
            return
        }

        let merged = try String(contentsOf: fileURL, encoding: .utf8)

        // User preamble preserved (no "Health Data — …" title from the exporter).
        XCTAssertTrue(merged.contains("# Monday"))
        XCTAssertTrue(merged.contains("Woke up rested."))
        XCTAssertFalse(merged.contains("# Health Data —"),
                       "Exporter's own title should not bleed into the user's daily note")

        // Existing frontmatter property preserved, new metric added.
        XCTAssertTrue(merged.contains("title: My Day"))
        XCTAssertTrue(merged.contains("steps: 5000"))

        // Activity section appended.
        XCTAssertTrue(merged.contains("Activity"))
        XCTAssertTrue(merged.contains("**Steps:**"))
    }

    func testInject_sectionsDisabled_bodyNeverModified() throws {
        let tmpDir = makeTempDir()
        defer { cleanup(tmpDir) }

        let filename = Self.enabledNoCreateSettings.formatFilename(for: Self.testDate) + ".md"
        let fileURL = tmpDir.appendingPathComponent(filename)
        let existing = "---\ntitle: My Day\n---\n\n# Monday\nA paragraph the user wrote.\n"
        try existing.write(to: fileURL, atomically: true, encoding: .utf8)

        var data = HealthData(date: Self.testDate)
        data.activity.steps = 5_000

        _ = DailyNoteInjector.inject(
            healthData: data,
            into: tmpDir,
            settings: Self.enabledNoCreateSettings,
            customization: Self.customization,
            metricSelection: Self.stepsOnly
        )

        let merged = try String(contentsOf: fileURL, encoding: .utf8)
        // Body untouched: no Activity heading was inserted.
        XCTAssertFalse(merged.contains("## Activity"),
                       "Frontmatter-only mode must not write body sections")
        XCTAssertFalse(merged.contains("**Steps:**"))
        // But frontmatter was updated.
        XCTAssertTrue(merged.contains("steps: 5000"))
        XCTAssertTrue(merged.contains("# Monday"))
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
