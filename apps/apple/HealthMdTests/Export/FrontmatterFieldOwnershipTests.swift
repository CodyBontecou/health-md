import XCTest
@testable import HealthMd

/// Format → Custom (the frontmatter field switches) decides which properties go into
/// frontmatter, for every category including workouts (#353). The per-note field list
/// (metric selection) decides which data is collected; it is not a second frontmatter switch.
final class FrontmatterFieldOwnershipTests: XCTestCase {
    /// AdvancedExportSettings are retained per the macOS deinit-crash workaround in ExporterSmokeTests.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private static func isWorkoutKey(_ key: String) -> Bool {
        key == "workouts" || key.hasPrefix("workout_")
    }

    private static var workoutFieldKeys: [String] {
        FrontmatterConfiguration.defaultFields.map(\.originalKey).filter(isWorkoutKey)
    }

    private func makeSettings(formats: Set<ExportFormat> = [.markdown, .obsidianBases]) -> AdvancedExportSettings {
        let suite = "healthmd.tests.frontmatter-ownership.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = formats
        settings.includeMetadata = true
        return settings
    }

    /// Top-level YAML keys between the first pair of `---` fences.
    private func frontmatterKeys(_ output: String) -> [String] {
        let lines = output.components(separatedBy: "\n")
        guard lines.first == "---" else { return [] }
        return lines.dropFirst().prefix { $0 != "---" }
            .filter { !$0.isEmpty && !($0.first?.isWhitespace ?? true) && $0.contains(":") }
            .map { String($0[..<$0.firstIndex(of: ":")!]) }
    }

    private func setFields(_ keys: [String], enabled: Bool, in settings: AdvancedExportSettings) {
        let config = settings.formatCustomization.frontmatterConfig
        for index in config.fields.indices where keys.contains(config.fields[index].originalKey) {
            config.fields[index].isEnabled = enabled
        }
    }

    func testWorkoutNoteHasWorkoutPropertiesByDefault() {
        let settings = makeSettings()
        let data = ExportFixtures.fullDay
        XCTAssertFalse(data.workouts.isEmpty)
        for format in [ExportFormat.markdown, .obsidianBases] {
            let keys = frontmatterKeys(data.export(format: format, settings: settings))
            XCTAssertTrue(keys.contains("workout_count"), "\(format)")
            XCTAssertTrue(keys.contains("workouts"), "\(format)")
        }
    }

    func testWorkoutFieldsSwitchedOffInFormatCustomLeaveNoWorkoutFrontmatter() {
        XCTAssertTrue(Self.workoutFieldKeys.contains("workout_details"))
        let settings = makeSettings()
        // The workouts metric stays on: the data is still collected and shown in the body.
        XCTAssertTrue(settings.metricSelection.isMetricEnabled("workouts"))
        setFields(Self.workoutFieldKeys, enabled: false, in: settings)
        let data = ExportFixtures.fullDay

        for format in [ExportFormat.markdown, .obsidianBases] {
            let output = data.export(format: format, settings: settings)
            let keys = frontmatterKeys(output)
            XCTAssertEqual(keys.filter(Self.isWorkoutKey), [], "\(format) frontmatter")
            XCTAssertFalse(keys.contains("workout_details"), "\(format) workout_details block")
            XCTAssertTrue(keys.contains("steps"), "\(format) keeps other properties")
            if format == .markdown {
                XCTAssertTrue(output.contains("Workouts"), "The body still lists the collected workout")
            }
        }
    }

    func testOneWorkoutFieldSwitchedOffRemovesOnlyThatProperty() {
        let settings = makeSettings()
        setFields(["workout_calories"], enabled: false, in: settings)
        let keys = frontmatterKeys(ExportFixtures.fullDay.export(format: .markdown, settings: settings))
        XCTAssertFalse(keys.contains("workout_calories"))
        XCTAssertTrue(keys.contains("workout_count"))
    }

    func testWorkoutsMetricOffCollectsNoWorkoutDataSoNoWorkoutFrontmatter() {
        let settings = makeSettings()
        settings.metricSelection.setMetric("workouts", enabled: false)
        for format in [ExportFormat.markdown, .obsidianBases] {
            let keys = frontmatterKeys(ExportFixtures.fullDay.export(format: format, settings: settings))
            XCTAssertEqual(keys.filter(Self.isWorkoutKey), [], "\(format)")
        }
    }

    /// Migration: a configuration saved by an older version keeps its exact output.
    func testLegacySavedConfigurationKeepsExistingOutput() throws {
        // Older versions saved only the fields they knew (no workout_details); one was switched off.
        let legacyJSON = #"{"fields":[{"originalKey":"steps","customKey":"steps","isEnabled":false},"# +
            #"{"originalKey":"workout_count","customKey":"workout_count","isEnabled":true}]}"#
        let legacy = try JSONDecoder().decode(FrontmatterConfiguration.self, from: Data(legacyJSON.utf8))

        let migrated = makeSettings()
        FrontmatterConfigurationSnapshot.from(legacy).apply(to: migrated.formatCustomization.frontmatterConfig)
        let expanded = makeSettings()
        setFields(["steps"], enabled: false, in: expanded)

        for format in [ExportFormat.markdown, .obsidianBases] {
            let output = ExportFixtures.fullDay.export(format: format, settings: migrated)
            XCTAssertEqual(output, ExportFixtures.fullDay.export(format: format, settings: expanded), "\(format)")
            let keys = frontmatterKeys(output)
            XCTAssertFalse(keys.contains("steps"))
            XCTAssertTrue(keys.contains("workout_count"))
        }
    }
}
