import XCTest
@testable import HealthMd

final class ExportSettingsSnapshotTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; existing tests retain them
    // to avoid platform-specific deinit crashes while the process tears down.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testSnapshotFromAdvancedSettings_preservesAllExportAffectingFields() throws {
        let settings = makeConfiguredSettings()

        let snapshot = ExportSettingsSnapshot.from(settings)

        XCTAssertEqual(snapshot.exportFormats, [.markdown, .obsidianBases, .json, .csv])
        XCTAssertFalse(snapshot.includeMetadata)
        XCTAssertFalse(snapshot.groupByCategory)
        XCTAssertEqual(snapshot.filenameFormat, "health-{date}")
        XCTAssertEqual(snapshot.folderStructure, "{year}/{month}")
        XCTAssertTrue(snapshot.organizeFormatsIntoFolders)
        XCTAssertEqual(snapshot.writeMode, .update)
        XCTAssertTrue(snapshot.includeGranularData)

        XCTAssertEqual(snapshot.formatCustomization.dateFormat, .usLong)
        XCTAssertEqual(snapshot.formatCustomization.timeFormat, .hour12WithSeconds)
        XCTAssertEqual(snapshot.formatCustomization.unitPreference, .imperial)
        XCTAssertEqual(snapshot.formatCustomization.markdownTemplate.style, .custom)
        XCTAssertEqual(snapshot.formatCustomization.markdownTemplate.customTemplate, "Custom {{date}}")
        XCTAssertEqual(snapshot.formatCustomization.markdownTemplate.sectionHeaderLevel, 3)
        XCTAssertTrue(snapshot.formatCustomization.markdownTemplate.useEmoji)
        XCTAssertFalse(snapshot.formatCustomization.markdownTemplate.includeSummary)
        XCTAssertEqual(snapshot.formatCustomization.markdownTemplate.bulletStyle, .plus)

        let frontmatter = snapshot.formatCustomization.frontmatterConfig
        XCTAssertFalse(frontmatter.includeDate)
        XCTAssertFalse(frontmatter.includeType)
        XCTAssertEqual(frontmatter.customDateKey, "day")
        XCTAssertEqual(frontmatter.customTypeKey, "kind")
        XCTAssertEqual(frontmatter.customTypeValue, "wellness-log")
        XCTAssertEqual(frontmatter.keyStyle, .camelCase)
        XCTAssertEqual(frontmatter.customFields, ["source": "Health.md"])
        XCTAssertEqual(frontmatter.placeholderFields, ["notes", "symptoms"])
        XCTAssertEqual(frontmatter.fields.first?.customKey, "sleepHoursCustom")
        XCTAssertEqual(frontmatter.fields.first?.isEnabled, false)

        XCTAssertTrue(snapshot.individualTracking.globalEnabled)
        XCTAssertEqual(snapshot.individualTracking.entriesFolder, "Tracked Entries")
        XCTAssertFalse(snapshot.individualTracking.useCategoryFolders)
        XCTAssertEqual(snapshot.individualTracking.filenameTemplate, "{date}-{time}-{metric}")
        XCTAssertEqual(snapshot.individualTracking.metricConfigs["steps"]?.trackIndividually, true)
        XCTAssertEqual(snapshot.individualTracking.metricConfigs["steps"]?.customFolder, "Movement")

        XCTAssertTrue(snapshot.dailyNoteInjection.enabled)
        XCTAssertEqual(snapshot.dailyNoteInjection.folderPath, "Journal/Daily")
        XCTAssertEqual(snapshot.dailyNoteInjection.filenamePattern, "daily-{date}")
        XCTAssertTrue(snapshot.dailyNoteInjection.createIfMissing)
        XCTAssertTrue(snapshot.dailyNoteInjection.injectMarkdownSections)

        XCTAssertEqual(snapshot.metricSelection.enabledMetricIDs, ["steps", "sleep_total_hours"])
        XCTAssertEqual(snapshot.metricSelection.enabledCategoryIDs, [HealthMetricCategory.activity.rawValue, HealthMetricCategory.sleep.rawValue])
    }

    func testSnapshot_roundTripsThroughJSON() throws {
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshot_decodesOlderPayloadWithoutFormatFolderKey() throws {
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "organizeFormatsIntoFolders")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: legacyData)

        XCTAssertFalse(decoded.organizeFormatsIntoFolders)
        XCTAssertEqual(decoded.exportFormats, snapshot.exportFormats)
        XCTAssertEqual(decoded.folderStructure, snapshot.folderStructure)
    }

    func testFrontmatterConfigurationDecode_migratesImperialDistanceFields() throws {
        let legacy = FrontmatterConfiguration()
        legacy.applyKeyStyle(.camelCase)
        if let cyclingIndex = legacy.fields.firstIndex(where: { $0.originalKey == "cycling_km" }) {
            legacy.fields[cyclingIndex].isEnabled = false
        }
        legacy.fields.removeAll {
            ["walking_running_mi", "cycling_mi", "workout_distance_mi"].contains($0.originalKey)
        }

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(FrontmatterConfiguration.self, from: data)

        let walkingRunningMi = decoded.fields.first { $0.originalKey == "walking_running_mi" }
        let cyclingMi = decoded.fields.first { $0.originalKey == "cycling_mi" }
        let workoutDistanceMi = decoded.fields.first { $0.originalKey == "workout_distance_mi" }

        XCTAssertEqual(walkingRunningMi?.customKey, "walkingRunningMi")
        XCTAssertEqual(cyclingMi?.customKey, "cyclingMi")
        XCTAssertEqual(cyclingMi?.isEnabled, false)
        XCTAssertEqual(workoutDistanceMi?.customKey, "workoutDistanceMi")
    }

    func testSnapshotCanCreateAdvancedSettingsWithoutMutatingCallerDefaults() throws {
        let macSuiteName = "ExportSettingsSnapshotTests.mac.\(UUID().uuidString)"
        let macDefaults = try XCTUnwrap(UserDefaults(suiteName: macSuiteName))
        macDefaults.removePersistentDomain(forName: macSuiteName)
        macDefaults.set("mac-local-{date}", forKey: "advancedExportSettings.filenameFormat")
        macDefaults.set("MacLocal", forKey: "advancedExportSettings.writeMode")

        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())
        let reconstructed = snapshot.makeAdvancedExportSettings()
        Self.retainedSettings.append(reconstructed)

        XCTAssertEqual(reconstructed.exportFormats, snapshot.exportFormats)
        XCTAssertEqual(reconstructed.filenameFormat, "health-{date}")
        XCTAssertEqual(reconstructed.folderStructure, "{year}/{month}")
        XCTAssertTrue(reconstructed.organizeFormatsIntoFolders)
        XCTAssertEqual(reconstructed.writeMode, .update)
        XCTAssertTrue(reconstructed.includeGranularData)
        XCTAssertEqual(reconstructed.metricSelection.enabledMetrics, ["steps", "sleep_total_hours"])
        XCTAssertEqual(reconstructed.metricSelection.enabledCategories, [HealthMetricCategory.activity.rawValue, HealthMetricCategory.sleep.rawValue])
        XCTAssertEqual(reconstructed.formatCustomization.frontmatterConfig.customFields, ["source": "Health.md"])
        XCTAssertEqual(reconstructed.individualTracking.metricConfigs["steps"]?.customFolder, "Movement")
        XCTAssertTrue(reconstructed.dailyNoteInjection.injectMarkdownSections)

        XCTAssertEqual(macDefaults.string(forKey: "advancedExportSettings.filenameFormat"), "mac-local-{date}")
        XCTAssertEqual(macDefaults.string(forKey: "advancedExportSettings.writeMode"), "MacLocal")
    }

    private func makeConfiguredSettings() -> AdvancedExportSettings {
        let suiteName = "ExportSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)

        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.includeMetadata = false
        settings.groupByCategory = false
        settings.filenameFormat = "health-{date}"
        settings.folderStructure = "{year}/{month}"
        settings.organizeFormatsIntoFolders = true
        settings.writeMode = .update
        settings.includeGranularData = true

        settings.formatCustomization.dateFormat = .usLong
        settings.formatCustomization.timeFormat = .hour12WithSeconds
        settings.formatCustomization.unitPreference = .imperial
        settings.formatCustomization.frontmatterConfig.includeDate = false
        settings.formatCustomization.frontmatterConfig.includeType = false
        settings.formatCustomization.frontmatterConfig.customDateKey = "day"
        settings.formatCustomization.frontmatterConfig.customTypeKey = "kind"
        settings.formatCustomization.frontmatterConfig.customTypeValue = "wellness-log"
        settings.formatCustomization.frontmatterConfig.keyStyle = .camelCase
        settings.formatCustomization.frontmatterConfig.customFields = ["source": "Health.md"]
        settings.formatCustomization.frontmatterConfig.placeholderFields = ["notes", "symptoms"]
        settings.formatCustomization.frontmatterConfig.fields[0].customKey = "sleepHoursCustom"
        settings.formatCustomization.frontmatterConfig.fields[0].isEnabled = false
        var markdownTemplate = MarkdownTemplateConfig()
        markdownTemplate.style = .custom
        markdownTemplate.customTemplate = "Custom {{date}}"
        markdownTemplate.sectionHeaderLevel = 3
        markdownTemplate.useEmoji = true
        markdownTemplate.includeSummary = false
        markdownTemplate.bulletStyle = .plus
        settings.formatCustomization.markdownTemplate = markdownTemplate

        settings.individualTracking.globalEnabled = true
        settings.individualTracking.entriesFolder = "Tracked Entries"
        settings.individualTracking.useCategoryFolders = false
        settings.individualTracking.filenameTemplate = "{date}-{time}-{metric}"
        settings.individualTracking.metricConfigs = [
            "steps": MetricTrackingConfig(trackIndividually: true, customFolder: "Movement")
        ]

        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.folderPath = "Journal/Daily"
        settings.dailyNoteInjection.filenamePattern = "daily-{date}"
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.injectMarkdownSections = true

        settings.metricSelection.enabledMetrics = ["steps", "sleep_total_hours"]
        settings.metricSelection.enabledCategories = [
            HealthMetricCategory.activity.rawValue,
            HealthMetricCategory.sleep.rawValue
        ]

        return settings
    }
}
