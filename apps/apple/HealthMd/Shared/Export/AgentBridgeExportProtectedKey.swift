import CryptoKit
import Foundation
import HealthMdConnectionCore
import LocalAuthentication
import Security

/// Loads only the independently provisioned native-source issuer integrity key. No credential
/// writer, alias selection, enrollment, authentication UI, cache or fallback is exposed here.
nonisolated struct AgentBridgeExportProtectedKey: AgentBridgeExportProtectedKeyReading, Sendable {
    typealias CopyMatching = @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    private let copyMatching: CopyMatching
    // Dedicated purpose/version, independent of channel/trust/cursor/API/provider/wake secrets.
    // A future native provisioning flow must use THIS identity and protection, never another key.
    private static let service = "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority"
    private static let account = "integrity-key-v1"

    /// Injection is solely at the Security lookup boundary; production calls the real native SDK.
    init(copyMatching: @escaping CopyMatching = { SecItemCopyMatching($0, $1) }) {
        self.copyMatching = copyMatching
    }

    func loadExistingExportAuthorityKey() throws -> SymmetricKey? {
        // A fresh prompt-suppressed context cannot reuse an earlier authentication success.
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
            // Do not fall back to the legacy macOS login Keychain, which lacks these protections.
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            // A bounded second EXACT-identity match detects ambiguity across entitled groups.
            // No caller-selected group or unrestricted credential enumeration is performed.
            kSecMatchLimit as String: 2
        ]
        var result: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound && result == nil { return nil }
        guard status == errSecSuccess,
              let records = result as? [Any], records.count == 1,
              let record = records[0] as? [String: Any],
              record[kSecClass as String] as? String == kSecClassGenericPassword as String,
              record[kSecAttrService as String] as? String == Self.service,
              record[kSecAttrAccount as String] as? String == Self.account,
              record[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
              Self.isExplicitFalse(record[kSecAttrSynchronizable as String]),
              record[kSecAttrIsNegative as String] == nil || Self.isExplicitFalse(record[kSecAttrIsNegative as String]),
              let data = record[kSecValueData as String] as? Data, data.count == 32 else {
            throw AgentBridgeValidationError.permissionRequired
        }
        return SymmetricKey(data: data)
    }

    // NSNumber(0)/strings/missing metadata are not evidence of nonsynchronizable protection.
    private static func isExplicitFalse(_ value: Any?) -> Bool {
        guard let value, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else { return false }
        return CFEqual(value as CFTypeRef, kCFBooleanFalse)
    }
}
