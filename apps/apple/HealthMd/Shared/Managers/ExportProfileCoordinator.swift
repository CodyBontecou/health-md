import Foundation
import Combine

/// Connects export profiles to the live export surface.
///
/// Phase 2 editing-authority model (feature decision 1): once any profile
/// exists, the active profile is the single source of truth. Switching
/// profiles loads the profile's frozen `ExportSettingsSnapshot` into the
/// shared `AdvancedExportSettings` object via `apply(snapshot:)`, and edits
/// are flushed back into the profile (debounced). The legacy defaults keys
/// remain that shared object's backing store, so every existing consumer —
/// manual export, preview, Mac jobs, Shortcuts — observes the active
/// profile's configuration without per-consumer changes.
///
/// Destinations: profile-bound folders live in `ProfileDestinationStore` as
/// security-scoped bookmarks and are adopted into `VaultManager` (which keeps
/// resolution, staleness detection, and expected-path verification). Profile
/// API endpoints are stored alongside; adopting one writes it into the shared
/// `APIExportSettings` used by the export pipeline.
@MainActor
final class ExportProfileCoordinator: ObservableObject {
    /// `nonisolated deinit` keeps teardown off the MainActor back-deployed
    /// dealloc path, which trips a libmalloc
    /// POINTER_BEING_FREED_WAS_NOT_ALLOCATED abort on the iOS 26.2 runtime
    /// when nested ObservableObject stores are released (seen on CI
    /// simulators; fixed in newer runtimes). All state is already torn down
    /// by the time deinit runs, so no isolation is required.
    nonisolated deinit {}

    /// Non-nil once a profile is active. UI uses this to label the export
    /// surface with the active profile name.
    @Published private(set) var activeProfileName: String?
    /// Mirrors the active profile's target so containers can sync their
    /// `exportTargetSelection` binding when the profile changes.
    @Published private(set) var activeTarget: ExportTargetSelection?

    let profileStore: ExportProfileStore
    let destinationStore: ProfileDestinationStore
    /// Phase 3: scheduled entries bound to profiles. Owned here so bootstrap
    /// migration (legacy schedule → Default profile entry) and profile
    /// deletion (entry cleanup) stay coupled.
    let scheduledEntryStore: ScheduledExportEntryStore

    /// The shared live export settings the Export tab edits. Read-only access
    /// for surfaces (profile editor) that seed a draft from current state.
    var liveSettings: AdvancedExportSettings { settings }

    /// The shared live API endpoint settings. Test/verification access for
    /// asserting that editor imports never touch live state.
    var apiExportSettingsForTesting: APIExportSettings { apiExportSettings }

    private let settings: AdvancedExportSettings
    private let vaultManager: VaultManager
    private let apiExportSettings: APIExportSettings
    private let now: () -> Date
    private var flushCancellable: AnyCancellable?

    /// Debounce window for flushing edits back into the active profile.
    /// Profile switches and teardown call `flushEdits()` immediately.
    private static let editFlushInterval: TimeInterval = 0.6

    init(
        profileStore: ExportProfileStore,
        destinationStore: ProfileDestinationStore,
        scheduledEntryStore: ScheduledExportEntryStore,
        settings: AdvancedExportSettings,
        vaultManager: VaultManager,
        apiExportSettings: APIExportSettings,
        initialTarget: ExportTargetSelection,
        now: @escaping () -> Date = { Date() }
    ) {
        self.profileStore = profileStore
        self.destinationStore = destinationStore
        self.scheduledEntryStore = scheduledEntryStore
        self.settings = settings
        self.vaultManager = vaultManager
        self.apiExportSettings = apiExportSettings
        self.now = now

        bootstrapIfNeeded(initialTarget: initialTarget)

        guard let activeID = profileStore.activeProfileID ?? profileStore.profiles.first?.id else {
            return
        }
        activate(profileID: activeID, adoptVault: true)
    }

    // MARK: - Bootstrap

