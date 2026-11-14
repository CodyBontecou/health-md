import Foundation
import Combine

/// A named, user-managed export configuration.
///
/// An export profile freezes every output-affecting setting as an
/// `ExportSettingsSnapshot` (the same immutable representation used for Mac
/// export jobs and durable scheduled work) and binds it to an export target.
/// Profiles are additive to the legacy single-settings model: while the
/// profile store is empty, the app continues to read live
/// `AdvancedExportSettings` exactly as before.
///
/// Profiles deliberately exclude HealthKit authorization, quota/account state,
/// scheduling, and runtime capture authority (sleep ownership, provider grants,
/// and device timezone). Identical profile settings and accepted capture context
/// preserve output behavior; a new occurrence resolves its own source authority
/// without changing an already-pending job or the stored profile template.
struct ExportProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var settings: ExportSettingsSnapshot
    var target: ExportTargetSelection
    /// Bound folder destination in `ProfileDestinationStore` when
    /// `target == .localIPhoneFolder`. Nil means the profile uses whatever
    /// folder the legacy single-vault state has loaded (the migration default
    /// binds the existing vault instead of leaving this nil, so behavior is
    /// preserved).
    var folderVaultID: UUID?
    /// Bound API endpoint in `ProfileDestinationStore` when
    /// `target == .apiEndpoint`. Nil keeps the current single-endpoint state.
    var apiEndpointID: UUID?
    /// Local non-secret Drive destination ID. Google authority never enters profile JSON.
    var googleDriveDestinationID: UUID?
    var createdAt: Date
    var updatedAt: Date
    /// Device-local configuration identity for exact revision pins; never portable authority.
    /// Timestamps are presentation metadata and cannot substitute for this counter.
    var configurationRevision: Int
    /// True only for the profile synthesized from legacy live settings during
    /// first-run migration. It marks the row users expect to keep editing as
    /// their "main" configuration and is not part of export output.
    var isMigrationDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        settings: ExportSettingsSnapshot,
        target: ExportTargetSelection,
        folderVaultID: UUID? = nil,
        apiEndpointID: UUID? = nil,
        googleDriveDestinationID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isMigrationDefault: Bool = false,
        configurationRevision: Int = 1
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.target = target
        self.folderVaultID = folderVaultID
        self.apiEndpointID = apiEndpointID
        self.googleDriveDestinationID = googleDriveDestinationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.configurationRevision = configurationRevision
        self.isMigrationDefault = isMigrationDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, settings, target, folderVaultID, apiEndpointID
        case googleDriveDestinationID, createdAt, updatedAt, isMigrationDefault, configurationRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(ExportSettingsSnapshot.self, forKey: .settings)
        target = try container.decode(ExportTargetSelection.self, forKey: .target)
        folderVaultID = try container.decodeIfPresent(UUID.self, forKey: .folderVaultID)
        apiEndpointID = try container.decodeIfPresent(UUID.self, forKey: .apiEndpointID)
        googleDriveDestinationID = try container.decodeIfPresent(UUID.self, forKey: .googleDriveDestinationID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isMigrationDefault = try container.decodeIfPresent(Bool.self, forKey: .isMigrationDefault) ?? false
        // Missing only is a legacy native row. Null/malformed values are never a new revision.
        configurationRevision = container.contains(.configurationRevision)
            ? try container.decode(Int.self, forKey: .configurationRevision) : 1
    }
}

/// Current non-secret output configuration, independent of the active profile and destinations.
struct ExportProfileConfigurationSnapshot {
    let revision: Int64
    let settings: ExportSettingsSnapshot
    let executionBlocked: Bool
}

