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
/// scheduling, and device timezone. Identical profile settings must produce
/// byte-for-byte identical export output; profiles change which request
/// produces files, never the public export schema.
struct ExportProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var settings: ExportSettingsSnapshot
    var target: ExportTargetSelection
    var createdAt: Date
    var updatedAt: Date
    /// True only for the profile synthesized from legacy live settings during
    /// first-run migration. It marks the row users expect to keep editing as
    /// their "main" configuration and is not part of export output.
    var isMigrationDefault: Bool

    init(
        id: UUID = UUID(),
        name: String,
        settings: ExportSettingsSnapshot,
        target: ExportTargetSelection,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isMigrationDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.target = target
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isMigrationDefault = isMigrationDefault
    }
}

/// Observable, UserDefaults-backed store for the ordered export profile list.
///
/// Persistence follows the `ExportSchedule` pattern: the whole list is stored
/// as one JSON payload. An empty or undecodable payload means "legacy mode" —
/// no profiles exist and callers keep using live `AdvancedExportSettings` —
/// so corruption or a partial decode can never change export behavior, only
/// lose saved profiles that the user can re-create.
///
/// Use from the main thread, matching `AdvancedExportSettings`.
final class ExportProfileStore: ObservableObject {
    @Published private(set) var profiles: [ExportProfile]
    @Published private(set) var activeProfileID: UUID?

    private let userDefaults: UserDefaults
    private let now: () -> Date

    private enum Key {
        static let list = "exportProfiles.list"
        static let activeProfileID = "exportProfiles.activeProfileID"
    }

    static let defaultProfileName = String(localized: "Default", comment: "Name of the export profile migrated from existing settings")

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.userDefaults = userDefaults
        self.now = now

        if let data = userDefaults.data(forKey: Key.list),
           let decoded = try? JSONDecoder().decode([ExportProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = []
        }

        if let idString = userDefaults.string(forKey: Key.activeProfileID),
           let id = UUID(uuidString: idString),
           decodedContainsProfile(withID: id, in: profiles) {
            activeProfileID = id
        } else {
            activeProfileID = nil
        }
    }

    // MARK: - Derived state

    /// True when at least one profile exists. Callers without profile support
    /// keep the legacy single-settings behavior while this is false.
    var hasProfiles: Bool { !profiles.isEmpty }

    /// The profile used by manual exports, or nil in legacy mode (no profiles,
    /// or the persisted active id dangles after external data loss).
    var activeProfile: ExportProfile? {
        profile(id: activeProfileID)
    }

    func profile(id: UUID?) -> ExportProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    /// Case-insensitive, whitespace-trimmed name lookup used by automation
    /// surfaces that reference profiles by display name.
    func profile(named name: String) -> ExportProfile? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return profiles.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    // MARK: - Migration

    /// Creates the initial "Default" profile from current live settings on
    /// first use. Returns true when a profile was created; subsequent calls
    /// are no-ops so callers can invoke this on every launch.
    @discardableResult
    func migrateDefaultProfileIfNeeded(
        settings: ExportSettingsSnapshot,
        target: ExportTargetSelection
    ) -> Bool {
        guard profiles.isEmpty else { return false }

        let profile = ExportProfile(
            name: uniquifiedName(Self.defaultProfileName),
            settings: settings,
            target: target,
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
        target: ExportTargetSelection
    ) -> ExportProfile {
        let profile = ExportProfile(
            name: uniquifiedName(name),
            settings: settings,
            target: target,
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
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].settings = settings
        profiles[index].updatedAt = now()
        persist()
        return true
    }

    /// Replaces the export target binding and touches `updatedAt`.
    /// Returns false when the id is unknown.
    @discardableResult
    func updateTarget(id: UUID, target: ExportTargetSelection) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].target = target
        profiles[index].updatedAt = now()
        persist()
        return true
    }

    /// Renames a profile, trimming whitespace and uniquifying against the
    /// remaining profiles. Returns the stored name, or nil when the id is
    /// unknown or the trimmed name is empty.
    @discardableResult
    func rename(id: UUID, to rawName: String) -> String? {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let others = profiles.filter { $0.id != id }
        let unique = Self.uniquified(trimmed, against: others.map(\.name))
        profiles[index].name = unique
        profiles[index].updatedAt = now()
        persist()
        return unique
    }

    /// Duplicates a profile under a fresh id with a name like "Weekly 2".
    /// Returns nil when the source id is unknown.
    @discardableResult
    func duplicate(id: UUID) -> ExportProfile? {
        guard let source = profile(id: id) else { return nil }
        return add(
            name: source.name,
            settings: source.settings,
            target: source.target
        )
    }

    /// Deletes a profile. Deleting the active profile activates the first
    /// remaining profile, or returns the store to legacy mode when the list
    /// becomes empty. Deleting the migration default is allowed.
    func delete(id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)

        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        persist()
    }

    /// Selects the profile manual exports use. Returns false for unknown ids
    /// or while in legacy mode.
    @discardableResult
    func activate(id: UUID) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        activeProfileID = id
        persist()
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

    // MARK: - Persistence

    private func persist() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            userDefaults.set(encoded, forKey: Key.list)
        }
        userDefaults.set(
            activeProfileID?.uuidString,
            forKey: Key.activeProfileID
        )
    }

    private func decodedContainsProfile(withID id: UUID, in list: [ExportProfile]) -> Bool {
        list.contains { $0.id == id }
    }
}
