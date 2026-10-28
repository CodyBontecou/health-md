import Foundation

/// Records object lookups and mutations in the supplied synthetic defaults domain.
/// The test exercises actual detached AdvancedExportSettings, including nested mutations.
final class AgentBridgeRequestSettingsDefaultsProbe: UserDefaults, @unchecked Sendable {
    var reads = 0
    var writes = 0

    override func object(forKey defaultName: String) -> Any? {
        reads += 1
        return super.object(forKey: defaultName)
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        writes += 1
        super.removeObject(forKey: defaultName)
    }
}