/// Observable, UserDefaults-backed store for the ordered export profile list.
///
/// Persistence remains compatible with the shipped JSON array while decoding each record
/// independently. Unknown or corrupt records are retained opaquely, so they cannot erase or
/// redirect unrelated runnable profiles when the list is saved again. Unreadable authority
/// blocks legacy fallback rather than redirecting an export to live settings.
///
/// Use from the main thread, matching `AdvancedExportSettings`.
final class ExportProfileStore: ObservableObject {
    /// `nonisolated deinit` keeps teardown off the MainActor back-deployed
    /// dealloc path, which trips a libmalloc
    /// POINTER_BEING_FREED_WAS_NOT_ALLOCATED abort on the iOS 26.2 runtime
    /// when nested ObservableObject stores are released (seen on CI
    /// simulators; fixed in newer runtimes). All state is already torn down
    /// by the time deinit runs, so no isolation is required.
    nonisolated deinit {}

    @Published private(set) var profiles: [ExportProfile]
    @Published private(set) var activeProfileID: UUID?
    /// Unknown or individually corrupt records retained verbatim so one future profile kind cannot
    /// erase unrelated runnable profiles when a Drive-capable build reads and later saves the list.
    @Published private(set) var unknownProfileRecordCount: Int

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private var opaqueProfileRecords: [Data]
    private var persistenceUnavailable = false

    private enum Key {
        static let list = ExportProfilePersistence.legacyListKey
        static let activeProfileID = ExportProfilePersistence.legacyActiveIDKey
        static let listV2 = ExportProfilePersistence.envelopeKey
        static let activeProfileIDV2 = ExportProfilePersistence.activeIDKey
    }

    static let defaultProfileName = String(localized: "Default", comment: "Name of the export profile migrated from existing settings")

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userDefaults = userDefaults
        self.now = now

        let hasV2 = ExportProfilePersistence.hasEnvelope(in: userDefaults)
        let key = hasV2 ? Key.listV2 : Key.list
        let data = userDefaults.data(forKey: key)
        let decoded = data.flatMap { ExportProfilePersistence.decode($0, envelope: hasV2) }
        if let decoded {
            profiles = decoded.profiles
            opaqueProfileRecords = decoded.opaque
        } else {
            profiles = []
            opaqueProfileRecords = []
            persistenceUnavailable = userDefaults.object(forKey: key) != nil
        }
        unknownProfileRecordCount = opaqueProfileRecords.count + (persistenceUnavailable ? 1 : 0)

