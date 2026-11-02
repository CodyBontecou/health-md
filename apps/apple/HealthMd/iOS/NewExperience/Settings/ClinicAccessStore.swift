import Combine
import Foundation

/// Local-only state behind ClinicAccessG, shown only when `PracticeFeaturePolicy`
/// is enabled (never in production builds today).
///
/// There is no Health.md Practice client in the Apple app, so this store makes no
/// network calls and holds no clinical data: only the user's own choices on this
/// device and an optional upload token, which lives in Keychain. Refreshing re-reads
/// that local state; disconnecting erases it. Purchases and exported files are untouched.
@MainActor
final class ClinicAccessStore: ObservableObject {
    // Keep deallocation on the releasing thread, matching the settings-store convention.
    nonisolated deinit {}

    enum Key {
        static let clinicName = "practice.clinicAccess.clinicName"
        static let sharing = "practice.clinicAccess.sharingEnabled"
        /// Retired: the switch became a choice of automation.
        static let usesClinicDestination = "practice.clinicAccess.usesClinicDestination"
        static let clinicDestinationProfileID = "practice.clinicAccess.clinicDestinationProfileID"
        static let lastRefreshedAt = "practice.clinicAccess.lastRefreshedAt"
        static let uploadToken = "practice.clinicAccess.uploadToken"
    }

    /// Set by a future invitation flow; nil means no clinic is connected on this device.
    @Published private(set) var clinicName: String?
    @Published private(set) var isSharingEnabled = false
    /// The automation that sends to the clinic destination; nil when none does.
    @Published private(set) var clinicDestinationProfileID: UUID?
    var usesClinicDestination: Bool { clinicDestinationProfileID != nil }
    @Published private(set) var hasUploadToken = false
    @Published private(set) var lastRefreshedAt: Date?

    private let defaults: UserDefaults
    private let keychain: any KeychainStoring
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        keychain: (any KeychainStoring)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.keychain = keychain ?? SystemKeychainStore()
        self.now = now
        load()
    }

    /// Turning sharing off stops future uploads only; it never reaches the clinic.
    func setSharingEnabled(_ isOn: Bool) {
        isSharingEnabled = isOn
        defaults.set(isOn, forKey: Key.sharing)
    }

    /// Chooses which automation uses the clinic destination, or none. Local only.
    func setClinicDestinationProfile(_ profileID: UUID?) {
        clinicDestinationProfileID = profileID
        if let profileID {
            defaults.set(profileID.uuidString, forKey: Key.clinicDestinationProfileID)
        } else {
            defaults.removeObject(forKey: Key.clinicDestinationProfileID)
        }
    }

    /// Saves, or with an empty value removes, the clinic upload token.
    func saveUploadToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.removeOrThrow(key: Key.uploadToken)
        } else {
            try keychain.writeStringOrThrow(key: Key.uploadToken, value: trimmed)
        }
        hasUploadToken = !trimmed.isEmpty
    }

    /// Re-reads local state (for example after another scene changed it) and records when.
    func refresh() {
        load()
        lastRefreshedAt = now()
        defaults.set(lastRefreshedAt, forKey: Key.lastRefreshedAt)
    }

    /// Forgets the clinic on this device: choices, name and the Keychain token.
    func disconnect() throws {
        try keychain.removeOrThrow(key: Key.uploadToken)
        for key in [Key.clinicName, Key.sharing, Key.usesClinicDestination, Key.clinicDestinationProfileID, Key.lastRefreshedAt] {
            defaults.removeObject(forKey: key)
        }
        load()
    }

    private func load() {
        clinicName = defaults.string(forKey: Key.clinicName)
        isSharingEnabled = defaults.bool(forKey: Key.sharing)
        clinicDestinationProfileID = defaults.string(forKey: Key.clinicDestinationProfileID).flatMap(UUID.init(uuidString:))
        lastRefreshedAt = defaults.object(forKey: Key.lastRefreshedAt) as? Date
        hasUploadToken = !(keychain.readString(key: Key.uploadToken) ?? "").isEmpty
    }
}
