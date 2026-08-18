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
                bookmarkData: persisted.bookmarkData
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
        guard let bindingID = profile.folderVaultID,
              let destination = destinationStore.vault(id: bindingID) else { return }
        vaultManager.adoptPersistedVault(
            bookmarkData: destination.bookmarkData,
            standardizedPath: destination.standardizedPath,
            displayName: destination.name
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

    /// Called after the user selects a new folder through the standard folder
    /// picker (`VaultManager.setVaultFolder`). Persists the newly saved vault
    /// as a profile-bound destination. Re-selecting a folder already stored
    /// reuses its destination row.
    func vaultFolderWasSelected() {
        guard let activeID = profileStore.activeProfileID,
              let persisted = vaultManager.persistedVaultSnapshot() else { return }

        let destination = destinationStore.upsertVault(
            name: persisted.displayName,
            standardizedPath: persisted.standardizedPath,
            bookmarkData: persisted.bookmarkData
        )
        profileStore.setFolderBinding(profileID: activeID, destinationID: destination.id)
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
}
