import HealthMdCoreRust
import XCTest
@testable import HealthMd

final class ExportSettingsSnapshotTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; existing tests retain them
    // to avoid platform-specific deinit crashes while the process tears down.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testSnapshotFromAdvancedSettings_preservesAllExportAffectingFields() throws {
        let settings = makeConfiguredSettings()

        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "2. Areas/Health"
        )

        XCTAssertEqual(snapshot.exportFormats, [.markdown, .obsidianBases, .json, .csv])
        XCTAssertFalse(snapshot.includeMetadata)
        XCTAssertFalse(snapshot.groupByCategory)
        XCTAssertEqual(snapshot.filenameFormat, "health-{date}")
        XCTAssertEqual(snapshot.folderStructure, "{year}/{month}")
        XCTAssertEqual(snapshot.healthSubfolder, "2. Areas/Health")
        XCTAssertTrue(snapshot.organizeFormatsIntoFolders)
        XCTAssertEqual(snapshot.writeMode, .update)
        XCTAssertTrue(snapshot.includeGranularData)
        XCTAssertTrue(snapshot.generateWeeklyRollups)
        XCTAssertTrue(snapshot.generateMonthlyRollups)
        XCTAssertFalse(snapshot.generateYearlyRollups)
        XCTAssertTrue(snapshot.summaryOnlyExport)
        XCTAssertTrue(snapshot.appleExportEngineAuthorityIsFrozen)

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
        XCTAssertTrue(snapshot.dailyNoteInjection.dailyNotesOnly)
        XCTAssertTrue(snapshot.dailyNotesOnlyModeEnabled)
        XCTAssertTrue(snapshot.hasFileDestinationOutput)

        XCTAssertEqual(snapshot.metricSelection.enabledMetricIDs, ["steps", "sleep_total_hours"])
        XCTAssertEqual(snapshot.metricSelection.enabledCategoryIDs, [HealthMetricCategory.activity.rawValue, HealthMetricCategory.sleep.rawValue])
    }

    func testSnapshot_roundTripsThroughJSON() throws {
        let snapshot = ExportSettingsSnapshot.from(
            makeConfiguredSettings(),
            healthSubfolder: "2. Areas/Health"
        )

        let data = try JSONEncoder().encode(snapshot)
        let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: data)

        XCTAssertEqual(encodedObject["includeGranularData"] as? Bool, true)
        XCTAssertTrue(decoded.includeGranularData)
        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshot_decodesLegacyPayloadWithoutLosslessRecordsBoolean() throws {
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "includeGranularData")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: legacyData)

        XCTAssertFalse(decoded.includeGranularData)
        XCTAssertEqual(decoded.exportFormats, snapshot.exportFormats)
        XCTAssertEqual(decoded.metricSelection, snapshot.metricSelection)
    }

    func testSnapshot_decodesLegacyDailyNoteSettingsWithoutDailyNotesOnly() throws {
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var dailyNote = try XCTUnwrap(object["dailyNoteInjection"] as? [String: Any])
        dailyNote.removeValue(forKey: "dailyNotesOnly")
        object["dailyNoteInjection"] = dailyNote
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: legacyData)

        XCTAssertFalse(decoded.dailyNoteInjection.dailyNotesOnly)
        XCTAssertFalse(decoded.dailyNotesOnlyModeEnabled)
        XCTAssertEqual(decoded.dailyNoteInjection.folderPath, "Journal/Daily")
    }

    func testSnapshot_decodesOlderPayloadWithoutFormatFolderKey() throws {
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "organizeFormatsIntoFolders")
        object.removeValue(forKey: "healthSubfolder")
        object.removeValue(forKey: "generateWeeklyRollups")
        object.removeValue(forKey: "generateMonthlyRollups")
        object.removeValue(forKey: "generateYearlyRollups")
        object.removeValue(forKey: "summaryOnlyExport")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ExportSettingsSnapshot.self, from: legacyData)

        XCTAssertFalse(decoded.organizeFormatsIntoFolders)
        XCTAssertFalse(decoded.generateWeeklyRollups)
        XCTAssertFalse(decoded.generateMonthlyRollups)
        XCTAssertFalse(decoded.generateYearlyRollups)
        XCTAssertFalse(decoded.summaryOnlyExport)
        XCTAssertNil(decoded.healthSubfolder)
        XCTAssertEqual(decoded.exportFormats, snapshot.exportFormats)
        XCTAssertEqual(decoded.folderStructure, snapshot.folderStructure)
    }

    func testSnapshotEnginePinAndCalendarTimeZoneRoundTrip() throws {
        let pin = try makeSyntheticAppleExportEnginePin(
            engine: .rust,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )
        let snapshot = ExportSettingsSnapshot.from(
            makeConfiguredSettings(),
            appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )

        let decoded = try JSONDecoder().decode(
            ExportSettingsSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.appleExportEnginePin, pin)
        XCTAssertEqual(decoded.calendarTimeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(decoded, snapshot)
    }

    @MainActor
    func testNewSupportedSummaryRollupOperationCapturesRustPinAfterCapabilityGate() async throws {
        let settings = makeSimpleEngineSettings()
        settings.generateWeeklyRollups = true
        settings.summaryOnlyExport = true
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")),
            surface: .localVaultRangeWithoutSideEffects,
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            )
        )

        XCTAssertTrue(snapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertEqual(snapshot.appleExportEnginePin?.engine, .rust)
        XCTAssertEqual(
            snapshot.appleExportEnginePin?.calendarTimeZoneIdentifier,
            "America/Los_Angeles"
        )
    }

    @MainActor
    func testShadowPinsRemainAvailableForDailyAndAPIParityCoverage() async throws {
        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "shadow",
            userDefaults: nil,
            environment: [:]
        )
        for surface in [
            AppleExportOperationSurface.localVaultWithoutSideEffects,
            .apiEndpoint,
        ] {
            let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(
                makeSimpleEngineSettings(),
                healthSubfolder: "Health",
                calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
                surface: surface,
                policyResolver: resolver
            )
            XCTAssertTrue(snapshot.appleExportEngineAuthorityIsFrozen)
            XCTAssertEqual(snapshot.appleExportEnginePin?.engine, .shadow)
        }
    }

    @MainActor
    func testNewRollupOperationCapturesPinForLocalAndDirectRangeSurfaces() async throws {
        let settings = makeSimpleEngineSettings()
        settings.generateWeeklyRollups = true
        settings.summaryOnlyExport = true
        let timezone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "rust",
            userDefaults: nil,
            environment: [:]
        )

        let range = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: timezone,
            surface: .localVaultRangeWithoutSideEffects,
            policyResolver: resolver
        )
        let directRange = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: timezone,
            surface: .directGeneratedFilesWithoutSideEffects,
            policyResolver: resolver
        )
        let singleDay = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: timezone,
            surface: .localVaultWithoutSideEffects,
            policyResolver: resolver,
            coreExecutor: SnapshotNeverCoreExecutor()
        )

        XCTAssertEqual(range.appleExportEnginePin?.engine, .rust)
        XCTAssertTrue(range.appleExportEngineAuthorityIsFrozen)
        XCTAssertEqual(directRange.appleExportEnginePin?.engine, .rust)
        XCTAssertTrue(directRange.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(singleDay.appleExportEnginePin)
        XCTAssertTrue(singleDay.appleExportEngineAuthorityIsFrozen)
    }

    @MainActor
    func testNewUnsupportedOrLegacyOnlyOperationNeverLoadsCoreOrCapturesPin() async throws {
        let unsupported = makeSimpleEngineSettings()
        unsupported.writeMode = .append
        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "rust",
            userDefaults: nil,
            environment: [:]
        )
        let executor = SnapshotNeverCoreExecutor()

        let unsupportedSnapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            unsupported,
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            surface: .localVaultWithoutSideEffects,
            policyResolver: resolver,
            coreExecutor: executor
        )
        let unsupportedPureRustDailySnapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            makeSimpleEngineSettings(),
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            surface: .localVaultRangeWithoutSideEffects,
            policyResolver: resolver,
            coreExecutor: executor
        )
        let unsupportedPureRustAPISnapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            makeSimpleEngineSettings(),
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            surface: .apiEndpoint,
            policyResolver: resolver,
            coreExecutor: executor
        )
        let legacyOnlySnapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            makeSimpleEngineSettings(),
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            surface: .legacyOnly,
            policyResolver: resolver,
            coreExecutor: executor
        )

        XCTAssertTrue(unsupportedSnapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(unsupportedSnapshot.appleExportEnginePin)
        XCTAssertTrue(unsupportedPureRustDailySnapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(unsupportedPureRustDailySnapshot.appleExportEnginePin)
        XCTAssertTrue(unsupportedPureRustAPISnapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(unsupportedPureRustAPISnapshot.appleExportEnginePin)
        XCTAssertTrue(legacyOnlySnapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(legacyOnlySnapshot.appleExportEnginePin)
    }

    func testPresentSnapshotPinRejectsUnknownOrExplicitLegacyEngine() throws {
        let pin = try makeSyntheticAppleExportEnginePin()
        let snapshot = ExportSettingsSnapshot.from(
            makeSimpleEngineSettings(),
            appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )

        for invalidEngine in ["future-engine", "legacy"] {
            var object = encoded
            var encodedPin = try XCTUnwrap(object["appleExportEnginePin"] as? [String: Any])
            encodedPin["engine"] = invalidEngine
            object["appleExportEnginePin"] = encodedPin
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ExportSettingsSnapshot.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            )
        }
    }

    func testLegacySnapshotDecodesWithoutPinOrCalendarTimeZone() throws {
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        object.removeValue(forKey: "appleExportEnginePin")
        object.removeValue(forKey: "appleExportEngineAuthorityIsFrozen")
        object.removeValue(forKey: "calendarTimeZoneIdentifier")

        let decoded = try JSONDecoder().decode(
            ExportSettingsSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.appleExportEnginePin)
        XCTAssertTrue(decoded.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(decoded.calendarTimeZoneIdentifier)
    }

    func testSnapshotRestoresOnlyValidIANACalendarTimeZone() {
        var valid = ExportSettingsSnapshot.from(makeConfiguredSettings())
        valid.calendarTimeZoneIdentifier = "America/New_York"
        let restored = valid.makeAdvancedExportSettings()
        Self.retainedSettings.append(restored)
        XCTAssertEqual(restored.exportTimeZoneOverride?.identifier, "America/New_York")

        var invalid = valid
        invalid.calendarTimeZoneIdentifier = "+05:00"
        let invalidRestored = invalid.makeAdvancedExportSettings()
        Self.retainedSettings.append(invalidRestored)
        XCTAssertNil(invalidRestored.exportTimeZoneOverride)
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
        XCTAssertTrue(reconstructed.generateWeeklyRollups)
        XCTAssertTrue(reconstructed.generateMonthlyRollups)
        XCTAssertFalse(reconstructed.generateYearlyRollups)
        XCTAssertTrue(reconstructed.summaryOnlyExport)
        XCTAssertFalse(reconstructed.summaryOnlyModeEnabled)
        XCTAssertEqual(reconstructed.effectiveFileExportMode, .dailyNotesOnly)
        XCTAssertEqual(reconstructed.metricSelection.enabledMetrics, ["steps", "sleep_total_hours"])
        XCTAssertEqual(reconstructed.metricSelection.enabledCategories, [HealthMetricCategory.activity.rawValue, HealthMetricCategory.sleep.rawValue])
        XCTAssertEqual(reconstructed.formatCustomization.frontmatterConfig.customFields, ["source": "Health.md"])
        XCTAssertEqual(reconstructed.individualTracking.metricConfigs["steps"]?.customFolder, "Movement")
        XCTAssertTrue(reconstructed.dailyNoteInjection.injectMarkdownSections)
        XCTAssertTrue(reconstructed.dailyNoteInjection.dailyNotesOnly)
        XCTAssertTrue(reconstructed.dailyNotesOnlyModeEnabled)
        XCTAssertTrue(reconstructed.executionAppleExportEngineAuthorityIsFrozen)

        XCTAssertEqual(macDefaults.string(forKey: "advancedExportSettings.filenameFormat"), "mac-local-{date}")
        XCTAssertEqual(macDefaults.string(forKey: "advancedExportSettings.writeMode"), "MacLocal")
    }

    func testSnapshotReconstructionDoesNotReplayPropertyObserversIntoDefaults() throws {
        let suiteName = "ExportSettingsSnapshotTests.reconstructed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let snapshot = ExportSettingsSnapshot.from(makeConfiguredSettings())

        let reconstructed = snapshot.makeAdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(reconstructed)

        XCTAssertNil(defaults.object(forKey: "advancedExportSettings.filenameFormat"))
        XCTAssertNil(defaults.object(forKey: "advancedExportSettings.formats"))

        reconstructed.filenameFormat = "changed-{date}"
        XCTAssertEqual(
            defaults.string(forKey: "advancedExportSettings.filenameFormat"),
            "changed-{date}"
        )
    }

    private func makeSimpleEngineSettings() -> AdvancedExportSettings {
        let suiteName = "ExportSettingsSnapshotTests.engine.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        return settings
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
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = true
        settings.generateYearlyRollups = false
        settings.summaryOnlyExport = true

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
        settings.dailyNoteInjection.dailyNotesOnly = true

        settings.metricSelection.enabledMetrics = ["steps", "sleep_total_hours"]
        settings.metricSelection.enabledCategories = [
            HealthMetricCategory.activity.rawValue,
            HealthMetricCategory.sleep.rawValue
        ]

        return settings
    }
}

nonisolated private struct SnapshotNeverCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    private struct UnexpectedCall: Error {}

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        throw UnexpectedCall()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        throw UnexpectedCall()
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        throw UnexpectedCall()
    }
}