    /// Creates the migration Default profile on first profile-mode launch,
    /// binding the user's current vault folder and API endpoint so behavior
    /// is identical to the pre-profile single-destination state.
    private func bootstrapIfNeeded(initialTarget: ExportTargetSelection) {
        guard profileStore.profiles.isEmpty else { return }

        var folderVaultID: UUID?
        if let persisted = vaultManager.persistedVaultSnapshot() {
            let destination = destinationStore.upsertVault(
                name: persisted.displayName,
                standardizedPath: persisted.standardizedPath,
                bookmarkData: persisted.bookmarkData,
                identity: persisted.identity
            )
            folderVaultID = destination.id
        }

        var apiEndpointID: UUID?
        let trimmedURL = apiExportSettings.endpointURLString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            let token = apiExportSettings.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoint = destinationStore.upsertAPIEndpoint(
                name: String(localized: "Default Endpoint", comment: "Name of the API endpoint migrated from existing settings"),
                endpointURLString: trimmedURL,
                bearerToken: token.isEmpty ? nil : token
            )
            apiEndpointID = endpoint.id
        }

        let didCreate = profileStore.migrateDefaultProfileIfNeeded(
            settings: ExportSettingsSnapshot.from(settings),
            target: initialTarget,
            folderVaultID: folderVaultID,
            apiEndpointID: apiEndpointID
        )

