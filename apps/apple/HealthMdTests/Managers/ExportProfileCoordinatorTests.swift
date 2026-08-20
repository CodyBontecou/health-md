import XCTest
@testable import HealthMd

/// Bookmark resolver that round-trips the path-encoded bookmark bytes the
/// test fake creates, so each saved destination resolves back to its own URL
/// the way real security-scoped bookmarks do.
final class PathMappingBookmarkResolver: BookmarkResolving {
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        let name = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "fake-bookmark-", with: "")
        return (URL(fileURLWithPath: "/Users/x").appendingPathComponent(name), false)
    }

    func createBookmarkData(for url: URL) throws -> Data {
        Data("fake-bookmark-\(url.lastPathComponent)".utf8)
    }

    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}

@MainActor
final class ExportProfileCoordinatorTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; existing tests retain them
    // to avoid platform-specific deinit crashes while the process tears down.
    private static var retainedSettings: [AdvancedExportSettings] = []
    // STATIC RETENTION JUSTIFICATION: MainActor-isolated deinits take the
    // back-deployed task path on older runtimes (CI's iOS 26.2 simulator)
    // where nested store release aborts; retain for the process lifetime.
    private static var retainedInstances: [AnyObject] = []

    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var keychain: FakeKeychainStore!
    private var bookmarkResolver: PathMappingBookmarkResolver!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ExportProfileCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        keychain = FakeKeychainStore()
        bookmarkResolver = PathMappingBookmarkResolver()
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        keychain = nil
        bookmarkResolver = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSettings() -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeVaultManager() -> VaultManager {
        guard let defaults else { fatalError("test defaults missing") }
        return VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            bookmarkResolver: bookmarkResolver,
            identityProbe: FakeVaultFolderIdentityProbe()
        )
    }

    private func makeAPIExportSettings() -> APIExportSettings {
        APIExportSettings(userDefaults: defaults, keychain: keychain)
    }

    private func makeCoordinator(
        settings: AdvancedExportSettings? = nil,
        vaultManager: VaultManager? = nil,
        apiExportSettings: APIExportSettings? = nil,
        initialTarget: ExportTargetSelection = .localIPhoneFolder
    ) -> ExportProfileCoordinator {
        let resolvedSettings = settings ?? makeSettings()
        let resolvedVaultManager = vaultManager ?? makeVaultManager()
        let resolvedAPIExportSettings = apiExportSettings ?? makeAPIExportSettings()
        let coordinator = ExportProfileCoordinator(
            profileStore: ExportProfileStore(userDefaults: defaults),
            destinationStore: ProfileDestinationStore(userDefaults: defaults, keychain: keychain),
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults),
            settings: resolvedSettings,
            vaultManager: resolvedVaultManager,
            apiExportSettings: resolvedAPIExportSettings,
            initialTarget: initialTarget
        )
        Self.retainedInstances.append(coordinator)
        Self.retainedInstances.append(resolvedVaultManager)
        return coordinator
    }

    /// Saves a complete vault selection through VaultManager's real path so
    /// `persistedVaultSnapshot()` has trusted metadata to read.
    private func selectVaultFolder(in vaultManager: VaultManager, path: String) {
        vaultManager.setVaultFolder(URL(fileURLWithPath: path))
    }

    // MARK: - Bootstrap migration

    func testBootstrapCreatesDefaultProfileBoundToCurrentDestinations() throws {
        let settings = makeSettings()
        settings.filenameFormat = "daily-{date}"
        let vaultManager = makeVaultManager()
        selectVaultFolder(in: vaultManager, path: "/Users/x/Health")
        let apiSettings = makeAPIExportSettings()
        apiSettings.endpointURLString = "https://api.example.com"
        apiSettings.bearerToken = "token-1"

        let coordinator = makeCoordinator(
            settings: settings,
            vaultManager: vaultManager,
            apiExportSettings: apiSettings,
            initialTarget: .localIPhoneFolder
        )

        XCTAssertEqual(coordinator.profileStore.profiles.count, 1)
        let profile = try XCTUnwrap(coordinator.profileStore.activeProfile)
        XCTAssertTrue(profile.isMigrationDefault)
        XCTAssertEqual(profile.target, .localIPhoneFolder)
        XCTAssertEqual(profile.settings.filenameFormat, "daily-{date}")

        // Vault seeded from the persisted legacy selection.
        let vaultBinding = try XCTUnwrap(
            coordinator.destinationStore.vault(id: profile.folderVaultID)
        )
        XCTAssertEqual(vaultBinding.standardizedPath, "/Users/x/Health")

        // API endpoint seeded with its Keychain token.
        let endpointBinding = try XCTUnwrap(
            coordinator.destinationStore.apiEndpoint(id: profile.apiEndpointID)
        )
        XCTAssertEqual(endpointBinding.endpointURLString, "https://api.example.com")
        XCTAssertEqual(coordinator.destinationStore.token(for: endpointBinding.id), "token-1")

        XCTAssertEqual(coordinator.activeTarget, .localIPhoneFolder)
        XCTAssertEqual(coordinator.activeProfileName, ExportProfileStore.defaultProfileName)
    }

    func testBootstrapWithoutDestinationsLeavesBindingsNil() throws {
        let coordinator = makeCoordinator(initialTarget: .connectedMac)

        let profile = try XCTUnwrap(coordinator.profileStore.activeProfile)
        XCTAssertNil(profile.folderVaultID)
        XCTAssertNil(profile.apiEndpointID)
        XCTAssertEqual(profile.target, .connectedMac)
    }

    func testBootstrapIsSkippedWhenProfilesAlreadyExist() throws {
        let first = makeCoordinator()
        let originalProfileID = try XCTUnwrap(first.profileStore.activeProfileID)

        let second = makeCoordinator()

        XCTAssertEqual(second.profileStore.profiles.count, 1)
        XCTAssertEqual(second.profileStore.activeProfileID, originalProfileID)
    }

    // MARK: - Activation swaps settings and destinations

    func testActivateLoadsProfileSnapshotIntoSharedSettings() throws {
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings)

        settings.filenameFormat = "weekly-{date}"
        coordinator.flushEdits()

        let weekly = try XCTUnwrap(
            coordinator.addProfileDuplicatingActive(),
            "duplicate creates the second profile"
        )
        settings.filenameFormat = "sleep-{date}"
        coordinator.flushEdits()

        // Switch back to the Default profile: its frozen snapshot wins.
        let defaultID = try XCTUnwrap(
            coordinator.profileStore.profiles.first(where: { $0.isMigrationDefault })?.id
        )
        coordinator.activate(profileID: defaultID)
        XCTAssertEqual(settings.filenameFormat, "weekly-{date}")

        coordinator.activate(profileID: weekly.id)
        XCTAssertEqual(settings.filenameFormat, "sleep-{date}")
        XCTAssertEqual(coordinator.activeProfileName, weekly.name)
    }

    func testUserSelectedTargetUpdatesProfileAndPublishedTarget() throws {
        let coordinator = makeCoordinator(initialTarget: .localIPhoneFolder)
        let activeID = try XCTUnwrap(coordinator.profileStore.activeProfileID)

        coordinator.userSelectedTarget(.connectedMac)

        XCTAssertEqual(coordinator.activeTarget, .connectedMac)
        XCTAssertEqual(coordinator.profileStore.profile(id: activeID)?.target, .connectedMac)
    }

    func testVaultFolderSelectionBindsActiveProfileToDestination() throws {
        let vaultManager = makeVaultManager()
        let coordinator = makeCoordinator(vaultManager: vaultManager)
        _ = try XCTUnwrap(coordinator.addProfileDuplicatingActive())
        let activeID = try XCTUnwrap(coordinator.profileStore.activeProfileID)

        selectVaultFolder(in: vaultManager, path: "/Users/x/WeeklyVault")
        coordinator.vaultFolderWasSelected()

        let binding = try XCTUnwrap(
            coordinator.destinationStore.vault(
                id: coordinator.profileStore.profile(id: activeID)?.folderVaultID
            )
        )
        XCTAssertEqual(binding.standardizedPath, "/Users/x/WeeklyVault")

        // Selecting the same folder while another profile is active reuses
        // the destination row instead of duplicating it.
        let other = try XCTUnwrap(coordinator.addProfileDuplicatingActive())
        selectVaultFolder(in: vaultManager, path: "/Users/x/WeeklyVault")
        coordinator.vaultFolderWasSelected()
        XCTAssertEqual(coordinator.destinationStore.vaults.count, 1)
        XCTAssertEqual(
            coordinator.profileStore.profile(id: other.id)?.folderVaultID,
            binding.id
        )
    }

    func testActivateAdoptsBoundVaultAndAPIEndpoint() throws {
        let vaultManager = makeVaultManager()
        selectVaultFolder(in: vaultManager, path: "/Users/x/Health")
        let apiSettings = makeAPIExportSettings()
        apiSettings.endpointURLString = "https://first.example.com"
        apiSettings.bearerToken = "first-token"
        let coordinator = makeCoordinator(
            vaultManager: vaultManager,
            apiExportSettings: apiSettings
        )
        let defaultID = try XCTUnwrap(
            coordinator.profileStore.profiles.first(where: { $0.isMigrationDefault })?.id
        )

        // Create the second profile first, then rebind its destinations while
        // it is active; the Default profile's bindings must stay untouched.
        let second = try XCTUnwrap(coordinator.addProfileDuplicatingActive())
        selectVaultFolder(in: vaultManager, path: "/Users/x/SecondVault")
        coordinator.vaultFolderWasSelected()
        apiSettings.endpointURLString = "https://second.example.com"
        apiSettings.bearerToken = "second-token"
        coordinator.apiEndpointDidChange()

        // Reactivating each profile adopts its own destinations.
        coordinator.activate(profileID: defaultID)
        XCTAssertEqual(
            vaultManager.vaultURL?.standardizedFileURL.path,
            "/Users/x/Health"
        )
        XCTAssertEqual(apiSettings.endpointURLString, "https://first.example.com")
        XCTAssertEqual(apiSettings.bearerToken, "first-token")

        coordinator.activate(profileID: second.id)
        XCTAssertEqual(
            vaultManager.vaultURL?.standardizedFileURL.path,
            "/Users/x/SecondVault"
        )
        XCTAssertEqual(apiSettings.endpointURLString, "https://second.example.com")
        XCTAssertEqual(apiSettings.bearerToken, "second-token")
    }

    // MARK: - Profile management

    func testDeleteProfileRefusesLastAndActivatesRemaining() throws {
        let coordinator = makeCoordinator()
        let firstID = try XCTUnwrap(coordinator.profileStore.activeProfileID)

        XCTAssertFalse(coordinator.deleteProfile(id: firstID), "last profile cannot be deleted")

        let second = try XCTUnwrap(coordinator.addProfileDuplicatingActive())
        XCTAssertTrue(coordinator.deleteProfile(id: second.id))
        XCTAssertEqual(coordinator.profileStore.activeProfileID, firstID)
        XCTAssertEqual(coordinator.profileStore.profiles.count, 1)
    }

    func testRenameUpdatesPublishedActiveName() throws {
        let coordinator = makeCoordinator()
        let activeID = try XCTUnwrap(coordinator.profileStore.activeProfileID)

        XCTAssertEqual(coordinator.renameProfile(id: activeID, to: "  Weekly Sleep  "), "Weekly Sleep")
        XCTAssertEqual(coordinator.activeProfileName, "Weekly Sleep")
        XCTAssertEqual(coordinator.profileStore.profile(id: activeID)?.name, "Weekly Sleep")
    }

    func testFlushEditsFreezesSharedSettingsIntoActiveProfile() throws {
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings)
        let activeID = try XCTUnwrap(coordinator.profileStore.activeProfileID)

        settings.filenameFormat = "flushed-{date}"
        coordinator.flushEdits()

        XCTAssertEqual(
            coordinator.profileStore.profile(id: activeID)?.settings.filenameFormat,
            "flushed-{date}"
        )
    }

    // MARK: - Creation form

    func testCreateProfileUsesChosenNameTargetAndFolderBinding() throws {
        let vaultManager = makeVaultManager()
        let coordinator = makeCoordinator(vaultManager: vaultManager)
        selectVaultFolder(in: vaultManager, path: "/Users/x/FirstVault")
        coordinator.vaultFolderWasSelected()

        let destination = try XCTUnwrap(coordinator.destinationStore.vaults.first)
        let created = try XCTUnwrap(
            coordinator.createProfile(
                name: "  Archive  ",
                target: .localIPhoneFolder,
                folderVaultID: destination.id
            )
        )

        XCTAssertEqual(created.name, "Archive")
        XCTAssertEqual(created.target, .localIPhoneFolder)
        XCTAssertEqual(created.folderVaultID, destination.id)
        XCTAssertEqual(coordinator.profileStore.activeProfileID, created.id, "creation activates the new profile")
        XCTAssertEqual(
            vaultManager.pathForDisplay,
            "/Users/x/FirstVault",
            "an explicit binding is adopted on activation so the live vault matches the created profile"
        )
    }

    func testSuggestedProfileNameSkipsTakenNames() throws {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.suggestedProfileName(), "Profile")

        _ = coordinator.renameProfile(
            id: coordinator.profileStore.activeProfileID!,
            to: "Profile"
        )
        XCTAssertEqual(coordinator.suggestedProfileName(), "Profile 2")

        _ = coordinator.createProfile(name: "Profile 2", target: .apiEndpoint)
        XCTAssertEqual(coordinator.suggestedProfileName(), "Profile 3")
    }

    func testOverlapPreviewNamesTrackChosenDestination() throws {
        let vaultManager = makeVaultManager()
        let coordinator = makeCoordinator(vaultManager: vaultManager)
        selectVaultFolder(in: vaultManager, path: "/Users/x/SharedVault")
        coordinator.vaultFolderWasSelected()
        let defaultName = try XCTUnwrap(coordinator.profileStore.profiles.first?.name)

        // Same live vault, duplicated templates: overlap with the Default profile.
        XCTAssertEqual(
            coordinator.overlapPreviewNames(target: .localIPhoneFolder, folderVaultID: nil),
            [defaultName]
        )

        // A different destination clears the overlap.
        let other = coordinator.destinationStore.upsertVault(
            name: "Archive",
            standardizedPath: "/Users/x/ArchiveVault",
            bookmarkData: Data("fake-bookmark-ArchiveVault".utf8)
        )
        XCTAssertTrue(
            coordinator.overlapPreviewNames(target: .localIPhoneFolder, folderVaultID: other.id).isEmpty
        )

        // API endpoints upload rather than write files: never overlap.
        XCTAssertTrue(
            coordinator.overlapPreviewNames(target: .apiEndpoint, folderVaultID: nil).isEmpty
        )
    }

    // MARK: - Profile editor

    func testUpdateProfileEditsNonActiveProfileWithoutTouchingLiveState() throws {
        let settings = makeSettings()
        let coordinator = makeCoordinator(settings: settings)
        let other = try XCTUnwrap(coordinator.addProfileDuplicatingActive())
        let defaultID = try XCTUnwrap(
            coordinator.profileStore.profiles.first(where: { $0.id != other.id })?.id
        )
        // Re-activate Default so `other` is NOT active, then establish the
        // live value the debounced edit flush would capture. Mutating live
        // settings while `other` is active would (correctly) flush into the
        // active profile and race this assertion.
        coordinator.activate(profileID: defaultID)
        settings.filenameFormat = "live-{date}"
        coordinator.flushEdits()

        var edited = coordinator.profileStore.profile(id: other.id)!.settings
        edited.filenameFormat = "edited-{date}"
        edited.exportFormats = [.json]
        let updated = try XCTUnwrap(
            coordinator.updateProfile(
                id: other.id,
                name: "  Renamed  ",
                target: .apiEndpoint,
                folderVaultID: nil,
                apiEndpointID: nil,
                settings: edited
            )
        )

        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertEqual(updated.target, .apiEndpoint)
        XCTAssertEqual(updated.settings.exportFormats, [.json])
        XCTAssertEqual(updated.settings.filenameFormat, "edited-{date}")
        XCTAssertNil(updated.folderVaultID, "non-local targets clear the folder binding")
        XCTAssertEqual(
            coordinator.profileStore.activeProfileID,
            defaultID,
            "editing never changes activation"
        )
        XCTAssertEqual(
            settings.filenameFormat,
            "live-{date}",
            "editing a non-active profile must not touch live settings"
        )
        XCTAssertEqual(
            coordinator.profileStore.profile(id: defaultID)?.settings.filenameFormat,
            "live-{date}",
            "the debounced flush captured the live value on the active profile"
        )
    }

    func testUpdateProfileOnActiveProfileSyncsLiveState() throws {
        let settings = makeSettings()
        let vaultManager = makeVaultManager()
        let coordinator = makeCoordinator(settings: settings, vaultManager: vaultManager)
        let activeID = try XCTUnwrap(coordinator.profileStore.activeProfileID)
        selectVaultFolder(in: vaultManager, path: "/Users/x/FirstVault")
        coordinator.vaultFolderWasSelected()

        let archiveVault = coordinator.destinationStore.upsertVault(
            name: "Archive",
            standardizedPath: "/Users/x/ArchiveVault",
            bookmarkData: Data("fake-bookmark-ArchiveVault".utf8)
        )

        var edited = coordinator.profileStore.profile(id: activeID)!.settings
        edited.filenameFormat = "synced-{date}"
        edited.exportFormats = [.csv]
        _ = try XCTUnwrap(
            coordinator.updateProfile(
                id: activeID,
                name: "Renamed Active",
                target: .localIPhoneFolder,
                folderVaultID: archiveVault.id,
                apiEndpointID: nil,
                settings: edited
            )
        )

        XCTAssertEqual(coordinator.activeProfileName, "Renamed Active")
        XCTAssertEqual(settings.filenameFormat, "synced-{date}", "live settings adopt the saved snapshot")
        XCTAssertEqual(settings.exportFormats, [.csv])
        XCTAssertEqual(
            vaultManager.pathForDisplay,
            "/Users/x/ArchiveVault",
            "the edited folder binding is adopted into live vault state"
        )
    }

    func testImportFolderSelectionUpsertsDestinationWithoutTouchingLiveVault() throws {
        let vaultManager = makeVaultManager()
        let coordinator = makeCoordinator(vaultManager: vaultManager)
        XCTAssertNil(vaultManager.pathForDisplay, "precondition: no live vault selected")

        let imported = try XCTUnwrap(
            coordinator.importFolderSelection(URL(fileURLWithPath: "/Users/x/EditorVault"))
        )

        let destination = try XCTUnwrap(
            coordinator.destinationStore.vaults.first { $0.id == imported }
        )
        XCTAssertEqual(destination.standardizedPath, "/Users/x/EditorVault")
        XCTAssertEqual(destination.name, "EditorVault")
        XCTAssertNil(
            vaultManager.pathForDisplay,
            "importing a folder must not change the live shared vault"
        )
        XCTAssertNil(
            coordinator.profileStore.activeProfile?.folderVaultID,
            "importing does not bind anything until the editor saves"
        )

        // Re-selecting the same folder reuses the destination row.
        let again = try XCTUnwrap(
            coordinator.importFolderSelection(URL(fileURLWithPath: "/Users/x/EditorVault"))
        )
        XCTAssertEqual(again, imported)
        XCTAssertEqual(
            coordinator.destinationStore.vaults.filter { $0.standardizedPath == "/Users/x/EditorVault" }.count,
            1
        )
    }

    func testImportAPIEndpointSelectionUpsertsEndpointAndTokenWithoutTouchingLiveSettings() throws {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.apiExportSettingsForTesting.endpointURLString, "", "precondition: no live endpoint")

        let imported = try XCTUnwrap(
            coordinator.importAPIEndpointSelection(
                name: "  Nightly Sink  ",
                endpointURLString: "  https://example.com/hook  ",
                bearerToken: " secret-token "
            )
        )

        let endpoint = try XCTUnwrap(
            coordinator.destinationStore.apiEndpoints.first { $0.id == imported }
        )
        XCTAssertEqual(endpoint.name, "Nightly Sink")
        XCTAssertEqual(endpoint.endpointURLString, "https://example.com/hook")
        XCTAssertEqual(
            coordinator.destinationStore.token(for: imported),
            "secret-token",
            "the token lands in the destination store's keychain slot, trimmed"
        )
        XCTAssertEqual(
            coordinator.apiExportSettingsForTesting.endpointURLString,
            "",
            "importing an endpoint must not change the live shared endpoint"
        )

        // Empty URL is rejected; a nil token leaves the stored value intact
        // when re-importing the same URL, and an empty name falls back to URL.
        XCTAssertNil(coordinator.importAPIEndpointSelection(name: "", endpointURLString: "   ", bearerToken: nil))
        let reused = try XCTUnwrap(
            coordinator.importAPIEndpointSelection(
                name: "",
                endpointURLString: "https://EXAMPLE.com/hook",
                bearerToken: nil
            )
        )
        XCTAssertEqual(reused, imported, "same URL (case-insensitive) reuses the endpoint row")
        XCTAssertEqual(coordinator.destinationStore.apiEndpoints.count, 1)
        XCTAssertEqual(
            coordinator.destinationStore.token(for: reused),
            "secret-token",
            "re-import without a token keeps the stored token"
        )
        XCTAssertEqual(
            coordinator.destinationStore.apiEndpoints.first?.name,
            "Nightly Sink",
            "re-import with an empty name keeps the existing name"
        )
    }

    func testOverlapPreviewUsesEditorDraftSettings() throws {
        let vaultManager = makeVaultManager()
        let coordinator = makeCoordinator(vaultManager: vaultManager)
        selectVaultFolder(in: vaultManager, path: "/Users/x/SharedVault")
        coordinator.vaultFolderWasSelected()
        let defaultName = try XCTUnwrap(coordinator.profileStore.profiles.first?.name)

        var draft = ExportSettingsSnapshot.from(coordinator.liveSettings)
        XCTAssertEqual(
            coordinator.overlapPreviewNames(
                target: .localIPhoneFolder,
                folderVaultID: nil,
                settings: draft
            ),
            [defaultName],
            "identical templates overlap"
        )

        draft.filenameFormat = "unique-{date}"
        XCTAssertTrue(
            coordinator.overlapPreviewNames(
                target: .localIPhoneFolder,
                folderVaultID: nil,
                settings: draft
            ).isEmpty,
            "a diverging draft template clears the overlap"
        )
    }
}
