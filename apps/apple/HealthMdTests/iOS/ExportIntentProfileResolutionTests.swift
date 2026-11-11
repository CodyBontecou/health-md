#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class ExportIntentProfileResolutionTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested
    // observation state that is unsafe during test teardown on some runtimes.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ExportIntentProfileResolutionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    private func makeSettings(filenameFormat: String) -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.filenameFormat = filenameFormat
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    func testNoProfilesResolvesLegacySettings() {
        let resolution = ExportIntentRunner.resolveProfile(
            named: "Weekly Sleep",
            profileStore: ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        )
        XCTAssertEqual(resolution, .legacySettings)
    }

    func testUnnamedResolutionUsesActiveProfile() throws {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "Daily", settings: makeSettings(filenameFormat: "d-{date}"), target: .localIPhoneFolder)
        let weekly = store.add(name: "Weekly Sleep", settings: makeSnapshot(), target: .apiEndpoint)
        store.activate(id: weekly.id)

        let resolution = ExportIntentRunner.resolveProfile(named: nil, profileStore: store)

        XCTAssertEqual(resolution, .profile(weekly))
        // Whitespace-only names behave like nil (active profile).
        XCTAssertEqual(
            ExportIntentRunner.resolveProfile(named: "   ", profileStore: store),
            .profile(weekly)
        )
    }

    func testNamedResolutionIsTrimmedAndCaseInsensitive() throws {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        let weekly = store.add(name: "Weekly Sleep", settings: makeSnapshot(), target: .apiEndpoint)

        let resolution = ExportIntentRunner.resolveProfile(named: "  weekly sleep ", profileStore: store)

        XCTAssertEqual(resolution, .profile(weekly))
    }

    func testUnknownNameFailsClosed() {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder)

        let resolution = ExportIntentRunner.resolveProfile(named: "Missing", profileStore: store)

        XCTAssertEqual(resolution, .notFound("Missing"))
        // Never silently falls back to the active profile.
        XCTAssertNotEqual(resolution, .profile(store.activeProfile!))
    }

    func testProfileRunUsesProfileSnapshotAndAdoptsDestinations() async throws {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        let profile = store.add(
            name: "Sleep",
            settings: makeSettings(filenameFormat: "sleep-{date}"),
            target: .localIPhoneFolder
        )

        let recorder = ProfileRunRecorder()
        let outcome = await ExportIntentRunner.run(
            dates: [Date()],
            profileName: "sleep",
            dependencies: recorder.makeDependencies(defaults: defaults)
        )

        guard case .success = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertEqual(recorder.adopted, ["Sleep"], "run profile adopted first")
        XCTAssertTrue(recorder.restored, "active destinations restored after the run")
        XCTAssertEqual(recorder.seenFilenameFormats, ["sleep-{date}"], "frozen profile snapshot drove the export")
        XCTAssertEqual(recorder.historyProfileNames, ["Sleep"])
        _ = profile
    }

    /// Connected Mac retains its local-folder Shortcut behavior; #252 routes API profiles separately.
    func testConnectedMacProfileShortcutStillUsesLocalPipelineAndFileQuota() async throws {
        for target in [ExportTargetSelection.connectedMac] {
            let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
            let profile = store.add(
                name: "Remote-\(target.rawValue)",
                settings: makeSettings(filenameFormat: "remote-{date}"),
                target: target
            )
            let recorder = ProfileRunRecorder()
            let outcome = await ExportIntentRunner.run(
                dates: [Date()],
                profileName: profile.name,
                dependencies: recorder.makeDependencies(defaults: defaults)
            )

            guard case .success = outcome else {
                return XCTFail("expected local export success, got \(outcome)")
            }
            XCTAssertEqual(recorder.seenFilenameFormats, ["remote-{date}"])
            XCTAssertEqual(recorder.historyTargetLabels, ["iPhone: TestVault"])
            XCTAssertEqual(recorder.exportUseCount, 1, "ordinary exports are not context/quota-exempt")
            XCTAssertTrue(recorder.restored)
            let reloaded = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
            XCTAssertEqual(reloaded.profile(named: profile.name), profile, "do not mutate the saved remote profile")
        }
    }

    func testRemoteProfileShortcutDoesNotBypassFileQuota() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        let profile = store.add(name: "Mac", settings: makeSnapshot(), target: .connectedMac)
        let recorder = ProfileRunRecorder()
        var dependencies = recorder.makeDependencies(defaults: defaults)
        dependencies.canExport = { false }
        ProfileResolutionRetainer.retained.append(dependencies)

        let outcome = await ExportIntentRunner.run(
            dates: [Date()], profileName: profile.name, dependencies: dependencies
        )

        guard case .paywall = outcome else {
            return XCTFail("expected ordinary file-export quota gate, got \(outcome)")
        }
        XCTAssertTrue(recorder.seenFilenameFormats.isEmpty)
        XCTAssertTrue(recorder.historyTargetLabels.isEmpty)
        XCTAssertEqual(recorder.exportUseCount, 0)
        XCTAssertTrue(recorder.restored)
    }

    func testProfileNotFoundShortCircuitsBeforeVaultAccess() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder)

        var vaultEvents: [String] = []
        let ghostDependencies = ExportIntentRunner.Dependencies(
                refreshPurchaseStatus: {},
                canExport: { true },
                hasVaultAccess: {
                    vaultEvents.append("hasAccess")
                    return true
                },
                requiresVaultReselection: {
                    vaultEvents.append("requiresReselection")
                    return false
                },
                refreshVaultAccess: { vaultEvents.append("refresh") },
                withVaultAccess: { operation in
                    vaultEvents.append("start")
                    let result = await operation()
                    vaultEvents.append("stop")
                    return result
                },
                targetLabel: { "iPhone: TestVault" },
                makeSettings: { AdvancedExportSettings() },
                profileStore: ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: self.defaults)),
                exportDatesBackground: { _, _ in
                    XCTFail("no export should run for an unresolvable profile")
                    return ExportOrchestrator.ExportResult(
                        successCount: 0,
                        totalCount: 0,
                        failedDateDetails: []
                    )
                },
                recordResult: { _, _, _, _, _, _, _ in },
                recordExportUse: {},
                updateScheduleLastExport: {},
                pendingExportStore: InMemoryPendingExportStore(),
                exportNotificationScheduler: InspectableExportNotificationScheduler(),
                now: Date.init,
                calendar: .current
        )
        ProfileResolutionRetainer.retained.append(ghostDependencies)

        let outcome = await ExportIntentRunner.run(
            dates: [Date()],
            profileName: "Ghost Profile",
            dependencies: ghostDependencies
        )

        guard case .profileNotFound(let name) = outcome else {
            return XCTFail("expected profileNotFound, got \(outcome)")
        }
        XCTAssertEqual(name, "Ghost Profile")
        XCTAssertTrue(vaultEvents.isEmpty, "resolution fails before any vault work")
    }

    func testDialogMentionsMissingProfileName() {
        let dialog = ExportIntentRunner.dialog(for: .profileNotFound(name: "Weekly"))
        XCTAssertTrue(dialog.contains("Weekly"))
        XCTAssertTrue(dialog.contains("profile"))
    }

    func testAPIProfileRunsUploadExactDatesAndSnapshotWithoutFolderAccess() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        let profile = store.add(name: "Morning API", settings: makeSettings(filenameFormat: "api-{date}"), target: .apiEndpoint)
        let folderProfile = store.add(name: "Local", settings: makeSnapshot(), target: .localIPhoneFolder)
        store.activate(id: profile.id)
        let dates = [Date(timeIntervalSince1970: 1_790_000_000)]

        for name: String? in [nil, "  morning api  "] {
            if name != nil { store.activate(id: folderProfile.id) }
            let activeID = store.activeProfileID
            let recorder = ProfileRunRecorder()
            let dependencies = apiDependencies(recorder: recorder)
            let outcome = await ExportIntentRunner.run(dates: dates, profileName: name, dependencies: dependencies)
            guard case .success = outcome else { return XCTFail("Expected API success, got \(outcome)") }
            XCTAssertEqual(recorder.apiDates, [dates])
            XCTAssertEqual(recorder.apiDestinations, [apiDestination])
            XCTAssertEqual(recorder.seenFilenameFormats, ["api-{date}"])
            XCTAssertEqual(recorder.historyProfileNames, ["Morning API"])
            XCTAssertEqual(recorder.historyTargets, [.apiEndpoint])
            XCTAssertEqual(recorder.historyTargetLabels, [apiDestination.displayName])
            XCTAssertEqual(recorder.exportUseCount, 1)
            XCTAssertTrue(recorder.adopted.isEmpty)
            XCTAssertFalse(recorder.restored)
            XCTAssertEqual(store.activeProfileID, activeID)
        }
    }

    func testMissingAPIDestinationFailsWithoutFolderFallbackOrQuotaUse() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        let recorder = ProfileRunRecorder()
        var dependencies = apiDependencies(recorder: recorder)
        dependencies.resolveAPIDestination = { _ in nil }
        let outcome = await ExportIntentRunner.run(dates: [Date()], dependencies: dependencies)
        guard case .failure = outcome else { return XCTFail("Expected missing endpoint failure") }
        XCTAssertTrue(recorder.apiDates.isEmpty)
        XCTAssertEqual(recorder.exportUseCount, 0)
    }

    func testAPIUploadFailureDialogNamesUploadWithoutFolderFallback() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        let recorder = ProfileRunRecorder()
        var dependencies = apiDependencies(recorder: recorder)
        dependencies.exportAPIEndpoint = { dates, _, _ in
            ExportOrchestrator.ExportResult(successCount: 0, totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .apiUploadFailed) })
        }
        let outcome = await ExportIntentRunner.run(dates: [Date()], dependencies: dependencies)
        XCTAssertEqual(ExportIntentRunner.dialog(for: outcome), "Export failed: API upload failed.")
        XCTAssertEqual(recorder.historyTargets, [.apiEndpoint])
        XCTAssertEqual(recorder.exportUseCount, 0)
    }

    func testAPIQuotaGatePreventsUploadAndReportsAPITarget() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        let recorder = ProfileRunRecorder()
        var dependencies = apiDependencies(recorder: recorder)
        dependencies.canExport = { false }
        let outcome = await ExportIntentRunner.run(dates: [Date()], dependencies: dependencies)
        guard case .paywall = outcome else { return XCTFail("Expected quota gate") }
        XCTAssertTrue(recorder.apiDates.isEmpty)
        XCTAssertEqual(recorder.exportUseCount, 0)
    }

    func testAPIFailureRecordsAPIDestinationWithoutConsumingQuotaOrQueuingFolderRetry() async throws {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        let recorder = ProfileRunRecorder()
        var dependencies = apiDependencies(recorder: recorder)
        dependencies.exportAPIEndpoint = { dates, _, _ in
            ExportOrchestrator.ExportResult(successCount: 0, totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .deviceLocked) })
        }
        let outcome = await ExportIntentRunner.run(dates: [Date()], dependencies: dependencies)
        guard case .failure = outcome else { return XCTFail("Expected locked API failure") }
        XCTAssertEqual(recorder.historyTargets, [.apiEndpoint])
        XCTAssertEqual(recorder.exportUseCount, 0)
        XCTAssertTrue(try dependencies.pendingExportStore.loadAll().isEmpty)
    }

    func testPartialAPIUploadRecordsSuccessAndFailureWithoutLocalFallback() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        let recorder = ProfileRunRecorder()
        var dependencies = apiDependencies(recorder: recorder)
        dependencies.exportAPIEndpoint = { dates, _, _ in
            ExportOrchestrator.ExportResult(successCount: 1, totalCount: dates.count,
                failedDateDetails: [FailedDateDetail(date: dates[1], reason: .unknown)], formatsPerDate: 0)
        }
        let dates = [Date(timeIntervalSince1970: 1_790_000_000), Date(timeIntervalSince1970: 1_790_086_400)]
        let outcome = await ExportIntentRunner.run(dates: dates, dependencies: dependencies)
        guard case .partial(let exported, let total, _, _, _, _) = outcome else { return XCTFail("Expected partial API upload") }
        XCTAssertEqual(exported, 1)
        XCTAssertEqual(total, 2)
        XCTAssertEqual(recorder.historyTargets, [.apiEndpoint])
        XCTAssertEqual(recorder.exportUseCount, 1)
    }

    func testCancelledAPIUploadRecordsCommittedDatesAgainstAPITarget() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        let recorder = ProfileRunRecorder()
        var dependencies = apiDependencies(recorder: recorder)
        dependencies.exportAPIEndpoint = { dates, _, _ in
            ExportOrchestrator.ExportResult(successCount: 1, totalCount: dates.count,
                failedDateDetails: [], formatsPerDate: 0, wasCancelled: true, completedDates: [dates[0]])
        }
        let dates = [Date(timeIntervalSince1970: 1_790_000_000), Date(timeIntervalSince1970: 1_790_086_400)]
        let outcome = await ExportIntentRunner.run(dates: dates, dependencies: dependencies)
        guard case .cancelled = outcome else { return XCTFail("Expected cancellation") }
        XCTAssertEqual(recorder.historyTargets, [.apiEndpoint])
        XCTAssertEqual(recorder.exportUseCount, 1)
    }

    func testAPIResolverUsesBoundEndpointAndTokenAndFailsClosedForMissingOrInvalidBinding() throws {
        let destinations = ProfileDestinationStore(userDefaults: defaults, keychain: FakeKeychainStore())
        let endpoint = destinations.upsertAPIEndpoint(name: "Morning", endpointURLString: "http://morning.local/upload?secret=hidden", bearerToken: "test-token")
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        var profile = store.add(name: "API", settings: makeSnapshot(), target: .apiEndpoint)
        profile.apiEndpointID = endpoint.id
        let resolved = try XCTUnwrap(ExportIntentRunner.resolveAPIDestination(for: profile, destinationStore: destinations, legacyDestination: apiDestination))
        XCTAssertEqual(resolved.endpointURL.absoluteString, endpoint.endpointURLString)
        XCTAssertEqual(resolved.authorizationHeaderValue, "Bearer test-token")
        XCTAssertEqual(resolved.redactedEndpointDescription, "http://morning.local/upload")
        profile.apiEndpointID = UUID()
        XCTAssertNil(ExportIntentRunner.resolveAPIDestination(for: profile, destinationStore: destinations, legacyDestination: apiDestination))
        let invalid = destinations.upsertAPIEndpoint(name: "Invalid", endpointURLString: "file:///tmp/upload", bearerToken: nil)
        profile.apiEndpointID = invalid.id
        XCTAssertNil(ExportIntentRunner.resolveAPIDestination(for: profile, destinationStore: destinations, legacyDestination: apiDestination))
        profile.apiEndpointID = nil
        XCTAssertEqual(ExportIntentRunner.resolveAPIDestination(for: profile, destinationStore: destinations, legacyDestination: apiDestination), apiDestination)
    }

    private var apiDestination: APIExportDestinationSnapshot {
        APIExportDestinationSnapshot(endpointURL: URL(string: "https://morning.local/upload")!,
            authorizationHeaderValue: "Bearer fixture", displayName: "morning.local",
            redactedEndpointDescription: "https://morning.local/upload")
    }

    private func apiDependencies(recorder: ProfileRunRecorder) -> ExportIntentRunner.Dependencies {
        var dependencies = recorder.makeDependencies(defaults: defaults)
        dependencies.hasVaultAccess = { XCTFail("API export must not require a folder"); return false }
        dependencies.requiresVaultReselection = { XCTFail("API export must not inspect a folder"); return true }
        dependencies.refreshVaultAccess = { XCTFail("API export must not refresh a folder") }
        dependencies.withVaultAccess = { _ in XCTFail("API export must not acquire a folder lease"); return nil }
        dependencies.targetLabel = { XCTFail("API export must not use a folder label"); return "folder" }
        dependencies.exportDatesBackground = { _, _ in
            XCTFail("API export must not write local files")
            return ExportOrchestrator.ExportResult(successCount: 0, totalCount: 1, failedDateDetails: [])
        }
        dependencies.resolveAPIDestination = { [apiDestination] _ in apiDestination }
        dependencies.exportAPIEndpoint = { [apiDestination] dates, settings, destination in
            recorder.apiDates.append(dates)
            recorder.apiDestinations.append(destination)
            recorder.seenFilenameFormats.append(settings.filenameFormat)
            XCTAssertEqual(destination, apiDestination)
            return ExportOrchestrator.ExportResult(successCount: dates.count, totalCount: dates.count, failedDateDetails: [], formatsPerDate: 0)
        }
        return dependencies
    }

    // MARK: - Helpers

    private func makeSnapshot() -> ExportSettingsSnapshot {
        makeSettings(filenameFormat: "health-{date}")
    }
}

