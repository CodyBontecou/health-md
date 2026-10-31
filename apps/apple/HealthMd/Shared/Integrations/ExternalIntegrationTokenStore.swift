import Foundation

protocol ExternalIntegrationSecureStoring: AnyObject {
    func readString(key: String) -> String?
    func readStringOrThrow(key: String) throws -> String?
    func writeStringOrThrow(key: String, value: String) throws
    func removeOrThrow(key: String) throws
}

extension ExternalIntegrationSecureStoring {
    func readStringOrThrow(key: String) throws -> String? {
        readString(key: key)
    }
}

extension SystemKeychainStore: ExternalIntegrationSecureStoring {}

enum ExternalIntegrationTokenStoreError: LocalizedError, Equatable {
    case persistenceVerificationFailed
    case connectionChanged

    var errorDescription: String? {
        switch self {
        case .persistenceVerificationFailed:
            "Health.md could not verify the provider credentials in Keychain."
        case .connectionChanged:
            "The provider connection changed. Start a new export."
        }
    }
}

@MainActor
final class ExternalIntegrationTokenStore {
    private enum Constants {
        static let accountListKey = "externalIntegrations.connectedProviders"
        static let tokenKeyPrefix = "externalIntegrations.token."
        static let accountKeyPrefix = "externalIntegrations.account."
    }

