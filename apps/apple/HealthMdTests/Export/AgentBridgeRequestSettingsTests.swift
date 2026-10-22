import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust
import XCTest
#if canImport(HealthMd)
@testable import HealthMd
#else
@testable import AgentBridgeRequestSettingsHarness
#endif

final class AgentBridgeRequestSettingsTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_779_998_400)

    func testExplicitJSONUsesNativeMappingsAndYearLayout() throws {
        let result = try resolve(intent(metrics: ["heart_rate_avg", "steps"]))
        XCTAssertEqual(result.settings.exportFormats, [.json])
        XCTAssertEqual(result.settings.folderStructure, "{year}")
        XCTAssertEqual(result.settings.filenameFormat, "{date}")
        XCTAssertEqual(result.settings.healthSubfolder, "")
        XCTAssertEqual(result.predictedRelativePaths, ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(result.selection.map(\.semanticID), ["heart_rate_avg", "steps"])
        XCTAssertEqual(result.selection.map(\.nativeMetricID), ["heart_rate_avg", "steps"])
        XCTAssertEqual(result.selection.map(\.sourceSelector), ["HKQuantityTypeIdentifierHeartRate", "HKQuantityTypeIdentifierStepCount"])
        XCTAssertEqual(result.selection.map(\.sourceReducer), ["discreteAvg", "cumulative"])
        XCTAssertEqual(result.selection.map(\.canonicalUnit), ["bpm", "steps"])
        XCTAssertEqual(result.settings.metricSelection.enabledMetricIDs, ["heart_rate_avg", "steps"])
        XCTAssertFalse(result.settings.metricSelection.enabledMetricIDs.contains("hrv"))
        XCTAssertFalse(result.settings.metricSelection.enabledMetricIDs.contains("heart_rate_min"))
        XCTAssertEqual(result.settings.metricSelection.enabledCategoryIDs, ["Heart", "Activity"])
        XCTAssertEqual(result.settings.detailPolicy, .summary)
        XCTAssertFalse(result.settings.includeDataDictionary)
        XCTAssertFalse(result.settings.archiveExportFiles)
        XCTAssertFalse(result.settings.generateRangeSummary)
        XCTAssertFalse(result.settings.individualTracking.globalEnabled)
        XCTAssertFalse(result.settings.dailyNoteInjection.enabled)
        XCTAssertEqual(result.settings.calendarTimeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(result.resolvedAt, clock)
        XCTAssertTrue(result.settings.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(result.settings.appleExportEnginePin)
    }

    func testFutureSelectionAndLayoutDoNotChangeFrozenResultOrPreferences() throws {
        let suite = "AgentBridgeRequestSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("synthetic-api-target", forKey: "api.target")
        defaults.set(Data([1, 2, 3]), forKey: "synthetic.preferences")
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let first = try resolve(intent(metrics: ["steps"]))
        let encoded = try JSONEncoder().encode(first)
        _ = try resolve(intent(metrics: ["heart_rate_min"], folder: "next/{month}", filename: "daily-{date}"))
        XCTAssertThrowsError(try resolve(intent(metrics: ["unknown.metric"])))
        // Discard/reconstruct is cancellation-like: no live apply or preference migration.
        let resumed = try JSONDecoder().decode(AgentBridgeRequestSettingsResolution.self, from: encoded)
        XCTAssertEqual(resumed, first)
        let execution = try first.makeExporterSettings()
        execution.filenameFormat = "discarded-{date}"
        execution.metricSelection.enabledMetrics = ["heart_rate_max"]
        execution.formatCustomization.unitPreference = .imperial
        let reused = try resumed.makeExporterSettings()
        XCTAssertEqual(reused.filenameFormat, "{date}")
        XCTAssertEqual(reused.metricSelection.enabledMetrics, ["steps"])
        XCTAssertEqual(reused.formatCustomization.unitPreference, .metric)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }

    func testConfigurationReuseRejectsChangedRequestCatalogAndSavedOutput() throws {
        let request = try intent()
        let catalog = try makeCatalog()
        let inputs = AgentBridgeRequestSettingsInputs(catalog: catalog, savedDevice: nil, profiles: [])
        let frozen = try resolve(request, inputs: inputs)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        try AgentBridgeRequestSettingsResolver.validateForReuse(frozen, intent: request, inputs: inputs, calendar: calendar)
        expect(.bindingChanged) {
            try AgentBridgeRequestSettingsResolver.validateForReuse(frozen, intent: intent(metrics: ["heart_rate_min"]), inputs: inputs, calendar: calendar)
        }
        let changedCatalog = try AgentBridgeRequestSettingsCatalog(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: ["steps"], revision: 4)
        expect(.bindingChanged) {
            try AgentBridgeRequestSettingsResolver.validateForReuse(frozen, intent: request, inputs: .init(catalog: changedCatalog, savedDevice: nil, profiles: []), calendar: calendar)
        }
        let changedAvailability = try makeCatalog(available: ["steps", "heart_rate_min"])
        expect(.bindingChanged) {
            try AgentBridgeRequestSettingsResolver.validateForReuse(frozen, intent: request, inputs: .init(catalog: changedAvailability, savedDevice: nil, profiles: []), calendar: calendar)
        }
        let savedRequest = try intent(policy: .savedDeviceSettings(expectedRevision: 2))
        let savedInputs = AgentBridgeRequestSettingsInputs(catalog: catalog, savedDevice: .init(revision: 2, settings: frozen.settings), profiles: [])
        let saved = try resolve(savedRequest, inputs: savedInputs)
        var changed = frozen.settings
        changed.folderStructure = "changed/{year}"
        expect(.bindingChanged) {
            try AgentBridgeRequestSettingsResolver.validateForReuse(saved, intent: savedRequest, inputs: .init(catalog: catalog, savedDevice: .init(revision: 2, settings: changed), profiles: []), calendar: calendar)
        }
    }

    func testDetachedConstructionDoesNotPersistEvenSubsequentMutations() throws {
        let suite = "AgentBridgeRequestSettingsTests.detached.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(AgentBridgeRequestSettingsDefaultsProbe(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("sentinel", forKey: "sentinel")
        let before = defaults.dictionaryRepresentation() as NSDictionary
        defaults.reads = 0
        defaults.writes = 0
        let snapshot = try resolve(intent()).settings
        let execution = AdvancedExportSettings(snapshot: snapshot, userDefaults: defaults, persistChanges: false)
        execution.exportFormats = [.csv]
        execution.filenameFormat = "changed"
        execution.metricSelection.enabledMetrics = []
        execution.dailyNoteInjection.enabled = true
        execution.formatCustomization.frontmatterConfig.customFields = ["custom": "value"]
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(defaults.reads, 0)
        XCTAssertEqual(defaults.writes, 0)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }

    func testSavedAndProfileModesUseOnlySuppliedRevisionedOutput() throws {
        var native = try resolve(intent(folder: "saved/{year}")).settings
        native.metricSelection.enabledMetricIDs = ["hrv"]
        native.detailPolicy = .lossless
        let nativeEncoder = JSONEncoder()
        nativeEncoder.outputFormatting = [.sortedKeys]
        let nativeBefore = try nativeEncoder.encode(native)
        let saved = AgentBridgeRequestSettingsSnapshot(revision: 7, settings: native)
        let id = try AgentBridgeUUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        let profile = AgentBridgeRequestSettingsProfile(profileID: id, snapshot: saved, executionBlocked: false)
        let catalog = try makeCatalog()
        let inputs = AgentBridgeRequestSettingsInputs(catalog: catalog, savedDevice: saved, profiles: [profile])
        let fromSaved = try resolve(intent(policy: .savedDeviceSettings(expectedRevision: 7)), inputs: inputs)
        let fromProfile = try resolve(intent(policy: .profile(profileID: id, expectedRevision: 7)), inputs: inputs)
        for result in [fromSaved, fromProfile] {
            XCTAssertEqual(result.settings.folderStructure, "saved/{year}")
            XCTAssertEqual(result.settings.metricSelection.enabledMetricIDs, ["steps"])
            XCTAssertEqual(result.settings.detailPolicy, .summary)
            XCTAssertEqual(result.settingsRevision, 7)
        }
        XCTAssertEqual(fromSaved.settingsOrigin, .savedDeviceSettings)
        XCTAssertEqual(fromProfile.settingsOrigin, .profile)
        XCTAssertEqual(fromProfile.profileID, id)
        XCTAssertEqual(native.detailPolicy, .lossless)
        XCTAssertEqual(saved.settings, native)
        XCTAssertEqual(try nativeEncoder.encode(native), nativeBefore)
        expect(.revisionConflict) { try resolve(intent(policy: .savedDeviceSettings(expectedRevision: 8)), inputs: inputs) }
        expect(.revisionConflict) { try resolve(intent(policy: .profile(profileID: id, expectedRevision: 8)), inputs: inputs) }
        expect(.unsupportedCapability) { try resolve(intent(policy: .savedDeviceSettings(expectedRevision: 7))) }
        let missing = try AgentBridgeUUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        expect(.unsupportedCapability) { try resolve(intent(policy: .profile(profileID: missing, expectedRevision: 7)), inputs: inputs) }
        let blocked = AgentBridgeRequestSettingsProfile(profileID: id, snapshot: saved, executionBlocked: true)
        expect(.nativeRebindRequired) {
            try resolve(intent(policy: .profile(profileID: id, expectedRevision: 7)), inputs: .init(catalog: catalog, savedDevice: nil, profiles: [blocked]))
        }
    }

    func testUnsupportedCaptureAndPresentationAxesReject() throws {
        expect(.unsupportedMetric) { try resolve(intent(metrics: ["android.hrv_rmssd"])) }
        expect(.unsupportedMetric) { try resolve(intent(metrics: ["sleep_total"])) }
        expect(.unsupportedMetric) { try resolve(intent(metrics: [])) }
        let selection = AgentBridgeSelection(metricIDs: [try AgentBridgeID("steps")], categoryIDs: [try AgentBridgeID("activity")], sourceIDs: [try AgentBridgeID("apple_health")], providerIDs: [], allMetrics: false)
        expect(.unsupportedCapability) { try resolve(intent(selection: selection)) }
        expect(.unsupportedCapability) { try resolve(intent(detail: .selectedTimeSeries)) }
        expect(.unsupportedCapability) { try resolve(intent(archive: .appleHealthKitCanonical)) }
        expect(.unsupportedCapability) { try resolve(intent(units: .imperial)) }
        expect(.unsupportedCapability) { try resolve(intent(locale: "fr-FR")) }
        expect(.unsupportedCapability) { try resolve(intent(format: .markdown)) }
        expect(.unsupportedCapability) { try resolve(intent(writeMode: .append)) }
        expect(.unsafePath) { try resolve(intent(folder: "../outside")) }
        expect(.pathCollision) { try resolve(intent(filename: "constant")) }
        let unavailable = try makeCatalog(available: [])
        expect(.unsupportedMetric) { try resolve(intent(), inputs: .init(catalog: unavailable, savedDevice: nil, profiles: [])) }
    }

    func testEveryUnsupportedOutputCompanionRejectsInsteadOfBeingIgnored() throws {
        let base = try output()
        let mutations: [(AgentBridgeOutputSettings) -> AgentBridgeOutputSettings] = [
            { self.changing($0, frontmatter: .init(enabledFieldIDs: [try! AgentBridgeID("steps")], customFields: [], includeUnits: true, includeCaptureDiagnostics: false)) },
            { self.changing($0, frontmatter: .init(enabledFieldIDs: [], customFields: [.init(key: try! AgentBridgeID("note"), value: "synthetic")], includeUnits: true, includeCaptureDiagnostics: false)) },
            { self.changing($0, frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: false, includeCaptureDiagnostics: false)) },
            { self.changing($0, frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: true)) },
            { self.changing($0, markdown: .init(style: .tables, customTemplate: "", placeholderIDs: [])) },
            { self.changing($0, individual: .init(enabled: true, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false)) },
            { self.changing($0, daily: .init(enabled: true, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: [])) },
            { self.changing($0, packaging: .zip(filenameTemplate: "export", includeLooseFiles: false, maxUncompressedBytes: 100, maxEntries: 10)) },
            { self.changing($0, dictionary: .profileDictionary(format: .json, filenameTemplate: "dictionary")) },
        ]
        for mutate in mutations {
            expect(.unsupportedCapability) { try resolve(intent(policy: .explicit(mutate(base)))) }
        }
        var unsupportedSaved = try resolve(intent()).settings
        unsupportedSaved.includeDataDictionary = true
        expect(.unsupportedCapability) {
            try resolve(intent(policy: .savedDeviceSettings(expectedRevision: 1)), inputs: .init(catalog: makeCatalog(), savedDevice: .init(revision: 1, settings: unsupportedSaved), profiles: []))
        }
    }

    func testRelativeDatesUseGregorianCivilDaysAcrossDSTAndAllAvailableStaysLogical() throws {
        let relative = AgentBridgeDates.pastCompleteDays(days: 2, anchorDate: try AgentBridgeDate("2026-03-09"))
        let result = try resolve(intent(dates: relative))
        XCTAssertEqual(result.requestedDays.map(\.rawValue), ["2026-03-07", "2026-03-08"])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let execution = try result.makeExporterSettings()
        for day in result.requestedDays {
            let components = day.rawValue.split(separator: "-").compactMap { Int($0) }
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2])))
            XCTAssertEqual(ExportPathPlanner.aggregateRelativePath(healthSubfolder: "", settings: execution, date: date, format: .json), "2026/\(day.rawValue).json")
        }
        let all = try resolve(intent(dates: .allAvailable))
        XCTAssertEqual(all.dates, .allAvailable)
        XCTAssertTrue(all.requestedDays.isEmpty)
        XCTAssertTrue(all.predictedRelativePaths.isEmpty)
        let base = try intent()
        let utc = AgentBridgeGeneratedIntent(intentID: base.intentID, peer: base.peer, destination: base.destination, dates: base.dates, calendarTimezone: try AgentBridgeZone("UTC"), captureScope: base.captureScope, settingsPolicy: base.settingsPolicy)
        XCTAssertEqual(try resolve(utc).settings.calendarTimeZoneIdentifier, "UTC")
    }

    func testLegacySnapshotConstructionStillPersistsOnlyToSuppliedDomain() throws {
        let suite = "AgentBridgeRequestSettingsTests.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = AdvancedExportSettings(snapshot: try resolve(intent()).settings, userDefaults: defaults)
        legacy.filenameFormat = "legacy-{date}"
        XCTAssertEqual(defaults.string(forKey: "advancedExportSettings.filenameFormat"), "legacy-{date}")
    }

    func testSkippedCivilDaysAndCalendarMismatchFailWithoutNarrowing() throws {
        let base = try intent()
        let skipped = AgentBridgeGeneratedIntent(intentID: base.intentID, peer: base.peer, destination: base.destination,
                                                dates: .exact(.init(startDate: try AgentBridgeDate("2011-12-29"), endDate: try AgentBridgeDate("2011-12-31"))),
                                                calendarTimezone: try AgentBridgeZone("Pacific/Apia"), captureScope: base.captureScope, settingsPolicy: base.settingsPolicy)
        expect(.invalidRequest) { try resolve(skipped) }
        var wrongCalendar = Calendar(identifier: .buddhist)
        wrongCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        expect(.unsupportedCapability) {
            try AgentBridgeRequestSettingsResolver.resolve(base, inputs: .init(catalog: makeCatalog(), savedDevice: nil, profiles: []), clock: clock, calendar: wrongCalendar)
        }
        expect(.invalidRequest) { try resolve(intent(dates: .pastCompleteDays(days: 1, anchorDate: AgentBridgeDate("0001-01-01")))) }
    }

    func testProfileIDNeverFallsBackToNameHintAndLegacyNameOnlyStillWorks() {
        let existing = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        var nameReads = 0
        let byID: (UUID) -> Int? = { $0 == existing ? 1 : nil }
        let byName: (String) -> Int? = { _ in nameReads += 1; return 2 }
        XCTAssertEqual(AgentBridgeRequestSettingsProfileLookup.resolve(.init(profileID: existing.uuidString, name: "hint"), byID: byID, byName: byName), 1)
        XCTAssertNil(AgentBridgeRequestSettingsProfileLookup.resolve(.init(profileID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", name: "hint"), byID: byID, byName: byName))
        XCTAssertNil(AgentBridgeRequestSettingsProfileLookup.resolve(.init(profileID: "malformed", name: "hint"), byID: byID, byName: byName))
        XCTAssertEqual(nameReads, 0)
        XCTAssertEqual(AgentBridgeRequestSettingsProfileLookup.resolve(.init(profileID: "", name: "hint"), byID: byID, byName: byName), 2)
    }

    func testHRVAndReducersRetainNativeIdentities() throws {
        let result = try resolve(intent(metrics: ["heart_rate_max", "heart_rate_min", "hrv", "resting_heart_rate"]))
        XCTAssertEqual(result.selection.map(\.sourceReducer), ["discreteMax", "discreteMin", "discreteAvg", "mostRecent"])
        XCTAssertEqual(result.selection[2].sourceSelector, "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        XCTAssertEqual(result.selection[2].semanticID, "hrv")
        var registry = try HealthMdCoreRegistryAdapter.appleSnapshot()
        registry.registrySha256 = String(repeating: "0", count: 64)
        expect(.bindingChanged) {
            try AgentBridgeRequestSettingsCatalog(registry: registry, availableNativeMetricIDs: ["steps"], revision: 1)
        }
        registry = try HealthMdCoreRegistryAdapter.appleSnapshot()
        let index = try XCTUnwrap(registry.metrics.firstIndex { $0.selectionId == "steps" })
        registry.metrics[index].sourceAggregation = "invented_reducer"
        expect(.bindingChanged) {
            try AgentBridgeRequestSettingsCatalog(registry: registry, availableNativeMetricIDs: ["steps"], revision: 1)
        }
    }

    private func makeCatalog(available: Set<String> = ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"]) throws -> AgentBridgeRequestSettingsCatalog {
        try AgentBridgeRequestSettingsCatalog(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: available, revision: 3)
    }

    private func resolve(_ value: AgentBridgeGeneratedIntent, inputs: AgentBridgeRequestSettingsInputs? = nil) throws -> AgentBridgeRequestSettingsResolution {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: value.calendarTimezone.rawValue))
        return try AgentBridgeRequestSettingsResolver.resolve(value, inputs: inputs ?? .init(catalog: makeCatalog(), savedDevice: nil, profiles: []), clock: clock, calendar: calendar)
    }

    private func expect<T>(_ expected: AgentBridgeValidationError, _ body: () throws -> T) {
        XCTAssertThrowsError(try body()) { XCTAssertEqual($0 as? AgentBridgeValidationError, expected) }
    }

    private func intent(metrics: [String] = ["steps"], folder: String = "{year}", filename: String = "{date}", dates: AgentBridgeDates? = nil, selection: AgentBridgeSelection? = nil, detail: AgentBridgeDetail = .summary, archive: AgentBridgeArchive = .none, units: AgentBridgeDisplayUnits = .metric, locale: String = "en-US", format: AgentBridgeFormat = .json, writeMode: AgentBridgeWriteMode = .overwrite, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgeGeneratedIntent {
        let host = try AgentBridgeUUID("11111111-1111-4111-8111-111111111111")
        return AgentBridgeGeneratedIntent(
            intentID: try AgentBridgeUUID("22222222-2222-4222-8222-222222222222"),
            peer: .init(sourceInstallationID: try AgentBridgeUUID("33333333-3333-4333-8333-333333333333"), hostInstallationID: host, platform: .apple),
            destination: .init(bindingID: try AgentBridgeUUID("44444444-4444-4444-8444-444444444444"), identitySHA256: try AgentBridgeDigest(String(repeating: "a", count: 64)), revision: 1, hostInstallationID: host),
            dates: try dates ?? .exact(.init(startDate: AgentBridgeDate("2026-03-07"), endDate: AgentBridgeDate("2026-03-08"))),
            calendarTimezone: try AgentBridgeZone("America/Los_Angeles"),
            captureScope: try .init(selection: selection ?? .init(metricIDs: metrics.map(AgentBridgeID.init).sorted { $0.rawValue < $1.rawValue }, categoryIDs: [], sourceIDs: [AgentBridgeID("apple_health")], providerIDs: [], allMetrics: false), compatibilityDetail: detail, nativeArchive: archive),
            settingsPolicy: try policy ?? .explicit(output(folder: folder, filename: filename, units: units, locale: locale, format: format, writeMode: writeMode))
        )
    }

    private func output(folder: String = "{year}", filename: String = "{date}", units: AgentBridgeDisplayUnits = .metric, locale: String = "en-US", format: AgentBridgeFormat = .json, writeMode: AgentBridgeWriteMode = .overwrite) throws -> AgentBridgeOutputSettings {
        .init(formats: [format], outputProfile: .appleV8, subfolder: "", folderTemplate: folder, filenameTemplate: filename, writeMode: writeMode,
              presentation: .init(displayUnits: units, locale: locale, includeMetadata: true, groupByCategory: true, frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: false), markdown: .init(style: .lists, customTemplate: "", placeholderIDs: [])),
              individualEntries: .init(enabled: false, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false),
              dailyNotes: .init(enabled: false, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []), packaging: .looseFiles, dictionary: .none)
    }

    private func changing(_ base: AgentBridgeOutputSettings, frontmatter: AgentBridgeFrontmatter? = nil, markdown: AgentBridgeMarkdown? = nil, individual: AgentBridgeIndividualEntries? = nil, daily: AgentBridgeDailyNotes? = nil, packaging: AgentBridgePackaging? = nil, dictionary: AgentBridgeDictionary? = nil) -> AgentBridgeOutputSettings {
        let p = base.presentation
        return .init(formats: base.formats, outputProfile: base.outputProfile, subfolder: base.subfolder, folderTemplate: base.folderTemplate, filenameTemplate: base.filenameTemplate, writeMode: base.writeMode, presentation: .init(displayUnits: p.displayUnits, locale: p.locale, includeMetadata: p.includeMetadata, groupByCategory: p.groupByCategory, frontmatter: frontmatter ?? p.frontmatter, markdown: markdown ?? p.markdown), individualEntries: individual ?? base.individualEntries, dailyNotes: daily ?? base.dailyNotes, packaging: packaging ?? base.packaging, dictionary: dictionary ?? base.dictionary)
    }
}
