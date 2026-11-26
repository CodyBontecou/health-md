import XCTest
@testable import HealthMd

/// The profile's metric selection alone decides which metrics a note holds (#465). Format →
/// Custom (the frontmatter field switches) only places a selected metric's fields in frontmatter
/// or leaves them in the body, for every category including workouts (#353).
final class FrontmatterFieldOwnershipTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation state that can
    // crash during test-process teardown on macOS 26 (same workaround as ExporterSmokeTests).
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

    func testOneWorkoutFieldSwitchedOffRemovesThatPropertyAndTheRecordBlock() {
        let settings = makeSettings()
        setFields(["workout_calories"], enabled: false, in: settings)
        for format in [ExportFormat.markdown, .obsidianBases] {
            let keys = frontmatterKeys(ExportFixtures.fullDay.export(format: format, settings: settings))
            XCTAssertFalse(keys.contains("workout_calories"), "\(format)")
            XCTAssertTrue(keys.contains("workout_count"), "\(format)")
            // #465: each workout_details record holds calories, so a customized group drops it.
            XCTAssertFalse(keys.contains("workout_details"), "\(format)")
        }
    }

    /// #465: Format → Custom → Workouts with a few fields on writes exactly those workout keys
    /// and nothing else; the default configuration keeps the structured block.
    func testCustomWorkoutsAddNoFrontmatterKeysBeyondTheFieldsSwitchedOn() {
        let defaults = makeSettings()
        let custom = makeSettings()
        let chosen: Set<String> = ["workout_count", "workout_minutes", "workout_details"]
        setFields(Self.workoutFieldKeys.filter { !chosen.contains($0) }, enabled: false, in: custom)
        let data = ExportFixtures.fullDay
        for format in [ExportFormat.markdown, .obsidianBases] {
            let defaultKeys = Set(frontmatterKeys(data.export(format: format, settings: defaults)))
            if format == .obsidianBases {
                XCTAssertTrue(defaultKeys.contains("workout_details"), "Default Bases output keeps the block")
            }
            let output = data.export(format: format, settings: custom)
            let keys = Set(frontmatterKeys(output))
            XCTAssertEqual(keys.filter(Self.isWorkoutKey), ["workout_count", "workout_minutes"], "\(format)")
            XCTAssertEqual(keys.subtracting(defaultKeys), [], "\(format) adds no key")
            let frontmatter = output.components(separatedBy: "\n---").first ?? output
            XCTAssertFalse(frontmatter.contains("    calories: "), "\(format) holds no unselected workout property")
            XCTAssertFalse(frontmatter.contains("    hr_avg: "), "\(format) holds no unselected workout property")
        }
    }

    /// #465: the profile's metric selection alone decides which metrics a note holds. Two
    /// profiles with different selections write only their own metrics, whatever Format → Custom
    /// says about the other profile's fields.
    func testTwoProfilesWriteOnlyTheirOwnMetrics() {
        let stepsOnly = makeSettings()
        let workoutsOnly = makeSettings()
        for (settings, metric) in [(stepsOnly, "steps"), (workoutsOnly, "workouts")] {
            for id in settings.metricSelection.enabledMetrics where id != metric {
                settings.metricSelection.setMetric(id, enabled: false)
            }
            settings.metricSelection.setMetric(metric, enabled: true)
            // Every Format → Custom field on, including those of metrics the profile omits.
            setFields(FrontmatterConfiguration.defaultFields.map(\.originalKey), enabled: true, in: settings)
        }
        let data = ExportFixtures.fullDay
        for format in [ExportFormat.markdown, .obsidianBases] {
            let steps = Set(frontmatterKeys(data.export(format: format, settings: stepsOnly)))
            let workouts = Set(frontmatterKeys(data.export(format: format, settings: workoutsOnly)))
            XCTAssertTrue(steps.contains("steps"), "\(format)")
            XCTAssertEqual(steps.filter(Self.isWorkoutKey), [], "\(format)")
            XCTAssertTrue(workouts.contains("workout_count"), "\(format)")
            XCTAssertFalse(workouts.contains("steps"), "\(format)")
            for key in FrontmatterConfiguration.defaultFields.map(\.originalKey) {
                if !HealthMetricExportMapping.profileExportsFrontmatterField(key, enabledMetricIDs: ["steps"]) {
                    XCTAssertFalse(steps.contains(key), "\(format) steps profile wrote \(key)")
                }
                if !HealthMetricExportMapping.profileExportsFrontmatterField(key, enabledMetricIDs: ["workouts"]) {
                    XCTAssertFalse(workouts.contains(key), "\(format) workouts profile wrote \(key)")
                }
            }
        }
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
