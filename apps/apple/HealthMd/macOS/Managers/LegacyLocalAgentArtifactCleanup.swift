#if os(macOS)
import Foundation
import Security

/// One-time removal of the local access-control artifacts retired with direct,
/// unauthenticated loopback queries. This deliberately does not inspect query
/// context storage, export state, manual-IP secrets, or provider credentials.
nonisolated enum LegacyLocalAgentArtifactCleanup {
    static let migrationMarkerKey = "healthmd.legacy-local-agent-artifacts-removed.v1"
    static let legacyCredentialService = "com.codybontecou.obsidianhealth.agent-credentials"
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
            defaults: defaults,
            deleteLegacyCredentials: deleteLegacyCredentials
        )
    }

    @discardableResult
    static func performIfNeeded(
        healthMdRoot: URL,
        fileManager: FileManager,
        defaults: UserDefaults,
        deleteLegacyCredentials: () -> Bool
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

        guard deleteLegacyCredentials() else { return false }
        defaults.set(true, forKey: migrationMarkerKey)
        return true
    }

    private static func deleteLegacyCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyCredentialService
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
#endif
