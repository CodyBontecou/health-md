import Foundation

/// Read-only history lease input, NOT profile execution authority or a revision.
/// A fresh store applies the existing canonical decode/valid-ID rules without
/// mutating a SwiftUI-observed instance. A cached raw activeProfileID is unsafe
/// after another store switches/removes the persisted identity. This final read
/// does not prove external A→B→A history or cross-process atomicity.
@MainActor
enum HealthHistoryCanonicalProfileIdentity {
    static func read(userDefaults: UserDefaults = .standard) -> UUID? {
        let snapshot = ExportProfileStore(userDefaults: userDefaults)
        return snapshot.activeProfile?.id
    }
}
