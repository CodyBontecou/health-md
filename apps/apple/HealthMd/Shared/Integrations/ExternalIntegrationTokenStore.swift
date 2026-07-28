import Foundation

protocol ExternalIntegrationSecureStoring: AnyObject {
    func readString(key: String) -> String?
    func writeStringOrThrow(key: String, value: String) throws
    func removeOrThrow(key: String) throws
}

extension SystemKeychainStore: ExternalIntegrationSecureStoring {}

enum ExternalIntegrationTokenStoreError: LocalizedError, Equatable {
    case persistenceVerificationFailed

    var errorDescription: String? {
        "Health.md could not verify the provider credentials in Keychain."
    }
}

final class ExternalIntegrationTokenStore {
    private enum Constants {
        static let accountListKey = "externalIntegrations.connectedProviders"
        static let tokenKeyPrefix = "externalIntegrations.token."
        static let accountKeyPrefix = "externalIntegrations.account."
    }

    private(set) var accounts: [ExternalIntegrationProvider: ExternalIntegrationAccount] = [:]
    /// Process-local credential snapshots avoid repeated Keychain decoding for
    /// every provider/day in a multi-day export. Mutations still verify the
    /// authoritative Keychain value before updating this cache.
    private var tokenCache: [ExternalIntegrationProvider: ExternalIntegrationToken] = [:]

    private let keychain: any ExternalIntegrationSecureStoring
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        keychain: any ExternalIntegrationSecureStoring = SystemKeychainStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadAccounts()
    }

    func token(for provider: ExternalIntegrationProvider) -> ExternalIntegrationToken? {
        if let cached = tokenCache[provider] { return cached }
        guard let encoded = keychain.readString(key: tokenKey(for: provider)),
              let data = encoded.data(using: .utf8),
              let token = try? decoder.decode(ExternalIntegrationToken.self, from: data) else {
            return nil
        }
        tokenCache[provider] = token
        return token
    }

    func save(
        token: ExternalIntegrationToken,
        provider: ExternalIntegrationProvider,
        connectedAt: Date = Date()
    ) throws {
        let previousToken = keychain.readString(key: tokenKey(for: provider))
        try persist(token: token, provider: provider)

        let account = updatedAccount(for: provider, token: token, connectedAt: connectedAt)
        do {
            try persist(account: account)
        } catch {
            // Initial connection must not leave a hidden token when no account
            // row can be shown. Restore any prior token or remove the new one.
            if let previousToken {
                do {
                    try keychain.writeStringOrThrow(
                        key: tokenKey(for: provider),
                        value: previousToken
                    )
                    guard keychain.readString(key: tokenKey(for: provider)) == previousToken else {
                        throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed
                    }
                    if let data = previousToken.data(using: .utf8),
                       let restored = try? decoder.decode(ExternalIntegrationToken.self, from: data) {
                        tokenCache[provider] = restored
                    } else {
                        tokenCache.removeValue(forKey: provider)
                    }
                } catch {
                    // The attempted new token may still be authoritative when
                    // rollback fails. Never cache the old token unless its
                    // restoration was verified against Keychain.
                    tokenCache.removeValue(forKey: provider)
                }
            } else {
                try? keychain.removeOrThrow(key: tokenKey(for: provider))
                tokenCache.removeValue(forKey: provider)
            }
            throw error
        }
        accounts[provider] = account
        persistConnectedProviderList()
    }

    /// Persists WHOOP's newly rotated credential pair as the authoritative
    /// result. Account metadata is secondary: a failure there must not discard
    /// a successfully stored pair after WHOOP invalidated the old one.
    func saveRotatedToken(
        _ token: ExternalIntegrationToken,
        provider: ExternalIntegrationProvider
    ) throws {
        try persist(token: token, provider: provider)
        let account = updatedAccount(for: provider, token: token, connectedAt: Date())
        if (try? persist(account: account)) != nil {
            accounts[provider] = account
            persistConnectedProviderList()
        }
    }

    func markSuccessfulExport(provider: ExternalIntegrationProvider, at date: Date = Date()) {
        guard var account = accounts[provider] else { return }
        account.lastSuccessfulExportAt = date
        guard (try? persist(account: account)) != nil else { return }
        accounts[provider] = account
    }

    func disconnect(provider: ExternalIntegrationProvider) throws {
        var firstError: Error?
        do {
            try keychain.removeOrThrow(key: tokenKey(for: provider))
        } catch {
            firstError = error
        }
        do {
            try keychain.removeOrThrow(key: accountKey(for: provider))
        } catch {
            if firstError == nil { firstError = error }
        }
        tokenCache.removeValue(forKey: provider)
        accounts.removeValue(forKey: provider)
        persistConnectedProviderList()
        if let firstError { throw firstError }
    }

    func disconnectAll() {
        for provider in ExternalIntegrationProvider.allCases {
            try? disconnect(provider: provider)
        }
    }

    private func loadAccounts() {
        let providerIDs = userDefaults.stringArray(forKey: Constants.accountListKey) ?? []
        var loaded: [ExternalIntegrationProvider: ExternalIntegrationAccount] = [:]

        for providerID in providerIDs {
            guard let provider = ExternalIntegrationProvider(rawValue: providerID),
                  let encoded = keychain.readString(key: accountKey(for: provider)),
                  let data = encoded.data(using: .utf8),
                  let account = try? decoder.decode(ExternalIntegrationAccount.self, from: data),
                  token(for: provider) != nil else { continue }
            loaded[provider] = account
        }
        accounts = loaded
        persistConnectedProviderList()
    }

    private func updatedAccount(
        for provider: ExternalIntegrationProvider,
        token: ExternalIntegrationToken,
        connectedAt: Date
    ) -> ExternalIntegrationAccount {
        var account = accounts[provider] ?? ExternalIntegrationAccount(
            provider: provider,
            connectedAt: connectedAt,
            lastSuccessfulExportAt: nil,
            scope: token.scope,
            providerUserID: token.providerUserID
        )
        account.scope = token.scope
        account.providerUserID = token.providerUserID
        return account
    }

    private func persist(token: ExternalIntegrationToken, provider: ExternalIntegrationProvider) throws {
        let tokenData = try encoder.encode(token)
        guard let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed
        }
        try keychain.writeStringOrThrow(key: tokenKey(for: provider), value: tokenString)
        guard keychain.readString(key: tokenKey(for: provider)) == tokenString else {
            throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed
        }
        tokenCache[provider] = token
    }

    private func persist(account: ExternalIntegrationAccount) throws {
        let data = try encoder.encode(account)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed
        }
        try keychain.writeStringOrThrow(key: accountKey(for: account.provider), value: string)
        guard keychain.readString(key: accountKey(for: account.provider)) == string else {
            throw ExternalIntegrationTokenStoreError.persistenceVerificationFailed
        }
    }

    private func persistConnectedProviderList() {
        userDefaults.set(accounts.keys.map(\.rawValue).sorted(), forKey: Constants.accountListKey)
    }

    private func tokenKey(for provider: ExternalIntegrationProvider) -> String {
        Constants.tokenKeyPrefix + provider.rawValue
    }

    private func accountKey(for provider: ExternalIntegrationProvider) -> String {
        Constants.accountKeyPrefix + provider.rawValue
    }
}