        // Phase 3: an enabled legacy schedule becomes the Default profile's
        // scheduled entry exactly once, then the legacy schedule is disabled
        // so exactly one runtime path (per-profile entries) owns scheduling
        // and the legacy configuration card no longer shows a duplicate.
        if didCreate, let defaultProfileID = profileStore.activeProfileID {
            let legacy = ExportSchedule.load()
            if scheduledEntryStore.migrateLegacyScheduleIfNeeded(
                legacy: legacy,
                defaultProfileID: defaultProfileID
            ) {
                var disabled = legacy
                disabled.isEnabled = false
                disabled.save()
            }
        }
    }

    // MARK: - Activation

    /// Switches the active profile: flushes outgoing edits, applies the new
    /// snapshot to the shared settings object, adopts its destination
    /// bindings, and publishes its target.
    func activate(profileID: UUID) {
        activate(profileID: profileID, adoptVault: true)
    }

    private func activate(profileID: UUID, adoptVault: Bool) {
        flushEdits()

        guard profileStore.activate(id: profileID),
              let profile = profileStore.profile(id: profileID) else { return }

        settings.apply(snapshot: profile.settings)
        activeProfileName = profile.name
        activeTarget = profile.target
        observeEdits()

        if adoptVault {
            adoptVaultDestination(for: profile)
        }
        adoptAPIEndpoint(for: profile)
    }

    private func adoptVaultDestination(for profile: ExportProfile) {
        vaultManager.adoptPersistedVault(
            destinationID: profile.folderVaultID,
            from: destinationStore
        )
    }

    private func adoptAPIEndpoint(for profile: ExportProfile) {
        guard let bindingID = profile.apiEndpointID,
              let endpoint = destinationStore.apiEndpoint(id: bindingID) else { return }
        apiExportSettings.endpointURLString = endpoint.endpointURLString
        apiExportSettings.bearerToken = destinationStore.token(for: endpoint.id) ?? ""
    }

    // MARK: - Edit flush

    private func observeEdits() {
        flushCancellable = settings.objectWillChange
            .debounce(for: .seconds(Self.editFlushInterval), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.flushEdits()
            }
    }

    /// Freezes the current shared settings into the active profile. Called
    /// debounced on edits, immediately on profile switch, and by containers
    /// before exports or teardown. The snapshot round-trip preserves renderer
    /// authority and timezone provenance.
    func flushEdits() {
        flushCancellable = nil
        guard let activeID = profileStore.activeProfileID else { return }
        profileStore.updateSettings(
            id: activeID,
            settings: ExportSettingsSnapshot.from(settings)
        )
    }

    // MARK: - Target changes

    /// Called by containers when the user changes the export target control
    /// while a profile is active.
    func userSelectedTarget(_ target: ExportTargetSelection) {
        guard let activeID = profileStore.activeProfileID else { return }
        profileStore.updateTarget(id: activeID, target: target)
        activeTarget = target
    }

    // MARK: - Destination changes

    /// Commits a standard folder-picker result into both the live vault state
    /// and the active profile destination. Binding occurs only after bookmark
    /// and trusted-selection persistence succeeds, so a denied replacement
    /// cannot displace the profile's prior valid folder.
    @discardableResult
    func selectVaultFolder(_ url: URL) -> Bool {
        guard vaultManager.setVaultFolder(url) else { return false }
        vaultFolderWasSelected()
        return true
    }

    /// Persists the live vault as the active profile's bound destination.
    /// Re-selecting a folder already stored reuses its destination row.
    func vaultFolderWasSelected() {
        guard let activeID = profileStore.activeProfileID,
              let persisted = vaultManager.persistedVaultSnapshot() else { return }

        let destination = destinationStore.upsertVault(
            name: persisted.displayName,
            standardizedPath: persisted.standardizedPath,
            bookmarkData: persisted.bookmarkData,
            identity: persisted.identity
        )
        profileStore.setFolderBinding(profileID: activeID, destinationID: destination.id)
    }

    /// Imports a freshly picked folder into the shared destination store for
    /// the profile editor — without touching the live shared vault. Returns
    /// the destination id for the editor draft's folder binding; the binding
    /// only reaches live state when saving an active profile adopts it.
    /// Re-selecting an already-saved folder reuses its destination row.
    @discardableResult
    func importFolderSelection(_ url: URL) -> UUID? {
        guard let selection = vaultManager.selectionMetadata(for: url) else { return nil }
        let destination = destinationStore.upsertVault(
            name: selection.displayName,
            standardizedPath: selection.standardizedPath,
            bookmarkData: selection.bookmarkData,
            identity: selection.identity
        )
        return destination.id
    }

    /// Imports a newly configured API endpoint into the shared destination
    /// store for the profile editor — without touching the live shared
    /// endpoint settings. The bearer token is stored in the destination
    /// store's Keychain-backed token slot. Re-entering an already-saved URL
    /// reuses its endpoint row. Returns the endpoint id for the editor
    /// draft's binding; the binding only reaches live state when saving an
    /// active profile adopts it.
    @discardableResult
    func importAPIEndpointSelection(
        name: String,
        endpointURLString: String,
        bearerToken: String?
    ) -> UUID? {
        let trimmedURL = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Upsert overwrites the row's name, so an empty form name must fall
        // back to the existing row's name (then the URL) rather than blank it.
        let existing = destinationStore.apiEndpoint(id: destinationStore.apiEndpoints.first {
            $0.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedURL) == .orderedSame
        }?.id)?.name
        let resolvedName = !trimmedName.isEmpty
            ? trimmedName
            : (existing ?? trimmedURL)
        let endpoint = destinationStore.upsertAPIEndpoint(
            name: resolvedName,
            endpointURLString: trimmedURL,
            bearerToken: bearerToken
        )
        return endpoint.id
    }

    /// Called when API endpoint settings change while a profile is active.
    /// Upserts the endpoint and binds it to the active profile.
    func apiEndpointDidChange() {
        guard let activeID = profileStore.activeProfileID else { return }

        let trimmedURL = apiExportSettings.endpointURLString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let token = apiExportSettings.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = destinationStore.upsertAPIEndpoint(
            name: trimmedURL,
            endpointURLString: trimmedURL,
            bearerToken: token.isEmpty ? nil : token
        )
        profileStore.setAPIEndpointBinding(profileID: activeID, endpointID: endpoint.id)
    }

    // MARK: - Profile management

    /// Creates a new profile from the flushed live settings with an explicit
    /// name, target, and destination binding — the creation-form path. When a
    /// folder binding is chosen, activation adopts it so the Export tab's
    /// live state matches the profile the user just configured.
    @discardableResult
    func createProfile(
        name: String,
        target: ExportTargetSelection,
        folderVaultID: UUID? = nil,
        settings newSettings: ExportSettingsSnapshot? = nil
    ) -> ExportProfile? {
        flushEdits()
        guard let source = profileStore.activeProfile else { return nil }
        let created = profileStore.add(
            name: name,
            settings: newSettings ?? ExportSettingsSnapshot.from(settings),
            target: target,
            folderVaultID: folderVaultID,
            apiEndpointID: source.apiEndpointID
        )
        activate(profileID: created.id, adoptVault: folderVaultID != nil)
        return created
    }

    /// Prefill suggestion for the creation form: "Profile", then "Profile 2",
    /// "Profile 3", … skipping names already taken (case-insensitive).
    func suggestedProfileName() -> String {
        let taken = Set(
            profileStore.profiles
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        guard !taken.contains("profile") else {
            var counter = 2
            while taken.contains("profile \(counter)") { counter += 1 }
            return "Profile \(counter)"
        }
        return "Profile"
    }

    /// Live creation-form overlap preview: names of existing profiles whose
    /// exports would write the same files as a candidate with this target,
    /// folder binding, and the flushed live settings the form will save.
    func overlapPreviewNames(target: ExportTargetSelection, folderVaultID: UUID?) -> [String] {
        overlapPreviewNames(
            target: target,
            folderVaultID: folderVaultID,
            settings: ExportSettingsSnapshot.from(settings)
        )
    }

    /// Overlap preview with an explicit settings override — the profile
    /// editor passes its draft so the warning tracks in-progress edits.
    func overlapPreviewNames(
        target: ExportTargetSelection,
        folderVaultID: UUID?,
        settings: ExportSettingsSnapshot
    ) -> [String] {
        let candidateID = UUID()
        let identities = profilePathIdentities() + [
            ExportProfileOverlapDetector.ProfilePathIdentity(
                profileID: candidateID,
                name: "",
                target: target,
                settings: settings,
                destinationRootKey: destinationRootKey(
                    target: target,
                    folderVaultID: folderVaultID
                )
            )
        ]
        return ExportProfileOverlapDetector.overlappingProfileNames(
            for: candidateID,
            among: identities
        )
    }

    /// Creates a new profile duplicating the active profile's current frozen
    /// state and destinations, then activates it.
    @discardableResult
    func addProfileDuplicatingActive() -> ExportProfile? {
        guard let source = profileStore.activeProfile else { return nil }
        let copy = profileStore.add(
            name: source.name,
            settings: ExportSettingsSnapshot.from(settings),
            target: source.target,
            folderVaultID: source.folderVaultID,
            apiEndpointID: source.apiEndpointID
        )
        activate(profileID: copy.id, adoptVault: false)
        return copy
    }

    /// Duplicates an arbitrary profile (including destination bindings)
    /// without activating the copy. The copy starts unscheduled; activating
    /// it later adopts its destinations like any other switch.
    @discardableResult
    func duplicateProfile(id: UUID) -> ExportProfile? {
        profileStore.duplicate(id: id)
    }

    /// Deletes a profile (forbidden for the last remaining profile by the
    /// store) and activates the first remaining profile. The profile's
    /// scheduled entry is removed so no orphaned automation survives the
    /// profile. Returns false when deletion was refused.
    @discardableResult
    func deleteProfile(id: UUID) -> Bool {
        guard profileStore.delete(id: id) else { return false }
        _ = scheduledEntryStore.delete(profileID: id)
        guard let next = profileStore.profiles.first else { return true }
        activate(profileID: next.id)
        return true
    }

    @discardableResult
    func renameProfile(id: UUID, to name: String) -> String? {
        let renamed = profileStore.rename(id: id, to: name)
        if id == profileStore.activeProfileID, renamed != nil {
            activeProfileName = renamed
        }
        return renamed
    }

    /// Full profile update from the editor sheet: identity, destination
    /// bindings, and the frozen settings snapshot in one save. Editing the
    /// active profile also syncs the shared live settings and adopts the new
    /// bindings so the Export tab reflects the edit immediately; editing a
    /// non-active profile never touches live state.
    @discardableResult
    func updateProfile(
        id: UUID,
        name: String,
        target: ExportTargetSelection,
        folderVaultID: UUID?,
        apiEndpointID: UUID?,
        settings newSettings: ExportSettingsSnapshot
    ) -> ExportProfile? {
        guard profileStore.profile(id: id) != nil else { return nil }

        _ = profileStore.rename(id: id, to: name)
        _ = profileStore.updateTarget(id: id, target: target)
        _ = profileStore.setFolderBinding(
            profileID: id,
            destinationID: target == .localIPhoneFolder ? folderVaultID : nil
        )
        _ = profileStore.setAPIEndpointBinding(
            profileID: id,
            endpointID: target == .apiEndpoint ? apiEndpointID : nil
        )
        _ = profileStore.updateSettings(id: id, settings: newSettings)

        guard let updated = profileStore.profile(id: id) else { return nil }
        guard id == profileStore.activeProfileID else { return updated }

        // Active-profile sync: live settings, published identity, and the
        // bound destinations must match what the editor just saved. No
        // flushEdits first — the live settings are about to be replaced by
        // the saved snapshot, so flushing would only write stale values.
        settings.apply(snapshot: newSettings)
        activeProfileName = updated.name
        activeTarget = updated.target
        if let folderVaultID {
            adoptVaultDestination(for: updated)
        }
        if let apiEndpointID {
            adoptAPIEndpoint(for: updated)
        }
        return updated
    }

    // MARK: - Output path overlap

    /// Path identities for every profile, resolving each local-folder
    /// profile's effective destination root: its bound vault when one is
    /// bound, otherwise the live shared vault (unbound profiles export
    /// through the legacy shared vault state). Connected Mac profiles share
    /// the Mac's single selected destination; API endpoints upload rather
    /// than write files and never participate.
    func profilePathIdentities() -> [ExportProfileOverlapDetector.ProfilePathIdentity] {
        let liveVaultRoot = vaultManager.vaultURL?.standardizedFileURL.path
            ?? vaultManager.pathForDisplay
        return profileStore.profiles.map { profile in
            ExportProfileOverlapDetector.ProfilePathIdentity(
                profileID: profile.id,
                name: profile.name,
                target: profile.target,
                settings: profile.settings,
                destinationRootKey: destinationRootKey(
                    target: profile.target,
                    folderVaultID: profile.folderVaultID,
                    liveVaultRoot: liveVaultRoot
                )
            )
        }
    }

    /// Names of other profiles whose exports write the same files for shared
    /// dates (same destination root and identical rendered output paths).
    /// Surfaced when a profile is created or duplicated and as a persistent
    /// detail-card warning, because profile names never appear in file paths
    /// and the collision is otherwise invisible until files are overwritten.
    func overlappingProfileNames(for profileID: UUID) -> [String] {
        ExportProfileOverlapDetector.overlappingProfileNames(
            for: profileID,
            among: profilePathIdentities()
        )
    }

    private func destinationRootKey(
        target: ExportTargetSelection,
        folderVaultID: UUID?,
        liveVaultRoot: String? = nil
    ) -> String? {
        switch target {
        case .localIPhoneFolder:
            if let vault = destinationStore.vault(id: folderVaultID) {
                return vault.standardizedPath
            }
            return liveVaultRoot
                ?? vaultManager.vaultURL?.standardizedFileURL.path
                ?? vaultManager.pathForDisplay
        case .connectedMac:
            return ExportProfileOverlapDetector.connectedMacRootKey
        case .apiEndpoint:
            return nil
        }
    }
}
