import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class SharedSetupV1Tests: XCTestCase {
    func testCanonicalCrossLanguageFixtureDecodesAndMapsExactSettings() throws {
        let data = try Data(contentsOf: fixtureURL())

        let document = try SharedSetupCodec.decode(data)
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())

        XCTAssertEqual(document.schema, SharedSetupV1.schemaName)
        XCTAssertEqual(document.profile.apiEndpoint?.validatedURLString, "https://setup.invalid:8443/synthetic/health")
        XCTAssertEqual(
            preview.supportedMetricSelectionIDs,
            Set(["active_energy", "blood_pressure_systolic", "heart_rate_avg", "hrv", "sleep_core", "steps"])
        )
        XCTAssertFalse(preview.hasInvalidItems)
        XCTAssertTrue(preview.installCustomTemplate)
        XCTAssertEqual(SharedSetupMapper.exactAppleSchedule(document)?.isEnabled, false)
    }

    func testAndroidOriginFixtureMapsExactSharedFieldsAndLeavesDistinctMetricUnsupported() throws {
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL("android-shared-setup-v1.json")))
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())
        let current = AdvancedExportSettings(userDefaults: isolatedDefaults())
        current.organizeFormatsIntoFolders = true
        current.generateWeeklyRollups = true
        current.dailyNoteInjection.dailyNotesOnly = true
        let candidate = SharedSetupMapper.portableSnapshot(from: preview, preservingTemplateFrom: current)

        XCTAssertEqual(document.createdBy.platform, .android)
        XCTAssertNil(document.platformExtensions.apple)
        XCTAssertTrue(candidate.organizeFormatsIntoFolders)
        XCTAssertTrue(candidate.generateWeeklyRollups)
        XCTAssertTrue(candidate.dailyNotes.dailyNotesOnly)
        XCTAssertEqual(candidate.metricSelectionIDs, Set(["steps"]))
        XCTAssertTrue(preview.items.contains { $0.id == "metric.android.hrv_rmssd" && $0.status == .requiresAction })
        XCTAssertTrue(candidate.dailyNotes.createIfMissing)
        XCTAssertEqual(candidate.individualTracking.filenameTemplate, "{metric}-{date}-{time}")
        let schedule = try XCTUnwrap(SharedSetupMapper.exactAppleSchedule(document))
        XCTAssertEqual(schedule.preferredHour, 6)

        try current.applySharedSetupBatch(candidate)
        let reexported = try SharedSetupMapper.exportDocument(
            settings: current,
            schedule: schedule,
            appVersion: "synthetic-round-trip",
            preservedAndroidExtension: document.platformExtensions.android,
            registry: fixtureRegistry()
        )
        let roundTrip = try SharedSetupCodec.decode(SharedSetupCodec.encode(reexported))
        XCTAssertNotNil(roundTrip.platformExtensions.apple)
        XCTAssertEqual(roundTrip.platformExtensions.android, document.platformExtensions.android)
    }

    func testAndroidReexportRestoresPreservedExactAppleScheduleExtension() throws {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL("android-shared-setup-v1.json"))) as? [String: Any]
        )
        var extensions = try XCTUnwrap(root["platform_extensions"] as? [String: Any])
        extensions["apple"] = [
            "extension_version": 1,
            "export": [
                "organize_formats_into_folders": false,
                "archive_files": false,
                "include_data_dictionary": false,
                "summary_only": false,
                "rollups": []
            ],
            "daily_notes": ["only": false],
            "schedule": [
                "frequency": "daily",
                "custom_unit": "days",
                "weekday": 6,
                "today_refresh_requested": true,
                "today_refresh_interval_hours": 12,
                "desired_target": "api_endpoint"
            ]
        ]
        root["platform_extensions"] = extensions

        let document = try SharedSetupCodec.decode(try jsonData(root))
        let schedule = try XCTUnwrap(SharedSetupMapper.exactAppleSchedule(document))

        XCTAssertEqual(schedule.weekday, 6)
        XCTAssertTrue(schedule.todayRefreshEnabled)
        XCTAssertEqual(schedule.todayRefreshIntervalHours, 12)
    }

    func testBoundedUnknownFieldsAreIgnoredButFutureVersionSecretsAndUnsafePathsAreRejected() throws {
        let root = try fixtureJSONObject()
        var unknown = root
        unknown["future_optional"] = ["bounded": true]
        XCTAssertNoThrow(try SharedSetupCodec.decode(try jsonData(unknown)))

        var future = root
        future["schema_version"] = 2
        XCTAssertThrowsError(try SharedSetupCodec.decode(try jsonData(future)))

        var sensitive = root
        sensitive["future_optional"] = "Bearer synthetic-secret"
        XCTAssertThrowsError(try SharedSetupCodec.decode(try jsonData(sensitive)))

        var categoryAuthority = root
        var categoryProfile = try XCTUnwrap(categoryAuthority["profile"] as? [String: Any])
        var categoryMetrics = try XCTUnwrap(categoryProfile["metrics"] as? [String: Any])
        categoryMetrics["enabled_categories"] = ["activity"]
        categoryProfile["metrics"] = categoryMetrics
        categoryAuthority["profile"] = categoryProfile
        XCTAssertThrowsError(try SharedSetupCodec.decode(try jsonData(categoryAuthority)))

        var unsafe = root
        var profile = try XCTUnwrap(unsafe["profile"] as? [String: Any])
        var export = try XCTUnwrap(profile["export"] as? [String: Any])
        export["folder_template"] = "../escape"
        profile["export"] = export
        unsafe["profile"] = profile
        XCTAssertThrowsError(try SharedSetupCodec.decode(try jsonData(unsafe)))

        var unicodeHost = root
        var unicodeProfile = try XCTUnwrap(unicodeHost["profile"] as? [String: Any])
        var endpoint = try XCTUnwrap(unicodeProfile["api_endpoint"] as? [String: Any])
        endpoint["host"] = "éxample.invalid"
        unicodeProfile["api_endpoint"] = endpoint
        unicodeHost["profile"] = unicodeProfile
        XCTAssertThrowsError(try SharedSetupCodec.decode(try jsonData(unicodeHost)))
        XCTAssertThrowsError(try SharedSetupCodec.decode(Data(repeating: 0, count: SharedSetupV1.maximumEncodedBytes + 1)))
    }

    func testRegistryDriftUsesCurrentLocalMappingsAndPinnedUnavailableRowsAreVerified() throws {
        var drifted = try fixtureJSONObject()
        var registryIdentity = try XCTUnwrap(drifted["metric_registry"] as? [String: Any])
        registryIdentity["registry_sha256"] = String(repeating: "0", count: 64)
        drifted["metric_registry"] = registryIdentity
        var aliases = try XCTUnwrap(drifted["metric_aliases"] as? [[String: Any]])
        let activeIndex = try XCTUnwrap(aliases.firstIndex { $0["semantic_id"] as? String == "active_energy" })
        aliases[activeIndex]["android_selection_id"] = "historical_active_energy"
        drifted["metric_aliases"] = aliases
        let driftedDocument = try SharedSetupCodec.decode(try jsonData(drifted))
        let driftedPreview = SharedSetupMapper.preview(driftedDocument, registry: fixtureRegistry())
        XCTAssertTrue(driftedPreview.supportedMetricSelectionIDs.contains("active_energy"))
        XCTAssertFalse(driftedPreview.hasInvalidItems)

        var pinned = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL("android-shared-setup-v1.json"))) as? [String: Any]
        )
        var pinnedAliases = try XCTUnwrap(pinned["metric_aliases"] as? [[String: Any]])
        let hrvIndex = try XCTUnwrap(pinnedAliases.firstIndex { $0["semantic_id"] as? String == "android.hrv_rmssd" })
        pinnedAliases[hrvIndex]["android_selection_id"] = "forged_hrv"
        pinned["metric_aliases"] = pinnedAliases
        let pinnedPreview = SharedSetupMapper.preview(
            try SharedSetupCodec.decode(try jsonData(pinned)),
            registry: fixtureRegistry()
        )
        XCTAssertTrue(pinnedPreview.hasInvalidItems)
    }

    func testDuplicateMetricAliasesAreRejectedWithoutPreviewCrash() throws {
        var root = try fixtureJSONObject()
        var aliases = try XCTUnwrap(root["metric_aliases"] as? [[String: Any]])
        aliases.append(try XCTUnwrap(aliases.first))
        root["metric_aliases"] = aliases

        XCTAssertThrowsError(try SharedSetupCodec.decode(try jsonData(root)))
    }

    func testUnsupportedScheduleIsNeverApproximated() throws {
        var root = try fixtureJSONObject()
        var profile = try XCTUnwrap(root["profile"] as? [String: Any])
        var schedule = try XCTUnwrap(profile["schedule"] as? [String: Any])
        schedule["lookback_days"] = ExportSchedule.maximumLookbackDays + 1
        profile["schedule"] = schedule
        root["profile"] = profile
        let document = try SharedSetupCodec.decode(try jsonData(root))

        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())

        XCTAssertNil(SharedSetupMapper.exactAppleSchedule(document))
        XCTAssertTrue(preview.items.contains {
            $0.id == "schedule" && $0.status == .requiresAction && $0.detail.contains("cannot be represented exactly")
        })
    }

    func testMalformedTemplateRemainsReviewableAndKeepsCurrentTemplate() throws {
        var root = try fixtureJSONObject()
        var profile = try XCTUnwrap(root["profile"] as? [String: Any])
        var presentation = try XCTUnwrap(profile["presentation"] as? [String: Any])
        var markdown = try XCTUnwrap(presentation["markdown"] as? [String: Any])
        markdown["custom_text"] = "{{#sleep}}not closed"
        presentation["markdown"] = markdown
        profile["presentation"] = presentation
        root["profile"] = profile

        let document = try SharedSetupCodec.decode(try jsonData(root))
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())
        let current = AdvancedExportSettings(userDefaults: isolatedDefaults())
        let snapshot = SharedSetupMapper.portableSnapshot(from: preview, preservingTemplateFrom: current)

        XCTAssertFalse(preview.installCustomTemplate)
        XCTAssertEqual(snapshot.markdownTemplate, current.formatCustomization.markdownTemplate)
        XCTAssertTrue(preview.items.contains { $0.id == "template" && $0.status == .requiresAction })
    }

    func testAppleWriterDoesNotFabricateAndroidExtensionDefaults() throws {
        let document = try SharedSetupMapper.exportDocument(
            settings: AdvancedExportSettings(userDefaults: isolatedDefaults()),
            schedule: ExportSchedule(),
            appVersion: "synthetic-test",
            registry: fixtureRegistry()
        )

        XCTAssertNotNil(document.platformExtensions.apple)
        XCTAssertNil(document.platformExtensions.android)
        XCTAssertNoThrow(try SharedSetupCodec.encode(document))
    }

    func testWriterRejectsSensitiveMaterialHiddenInCustomContent() throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.formatCustomization.frontmatterConfig.customFields = [
            "family_note": "Bearer synthetic-secret"
        ]
        let document = try SharedSetupMapper.exportDocument(
            settings: settings,
            schedule: ExportSchedule(),
            appVersion: "synthetic-test",
            registry: fixtureRegistry()
        )

        XCTAssertThrowsError(try SharedSetupCodec.encode(document))
    }

    func testExportStripsEndpointQueryAndCredentialsAndPreservesAndroidExtension() throws {
        let defaults = isolatedDefaults()
        let keychain = FakeKeychainStore()
        let api = APIExportSettings(userDefaults: defaults, keychain: keychain)
        api.endpointURLString = "https://synthetic-user:synthetic-pass@family.invalid:9443/health?tenant=private#fragment"
        api.bearerToken = "Bearer must-not-export"
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let preserved = SharedSetupV1.AndroidExtension(
            extensionVersion: 1,
            export: .init(
                compatibilityProfile: .frozenV4,
                includeLegacyAliases: true,
                includeAndroidNativeFields: false,
                subfolder: "portable/android",
                folderOrganization: .byYearMonth
            )
        )

        let document = try SharedSetupMapper.exportDocument(
            settings: settings,
            schedule: ExportSchedule(),
            apiExportSettings: api,
            appVersion: "synthetic-test",
            preservedAndroidExtension: preserved,
            registry: fixtureRegistry()
        )
        let encoded = try SharedSetupCodec.encode(document)
        let decoded = try SharedSetupCodec.decode(encoded)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(decoded.profile.apiEndpoint?.host, "family.invalid")
        XCTAssertEqual(decoded.profile.apiEndpoint?.path, "/health")
        XCTAssertEqual(decoded.profile.apiEndpoint?.queryOmitted, true)
        XCTAssertEqual(decoded.platformExtensions.android, preserved)
        XCTAssertFalse(text.contains("tenant=private"))
        XCTAssertFalse(text.contains("synthetic-user"))
        XCTAssertFalse(text.contains("synthetic-pass"))
        XCTAssertFalse(text.contains("fragment"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("must-not-export"))
    }

    func testPreviewPerformsZeroWrites() throws {
        let defaults = isolatedDefaults()
        _ = AdvancedExportSettings(userDefaults: defaults)
        let before = defaults.dictionaryRepresentation()
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))

        _ = SharedSetupMapper.preview(document, registry: fixtureRegistry())

        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
    }

    func testPortableSettingsBatchPersistsEveryNativeKey() throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())
        let candidate = SharedSetupMapper.portableSnapshot(from: preview, preservingTemplateFrom: settings)

        try settings.applySharedSetupBatch(candidate, verificationOverride: { true })
        let reloaded = AdvancedExportSettings(userDefaults: defaults)

        XCTAssertEqual(SharedSetupPortableSnapshot.capture(settings), candidate)
        XCTAssertEqual(SharedSetupPortableSnapshot.capture(reloaded), candidate)
    }

    func testTransactionalApplyAndUndoRestoreSettingsScheduleAndUnsupportedExtension() throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.filenameFormat = "before-{date}"
        let previousSettings = SharedSetupPortableSnapshot.capture(settings)
        let previousSchedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 7,
            preferredMinute: 15,
            weekday: 3,
            target: .localIPhoneFolder,
            lookbackDays: 4
        )
        let scheduling = FakeSharedSetupScheduler(schedule: previousSchedule)
        let api = APIExportSettings(userDefaults: defaults, keychain: FakeKeychainStore())
        let transaction = SharedSetupTransaction(
            settings: settings,
            apiExportSettings: api,
            schedulingManager: scheduling,
            userDefaults: defaults
        )
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())

        _ = try transaction.apply(preview)

        XCTAssertEqual(settings.filenameFormat, "health-{date}")
        XCTAssertFalse(scheduling.schedule.isEnabled)
        XCTAssertEqual(transaction.pendingEndpointHint, "https://setup.invalid:8443/synthetic/health")
        XCTAssertEqual(transaction.preservedAndroidExtension, document.platformExtensions.android)
        XCTAssertTrue(transaction.canUndo)

        _ = try transaction.undo()

        XCTAssertEqual(SharedSetupPortableSnapshot.capture(settings), previousSettings)
        XCTAssertEqual(scheduling.schedule, previousSchedule)
        XCTAssertNil(transaction.pendingEndpointHint)
        XCTAssertNil(transaction.preservedAndroidExtension)
        XCTAssertFalse(transaction.canUndo)
    }

    func testEndpointConfirmationAndUndoClearNewCredentialBeforeRestoringOldEndpoint() throws {
        let defaults = isolatedDefaults()
        let keychain = FakeKeychainStore()
        let api = APIExportSettings(userDefaults: defaults, keychain: keychain)
        api.endpointURLString = "https://old.invalid/path"
        api.bearerToken = "old-secret"
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let previousSettings = SharedSetupPortableSnapshot.capture(settings)
        let scheduling = FakeSharedSetupScheduler(schedule: ExportSchedule())
        let transaction = SharedSetupTransaction(
            settings: settings,
            apiExportSettings: api,
            schedulingManager: scheduling,
            userDefaults: defaults
        )
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())
        _ = try transaction.apply(preview)

        try transaction.confirmPendingEndpoint(authorization: "new-local-secret")

        XCTAssertEqual(api.endpointURLString, "https://setup.invalid:8443/synthetic/health")
        XCTAssertEqual(api.authorizationHeaderValue, "Bearer new-local-secret")
        XCTAssertNotEqual(api.authorizationHeaderValue, "Bearer old-secret")
        XCTAssertNil(transaction.pendingEndpointHint)
        XCTAssertFalse(scheduling.schedule.isEnabled)

        let undo = try transaction.undo()

        XCTAssertEqual(SharedSetupPortableSnapshot.capture(settings), previousSettings)
        XCTAssertEqual(api.endpointURLString, "https://old.invalid/path")
        XCTAssertEqual(api.bearerToken, "")
        XCTAssertEqual(try api.sharedSetupPersistedBearerToken(), "")
        XCTAssertNil(transaction.pendingEndpointHint)
        XCTAssertFalse(transaction.canUndo)
        XCTAssertTrue(undo.attentionItems.contains { $0.contains("credentials were cleared") })
    }

    func testEndpointConfirmationRollsBackAndRetainsHintWhenKeychainWriteFails() throws {
        let defaults = isolatedDefaults()
        let keychain = FakeKeychainStore()
        let api = APIExportSettings(userDefaults: defaults, keychain: keychain)
        api.endpointURLString = "https://old.invalid/path"
        api.bearerToken = "old-secret"
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let scheduling = FakeSharedSetupScheduler(schedule: ExportSchedule())
        let transaction = SharedSetupTransaction(
            settings: settings,
            apiExportSettings: api,
            schedulingManager: scheduling,
            userDefaults: defaults
        )
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))
        _ = try transaction.apply(SharedSetupMapper.preview(document, registry: fixtureRegistry()))
        keychain.nextWriteStringError = NSError(domain: "SharedSetupV1Tests", code: 1)

        XCTAssertThrowsError(try transaction.confirmPendingEndpoint(authorization: "new-local-secret"))

        XCTAssertEqual(api.endpointURLString, "https://old.invalid/path")
        XCTAssertEqual(api.bearerToken, "old-secret")
        XCTAssertEqual(try api.sharedSetupPersistedBearerToken(), "old-secret")
        XCTAssertEqual(transaction.pendingEndpointHint, "https://setup.invalid:8443/synthetic/health")
    }

    func testUndoCredentialCleanupFailureLeavesConfirmedEndpointAndUndoRetryable() throws {
        let defaults = isolatedDefaults()
        let keychain = FakeKeychainStore()
        let api = APIExportSettings(userDefaults: defaults, keychain: keychain)
        api.endpointURLString = "https://old.invalid/path"
        api.bearerToken = "old-secret"
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let scheduling = FakeSharedSetupScheduler(schedule: ExportSchedule())
        let transaction = SharedSetupTransaction(
            settings: settings,
            apiExportSettings: api,
            schedulingManager: scheduling,
            userDefaults: defaults
        )
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))
        _ = try transaction.apply(SharedSetupMapper.preview(document, registry: fixtureRegistry()))
        try transaction.confirmPendingEndpoint(authorization: "new-local-secret")
        let importedSettings = SharedSetupPortableSnapshot.capture(settings)
        keychain.nextRemoveError = NSError(domain: "SharedSetupV1Tests", code: 2)

        XCTAssertThrowsError(try transaction.undo())

        XCTAssertEqual(SharedSetupPortableSnapshot.capture(settings), importedSettings)
        XCTAssertEqual(api.endpointURLString, "https://setup.invalid:8443/synthetic/health")
        XCTAssertEqual(api.bearerToken, "new-local-secret")
        XCTAssertEqual(try api.sharedSetupPersistedBearerToken(), "new-local-secret")
        XCTAssertTrue(transaction.canUndo)
    }

    func testFailedApplyLeavesConfigurationUnchanged() throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.filenameFormat = "unchanged-{date}"
        let previousSettings = SharedSetupPortableSnapshot.capture(settings)
        let previousSchedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 9, preferredMinute: 10)
        let scheduling = FakeSharedSetupScheduler(schedule: previousSchedule)
        let transaction = SharedSetupTransaction(
            settings: settings,
            apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: FakeKeychainStore()),
            schedulingManager: scheduling,
            userDefaults: defaults,
            verificationOverride: { false }
        )
        let document = try SharedSetupCodec.decode(Data(contentsOf: fixtureURL()))
        let preview = SharedSetupMapper.preview(document, registry: fixtureRegistry())

        XCTAssertThrowsError(try transaction.apply(preview))
        XCTAssertEqual(SharedSetupPortableSnapshot.capture(settings), previousSettings)
        XCTAssertEqual(scheduling.schedule, previousSchedule)
        XCTAssertNil(transaction.pendingEndpointHint)
        XCTAssertFalse(transaction.canUndo)
    }

    #if os(iOS)
    func testCoordinatorUsesInjectedLiveSettingsAndHandlesColdAndWarmDocuments() async throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let api = APIExportSettings(userDefaults: defaults, keychain: FakeKeychainStore())
        let scheduling = SchedulingManager(
            initialSchedule: ExportSchedule(),
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false
        )
        let coordinator = SharedSetupCoordinator(
            settings: settings,
            apiExportSettings: api,
            schedulingManager: scheduling,
            userDefaults: defaults,
            registry: fixtureRegistry()
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedSetupV1Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("Family.healthmdconfig")
        try Data(contentsOf: fixtureURL()).write(to: documentURL)

        XCTAssertTrue(coordinator.settings === settings)
        XCTAssertTrue(coordinator.handleOpenURL(documentURL, cold: true))
        XCTAssertEqual(coordinator.lastRouteSource, .coldOpen)
        try await waitForPreview(coordinator)
        XCTAssertTrue(coordinator.isFlowPresented)

        coordinator.finish()
        XCTAssertTrue(coordinator.handleOpenURL(documentURL, cold: false))
        XCTAssertEqual(coordinator.lastRouteSource, .warmOpen)
        try await waitForPreview(coordinator)
        XCTAssertFalse(coordinator.handleOpenURL(directory.appendingPathComponent("not-a-setup.json"), cold: false))
    }

    func testCoordinatorNewestExternalDocumentWinsAndFinishCancelsPendingRead() async throws {
        let defaults = isolatedDefaults()
        let coordinator = SharedSetupCoordinator(
            settings: AdvancedExportSettings(userDefaults: defaults),
            apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: FakeKeychainStore()),
            schedulingManager: SchedulingManager(
                initialSchedule: ExportSchedule(),
                persistScheduleChanges: false,
                systemSideEffectsEnabled: false
            ),
            userDefaults: defaults,
            registry: fixtureRegistry()
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedSetupNewestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("First.healthmdconfig")
        let secondURL = directory.appendingPathComponent("Second.healthmdconfig")
        try Data(contentsOf: fixtureURL()).write(to: firstURL)
        var second = try fixtureJSONObject()
        var profile = try XCTUnwrap(second["profile"] as? [String: Any])
        var export = try XCTUnwrap(profile["export"] as? [String: Any])
        export["filename_template"] = "second-{date}"
        profile["export"] = export
        second["profile"] = profile
        try jsonData(second).write(to: secondURL)

        coordinator.handleImportedURL(firstURL, source: .coldOpen)
        coordinator.handleImportedURL(secondURL, source: .warmOpen)
        try await waitForPreview(coordinator)
        XCTAssertEqual(coordinator.preview?.document.profile.export.filenameTemplate, "second-{date}")
        XCTAssertEqual(coordinator.lastRouteSource, .warmOpen)

        coordinator.finish()
        coordinator.handleImportedURL(firstURL, source: .warmOpen)
        coordinator.finish()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(coordinator.preview)
        XCTAssertFalse(coordinator.isFlowPresented)
    }

    func testCoordinatorCancellationPropagatesToExternalReader() async throws {
        let defaults = isolatedDefaults()
        let readStarted = expectation(description: "external read started")
        let readCancelled = expectation(description: "external read cancelled")
        let coordinator = SharedSetupCoordinator(
            settings: AdvancedExportSettings(userDefaults: defaults),
            apiExportSettings: APIExportSettings(
                userDefaults: defaults,
                keychain: FakeKeychainStore()
            ),
            schedulingManager: SchedulingManager(
                initialSchedule: ExportSchedule(),
                persistScheduleChanges: false,
                systemSideEffectsEnabled: false
            ),
            userDefaults: defaults,
            registry: fixtureRegistry(),
            externalFileReader: { _ in
                readStarted.fulfill()
                return try await withTaskCancellationHandler {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    return Data()
                } onCancel: {
                    readCancelled.fulfill()
                }
            }
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cancelled.healthmdconfig")
        coordinator.handleImportedURL(url, source: .warmOpen)
        await fulfillment(of: [readStarted], timeout: 2)

        coordinator.finish()
        await fulfillment(of: [readCancelled], timeout: 2)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(coordinator.preview)
        XCTAssertFalse(coordinator.isFlowPresented)
    }

    func testCoordinatorAnnouncesApplyEndpointConfirmationAndUndo() throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let api = APIExportSettings(userDefaults: defaults, keychain: FakeKeychainStore())
        let scheduling = SchedulingManager(
            initialSchedule: ExportSchedule(),
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false
        )
        var announcements: [String] = []
        let coordinator = SharedSetupCoordinator(
            settings: settings,
            apiExportSettings: api,
            schedulingManager: scheduling,
            userDefaults: defaults,
            registry: fixtureRegistry(),
            accessibilityAnnouncer: { announcements.append($0) }
        )

        try coordinator.load(Data(contentsOf: fixtureURL()))
        coordinator.apply()
        coordinator.confirmPendingEndpoint(authorization: "Bearer local-test")
        coordinator.undo()

        XCTAssertEqual(
            announcements,
            [
                "Shared Setup applied. Review items requiring attention, then finish setup.",
                "API endpoint confirmed",
                "Shared Setup import undone"
            ]
        )
    }

    func testShareArtifactIsRemovedAfterSystemShare() throws {
        let defaults = isolatedDefaults()
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let scheduling = SchedulingManager(
            initialSchedule: ExportSchedule(),
            persistScheduleChanges: false,
            systemSideEffectsEnabled: false
        )
        let coordinator = SharedSetupCoordinator(
            settings: settings,
            apiExportSettings: APIExportSettings(userDefaults: defaults, keychain: FakeKeychainStore()),
            schedulingManager: scheduling,
            userDefaults: defaults,
            registry: fixtureRegistry()
        )

        let url = try coordinator.makeShareArtifact(appVersion: "synthetic-test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        coordinator.removeShareArtifact(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    #endif

    private final class FakeSharedSetupScheduler: SharedSetupScheduling {
        var schedule: ExportSchedule
        private(set) var cancellationCount = 0

        init(schedule: ExportSchedule) {
            self.schedule = schedule
        }

        func cancelSharedSetupAutomation() {
            cancellationCount += 1
        }
    }

    private func fixtureRegistry() -> SharedSetupMetricRegistry {
        SharedSetupMetricRegistry(
            version: 1,
            sha256: "1cc9aaf41cb92a2e903487756cf561f0ff44b9518f3ef66d1a45a997f770248d",
            semanticToApple: [
                "active_energy": "active_energy",
                "blood_pressure_systolic": "blood_pressure_systolic",
                "heart_rate_avg": "heart_rate_avg",
                "hrv": "hrv",
                "sleep_core": "sleep_core",
                "steps": "steps"
            ],
            semanticToAndroid: [
                "active_energy": "active_calories",
                "blood_pressure_systolic": "bp_systolic",
                "heart_rate_avg": "avg_hr",
                "sleep_core": "sleep_light",
                "steps": "steps",
                "android.hrv_rmssd": "hrv"
            ],
            equivalence: [
                "active_energy": .mappedAlias,
                "blood_pressure_systolic": .mappedAlias,
                "heart_rate_avg": .mappedAlias,
                "hrv": .platformExactOrUnavailable,
                "sleep_core": .mappedAlias,
                "steps": .platformExactOrUnavailable,
                "android.hrv_rmssd": .platformDistinct
            ]
        )
    }

    #if os(iOS)
    private func waitForPreview(_ coordinator: SharedSetupCoordinator) async throws {
        for _ in 0..<100 {
            if coordinator.preview != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the bounded external document read")
    }
    #endif

    private func fixtureURL(_ name: String = "shared-setup-v1.json") throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("packages/contracts/shared-setup/v1/fixtures/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate canonical shared-setup fixture")
    }

    private func fixtureJSONObject() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL())) as? [String: Any]
        )
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SharedSetupV1Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