    /// Remains a flat token JSON object so older token decoders ignore the
    /// private binding field. Credentials and their generation change together.
    private struct Credentials: Codable {
        let token: ExternalIntegrationToken
        let connectionID: UUID?
        enum CodingKeys: String, CodingKey { case connectionID = "_healthmd_connection_id" }
        init(token: ExternalIntegrationToken, connectionID: UUID?) {
            self.token = token
            self.connectionID = connectionID
        }
        init(from decoder: Decoder) throws {
            token = try ExternalIntegrationToken(from: decoder)
            connectionID = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(UUID.self, forKey: .connectionID)
        }
        func encode(to encoder: Encoder) throws {
            try token.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(connectionID, forKey: .connectionID)
        }
    }
    private struct CachedCredentials {
        let encoded: String
        let credentials: Credentials
    }
    private var credentialCache: [ExternalIntegrationProvider: CachedCredentials] = [:]
    private(set) var accounts: [ExternalIntegrationProvider: ExternalIntegrationAccount] = [:]
    private let keychain: any ExternalIntegrationSecureStoring
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: any ExternalIntegrationSecureStoring = SystemKeychainStore(), userDefaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.userDefaults = userDefaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadAccounts()
    }

    var connectedProviders: Set<ExternalIntegrationProvider> {
        Set((userDefaults.stringArray(forKey: Constants.accountListKey) ?? []).compactMap(ExternalIntegrationProvider.init(rawValue:)))
    }

    func connectionID(for provider: ExternalIntegrationProvider) -> UUID? {
        guard connectedProviders.contains(provider), var account = readAccount(provider),
              var credentials = readCredentials(provider)?.credentials else { return nil }
        if account.connectionID == nil && credentials.connectionID == nil {
            guard migrateLegacy(provider: provider, account: account, credentials: credentials),
                  let currentAccount = readAccount(provider),
                  let currentCredentials = readCredentials(provider)?.credentials else { return nil }
            account = currentAccount
            credentials = currentCredentials
        }
        guard let id = credentials.connectionID, account.connectionID == id else { return nil }
        accounts[provider] = account
        return id
    }

    func token(for provider: ExternalIntegrationProvider) -> ExternalIntegrationToken? {
        // Recheck the authoritative value; memoize decoding only while it is
        // byte-identical. Another store may have rotated the same connection.
        readCredentials(provider)?.credentials.token
    }

    func save(token: ExternalIntegrationToken, provider: ExternalIntegrationProvider, connectedAt: Date = Date()) throws {
        let previous = keychain.readString(key: tokenKey(for: provider))
        let id = UUID()
        try persist(credentials: Credentials(token: token, connectionID: id), provider: provider)
        let account = ExternalIntegrationAccount(provider: provider, connectedAt: connectedAt,
            lastSuccessfulExportAt: nil, scope: token.scope, providerUserID: token.providerUserID, connectionID: id)
        do { try persist(account: account) }
        catch {
            // A failed replacement must invalidate accepted old captures even
            // when its old credential bytes can be restored. Leave an unmatched
            // generation unavailable until account binding can be repaired.
            if let previous {
                do {
                    if let data = previous.data(using: .utf8), let old = try? decoder.decode(Credentials.self, from: data) {
                        try persist(credentials: Credentials(token: old.token, connectionID: UUID()), provider: provider)
                    } else {
                        try keychain.writeStringOrThrow(key: tokenKey(for: provider), value: previous)
                        credentialCache.removeValue(forKey: provider)
                    }
                } catch { credentialCache.removeValue(forKey: provider) }
            } else {
                try? keychain.removeOrThrow(key: tokenKey(for: provider))
                credentialCache.removeValue(forKey: provider)
            }
            throw error
        }
        accounts[provider] = account
        setConnected(provider, true)
    }

    /// Rotation retains the accepted connection. Metadata repair is secondary
    /// once the upstream provider has invalidated the previous credential pair.
    func saveRotatedToken(_ token: ExternalIntegrationToken, provider: ExternalIntegrationProvider,
                          replacingConnection id: UUID) throws {
        guard connectionID(for: provider) == id, var account = readAccount(provider) else {
            throw ExternalIntegrationTokenStoreError.connectionChanged
        }
        try persist(credentials: Credentials(token: token, connectionID: id), provider: provider)
        account.scope = token.scope
        account.providerUserID = token.providerUserID
        if (try? persist(account: account)) != nil { accounts[provider] = account }
    }

    func markSuccessfulExport(provider: ExternalIntegrationProvider, at date: Date = Date()) {
        guard connectionID(for: provider) != nil, var account = readAccount(provider) else { return }
        account.lastSuccessfulExportAt = date
        guard (try? persist(account: account)) != nil else { return }
        accounts[provider] = account
    }

    func disconnect(provider: ExternalIntegrationProvider, expectedConnectionID: UUID? = nil) throws {
        if let expectedConnectionID, connectionID(for: provider) != expectedConnectionID {
            throw ExternalIntegrationTokenStoreError.connectionChanged
        }
        var firstError: Error?
        do { try keychain.removeOrThrow(key: tokenKey(for: provider)) } catch { firstError = error }
        do { try keychain.removeOrThrow(key: accountKey(for: provider)) } catch { if firstError == nil { firstError = error } }
        credentialCache.removeValue(forKey: provider)
        accounts.removeValue(forKey: provider)
        setConnected(provider, false)
        if let firstError { throw firstError }
    }

    func disconnectAll() {
        for provider in ExternalIntegrationProvider.allCases { try? disconnect(provider: provider) }
    }

    private func loadAccounts() {
        for provider in connectedProviders {
            guard let account = readAccount(provider), token(for: provider) != nil else { continue }
            accounts[provider] = account
            _ = connectionID(for: provider)
        }
        // An unreadable Keychain item is not evidence of disconnection. Never
        // erase the connected-provider inventory merely while loading it.
    }

    private func readAccount(_ provider: ExternalIntegrationProvider) -> ExternalIntegrationAccount? {
        guard let encoded = keychain.readString(key: accountKey(for: provider)), let data = encoded.data(using: .utf8),
              let account = try? decoder.decode(ExternalIntegrationAccount.self, from: data), account.provider == provider else { return nil }
        return account
    }

    private func readCredentials(_ provider: ExternalIntegrationProvider) -> CachedCredentials? {
        guard let encoded = keychain.readString(key: tokenKey(for: provider)) else {
            credentialCache.removeValue(forKey: provider)
            return nil
        }
        if let cached = credentialCache[provider], cached.encoded == encoded { return cached }
        guard let data = encoded.data(using: .utf8), let credentials = try? decoder.decode(Credentials.self, from: data) else {
            credentialCache.removeValue(forKey: provider)
            return nil
        }
        let cached = CachedCredentials(encoded: encoded, credentials: credentials)
        credentialCache[provider] = cached
        return cached
    }

    private func migrateLegacy(provider: ExternalIntegrationProvider, account: ExternalIntegrationAccount, credentials: Credentials) -> Bool {
        guard let previous = keychain.readString(key: tokenKey(for: provider)) else { return false }
        var migrated = account
        migrated.connectionID = UUID()
        do {
            try persist(credentials: Credentials(token: credentials.token, connectionID: migrated.connectionID), provider: provider)
            try persist(account: migrated)
            accounts[provider] = migrated
            return true
        } catch {
            try? keychain.writeStringOrThrow(key: tokenKey(for: provider), value: previous)
            credentialCache.removeValue(forKey: provider)
            return false
        }
    }

    private func persist(credentials: Credentials, provider: ExternalIntegrationProvider) throws {
        let data = try encoder.encode(credentials)
        guard let string = String(data: data, encoding: .utf8) else { throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed }
        try keychain.writeStringOrThrow(key: tokenKey(for: provider), value: string)
        guard keychain.readString(key: tokenKey(for: provider)) == string else {
            credentialCache.removeValue(forKey: provider)
            throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed
        }
        credentialCache[provider] = CachedCredentials(encoded: string, credentials: credentials)
    }

    private func persist(account: ExternalIntegrationAccount) throws {
        let data = try encoder.encode(account)
        guard let string = String(data: data, encoding: .utf8) else { throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed }
        try keychain.writeStringOrThrow(key: accountKey(for: account.provider), value: string)
        guard keychain.readString(key: accountKey(for: account.provider)) == string else { throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed }
    }

    private func setConnected(_ provider: ExternalIntegrationProvider, _ connected: Bool) {
        // Preserve entries owned by newer builds and other store instances.
        var ids = Set(userDefaults.stringArray(forKey: Constants.accountListKey) ?? [])
        if connected { ids.insert(provider.rawValue) } else { ids.remove(provider.rawValue) }
        userDefaults.set(ids.sorted(), forKey: Constants.accountListKey)
    }
    private func tokenKey(for provider: ExternalIntegrationProvider) -> String { Constants.tokenKeyPrefix + provider.rawValue }
    private func accountKey(for provider: ExternalIntegrationProvider) -> String { Constants.accountKeyPrefix + provider.rawValue }
}
