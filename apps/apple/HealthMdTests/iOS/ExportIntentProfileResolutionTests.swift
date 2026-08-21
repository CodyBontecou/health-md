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

    func testProfileNotFoundShortCircuitsBeforeVaultAccess() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "Daily", settings: makeSnapshot(), target: .localIPhoneFolder)

        var vaultEvents: [String] = []
        let ghostDependencies = ExportIntentRunner.Dependencies(
                refreshPurchaseStatus: {},
                canExport: { true },
                trackExportBlockedByQuota: {},
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
                recordResult: { _, _, _, _, _, _ in },
                recordExportUse: {},
                trackExportSucceeded: { _ in },
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

    func testDriveProfileReturnsTypedForegroundRequirementWithoutVaultFallback() async {
        let store = ProfileResolutionRetainer.retain(ExportProfileStore(userDefaults: defaults))
        store.add(name: "Drive", settings: makeSnapshot(), target: .googleDrive)
        let recorder = ProfileRunRecorder()

        let outcome = await ExportIntentRunner.run(
            dates: [Date()],
            profileName: "Drive",
            dependencies: recorder.makeDependencies(defaults: defaults)
        )

        guard case .foregroundRequired(let destination) = outcome else {
            return XCTFail("expected foregroundRequired, got \(outcome)")
        }
        XCTAssertEqual(destination, .googleDrive)
        XCTAssertTrue(recorder.seenFilenameFormats.isEmpty, "Drive intent must not invoke local exporter")
        let dialog = ExportIntentRunner.dialog(for: outcome)
        XCTAssertTrue(dialog.contains("foreground"))
        XCTAssertTrue(dialog.contains("no local-vault fallback"))
        XCTAssertThrowsError(try ExportIntentRunner.requireNoForegroundTransition(outcome)) { error in
            XCTAssertEqual(
                error as? ExportIntentForegroundRequiredError,
                ExportIntentForegroundRequiredError(destination: .googleDrive)
            )
        }
    }

    func testDialogMentionsMissingProfileName() {
        let dialog = ExportIntentRunner.dialog(for: .profileNotFound(name: "Weekly"))
        XCTAssertTrue(dialog.contains("Weekly"))
        XCTAssertTrue(dialog.contains("profile"))
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

    func makeDependencies(defaults: UserDefaults) -> ExportIntentRunner.Dependencies {
        let dependencies = ExportIntentRunner.Dependencies(
            refreshPurchaseStatus: {},
            canExport: { true },
            trackExportBlockedByQuota: {},
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
            recordResult: { [weak self] _, _, _, _, _, profileName in
                self?.historyProfileNames.append(profileName)
            },
            recordExportUse: {},
            trackExportSucceeded: { _ in },
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
