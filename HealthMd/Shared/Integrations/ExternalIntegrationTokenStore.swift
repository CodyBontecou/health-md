import Foundation

final class ExternalIntegrationTokenStore {
    private enum Constants {
        static let accountListKey = "externalIntegrations.connectedProviders"
        static let tokenKeyPrefix = "externalIntegrations.token."
        static let accountKeyPrefix = "externalIntegrations.account."
    }

    private(set) var accounts: [ExternalIntegrationProvider: ExternalIntegrationAccount] = [:]

    private let keychain: SystemKeychainStore
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        keychain: SystemKeychainStore = SystemKeychainStore(),
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
        guard let encoded = keychain.readString(key: tokenKey(for: provider)),
              let data = encoded.data(using: .utf8) else { return nil }
        return try? decoder.decode(ExternalIntegrationToken.self, from: data)
    }

    func save(
        token: ExternalIntegrationToken,
        provider: ExternalIntegrationProvider,
        connectedAt: Date = Date()
    ) {
        guard let tokenData = try? encoder.encode(token),
              let tokenString = String(data: tokenData, encoding: .utf8) else { return }

        keychain.writeString(key: tokenKey(for: provider), value: tokenString)

        var account = accounts[provider] ?? ExternalIntegrationAccount(
            provider: provider,
            connectedAt: connectedAt,
            lastSuccessfulExportAt: nil,
            scope: token.scope,
            providerUserID: token.providerUserID
        )
        account.scope = token.scope
        account.providerUserID = token.providerUserID
        accounts[provider] = account
        persist(account: account)
        persistConnectedProviderList()
    }

    func markSuccessfulExport(provider: ExternalIntegrationProvider, at date: Date = Date()) {
        guard var account = accounts[provider] else { return }
        account.lastSuccessfulExportAt = date
        accounts[provider] = account
        persist(account: account)
    }

    func disconnect(provider: ExternalIntegrationProvider) {
        keychain.remove(key: tokenKey(for: provider))
        keychain.remove(key: accountKey(for: provider))
        accounts.removeValue(forKey: provider)
        persistConnectedProviderList()
    }

    func disconnectAll() {
        for provider in ExternalIntegrationProvider.allCases {
            disconnect(provider: provider)
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

    private func persist(account: ExternalIntegrationAccount) {
        guard let data = try? encoder.encode(account),
              let string = String(data: data, encoding: .utf8) else { return }
        keychain.writeString(key: accountKey(for: account.provider), value: string)
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