@MainActor
private final class ProfileRunRecorder {
    var adopted: [String?] = []
    var restored = false
    var seenFilenameFormats: [String] = []
    var historyProfileNames: [String?] = []
    var historyTargets: [ExportTargetSelection] = []
    var historyTargetLabels: [String?] = []
    var exportUseCount = 0
    var apiDates: [[Date]] = []
    var apiDestinations: [APIExportDestinationSnapshot] = []

    func makeDependencies(defaults: UserDefaults) -> ExportIntentRunner.Dependencies {
        let dependencies = ExportIntentRunner.Dependencies(
            refreshPurchaseStatus: {},
            canExport: { true },
            hasVaultAccess: { true },
            requiresVaultReselection: { false },
            refreshVaultAccess: {},
            withVaultAccess: { operation in await operation() },
            targetLabel: { "iPhone: TestVault" },
            makeSettings: { AdvancedExportSettings() },
            profileStore: ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults)),
            makeSettingsForProfile: { profile in
                AdvancedExportSettings(snapshot: profile.settings, userDefaults: defaults)
            },
            adoptProfileDestinations: { [weak self] profile in
                self?.adopted.append(profile?.name)
            },
            restoreActiveProfileDestinations: { [weak self] in
                self?.restored = true
            },
            exportDatesBackground: { [weak self] _, settings in
                self?.seenFilenameFormats.append(settings.filenameFormat)
                return ExportOrchestrator.ExportResult(
                    successCount: 1,
                    totalCount: 1,
                    failedDateDetails: []
                )
            },
            recordResult: { [weak self] _, _, _, _, label, profileName, target in
                self?.historyProfileNames.append(profileName)
                self?.historyTargets.append(target)
                self?.historyTargetLabels.append(label)
            },
            recordExportUse: { [weak self] in self?.exportUseCount += 1 },
            updateScheduleLastExport: {},
            pendingExportStore: InMemoryPendingExportStore(),
            exportNotificationScheduler: InspectableExportNotificationScheduler(),
            now: Date.init,
            calendar: .current
        )
        ProfileResolutionRetainer.retained.append(dependencies)
        return dependencies
    }
}

/// Process-lifetime retention pool for dependency graphs built by these tests.
/// Dependencies own their stores; releasing MainActor-isolated stores via the
/// back-deployed deinit path aborts on older runtimes (CI's iOS 26.2 simulator).
/// STATIC RETENTION JUSTIFICATION: retain Dependencies for the process lifetime.
enum ProfileResolutionRetainer {
    static var retained: [ExportIntentRunner.Dependencies] = []
    static var retainedStores: [ExportProfileStore] = []

    static func retain(_ store: ExportProfileStore) -> ExportProfileStore {
        retainedStores.append(store)
        return store
    }
}
#endif
