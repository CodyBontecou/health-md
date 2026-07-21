#if os(macOS)
import CryptoKit
import Foundation
import Security

/// Supplies the data-encryption key for the local Mac query-context store.
/// Key bytes must never be persisted beside encrypted health context.
nonisolated protocol HealthContextEncryptionKeyProviding: Sendable {
    func existingKeyData() throws -> Data?
    func existingOrCreateKeyData() throws -> Data
    func removeKey() throws
}

nonisolated enum HealthContextEncryptionKeyProviderError: LocalizedError, Equatable {
    case invalidKeyLength(Int)
    case randomGenerationFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKeyLength:
            return "The Health.md query-context encryption key is invalid."
        case .randomGenerationFailed:
            return "Health.md could not generate a query-context encryption key."
        case .keychainReadFailed:
            return "Health.md could not read the query-context encryption key from Keychain."
        case .keychainWriteFailed:
            return "Health.md could not save the query-context encryption key in Keychain."
        case .keychainDeleteFailed:
            return "Health.md could not remove the query-context encryption key from Keychain."
        }
    }
}

/// A 256-bit, this-device-only Keychain key provider for encrypted query context.
nonisolated final class KeychainHealthContextEncryptionKeyProvider: HealthContextEncryptionKeyProviding, @unchecked Sendable {
    static let keyLength = 32

    private let service: String
    private let account: String

    init(
        service: String = "com.codybontecou.obsidianhealth.query-context",
        account: String = "aes-gcm-key-v1"
    ) {
        self.service = service
        self.account = account
    }

    func existingKeyData() throws -> Data? {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw HealthContextEncryptionKeyProviderError.keychainReadFailed(status)
        }
        try Self.validate(data)
        return data
    }

    func existingOrCreateKeyData() throws -> Data {
        if let existing = try existingKeyData() { return existing }

        var generated = Data(count: Self.keyLength)
        let randomStatus = generated.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, Self.keyLength, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw HealthContextEncryptionKeyProviderError.randomGenerationFailed(randomStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = generated
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            guard let winner = try existingKeyData() else {
                throw HealthContextEncryptionKeyProviderError.keychainWriteFailed(addStatus)
            }
            return winner
        }
        guard addStatus == errSecSuccess else {
            throw HealthContextEncryptionKeyProviderError.keychainWriteFailed(addStatus)
        }
        return generated
    }

    func removeKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HealthContextEncryptionKeyProviderError.keychainDeleteFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func validate(_ data: Data) throws {
        guard data.count == keyLength else {
            throw HealthContextEncryptionKeyProviderError.invalidKeyLength(data.count)
        }
    }
}

/// Injectable test seam. Production code uses `KeychainHealthContextEncryptionKeyProvider`.
nonisolated final class InMemoryHealthContextEncryptionKeyProvider: HealthContextEncryptionKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var keyData: Data?

    init(keyData: Data? = nil) {
        self.keyData = keyData
    }

    func existingKeyData() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if let keyData { try Self.validate(keyData) }
        return keyData
    }

    func existingOrCreateKeyData() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let keyData {
            try Self.validate(keyData)
            return keyData
        }
        let generated = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        keyData = generated
        return generated
    }

    func replaceKeyData(_ keyData: Data?) {
        lock.lock()
        self.keyData = keyData
        lock.unlock()
    }

    func removeKey() throws {
        replaceKeyData(nil)
    }

    private static func validate(_ data: Data) throws {
        guard data.count == KeychainHealthContextEncryptionKeyProvider.keyLength else {
            throw HealthContextEncryptionKeyProviderError.invalidKeyLength(data.count)
        }
    }
}
#endif
