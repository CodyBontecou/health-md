#if os(macOS)
import Foundation

/// One-time removal of the local file artifacts retired with direct,
/// unauthenticated loopback queries. This deliberately does not access Keychain
/// or inspect query context storage, export state, or provider credentials.
nonisolated enum LegacyLocalAgentArtifactCleanup {
    static let migrationMarkerKey = "healthmd.legacy-local-agent-artifacts-removed.v1"
    static let legacyDirectoryNames = ["AgentAccess", "HealthContextProfiles"]

    static func runIfNeeded(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let healthMdRoot = applicationSupport
            .appendingPathComponent("Health.md", isDirectory: true)
        _ = performIfNeeded(
            healthMdRoot: healthMdRoot,
            fileManager: fileManager,
            defaults: defaults
        )
    }

    @discardableResult
    static func performIfNeeded(
        healthMdRoot: URL,
        fileManager: FileManager,
        defaults: UserDefaults
    ) -> Bool {
        guard !defaults.bool(forKey: migrationMarkerKey) else { return true }

        do {
            for name in legacyDirectoryNames {
                let url = healthMdRoot.appendingPathComponent(name, isDirectory: true)
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        } catch {
            return false
        }

        defaults.set(true, forKey: migrationMarkerKey)
        return true
    }
}
#endif