        if let idString = userDefaults.string(forKey: hasV2 ? Key.activeProfileIDV2 : Key.activeProfileID),
           let id = UUID(uuidString: idString),
           decodedContainsProfile(withID: id, in: profiles) {
            activeProfileID = id
        } else {
            activeProfileID = nil
        }
    }

    /// Re-reads persisted state so instances owned by different subsystems
    /// (UI coordinator, SchedulingManager, CLI paths) observe each other's
    /// mutations. Safe on the main thread, matching every existing call site.
    /// Detail views call this during rendering: publishing equal values would
    /// invalidate the same observed body again and prevent the UI from idling.
    /// Returns false when present authoritative storage is unreadable.
    @discardableResult
    private func reloadFromDefaults() -> Bool {
        let hasV2 = ExportProfilePersistence.hasEnvelope(in: userDefaults)
        let key = hasV2 ? Key.listV2 : Key.list
        let decoded = userDefaults.data(forKey: key).flatMap {
            ExportProfilePersistence.decode($0, envelope: hasV2)
        }
        let loadedProfiles = decoded?.profiles ?? []
        let loadedOpaque = decoded?.opaque ?? []
        persistenceUnavailable = userDefaults.object(forKey: key) != nil && decoded == nil

        if loadedProfiles != profiles {
            profiles = loadedProfiles
        }
        if loadedOpaque != opaqueProfileRecords {
            opaqueProfileRecords = loadedOpaque
        }
        let unknownCount = loadedOpaque.count + (persistenceUnavailable ? 1 : 0)
        if unknownProfileRecordCount != unknownCount {
            unknownProfileRecordCount = unknownCount
        }
        let activeKey = hasV2 ? Key.activeProfileIDV2 : Key.activeProfileID
        let persistedID = userDefaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        let loadedActiveID = persistedID.flatMap {
            decodedContainsProfile(withID: $0, in: loadedProfiles) ? $0 : nil
        }
        if activeProfileID != loadedActiveID {
            activeProfileID = loadedActiveID
        }
        return !persistenceUnavailable
    }

    // MARK: - Derived state

    /// True when at least one profile exists. Callers without profile support
    /// keep the legacy single-settings behavior while this is false.
    var hasProfiles: Bool { !profiles.isEmpty || unknownProfileRecordCount > 0 }

    /// The profile used by manual exports, or nil in legacy mode (no profiles,
    /// or the persisted active id dangles after external data loss).
    var activeProfile: ExportProfile? {
        reloadFromDefaults()
        return profile(id: activeProfileID)
    }

    func profile(id: UUID?) -> ExportProfile? {
        reloadFromDefaults()
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    /// Case-insensitive, whitespace-trimmed name lookup used by automation
    /// surfaces that reference profiles by display name.
    func profile(named name: String) -> ExportProfile? {
        reloadFromDefaults()
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return profiles.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    /// Reads the exact persisted row without updating caches, migrating, or consulting live settings.
    /// Missing, duplicate, malformed or changed revision pins have no fallback configuration.
    func readConfigurationProfile(id: UUID, expectedRevision: Int64) -> ExportProfileConfigurationSnapshot? {
        let hasV2 = ExportProfilePersistence.hasEnvelope(in: userDefaults)
        // Any unreadable root or opaque (corrupt, duplicate or future) record fails closed.
        guard (1...Int64(Int32.max)).contains(expectedRevision),
              let data = userDefaults.data(forKey: hasV2 ? Key.listV2 : Key.list),
              let decoded = ExportProfilePersistence.decode(data, envelope: hasV2),
              decoded.opaque.isEmpty else { return nil }
        let matches = decoded.profiles.filter { $0.id == id }
        guard matches.count == 1, let profile = matches.first,
              Int64(profile.configurationRevision) == expectedRevision else { return nil }
        return .init(
            revision: expectedRevision,
            settings: profile.settings,
            executionBlocked: SharedSetupV2ExecutionGate(userDefaults: userDefaults).isExecutionBlocked(profileID: id)
        )
    }

    // MARK: - Migration

    /// Creates the initial "Default" profile from current live settings on
    /// first use, optionally binding it to existing folder/API destinations.
    /// Returns true when a profile was created; subsequent calls are no-ops
    /// so callers can invoke this on every launch.
    @discardableResult
    func migrateDefaultProfileIfNeeded(
        settings: ExportSettingsSnapshot,
        target: ExportTargetSelection,
        folderVaultID: UUID? = nil,
        apiEndpointID: UUID? = nil,
        googleDriveDestinationID: UUID? = nil
    ) -> Bool {
        guard prepareForListMutation(allowAbsent: true), profiles.isEmpty,
              opaqueProfileRecords.isEmpty, !persistenceUnavailable else { return false }

        let profile = ExportProfile(
            name: uniquifiedName(Self.defaultProfileName),
            settings: settings,
            target: target,
            folderVaultID: folderVaultID,
            apiEndpointID: apiEndpointID,
            googleDriveDestinationID: googleDriveDestinationID,
            createdAt: now(),
            updatedAt: now(),
            isMigrationDefault: true
        )
        profiles = [profile]
        activeProfileID = profile.id
        persist()
        return true
    }

    // MARK: - CRUD

    @discardableResult
    func add(
        name: String,
        settings: ExportSettingsSnapshot,
        target: ExportTargetSelection,
        folderVaultID: UUID? = nil,
        apiEndpointID: UUID? = nil,
        googleDriveDestinationID: UUID? = nil
    ) -> ExportProfile? {
        guard prepareForListMutation(allowAbsent: true) else { return nil }
        let profile = ExportProfile(
            name: uniquifiedName(name),
            settings: settings,
            target: target,
            folderVaultID: folderVaultID,
            apiEndpointID: apiEndpointID,
            googleDriveDestinationID: googleDriveDestinationID,
            createdAt: now(),
            updatedAt: now()
        )
        profiles.append(profile)
        if activeProfileID == nil {
            activeProfileID = profile.id
        }
        persist()
        return profile
    }

    /// Replaces the frozen settings snapshot and touches `updatedAt`.
    /// Returns false when the id is unknown.
    @discardableResult
    func updateSettings(id: UUID, settings: ExportSettingsSnapshot) -> Bool {
        guard let edit = nextConfigurationRevision(for: id) else { return false }
        let index = edit.index
        profiles[index].settings = settings
        profiles[index].updatedAt = now()
        profiles[index].configurationRevision = edit.revision
        persist()
        return true
    }

    /// Binds a profile to a folder destination in `ProfileDestinationStore`.
    /// Returns false when the profile id is unknown.
    @discardableResult
    func setFolderBinding(profileID: UUID, destinationID: UUID?) -> Bool {
        guard reloadFromDefaults(), let current = profiles.first(where: { $0.id == profileID }) else { return false }
        guard current.folderVaultID != destinationID else { return true }
        guard let edit = nextConfigurationRevision(for: profileID) else { return false }
        let index = edit.index
        profiles[index].folderVaultID = destinationID
        profiles[index].updatedAt = now()
        profiles[index].configurationRevision = edit.revision
        persist()
        return true
    }

    /// Binds a profile to an API endpoint in `ProfileDestinationStore`.
    /// Returns false when the profile id is unknown.
    @discardableResult
    func setAPIEndpointBinding(profileID: UUID, endpointID: UUID?) -> Bool {
        guard reloadFromDefaults(), let current = profiles.first(where: { $0.id == profileID }) else { return false }
        guard current.apiEndpointID != endpointID else { return true }
        guard let edit = nextConfigurationRevision(for: profileID) else { return false }
        let index = edit.index
        profiles[index].apiEndpointID = endpointID
        profiles[index].updatedAt = now()
        profiles[index].configurationRevision = edit.revision
        persist()
        return true
    }

    /// Binds a profile to a local non-secret Google Drive destination record.
    @discardableResult
    func setGoogleDriveBinding(profileID: UUID, destinationID: UUID?) -> Bool {
        guard reloadFromDefaults(), let current = profiles.first(where: { $0.id == profileID }) else { return false }
        guard current.googleDriveDestinationID != destinationID else { return true }
        guard let edit = nextConfigurationRevision(for: profileID) else { return false }
        let index = edit.index
        profiles[index].googleDriveDestinationID = destinationID
        profiles[index].updatedAt = now()
        profiles[index].configurationRevision = edit.revision
        persist()
        return true
    }

    /// Replaces the export target binding and touches `updatedAt`.
    /// Returns false when the id is unknown.
    @discardableResult
    func updateTarget(id: UUID, target: ExportTargetSelection) -> Bool {
        guard let edit = nextConfigurationRevision(for: id) else { return false }
        let index = edit.index
        profiles[index].target = target
        profiles[index].updatedAt = now()
        profiles[index].configurationRevision = edit.revision
        persist()
        return true
    }

    /// Renames a profile, trimming whitespace and uniquifying against the
    /// remaining profiles. Returns the stored name, or nil when the id is
    /// unknown or the trimmed name is empty.
    @discardableResult
    func rename(id: UUID, to rawName: String) -> String? {
        guard let edit = nextConfigurationRevision(for: id) else { return nil }
        let index = edit.index
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let others = profiles.filter { $0.id != id }
        let unique = Self.uniquified(trimmed, against: others.map(\.name))
        profiles[index].name = unique
        profiles[index].updatedAt = now()
        profiles[index].configurationRevision = edit.revision
        persist()
        return unique
    }

    /// Duplicates a profile under a fresh id with a name like "Weekly 2",
    /// including destination bindings. Returns nil when the source id is
    /// unknown.
    @discardableResult
    func duplicate(id: UUID) -> ExportProfile? {
        guard !SharedSetupV2ExecutionGate(userDefaults: userDefaults).isExecutionBlocked(profileID: id),
              let source = profile(id: id) else { return nil }
        return add(
            name: source.name,
            settings: source.settings,
            target: source.target,
            folderVaultID: source.folderVaultID,
            apiEndpointID: source.apiEndpointID,
            googleDriveDestinationID: source.googleDriveDestinationID
        )
    }

    /// Deletes a profile. Deleting the last remaining profile is forbidden:
    /// once profiles exist, the app must keep at least one so manual export
    /// and scheduling always resolve a concrete configuration instead of
    /// silently falling back to stale legacy settings. Deleting the active
    /// profile activates the first remaining profile. Returns true when a
    /// profile was deleted; false for unknown ids or the final profile.
    @discardableResult
    func delete(id: UUID) -> Bool {
        guard prepareForListMutation(), profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)

        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        persist()
        return true
    }

    /// Selects the profile manual exports use. Returns false for unknown ids
    /// or while in legacy mode.
    @discardableResult
    func activate(id: UUID) -> Bool {
        guard prepareForListMutation(), profiles.contains(where: { $0.id == id }) else { return false }
        // Activation selects an existing immutable output snapshot; rewriting the whole list
        // needlessly re-encodes set order and must not become a settings edit on startup.
        guard activeProfileID != id else { return true }
        activeProfileID = id
        let activeKey = ExportProfilePersistence.hasEnvelope(in: userDefaults)
            ? Key.activeProfileIDV2 : Key.activeProfileID
        userDefaults.set(id.uuidString, forKey: activeKey)
        return true
    }

    // MARK: - Naming

    private func uniquifiedName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? String(localized: "Profile", comment: "Fallback export profile name") : trimmed
        return Self.uniquified(base, against: profiles.map(\.name))
    }

    /// Appends " 2", " 3", … until the name is unique (case-insensitive).
    private static func uniquified(_ base: String, against existingNames: [String]) -> String {
        let existing = Set(
            existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        guard existing.contains(base.lowercased()) else { return base }

        var counter = 2
        while existing.contains("\(base) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    /// A genuinely empty initial store is creatable; unreadable or externally removed state
    /// is never replaced from cached rows. Rejection precedes observable state changes.
    private func prepareForListMutation(allowAbsent: Bool = false) -> Bool {
        let key = ExportProfilePersistence.hasEnvelope(in: userDefaults) ? Key.listV2 : Key.list
        if userDefaults.object(forKey: key) == nil {
            return allowAbsent && profiles.isEmpty
        }
        return reloadFromDefaults()
    }

    /// Invalid or exhausted counters fail before mutation, never wrap or reuse an old pin.
    private func nextConfigurationRevision(for id: UUID) -> (index: Int, revision: Int)? {
        guard reloadFromDefaults(),
              let index = profiles.firstIndex(where: { $0.id == id }),
              (1..<Int(Int32.max)).contains(profiles[index].configurationRevision) else { return nil }
        return (index, profiles[index].configurationRevision + 1)
    }

    // MARK: - Persistence

    private func persist() {
        // A malformed existing authority is not an empty store. Never replace it from a cached
        // list, including through unrelated add/delete/activation paths that serialize the list.
        let hasV2 = ExportProfilePersistence.hasEnvelope(in: userDefaults)
        let key = hasV2 ? Key.listV2 : Key.list
        if userDefaults.object(forKey: key) != nil {
            guard let data = userDefaults.data(forKey: key),
                  ExportProfilePersistence.decode(data, envelope: hasV2) != nil else { return }
        }
        guard !persistenceUnavailable else { return }
        guard let encoded = try? ExportProfilePersistence.encode(
            profiles, opaque: opaqueProfileRecords, envelope: true
        ) else { return }
        userDefaults.set(encoded, forKey: Key.listV2)
        unknownProfileRecordCount = opaqueProfileRecords.count
        userDefaults.set(
            activeProfileID?.uuidString,
            forKey: Key.activeProfileIDV2
        )
    }

    private func decodedContainsProfile(withID id: UUID, in list: [ExportProfile]) -> Bool {
        list.contains { $0.id == id }
    }
}
