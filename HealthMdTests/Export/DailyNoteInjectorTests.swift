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

    // Static ObservableObject instances to avoid the macOS 26 / Swift 6
    // reentrant-main-actor-deinit crash.
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

    // Static MetricSelectionState instances to avoid ObservableObject deinit crash
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
